"""Simple print-based smoke test. Run from the project folder after `terraform apply`:
    python tests/smoke_test.py
Needs: pip install boto3 ; Learner Lab credentials active.
"""
import json
import subprocess
import time
import urllib.error
import urllib.request

import boto3

EMAIL = "test.user@example.com"
PASSWORD = "Passw0rd"


def tf_output():
    raw = subprocess.check_output(["terraform", "output", "-json"], text=True)
    return {k: v["value"] for k, v in json.loads(raw).items()}


def call(method, url, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or "null")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def check(name, ok, detail=""):
    print(("PASS" if ok else "FAIL"), "-", name, detail)


out = tf_output()
api = out["api_url"]
pool, client = out["cognito_user_pool_id"], out["cognito_client_id"]
cog = boto3.client("cognito-idp", region_name="us-east-1")

# 1. public route works, protected route refuses anonymous calls
status, _ = call("GET", f"{api}/products")
check("GET /products (public)", status == 200, status)
status, _ = call("POST", f"{api}/orders", body={"items": []})
check("POST /orders without token -> 401", status == 401, status)

# 2. create + confirm user, add to admins, login
try:
    cog.sign_up(ClientId=client, Username=EMAIL, Password=PASSWORD)
except cog.exceptions.UsernameExistsException:
    print("INFO - user already exists")
cog.admin_confirm_sign_up(UserPoolId=pool, Username=EMAIL)
cog.admin_add_user_to_group(UserPoolId=pool, Username=EMAIL, GroupName="admins")
auth = cog.initiate_auth(
    ClientId=client,
    AuthFlow="USER_PASSWORD_AUTH",
    AuthParameters={"USERNAME": EMAIL, "PASSWORD": PASSWORD},
)
token = auth["AuthenticationResult"]["IdToken"]
check("Cognito login", bool(token))

# 3. create a product (admin) with stock 5
status, product = call("POST", f"{api}/products", token, {"name": "Laptop", "price": 999.9, "stock": 5})
check("POST /products (admin)", status == 201, status)
pid = product["id"]

# 4. create an order and wait for the event-driven workflow
status, order = call("POST", f"{api}/orders", token, {"items": [{"product_id": pid, "quantity": 1}]})
check("POST /orders -> 202 PENDING", status == 202 and order["status"] == "PENDING", status)

final = "PENDING"
for _ in range(15):
    time.sleep(2)
    _, got = call("GET", f"{api}/orders/{order['order_id']}", token)
    final = got["status"]
    if final != "PENDING":
        break
check("Workflow finished (CONFIRMED or CANCELLED)", final in ("CONFIRMED", "CANCELLED"), final)

# 5. out of stock -> CANCELLED
status, big = call("POST", f"{api}/orders", token, {"items": [{"product_id": pid, "quantity": 999}]})
time.sleep(8)
_, got = call("GET", f"{api}/orders/{big['order_id']}", token)
check("Order > stock -> CANCELLED", got["status"] == "CANCELLED", got["status"])
