# COFRAP — Secure Serverless Auth Portal

A serverless authentication portal built on **OpenFaaS + Kubernetes + PostgreSQL**, featuring password generation and TOTP-based two-factor authentication (2FA).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                              │
│                   frontend/index.html                       │
│              (served via python3 -m http.server)            │
└───────────────────────┬─────────────────────────────────────┘
                        │ HTTP  (localhost:8080)
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenFaaS Gateway  (port-forward)               │
│                   http://127.0.0.1:8080                     │
└────────────┬──────────────┬──────────────┬──────────────────┘
             │              │              │
             ▼              ▼              ▼
      ┌────────────┐ ┌────────────┐ ┌────────────┐
      │register-   │ │  auth-user │ │ renew-user │
      │   user     │ │            │ │            │
      └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
            │              │              │
            └──────────────┼──────────────┘
                           │ psycopg2 (port 5432)
                           ▼
             ┌─────────────────────────┐
             │   PostgreSQL (pod)      │
             │   database: cofrap_db   │
             │   namespace: openfaas-fn│
             └─────────────────────────┘
```

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Docker Desktop** | Container runtime + local Kubernetes | [docs.docker.com](https://docs.docker.com/desktop/) |
| **kubectl** | Kubernetes CLI (bundled with Docker Desktop) | included |
| **helm** | Kubernetes package manager | `brew install helm` |
| **faas-cli** | OpenFaaS function build & deploy | `brew install faas-cli` |

> Docker Desktop → Settings → Kubernetes → **Enable Kubernetes** must be checked before running the install script.

---

## Quick Start

```bash
git clone <your-repo>
cd mspr-serverless
chmod +x install.sh
./install.sh
```

Windows (PowerShell):
```powershell
.\install.ps1
```

Windows (CMD):
```cmd
install.bat
```

The script handles everything: OpenFaaS deployment, PostgreSQL setup, function build & push, Kubernetes Dashboard install, and database initialisation.

---

## Manual Startup

After installation, use these commands each time you want to use the project (the install script prints them at the end):

**Terminal 1 — Tunnels:**
```bash
# Free port 8080 first if needed
lsof -ti:8080 | xargs kill -9 2>/dev/null || true

# OpenFaaS gateway
kubectl port-forward -n openfaas svc/gateway 8080:8080 &

# Kubernetes Dashboard
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

**Terminal 2 — Frontend:**
```bash
cd frontend
python3 -m http.server 8000
```

**Access:**
| Service | URL |
|---------|-----|
| Web portal | http://localhost:8000 |
| Kubernetes Dashboard | https://localhost:8443 |

---

## Endpoint Reference

All functions are reached via the OpenFaaS gateway: `http://127.0.0.1:8080/function/<name>`

---

### `POST /function/register-user`

Creates a new account, or overwrites an existing one.

**Request body:** plain text username

```
alice
```

**Response `200`:**
```json
{
  "qr_code": "<base64 PNG>",
  "password_generated": "xK#9mP...",
  "message": "Compte créé. Scannez le QR Code dans Google Authenticator.",
  "status": "created"
}
```

`status` is `"created"` for new accounts, `"renewed"` if the username already existed (credentials are reset).

**Response `500`:**
```json
{ "error": "<description>" }
```

---

### `POST /function/auth-user`

Authenticates a user with password + TOTP code.

**Request body:** JSON

```json
{
  "username": "alice",
  "password": "xK#9mP...",
  "code_2fa": "123456"
}
```

**Response `200` — success:**
```json
{ "auth": true, "message": "Authentification réussie !" }
```

**Response `401` — wrong credentials:**
```json
{ "auth": false, "reason": "Identifiants invalides" }
```

**Response `401` — account expired (> 6 months old):**
```json
{ "auth": false, "action": "renew" }
```

The frontend automatically triggers `renew-user` when it receives `action: "renew"`.

**Response `400`:**
```json
{ "auth": false, "reason": "Champs manquants" }
```

**Response `503`:**
```json
{ "error": "Database unavailable" }
```

---

### `POST /function/renew-user`

Regenerates credentials for an existing account (new password + new TOTP secret + new QR code). Resets the 6-month expiry clock.

**Request body:** JSON or plain text username

```json
{ "username": "alice" }
```

**Response `200`:**
```json
{
  "qr_code": "<base64 PNG>",
  "password_generated": "nR@7wQ...",
  "message": "Compte renouvelé. Scannez le nouveau QR Code dans Google Authenticator.",
  "status": "renewed"
}
```

**Response `404`:**
```json
{ "error": "Utilisateur introuvable" }
```

**Response `503`:**
```json
{ "error": "Database unavailable" }
```

---

## Database Schema

```sql
CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password TEXT        NOT NULL,   -- bcrypt hash (improvement 8)
    mfa      TEXT        NOT NULL,   -- TOTP base32 secret
    gendate  BIGINT      NOT NULL,   -- Unix timestamp of last registration/renewal
    expired  INT         DEFAULT 0   -- 1 = account expired, must renew
);
```

---

## Known Limitations & PoC Scope

This project is a **proof-of-concept** for the MSPR EPSI exercise. The following limitations are intentional or known:

- **No TLS on the API** — the OpenFaaS gateway is accessed over plain HTTP via a local port-forward. Credentials and 2FA codes are not encrypted in transit in this setup.
- **Wildcard CORS** — all origins are allowed (`*`). Acceptable for local development, not for production.
- **Hardcoded DB credentials** — `monSuperMotDePasse` is used throughout. In a production system these would live in a secrets manager.
- **No rate limiting** — the auth endpoint has no brute-force protection.
- **No session management** — there is no JWT or session token issued after successful login. Each page load starts fresh.
- **Single-node PostgreSQL** — the database runs as a single pod with no persistent volume, so data is lost if the pod restarts.
- **Docker Hub images** — functions are pushed to a public Docker Hub registry (`martinpavy/*`). Use a private registry for sensitive workloads.
- **No CI/CD** — deployment is manual via `faas-cli up`.

---

## Project Structure

```
mspr-serverless/
├── register-user/        # OpenFaaS function — account creation
│   ├── handler.py
│   └── requirements.txt
├── auth-user/            # OpenFaaS function — authentication + expiry check
│   ├── handler.py
│   └── requirements.txt
├── renew-user/           # OpenFaaS function — credential renewal
│   ├── handler.py
│   └── requirements.txt
├── frontend/
│   └── index.html        # Single-page UI
├── template/             # OpenFaaS function templates
├── postgres.yaml         # PostgreSQL pod + service
├── stack.yaml            # OpenFaaS function registry
├── install.sh            # Install script — Linux/macOS
├── install.ps1           # Install script — Windows PowerShell
├── install.bat           # Install script — Windows CMD
└── README.md
```

---

*COFRAP — MSPR EPSI*
