-- Script d'initialisation PostgreSQL
CREATE TABLE IF NOT EXISTS notes (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insérer une note de test si la table est vide
INSERT INTO notes (text) 
SELECT 'Bienvenue dans NotesApp!'
WHERE NOT EXISTS (SELECT 1 FROM notes LIMIT 1);
