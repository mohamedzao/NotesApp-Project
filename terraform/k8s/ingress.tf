resource "kubernetes_ingress_v1" "notesapp" {
  metadata {
    name      = "notesapp-ingress"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
    
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "false"
    }
  }
  
  spec {
    ingress_class_name = "nginx"
    
    rule {
      host = var.ingress_host
      
      http {
        path {
          path = "/"
          path_type = "Prefix"
          
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
          path_type = "Prefix"
          
          backend {
            service {
              name = kubernetes_service.api.metadata[0].name
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}
