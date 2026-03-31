# IAM role for external-secrets
module "external_secrets_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2.1"

  name = "external-secrets-${data.aws_caller_identity.current.account_id}"

  attach_external_secrets_policy                     = true
  external_secrets_secrets_manager_arns              = var.external_secrets_secrets_manager_arns
  external_secrets_secrets_manager_create_permission = true

  oidc_providers = {
    main = {
      provider_arn               = var.cluster_oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = var.tags
}

# Additional policy for Secrets Manager integration
resource "aws_iam_policy" "ack_eso_secrets_manager" {
  name_prefix = "ack-eso-secrets-manager-"
  description = "Additional permissions for ESO controller to manage secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:RotateSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:Verify*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ack_rds_secrets_manager" {
  role       = module.external_secrets_role.name
  policy_arn = aws_iam_policy.ack_eso_secrets_manager.arn
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_version

  namespace        = "external-secrets"
  create_namespace = true

  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      serviceAccount = {
        name = "external-secrets"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_secrets_role.arn
        }
      }

      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }

      webhook = {
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
        # Fix for EKS Fargate - port 10250 conflicts with kubelet
        port = 9443
      }

      certController = {
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
      }
    })
  ]

  depends_on = [module.external_secrets_role]
}

resource "helm_release" "secretstores" {
  name  = "external-secrets-secretstores"
  chart = "${path.module}/charts/secretstores"

  namespace = "external-secrets"

  values = [
    yamlencode({
      enabled = true
      aws = {
        region = var.region
      }
    })
  ]

  depends_on = [helm_release.external_secrets]
}
