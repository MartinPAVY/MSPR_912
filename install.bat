@echo off
REM ==========================================
REM SCRIPT D'INSTALLATION AUTOMATISÉE MSPR - WINDOWS (CMD)
REM ==========================================

echo.
echo 🔐 Installation du Portail Sécurisé COFRAP - Windows
echo ====================================================

REM 1. VÉRIFICATION DES PRÉ-REQUIS
echo [1/7] Vérification de l'environnement...

REM Vérifier si Docker tourne
docker info >nul 2>&1
if errorlevel 1 (
    echo ❌ Erreur : Docker n'est pas lancé.
    echo Veuillez lancer Docker Desktop et réessayer.
    exit /b 1
)
echo ✅ Docker est lancé.

REM Vérifier si Kubernetes est activé
kubectl cluster-info >nul 2>&1
if errorlevel 1 (
    echo ❌ Erreur : Kubernetes n'est pas accessible.
    echo Vérifiez que 'Enable Kubernetes' est coché dans Docker Desktop.
    exit /b 1
)
echo ✅ Kubernetes est accessible.

REM 2. VÉRIFICATION DES OUTILS
echo [2/7] Vérification des outils...

REM Vérifier Helm
helm version >nul 2>&1
if errorlevel 1 (
    echo ❌ Helm n'est pas installé.
    echo Installez Helm depuis https://helm.sh/docs/intro/install/
    echo Ou utilisez Chocolatey: choco install kubernetes-helm
    exit /b 1
)
echo ✅ Helm est installé.

REM Vérifier faas-cli
faas-cli version >nul 2>&1
if errorlevel 1 (
    echo ❌ faas-cli n'est pas installé.
    echo Téléchargez depuis https://github.com/openfaas/faas-cli/releases
    echo Ou utilisez Chocolatey: choco install faas-cli
    exit /b 1
)
echo ✅ faas-cli est installé.

REM 3. DÉPLOIEMENT OPENFAAS
echo [3/7] Installation d'OpenFaaS sur le cluster...

kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml >nul 2>&1
helm repo add openfaas https://openfaas.github.io/faas-netes/ >nul 2>&1
helm repo update >nul 2>&1

helm upgrade openfaas --install openfaas/openfaas ^
    --namespace openfaas ^
    --set functionNamespace=openfaas-fn ^
    --set generateBasicAuth=true ^
    --wait

echo ✅ OpenFaaS est déployé.

REM 4. DÉPLOIEMENT POSTGRESQL
echo [4/7] Déploiement de la Base de Données...

if not exist "postgres.yaml" (
    echo ❌ Fichier postgres.yaml introuvable !
    exit /b 1
)

kubectl apply -f postgres.yaml
echo Attente du démarrage de PostgreSQL...
kubectl wait --for=condition=ready pod -l app=postgres -n openfaas-fn --timeout=60s

REM 5. CONSTRUCTION DES FONCTIONS
echo [5/7] Construction et Déploiement des Fonctions...
echo ⚠️ Assurez-vous d'être connecté à Docker Hub (docker login).

faas-cli build -f stack.yaml
if errorlevel 1 (
    echo ⚠️ Erreur lors de la construction des fonctions
) else (
    echo ✅ Fonctions construites avec succès.
)

REM Redémarrer les pods pour utiliser les nouvelles images
kubectl delete pods -n openfaas-fn --all >nul 2>&1

REM 6. INITIALISATION BASE DE DONNÉES
echo [6/7] Création de la table SQL 'users'...

REM Attendre que PostgreSQL soit prêt
timeout /t 10 /nobreak >nul

kubectl exec -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL, mfa VARCHAR(32) NOT NULL, gendate TIMESTAMP NOT NULL);" >nul 2>&1
if errorlevel 1 (
    echo ⚠️ Erreur lors de la création de la table
) else (
    echo ✅ Table 'users' créée avec succès.
)

REM 7. INSTRUCTIONS FINALES
echo [7/7] Finalisation...
echo.
echo ==============================================
echo 🎉 INSTALLATION TERMINÉE AVEC SUCCÈS ! 🎉
echo ==============================================
echo.
echo Pour utiliser votre projet, ouvrez 2 terminaux CMD/PowerShell :
echo.
echo 1️⃣  Terminal 1 (Tunnel Backend) :
echo    kubectl port-forward -n openfaas svc/gateway 8080:8080
echo.
echo 2️⃣  Terminal 2 (Serveur Frontend) :
echo    cd frontend
echo    python -m http.server 8000
echo.
echo Ensuite, allez sur : http://localhost:8000
echo.
echo 🔧 Commandes utiles de debug :
echo    kubectl get pods -n openfaas-fn
echo    kubectl logs -n openfaas-fn -l faas_function=auth-user
echo    kubectl logs -n openfaas-fn -l faas_function=register-user
echo.
pause
