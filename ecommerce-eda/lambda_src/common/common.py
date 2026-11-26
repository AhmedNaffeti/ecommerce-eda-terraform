"""Shared helpers packaged into every Lambda."""
import json
import logging
import os
import uuid
from datetime import UTC, datetime
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_dynamodb = boto3.resource("dynamodb")
_events = boto3.client("events")
_sns = boto3.client("sns")

HEADERS = {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}


class _Encoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return int(o) if o == o.to_integral_value() else float(o)
        return super().default(o)


def dumps(obj):
    return json.dumps(obj, cls=_Encoder)


def loads(s):
    return json.loads(s, parse_float=Decimal)


def response(status, body):
    return {"statusCode": status, "headers": HEADERS, "body": dumps(body)}


def table(env_name):
    return _dynamodb.Table(os.environ[env_name])


def db_client():
    return _dynamodb.meta.client  # accepts native Python types


def now():
    return datetime.now(UTC).isoformat()


def new_id():
    return str(uuid.uuid4())


def claims(event):
    return (event.get("requestContext", {}).get("authorizer") or {}).get("claims") or {}


def publish_event(source, detail_type, detail):
    res = _events.put_events(Entries=[{
        "EventBusName": os.environ["EVENT_BUS_NAME"],
        "Source": source,
        "DetailType": detail_type,
        "Detail": dumps(detail),
    }])
    if res["FailedEntryCount"]:
        raise RuntimeError(f"PutEvents failed: {res['Entries']}")


def notify(subject, message):
    _sns.publish(TopicArn=os.environ["SNS_TOPIC_ARN"], Subject=subject[:100], Message=dumps(message))


def process_sqs(event, fn):
    """Run fn(detail_type, detail) per SQS record; report partial batch failures."""
    failures = []
    for record in event["Records"]:
        try:
            envelope = loads(record["body"])  # EventBridge envelope
            fn(envelope["detail-type"], envelope["detail"])
        except Exception:
            logger.exception("Failed to process message %s", record["messageId"])
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
