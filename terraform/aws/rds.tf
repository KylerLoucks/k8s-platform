################################################################################
# RDS PostgreSQL
################################################################################

resource "aws_security_group" "rds" {
  name_prefix = "rds-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for RDS PostgreSQL"

  ingress {
    description     = "Allow access from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_primary_security_group_id]
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.0"

  db_name  = var.rds_db_name
  username = var.rds_username
  port     = var.rds_port

  identifier            = var.rds_identifier
  engine                = var.rds_engine
  family                = var.rds_family
  engine_version        = var.rds_engine_version
  major_engine_version  = var.rds_major_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = var.rds_storage_type
  storage_encrypted     = var.rds_storage_encrypted

  manage_master_user_password                       = true
  manage_master_user_password_rotation              = true
  master_user_password_rotate_immediately           = false
  master_user_password_rotation_schedule_expression = "rate(15 days)"

  multi_az = var.rds_multi_az

  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.rds_backup_retention_period
  skip_final_snapshot     = var.rds_skip_final_snapshot
  deletion_protection     = var.rds_deletion_protection
}

# RDS-managed master secret (tagged for ESO dataFrom.find) only contains username + password.
# Hostname is published separately so External Secrets can merge DB_HOST + credentials into one K8s Secret.
resource "aws_secretsmanager_secret" "rds_host" {
  name        = "platform/${var.environment}/rds-host"
  description = "RDS hostname (JSON key: host). Master credentials use the RDS-managed secret."
}

resource "aws_secretsmanager_secret_version" "rds_host" {
  secret_id = aws_secretsmanager_secret.rds_host.id
  secret_string = jsonencode({
    host = module.rds.db_instance_address
  })
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed master secret (tagged for ESO dataFrom.find)"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "rds_db_instance_identifier" {
  description = "Use as aws:rds:db-instance-id tag value in ExternalSecret dataFrom.find.tags"
  value       = module.rds.db_instance_identifier
}

output "rds_host_secret_name" {
  description = "Secrets Manager secret name for host JSON (use as externalSecret.hostRemoteRef.key in Helm)"
  value       = aws_secretsmanager_secret.rds_host.name
}

# Apply custom tags to the AWS-managed RDS master secret after it is created so ESO can find it.
resource "null_resource" "tag_rds_master_secret" {
  for_each = var.rds_master_secret_tags

  triggers = {
    secret_arn = module.rds.db_instance_master_user_secret_arn
    tag_key    = each.key
    tag_value  = each.value
    region     = data.aws_region.current.region
  }

  provisioner "local-exec" {
    command = "aws secretsmanager tag-resource --secret-id ${self.triggers.secret_arn} --tags Key=${self.triggers.tag_key},Value=${self.triggers.tag_value} --region ${self.triggers.region}"
  }

  depends_on = [module.rds]
}
