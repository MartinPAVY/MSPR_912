# ==========================================
# SCRIPT D'INSTALLATION AUTOMATISÉE MSPR - WINDOWS (PowerShell)
# ==========================================

# Couleurs pour la lisibilité
$GREEN = "Green"
$BLUE = "Cyan"
$RED = "Red"
$YELLOW = "Yellow"

Write-Host "🚀 Démarrage de l'installation du projet Serverless MSPR..." -ForegroundColor $BLUE

# 1. VÉRIFICATION DES PRÉ-REQUIS
# ------------------------------------------
Write-Host "[1/8] Vérification de l'environnement..." -ForegroundColor $BLUE

# Vérifier si Docker tourne
try {
    docker info *> $null
    Write-Host "✅ Docker est lancé." -ForegroundColor $GREEN
} catch {
    Write-Host "❌ Erreur : Docker n'est pas lancé." -ForegroundColor $RED
    Write-Host "Veuillez lancer Docker Desktop et réessayer." -ForegroundColor $RED
    exit 1
}

# Vérifier si Kubernetes est activé
try {
    kubectl cluster-info *> $null
    Write-Host "✅ Kubernetes est accessible." -ForegroundColor $GREEN
} catch {
    Write-Host "❌ Erreur : Kubernetes n'est pas accessible." -ForegroundColor $RED
    Write-Host "Vérifiez que 'Enable Kubernetes' est coché dans Docker Desktop settings." -ForegroundColor $RED
    exit 1
}

# 2. INSTALLATION DES OUTILS
# ------------------------------------------
Write-Host "[2/8] Installation des dépendances..." -ForegroundColor $BLUE

# Vérifier si Chocolatey est installé
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Chocolatey n'est pas installé." -ForegroundColor $RED
    Write-Host "Installez Chocolatey (https://chocolatey.org/install) ou installez manuellement helm et faas-cli." -ForegroundColor $YELLOW
    exit 1
}

$tools = @("kubernetes-helm", "faas-cli")
foreach ($tool in $tools) {
    $installed = choco list --local-only $tool 2>$null | Select-String $tool
    if ($installed) {
        Write-Host "✅ $tool est déjà installé." -ForegroundColor $GREEN
    } else {
        Write-Host "Installation de $tool..." -ForegroundColor $YELLOW
        try {
            choco install $tool -y
        } catch {
            Write-Host "⚠️ Erreur non bloquante lors de l'installation de $tool" -ForegroundColor $YELLOW
        }
    }
}

# 3. DÉPLOIEMENT OPENFAAS (Via Helm)
# ------------------------------------------
Write-Host "[3/8] Installation d'OpenFaaS sur le cluster..." -ForegroundColor $BLUE

kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml *> $null
helm repo add openfaas https://openfaas.github.io/faas-netes/ *> $null
helm repo update *> $null

helm upgrade openfaas --install openfaas/openfaas `
    --namespace openfaas `
    --set functionNamespace=openfaas-fn `
    --set generateBasicAuth=true `
    --wait

Write-Host "✅ OpenFaaS est déployé." -ForegroundColor $GREEN

# 4. CONNEXION CLI (Login)
# ------------------------------------------
Write-Host "[4/8] Connexion à OpenFaaS..." -ForegroundColor $BLUE

# On lance un port-forward temporaire
$job = Start-Job -ScriptBlock { kubectl port-forward -n openfaas svc/gateway 8080:8080 }
Start-Sleep -Seconds 7 # Pause pour laisser le tunnel s'ouvrir

try {
    # Récupération propre du mot de passe en PowerShell
    $secret = kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}"
    $PASSWORD = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))
    
    # Login
    echo $PASSWORD | faas-cli login --username admin --password-stdin
    Write-Host "✅ Connecté avec succès (Admin Password récupéré)." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur lors de la connexion OpenFaaS (Le déploiement suivant risque d'échouer)." -ForegroundColor $RED
}

# 5. DÉPLOIEMENT INFRA (DB + Fonctions)
# ------------------------------------------
Write-Host "[5/8] Déploiement de la Base de Données..." -ForegroundColor $BLUE

if (Test-Path "postgres.yaml") {
    kubectl apply -f postgres.yaml
    Write-Host "Attente du démarrage de PostgreSQL..." -ForegroundColor $YELLOW
    kubectl wait --for=condition=ready pod -l app=postgres -n openfaas-fn --timeout=60s
} else {
    Write-Host "❌ Fichier postgres.yaml introuvable !" -ForegroundColor $RED
    Stop-Job $job
    Remove-Job $job
    exit 1
}

Write-Host "[6/8] Construction et Déploiement des Fonctions..." -ForegroundColor $BLUE
Write-Host "⚠️ Assurez-vous d'être connecté à Docker Hub (docker login)." -ForegroundColor $YELLOW

try {
    # On utilise 'up' pour faire Build + Push + Deploy
    faas-cli up -f stack.yaml
    Write-Host "✅ Fonctions déployées avec succès." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur lors du déploiement. Vérifiez les logs." -ForegroundColor $RED
}

# 6. INITIALISATION DONNÉES
# ------------------------------------------
Write-Host "[7/8] Création de la table SQL 'users'..." -ForegroundColor $BLUE

Start-Sleep -Seconds 5
try {
    kubectl exec -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL, mfa VARCHAR(32) NOT NULL, gendate TIMESTAMP NOT NULL, expired INT DEFAULT 0, failed_attempts INT DEFAULT 0, locked_until TIMESTAMP);"
    # Add columns if table already existed without them
    kubectl exec -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_attempts INT DEFAULT 0; ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;" *> $null
    Write-Host "✅ Table 'users' créée avec succès." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur lors de la création de la table (Peut-être déjà existante ?)" -ForegroundColor $YELLOW
}

# 7. INSTALLATION DASHBOARD K8S (BONUS)
# ------------------------------------------
Write-Host "[8/8] Installation du Dashboard Kubernetes (Bonus)..." -ForegroundColor $BLUE

# Installation via manifest officiel (le repo Helm kubernetes-dashboard n'est plus disponible)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml *> $null

Write-Host "Attente du démarrage du Dashboard..." -ForegroundColor $YELLOW
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=120s *> $null

# Création du ServiceAccount Admin via Here-String PowerShell
$adminYaml = @"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
"@

$adminYaml | kubectl apply -f - *> $null

# Récupération du Token
$TOKEN = kubectl -n kubernetes-dashboard create token admin-user

Write-Host "✅ Dashboard installé." -ForegroundColor $GREEN

# 8. NETTOYAGE ET FIN
# ------------------------------------------
Stop-Job $job
Remove-Job $job

Write-Host "==============================================" -ForegroundColor $GREEN
Write-Host "🎉 INSTALLATION TERMINÉE AVEC SUCCÈS ! 🎉" -ForegroundColor $GREEN
Write-Host "==============================================" -ForegroundColor $GREEN
Write-Host ""
Write-Host "Pour utiliser votre projet, ouvrez 3 fenêtres PowerShell :" -ForegroundColor $BLUE
Write-Host ""
Write-Host "1️⃣  Terminal 1 (Tunnels) :" -ForegroundColor $BLUE
Write-Host "   kubectl port-forward -n openfaas svc/gateway 8080:8080" -ForegroundColor $YELLOW
Write-Host "   (Ouvrez un nouvel onglet et lancez aussi :)" -ForegroundColor $YELLOW
Write-Host "   kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443" -ForegroundColor $YELLOW
Write-Host ""
Write-Host "2️⃣  Terminal 2 (Serveur Frontend) :" -ForegroundColor $BLUE
Write-Host "   cd frontend" -ForegroundColor $YELLOW
Write-Host "   python -m http.server 8000" -ForegroundColor $YELLOW
Write-Host ""
Write-Host "3️⃣  Accès Visuels :" -ForegroundColor $BLUE
Write-Host "   🌍 Site Web : http://localhost:8000" -ForegroundColor $GREEN
Write-Host "   📊 Dashboard : https://localhost:8443" -ForegroundColor $GREEN
Write-Host ""
Write-Host "🔑 TOKEN POUR LE DASHBOARD (Copiez-le) :" -ForegroundColor $RED
Write-Host $TOKEN -ForegroundColor $White
Write-Host ""
Read-Host -Prompt "Appuyez sur Entrée pour quitter"