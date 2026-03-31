variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. sandbox, production, demos)"
  type        = string
  default     = "sandbox"
}

variable "region" {
  description = "AWS region where the EKS cluster is located"
  type        = string
}

variable "external_secrets_version" {
  description = "Version of the external-secrets Helm chart"
  type        = string
  default     = "0.19.2"
}

variable "external_secrets_namespace" {
  description = "Namespace for external-secrets resources"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_secrets_manager_arns" {
  description = "List of Secrets Manager secret ARNs that external-secrets should have access to"
  type        = list(string)
  default     = []
}


variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

