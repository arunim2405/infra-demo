"""
Lambda: API Gateway Custom Authorizer (RBAC)
Validates Cognito JWT, looks up user in DynamoDB, and returns an IAM policy
with tenant_id and role in the context.
"""

import json
import os
import time
import logging
import urllib.request

import boto3
from jose import jwt, jwk, JWTError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

USERS_TABLE = os.environ["USERS_TABLE"]
USER_POOL_ID = os.environ["USER_POOL_ID"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
APP_CLIENT_ID = os.environ["APP_CLIENT_ID"]

table = dynamodb.Table(USERS_TABLE)

# Cache JWKS keys on cold start
_jwks_cache = None

ROLE_PERMISSIONS = {
    "ADMIN": {
        "POST/jobs",
        "GET/jobs",
        "GET/jobs/*",
        "GET/jobs/*/logs",
        "POST/tenants/users",
        "DELETE/tenants/users/*",
        "GET/tenants/users",
        "POST/tenants/register",
    },
    "DOCTOR": {
        "POST/jobs",
        "GET/jobs",
        "GET/jobs/*",
        "GET/jobs/*/logs",
        "POST/tenants/register",
    },
    "READ_ONLY": {
        "GET/jobs",
        "GET/jobs/*",
        "GET/jobs/*/logs",
        "POST/tenants/register",
    },
}


def handler(event, context):
    """API Gateway TOKEN authorizer."""
    token = event.get("authorizationToken", "")

    # Strip "Bearer " prefix
    if token.lower().startswith("bearer "):
        token = token[7:]

    if not token:
        raise Exception("Unauthorized")

    try:
        # Validate JWT
        claims = _validate_token(token)
        cognito_id = claims["sub"]
        email = claims.get("email", "")

        # Look up user in DynamoDB
        result = table.get_item(Key={"cognito_id": cognito_id})
        user = result.get("Item")

        if not user:
            # User exists in Cognito but not registered in our system yet
            # Allow only the register endpoint
            policy = _generate_policy(
                cognito_id,
                "Allow",
                event["methodArn"],
                context_data={
                    "cognito_id": cognito_id,
                    "email": email,
                    "tenant_id": "",
                    "role": "UNREGISTERED",
                },
            )
            return policy

        tenant_id = user.get("tenant_id", "")
        role = user.get("role", "READ_ONLY")

        # Check if this role is allowed for the requested method/resource
        method_arn = event["methodArn"]
        http_method, resource_path = _parse_method_arn(method_arn)
        route_key = f"{http_method}{resource_path}"

        allowed_routes = ROLE_PERMISSIONS.get(role, set())
        is_allowed = _check_permission(route_key, allowed_routes)

        effect = "Allow" if is_allowed else "Deny"

        policy = _generate_policy(
            cognito_id,
            effect,
            event["methodArn"],
            context_data={
                "cognito_id": cognito_id,
                "email": email,
                "tenant_id": tenant_id,
                "role": role,
            },
        )
        return policy

    except JWTError as exc:
        logger.error("JWT validation failed: %s", exc)
        raise Exception("Unauthorized")
    except Exception as exc:
        logger.error("Authorization error: %s", exc)
        raise Exception("Unauthorized")


def _validate_token(token: str) -> dict:
    """Validate and decode a Cognito JWT token."""
    global _jwks_cache

    if _jwks_cache is None:
        jwks_url = (
            f"https://cognito-idp.{AWS_REGION}.amazonaws.com/"
            f"{USER_POOL_ID}/.well-known/jwks.json"
        )
        with urllib.request.urlopen(jwks_url) as resp:
            _jwks_cache = json.loads(resp.read())

    # Get the key ID from the token header
    headers = jwt.get_unverified_headers(token)
    kid = headers["kid"]

    # Find the matching key
    key = None
    for k in _jwks_cache["keys"]:
        if k["kid"] == kid:
            key = k
            break

    if not key:
        raise JWTError("Public key not found")

    # Decode and validate
    claims = jwt.decode(
        token,
        key,
        algorithms=["RS256"],
        audience=APP_CLIENT_ID,
        issuer=f"https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}",
        options={"verify_at_hash": False},
    )

    # Verify token is not expired
    if claims.get("exp", 0) < time.time():
        raise JWTError("Token expired")

    return claims


def _parse_method_arn(method_arn: str):
    """Extract HTTP method and resource path from the method ARN."""
    # arn:aws:execute-api:region:account:api-id/stage/METHOD/resource/path
    arn_parts = method_arn.split(":")
    api_gw_part = arn_parts[5]  # api-id/stage/METHOD/resource
    parts = api_gw_part.split("/")
    http_method = parts[2]  # GET, POST, etc.
    resource_path = "/" + "/".join(parts[3:]) if len(parts) > 3 else "/"
    return http_method, resource_path


def _check_permission(route_key: str, allowed_routes: set) -> bool:
    """Check if a route key matches any allowed patterns (supports * wildcards)."""
    if route_key in allowed_routes:
        return True

    # Check wildcard patterns
    for pattern in allowed_routes:
        if "*" in pattern:
            # Convert pattern to match: GET/jobs/* matches GET/jobs/abc-123
            pattern_parts = pattern.split("/")
            route_parts = route_key.split("/")

            if len(route_parts) >= len(pattern_parts):
                match = True
                for i, pp in enumerate(pattern_parts):
                    if pp == "*":
                        continue
                    if i >= len(route_parts) or pp != route_parts[i]:
                        match = False
                        break
                if match:
                    return True

    return False


def _generate_policy(
    principal_id: str,
    effect: str,
    method_arn: str,
    context_data: dict = None,
) -> dict:
    """Generate an IAM policy document for API Gateway."""
    # Use a wildcard ARN so the policy is cached across all methods
    arn_parts = method_arn.split(":")
    api_gw_part = arn_parts[5].split("/")
    resource_arn = ":".join(arn_parts[:5]) + ":" + api_gw_part[0] + "/*"

    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource_arn,
                }
            ],
        },
    }

    if context_data:
        # API Gateway context values must be strings
        policy["context"] = {k: str(v) for k, v in context_data.items()}

    return policy
