resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws_key" {
  key_name   = var.key_name
  public_key = tls_private_key.private_key.public_key_openssh
  tags       = var.tags
}

resource "aws_ssm_parameter" "keypair_ssm" {
  name        = var.key_name
  description = "SSH KeyPair created via Terraform"
  type        = "SecureString"
  # key_id      = var.kms_key_id
  value       = tls_private_key.private_key.private_key_pem
  tags        = var.tags
}
