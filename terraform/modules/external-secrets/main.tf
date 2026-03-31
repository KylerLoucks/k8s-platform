terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.34"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
  }
}

# Get current AWS region and account
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

