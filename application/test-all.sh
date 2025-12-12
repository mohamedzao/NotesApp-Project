#!/bin/bash

echo "🧪 Test complet de NotesApp"
echo "============================="
echo ""

cd application

# 1. Vérifier l'état des conteneurs
echo "1. 📊 État des conteneurs:"
docker-compose ps
echo ""

# 2. Attendre un peu
echo "2. ⏳ Attente du démarrage complet..."
sleep 10
echo ""

# 3. Tester la base de données
echo "3. 🗄️  Test PostgreSQL:"
docker-compose exec db pg_isready -U postgres
echo ""

# 4. Tester l'API Flask
echo "4. 🔧 Test API Flask:"
echo "   Santé:"
curl -s http://localhost:5000/health | jq . || curl -s http://localhost:5000/health
echo ""
echo "   Test endpoint:"
curl -s http://localhost:5000/test | jq . || curl -s http://localhost:5000/test
echo ""

# 5. Tester les notes
echo "5. 📝 Test des notes:"
echo "   Liste des notes:"
curl -s http://localhost:5000/notes | jq . || curl -s http://localhost:5000/notes
echo ""
echo "   Ajout d'une note:"
curl -s -X POST http://localhost:5000/add \
  -H "Content-Type: application/json" \
  -d '{"text":"Note de test depuis le script"}' | jq . || \
curl -s -X POST http://localhost:5000/add \
  -H "Content-Type: application/json" \
  -d '{"text":"Note de test depuis le script"}'
echo ""
echo "   Vérification:"
curl -s http://localhost:5000/notes | jq . || curl -s http://localhost:5000/notes
echo ""

# 6. Tester le frontend
echo "6. 🌐 Test frontend:"
echo "   Vérification HTTP:"
curl -I http://localhost 2>/dev/null | head -1 || echo "   Frontend non accessible"
echo ""

# 7. Afficher les logs récents
echo "7. 📋 Logs récents:"
echo "   Backend:"
docker-compose logs backend --tail=5 2>/dev/null | tail -5 || echo "   Logs non disponibles"
echo ""
echo "   Database:"
docker-compose logs db --tail=3 2>/dev/null | tail -3 || echo "   Logs non disponibles"
echo ""

echo "✅ Tests terminés!"
echo ""
echo "🌐 Accès:"
echo "   Frontend:  http://localhost"
echo "   API:       http://localhost:5000"
echo "   PostgreSQL: localhost:5433"
echo ""
echo "📋 Commandes utiles:"
echo "   docker-compose logs -f backend  # Suivre les logs"
echo "   docker-compose restart backend  # Redémarrer"
echo "   ./test-all.sh                   # Retester"
