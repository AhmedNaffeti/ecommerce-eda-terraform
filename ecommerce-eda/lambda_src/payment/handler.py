import os
import random

import common as c

SOURCE = "ecommerce.payment"


def handler(event, context):
    return c.process_sqs(event, on_event)


def on_event(detail_type, detail):
    if detail_type != "StockReserved":
        return
    order_id = detail["order_id"]
    payments = c.table("PAYMENTS_TABLE")

    existing = payments.get_item(Key={"order_id": order_id}).get("Item")
    if existing:  # redelivery: replay the same outcome
        payment = existing
    else:
        # Simulated payment provider - replace with Stripe/Adyen/etc. in production
        failed = random.random() < float(os.environ.get("PAYMENT_FAILURE_RATE", "0.1"))
        payment = {
            "order_id": order_id,
            "payment_id": c.new_id(),
            "amount": detail["amount"],
            "status": "FAILED" if failed else "SUCCEEDED",
            "created_at": c.now(),
        }
        # Conditional write: if a concurrent delivery won, raise and let SQS retry
        payments.put_item(Item=payment, ConditionExpression="attribute_not_exists(order_id)")

    outcome = "PaymentSucceeded" if payment["status"] == "SUCCEEDED" else "PaymentFailed"
    c.publish_event(SOURCE, outcome, {
        "order_id": order_id,
        "customer_id": detail["customer_id"],
        "payment_id": payment["payment_id"],
        "amount": payment["amount"],
    })
