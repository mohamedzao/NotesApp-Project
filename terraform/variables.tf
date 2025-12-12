variable "namespace" {
  description = "Namespace Kubernetes"
  type        = string
  default     = "notesapp"
}

variable "frontend_image" {
  description = "Image Docker du frontend"
  type        = string
  default     = "notes-frontend:latest"
}

variable "backend_image" {
  description = "Image Docker du backend"
  type        = string
  default     = "notes-api:latest"
}

variable "db_password" {
  description = "Mot de passe PostgreSQL"
  type        = string
  default     = "password"
  sensitive   = true
}

variable "minikube_ip" {
  description = "IP de Minikube"
  type        = string
  default     = ""  # Récupéré automatiquement
}
