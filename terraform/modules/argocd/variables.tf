variable "create" {
  description = "Create terraform resources"
  type        = bool
  default     = true
}
variable "argocd" {
  description = "argocd helm options"
  type        = any
  default     = {}
}

variable "apps" {
  description = "argocd app of apps to deploy"
  type        = any
  default     = {}
}

variable "external_clusters" {
  description = "External clusters to register in ArgoCD"
  type        = map(any)
  default     = {}
}

variable "repositories" {
  description = "Repositories to add to ArgoCD"
  type        = map(any)
  default     = {}
}