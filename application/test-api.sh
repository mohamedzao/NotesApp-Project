#!/bin/bash

echo "🧪 Test de l'API NotesApp..."
echo "=============================="

# Attendre que les services soient prêts
echo "⏳ Attente des services..."
sleep 10

# Test 1: Santé de l'API
echo "1. Test santé API:"
curl -s http://localhost:5000/health | jq . || curl -s http://localhost:5000/health

echo ""
echo "2. Test endpoint /notes:"
curl -s http://localhost:5000/notes | jq . || curl -s http://localhost:5000/notes

echo ""
echo "3. Test ajout de note:"
curl -s -X POST http://localhost:5000/add \
  -H "Content-Type: application/json" \
  -d '{"text":"Note de test via script"}' | jq . || \
curl -s -X POST http://localhost:5000/add \
  -H "Content-Type: application/json" \
  -d '{"text":"Note de test via script"}'

echo ""
echo "4. Vérification des notes:"
curl -s http://localhost:5000/notes | jq . || curl -s http://localhost:5000/notes

echo ""
echo "✅ Tests terminés!"
