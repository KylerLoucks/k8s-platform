
################################################################################
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager to extract the ArgoCD admin password with the secret name as "argocd"
################################################################################

resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd/admin-password"
  recovery_window_in_days = 0 # Set to zero to force delete during Terraform destroy
  description             = "ArgoCD admin password"
  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
    SecretType  = "argocd-password"
  }
}

# Argo requires the password to be bcrypt, we use custom provider of bcrypt,
# as the default bcrypt function generates diff for each terraform plan
resource "bcrypt_hash" "argo" {
  cleartext = random_password.argocd.result
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result

  lifecycle {
    # Avoid re-hashing/re-writing on future applies
    ignore_changes = [secret_string]
  }
}



################################################################################
# Install ArgoCD
################################################################################
module "argocd" {
  source = "../modules/argocd"

  argocd = {
    chart_version = "9.1.1"
    timeout       = 900
    values = [
      yamlencode({

        # in-cluster redis
        redis = {
          enabled      = true
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
        redis-ha = {
          enabled = false
        }

        # externalRedis = {
        #   host     = module.argocd_external_redis.replication_group_primary_endpoint_address
        #   port     = module.argocd_external_redis.replication_group_port
        #   username = "default"
        #   # password will be injected via set_sensitive below
        #   # externalRedis.password
        # }

        # ALB handles TLS termination with ACM certificate. ALB (HTTPS) --> ArgoCD (HTTP)
        configs = {
          params = {
            "server.insecure" = true
            "server.basehref" = "/argocd"
            "server.rootpath" = "/argocd"
          }
        }

        # Enable TLS when ArgoCD talks to external Redis. Will cause connection errors if not set.
        controller = {
          extraArgs = [
            "--redis-use-tls",
          ]
          resources = var.argocd_controller_resources
        }

        repoServer = {
          extraArgs = [
            "--redis-use-tls",
          ]
          resources = var.argocd_repo_resources
        }

        server = {
          extraArgs = [
            "--redis-use-tls",
          ]
          service   = { type = "ClusterIP" }
          resources = var.argocd_server_resources

          # Disable chart-managed ingress; we manage ingress explicitly below.
          ingress = {
            enabled = false
          }
        }

        applicationSet = {
          resources = var.argocd_applicationset_resources
        }

        dex = {
          resources = var.argocd_dex_resources
        }

        notifications = {
          resources = var.argocd_notifications_resources
        }

      })
    ]

    set_sensitive = [
      # Argo CD admin password (bcrypt)
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      },


      # External Redis password from Secrets Manager. Must be plaintext since it's passed to the external Redis.
      # {
      #   name  = "externalRedis.password"
      #   value = random_password.argocd_redis_auth_password.result
      # }
    ]
  }

  apps = {
    bootstrap = {
      name      = "app-of-apps"
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repo_url        = "https://github.com/KylerLoucks/k8s-platform.git"
          target_revision = "main"
          path            = "argocd/bootstrap/${var.environment}/apps"
        }
      ]
      destination_namespace = "argocd"
      destination_server    = "https://kubernetes.default.svc"
      prune                 = true
      self_heal             = true
      sync_options = [
        "CreateNamespace=true",
        "ApplyOutOfSyncOnly=true",
        "PrunePropagationPolicy=foreground",
        "ServerSideApply=true",
      ]
    }
  }

  repositories = {
    platform = {
      repo       = "https://github.com/KylerLoucks/k8s-platform.git"
      project    = "default"
      enable_lfs = false
      insecure   = false
    }
  }

  depends_on = [
    module.eks,
    helm_release.alb_controller,
  ]
}

# Explicit Argo CD ingress manifest (ALB path-based route on /argocd).
resource "kubernetes_ingress_v1" "argocd_alb" {
  metadata {
    name      = "argocd-server-alb"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"              = "alb"
      "alb.ingress.kubernetes.io/scheme"         = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"    = "ip"
      "alb.ingress.kubernetes.io/listen-ports"   = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/group.name"     = "platform-dev-us"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/argocd/healthz"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/argocd"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.argocd,
    helm_release.alb_controller,
  ]
}


################################################################################
# ArgoCD ExternalRedis Auth credentials with Secrets Manager
################################################################################
# resource "random_password" "argocd_redis_auth_password" {
#   length  = 32
#   special = false
# }

# resource "aws_secretsmanager_secret" "argocd_redis_auth" {
#   name                    = "argocd/redis-auth-token"
#   recovery_window_in_days = 0 # Set to zero to force delete during Terraform destroy
#   description             = "Auth token for ArgoCD Redis"


#   tags = {
#     Environment = var.environment
#     Owner       = var.environment
#     ManagedBy   = "terraform"
#     SecretType  = "redis-auth"
#   }
# }

# resource "aws_secretsmanager_secret_version" "argocd_redis_auth" {
#   secret_id = aws_secretsmanager_secret.argocd_redis_auth.id
#   secret_string = jsonencode({
#     redis-password = random_password.argocd_redis_auth_password.result
#     redis-username = "default"
#   })
# }



################################################################################
# ArgoCD External Redis
################################################################################
# module "argocd_external_redis" {
#   source  = "terraform-aws-modules/elasticache/aws"
#   version = "1.10.3"

#   replication_group_id = var.argocd_external_redis_replication_group_id

#   engine_version = var.external_redis_engine_version
#   node_type      = var.external_redis_node_type

#   # Auth token (requires transit encryption to be enabled)
#   transit_encryption_enabled = true
#   auth_token                 = random_password.argocd_redis_auth_password.result
#   # Don't destroy the Redis cluster when the auth token is updated
#   auth_token_update_strategy = var.external_redis_auth_token_update_strategy

#   multi_az_enabled   = var.external_redis_multi_az_enabled
#   maintenance_window = var.external_redis_maintenance_window

#   # Don't wait for the maintenance window to apply the changes
#   apply_immediately = var.external_redis_apply_immediately



#   # Single node group and no replicas
#   num_node_groups         = var.external_redis_num_node_groups
#   replicas_per_node_group = var.external_redis_replicas_per_node_group

#   # Security group
#   vpc_id                = module.vpc.vpc_id
#   create_security_group = false
#   security_group_ids = [
#     aws_security_group.argocd_external_redis.id
#   ]

#   # Subnet Group
#   subnet_ids = module.vpc.database_subnets

#   # Parameter Group
#   create_parameter_group = true
#   parameter_group_family = "redis7"
#   parameters = [
#     {
#       name  = "latency-tracking"
#       value = "yes"
#     }
#   ]

#   tags = {
#     Terraform   = "true"
#     Environment = var.environment
#   }
# }


# # Security Group for ElastiCache Redis replication groups
# resource "aws_security_group" "argocd_external_redis" {
#   name_prefix = "argocd-external-redis-"
#   vpc_id      = module.vpc.vpc_id
#   description = "Security group for ArgoCD External Redis replication groups"

#   ingress {
#     description = "Redis traffic from EKS (Fargate + nodes)"
#     from_port   = 6379
#     to_port     = 6379
#     protocol    = "tcp"
#     security_groups = [
#       module.eks.cluster_primary_security_group_id,
#       module.eks.node_security_group_id
#     ]
#   }

#   # Allow Redis access from EKS cluster
#   egress {
#     description = "Outbound to VPC"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = [module.vpc.vpc_cidr_block]
#   }

#   tags = {
#     Name        = "argocd-external-redis-sg"
#     Environment = var.environment
#     Purpose     = "ArgoCD External Redis access"
#   }

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# # Output the ElastiCache security group ID for use in ElastiCache charts
# output "argocd_external_redis_security_group_id" {
#   description = "ID of the security group for ArgoCD External Redis replication groups"
#   value       = aws_security_group.argocd_external_redis.id
# }


# output "external_redis_endpoint" {
#   value = module.argocd_external_redis.replication_group_primary_endpoint_address
# }

# output "external_redis_port" {
#   value = module.argocd_external_redis.replication_group_port
# }