output "ingress_url" {
  description = "URL d'accès à l'application"
  value       = "http://notes.${var.minikube_ip}.nip.io"
}

output "application_status" {
  description = "Statut de l'application"
  value       = "Déployée sur Minikube - Accès via http://notes.${var.minikube_ip}.nip.io"
}
