# # Initiate the shards replica sets 
# resource "null_resource" "initiate_shard_replset" {
#   depends_on = [docker_container.arbiter, docker_container.shard]

#   # Initiate the shards replica sets 
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.shard[each.key * data_nodes_per_replset].name} mongosh --port ${var.shardsvr_port} --eval '
#         rs.initiate({
#           _id: "${lookup({for label in docker_container.shard[each.key * var.data_nodes_per_replset].labels : label.label => label.value}, "replsetName", null)}",
#           members: [
#             { _id: 0, host: "${docker_container.shard[each.key * var.data_nodes_per_replset].name}:${var.shardsvr_port}", priority: 2 },
#             ${join(",", [for i in range(1, var.data_nodes_per_replset) : "{ _id: ${i}, host: \"${docker_container.shard[each.key * var.data_nodes_per_replset + i].name}:${var.shardsvr_port}\" }"])}
#             ${join(",", [for i in range(var.arbiters_per_replset) : ",{ _id: ${var.data_nodes_per_replset + i}, host: \"${docker_container.arbiter[each.key * var.arbiters_per_replset + i].name}:${var.shardsvr_port}\", arbiterOnly: true }"])}
#           ]
#         });
#       '
#       retries=30
#       success=false
#       while [ $retries -gt 0 ]; do
#         # Check the replica set status and look for a primary for the shard
#         primary=$(docker exec -i ${docker_container.shard[each.key * var.data_nodes_per_replset].name} mongosh --port ${var.shardsvr_port} --eval "rs.status().members.filter(m => m.stateStr === 'PRIMARY').length > 0")
        
#         if test "$primary" = "true"; then
#           echo "Primary has been elected in shard ${each.key}"
#           success=true
#           break
#         fi
        
#         echo "Waiting for primary to be elected in shard ${each.key}... retries left: $retries"
#         retries=$((retries - 1))
#         sleep 5
#       done

#       if test "$success" = "false" ; then
#         echo "Primary not elected in shard ${each.key} after maximum retries. Exiting."
#         exit 1
#       fi
#     EOT
#   }

#   # Create the root user on the shards
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.shard[each.key * var.data_nodes_per_replset].name} mongosh admin --port ${var.shardsvr_port} --eval '
#         db.createUser({
#           "user": "${var.mongodb_root_user}",
#           "pwd": "${var.mongodb_root_password}",
#           "roles": [
#             { "role": "root", "db": "admin" }
#           ]
#         });
#       '        
#     EOT
#   }  

#   # Create user for PBM on the shards
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.shard[each.key * var.data_nodes_per_replset].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.shardsvr_port} --eval '
#         db.createRole({
#           "role": "pbmAnyAction",
#           "privileges": [
#             { "resource": { "anyResource": true }, "actions": ["anyAction"] }
#           ],
#           "roles": []
#         });
#         db.createUser( {
#           "user": "${var.mongodb_pbm_user}",
#           "pwd": "${var.mongodb_pbm_password}",
#           "roles": [         
#             { "db" : "admin", "role" : "readWrite", "collection": "" },
#             { "db" : "admin", "role" : "backup" },
#             { "db" : "admin", "role" : "clusterMonitor" },
#             { "db" : "admin", "role" : "restore" },
#             { "db" : "admin", "role" : "pbmAnyAction" } 
#           ]
#         });
#       '
#     EOT
#   }  

#   # Create user for PMM on the shards
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.shard[each.key * var.data_nodes_per_replset].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --port ${var.shardsvr_port} --eval '
#         db.createRole({
#           "role": "explainRole",
#           "privileges": [{
#             "resource": { "db": "", "collection": "" },
#             "actions": ["listIndexes","listCollections","dbStats","dbHash","collStats","indexStats","find"]
#           }, 
#           {
#             "resource": { "db": "", "collection": "system.profile" },
#             "actions": ["dbStats","indexStats","collStats"]
#           }, 
#           {
#             "resource": { "db": "", "collection": "system.version" },
#             "actions": ["find"]
#           }],
#           "roles": []
#         });
#         db.createUser({
#           "user": "${var.mongodb_pmm_user}",
#           "pwd": "${var.mongodb_pmm_password}",
#           "roles": [ 
#             { "role": "explainRole", "db": "admin" },
#             { "role": "read", "db": "local" },
#             { "db" : "admin", "role" : "readWrite", "collection": "" },
#             { "db" : "admin", "role" : "backup" },
#             { "db" : "admin", "role" : "clusterMonitor" },
#             { "db" : "admin", "role" : "restore" },
#             { "db" : "admin", "role" : "pbmAnyAction" } 
#           ]
#         });
#       '
#     EOT
#   }  
# }

# # Set the global write concern to 1. This is needed when using arbiters
# resource "null_resource" "change_default_write_concern" {
#   count = length(docker_container.arbiter) > 0 ? 1 : 0
#   depends_on = [
#     docker_container.mongos,
#     null_resource.initiate_shard_replset
#   ]
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.mongos[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval '
#         db.adminCommand({
#           "setDefaultRWConcern" : 1,
#           "defaultWriteConcern" : { "w" : 1 },
#           "defaultReadConcern" : { "level" : "local" }
#         })
#       '
#     EOT
#   }
# }

# # Configure PBM
# resource "null_resource" "configure_pbm" {
#   depends_on = [
#     docker_container.shard,
#     docker_container.pbm_shard,
#   ]
#   provisioner "local-exec" {
#     command = <<-EOT
#       sleep 5
#       cat pbm-storage.conf | docker exec -i ${docker_container.pbm_shard[0].name} pbm config --file=-
#     EOT
#   }
# }

# # Configure PMM for shard servers
# resource "null_resource" "configure_pmm_client_shards" {
#   depends_on = [
#     null_resource.initiate_shard_replset,
#     docker_container.pmm_shard,
#     docker_container.shard,
#   ]
#   for_each = toset([for i in docker_container.shard : tostring(i.name)])
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${var.pmm_host}:${var.pmm_port} --server-insecure-tls --force 
#     EOT
#   }  
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --username=${var.mongodb_pmm_user} --password=${var.mongodb_pmm_password} --host=${each.key} --port=${var.shardsvr_port} --service-name=${each.key}-mongodb --tls-skip-verify --enable-all-collectors
#     EOT
#   }    
# }

# # Configure PMM for arbiters
# resource "null_resource" "configure_pmm_client_arb" {
#   depends_on = [
#     null_resource.initiate_shard_replset,
#     docker_container.pmm_arb, 
#     docker_container.arbiter            
#   ]
#   for_each = toset([for i in docker_container.arbiter : tostring(i.name)])
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin config ${each.key} container ${each.key} --server-url=https://${var.pmm_user}:${var.pmm_password}@${var.pmm_host}:${var.pmm_port} --server-insecure-tls --force 
#     EOT
#   }    
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${each.key}-${var.pmm_client_container_suffix} pmm-admin add mongodb --environment=${var.env_tag} --cluster ${var.cluster} --host=${each.key} --port=${var.shardsvr_port} --service-name=${each.key}-mongodb --tls-skip-verify
#     EOT
#   }     
# }

# # Create the YCSB collection
# resource "null_resource" "create_ycsb_collection" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       docker exec -i ${docker_container.shard[0].name} mongosh admin -u ${var.mongodb_root_user} -p ${var.mongodb_root_password} --eval 'sh.enableSharding("ycsb"); sh.shardCollection("ycsb.usertable", { "_id" : "hashed" }, false, { numInitialChunks : 100 });'
#     EOT
#   }
# }