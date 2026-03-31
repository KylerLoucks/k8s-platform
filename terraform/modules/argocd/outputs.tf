output "argocd" {
  description = "Argocd helm release"
  value       = try(helm_release.argocd[0], null)
}