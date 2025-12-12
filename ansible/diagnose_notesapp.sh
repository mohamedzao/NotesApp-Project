#!/bin/bash

# Script pour diagnostiquer et corriger les problèmes de déploiement NotesApp

set -e

echo "🔍 Diagnostic du déploiement NotesApp..."
echo "=========================================="

# 1. Vérifier Minikube
echo ""
echo "1. Vérification Minikube:"
minikube status
echo ""

# 2. Vérifier les addons
echo "2. Vérification des addons:"
minikube addons list | grep -E "(ingress|metallb)"
echo ""

# 3. Vérifier MetalLB
echo "3. Vérification MetalLB:"
kubectl get pods -n metallb-system
kubectl get configmap -n metallb-system
echo ""

# 4. Vérifier les images Docker dans Minikube
echo "4. Vérification des images Docker dans Minikube:"
eval $(minikube docker-env)
docker images | grep -E "(notes-frontend|notes-api)"
echo ""

# 5. Vérifier le répertoire Terraform
echo "5. Vérification du répertoire Terraform:"
cd /mnt/c/users/acer-/downloads/NotesApp-Project/terraform
pwd
ls -la
echo ""

# 6. Vérifier les fichiers Terraform
echo "6. Fichiers Terraform présents:"
ls -la *.tf 2>/dev/null || echo "Aucun fichier .tf trouvé"
echo ""

# 7. Initialiser et appliquer Terraform manuellement
echo "7. Exécution manuelle de Terraform:"
if [ -f "main.tf" ] || [ -f "*.tf" ]; then
    echo "Initialisation Terraform..."
    terraform init
    
    echo ""
    echo "Plan Terraform..."
    terraform plan
    
    echo ""
    echo "Application Terraform..."
    terraform apply -auto-approve
else
    echo "❌ Aucun fichier Terraform trouvé dans le répertoire!"
    
    # Créer une configuration Terraform minimaliste
    echo "Création d'une configuration Terraform minimale..."
    cat > main.tf << 'EOF'
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "kubernetes_namespace" "notesapp" {
  metadata {
    name = "notesapp"
  }
}

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "notes-frontend"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "notes-frontend"
      }
    }

    template {
      metadata {
        labels = {
          app = "notes-frontend"
        }
      }

      spec {
        container {
          image = "notes-frontend:latest"
          name  = "frontend"

          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name      = "notes-frontend"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }

  spec {
    selector = {
      app = "notes-frontend"
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "api" {
  metadata {
    name      = "notes-api"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "notes-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "notes-api"
        }
      }

      spec {
        container {
          image = "notes-api:latest"
          name  = "api"

          port {
            container_port = 5000
          }

          env {
            name  = "DATABASE_URL"
            value = "sqlite:///app/notes.db"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "notes-api"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }

  spec {
    selector = {
      app = "notes-api"
    }

    port {
      port        = 80
      target_port = 5000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "notesapp" {
  metadata {
    name      = "notesapp-ingress"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "notes.$(minikube ip).nip.io"

      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.frontend.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path = "/api"
          backend {
            service {
              name = kubernetes_service.api.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
EOF

    echo "✅ Fichier main.tf créé. Exécution de Terraform..."
    terraform init
    terraform apply -auto-approve
fi

echo ""
echo "8. Vérification finale:"
kubectl get all -n notesapp
echo ""

echo "9. Vérification des événements:"
kubectl get events -n notesapp --sort-by='.lastTimestamp'
echo ""

echo "10. Vérification des logs des pods (si existants):"
kubectl get pods -n notesapp -o name | while read pod; do
    echo "Logs pour $pod:"
    kubectl logs -n notesapp $pod --tail=20 || echo "Impossible de récupérer les logs"
done

echo ""
echo "=========================================="
echo "📝 Résumé des problèmes possibles:"
echo "1. Images Docker non construites (vérifiez avec 'docker images')"
echo "2. Terraform non configuré correctement"
echo "3. Problèmes de réseau avec Minikube"
echo "4. Problèmes de ressources (CPU/mémoire)"
echo ""
echo "🛠️  Commandes de dépannage:"
echo "  minikube status"
echo "  kubectl get all -A"
echo "  kubectl describe namespace notesapp"
echo "  terraform state list"
