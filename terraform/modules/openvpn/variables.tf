variable "name" {
  description = "Name for the OpenVPN instance and related resources"
  type        = string
}
variable "root_volume_type" {
  description = "Volume type for the instance"
  default     = "gp2"
  type        = string
}
variable "ebs_optimized" {
  default = null
  type    = bool
}
variable "hibernation" {
  default = null
  type    = bool
}

variable "disable_api_termination" {
  description = "Termination protection."
  default     = true
  type        = bool
}

variable "ebs_encryption" {
  description = "Encrypt root EBS volume"
  default     = false
  type        = bool
}

variable "ebs_kms_key_id" {
  description = "KMS Key ID.  Required if encryption is enabled."
  default     = ""
  type        = string
}


variable "enable_ssm" {
  description = "Enable Systems Manager (SSM) access. *Required to set initial password.*"
  default     = true
  type        = string
}

variable "instance_type" {
  description = "EC2 Instance type."
  default     = "t4g.micro"
  type        = string
}

variable "key_name" {
  description = "Key pair name."
  type        = string
}

variable "root_volume_size" {
  description = "Size in GB of root EBS volume."
  default     = 16
  type        = number
}

variable "subnet_id" {
  description = "Target public subnet ID for deployment."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all stack resources."
  default     = {}
  type        = map(any)
}

variable "vpc_cidr" {
  description = "VPC CIDR of the target VPC."
  type        = string
}

variable "private_network_cidrs" {
  description = "Private Network CIDRs to route. Defaults to the VPC CIDR only"
  type        = list(string)
  default     = []
}

variable "vpn_ingress_cidr" {
  description = "This CIDR range will be allowed to connect to ports 443 (HTTPS) and 1194 (UDP OpenVPN)."
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "openvpn_admin_password" {
  description = "OpenVPN Admin Password for user named openvpn"
  type        = string
}