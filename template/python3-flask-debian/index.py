from flask import Flask, request, make_response
from flask_cors import CORS
from function import handler
from waitress import serve
import os

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*", "methods": ["GET", "POST", "OPTIONS"], "allow_headers": ["Content-Type"]}})

def is_true(val):
    return len(val) > 0 and val.lower() == "true" or val == "1"

@app.before_request
def fix_transfer_encoding():
    transfer_encoding = request.headers.get("Transfer-Encoding", None)
    if transfer_encoding == u"chunked":
        request.environ["wsgi.input_terminated"] = True

@app.route("/", defaults={"path": ""}, methods=["POST", "GET", "OPTIONS"])
@app.route("/<path:path>", methods=["POST", "GET", "OPTIONS"])
def main_route(path):
    if request.method == "OPTIONS":
        resp = make_response("", 200)
        resp.headers["Access-Control-Allow-Origin"] = "*"
        resp.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
        return resp

    raw_body = os.getenv("RAW_BODY", "false")
    as_text = True
    if is_true(raw_body):
        as_text = False
    
    result = handler.handle(request.get_data(as_text=as_text))
    
    if isinstance(result, tuple):
        body = result[0]
        status_code = result[1] if len(result) > 1 else 200
        headers = result[2] if len(result) > 2 else {}
        
        response = make_response(body, status_code)
        for key, value in headers.items():
            response.headers[key] = value
        
        # Ensure fallback CORS
        if "Access-Control-Allow-Origin" not in response.headers:
            response.headers["Access-Control-Allow-Origin"] = "*"
        return response
    
    response = make_response(result)
    response.headers["Access-Control-Allow-Origin"] = "*"
    return response

if __name__ == '__main__':
    serve(app, host='0.0.0.0', port=5000)
