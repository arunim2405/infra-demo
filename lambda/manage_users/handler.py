"""
Lambda: Manage Users
ADMIN-only endpoints to add, remove, and list users in a tenant.
Routes based on HTTP method:
  POST   /tenants/users            → add user
  DELETE /tenants/users/{cognito_id} → remove user
  GET    /tenants/users            → list users
"""

import json
import os
import logging
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
cognito = boto3.client("cognito-idp")

USERS_TABLE = os.environ["USERS_TABLE"]
USER_POOL_ID = os.environ["USER_POOL_ID"]

users_table = dynamodb.Table(USERS_TABLE)

VALID_ROLES = {"ADMIN", "DOCTOR", "READ_ONLY"}


def handler(event, context):
    """Route to the appropriate handler based on HTTP method."""
    http_method = event.get("httpMethod", "")
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    caller_role = auth_context.get("role", "")
    caller_tenant_id = auth_context.get("tenant_id", "")

    if caller_role != "ADMIN":
        return _response(403, {"error": "Only ADMIN users can manage team members"})

    if not caller_tenant_id:
        return _response(403, {"error": "No tenant associated with this user"})

    if http_method == "POST":
        return _add_user(event, caller_tenant_id)
    elif http_method == "DELETE":
        return _remove_user(event, caller_tenant_id)
    elif http_method == "GET":
        return _list_users(caller_tenant_id)
    else:
        return _response(405, {"error": f"Method {http_method} not allowed"})


def _add_user(event, tenant_id):
    """Add a user to the tenant."""
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    email = body.get("email")
    role = body.get("role", "READ_ONLY")

    if not email:
        return _response(400, {"error": "'email' is required"})

    if role not in VALID_ROLES:
        return _response(400, {"error": f"Invalid role. Must be one of: {', '.join(VALID_ROLES)}"})

    # Look up user in Cognito by email
    try:
        response = cognito.list_users(
            UserPoolId=USER_POOL_ID,
            Filter=f'email = "{email}"',
            Limit=1,
        )
        users = response.get("Users", [])
    except ClientError as exc:
        logger.error("Cognito lookup failed: %s", exc)
        return _response(500, {"error": "Failed to look up user in Cognito"})

    if not users:
        return _response(404, {"error": f"No Cognito user found with email '{email}'. They must sign up first."})

    cognito_user = users[0]
    target_cognito_id = cognito_user["Username"]

    # Check if user already belongs to a tenant
    existing = users_table.get_item(Key={"cognito_id": target_cognito_id}).get("Item")
    if existing:
        if existing.get("tenant_id") == tenant_id:
            return _response(409, {"error": "User is already a member of this tenant"})
        else:
            return _response(409, {"error": "User already belongs to another tenant"})

    # Add user to tenant
    now = datetime.now(timezone.utc).isoformat()
    users_table.put_item(Item={
        "cognito_id": target_cognito_id,
        "email": email,
        "tenant_id": tenant_id,
        "role": role,
        "created_at": now,
        "added_by": event.get("requestContext", {}).get("authorizer", {}).get("cognito_id", ""),
    })

    logger.info("Added user %s to tenant %s as %s", email, tenant_id, role)

    return _response(201, {
        "message": f"User {email} added as {role}",
        "cognito_id": target_cognito_id,
        "email": email,
        "role": role,
        "tenant_id": tenant_id,
    })


def _remove_user(event, tenant_id):
    """Remove a user from the tenant."""
    path_params = event.get("pathParameters") or {}
    target_cognito_id = path_params.get("cognito_id")

    if not target_cognito_id:
        return _response(400, {"error": "cognito_id path parameter is required"})

    # Check the target user exists and belongs to this tenant
    result = users_table.get_item(Key={"cognito_id": target_cognito_id})
    target_user = result.get("Item")

    if not target_user:
        return _response(404, {"error": "User not found"})

    if target_user.get("tenant_id") != tenant_id:
        return _response(403, {"error": "User does not belong to your tenant"})

    # Prevent removing yourself
    caller_id = event.get("requestContext", {}).get("authorizer", {}).get("cognito_id", "")
    if target_cognito_id == caller_id:
        return _response(400, {"error": "You cannot remove yourself from the tenant"})

    users_table.delete_item(Key={"cognito_id": target_cognito_id})

    logger.info("Removed user %s from tenant %s", target_cognito_id, tenant_id)

    return _response(200, {
        "message": "User removed successfully",
        "cognito_id": target_cognito_id,
    })


def _list_users(tenant_id):
    """List all users in the tenant."""
    result = users_table.query(
        IndexName="tenant-index",
        KeyConditionExpression="tenant_id = :tid",
        ExpressionAttributeValues={":tid": tenant_id},
    )

    users = []
    for item in result.get("Items", []):
        users.append({
            "cognito_id": item.get("cognito_id"),
            "email": item.get("email"),
            "role": item.get("role"),
            "created_at": item.get("created_at"),
        })

    return _response(200, {
        "tenant_id": tenant_id,
        "users": users,
        "count": len(users),
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
