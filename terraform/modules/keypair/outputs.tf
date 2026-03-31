output "ec2_keypair_name" {
  description = "EC2 SSH KeyPair Name"
  value       = aws_key_pair.aws_key.key_name
}
