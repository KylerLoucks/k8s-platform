output "instance_id" {
  value       = aws_instance.openvpn.id
  description = "EC2 instance ID."
}

output "private_ip" {
  value       = aws_instance.openvpn.private_ip
  description = "Instance private IP."
}

output "public_ip" {
  value       = aws_eip.eip.public_ip
  description = "Instance public IP."
}

output "security_group_id" {
  value       = aws_security_group.openvpn.id
  description = "Security group ID."
}
