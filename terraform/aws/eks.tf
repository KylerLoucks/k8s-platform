# Resolves to a stable IAM principal ARN (role/user) for the identity running Terraform.
# The EKS module’s KMS policy uses this pattern when kms_key_administrators is empty; including it
# alongside aws_iam_role.eks avoids MalformedPolicyDocumentException from a single invalid/empty principal.
data "aws_iam_session_context" "caller" {
  arn = data.aws_caller_identity.current.arn
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.2.0"

  name               = var.eks_cluster_name
  kubernetes_version = "1.33"
  enable_irsa        = true # Allow IAM Roles for Service Accounts (IRSA)

  # Cluster encryption KMS key admins: Terraform caller + role used for kubectl/API access.
  kms_key_administrators = distinct(compact([
    data.aws_iam_session_context.caller.issuer_arn,
    aws_iam_role.eks.arn,
  ]))

  # Allow assumed IAM role access to the clusters resources
  access_entries = {
    local-role-accounts = {
      principal_arn = aws_iam_role.eks.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    dev-user = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/dev"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }

  }

  endpoint_public_access_cidrs = [
    module.vpc.vpc_cidr_block,
    "50.39.170.84/32",
  ]

  endpoint_public_access  = true
  endpoint_private_access = true

  security_group_additional_rules = {
    vpc_ingress = {
      description = "Allow access to the EKS API from the VPC"
      type        = "ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }


  # Enable control plane logging including audit logs
  create_cloudwatch_log_group            = false
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 90
  # cloudwatch_log_group_kms_key_id        = module.kms.cloudwatch_key_arn

  addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate" # Tell CoreDNS to use Fargate for the pods. Will fail if not set since there are no node groups.
      })
    }
    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
    }
    # Metrics Server for HPA (resource-based autoscaling) and kubectl top
    # Note: Configured to use port 10251 for Fargate compatibility (10250 is reserved)
    metrics-server = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets


  # Choose which namespaces to allow for fargate container provisioning
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
        },
        {
          namespace = "default"
        },
        {
          namespace = "argocd"
        },
        {
          namespace = "external-*"
        },
        {
          namespace = "monitoring"
        }
      ]
      tags = {
        Owner = var.environment
      }
    }

    dev = {
      name = "dev"
      selectors = [
        {
          namespace = "dev-*"
        }
      ]
      tags = {
        Owner = var.environment
      }
    }

    metrics = {
      name = "metrics"
      selectors = [
        {
          namespace = "amazon-cloudwatch"
        }
      ]
      tags = {
        Owner = var.environment
      }
    }
  }



  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
  }
}


################################################################################
# EKS Role - used to access the EKS cluster API server from terraform.
# See the module.eks.access_entries for the IAM roles that are allowed to access the EKS cluster.
################################################################################
resource "aws_iam_role" "eks" {
  name = "eks-kms-admin-${data.aws_caller_identity.current.account_id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}


module "external-secrets" {
  source = "../modules/external-secrets/"

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  environment               = var.environment
  region                    = data.aws_region.current.region

  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:platform/${var.environment}/*",
    module.rds.db_instance_master_user_secret_arn,
  ]


  tags = {
    Environment = var.environment
    Owner       = var.environment
  }

  depends_on = [
    module.eks,
    module.rds,
  ]
}

# module "external-dns" {
#   source = "../modules/external-dns/"

#   cluster_name              = module.eks.cluster_name
#   cluster_oidc_provider_arn = module.eks.oidc_provider_arn

#   # Pass the ARN of the hosted zone created by the Route53 zone module.
#   external_dns_hosted_zone_arns = [
#     data.aws_route53_zone.domain.arn
#   ]

#   external_dns_domain_filters = [var.domain_name]

#   tags = {
#     Environment = var.environment
#     Owner       = var.environment
#   }
#   depends_on = [
#     module.eks
#   ]
# }