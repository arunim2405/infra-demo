"""
Lambda: Register Tenant
Called after first Cognito sign-up. Creates a tenant and registers user as ADMIN.
If the user already has a tenant, returns existing info.
"""

import json
import os
import uuid
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

USERS_TABLE = os.environ["USERS_TABLE"]

users_table = dynamodb.Table(USERS_TABLE)


def handler(event, context):
    """POST /tenants/register — register current user + create tenant."""
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    cognito_id = auth_context.get("cognito_id", "")
    email = auth_context.get("email", "")

    if not cognito_id:
        return _response(401, {"error": "Unauthorized"})

    # Check if user already exists
    result = users_table.get_item(Key={"cognito_id": cognito_id})
    existing_user = result.get("Item")

    if existing_user:
        return _response(200, {
            "message": "User already registered",
            "tenant_id": existing_user.get("tenant_id"),
            "role": existing_user.get("role"),
            "email": existing_user.get("email"),
        })

    # Parse optional tenant_name from body
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        body = {}

    tenant_name = body.get("tenant_name", f"{email}'s team")
    tenant_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    # Create the user as ADMIN of the new tenant
    user_item = {
        "cognito_id": cognito_id,
        "email": email,
        "tenant_id": tenant_id,
        "tenant_name": tenant_name,
        "role": "ADMIN",
        "created_at": now,
    }

    users_table.put_item(
        Item=user_item,
        ConditionExpression="attribute_not_exists(cognito_id)",
    )

    logger.info("Created tenant %s for user %s", tenant_id, cognito_id)

    return _response(201, {
        "message": "Tenant created successfully",
        "tenant_id": tenant_id,
        "role": "ADMIN",
        "tenant_name": tenant_name,
    })


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
