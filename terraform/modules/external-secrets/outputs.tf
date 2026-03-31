output "external_secrets_service_account_arn" {
  description = "ARN of the external-secrets service account IAM role"
  value       = module.external_secrets_role.arn
}

