import json
import re
import secrets
import string
import io
import base64
import time
import qrcode
import psycopg2
import bcrypt
import pyotp

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

    # Accept both plain username string and JSON {"username": "..."}
    try:
        payload = json.loads(req)
        username = payload.get("username", "").strip()
    except (json.JSONDecodeError, AttributeError):
        username = req.strip()

    if not username:
        return json.dumps({"error": "Username requis"}), 400, headers

    if not USERNAME_RE.match(username):
        return json.dumps({
            "error": "Nom d'utilisateur invalide (3-50 caractères : lettres, chiffres, _ -)"
        }), 400, headers

    try:
        conn = connect_db()
        if conn is None:
            return json.dumps({"error": "Database unavailable"}), 503, headers
        cur = conn.cursor()

        cur.execute("SELECT 1 FROM users WHERE username = %s", (username,))
        if cur.fetchone() is None:
            cur.close()
            conn.close()
            return json.dumps({"error": "Utilisateur introuvable"}), 404, headers

        # Generate new credentials
        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = ''.join(secrets.choice(alphabet) for i in range(24))
        password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

        mfa_secret = pyotp.random_base32()

        totp_uri = pyotp.totp.TOTP(mfa_secret).provisioning_uri(name=username, issuer_name="COFRAP")
        img = qrcode.make(totp_uri)
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()

        cur.execute(
            """
            UPDATE users
            SET password = %s,
                mfa      = %s,
                gendate  = %s,
                expired  = 0
            WHERE username = %s
            """,
            (password_hash, mfa_secret, int(time.time()), username)
        )
        conn.commit()
        cur.close()
        conn.close()

        return json.dumps({
            "qr_code": img_str,
            "password_generated": password,
            "message": "Compte renouvelé. Scannez le nouveau QR Code dans Google Authenticator.",
            "status": "renewed"
        }), 200, headers

    except Exception as e:
        return json.dumps({"error": str(e)}), 500, headers
