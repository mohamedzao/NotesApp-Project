# Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "postgres-pvc"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }
  
  spec {
    access_modes = ["ReadWriteOnce"]
    
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# ConfigMap pour init DB
resource "kubernetes_config_map" "db_init" {
  metadata {
    name      = "db-init-script"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }
  
  data = {
    "init.sql" = <<-EOT
      CREATE TABLE IF NOT EXISTS notes (
        id SERIAL PRIMARY KEY,
        text TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    EOT
  }
}

# Déploiement PostgreSQL
resource "kubernetes_deployment" "db" {
  metadata {
    name      = "notes-db"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
    labels = {
      app = "notes-db"
    }
  }

  spec {
    replicas = 1
    
    selector {
      match_labels = {
        app = "notes-db"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "notes-db"
        }
      }
      
      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"
          
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.db_password
          }
          
          env {
            name  = "POSTGRES_DB"
            value = "notesdb"
          }
          
          port {
            container_port = 5432
          }
          
          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }
          
          volume_mount {
            name       = "init-script"
            mount_path = "/docker-entrypoint-initdb.d"
          }
          
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
          
          liveness_probe {
            tcp_socket {
              port = 5432
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
        
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata[0].name
          }
        }
        
        volume {
          name = "init-script"
          config_map {
            name = kubernetes_config_map.db_init.metadata[0].name
          }
        }
      }
    }
  }
}

# Service Database
resource "kubernetes_service" "db" {
  metadata {
    name      = "notes-db"
    namespace = kubernetes_namespace.notesapp.metadata[0].name
  }
  
  spec {
    selector = {
      app = "notes-db"
    }
    
    port {
      port        = 5432
      target_port = 5432
    }
    
    type = "ClusterIP"
  }
}
