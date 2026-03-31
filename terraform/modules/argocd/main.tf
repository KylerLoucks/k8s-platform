################################################################################
# Install ArgoCD
################################################################################
resource "helm_release" "argocd" {
  count = var.create ? 1 : 0

  name             = try(var.argocd.name, "argocd")
  description      = try(var.argocd.description, "A Helm chart to install ArgoCD")
  namespace        = try(var.argocd.namespace, "argocd")
  create_namespace = try(var.argocd.create_namespace, true)
  chart            = try(var.argocd.chart, "argo-cd")
  version          = try(var.argocd.chart_version, "9.1.1")
  repository       = try(var.argocd.repository, "https://argoproj.github.io/argo-helm")
  values           = try(var.argocd.values, [])

  timeout                    = try(var.argocd.timeout, null)
  repository_key_file        = try(var.argocd.repository_key_file, null)
  repository_cert_file       = try(var.argocd.repository_cert_file, null)
  repository_ca_file         = try(var.argocd.repository_ca_file, null)
  repository_username        = try(var.argocd.repository_username, null)
  repository_password        = try(var.argocd.repository_password, null)
  devel                      = try(var.argocd.devel, null)
  verify                     = try(var.argocd.verify, null)
  keyring                    = try(var.argocd.keyring, null)
  disable_webhooks           = try(var.argocd.disable_webhooks, null)
  reuse_values               = try(var.argocd.reuse_values, null)
  reset_values               = try(var.argocd.reset_values, null)
  force_update               = try(var.argocd.force_update, null)
  recreate_pods              = try(var.argocd.recreate_pods, null)
  cleanup_on_fail            = try(var.argocd.cleanup_on_fail, null)
  max_history                = try(var.argocd.max_history, null)
  atomic                     = try(var.argocd.atomic, null)
  skip_crds                  = try(var.argocd.skip_crds, null)
  render_subchart_notes      = try(var.argocd.render_subchart_notes, null)
  disable_openapi_validation = try(var.argocd.disable_openapi_validation, null)
  wait                       = try(var.argocd.wait, true)
  wait_for_jobs              = try(var.argocd.wait_for_jobs, null)
  dependency_update          = try(var.argocd.dependency_update, null)
  replace                    = try(var.argocd.replace, null)
  lint                       = try(var.argocd.lint, null)

  postrender    = try(var.argocd.postrender, null)
  set           = try(var.argocd.set, [])
  set_sensitive = try(var.argocd.set_sensitive, [])

}

################################################################################
# External clusters registered via ArgoCD provider
################################################################################
resource "argocd_cluster" "external" {
  for_each = var.create ? var.external_clusters : {}

  server     = try(each.value.server, null)
  name       = try(each.value.name, each.key)
  namespaces = try(each.value.namespaces, [])
  project    = try(each.value.project, "default")
  shard      = try(each.value.shard, null)
  metadata {
    labels      = try(each.value.metadata.labels, {})
    annotations = try(each.value.metadata.annotations, {})
  }

  dynamic "config" {
    for_each = [each.value.config]
    content {
      bearer_token = try(config.value.bearer_token, null)
      username     = try(config.value.username, null)
      password     = try(config.value.password, null)

      dynamic "tls_client_config" {
        for_each = try(config.value.tls_client_config, null) == null ? [] : [config.value.tls_client_config]
        content {
          insecure    = try(tls_client_config.value.insecure, false)
          ca_data     = try(tls_client_config.value.ca_data, null)
          cert_data   = try(tls_client_config.value.cert_data, null)
          key_data    = try(tls_client_config.value.key_data, null)
          server_name = try(tls_client_config.value.server_name, null)
        }
      }

      dynamic "aws_auth_config" {
        for_each = try(config.value.aws_auth_config, null) == null ? [] : [config.value.aws_auth_config]
        content {
          cluster_name = try(aws_auth_config.value.cluster_name, null)
          role_arn     = try(aws_auth_config.value.role_arn, null)
        }
      }

      dynamic "exec_provider_config" {
        for_each = try(config.value.exec_provider_config, null) == null ? [] : [config.value.exec_provider_config]
        content {
          api_version  = try(exec_provider_config.value.api_version, null)
          command      = try(exec_provider_config.value.command, null)
          args         = try(exec_provider_config.value.args, null)
          env          = try(exec_provider_config.value.env, null)
          install_hint = try(exec_provider_config.value.install_hint, null)
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}



################################################################################
# App of Apps
################################################################################
resource "argocd_application" "app_of_apps" {
  for_each = var.create ? var.apps : {}

  metadata {
    name        = try(each.value.name, each.key)
    namespace   = try(each.value.namespace, "argocd")
    labels      = try(each.value.labels, {})
    annotations = try(each.value.annotations, {})
  }

  spec {
    project = try(each.value.project, "default")
    dynamic "source" {
      for_each = length(try(each.value.sources, [])) > 0 ? each.value.sources : [
        merge(
          {
            repo_url        = each.value.repo_url
            target_revision = try(each.value.target_revision, "main")
            path            = try(each.value.path, null)
            chart           = try(each.value.chart, null)
            ref             = try(each.value.ref, null)
            name            = try(each.value.source_name, null)
          },
          try(each.value.source, {})
        )
      ]

      content {
        repo_url        = source.value.repo_url
        target_revision = try(source.value.target_revision, try(each.value.target_revision, "main"))
        path            = try(source.value.path, null)
        chart           = try(source.value.chart, null)
        ref             = try(source.value.ref, null)
        name            = try(source.value.name, null)

        dynamic "helm" {
          for_each = lookup(source.value, "helm", null) == null ? [] : [lookup(source.value, "helm", null)]
          content {
            release_name               = try(helm.value.release_name, null)
            version                    = try(helm.value.version, null)
            pass_credentials           = try(helm.value.pass_credentials, null)
            skip_crds                  = try(helm.value.skip_crds, null)
            ignore_missing_value_files = try(helm.value.ignore_missing_value_files, null)
            value_files                = try(helm.value.value_files, null)
            values                     = try(helm.value.values, null)

            dynamic "parameter" {
              for_each = try(helm.value.parameters, [])
              content {
                name         = try(parameter.value.name, null)
                value        = try(parameter.value.value, null)
                force_string = try(parameter.value.force_string, null)
              }
            }

            dynamic "file_parameter" {
              for_each = try(helm.value.file_parameters, [])
              content {
                name = try(file_parameter.value.name, null)
                path = try(file_parameter.value.path, null)
              }
            }
          }
        }

        dynamic "kustomize" {
          for_each = lookup(source.value, "kustomize", null) == null ? [] : [lookup(source.value, "kustomize", null)]
          content {
            name_prefix        = try(kustomize.value.name_prefix, null)
            name_suffix        = try(kustomize.value.name_suffix, null)
            version            = try(kustomize.value.version, null)
            common_labels      = try(kustomize.value.common_labels, null)
            common_annotations = try(kustomize.value.common_annotations, null)
            images             = try(kustomize.value.images, null)
          }
        }
      }
    }
    destination {
      server    = try(each.value.destination_server, null)
      namespace = try(each.value.destination_namespace, "argocd")
      name      = try(each.value.destination_name, null)
    }
    sync_policy {
      automated {
        prune     = try(each.value.prune, true)
        self_heal = try(each.value.self_heal, true)
      }
      sync_options = try(each.value.sync_options, ["CreateNamespace=true", "ApplyOutOfSyncOnly=true", "PrunePropagationPolicy=foreground"])
    }
    dynamic "ignore_difference" {
      for_each = try(each.value.ignore_differences, {})
      content {
        group         = try(ignore_difference.value.group, null)
        kind          = try(ignore_difference.value.kind, null)
        name          = try(ignore_difference.value.name, null)
        namespace     = try(ignore_difference.value.namespace, null)
        json_pointers = try(ignore_difference.value.json_pointers, null)
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    argocd_cluster.external,
    argocd_repository.repository
  ]
}


################################################################################
# ArgoCD Repositories
# Generates secret in ArgoCD namespace for access to private git/helm repositories
################################################################################
resource "argocd_repository" "repository" {
  for_each = var.create ? var.repositories : {}
  name = try(each.value.name, null)
  repo = try(each.value.repo, null)

  bearer_token    = try(each.value.bearer_token, null)
  type            = try(each.value.type, "git")
  username        = try(each.value.username, null)
  password        = try(each.value.password, null)
  ssh_private_key = try(each.value.ssh_private_key, null)
  insecure        = try(each.value.insecure, false)
  enable_lfs      = try(each.value.enable_lfs, true)
  project         = try(each.value.project, "default")

  # Use GitHub App authentication if provided
  githubapp_id              = try(each.value.github_app_id, null)
  githubapp_installation_id = try(each.value.github_app_installation_id, null)
  githubapp_private_key     = try(each.value.github_app_private_key, null)

  # Helm repository Settings
  enable_oci = try(each.value.enable_oci, false)

  tls_client_cert_data = try(each.value.tls_client_cert_data, null)
  tls_client_cert_key  = try(each.value.tls_client_cert_key, null)

  depends_on = [helm_release.argocd]
}
