import json
import psycopg2
import pyotp
import datetime

PASSWORD_EXPIRY_DAYS = 180
MAX_FAILED_ATTEMPTS = 5
LOCKOUT_MINUTES = 15

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
            "SELECT password, mfa, gendate, failed_attempts, locked_until FROM users WHERE username = %s",
            (username,)
        )
        result = cur.fetchone()

        if not result:
            cur.close()
            conn.close()
            return json.dumps({
                "auth": False,
                "reason": "Utilisateur inexistant"
            }), 401, headers

        db_password, mfa_secret, gendate, failed_attempts, locked_until = result

        # Check account lockout
        now = datetime.datetime.now()
        if locked_until and now < locked_until:
            remaining = int((locked_until - now).total_seconds() / 60) + 1
            cur.close()
            conn.close()
            return json.dumps({
                "auth": False,
                "reason": f"Compte verrouillé. Réessayez dans {remaining} minute(s)."
            }), 403, headers

        # Check password expiry
        if gendate:
            if isinstance(gendate, str):
                try:
                    gendate = datetime.datetime.fromisoformat(gendate)
                except ValueError:
                    gendate = datetime.datetime.strptime(gendate, "%Y-%m-%d %H:%M:%S.%f")
            age_days = (now - gendate).days
            if age_days > PASSWORD_EXPIRY_DAYS:
                cur.close()
                conn.close()
                return json.dumps({
                    "auth": False,
                    "reason": f"Mot de passe expiré (>{PASSWORD_EXPIRY_DAYS} jours). Recréez votre compte."
                }), 403, headers

        # Validate password
        if db_password != password:
            new_attempts = failed_attempts + 1
            if new_attempts >= MAX_FAILED_ATTEMPTS:
                lockout_until = now + datetime.timedelta(minutes=LOCKOUT_MINUTES)
                cur.execute(
                    "UPDATE users SET failed_attempts = %s, locked_until = %s WHERE username = %s",
                    (new_attempts, lockout_until, username)
                )
                conn.commit()
                cur.close()
                conn.close()
                return json.dumps({
                    "auth": False,
                    "reason": f"Trop de tentatives. Compte verrouillé {LOCKOUT_MINUTES} minutes."
                }), 403, headers
            else:
                cur.execute(
                    "UPDATE users SET failed_attempts = %s WHERE username = %s",
                    (new_attempts, username)
                )
                conn.commit()
                cur.close()
                conn.close()
                remaining_attempts = MAX_FAILED_ATTEMPTS - new_attempts
                return json.dumps({
                    "auth": False,
                    "reason": f"Mot de passe incorrect. {remaining_attempts} tentative(s) restante(s)."
                }), 401, headers

        # Validate 2FA
        totp = pyotp.TOTP(mfa_secret)
        if not totp.verify(code_2fa):
            new_attempts = failed_attempts + 1
            if new_attempts >= MAX_FAILED_ATTEMPTS:
                lockout_until = now + datetime.timedelta(minutes=LOCKOUT_MINUTES)
                cur.execute(
                    "UPDATE users SET failed_attempts = %s, locked_until = %s WHERE username = %s",
                    (new_attempts, lockout_until, username)
                )
                conn.commit()
                cur.close()
                conn.close()
                return json.dumps({
                    "auth": False,
                    "reason": f"Trop de tentatives. Compte verrouillé {LOCKOUT_MINUTES} minutes."
                }), 403, headers
            else:
                cur.execute(
                    "UPDATE users SET failed_attempts = %s WHERE username = %s",
                    (new_attempts, username)
                )
                conn.commit()
                cur.close()
                conn.close()
                remaining_attempts = MAX_FAILED_ATTEMPTS - new_attempts
                return json.dumps({
                    "auth": False,
                    "reason": f"Code 2FA invalide. {remaining_attempts} tentative(s) restante(s)."
                }), 401, headers

        # Success — reset failed attempts
        cur.execute(
            "UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE username = %s",
            (username,)
        )
        conn.commit()
        cur.close()
        conn.close()

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
