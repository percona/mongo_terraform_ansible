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

  # Wait for primary to be elected
  provisioner "local-exec" {
    command = <<-EOT
      retries=30
      success=false
      while [ $retries -gt 0 ]; do
        # Check the replica set status and look for a primary
        primary=$(docker exec -i ${docker_container.cfg[0].name} mongosh --port ${var.configsvr_port} --eval "rs.status().members.filter(m => m.stateStr === 'PRIMARY').length > 0")
        
        if test "$primary" = "true"; then
          echo "Primary has been elected in config server replica set"
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
}

# Check primary elected
resource "null_resource" "check_primary" {
  depends_on = [null_resource.initiate_shard_replset]

  for_each = toset([for i in range(var.shard_count) : tostring(i)]) 

  provisioner "local-exec" {
    command = <<-EOT
      retries=30
      success=false
      while [ $retries -gt 0 ]; do
        # Check the replica set status and look for a primary for the shard
        primary=$(docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh --port ${var.shardsvr_port} --eval "rs.status().members.filter(m => m.stateStr === 'PRIMARY').length > 0")
        
        if test "$primary" = "true"; then
          echo "Primary has been elected in shard ${each.key}"
          success=true
          break
        fi
        
        echo "Waiting for primary to be elected in shard ${each.key}... retries left: $retries"
        retries=$((retries - 1))
        sleep 5
      done

      if test "$success" = "false" ; then
        echo "Primary not elected in shard ${each.key} after maximum retries. Exiting."
        exit 1
      fi
    EOT
  }
}

# Create users
resource "null_resource" "create_users" {
  depends_on = [null_resource.check_primary]

  for_each = toset([for i in range(var.shard_count) : tostring(i)]) 

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
    null_resource.initiate_shard_replset,
    null_resource.change_default_write_concern
  ]
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval '
        ${join(";", [for i in range(var.shard_count) : "sh.addShard(\"${lookup({for label in docker_container.shard[i * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}/${docker_container.shard[i * var.shardsvr_replicas].name}:${var.shardsvr_port}\")"])};
      '
    EOT
  }
}

# Configure PBM Storage
resource "null_resource" "configure_pbm" {
  count = var.enable_pbm ? 1 : 0

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
      cat ${path.module}/pbm-storage.conf.${var.cluster_name} | docker exec -i ${docker_container.pbm_cfg[0].name} pbm config --file=-
    EOT
  }
}

locals {
  pmm_cfg_map = {
    for k, container in docker_container.pmm_cfg :
    container.name => {
      name    = docker_container.cfg[k].hostname
      port    = docker_container.cfg[k].ports[0].internal
      use_auth = true
      collectors = true       
    }
  }

  pmm_arb_map = {
    for k, container in docker_container.pmm_arb :
    container.name => {
      name    = docker_container.arbiter[k].hostname
      port    = docker_container.arbiter[k].ports[0].internal
      use_auth = false
      collectors = false        
    }
  }

pmm_shard_map = {
    for k, container in docker_container.pmm_shard :
    container.name => {
      name    = docker_container.shard[k].hostname
      port    = docker_container.shard[k].ports[0].internal
      use_auth = true
      collectors = true         
    }
  }

pmm_mongos_map = {
    for k, container in docker_container.pmm_mongos :
    container.name => {
      name    = docker_container.mongos[k].hostname
      port    = docker_container.mongos[k].ports[0].internal
      use_auth = true
      collectors = true         
    }
  }    

  all_pmm_containers = merge(local.pmm_cfg_map, local.pmm_arb_map, local.pmm_shard_map, local.pmm_mongos_map)
}

# Register with PMM server
resource "null_resource" "register_pmm_client" {
  depends_on = [
    docker_container.pmm_cfg,
    docker_container.pmm_arb,
    docker_container.pmm_shard,
    docker_container.pmm_mongos,
    docker_container.cfg,
    docker_container.shard,
    docker_container.arbiter,
    docker_container.mongos
  ]
  for_each = local.all_pmm_containers

  provisioner "local-exec" {
    command = <<-EOT
      until docker exec -i ${each.key} \
        pmm-admin config ${each.value.name} \
          container ${each.value.name} \
        --server-url=https://${var.pmm_server_user}:${var.pmm_server_pwd}@${var.pmm_host}:${var.pmm_port} \
        --server-insecure-tls \
        --force; do
          echo "Retrying pmm-admin config for ${each.key}..."
          sleep 1
      done
    EOT
  }
}

# Configure MongoDB collectors
resource "null_resource" "configure_pmm_clients" {
  depends_on = [
    docker_container.pmm_cfg,
    docker_container.pmm_shard,
    docker_container.pmm_arb,
    docker_container.pmm_mongos,
    docker_container.cfg,
    docker_container.shard,
    docker_container.arbiter,
    docker_container.mongos,
    null_resource.create_ycsb_collection
  ]
  for_each = local.all_pmm_containers

  provisioner "local-exec" {
    command = <<-EOT
      until docker exec -i ${each.key} \
        pmm-admin add mongodb \
        --environment=${var.env_tag} \
        --cluster ${var.cluster_name} \
        --host=${each.value.name} \
        --port=${each.value.port} \
        ${each.value.use_auth ? "--username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password}" : ""} \
        --service-name=${each.value.name}-mongodb \
        --tls-skip-verify ${each.value.collectors ? "--enable-all-collectors" : ""}; do
          echo "Retrying pmm-admin add mongodb for ${each.key}..."
          sleep 1
      done
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