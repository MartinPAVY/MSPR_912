#!/bin/bash

# ==========================================
# SCRIPT D'INSTALLATION AUTOMATISÉE MSPR
# ==========================================

# Couleurs pour la lisibilité
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Démarrage de l'installation du projet Serverless MSPR...${NC}"

# 1. VÉRIFICATION DES PRÉ-REQUIS
# ------------------------------------------
echo -e "${BLUE}[1/7] Vérification de l'environnement...${NC}"

# Vérifier si Docker tourne
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}❌ Erreur : Docker n'est pas lancé.${NC}"
  echo "Veuillez lancer Docker Desktop et réessayer."
  exit 1
fi

# Vérifier si Kubernetes est activé
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo -e "${RED}❌ Erreur : Kubernetes n'est pas accessible.${NC}"
  echo "Vérifiez que 'Enable Kubernetes' est coché dans Docker Desktop settings."
  exit 1
fi

# 2. INSTALLATION DES OUTILS (Via Homebrew)
# ------------------------------------------
echo -e "${BLUE}[2/7] Installation des dépendances...${NC}"

if ! command -v brew &> /dev/null; then
    echo -e "${RED}❌ Homebrew n'est pas installé. Installez-le d'abord.${NC}"
    exit 1
fi

list_tools=(helm faas-cli kubectl)
for tool in "${list_tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "Installation de $tool..."
        brew install $tool
    else
        echo "✅ $tool est déjà installé."
    fi
done

# 3. DÉPLOIEMENT OPENFAAS (Via Helm)
# ------------------------------------------
echo -e "${BLUE}[3/7] Installation d'OpenFaaS sur le cluster...${NC}"

# Ajout des repos Helm
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml > /dev/null 2>&1
helm repo add openfaas https://openfaas.github.io/faas-netes/ > /dev/null 2>&1
helm repo update > /dev/null 2>&1

# Installation du chart
helm upgrade openfaas --install openfaas/openfaas \
    --namespace openfaas \
    --set functionNamespace=openfaas-fn \
    --set generateBasicAuth=true \
    --wait

echo "✅ OpenFaaS est déployé."

# 4. CONNEXION CLI (Login)
# ------------------------------------------
echo -e "${BLUE}[4/7] Connexion à OpenFaaS...${NC}"

# On lance un port-forward temporaire en arrière-plan pour se connecter
kubectl port-forward -n openfaas svc/gateway 8080:8080 > /dev/null 2>&1 &
PID_FWD=$!
sleep 5 # Attendre que le tunnel s'ouvre

PASSWORD=$(kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
echo -n $PASSWORD | faas-cli login --username admin --password-stdin

echo "✅ Connecté avec succès (Admin Password récupéré)."

# 5. DÉPLOIEMENT INFRA (DB + Fonctions)
# ------------------------------------------
echo -e "${BLUE}[5/7] Déploiement de la Base de Données...${NC}"

# Appliquer le fichier postgres.yaml (Doit être dans le même dossier)
if [ -f "postgres.yaml" ]; then
    kubectl apply -f postgres.yaml
    echo "Attente du démarrage de PostgreSQL..."
    kubectl wait --for=condition=ready pod -l app=postgres -n openfaas-fn --timeout=60s
else
    echo -e "${RED}❌ Fichier postgres.yaml introuvable !${NC}"
    kill $PID_FWD
    exit 1
fi

echo -e "${BLUE}[6/7] Construction et Déploiement des Fonctions...${NC}"
# Nécessite d'être connecté au Docker Hub
echo "⚠️ Assurez-vous d'être connecté à Docker Hub (docker login)."
# 1. On force la suppression des images locales pour être sûr
docker rmi -f martinpavy/auth-user:v6
docker rmi -f martinpavy/register-user:v6

# 2. On lance la construction avec l'option --no-cache (C'est ça le secret)
echo "🚧 Construction forcée sans cache..."
faas-cli up -f stack.yaml --no-cache

# 6. INITIALISATION DONNÉES
# ------------------------------------------
echo -e "${BLUE}[7/7] Création de la table SQL 'users'...${NC}"

# On attend un peu que Postgres soit prêt à recevoir des commandes
sleep 5
kubectl exec -it -n openfaas-fn postgres -- psql -U postgres -d cofrap_db -c "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, username VARCHAR(50), password TEXT, mfa TEXT, gendate VARCHAR(50), expired INT DEFAULT 0);"

# ------------------------------------------
# 7. INSTALLATION DU DASHBOARD K8S (Bonus)
# ------------------------------------------
echo -e "${BLUE}[8/8] Installation du Dashboard Kubernetes...${NC}"

# Ajout du repo Helm officiel
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ > /dev/null 2>&1
helm repo update > /dev/null 2>&1

# Installation du Dashboard
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --create-namespace --namespace kubernetes-dashboard \
    --set protocolHttp=true \
    --set service.externalPort=9090 \
    --wait > /dev/null 2>&1

# Création du compte Admin (Indispensable pour voir les ressources)
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
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
EOF

echo "✅ Dashboard installé."

# Récupération du Token de connexion
# Note: La commande change selon les versions de K8s, celle-ci est la plus robuste pour Docker Desktop récent
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)

# ------------------------------------------

# 8. NETTOYAGE ET INSTRUCTIONS FINALES
# ------------------------------------------
# On tue le port-forward temporaire car l'utilisateur doit le lancer lui-même pour voir les logs
kill $PID_FWD

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}🎉 INSTALLATION TERMINÉE AVEC SUCCÈS ! 🎉${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""
echo "Pour utiliser votre projet, ouvrez 2 terminaux :"
echo ""
echo -e "1️⃣  ${BLUE}Terminal 1 (Tunnel OpenFaaS & Dashboard) :${NC}"
echo "   kubectl port-forward -n openfaas svc/gateway 8080:8080 &"
echo "   kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443"
echo ""
echo -e "2️⃣  ${BLUE}Terminal 2 (Serveur Frontend) :${NC}"
echo "   cd frontend && python3 -m http.server 8000"
echo ""
echo -e "3️⃣  ${BLUE}Accès Visuels :${NC}"
echo "   🌍 Site Web : http://localhost:8000"
echo "   📊 Dashboard K8s : https://localhost:8443"
echo ""
echo -e "${RED}🔑 TOKEN POUR LE DASHBOARD (Copiez-le) :${NC}"
echo $TOKEN
echo ""
