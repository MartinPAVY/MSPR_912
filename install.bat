@echo off
REM ==========================================
REM SCRIPT D'INSTALLATION AUTOMATISÉE MSPR - WINDOWS (CMD)
REM ==========================================

echo.
echo 🔐 Installation du Portail Sécurisé COFRAP - Windows
echo ====================================================

REM 1. VÉRIFICATION ENVIRONNEMENT
echo [1/8] Vérification de l'environnement...

docker info >nul 2>&1
if errorlevel 1 (
    echo ❌ Erreur : Docker n'est pas lancé.
    pause
    exit /b 1
)

kubectl cluster-info >nul 2>&1
if errorlevel 1 (
    echo ❌ Erreur : Kubernetes n'est pas accessible.
    pause
    exit /b 1
)
echo ✅ Environnement OK.

REM 2. OUTILS
echo [2/8] Vérification des outils...
helm version >nul 2>&1
if errorlevel 1 echo ⚠️ Helm manquant (Installez via Choco)
faas-cli version >nul 2>&1
if errorlevel 1 echo ⚠️ faas-cli manquant (Installez via Choco)
echo ✅ Outils vérifiés.

REM 3. OPENFAAS
echo [3/8] Installation d'OpenFaaS...
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml >nul 2>&1
helm repo add openfaas https://openfaas.github.io/faas-netes/ >nul 2>&1
helm repo update >nul 2>&1
helm upgrade openfaas --install openfaas/openfaas --namespace openfaas --set functionNamespace=openfaas-fn --set generateBasicAuth=true --wait >nul 2>&1
echo ✅ OpenFaaS déployé.

REM 4. LOGIN OPENFAAS (Astuce PowerShell pour le décodage)
echo [4/8] Connexion à OpenFaaS...
echo Lancement du tunnel temporaire...
start /b kubectl port-forward -n openfaas svc/gateway 8080:8080 >nul 2>&1
timeout /t 5 /nobreak >nul

for /f "delims=" %%i in ('kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}"') do set SECRET=%%i
powershell -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('%SECRET%')) | faas-cli login --username admin --password-stdin"

echo ✅ Tentative de connexion terminée.

REM 5. DB
echo [5/8] Déploiement de la Base de Données...
kubectl apply -f postgres.yaml
echo Attente du démarrage PostgreSQL...
kubectl wait --for=condition=ready pod -l app=postgres -n openfaas-fn --timeout=60s >nul 2>&1

REM 6. FONCTIONS
echo [6/8] Déploiement des Fonctions...
echo ⚠️ Assurez-vous d'être connecté à Docker Hub.
faas-cli up -f stack.yaml
echo ✅ Fonctions traitées.

REM 7. SQL
echo [7/8] Initialisation SQL...
timeout /t 5 /nobreak >nul
kubectl exec -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL, mfa VARCHAR(32) NOT NULL, gendate TIMESTAMP NOT NULL);" >nul 2>&1

REM 8. DASHBOARD K8S (Bonus)
echo [8/8] Installation Dashboard K8S...
REM Installation via manifest officiel (le repo Helm kubernetes-dashboard n'est plus disponible)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml >nul 2>&1
echo Attente du demarrage du Dashboard...
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=120s >nul 2>&1

REM Création Admin via fichier temp
echo apiVersion: v1 > admin-user.yaml
echo kind: ServiceAccount >> admin-user.yaml
echo metadata: >> admin-user.yaml
echo   name: admin-user >> admin-user.yaml
echo   namespace: kubernetes-dashboard >> admin-user.yaml
echo --- >> admin-user.yaml
echo apiVersion: rbac.authorization.k8s.io/v1 >> admin-user.yaml
echo kind: ClusterRoleBinding >> admin-user.yaml
echo metadata: >> admin-user.yaml
echo   name: admin-user >> admin-user.yaml
echo roleRef: >> admin-user.yaml
echo   apiGroup: rbac.authorization.k8s.io >> admin-user.yaml
echo   kind: ClusterRole >> admin-user.yaml
echo   name: cluster-admin >> admin-user.yaml
echo subjects: >> admin-user.yaml
echo - kind: ServiceAccount >> admin-user.yaml
echo   name: admin-user >> admin-user.yaml
echo   namespace: kubernetes-dashboard >> admin-user.yaml

kubectl apply -f admin-user.yaml >nul 2>&1
del admin-user.yaml

REM Récupération Token
for /f "tokens=*" %%i in ('kubectl -n kubernetes-dashboard create token admin-user') do set TOKEN=%%i

REM NETTOYAGE (Tuer le tunnel 8080)
taskkill /IM kubectl.exe /F >nul 2>&1

echo.
echo ==============================================
echo 🎉 INSTALLATION TERMINÉE AVEC SUCCÈS ! 🎉
echo ==============================================
echo.
echo Pour utiliser le projet :
echo.
echo 1️⃣  Ouvrez un terminal pour les Tunnels :
echo    kubectl port-forward -n openfaas svc/gateway 8080:8080
echo    kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard 8443:443
echo.
echo 2️⃣  Ouvrez un terminal pour le Frontend :
echo    cd frontend ^&^& python -m http.server 8000
echo.
echo 3️⃣  Accédez à :
echo    Web: http://localhost:8000
echo    Dashboard: https://localhost:8443
echo.
echo 🔑 TOKEN DASHBOARD :
echo %TOKEN%
echo.
pause