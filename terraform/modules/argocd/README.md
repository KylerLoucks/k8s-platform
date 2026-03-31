# Argo CD Terraform Module

This module installs Argo CD into a Kubernetes cluster via Helm, optionally registers external clusters with the Argo CD control plane, and manages one or more `argocd_application` resources (commonly used for an App-of-Apps bootstrap). It wraps the [`argocd_application` resource](https://registry.terraform.io/providers/argoproj-labs/argocd/7.11.2/docs/resources/application#nestedblock--spec--source) so you can mix Git, Helm, Kustomize, and multi-source setups without rewriting boilerplate.

## Features

- Deploys Argo CD using the upstream Helm chart with full access to Helm arguments.
- Registers additional Kubernetes clusters through the `argocd_cluster` provider resource.
- Exposes an `apps` map that can express:
  - Single Git/Kustomize sources.
  - Helm charts with their nested Helm options.
  - Multi-source applications (e.g., chart + external values repo) by passing multiple `sources` entries.
- Supports `ignore_difference` blocks to silence drift on generated fields.

Inputs are declared in `variables.tf`; see `terraform/k3d/main.tf` for an end-to-end usage example.

## Configure GitHub Deploy Key

Use an SSH deploy key when Argo CD needs to read private Git repositories. The steps below create a dedicated keypair and register it with GitHub:

1. Generate the keypair (leave the passphrase empty; Argo CD cannot unlock keys that require one):
   ```
   ssh-keygen -t ed25519 -C "ArgoCD GitHub deploy key" -f ~/.ssh/argocd_ed25519
   ```
2. Grab the public key value you need to paste into GitHub:
   ```
   cat ~/.ssh/argocd_ed25519.pub
   ```
3. In GitHub, open the repository, go to **Settings → Deploy Keys**, click **Add deploy key**, set **Title** to `argocd`, and paste the public key into the **Key** textbox. Enable **Allow write access** only if Argo CD must push.
4. The private key remains on disk for Terraform/Argo CD to use:
   ```
   cat ~/.ssh/argocd_ed25519
   ```

> Keep the private key file readable only by the user running Terraform (`chmod 600 ~/.ssh/argocd_ed25519`).

## Passing Module Inputs (Argo CD + Repositories)

```hcl
module "argocd" {
  source = "../modules/argocd"

  argocd = {
    name             = "argo-cd"
    namespace        = "argocd"
    create_namespace = true
    chart_version    = "9.1.1"
    repository       = "https://argoproj.github.io/argo-helm"
    values = [
      yamlencode({
        server = {
          service = {
            type = "ClusterIP"
          }
        }
      })
    ]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argocd_admin.id
      }
    ]
  }

  repositories = {
    # Git repo via ssh Deploy Key
    my_repo = {
      repo            = "git@github.com:<git-org>/<my-repo>.git"
      project         = "default"
      enable_lfs      = true
      insecure        = false
      ssh_private_key = file("~/.ssh/argocd_ed25519")
    }

    # Git repo via Github App
    my_repo = {
      # Must use https instead of SSH with GH Apps
      repo            = "https://github.com/<git-org>/<my-repo>.git"
      project         = "default"
      enable_lfs      = false
      insecure        = false

      github_app_id              = "2393963"
      github_app_installation_id = "97557408"
      github_app_private_key     = file("~/.ssh/argoapp-private-key.pem") # Github App Secret
    }

    # Github container registry repo
    ghcr_helm_repo = {
      repo = "ghcr.io/<git-org>/charts"
      type = "helm"
      name = "ghcr-charts"

      enable_oci = true
      username   = data.sops_file.secrets.data["github_oci_user"]  # username used to auth
      password   = data.sops_file.secrets.data["github_oci_token"] # access token

      project  = "default"
      insecure = false
    }
  }

  apps = {
    bootstrap = {
      name                 = "app-of-apps"
      namespace            = "argocd"
      project              = "default"
      target_revision      = "main"
      destination_server   = "https://kubernetes.default.svc"
      destination_namespace = "argocd"
      sources = [
        {
          repo_url = "git@github.com:<git-org>/<my-repo>.git"
          path     = "argocd/bootstrap"
        }
      ]
    }
  }
}
```

The `repositories` map wires Argo CD to the SSH deploy key you created earlier, while the `argocd` block controls the Helm release and `apps` describes the desired `argocd_application` resources.

## Apps Examples

### Kustomize App-of-Apps

```hcl
module "argocd" {
  source = "../modules/argocd"

  apps = {
    management = {
      name      = "app-of-apps"
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repo_url        = "https://github.com/<git-org>/<my-repo>.git"
          target_revision = "main"
          path            = "argocd/bootstrap/management"
          kustomize = {
            name_prefix = "mgmt-"
          }
        }
      ]
      destination_namespace = "argocd"
      destination_server    = "https://kubernetes.default.svc"
      prune                 = true
      self_heal             = true
    }
  }
}
```

### Single Helm Source

```hcl
module "argocd" {
  source = "../modules/argocd"

  apps = {
    helm_demo = {
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repo_url        = "https://charts.bitnami.com/bitnami"
          chart           = "nginx"
          target_revision = "15.14.0"
          helm = {
            release_name = "frontend"
            value_files  = ["values.yaml"]
            values = yamlencode({
              service = {
                type = "ClusterIP"
              }
            })
            parameters = [
              {
                name  = "image.tag"
                value = "1.25.0"
              }
            ]
          }
        }
      ]
      destination_namespace = "frontend"
      destination_server    = "https://kubernetes.default.svc"
    }
  }
}
```

### Multi-Source Helm with External Values

```hcl
module "argocd" {
  source = "../modules/argocd"

  apps = {
    wordpress = {
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repo_url        = "https://charts.helm.sh/stable"
          chart           = "wordpress"
          target_revision = "9.0.3"
          helm = {
            value_files = ["$values/envs/prod/values.yaml"]
          }
        },
        {
          repo_url        = "https://github.com/example/platform-config.git"
          target_revision = "main"
          ref             = "values"
        }
      ]
      destination_namespace = "apps"
      destination_server    = "https://kubernetes.default.svc"
      sync_options = [
        "CreateNamespace=true",
        "ApplyOutOfSyncOnly=true",
        "PrunePropagationPolicy=foreground",
      ]
    }
  }
}
```

`$values/...` paths reference other `sources` entries via the `ref` field, matching the Argo CD multi-source pattern documented in the provider reference.

## External Cluster Example

```hcl
module "argocd" {
  source = "../modules/argocd"

  external_clusters = {
    prod = {
      server     = "https://prod-api.example.com"
      name       = "prod"
      namespaces = ["apps", "default"]

      config = {
        bearer_token = var.prod_cluster_token
        tls_client_config = {
          ca_data  = var.prod_cluster_ca_pem
          insecure = false
        }
      }

      metadata = {
        labels = {
          environment   = "prod"
          enable_argocd = true
          cluster_name  = "prod"
        }
        annotations = {}
      }
    }
  }
}
```

The `argocd_cluster` resource uses the supplied CA and bearer token to register remote clusters so ApplicationSets can target them by cluster labels (`enable_argocd`, `environment`, etc.).

## Installing Argo CD with `set_sensitive`

```hcl
resource "bcrypt_hash" "argocd_admin" {
  cleartext = var.argocd_admin_password
}

module "argocd" {
  source = "../modules/argocd"

  argocd = {
    name             = "argo-cd"
    namespace        = "argocd"
    create_namespace = true
    chart_version    = "9.1.1"
    repository       = "https://argoproj.github.io/argo-helm"
    values = [
      yamlencode({
        server = {
          service = {
            type = "ClusterIP"
          }
        }
      })
    ]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argocd_admin.id
      }
    ]
  }
}
```

Sensitive Helm overrides (e.g., hashed admin password) can be passed via `set_sensitive` to avoid leaking secrets into state files or logs while still templating the chart through Terraform.


