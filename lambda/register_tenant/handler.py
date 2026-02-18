"""
Lambda: Register Tenant
Called after Cognito sign-in. If the user has a pending invitation,
claims it. Otherwise creates a new tenant and registers user as ADMIN.
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
    """POST /tenants/register — register current user + create or join tenant."""
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    cognito_id = auth_context.get("cognito_id", "")
    email = auth_context.get("email", "")

    if not cognito_id:
        return _response(401, {"error": "Unauthorized"})

    # 1. Check if user already has an active record (by cognito_id)
    result = users_table.get_item(Key={"cognito_id": cognito_id})
    existing_user = result.get("Item")

    if existing_user:
        return _response(200, {
            "message": "User already registered",
            "tenant_id": existing_user.get("tenant_id"),
            "role": existing_user.get("role"),
            "email": existing_user.get("email"),
        })

    # 2. Check if there's a pending invitation for this email
    if email:
        invite_result = users_table.query(
            IndexName="email-index",
            KeyConditionExpression="email = :email",
            ExpressionAttributeValues={":email": email},
        )

        for invite in invite_result.get("Items", []):
            if invite.get("status") == "PENDING":
                # Found a pending invitation — claim it!
                old_id = invite["cognito_id"]
                tenant_id = invite["tenant_id"]
                role = invite.get("role", "READ_ONLY")
                now = datetime.now(timezone.utc).isoformat()

                # Delete the placeholder record
                users_table.delete_item(Key={"cognito_id": old_id})

                # Create the real record with this user's cognito_id
                users_table.put_item(Item={
                    "cognito_id": cognito_id,
                    "email": email,
                    "tenant_id": tenant_id,
                    "role": role,
                    "status": "ACTIVE",
                    "created_at": now,
                    "invited_at": invite.get("created_at", ""),
                })

                logger.info(
                    "User %s claimed invitation to tenant %s as %s",
                    cognito_id, tenant_id, role,
                )

                return _response(200, {
                    "message": "Joined tenant via invitation",
                    "tenant_id": tenant_id,
                    "role": role,
                    "email": email,
                })

    # 3. No invitation found — create a brand-new tenant
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        body = {}

    tenant_name = body.get("tenant_name", f"{email}'s team")
    tenant_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    users_table.put_item(
        Item={
            "cognito_id": cognito_id,
            "email": email,
            "tenant_id": tenant_id,
            "tenant_name": tenant_name,
            "role": "ADMIN",
            "status": "ACTIVE",
            "created_at": now,
        },
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
