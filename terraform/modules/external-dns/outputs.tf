output "external_dns_service_account_arn" {
  description = "ARN of the external-dns service account IAM role"
  value       = module.external_dns_role.arn
}
