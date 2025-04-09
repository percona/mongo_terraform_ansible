# Initialize replica set 
resource "null_resource" "initiate_replset" {
  depends_on = [docker_container.rs]

  # Run rs.initiate()
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.rs[0].name} mongosh --port ${var.replset_port} --eval '
        rs.initiate({
          "_id": "${lookup({for label in docker_container.rs[0].labels : label.label => label.value}, "replsetName", null)}",
          "members": [
            { "_id": 0, "host": "${docker_container.rs[0].name}:${var.replset_port}", "priority": 2 },
            ${join(",", [for i in range(1, var.data_nodes_per_replset) : "{ _id: ${i}, host: \"${docker_container.rs[i].name}:${var.replset_port}\" }"])}
            ${join(",", [for i in range(var.arbiters_per_replset) : ",{ _id: ${var.data_nodes_per_replset + i}, host: \"${docker_container.arbiter[i].name}:${var.arbiter_port}\", arbiterOnly: true }"])}
          ]
        });
      '
    EOT
  }

  # Wait for primary to be elected
  provisioner "local-exec" {
    command = <<-EOT
      retries=30
      success=false
      while [ $retries -gt 0 ]; do
        # Check the replica set status and look for a primary
        primary=$(docker exec -i ${docker_container.rs[0].name} mongosh --port ${var.replset_port} --eval "rs.status().members.filter(m => m.stateStr === 'PRIMARY').length > 0")
        
        if test "$primary" = "true"; then
          echo "Primary has been elected in replica set"
          success=true
          break
        fi
        
        echo "Waiting for primary to be elected... retries left: $retries"
        retries=$((retries - 1))
        sleep 5
      done

      if test "$success" = "false"; then
        echo "Primary not elected after maximum retries. Exiting."
        exit 1
      fi
    EOT
  }

  # Create root user on the rs servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.rs[0].name} mongosh admin --port ${var.replset_port} --eval '
        db.createUser({
          "user": "${var.mongodb_root_user}",
          "pwd": "${var.mongodb_root_password}",
          "roles": [
            { "role": "root", "db": "admin" }
          ]
        });
      '
    EOT
  }

  # Create user for PBM on rs servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.rs[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.replset_port} --eval '
        db.createRole({
          "role": "pbmAnyAction",
          "privileges": [
            { "resource": { "anyResource": true }, "actions": [ "anyAction" ] }
          ],
          roles: []
        });
        db.createUser( {
          "user": "${var.mongodb_pbm_user}",
          "pwd": "${var.mongodb_pbm_password}",
          "roles": [         
            { "db" : "admin", "role" : "readWrite", "collection": "" },
            { "db" : "admin", "role" : "backup" },
            { "db" : "admin", "role" : "clusterMonitor" },
            { "db" : "admin", "role" : "restore" },
            { "db" : "admin", "role" : "pbmAnyAction" } 
          ]
        });
      '
    EOT
  }

  # Create user for PMM on rs servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.rs[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.replset_port} --eval '
        db.createRole({
          role: "explainRole",
          privileges: [{
            "resource": { "db": "", "collection": "" },
            "actions": [ "listIndexes", "listCollections", "dbStats", "dbHash", "collStats", "indexStats", "find" ]
          }, 
          {
            "resource": { "db": "", "collection": "system.profile" },
            "actions": [ "dbStats","indexStats","collStats" ], 
          },
          {
            "resource": { "db": "", "collection": "system.version" },
            "actions": [ "find" ]
          }],
          roles: []
        });
        db.createUser({
          "user": "${var.mongodb_pmm_user}",
          "pwd": "${var.mongodb_pmm_password}",
          "roles": [ 
            { "role": "explainRole", "db": "admin" },
            { "role": "read", "db": "local" },
            { "db" : "admin", "role" : "readWrite", "collection": "" },
            { "db" : "admin", "role" : "backup" },
            { "db" : "admin", "role" : "clusterMonitor" },
            { "db" : "admin", "role" : "restore" },
            { "db" : "admin", "role" : "pbmAnyAction" } 
          ]
        });
      '
    EOT
  }
}

# Set the global write concern to 1. This is needed when using arbiters
resource "null_resource" "change_default_write_concern" {
  count = length(docker_container.arbiter) > 0 ? 1 : 0
  depends_on = [
    null_resource.initiate_replset
  ]
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.rs[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.replset_port} --eval '
        db.adminCommand({
          "setDefaultRWConcern" : 1,
          "defaultWriteConcern" : { "w" : 1 },
          "defaultReadConcern" : { "level" : "local" }
        })
      '
    EOT
  }
}

# Configure PBM
resource "null_resource" "configure_pbm" {
  depends_on = [
    null_resource.initiate_replset,
    docker_container.rs,
    docker_container.pbm_rs
  ]
  provisioner "local-exec" {
    command = <<-EOT
      sleep 5
      cat ${path.module}/pbm-storage.conf.${var.rs_name} | docker exec -i ${docker_container.pbm_rs[0].name} pbm config --file=-
    EOT
  }
}

resource "null_resource" "wait_for_pmm" {
  provisioner "local-exec" {
    command = <<EOT
      until docker exec -i ${docker_container.rs[0].name} curl -k -f https://${var.pmm_host}:${var.pmm_port}/graph/login > /dev/null 2>&1; do      
        echo "Waiting for PMM..."
        sleep 5
      done
    EOT
  }
}

# Configure PMM for rs servers
resource "null_resource" "configure_pmm_client_rs" {
  depends_on = [
    null_resource.initiate_replset,
    docker_container.pmm_rs,
    docker_container.rs,
  ]
  for_each = toset([for i in docker_container.rs : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${var.pmm_host}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password} --host=${each.key} --port=${var.replset_port} --service-name=${each.key}-mongodb --tls-skip-verify --enable-all-collectors
    EOT
  }  
}

# Configure PMM for arbiters
resource "null_resource" "configure_pmm_client_arb" {
  depends_on = [
    null_resource.initiate_replset,
    docker_container.pmm_arb, 
    docker_container.arbiter            
  ]
  for_each = toset([for i in docker_container.arbiter : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${var.pmm_host}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }    
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --host=${each.key} --port=${var.arbiter_port} --service-name=${each.key}-mongodb --tls-skip-verify
    EOT
  }     
}