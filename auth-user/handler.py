import json
import psycopg2
import pyotp

def handle(req):
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS, POST, GET",
        "Access-Control-Allow-Headers": "Content-Type",
        "Content-Type": "application/json"
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

        conn = psycopg2.connect(
            host="postgres",
            database="cofrap_db",
            user="postgres",
            password="monSuperMotDePasse"
        )
        cur = conn.cursor()
        
        cur.execute(
            "SELECT password, mfa FROM users WHERE username = %s",
            (username,)
        )
        result = cur.fetchone()
        cur.close()
        conn.close()

        if not result:
            return json.dumps({
                "auth": False,
                "reason": "Utilisateur inexistant"
            }), 401, headers

        db_password, mfa_secret = result

        if db_password != password:
            return json.dumps({
                "auth": False,
                "reason": "Mot de passe incorrect"
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

