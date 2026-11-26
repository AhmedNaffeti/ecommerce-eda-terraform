import common as c
from botocore.exceptions import ClientError

SOURCE = "ecommerce.warehouse"


def handler(event, context):
    return c.process_sqs(event, on_event)


def on_event(detail_type, detail):
    if detail_type != "OrderCreated":
        return
    order_id = detail["order_id"]
    inventory = c.table("INVENTORY_TABLE")
    marker_key = f"RESERVATION#{order_id}"

    # Idempotency: SQS is at-least-once, so a redelivery must not reserve twice
    if inventory.get_item(Key={"product_id": marker_key}).get("Item"):
        return c.publish_event(SOURCE, "StockReserved", detail)

    quantities = {}
    for line in detail["items"]:
        quantities[line["product_id"]] = quantities.get(line["product_id"], 0) + int(line["quantity"])

    # All-or-nothing stock reservation
    tx = [{
        "Update": {
            "TableName": inventory.name,
            "Key": {"product_id": pid},
            "UpdateExpression": "SET stock = stock - :q",
            "ConditionExpression": "stock >= :q",
            "ExpressionAttributeValues": {":q": qty},
        }
    } for pid, qty in quantities.items()]
    tx.append({
        "Put": {
            "TableName": inventory.name,
            "Item": {"product_id": marker_key, "items": quantities, "created_at": c.now()},
            "ConditionExpression": "attribute_not_exists(product_id)",
        }
    })

    try:
        c.db_client().transact_write_items(TransactItems=tx)
    except ClientError as err:
        if err.response["Error"]["Code"] == "TransactionCanceledException":
            return c.publish_event(SOURCE, "StockRejected", {**detail, "reason": "insufficient_stock"})
        raise

    c.publish_event(SOURCE, "StockReserved", detail)
