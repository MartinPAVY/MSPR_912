import json
import re
import time
import psycopg2
import bcrypt
import pyotp

EXPIRY_SECONDS = 15_552_000  # 6 months
USERNAME_RE = re.compile(r'^[a-zA-Z0-9_-]{3,50}$')


def _db_password():
    try:
        with open('/var/openfaas/secrets/db-password') as f:
            return f.read().strip()
    except FileNotFoundError:
        import os
        return os.getenv('DB_PASSWORD', '')


def connect_db():
    for attempt in range(3):
        try:
            return psycopg2.connect(
                host="postgres",
                database="cofrap_db",
                user="postgres",
                password=_db_password()
            )
        except psycopg2.OperationalError:
            if attempt < 2:
                time.sleep(1)
    return None


def handle(req):
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS, POST, GET",
        "Access-Control-Allow-Headers": "Content-Type",
        "Content-Type": "application/json",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
    }

    if req == "" or req is None:
        return "", 200, headers

    try:
        payload = json.loads(req)
        username = payload.get("username", "")
        password = payload.get("password", "")
        code_2fa = payload.get("code_2fa", "")

        if not username or not password or not code_2fa:
            return json.dumps({
                "auth": False,
                "reason": "Champs manquants"
            }), 400, headers

        if not USERNAME_RE.match(username):
            return json.dumps({
                "auth": False,
                "reason": "Nom d'utilisateur invalide"
            }), 400, headers

        conn = connect_db()
        if conn is None:
            return json.dumps({"error": "Database unavailable"}), 503, headers
        cur = conn.cursor()

        cur.execute(
            "SELECT password, mfa, gendate, expired FROM users WHERE username = %s",
            (username,)
        )
        result = cur.fetchone()

        if not result:
            cur.close()
            conn.close()
            return json.dumps({
                "auth": False,
                "reason": "Identifiants invalides"
            }), 401, headers

        db_password_hash, mfa_secret, gendate, expired = result

        # Already marked expired
        if expired == 1:
            cur.close()
            conn.close()
            return json.dumps({
                "auth": False,
                "action": "renew"
            }), 401, headers

        # Check if account has aged past 6 months
        try:
            age = time.time() - int(gendate)
        except (TypeError, ValueError):
            age = 0

        if age > EXPIRY_SECONDS:
            cur.execute(
                "UPDATE users SET expired = 1 WHERE username = %s",
                (username,)
            )
            conn.commit()
            cur.close()
            conn.close()
            return json.dumps({
                "auth": False,
                "action": "renew"
            }), 401, headers

        cur.close()
        conn.close()

        if not bcrypt.checkpw(password.encode(), db_password_hash.encode()):
            return json.dumps({
                "auth": False,
                "reason": "Identifiants invalides"
            }), 401, headers

        totp = pyotp.TOTP(mfa_secret)
        if not totp.verify(code_2fa):
            return json.dumps({
                "auth": False,
                "reason": "Code 2FA invalide"
            }), 401, headers

        return json.dumps({
            "auth": True,
            "message": "Authentification réussie !"
        }), 200, headers

    except json.JSONDecodeError:
        return json.dumps({
            "auth": False,
            "reason": "Format JSON invalide"
        }), 400, headers
    except Exception as e:
        return json.dumps({
            "auth": False,
            "reason": f"Erreur serveur: {str(e)}"
        }), 500, headers
