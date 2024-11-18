# Initialize Config server replica set 
resource "null_resource" "initiate_cfg_replset" {
  depends_on = [docker_container.cfg]

  # Run rs.initiate()
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh --port ${var.configsvr_port} --eval '
        rs.initiate({
          _id: "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}",
          configsvr: true,
          members: [
            { _id: 0, host: "${docker_container.cfg[0].name}:${var.configsvr_port}", priority: 2 },
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
          user: "root",
          pwd: "percona",
          roles: [
            {role: "root", db: "admin"}
          ]
        });
      '
    EOT
  }

  # Create user for PBM
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin -u root -p percona --port ${var.configsvr_port} --eval '
        db.createRole({
          role: "pbmAgent",
          privileges: [{
            "resource": { "anyResource": true },
            "actions": ["anyAction"]
          }],
          roles: [
            "backup",
            "restore",
            "clusterAdmin"
          ]
        });
        db.createUser({
          user: "pbm",
          pwd: "percona",
          roles: [ "pbmAgent" ]
        });
      '
    EOT
  }

  # Create user for PMM
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin -u root -p percona --port ${var.configsvr_port} --eval '
        db.createRole({
          role: "explainRole",
          privileges: [{
            "resource": { "db": "", "collection": "" },
            "actions": ["listIndexes","listCollections","dbStats","dbHash","collStats","find"]
          }, 
          {
            "resource": { "db": "", "collection": "system.profile" },
            "actions": ["dbStats","indexStats","collStats"]
          }],
          roles: []
        });
        db.createUser({
          user: "mongodb_exporter",
          pwd: "percona",
          roles: [ 
            { "role": "explainRole", "db": "admin" },
            { "role": "clusterMonitor", "db": "admin" },
            { "role": "read", "db": "local" },
            { "db" : "admin", "role" : "readWrite", "collection": "" },
            { "db" : "admin", "role" : "backup" },
            { "db" : "admin", "role" : "clusterMonitor" },
            { "db" : "admin", "role" : "restore" },
            { "db" : "admin", "role" : "pbmAgent" }    ]
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
          user: "root",
          pwd: "percona",
          roles: [
            {role: "root", db: "admin"}
          ]
        });
      '        
    EOT
  }  

  # Create user for PBM
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin -u root -p percona --port ${var.shardsvr_port} --eval '
        db.createRole({
          role: "pbmAgent",
          privileges: [{
            "resource": { "anyResource": true },
            "actions": ["anyAction"]
          }],
          roles: [
            "backup",
            "restore",
            "clusterAdmin"
          ]
        });
        db.createUser({
          user: "pbm",
          pwd: "percona",
          roles: [ "pbmAgent" ]
        });
      '        
    EOT
  }  

  # Create user for PMM
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin -u root -p percona --port ${var.shardsvr_port} --eval '
        db.createRole({
          role: "explainRole",
          privileges: [{
            "resource": { "db": "", "collection": "" },
            "actions": ["listIndexes","listCollections","dbStats","dbHash","collStats","find"]
          }, 
          {
            "resource": { "db": "", "collection": "system.profile" },
            "actions": ["dbStats","indexStats","collStats"]
          }],
          roles: []
        });
        db.createUser({
          user: "mongodb_exporter",
          pwd: "percona",
          roles: [ 
            { "role": "explainRole", "db": "admin" },
            { "role": "clusterMonitor", "db": "admin" },
            { "role": "read", "db": "local" },
            { "db" : "admin", "role" : "readWrite", "collection": "" },
            { "db" : "admin", "role" : "backup" },
            { "db" : "admin", "role" : "clusterMonitor" },
            { "db" : "admin", "role" : "restore" },
            { "db" : "admin", "role" : "pbmAgent" }    ]
        });
      '
    EOT
  }  
}

# Add shards to the cluster
resource "null_resource" "add_shards" {
  depends_on = [
    docker_container.mongos,
    null_resource.initiate_cfg_replset,
    null_resource.initiate_shard_replset
  ]

  # Set the write concern 
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u root -p percona --eval '
        db.adminCommand({
          "setDefaultRWConcern" : 1,
          "defaultWriteConcern" : { "w" : 1 },
          "defaultReadConcern" : { "level" : "local" }
        })
      '
    EOT
  }

  # Run the add shards command 
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u root -p percona --eval '
        ${join(";", [for i in range(var.shard_count) : "sh.addShard(\"${lookup({for label in docker_container.shard[i * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}/${docker_container.shard[i * var.shardsvr_replicas].name}:${var.shardsvr_port}\")"])};
      '
    EOT
  }
}

# Configure PBM
resource "null_resource" "configure_pbm" {
  depends_on = [
    null_resource.initiate_cfg_replset,
    null_resource.add_shards,
    docker_container.pbm_shard,
    docker_container.pbm_cfg
  ]
  provisioner "local-exec" {
    command = <<-EOT
      cat pbm-storage.conf | docker exec -i ${docker_container.pbm_cfg[0].name} pbm config --file=-
    EOT
  }
}

# Configure PMM for config servers
resource "null_resource" "configure_pmm_client_cfg" {
  depends_on = [
    null_resource.initiate_cfg_replset,
    docker_container.pmm_cfg,
    docker_container.cfg,
  ]
#  for_each = toset([for i in range(var.shard_count) : tostring(i)])
  
  for_each = toset([for i in docker_container.cfg : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-pmm pmm-admin add mongodb --username=mongodb_exporter --password=percona --cluster ${var.env_tag} --host=${each.key} --port=${var.configsvr_port} --tls-skip-verify --enable-all-collectors
    EOT
  }
}

# Configure PMM for shard servers
resource "null_resource" "configure_pmm_client_shards" {
  depends_on = [
    null_resource.add_shards,
    null_resource.initiate_shard_replset,
    docker_container.pmm_shard,
    docker_container.shard,
  ]
  for_each = toset([for i in docker_container.shard : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-pmm pmm-admin add mongodb --username=mongodb_exporter --password=percona --cluster ${var.env_tag} --host=${each.key} --port=${var.shardsvr_port} --tls-skip-verify --enable-all-collectors
    EOT
  }  
}

# Configure PMM for arbiters
resource "null_resource" "configure_pmm_client_arb" {
  depends_on = [
    null_resource.initiate_shard_replset,
    docker_container.pmm_arb, 
    docker_container.arbiter            
  ]
  for_each = toset([for i in docker_container.arbiter : tostring(i.name)])
  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${each.key}-pmm pmm-admin add mongodb --cluster ${var.env_tag} --host=${each.key} --port=${var.shardsvr_port} --tls-skip-verify
    EOT
  }    
}