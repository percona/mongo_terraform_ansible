resource "null_resource" "initiate_cfg_replset" {
  depends_on = [docker_container.cfg]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh --port 27019 --eval '
        rs.initiate({
          _id: "${lookup({for label in docker_container.cfg[0].labels : label.label => label.value}, "replsetName", null)}",
          configsvr: true,
          members: [
            { _id: 0, host: "${docker_container.cfg[0].name}:27019", priority: 2 },
            ${join(",", [for i in range(1, var.configsvr_count) : "{ _id: ${i}, host: \"${docker_container.cfg[i].name}:27019\" }"])}
          ]
        });
      '
    EOT
  }

  provisioner "local-exec" {
    command = "sleep 10"
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.cfg[0].name} mongosh admin --port 27019 --eval '
        db.createUser({
          user: "root",
          pwd: "percona",
          roles: [
            {role: "root", db: "admin"}
          ]
        })
      '
    EOT
  }

}

resource "null_resource" "initiate_shard_replset" {

  for_each = toset([for i in range(var.shard_count) : tostring(i)])

  depends_on = [docker_container.arbiter, docker_container.shard]

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh --port 27018 --eval '
        rs.initiate({
          _id: "${lookup({for label in docker_container.shard[each.key * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}",
          members: [
            { _id: 0, host: "${docker_container.shard[each.key * var.shardsvr_replicas].name}:27018", priority: 2 },
            ${join(",", [for i in range(1, var.shardsvr_replicas) : "{ _id: ${i}, host: \"${docker_container.shard[each.key * var.shardsvr_replicas + i].name}:27018\" }"])}
            ${join(",", [for i in range(var.arbiters_per_replset) : ",{ _id: ${var.shardsvr_replicas + i}, host: \"${docker_container.arbiter[each.key * var.arbiters_per_replset + i].name}:27018\", arbiterOnly: true }"])}
          ]
        });
      '
    EOT
  }

  provisioner "local-exec" {
    command = "sleep 10"
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.shard[each.key * var.shardsvr_replicas].name} mongosh admin --port 27018 --eval '
        db.createUser({
          user: "root",
          pwd: "percona",
          roles: [
            {role: "root", db: "admin"}
          ]
        })
      '
    EOT
  }  
}

resource "null_resource" "add_shards" {
  depends_on = [
    docker_container.mongos,
    null_resource.initiate_cfg_replset,
    null_resource.initiate_shard_replset
  ]

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

  provisioner "local-exec" {
    command = <<-EOT
      docker exec -i ${docker_container.mongos[0].name} mongosh admin -u root -p percona --eval '
        ${join(";", [for i in range(var.shard_count) : "sh.addShard(\"${lookup({for label in docker_container.shard[i * var.shardsvr_replicas].labels : label.label => label.value}, "replsetName", null)}/${docker_container.shard[i * var.shardsvr_replicas].name}:27018\")"])};
      '
    EOT
  }
}