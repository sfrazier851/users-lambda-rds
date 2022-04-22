output "instance_public_dns" {
  description = "Public DNS of the EC2 bastion host"
  value       = aws_instance.rds_bastion.public_dns
}
