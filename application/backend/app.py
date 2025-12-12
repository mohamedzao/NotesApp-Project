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
