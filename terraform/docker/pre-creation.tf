locals {
  custom_image_dockerfile_content = templatefile("${path.module}/custom_image.Dockerfile.tmpl", {
    psmdb_image      = var.psmdb_image
    pbm_image        = var.pbm_image
    base_os_image    = var.base_os_image        
  })  
  ycsb_dockerfile_content = templatefile("${path.module}/ycsb.Dockerfile.tmpl", {
    ycsb_os_image    = var.ycsb_os_image        
  })    
}

resource "local_file" "custom_image_dockerfile_content" {
  filename = "${path.module}/${var.custom_image}.Dockerfile"
  content  = local.custom_image_dockerfile_content
}

resource "null_resource" "docker_build_custom_image" {
  provisioner "local-exec" {
    command = "docker build -t ${var.custom_image} -f ${path.module}/${var.custom_image}.Dockerfile ."
  }
}

resource "local_file" "ycsdb_dockerfile_content" {
  filename = "${path.module}/${var.ycsb_image}.Dockerfile"
  content  = local.ycsb_dockerfile_content
}

resource "null_resource" "docker_build_ycsb" {
  provisioner "local-exec" {
    command = "docker build -t ${var.ycsb_image} -f ${path.module}/${var.ycsb_image}.Dockerfile ."
  }
}