from decimal import Decimal

import common as c
from boto3.dynamodb.conditions import Key

SOURCE = "ecommerce.orders"

# Outcome events consumed from the orders queue -> (new status, reason)
OUTCOMES = {
    "StockRejected": ("CANCELLED", "out_of_stock"),
    "PaymentSucceeded": ("CONFIRMED", ""),
    "PaymentFailed": ("CANCELLED", "payment_failed"),
}


def handler(event, context):
    if "Records" in event:  # triggered by SQS
        return c.process_sqs(event, on_event)
    return on_http(event)  # triggered by API Gateway


# ---------- event-driven side ----------
def on_event(detail_type, detail):
    status, reason = OUTCOMES[detail_type]
    c.table("ORDERS_TABLE").update_item(
        Key={"order_id": detail["order_id"]},
        UpdateExpression="SET #s = :s, reason = :r, updated_at = :t",
        ConditionExpression="attribute_exists(order_id)",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": status, ":r": reason, ":t": c.now()},
    )
    c.notify(f"Order {status}", {"order_id": detail["order_id"], "status": status, "reason": reason})


# ---------- HTTP side ----------
def on_http(event):
    claims = c.claims(event)
    user = claims.get("sub")
    if not user:
        return c.response(401, {"message": "Unauthorized"})

    method = event["httpMethod"]
    order_id = (event.get("pathParameters") or {}).get("id")
    orders = c.table("ORDERS_TABLE")

    if method == "POST":
        return create_order(user, claims.get("email", ""), c.loads(event.get("body") or "{}"))

    if method == "GET" and order_id:
        item = orders.get_item(Key={"order_id": order_id}).get("Item")
        if not item or item["customer_id"] != user:
            return c.response(404, {"message": "Order not found"})
        return c.response(200, item)

    if method == "GET":
        res = orders.query(
            IndexName="customer-index",
            KeyConditionExpression=Key("customer_id").eq(user),
            ScanIndexForward=False,
        )
        return c.response(200, res["Items"])

    return c.response(405, {"message": "Method not allowed"})


def create_order(user, email, body):
    products = c.table("PRODUCTS_TABLE")
    lines, total = [], Decimal(0)

    for it in body.get("items") or []:
        pid, qty = it.get("product_id"), int(it.get("quantity", 0))
        if not pid or qty <= 0:
            return c.response(400, {"message": "Each item needs product_id and quantity > 0"})
        product = products.get_item(Key={"id": pid}).get("Item")
        if not product:
            return c.response(400, {"message": f"Unknown product {pid}"})
        lines.append({"product_id": pid, "quantity": qty, "unit_price": product["price"]})
        total += Decimal(product["price"]) * qty

    if not lines:
        return c.response(400, {"message": "items must not be empty"})

    order = {
        "order_id": c.new_id(),
        "customer_id": user,
        "customer_email": email,
        "items": lines,
        "amount": total,
        "status": "PENDING",
        "created_at": c.now(),
        "updated_at": c.now(),
    }
    c.table("ORDERS_TABLE").put_item(Item=order)
    c.publish_event(SOURCE, "OrderCreated", {
        "order_id": order["order_id"], "customer_id": user, "items": lines, "amount": total,
    })
    c.notify("Order received", {"order_id": order["order_id"], "status": "PENDING"})
    return c.response(202, order)
