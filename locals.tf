locals {
  az_name = data.aws_availability_zones.available.names[0]

  common_tags = {
    Name = var.project_name
  }

  public_subnet_cidr = cidrsubnet(var.vpc_cidr, 8, 1)

  ssh_private_key_path = "${path.module}/ssh/${var.project_name}.pem"
  license_file_path    = abspath(pathexpand(var.license_file))
}
