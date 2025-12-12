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
