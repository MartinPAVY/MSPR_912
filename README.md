# 🔐 COFRAP - Portail Sécurisé avec Double Authentification

Application serverless sécurisée utilisant OpenFaaS avec authentification à double facteur (2FA) via TOTP.

## 🚀 Installation en un clic

### Prérequis

**OBLIGATOIRES :**
- **Docker Desktop** avec **Kubernetes activé** 
  - Docker Desktop → Settings → Kubernetes → ✅ Enable Kubernetes
- **OpenFaaS CLI** (`faas-cli`)
- **kubectl** (inclus avec Docker Desktop)

**Gestionnaires de paquets (auto-installés par les scripts) :**
- 🐧 **Linux/macOS** : Homebrew pour les dépendances
- 🪟 **Windows** : Chocolatey pour les dépendances

### Installation automatique

**🐧 Linux/macOS :**
```bash
git clone <votre-repo>
cd mspr-serverless
chmod +x install.sh
./install.sh
```

**🪟 Windows PowerShell (Recommandé) :**
```powershell
git clone <votre-repo>
cd mspr-serverless
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\install.ps1
```

**🪟 Windows CMD :**
```cmd
git clone <votre-repo>
cd mspr-serverless
install.bat
```

### Installation manuelle

Si le script automatique échoue :

**🐧 Linux/macOS :**
```bash
# 1. Installer les outils
brew install helm faas-cli

# 2. Installer OpenFaaS
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml
helm repo add openfaas https://openfaas.github.io/faas-netes/
helm upgrade openfaas --install openfaas/openfaas --namespace openfaas

# 3. Installer PostgreSQL
kubectl apply -f postgres.yaml

# 4. Builder et déployer les fonctions
faas-cli build -f stack.yaml
kubectl delete pods -n openfaas-fn --all
```

**🪟 Windows :**
```powershell
# 1. Installer Chocolatey (si pas déjà fait)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 2. Installer les outils
choco install kubernetes-helm faas-cli -y

# 3. Suivre les mêmes étapes que Linux/macOS
```

## 📱 Utilisation

1. **Ouvrir l'interface web** : `frontend/index.html` dans votre navigateur

2. **Créer un compte** :
   - Entrez un nom d'utilisateur
   - Cliquez sur "Générer le compte" 
   - ⚠️ **COPIEZ le mot de passe généré** (ne sera plus affiché)

3. **Configurer 2FA** :
   - Scannez le QR code avec **Google Authenticator** ou **Authy**
   - L'app génère des codes à 6 chiffres renouvelés toutes les 30 secondes

4. **Se connecter** :
   - Nom d'utilisateur
   - Mot de passe copié
   - Code 2FA de votre app d'authentification

## 🏗️ Architecture

### Fonctions Serverless (OpenFaaS)

- **`register-user`** : Création de compte avec génération de QR code TOTP
- **`auth-user`** : Authentification avec vérification 2FA

### Base de données

PostgreSQL avec table `users` :
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    mfa VARCHAR(32) NOT NULL,
    gendate TIMESTAMP NOT NULL
);
```

### Frontend

Interface web simple en HTML/JavaScript avec support CORS.

## 🔧 Configuration

### Ports utilisés

- **31112** : Gateway OpenFaaS (NodePort)
- **5432** : PostgreSQL
- **8080** : Gateway interne OpenFaaS

### Accès aux services

- **Interface web** : Ouvrir `frontend/index.html`
- **Fonctions** : `http://127.0.0.1:31112/function/{nom-fonction}`

## 🐛 Dépannage

### Problème : "connection refused"
```bash
# Vérifier que Kubernetes tourne
kubectl get nodes

# Vérifier les pods OpenFaaS
kubectl get pods -n openfaas
kubectl get pods -n openfaas-fn
```

### Problème : "CORS error"
Les headers CORS sont configurés dans `template/python3-flask-debian/index.py` avec flask-cors.

### Problème : "Mot de passe incorrect" 
- Vérifiez qu'il n'y a pas de doublons d'utilisateurs
- La base a une contrainte UNIQUE sur username

### Logs utiles
```bash
# Logs des fonctions
kubectl logs -n openfaas-fn -l faas_function=auth-user
kubectl logs -n openfaas-fn -l faas_function=register-user

# Logs PostgreSQL  
kubectl logs -n openfaas-fn postgres

# Logs Gateway OpenFaaS
kubectl logs -n openfaas -l app=gateway
```

## 🔒 Sécurité

- Mots de passe générés avec 24 caractères aléatoires
- Secrets TOTP générés avec `pyotp.random_base32()`
- Headers CORS configurés pour les domaines autorisés
- Base de données PostgreSQL avec authentification

## 📁 Structure du projet

```
├── auth-user/              # Fonction d'authentification
│   ├── handler.py          # Logique d'auth + vérification 2FA
│   └── index.py            # Interface Flask avec CORS
├── register-user/          # Fonction de création de compte  
│   ├── handler.py          # Génération user/password/QR
│   └── index.py            # Interface Flask avec CORS
├── frontend/
│   └── index.html          # Interface web utilisateur
├── template/               # Templates OpenFaaS personnalisés
├── postgres.yaml           # Déploiement PostgreSQL
├── stack.yaml              # Configuration des fonctions
├── install.sh              # Script d'installation Linux/macOS
├── install.ps1             # Script d'installation Windows (PowerShell)
├── install.bat             # Script d'installation Windows (CMD)
└── README.md               # Documentation complète
```

## 📧 Support

- Vérifiez les logs en cas de problème
- Assurez-vous que Docker Desktop + K8s sont bien activés
- La première installation peut prendre quelques minutes

---
*🛡️ Portail sécurisé COFRAP - MSPR EPSI*
