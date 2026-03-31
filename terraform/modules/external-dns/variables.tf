variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN"
  type        = string
}

variable "external_dns_version" {
  description = "Version of the external-dns Helm chart"
  type        = string
  default     = "1.17.0"
}

variable "external_dns_hosted_zone_arns" {
  description = "List of Route53 hosted zone ARNs that external-dns should have access to"
  type        = list(string)
  default     = []
}

variable "external_dns_sources" {
  description = "List of sources external-dns should watch for DNS entries"
  type        = list(string)
  default     = ["ingress", "service", "crd"]
}

variable "external_dns_domain_filters" {
  description = "List of domains external-dns should manage (empty means all domains)"
  type        = list(string)
  default     = []
}

variable "external_dns_policy" {
  description = "External-dns policy (sync, upsert-only, or create-only)"
  type        = string
  default     = "sync"

  validation {
    condition     = contains(["sync", "upsert-only", "create-only"], var.external_dns_policy)
    error_message = "Policy must be 'sync', 'upsert-only', or 'create-only'."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

