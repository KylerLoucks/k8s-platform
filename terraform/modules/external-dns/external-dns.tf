# IAM role for external-dns
module "external_dns_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2.1"

  name = "external-dns-${data.aws_caller_identity.current.account_id}"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = var.external_dns_hosted_zone_arns

  oidc_providers = {
    main = {
      provider_arn               = var.cluster_oidc_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

  tags = var.tags
}

# external-dns Helm chart
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_version

  namespace        = "external-dns"
  create_namespace = true

  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_role.arn
        }
      }

      provider = {
        name = "aws"
      }
      env = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.name
        }
      ]

      sources       = var.external_dns_sources
      domainFilters = var.external_dns_domain_filters
      policy        = var.external_dns_policy

      txtOwnerId = var.cluster_name
      txtPrefix  = "external-dns-"

      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }

      # Security context
      securityContext = {
        runAsNonRoot = false
      }

      # Annotations for the deployment
      deploymentAnnotations = {
        "reloader.stakater.com/auto" = "true"
      }
    })
  ]

  depends_on = [module.external_dns_role]
}
