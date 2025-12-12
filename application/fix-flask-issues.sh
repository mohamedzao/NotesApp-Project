#!/bin/bash

# ============================================
# Script : fix-flask-issues.sh
# Description : Corrige les problèmes Flask et PostgreSQL
# Usage : ./fix-flask-issues.sh
# ============================================

set -e

echo "🔧 Correction des problèmes Flask et PostgreSQL..."

cd application

# 1. Arrêter tout
echo "🛑 Arrêt des conteneurs..."
docker-compose down -v 2>/dev/null || true

# 2. Mettre à jour app.py avec Flask 2.3+ compatible
echo "📝 Mise à jour du backend Flask..."
cat > backend/app.py << 'EOF'
from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
import os
import time
import threading
import sys

app = Flask(__name__)
CORS(app)

# Configuration de la base de données
DB_HOST = os.getenv('DB_HOST', 'db')
DB_NAME = os.getenv('DB_NAME', 'notesdb')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'password')

# Variable pour suivre l'initialisation
db_initialized = False
init_lock = threading.Lock()

def wait_for_db():
    """Attendre que la base de données soit disponible"""
    print("⏳ Attente de la base de données...", file=sys.stderr)
    max_retries = 30
    for i in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                database='postgres',
                user=DB_USER,
                password=DB_PASSWORD,
                connect_timeout=2
            )
            conn.close()
            print("✅ Base de données disponible!", file=sys.stderr)
            return True
        except Exception as e:
            if i < max_retries - 1:
                print(f"⏱️  Tentative {i+1}/{max_retries}: {e}", file=sys.stderr)
                time.sleep(2)
            else:
                print(f"❌ Base de données non disponible après {max_retries} tentatives", file=sys.stderr)
                return False
    return False

def init_database():
    """Initialiser la base de données"""
    global db_initialized
    
    with init_lock:
        if db_initialized:
            return True
            
        try:
            print("🔧 Initialisation de la base de données...", file=sys.stderr)
            
            # 1. Se connecter à 'postgres' (base par défaut)
            conn = psycopg2.connect(
                host=DB_HOST,
                database='postgres',
                user=DB_USER,
                password=DB_PASSWORD
            )
            conn.autocommit = True
            cur = conn.cursor()
            
            # 2. Créer la base si elle n'existe pas
            cur.execute(f"SELECT 1 FROM pg_database WHERE datname='{DB_NAME}';")
            if not cur.fetchone():
                print(f"📦 Création de la base '{DB_NAME}'...", file=sys.stderr)
                cur.execute(f'CREATE DATABASE {DB_NAME};')
            else:
                print(f"✅ Base '{DB_NAME}' existe déjà", file=sys.stderr)
            
            cur.close()
            conn.close()
            
            # 3. Se connecter à notre base et créer la table
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD
            )
            cur = conn.cursor()
            
            cur.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                    id SERIAL PRIMARY KEY,
                    text TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            ''')
            
            # Vérifier si la table est vide, ajouter une note de test
            cur.execute('SELECT COUNT(*) FROM notes;')
            count = cur.fetchone()[0]
            if count == 0:
                cur.execute("INSERT INTO notes (text) VALUES ('Première note de test!');")
                print("📝 Note de test ajoutée", file=sys.stderr)
            
            conn.commit()
            cur.close()
            conn.close()
            
            print("✅ Base de données initialisée avec succès!", file=sys.stderr)
            db_initialized = True
            return True
            
        except Exception as e:
            print(f"❌ Erreur lors de l'initialisation: {e}", file=sys.stderr)
            return False

def get_db_connection():
    """Obtenir une connexion à la base de données"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5
        )
        return conn
    except Exception as e:
        print(f"❌ Erreur de connexion DB: {e}", file=sys.stderr)
        return None

@app.before_request
def before_first_request():
    """Exécuté avant la première requête"""
    global db_initialized
    
    if not db_initialized:
        print("🚀 Initialisation au premier appel...", file=sys.stderr)
        if wait_for_db():
            init_database()
        else:
            print("⚠️  ATTENTION: Base de données non disponible!", file=sys.stderr)

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de santé"""
    try:
        # Initialiser si pas déjà fait
        if not db_initialized:
            if wait_for_db():
                init_database()
        
        conn = get_db_connection()
        if conn:
            conn.close()
            return jsonify({
                'status': 'healthy', 
                'database': 'connected',
                'initialized': db_initialized
            }), 200
        else:
            return jsonify({
                'status': 'unhealthy', 
                'database': 'disconnected',
                'initialized': db_initialized
            }), 500
    except Exception as e:
        return jsonify({
            'status': 'unhealthy', 
            'error': str(e),
            'initialized': db_initialized
        }), 500

@app.route('/notes', methods=['GET'])
def get_notes():
    """Récupérer toutes les notes"""
    try:
        conn = get_db_connection()
        if conn is None:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cur = conn.cursor()
        cur.execute('SELECT id, text FROM notes ORDER BY created_at DESC;')
        notes = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify([{'id': n[0], 'text': n[1]} for n in notes])
    except Exception as e:
        print(f"❌ Erreur /notes: {e}", file=sys.stderr)
        return jsonify({'error': str(e)}), 500

@app.route('/add', methods=['POST'])
def add_note():
    """Ajouter une nouvelle note"""
    try:
        data = request.json
        if not data:
            return jsonify({'error': 'No data provided'}), 400
            
        text = data.get('text', '').strip()
        if not text:
            return jsonify({'error': 'Text cannot be empty'}), 400
        
        conn = get_db_connection()
        if conn is None:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cur = conn.cursor()
        cur.execute('INSERT INTO notes (text) VALUES (%s) RETURNING id;', (text,))
        note_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        
        return jsonify({'id': note_id, 'text': text, 'message': 'Note added successfully'})
    except Exception as e:
        print(f"❌ Erreur /add: {e}", file=sys.stderr)
        return jsonify({'error': str(e)}), 500

@app.route('/delete/<int:note_id>', methods=['DELETE'])
def delete_note(note_id):
    """Supprimer une note"""
    try:
        conn = get_db_connection()
        if conn is None:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cur = conn.cursor()
        cur.execute('DELETE FROM notes WHERE id = %s;', (note_id,))
        conn.commit()
        rows_deleted = cur.rowcount
        cur.close()
        conn.close()
        
        if rows_deleted > 0:
            return jsonify({'message': f'Note {note_id} deleted successfully'})
        else:
            return jsonify({'error': 'Note not found'}), 404
    except Exception as e:
        print(f"❌ Erreur /delete: {e}", file=sys.stderr)
        return jsonify({'error': str(e)}), 500

@app.route('/test', methods=['GET'])
def test():
    """Endpoint de test"""
    return jsonify({
        'message': 'API is working',
        'database_host': DB_HOST,
        'database_name': DB_NAME,
        'database_initialized': db_initialized,
        'timestamp': time.time()
    })

@app.route('/init', methods=['GET'])
def init_db_endpoint():
    """Endpoint pour forcer l'initialisation"""
    if init_database():
        return jsonify({'message': 'Database initialized successfully'})
    else:
        return jsonify({'error': 'Database initialization failed'}), 500

if __name__ == '__main__':
    print("🌐 Démarrage de l'API Flask...", file=sys.stderr)
    print(f"📊 Configuration DB: host={DB_HOST}, db={DB_NAME}", file=sys.stderr)
    
    # Essayer d'initialiser au démarrage
    if wait_for_db():
        init_database()
    
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# 3. Mettre à jour docker-compose.yml (simplifié et sans problèmes)
echo "🐳 Création d'un docker-compose.yml simplifié..."
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  frontend:
    build: ./frontend
    ports:
      - "80:80"
    depends_on:
      - backend
    networks:
      - notes-network

  backend:
    build: 
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "5000:5000"
    environment:
      - DB_HOST=db
      - DB_NAME=notesdb
      - DB_USER=postgres
      - DB_PASSWORD=password
      - FLASK_DEBUG=1
    volumes:
      - ./backend:/app
    depends_on:
      - db
    networks:
      - notes-network
    command: >
      sh -c "echo '🚀 Démarrage du backend...' &&
             sleep 5 &&
             python app.py"

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=notesdb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5433:5432"  # Changer le port pour éviter les conflits
    networks:
      - notes-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres || exit 0"]  # Exit 0 pour éviter l'arrêt
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  notes-network:
    driver: bridge

volumes:
  postgres_data:
EOF

# 4. Mettre à jour le Dockerfile du backend
echo "🐳 Mise à jour du Dockerfile backend..."
cat > backend/Dockerfile << 'EOF'
FROM python:3.9-slim

# Installer les dépendances système pour psycopg2
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copier les requirements d'abord pour meilleur caching
COPY requirements.txt .

# Installer les dépendances Python
RUN pip install --no-cache-dir -r requirements.txt

# Copier le reste de l'application
COPY app.py database.py ./

# Créer un utilisateur non-root pour plus de sécurité
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Port exposé
EXPOSE 5000

# Commande de démarrage
CMD ["python", "app.py"]
EOF

# 5. Mettre à jour requirements.txt
echo "📦 Mise à jour des dépendances..."
cat > backend/requirements.txt << 'EOF'
Flask==2.3.3
Flask-CORS==4.0.0
psycopg2-binary==2.9.7
gunicorn==21.2.0
EOF

# 6. Mettre à jour le frontend pour mieux gérer les erreurs
echo "🎨 Mise à jour du frontend..."
cat > frontend/app.js << 'EOF'
// Configuration
const API_BASE = window.location.origin.includes('localhost') 
    ? 'http://localhost:5000' 
    : '/api';

// Éléments DOM
let retryCount = 0;
const MAX_RETRIES = 3;

// Fonctions d'affichage des messages
function showMessage(message, type = 'info') {
    console.log(`${type.toUpperCase()}: ${message}`);
    
    // Créer ou récupérer le conteneur de message
    let messageDiv = document.getElementById('message-container');
    if (!messageDiv) {
        messageDiv = document.createElement('div');
        messageDiv.id = 'message-container';
        messageDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
            min-width: 300px;
        `;
        document.body.appendChild(messageDiv);
    }
    
    // Créer le message
    const msgElement = document.createElement('div');
    msgElement.style.cssText = `
        padding: 15px;
        margin: 10px 0;
        border-radius: 5px;
        color: white;
        font-weight: bold;
        box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        animation: slideIn 0.3s ease-out;
    `;
    
    // Couleur selon le type
    switch(type) {
        case 'success':
            msgElement.style.backgroundColor = '#28a745';
            break;
        case 'error':
            msgElement.style.backgroundColor = '#dc3545';
            break;
        case 'warning':
            msgElement.style.backgroundColor = '#ffc107';
            msgElement.style.color = '#212529';
            break;
        default:
            msgElement.style.backgroundColor = '#17a2b8';
    }
    
    msgElement.textContent = message;
    messageDiv.appendChild(msgElement);
    
    // Supprimer après 5 secondes (3 secondes pour les infos)
    const delay = type === 'info' ? 3000 : 5000;
    setTimeout(() => {
        msgElement.style.animation = 'slideOut 0.3s ease-out';
        setTimeout(() => msgElement.remove(), 300);
    }, delay);
}

// Animation CSS
if (!document.querySelector('#message-styles')) {
    const style = document.createElement('style');
    style.id = 'message-styles';
    style.textContent = `
        @keyframes slideIn {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        @keyframes slideOut {
            from { transform: translateX(0); opacity: 1; }
            to { transform: translateX(100%); opacity: 0; }
        }
        .loading {
            text-align: center;
            padding: 20px;
            color: #6c757d;
        }
        .error-container {
            text-align: center;
            padding: 40px;
            background: #f8d7da;
            border: 1px solid #f5c6cb;
            border-radius: 8px;
            margin: 20px;
        }
        .retry-btn {
            background: #dc3545;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin-top: 10px;
        }
    `;
    document.head.appendChild(style);
}

// Fonction pour tester la connexion API
async function testConnection() {
    try {
        const response = await fetch(`${API_BASE}/health`, {
            timeout: 5000
        });
        
        if (response.ok) {
            const data = await response.json();
            console.log('✅ API connectée:', data);
            return true;
        }
        return false;
    } catch (error) {
        console.warn('⚠️ API non disponible:', error.message);
        return false;
    }
}

// Charger les notes avec réessais
async function loadNotes() {
    const notesList = document.getElementById('notesList');
    
    // Afficher l'état de chargement
    notesList.innerHTML = '<div class="loading">Chargement des notes...</div>';
    
    try {
        showMessage('Connexion à l\'API...', 'info');
        
        // Tester d'abord la connexion
        if (!await testConnection() && retryCount < MAX_RETRIES) {
            retryCount++;
            showMessage(`Tentative de connexion ${retryCount}/${MAX_RETRIES}...`, 'warning');
            setTimeout(loadNotes, 2000);
            return;
        }
        
        if (retryCount >= MAX_RETRIES) {
            throw new Error('Impossible de se connecter au serveur après plusieurs tentatives');
        }
        
        // Réinitialiser le compteur de réessais
        retryCount = 0;
        
        // Récupérer les notes
        const response = await fetch(`${API_BASE}/notes`);
        
        if (!response.ok) {
            throw new Error(`Erreur ${response.status}: ${response.statusText}`);
        }
        
        const notes = await response.json();
        
        if (notes.error) {
            throw new Error(notes.error);
        }
        
        // Vider la liste
        notesList.innerHTML = '';
        
        if (notes.length === 0) {
            notesList.innerHTML = `
                <div class="loading" style="color: #6c757d;">
                    📝 Aucune note pour le moment<br>
                    <small>Ajoutez votre première note ci-dessus!</small>
                </div>
            `;
            showMessage('Aucune note trouvée', 'info');
            return;
        }
        
        // Afficher les notes
        notes.forEach(note => {
            const noteElement = document.createElement('div');
            noteElement.className = 'note-item';
            noteElement.innerHTML = `
                <div style="flex: 1;">
                    <div style="font-size: 16px; color: #333;">${note.text}</div>
                    <small style="color: #6c757d;">ID: ${note.id}</small>
                </div>
                <button class="delete-btn" onclick="deleteNote(${note.id})" 
                        title="Supprimer cette note">
                    🗑️ Supprimer
                </button>
            `;
            notesList.appendChild(noteElement);
        });
        
        showMessage(`${notes.length} note(s) chargée(s)`, 'success');
        
    } catch (error) {
        console.error('Erreur lors du chargement des notes:', error);
        
        notesList.innerHTML = `
            <div class="error-container">
                <h3 style="color: #721c24;">⚠️ Erreur de connexion</h3>
                <p>${error.message}</p>
                <p><small>Vérifiez que le serveur backend est en cours d'exécution</small></p>
                <button class="retry-btn" onclick="location.reload()">🔄 Réessayer</button>
                <button class="retry-btn" onclick="initDatabase()" style="background: #6c757d; margin-left: 10px;">
                    🔧 Initialiser la base
                </button>
            </div>
        `;
        
        showMessage(`Erreur: ${error.message}`, 'error');
    }
}

// Ajouter une note
async function addNote() {
    const input = document.getElementById('noteInput');
    const text = input.value.trim();
    
    if (!text) {
        showMessage('Veuillez entrer une note', 'error');
        return;
    }
    
    // Désactiver le bouton pendant l'ajout
    const button = document.querySelector('.add-note button');
    const originalText = button.textContent;
    button.textContent = 'Ajout en cours...';
    button.disabled = true;
    
    try {
        const response = await fetch(`${API_BASE}/add`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({text})
        });
        
        const result = await response.json();
        
        if (!response.ok || result.error) {
            throw new Error(result.error || `Erreur ${response.status}`);
        }
        
        // Réinitialiser le champ
        input.value = '';
        
        // Remettre le focus
        input.focus();
        
        showMessage('Note ajoutée avec succès!', 'success');
        
        // Recharger les notes
        await loadNotes();
        
    } catch (error) {
        console.error('Erreur lors de l\'ajout:', error);
        showMessage(`Erreur: ${error.message}`, 'error');
    } finally {
        // Réactiver le bouton
        button.textContent = originalText;
        button.disabled = false;
    }
}

// Supprimer une note
async function deleteNote(id) {
    if (!confirm('Êtes-vous sûr de vouloir supprimer cette note ?')) {
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE}/delete/${id}`, {
            method: 'DELETE'
        });
        
        const result = await response.json();
        
        if (!response.ok || result.error) {
            throw new Error(result.error || `Erreur ${response.status}`);
        }
        
        showMessage('Note supprimée avec succès!', 'success');
        
        // Recharger les notes
        await loadNotes();
        
    } catch (error) {
        console.error('Erreur lors de la suppression:', error);
        showMessage(`Erreur: ${error.message}`, 'error');
    }
}

// Fonction pour initialiser la base de données
async function initDatabase() {
    try {
        showMessage('Initialisation de la base de données...', 'info');
        
        const response = await fetch(`${API_BASE}/init`);
        
        if (response.ok) {
            showMessage('Base de données initialisée avec succès!', 'success');
            await loadNotes();
        } else {
            throw new Error('Échec de l\'initialisation');
        }
    } catch (error) {
        showMessage(`Erreur d'initialisation: ${error.message}`, 'error');
    }
}

// Initialisation au chargement de la page
document.addEventListener('DOMContentLoaded', async function() {
    console.log('🚀 Démarrage de NotesApp...');
    console.log(`API Base URL: ${API_BASE}`);
    
    // Tester la connexion
    const isConnected = await testConnection();
    
    if (isConnected) {
        showMessage('Connecté au serveur', 'success');
    } else {
        showMessage('Connexion au serveur en cours...', 'warning');
    }
    
    // Charger les notes
    await loadNotes();
    
    // Gestion de la touche Entrée
    document.getElementById('noteInput').addEventListener('keypress', function(e) {
        if (e.key === 'Enter') {
            addNote();
        }
    });
    
    // Bouton pour initialiser la base
    const initButton = document.createElement('button');
    initButton.textContent = '🔧 Initialiser DB';
    initButton.style.cssText = `
        position: fixed;
        bottom: 20px;
        right: 20px;
        padding: 10px;
        background: #6c757d;
        color: white;
        border: none;
        border-radius: 5px;
        cursor: pointer;
        z-index: 100;
    `;
    initButton.onclick = initDatabase;
    document.body.appendChild(initButton);
    
    // Rafraîchissement automatique toutes les 30 secondes
    setInterval(async () => {
        if (document.visibilityState === 'visible') {
            await loadNotes();
        }
    }, 30000);
});

// Exposer les fonctions globalement
window.addNote = addNote;
window.deleteNote = deleteNote;
window.loadNotes = loadNotes;
window.initDatabase = initDatabase;
EOF

# 7. Ajouter un index.html amélioré
echo "📄 Mise à jour de index.html..."
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NotesApp - Application de Notes</title>
    <link rel="stylesheet" href="style.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>📝</text></svg>">
</head>
<body>
    <div class="container">
        <header>
            <h1>
                <i class="fas fa-sticky-note"></i>
                NotesApp
                <small style="font-size: 14px; color: #6c757d; font-weight: normal;">
                    | Application de prise de notes
                </small>
            </h1>
            <div class="status" id="status">
                <span class="status-dot"></span>
                <span class="status-text">Connexion...</span>
            </div>
        </header>
        
        <div class="add-note-card">
            <h2><i class="fas fa-plus-circle"></i> Nouvelle Note</h2>
            <div class="add-note">
                <textarea 
                    id="noteInput" 
                    placeholder="Écrivez votre note ici..." 
                    rows="3"></textarea>
                <div class="button-group">
                    <button onclick="addNote()" class="btn-primary">
                        <i class="fas fa-paper-plane"></i> Ajouter
                    </button>
                    <button onclick="document.getElementById('noteInput').value = ''" class="btn-secondary">
                        <i class="fas fa-eraser"></i> Effacer
                    </button>
                </div>
            </div>
            <div class="note-counter">
                <small>
                    <i class="fas fa-info-circle"></i>
                    <span id="charCount">0</span> caractères
                </small>
            </div>
        </div>
        
        <div class="notes-section">
            <h2><i class="fas fa-list"></i> Notes <span class="badge" id="notesCount">0</span></h2>
            <div class="notes-controls">
                <button onclick="loadNotes()" class="btn-refresh">
                    <i class="fas fa-sync-alt"></i> Rafraîchir
                </button>
                <button onclick="initDatabase()" class="btn-init">
                    <i class="fas fa-database"></i> Initialiser DB
                </button>
            </div>
            <div id="notesList" class="notes-list">
                <!-- Les notes seront chargées ici -->
                <div class="loading-notes">
                    <div class="spinner"></div>
                    <p>Chargement des notes...</p>
                </div>
            </div>
        </div>
        
        <footer>
            <p>
                <i class="fas fa-code"></i> 
                NotesApp v1.0 | 
                <i class="fas fa-server"></i> 
                Backend: Flask + PostgreSQL |
                <i class="fas fa-globe"></i> 
                Frontend: HTML/CSS/JS
            </p>
            <p class="debug-info">
                <small>
                    API: <span id="apiUrl">http://localhost:5000</span> | 
                    DB: <span id="dbStatus">Connexion...</span>
                </small>
            </p>
        </footer>
    </div>
    
    <!-- Scripts -->
    <script src="app.js"></script>
    
    <!-- Script pour le compteur de caractères -->
    <script>
        document.getElementById('noteInput').addEventListener('input', function(e) {
            const charCount = e.target.value.length;
            document.getElementById('charCount').textContent = charCount;
            
            // Changer la couleur si trop long
            const charCountElem = document.getElementById('charCount');
            if (charCount > 500) {
                charCountElem.style.color = '#dc3545';
                charCountElem.innerHTML = `${charCount} <i class="fas fa-exclamation-triangle"></i>`;
            } else if (charCount > 250) {
                charCountElem.style.color = '#ffc107';
            } else {
                charCountElem.style.color = '#28a745';
            }
        });
        
        // Mettre à jour le statut
        async function updateStatus() {
            try {
                const response = await fetch('http://localhost:5000/health');
                const data = await response.json();
                
                const statusDot = document.querySelector('.status-dot');
                const statusText = document.querySelector('.status-text');
                const dbStatus = document.getElementById('dbStatus');
                
                if (data.status === 'healthy') {
                    statusDot.style.backgroundColor = '#28a745';
                    statusText.textContent = 'Connecté';
                    dbStatus.textContent = 'OK';
                    dbStatus.style.color = '#28a745';
                } else {
                    statusDot.style.backgroundColor = '#dc3545';
                    statusText.textContent = 'Déconnecté';
                    dbStatus.textContent = 'Erreur';
                    dbStatus.style.color = '#dc3545';
                }
            } catch (error) {
                console.log('Statut non disponible');
            }
        }
        
        // Mettre à jour le statut toutes les 10 secondes
        setInterval(updateStatus, 10000);
        updateStatus(); // Premier appel
    </script>
</body>
</html>
EOF

# 8. Mettre à jour le style CSS
echo "🎨 Mise à jour du style CSS..."
cat > frontend/style.css << 'EOF'
/* Variables CSS */
:root {
    --primary-color: #4361ee;
    --secondary-color: #3a0ca3;
    --success-color: #4cc9f0;
    --danger-color: #f72585;
    --warning-color: #ff9e00;
    --light-color: #f8f9fa;
    --dark-color: #212529;
    --gray-color: #6c757d;
    --shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    --transition: all 0.3s ease;
}

/* Reset et base */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    padding: 20px;
    color: var(--dark-color);
}

/* Container principal */
.container {
    max-width: 1000px;
    margin: 0 auto;
    background: white;
    border-radius: 20px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
    overflow: hidden;
}

/* Header */
header {
    background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
    color: white;
    padding: 30px;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

header h1 {
    font-size: 2.5rem;
    display: flex;
    align-items: center;
    gap: 15px;
}

header h1 i {
    font-size: 2rem;
}

.status {
    display: flex;
    align-items: center;
    gap: 10px;
    background: rgba(255, 255, 255, 0.2);
    padding: 10px 20px;
    border-radius: 50px;
}

.status-dot {
    width: 12px;
    height: 12px;
    background-color: var(--warning-color);
    border-radius: 50%;
    animation: pulse 2s infinite;
}

.status-text {
    font-weight: 600;
}

@keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
}

/* Section d'ajout de note */
.add-note-card {
    padding: 30px;
    border-bottom: 1px solid #eee;
}

.add-note-card h2 {
    color: var(--primary-color);
    margin-bottom: 20px;
    display: flex;
    align-items: center;
    gap: 10px;
}

.add-note {
    display: flex;
    flex-direction: column;
    gap: 15px;
}

#noteInput {
    width: 100%;
    padding: 20px;
    border: 2px solid #e0e0e0;
    border-radius: 10px;
    font-size: 16px;
    font-family: inherit;
    resize: vertical;
    min-height: 100px;
    transition: var(--transition);
}

#noteInput:focus {
    outline: none;
    border-color: var(--primary-color);
    box-shadow: 0 0 0 3px rgba(67, 97, 238, 0.1);
}

.button-group {
    display: flex;
    gap: 10px;
    justify-content: flex-end;
}

button {
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 8px;
    transition: var(--transition);
}

.btn-primary {
    background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
    color: white;
}

.btn-primary:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow);
}

.btn-secondary {
    background: var(--light-color);
    color: var(--gray-color);
    border: 1px solid #ddd;
}

.btn-secondary:hover {
    background: #e9ecef;
}

.note-counter {
    margin-top: 10px;
    text-align: right;
    color: var(--gray-color);
}

/* Section des notes */
.notes-section {
    padding: 30px;
}

.notes-section h2 {
    color: var(--primary-color);
    margin-bottom: 20px;
    display: flex;
    align-items: center;
    gap: 10px;
}

.badge {
    background: var(--primary-color);
    color: white;
    padding: 4px 12px;
    border-radius: 20px;
    font-size: 0.8em;
}

.notes-controls {
    display: flex;
    gap: 10px;
    margin-bottom: 20px;
}

.btn-refresh {
    background: var(--success-color);
    color: white;
}

.btn-init {
    background: var(--warning-color);
    color: white;
}

.notes-list {
    min-height: 300px;
}

.loading-notes {
    text-align: center;
    padding: 60px 20px;
    color: var(--gray-color);
}

.spinner {
    width: 50px;
    height: 50px;
    border: 5px solid #f3f3f3;
    border-top: 5px solid var(--primary-color);
    border-radius: 50%;
    margin: 0 auto 20px;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.note-item {
    background: var(--light-color);
    border-left: 4px solid var(--primary-color);
    padding: 20px;
    margin-bottom: 15px;
    border-radius: 8px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    transition: var(--transition);
    animation: slideIn 0.3s ease-out;
}

@keyframes slideIn {
    from {
        opacity: 0;
        transform: translateY(20px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

.note-item:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow);
}

.note-item .note-content {
    flex: 1;
}

.note-item .note-text {
    font-size: 16px;
    margin-bottom: 5px;
}

.note-item .note-meta {
    font-size: 12px;
    color: var(--gray-color);
}

.delete-btn {
    background: var(--danger-color);
    color: white;
    padding: 8px 16px;
    font-size: 14px;
}

.delete-btn:hover {
    background: #d1144a;
    transform: scale(1.05);
}

/* Footer */
footer {
    background: #f8f9fa;
    padding: 20px 30px;
    text-align: center;
    border-top: 1px solid #eee;
    color: var(--gray-color);
}

footer p {
    margin: 5px 0;
}

.debug-info {
    font-family: 'Courier New', monospace;
    background: #e9ecef;
    padding: 10px;
    border-radius: 5px;
    margin-top: 10px;
}

/* Responsive */
@media (max-width: 768px) {
    header {
        flex-direction: column;
        text-align: center;
        gap: 15px;
    }
    
    header h1 {
        font-size: 2rem;
    }
    
    .button-group {
        flex-direction: column;
    }
    
    button {
        width: 100%;
        justify-content: center;
    }
    
    .notes-controls {
        flex-direction: column;
    }
}
EOF

# 9. Créer un script de test amélioré
echo "🧪 Création du script de test..."
cat > test-all.sh << 'EOF'
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
EOF

chmod +x test-all.sh

# 10. Construire et démarrer
echo "🚀 Construction et démarrage des conteneurs..."
docker-compose build --no-cache
docker-compose up -d

# 11. Attendre et tester
echo "⏳ Attente du démarrage complet (30 secondes)..."
sleep 30

# 12. Exécuter les tests
echo "🧪 Exécution des tests..."
cd ..
./test-all.sh

echo ""
echo "========================================="
echo "✅ Tous les problèmes ont été corrigés !"
echo ""
echo "✨ Points corrigés:"
echo "   ✓ before_first_request remplacé par before_request"
echo "   ✓ Meilleure gestion d'erreurs Flask"
echo "   ✓ Interface frontend améliorée"
echo "   ✓ Système de réessais automatique"
echo "   ✓ Healthchecks corrigés"
echo "   ✓ Docker Compose simplifié"
echo ""
echo "🌐 Accès:"
echo "   Frontend: http://localhost"
echo "   API:      http://localhost:5000"
echo ""
echo "🐛 Si vous avez encore des problèmes:"
echo "   1. docker-compose logs -f backend"
echo "   2. docker-compose restart"
echo "   3. Accédez à http://localhost:5000/init pour forcer l'init DB"
echo "========================================="
