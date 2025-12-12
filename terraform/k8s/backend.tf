resource "kubernetes_deployment" "api" {
  metadata {
    name      = "notes-api"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
    labels = {
      app = "notes-api"
    }
  }

  spec {
    replicas = 2
    
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
          name  = "api"
          image = var.backend_image
          
          env {
            name  = "DB_HOST"
            value = "notes-db"
          }
          
          env {
            name  = "DB_NAME"
            value = "notesdb"
          }
          
          env {
            name  = "DB_USER"
            value = "postgres"
          }
          
          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
          
          env {
            name  = "FLASK_ENV"
            value = "production"
          }
          
          port {
            container_port = 5000
          }
          
          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "250m"
            }
          }
          
          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
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
      port        = 5000
      target_port = 5000
    }
    
    type = "ClusterIP"
  }
}
