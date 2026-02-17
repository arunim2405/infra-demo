"""
Lambda: Get Job Status
Returns task metadata from DynamoDB and pre-signed S3 URLs for outputs.
Enforces tenant ownership via authorizer context.
"""

import json
import os
import logging
import decimal

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
S3_BUCKET = os.environ["S3_BUCKET"]
PRESIGN_EXPIRY = int(os.environ.get("PRESIGN_EXPIRY", "3600"))

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """GET /jobs/{task_id} — return task metadata and output URLs."""
    task_id = event.get("pathParameters", {}).get("task_id")

    if not task_id:
        return _response(400, {"error": "task_id is required"})

    # Verify tenant ownership
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    caller_tenant_id = auth_context.get("tenant_id", "")

    # Fetch from DynamoDB
    result = table.get_item(Key={"task_id": task_id})
    item = result.get("Item")

    if not item:
        return _response(404, {"error": f"Task {task_id} not found"})

    # Enforce tenant isolation
    if item.get("tenant_id") != caller_tenant_id:
        return _response(403, {"error": "You do not have access to this task"})

    # Convert Decimal types for JSON serialization
    task_data = _sanitize_item(item)

    # If completed, generate pre-signed URLs
    if task_data.get("status") in ("COMPLETED", "FAILED"):
        task_data["outputs"] = _get_output_urls(task_id)

    return _response(200, task_data)


def _get_output_urls(task_id: str) -> dict:
    """Generate pre-signed URLs for task output files."""
    output_keys = [
        ("screenshot", f"tasks/{task_id}/screenshot.png"),
        ("execution_log", f"tasks/{task_id}/execution.log"),
        ("error", f"tasks/{task_id}/error.json"),
        ("heartbeat", f"tasks/{task_id}/heartbeat.json"),
    ]

    urls = {}
    for name, key in output_keys:
        try:
            # Check if the object exists
            s3.head_object(Bucket=S3_BUCKET, Key=key)
            url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": S3_BUCKET, "Key": key},
                ExpiresIn=PRESIGN_EXPIRY,
            )
            urls[name] = url
        except ClientError:
            pass  # Object doesn't exist

    return urls


def _sanitize_item(item: dict) -> dict:
    """Convert DynamoDB Decimal types to int/float for JSON."""
    sanitized = {}
    for key, value in item.items():
        if isinstance(value, decimal.Decimal):
            sanitized[key] = int(value) if value == int(value) else float(value)
        else:
            sanitized[key] = value
    return sanitized


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
        },
        "body": json.dumps(body),
    }
