# Initialize Config server replica set 
resource "null_resource" "initiate_cfg_replset" {
  depends_on = [docker_container.cfg]

  # Run rs.initiate()
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh --port ${var.configsvr_port} --eval '
        rs.initiate({
          "_id": "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}",
          "configsvr": true,
          "members": [
            { "_id": 0, "host": "${docker_container.cfg[0].name}:${var.configsvr_port}", "priority": 2 },
            ${join(",", [for i in range(1, var.configsvr_count) : "{ _id: ${i}, host: \"${docker_container.cfg[i].name}:${var.configsvr_port}\" }"])}
          ]
        });
      '
    EOT
  }

  # Wait for RS to be finish initializing
  provisioner "local-exec" {
    command = "sleep 20"
  }

  # Create root user on the config servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin --port ${var.configsvr_port} --eval '
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

  # Create user for PBM on config servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.configsvr_port} --eval '
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

  # Create user for PMM on config servers
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.configsvr_port} --eval '
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

# Initiate the shards replica sets 
resource "null_resource" "initiate_shard_replset" {
  depends_on = [docker_container.arbiter, docker_container.shard]

  # Initiate the shards replica sets 
  for_each = toset([for i in range(var.shard_count) : tostring(i)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh --port ${var.shardsvr_port} --eval '
        rs.initiate({
          _id: "${lookup({for label in docker_container.shard[each.key * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}",
          members: [
            { _id: 0, host: "${docker_container.shard[each.key * var.shardsvr_replicas].name}:${var.shardsvr_port}", priority: 2 },
            ${join(",", [for i in range(1, var.shardsvr_replicas) : "{ _id: ${i}, host: \"${docker_container.shard[each.key * var.shardsvr_replicas + i].name}:${var.shardsvr_port}\" }"])}
            ${join(",", [for i in range(var.arbiters_per_replset) : ",{ _id: ${var.shardsvr_replicas + i}, host: \"${docker_container.arbiter[each.key * var.arbiters_per_replset + i].name}:${var.shardsvr_port}\", arbiterOnly: true }"])}
          ]
        });
      '
    EOT
  }

  provisioner "local-exec" {
    command = "sleep 20"
  }

  # Create the root user on the shards
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin --port ${var.shardsvr_port} --eval '
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

  # Create user for PBM on the shards
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.shardsvr_port} --eval '
        db.createRole({
          "role": "pbmAnyAction",
          "privileges": [
            { "resource": { "anyResource": true }, "actions": ["anyAction"] }
          ],
          "roles": []
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

  # Create user for PMM on the shards
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.shardsvr_port} --eval '
        db.createRole({
          "role": "explainRole",
          "privileges": [{
            "resource": { "db": "", "collection": "" },
            "actions": ["listIndexes","listCollections","dbStats","dbHash","collStats","indexStats","find"]
          }, 
          {
            "resource": { "db": "", "collection": "system.profile" },
            "actions": ["dbStats","indexStats","collStats"]
          }, 
          {
            "resource": { "db": "", "collection": "system.version" },
            "actions": ["find"]
          }],
          "roles": []
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
    docker_container.mongos,
    null_resource.initiate_cfg_replset,
    null_resource.initiate_shard_replset
  ]
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval '
        db.adminCommand({
          "setDefaultRWConcern" : 1,
          "defaultWriteConcern" : { "w" : 1 },
          "defaultReadConcern" : { "level" : "local" }
        })
      '
    EOT
  }
}

# Add the shards to the cluster
resource "null_resource" "add_shards" {
  depends_on = [
    docker_container.mongos,
    null_resource.initiate_cfg_replset,
    null_resource.initiate_shard_replset
  ]
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval '
        ${join(";", [for i in range(var.shard_count) : "sh.addShard(\"${lookup({for label in docker_container.shard[i * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}/${docker_container.shard[i * var.shardsvr_replicas].name}:${var.shardsvr_port}\")"])};
      '
    EOT
  }
}

# Configure PBM
resource "null_resource" "configure_pbm" {
  depends_on = [
    null_resource.add_shards,
    docker_container.cfg,
    docker_container.shard,
    docker_container.pbm_shard,
    docker_container.pbm_cfg
  ]
  provisioner "local-exec" {
    command = <<-EOT
      sleep 5
      cat pbm-storage.conf | docker exec -i ${docker_container.pbm_cfg[0].name} pbm config --file=-
    EOT
  }
}

# Configure PMM for config servers
resource "null_resource" "configure_pmm_client_cfg" {
  depends_on = [
    docker_container.pmm,
    null_resource.initiate_cfg_replset,
    docker_container.pmm_cfg,
    docker_container.cfg,
  ]
  for_each = toset([for i in docker_container.cfg : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${docker_container.pmm.name}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password} --host=${each.key} --port=${var.configsvr_port} --service-name=${each.key}-mongodb --tls-skip-verify --enable-all-collectors
    EOT
  }  
}

# Configure PMM for shard servers
resource "null_resource" "configure_pmm_client_shards" {
  depends_on = [
    docker_container.pmm,
    null_resource.add_shards,
    null_resource.initiate_shard_replset,
    docker_container.pmm_shard,
    docker_container.shard,
  ]
  for_each = toset([for i in docker_container.shard : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${docker_container.pmm.name}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }  
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password} --host=${each.key} --port=${var.shardsvr_port} --service-name=${each.key}-mongodb --tls-skip-verify --enable-all-collectors
    EOT
  }    
}

# Configure PMM for arbiters
resource "null_resource" "configure_pmm_client_arb" {
  depends_on = [
    docker_container.pmm,
    null_resource.initiate_shard_replset,
    docker_container.pmm_arb, 
    docker_container.arbiter            
  ]
  for_each = toset([for i in docker_container.arbiter : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${docker_container.pmm.name}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }    
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --host=${each.key} --port=${var.shardsvr_port} --service-name=${each.key}-mongodb --tls-skip-verify
    EOT
  }     
}

# Configure PMM for mongos routers
resource "null_resource" "configure_pmm_client_mongos" {
  depends_on = [
    docker_container.pmm,
    null_resource.add_shards,
    docker_container.pmm_mongos, 
    docker_container.mongos            
  ]
  for_each = toset([for i in docker_container.mongos : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${docker_container.pmm.name}:${var.pmm_port} --server-insecure-tls --force 
    EOT
  }    
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password} --host=${each.key} --port=${var.mongos_port} --service-name=${each.key}-mongodb --tls-skip-verify --enable-all-collectors
    EOT
  }    
}

# Create the YCSB collection
resource "null_resource" "create_ycsb_collection" {
  depends_on = [
    null_resource.add_shards
  ]
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval 'sh.enableSharding("ycsb"); sh.shardCollection("ycsb.usertable", { "_id" : "hashed" }, false, { numInitialChunks : 100 });'
    EOT
  }
}