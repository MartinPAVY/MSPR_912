# ==========================================
# SCRIPT D'INSTALLATION AUTOMATISÉE MSPR - WINDOWS
# ==========================================

# Couleurs pour la lisibilité
$GREEN = "Green"
$BLUE = "Cyan"
$RED = "Red"
$YELLOW = "Yellow"

Write-Host "🚀 Démarrage de l'installation du projet Serverless MSPR..." -ForegroundColor $BLUE

# 1. VÉRIFICATION DES PRÉ-REQUIS
# ------------------------------------------
Write-Host "[1/7] Vérification de l'environnement..." -ForegroundColor $BLUE

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
Write-Host "[2/7] Installation des dépendances..." -ForegroundColor $BLUE

# Vérifier si Chocolatey est installé
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Chocolatey n'est pas installé." -ForegroundColor $RED
    Write-Host "Installez Chocolatey depuis https://chocolatey.org/install puis relancez ce script." -ForegroundColor $YELLOW
    exit 1
}

$tools = @("kubernetes-helm", "faas-cli")
foreach ($tool in $tools) {
    try {
        # Vérifier si l'outil est déjà installé
        $installed = choco list --local-only $tool 2>$null | Select-String $tool
        if ($installed) {
            Write-Host "✅ $tool est déjà installé." -ForegroundColor $GREEN
        } else {
            Write-Host "Installation de $tool..." -ForegroundColor $YELLOW
            choco install $tool -y
        }
    } catch {
        Write-Host "⚠️ Erreur lors de l'installation de $tool" -ForegroundColor $RED
    }
}

# 3. DÉPLOIEMENT OPENFAAS (Via Helm)
# ------------------------------------------
Write-Host "[3/7] Installation d'OpenFaaS sur le cluster..." -ForegroundColor $BLUE

# Ajout des repos Helm
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml *> $null
helm repo add openfaas https://openfaas.github.io/faas-netes/ *> $null
helm repo update *> $null

# Installation du chart
helm upgrade openfaas --install openfaas/openfaas `
    --namespace openfaas `
    --set functionNamespace=openfaas-fn `
    --set generateBasicAuth=true `
    --wait

Write-Host "✅ OpenFaaS est déployé." -ForegroundColor $GREEN

# 4. CONNEXION CLI (Login)
# ------------------------------------------
Write-Host "[4/7] Connexion à OpenFaaS..." -ForegroundColor $BLUE

# On lance un port-forward temporaire en arrière-plan pour se connecter
$job = Start-Job -ScriptBlock { kubectl port-forward -n openfaas svc/gateway 8080:8080 }
Start-Sleep -Seconds 5  # Attendre que le tunnel s'ouvre

try {
    $PASSWORD = kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}" | % { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    echo $PASSWORD | faas-cli login --username admin --password-stdin
    Write-Host "✅ Connecté avec succès (Admin Password récupéré)." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur de connexion OpenFaaS" -ForegroundColor $RED
}

# 5. DÉPLOIEMENT INFRA (DB + Fonctions)
# ------------------------------------------
Write-Host "[5/7] Déploiement de la Base de Données..." -ForegroundColor $BLUE

# Appliquer le fichier postgres.yaml
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

Write-Host "[6/7] Construction et Déploiement des Fonctions..." -ForegroundColor $BLUE
Write-Host "⚠️ Assurez-vous d'être connecté à Docker Hub (docker login)." -ForegroundColor $YELLOW

try {
    faas-cli up -f stack.yaml
    Write-Host "✅ Fonctions déployées avec succès." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur lors du déploiement des fonctions" -ForegroundColor $RED
}

# 6. INITIALISATION DONNÉES
# ------------------------------------------
Write-Host "[7/7] Création de la table SQL 'users'..." -ForegroundColor $BLUE

# On attend un peu que Postgres soit prêt à recevoir des commandes
Start-Sleep -Seconds 5

try {
    kubectl exec -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL, mfa VARCHAR(32) NOT NULL, gendate TIMESTAMP NOT NULL);"
    Write-Host "✅ Table 'users' créée avec succès." -ForegroundColor $GREEN
} catch {
    Write-Host "⚠️ Erreur lors de la création de la table" -ForegroundColor $RED
}

# 7. NETTOYAGE ET INSTRUCTIONS FINALES
# ------------------------------------------
# On arrête le port-forward temporaire
Stop-Job $job
Remove-Job $job

Write-Host "==============================================" -ForegroundColor $GREEN
Write-Host "🎉 INSTALLATION TERMINÉE AVEC SUCCÈS ! 🎉" -ForegroundColor $GREEN
Write-Host "==============================================" -ForegroundColor $GREEN
Write-Host ""
Write-Host "Pour utiliser votre projet, ouvrez 2 terminaux PowerShell :" -ForegroundColor $BLUE
Write-Host ""
Write-Host "1️⃣  Terminal 1 (Tunnel Backend) :" -ForegroundColor $BLUE
Write-Host "   kubectl port-forward -n openfaas svc/gateway 8080:8080" -ForegroundColor $YELLOW
Write-Host ""
Write-Host "2️⃣  Terminal 2 (Serveur Frontend) :" -ForegroundColor $BLUE
Write-Host "   cd frontend" -ForegroundColor $YELLOW
Write-Host "   python -m http.server 8000" -ForegroundColor $YELLOW
Write-Host ""
Write-Host "Ensuite, allez sur : http://localhost:8000" -ForegroundColor $GREEN
Write-Host ""
Write-Host "🔧 Commandes utiles de debug :" -ForegroundColor $BLUE
Write-Host "   kubectl get pods -n openfaas-fn" -ForegroundColor $YELLOW
Write-Host "   kubectl logs -n openfaas-fn -l faas_function=auth-user" -ForegroundColor $YELLOW
Write-Host "   kubectl logs -n openfaas-fn -l faas_function=register-user" -ForegroundColor $YELLOW
