import json
import secrets
import string
import io
import base64
import qrcode
import psycopg2
import datetime
import pyotp  # Nouvelle librairie

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
        username = req
        
        # 1. Générer MDP
        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = ''.join(secrets.choice(alphabet) for i in range(24))

        # 2. Générer Secret 2FA (TOTP)
        mfa_secret = pyotp.random_base32()
        
        # 3. Générer QR Code (Pour l'appli 2FA, c'est plus utile que le MDP)
        # URI standard pour Google Authenticator
        totp_uri = pyotp.totp.TOTP(mfa_secret).provisioning_uri(name=username, issuer_name="COFRAP")
        
        img = qrcode.make(totp_uri)
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()

        # 4. Insertion DB
        conn = psycopg2.connect(
            host="postgres",
            database="cofrap_db",
            user="postgres",
            password="monSuperMotDePasse"
        )
        cur = conn.cursor()
        
        timestamp = datetime.datetime.now()
        
        # On sauvegarde le MDP et le Secret MFA
        cur.execute(
            "INSERT INTO users (username, password, mfa, gendate) VALUES (%s, %s, %s, %s)",
            (username, password, mfa_secret, timestamp)
        )
        conn.commit()
        cur.close()
        conn.close()

        response_body = {
            "qr_code": img_str,
            "password_generated": password, # On renvoie le MDP pour que l'user puisse le noter
            "message": "Compte créé. Scannez le QR Code dans Google Authenticator."
        }

        return json.dumps(response_body), 200, headers

    except Exception as e:
        return json.dumps({"error": str(e)}), 500, headers
