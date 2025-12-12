#!/usr/bin/env python3
"""
Script d'initialisation de la base de données
À exécuter manuellement si nécessaire: python database.py
"""
import psycopg2
import time
import sys

def init_db():
    print("🔧 Initialisation manuelle de la base de données...")
    
    # Configuration
    DB_HOST = 'db'
    DB_NAME = 'notesdb'
    DB_USER = 'postgres'
    DB_PASSWORD = 'password'
    
    max_retries = 10
    for i in range(max_retries):
        try:
            print(f"Tentative {i+1}/{max_retries}...")
            
            # Se connecter à 'postgres' (base par défaut)
            conn = psycopg2.connect(
                host=DB_HOST,
                database='postgres',
                user=DB_USER,
                password=PASSWORD,
                connect_timeout=5
            )
            conn.autocommit = True
            cur = conn.cursor()
            
            # Créer la base si elle n'existe pas
            cur.execute(f"SELECT 1 FROM pg_database WHERE datname='{DB_NAME}';")
            if not cur.fetchone():
                print(f"Création de la base '{DB_NAME}'...")
                cur.execute(f"CREATE DATABASE {DB_NAME};")
            else:
                print(f"Base '{DB_NAME}' existe déjà")
            
            cur.close()
            conn.close()
            
            # Se connecter à notre base
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=PASSWORD
            )
            cur = conn.cursor()
            
            # Créer la table
            cur.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                    id SERIAL PRIMARY KEY,
                    text TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            ''')
            
            # Ajouter une note de test
            cur.execute("SELECT COUNT(*) FROM notes;")
            count = cur.fetchone()[0]
            if count == 0:
                cur.execute("INSERT INTO notes (text) VALUES ('Note de test depuis script');")
                print("Note de test ajoutée")
            
            conn.commit()
            cur.close()
            conn.close()
            
            print("✅ Base de données initialisée avec succès!")
            return True
            
        except Exception as e:
            print(f"Erreur: {e}")
            if i < max_retries - 1:
                print(f"Nouvelle tentative dans 3 secondes...")
                time.sleep(3)
    
    print("❌ Échec de l'initialisation")
    return False

if __name__ == '__main__':
    init_db()
