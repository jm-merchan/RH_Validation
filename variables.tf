variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach the instance over SSH (your public IPv4 /32)."
  type        = string
  default     = "88.13.155.209/32"

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR, for example 203.0.113.10/32."
  }
}

variable "aws_region" {
  description = "AWS region for the RHEL 9 instance."
  type        = string
  default     = "eu-central-1"
}

variable "data_volume_size_gb" {
  description = "Size in GiB of the dedicated XFS volume mounted at /apps/vault/data."
  type        = number
  default     = 100
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "lab"
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium gives 4 GiB RAM, enough for a Vault PoC."
  type        = string
  default     = "t3.medium"
}

variable "license_file" {
  description = "Local path to the Vault Enterprise license (.hclic) used by the scp_license output."
  type        = string
  default     = "vault-telefonica.hclic"
}

variable "project_name" {
  description = "Short name used in resource names and tags."
  type        = string
  default     = "rh-vault-poc"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.42.0.0/16"
}
