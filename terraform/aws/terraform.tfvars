external_redis_auth_token_update_strategy = "ROTATE"
external_redis_node_type                  = "cache.t4g.small"
external_redis_engine_version             = "7.1"
external_redis_multi_az_enabled           = false
external_redis_maintenance_window         = "sun:05:00-sun:09:00"
external_redis_apply_immediately          = true
external_redis_num_node_groups            = 1
external_redis_replicas_per_node_group    = 0 # must be at least 1 for multi-az


rds_db_name               = "platform"
rds_username              = "postgres"
rds_port                  = 5432
rds_identifier            = "platform"
rds_engine                = "postgres"
rds_family                = "postgres17"
rds_major_engine_version  = "17"
rds_engine_version        = "17.4"
rds_instance_class        = "db.t4g.micro"
rds_allocated_storage     = 20
rds_max_allocated_storage = 25
rds_storage_type          = "gp3"
rds_skip_final_snapshot   = true
rds_master_secret_tags = {
  "platform:instance-id" = "platform"
}

# Argo CD repo-server: larger Helm renders + multi-source apps can hit default timeouts under load.
argocd_repo_resources = {
  requests = {
    cpu    = "500m"
    memory = "1Gi"
  }
  limits = {
    cpu    = "2"
    memory = "4Gi"
  }
}