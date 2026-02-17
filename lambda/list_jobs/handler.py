"""
Lambda: List Jobs
Returns paginated list of jobs for the caller's tenant.
"""

import json
import os
import logging
import decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """GET /jobs — list all jobs for the caller's tenant."""
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    tenant_id = auth_context.get("tenant_id", "")

    if not tenant_id:
        return _response(403, {"error": "No tenant associated with this user"})

    query_params = event.get("queryStringParameters") or {}
    limit = min(int(query_params.get("limit", "20")), 100)
    next_token = query_params.get("next_token")

    kwargs = {
        "IndexName": "tenant-index",
        "KeyConditionExpression": "tenant_id = :tid",
        "ExpressionAttributeValues": {":tid": tenant_id},
        "ScanIndexForward": False,  # newest first
        "Limit": limit,
    }

    if next_token:
        import base64
        kwargs["ExclusiveStartKey"] = json.loads(
            base64.b64decode(next_token).decode()
        )

    result = table.query(**kwargs)

    items = [_sanitize(item) for item in result.get("Items", [])]

    response_body = {
        "tenant_id": tenant_id,
        "jobs": items,
        "count": len(items),
    }

    if "LastEvaluatedKey" in result:
        import base64
        response_body["next_token"] = base64.b64encode(
            json.dumps(result["LastEvaluatedKey"]).encode()
        ).decode()

    return _response(200, response_body)


def _sanitize(item: dict) -> dict:
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
