"""
Lambda: Manage Users
ADMIN-only endpoints to add, remove, and list users in a tenant.
Routes based on HTTP method:
  POST   /tenants/users            → invite user (creates pending invitation)
  DELETE /tenants/users/{cognito_id} → remove user
  GET    /tenants/users            → list users
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
    """Invite a user to the tenant by email.
    
    Creates a pending invitation record. The user does NOT need to have
    signed up in Cognito yet. When they sign up and call /tenants/register,
    the register_tenant Lambda will find this invitation and assign them
    to this tenant instead of creating a new one.
    """
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

    # Check if this email already has a record (pending or active)
    existing_records = users_table.query(
        IndexName="email-index",
        KeyConditionExpression="email = :email",
        ExpressionAttributeValues={":email": email},
    ).get("Items", [])

    for record in existing_records:
        if record.get("tenant_id") == tenant_id:
            return _response(409, {"error": "User is already a member of (or invited to) this tenant"})
        else:
            return _response(409, {"error": "User already belongs to another tenant"})

    # Create a pending invitation with a placeholder cognito_id
    placeholder_id = f"invite_{uuid.uuid4()}"
    now = datetime.now(timezone.utc).isoformat()

    users_table.put_item(Item={
        "cognito_id": placeholder_id,
        "email": email,
        "tenant_id": tenant_id,
        "role": role,
        "status": "PENDING",
        "created_at": now,
        "invited_by": event.get("requestContext", {}).get("authorizer", {}).get("cognito_id", ""),
    })

    logger.info("Created invitation for %s to tenant %s as %s", email, tenant_id, role)

    return _response(201, {
        "message": f"Invitation sent to {email} as {role}",
        "email": email,
        "role": role,
        "tenant_id": tenant_id,
        "status": "PENDING",
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
    """List all users in the tenant (including pending invitations)."""
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
            "status": item.get("status", "ACTIVE"),
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
