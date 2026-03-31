<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_metric_alarm.instance_status_check_failed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.system_status_check_failed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_eip.eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eip_association.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association) | resource |
| [aws_iam_instance_profile.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.openvpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.egress_full](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_https_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_vpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami"></a> [ami](#input\_ami) | Amazon Linux AMI in the target region. | `string` | n/a | yes |
| <a name="input_disable_api_termination"></a> [disable\_api\_termination](#input\_disable\_api\_termination) | Termination protection. | `bool` | `true` | no |
| <a name="input_ebs_encryption"></a> [ebs\_encryption](#input\_ebs\_encryption) | Encrypt root EBS volume | `bool` | `false` | no |
| <a name="input_ebs_kms_key_id"></a> [ebs\_kms\_key\_id](#input\_ebs\_kms\_key\_id) | KMS Key ID.  Required if encryption is enabled. | `string` | `""` | no |
| <a name="input_ebs_optimized"></a> [ebs\_optimized](#input\_ebs\_optimized) | n/a | `bool` | `null` | no |
| <a name="input_enable_ssm"></a> [enable\_ssm](#input\_enable\_ssm) | Enable Systems Manager (SSM) access. *Required to set initial password.* | `string` | `true` | no |
| <a name="input_hibernation"></a> [hibernation](#input\_hibernation) | n/a | `bool` | `null` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 Instance type. | `string` | `"t4g.micro"` | no |
| <a name="input_key_name"></a> [key\_name](#input\_key\_name) | Key pair name. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name used for instance, IAM role, and security group. | `string` | n/a | yes |
| <a name="input_openvpn_admin_password"></a> [openvpn\_admin\_password](#input\_openvpn\_admin\_password) | OpenVPN Admin Password for user named openvpn | `string` | n/a | yes |
| <a name="input_private_network_cidrs"></a> [private\_network\_cidrs](#input\_private\_network\_cidrs) | Private Network CIDRs to route. Defaults to the VPC CIDR only | `list(string)` | `[]` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Size in GB of root EBS volume. | `number` | `16` | no |
| <a name="input_root_volume_type"></a> [root\_volume\_type](#input\_root\_volume\_type) | Volume type for the instance | `string` | `"gp2"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Target public subnet ID for deployment. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all stack resources. | `map(any)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR of the target VPC. | `string` | n/a | yes |
| <a name="input_vpn_ingress_cidr"></a> [vpn\_ingress\_cidr](#input\_vpn\_ingress\_cidr) | This CIDR range will be allowed to connect to ports 443 (HTTPS) and 1194 (UDP OpenVPN). | `list(string)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | EC2 instance ID. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Instance private IP. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Instance public IP. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID. |
<!-- END_TF_DOCS -->
