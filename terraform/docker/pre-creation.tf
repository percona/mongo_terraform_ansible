locals {
  pbm_mongod_image_dockerfile_content = templatefile("${path.module}/pbm-mongod.Dockerfile.tmpl", {
    psmdb_image      = var.psmdb_image
    pbm_image        = var.pbm_image
    base_os_image    = var.base_os_image        
  })  
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_os_image    = var.ycsb_os_image        
  })    
#  mongos_dockerfile_content = templatefile("${path.module}/mongos.Dockerfile.tmpl", {
#    base_os_image    = var.base_os_image        
#    psmdb_image      = var.psmdb_image
#  })      
}

# Write PBM Dockerfile to disk
resource "local_file" "pbm_mongod_image_dockerfile_content" {
  filename = "${path.module}/${var.pbm_mongod_image}.Dockerfile"
  content  = local.pbm_mongod_image_dockerfile_content
}

# Build PBM Docker image with the MongoDB binary of the version in use (required for physical restore)
resource "docker_image" "pbm_mongod" {
  name = var.pbm_mongod_image
  build {
    context    = path.module
    dockerfile = local_file.pbm_mongod_image_dockerfile_content.filename
  }
}

# Write YCSB Dockerfile to disk
resource "local_file" "ycsb_dockerfile_content" {
  filename = "${path.module}/${var.ycsb_image}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

# Build YCSB Docker image
resource "docker_image" "ycsb" {
  name = var.ycsb_image
  build {
    context    = path.module
    dockerfile = local_file.ycsb_dockerfile_content.filename
  }
}

# Prepare a custom mongos docker image
#resource "local_file" "mongos_image_dockerfile_content" {
#  filename = "${path.module}/${var.mongos_image}.Dockerfile"
#  content  = local.mongos_dockerfile_content
#}

#resource "null_resource" "docker_build_mongos_image" {
#  provisioner "local-exec" {
#    command = "docker build -t ${var.mongos_image} -f ${path.module}/${var.mongos_image}.Dockerfile ."
#  }
#}
