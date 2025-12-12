resource "kubernetes_namespace" "notesapp" {
  metadata {
    name = var.namespace
    labels = {
      app       = "notesapp"
      managed-by = "terraform"
    }
  }
}
