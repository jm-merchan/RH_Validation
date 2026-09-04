output "ami_id" {
  description = "RHEL 9 AMI selected in eu-central-1."
  value       = data.aws_ami.rhel9.id
}

output "ami_name" {
  description = "Human-readable name of the selected RHEL 9 AMI."
  value       = data.aws_ami.rhel9.name
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.rhel9.id
}

output "private_ip" {
  description = "Private IPv4 of the instance. Use this in Vault api_addr/cluster_addr for a single-node PoC."
  value       = aws_instance.rhel9.private_ip
}

output "public_ip" {
  description = "Elastic IP used to reach the instance from the Internet."
  value       = aws_eip.rhel9.public_ip
}

output "scp_license" {
  description = "scp that copies the local license to ~/vault.hclic. Usage: eval \"$(terraform output -raw scp_license)\""
  value       = "scp -i '${abspath(local.ssh_private_key_path)}' '${local.license_file_path}' ec2-user@${aws_eip.rhel9.public_ip}:~/vault.hclic"
}

output "ssh" {
  description = "SSH command as ec2-user. Usage: eval \"$(terraform output -raw ssh)\""
  value       = "ssh -i '${abspath(local.ssh_private_key_path)}' ec2-user@${aws_eip.rhel9.public_ip}"
}

output "ssh_command" {
  description = "Same as the ssh output (kept for compatibility)."
  value       = "ssh -i '${abspath(local.ssh_private_key_path)}' ec2-user@${aws_eip.rhel9.public_ip}"
}

output "ssh_private_key_path" {
  description = "Path to the generated private key. Do not commit this file."
  value       = abspath(local.ssh_private_key_path)
}
