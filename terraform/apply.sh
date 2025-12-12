#!/bin/bash

# Récupérer l'adresse IP
IP=$(hostname -I | awk '{print $1}')
echo "Adresse IP détectée: $IP"

# Initialiser Terraform
terraform init

# Appliquer avec les variables
terraform apply -auto-approve \
  -var="ingress_host=notes.${IP}.nip.io" \
  -var="frontend_image=registry.gitlab.com/votre-username/notes-frontend:latest" \
  -var="backend_image=registry.gitlab.com/votre-username/notes-api:latest"

# Afficher les sorties
echo ""
terraform output
