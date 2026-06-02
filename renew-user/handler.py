import json
import secrets
import string
import io
import base64
import qrcode
import psycopg2
import datetime
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
        # Accept JSON {"username":"..."} or plain text
        try:
            payload = json.loads(req)
            username = payload.get("username", "").strip()
        except (json.JSONDecodeError, AttributeError):
            username = req.strip() if isinstance(req, str) else ""

        if not username:
            return json.dumps({"error": "Username required"}), 400, headers

        conn = psycopg2.connect(
            host="postgres",
            database="cofrap_db",
            user="postgres",
            password="monSuperMotDePasse"
        )
        cur = conn.cursor()

        cur.execute("SELECT id FROM users WHERE username = %s", (username,))
        result = cur.fetchone()

        if not result:
            cur.close()
            conn.close()
            return json.dumps({"error": "User not found"}), 404, headers

        # Regenerate password
        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = ''.join(secrets.choice(alphabet) for i in range(24))

        # Regenerate TOTP secret + QR code
        mfa_secret = pyotp.random_base32()
        totp_uri = pyotp.totp.TOTP(mfa_secret).provisioning_uri(name=username, issuer_name="COFRAP")

        img = qrcode.make(totp_uri)
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()

        timestamp = datetime.datetime.now()

        cur.execute(
            "UPDATE users SET password = %s, mfa = %s, gendate = %s, failed_attempts = 0, locked_until = NULL WHERE username = %s",
            (password, mfa_secret, timestamp, username)
        )
        conn.commit()
        cur.close()
        conn.close()

        return json.dumps({
            "qr_code": img_str,
            "password_generated": password,
            "message": "Account renewed. Scan new QR Code.",
            "status": "renewed"
        }), 200, headers

    except Exception as e:
        return json.dumps({"error": str(e)}), 500, headers
