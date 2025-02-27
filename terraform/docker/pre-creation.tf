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

# Prepare the PBM docker image
resource "local_file" "pbm_mongod_image_dockerfile_content" {
  filename = "${path.module}/${var.pbm_mongod_image}.Dockerfile"
  content  = local.pbm_mongod_image_dockerfile_content
}

resource "null_resource" "docker_build_pbm_mongod_image" {
  provisioner "local-exec" {
    command = "docker build -t ${var.pbm_mongod_image} -f ${path.module}/${var.pbm_mongod_image}.Dockerfile ."
  }
}

# Prepare the YCSB docker image
resource "local_file" "ycsdb_dockerfile_content" {
  filename = "${path.module}/${var.ycsb_image}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

resource "null_resource" "docker_build_ycsb" {
  provisioner "local-exec" {
    command = "docker build -t ${var.ycsb_image} -f ${path.module}/${var.ycsb_image}.Dockerfile ."
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
