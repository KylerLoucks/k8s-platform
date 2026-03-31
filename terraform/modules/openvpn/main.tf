data "aws_region" "current" {}

# Get latest Ubuntu 22.04 ARM64 AMI
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/arm64/hvm/ebs-gp2/ami-id"
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

locals {
  _private_network_cidrs = length(var.private_network_cidrs) == 0 ? [var.vpc_cidr] : var.private_network_cidrs
  private_network_lines = join("\n", [
    for idx, network in local._private_network_cidrs :
    "sacli --key \"vpn.server.routing.private_network.${idx}\" --value \"${network}\" ConfigPut"
  ])
}

# EIP
resource "aws_eip" "eip" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-eip"
  })
}

resource "aws_eip_association" "openvpn" {
  instance_id   = aws_instance.openvpn.id
  allocation_id = aws_eip.eip.id
}

resource "aws_instance" "openvpn" {
  ami                     = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type           = var.instance_type
  disable_api_termination = var.disable_api_termination
  iam_instance_profile    = aws_iam_instance_profile.openvpn.id
  key_name                = var.key_name
  subnet_id               = var.subnet_id
  vpc_security_group_ids  = [aws_security_group.openvpn.id]
  ebs_optimized           = var.ebs_optimized
  hibernation             = var.hibernation
  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = var.ebs_encryption
    kms_key_id  = var.ebs_kms_key_id
  }

  # Additional EBS volume for OpenVPN data
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = false
    encrypted             = var.ebs_encryption
    kms_key_id            = var.ebs_kms_key_id
  }

  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh", {
    vpc_cidr               = var.vpc_cidr
    openvpn_admin_password = var.openvpn_admin_password
    elastic_ip             = aws_eip.eip.public_ip
    private_network_lines  = local.private_network_lines
  }))

  volume_tags = merge(var.tags, { "Name" = "${var.name} root volume" })
  tags        = merge(var.tags, { "Name" = var.name, "ssm" = var.enable_ssm })

  lifecycle {
    ignore_changes = [
      # Ignore if new AMI is available from AWS
      ami,
      # Ignore if new EIP is available from AWS
      public_ip,
      public_dns,
    ]
  }

}
resource "aws_iam_role" "openvpn" {
  name        = var.name
  path        = "/"
  description = "${var.name} EC2 instance"

  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
}
POLICY
}

resource "aws_iam_instance_profile" "openvpn" {
  name = aws_iam_role.openvpn.name
  role = aws_iam_role.openvpn.name
}

resource "aws_iam_role_policy_attachment" "openvpn" {
  role       = aws_iam_role.openvpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#
# Security group, allow TCP 443 and UDP 1194 from var.vpn_ingress_cidr.
# TCP 22 and TCP 943 (OpenVPN Web Admin) from inside the VPC.
#

resource "aws_security_group" "openvpn" {
  name_prefix = "${var.name}-"
  description = "Internal and external ${var.name} instance access"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(var.tags, { "Name" = var.name })
}

resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.openvpn.id
  description       = "SSH"
}

resource "aws_security_group_rule" "ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.vpn_ingress_cidr
  security_group_id = aws_security_group.openvpn.id
  description       = "OpenVPN HTTPS"
}

resource "aws_security_group_rule" "ingress_https_admin" {
  type              = "ingress"
  from_port         = 943
  to_port           = 943
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.openvpn.id
  description       = "OpenVPN HTTPS Admin Management"
}

resource "aws_security_group_rule" "ingress_vpn" {
  type              = "ingress"
  from_port         = 1194
  to_port           = 1194
  protocol          = "udp"
  cidr_blocks       = var.vpn_ingress_cidr
  security_group_id = aws_security_group.openvpn.id
  description       = "OpenVPN UDP"
}

resource "aws_security_group_rule" "egress_full" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.openvpn.id
  description       = "ALL"
}
