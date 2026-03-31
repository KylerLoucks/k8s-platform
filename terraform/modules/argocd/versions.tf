terraform {
  required_version = ">= 1.5.7"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}