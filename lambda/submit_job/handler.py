"""
Lambda: Submit Job
Accepts a job request via API Gateway, writes metadata to DynamoDB, and queues the job in SQS.
"""

import json
import os
import uuid
import time
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
QUEUE_URL = os.environ["SQS_QUEUE_URL"]

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """POST /jobs — submit a new computer-use job."""
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    query = body.get("query")
    tenant_id = body.get("tenant_id", "default")

    if not query:
        return _response(400, {"error": "'query' is required"})

    task_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    ttl = int(time.time()) + 7 * 24 * 3600  # 7 days

    # Write to DynamoDB
    item = {
        "task_id": task_id,
        "tenant_id": tenant_id,
        "query": query,
        "status": "PENDING",
        "created_at": now,
        "updated_at": now,
        "ttl": ttl,
    }
    table.put_item(Item=item)

    # Queue in SQS
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({"task_id": task_id, "query": query, "tenant_id": tenant_id}),
    )

    return _response(202, {"task_id": task_id, "status": "PENDING"})


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }
