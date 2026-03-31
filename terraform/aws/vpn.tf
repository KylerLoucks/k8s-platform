################################################################################
# OpenVPN Instance - used to connect to the EKS cluster from local machine
################################################################################
module "openvpn" {
  source                 = "../modules/openvpn"
  name                   = "${basename(path.cwd)}-openvpn"
  openvpn_admin_password = random_password.openvpn_admin_password.result
  ebs_encryption         = true
  #   ebs_kms_key_id         = module.kms.ebs_key_arn
  key_name  = module.keypair01.ec2_keypair_name
  subnet_id = module.vpc.public_subnets[0]
  vpc_cidr  = module.vpc.vpc_cidr_block
  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
  }

  # Set API termination to false to allow tearing down the instance during Terraform destroy
  disable_api_termination = false
}

################################################################################
# OpenVPN Keypair - used to connect to the OpenVPN instance
################################################################################
module "keypair01" {
  source   = "../modules/keypair"
  key_name = basename(path.cwd)
}

################################################################################
# OpenVPN Admin Password
################################################################################
resource "random_password" "openvpn_admin_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "openvpn_admin_password" {
  name                    = "openvpn_admin_password"
  recovery_window_in_days = 0 # Set to zero to force delete during Terraform destroy
  description             = "OpenVPN admin password"
  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
    SecretType  = "openvpn-password"
  }
}

resource "aws_secretsmanager_secret_version" "openvpn_admin_password" {
  secret_id     = aws_secretsmanager_secret.openvpn_admin_password.id
  secret_string = random_password.openvpn_admin_password.result
}