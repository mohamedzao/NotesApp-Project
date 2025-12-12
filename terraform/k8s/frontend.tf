resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "notes-frontend"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
    labels = {
      app = "notes-frontend"
    }
  }

  spec {
    replicas = 2
    
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
          name  = "frontend"
          image = var.frontend_image
          
          port {
            container_port = 80
          }
          
          resources {
            requests = {
              memory = "64Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "128Mi"
              cpu    = "100m"
            }
          }
          
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
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
      target_port = 80
    }
    
    type = "ClusterIP"
  }
}
