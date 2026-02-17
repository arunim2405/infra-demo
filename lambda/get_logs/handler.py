"""
Lambda: Get Runtime Logs
Fetches CloudWatch runtime logs for an ECS task using the ecs_task_id stored in DynamoDB.
Enforces tenant ownership via authorizer context.
Log stream pattern: {prefix}/{container-name}/{ecs-task-id}
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
logs_client = boto3.client("logs")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
LOG_GROUP = os.environ["LOG_GROUP"]
LOG_STREAM_PREFIX = os.environ.get("LOG_STREAM_PREFIX", "agent")
CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "agent")

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """GET /jobs/{task_id}/logs — return CloudWatch runtime logs for the ECS task."""
    task_id = event.get("pathParameters", {}).get("task_id")

    if not task_id:
        return _response(400, {"error": "task_id is required"})

    # Verify tenant ownership
    auth_context = event.get("requestContext", {}).get("authorizer", {})
    caller_tenant_id = auth_context.get("tenant_id", "")

    # Fetch task metadata from DynamoDB
    result = table.get_item(Key={"task_id": task_id})
    item = result.get("Item")

    if not item:
        return _response(404, {"error": f"Task {task_id} not found"})

    # Enforce tenant isolation
    if item.get("tenant_id") != caller_tenant_id:
        return _response(403, {"error": "You do not have access to this task"})

    ecs_task_id = item.get("ecs_task_id")
    if not ecs_task_id:
        return _response(400, {
            "error": "Task has no ECS task ID yet — it may still be queued or provisioning",
            "status": item.get("status", "UNKNOWN"),
        })

    # Construct the log stream name: {prefix}/{container-name}/{ecs-task-id}
    log_stream_name = f"{LOG_STREAM_PREFIX}/{CONTAINER_NAME}/{ecs_task_id}"

    # Use created_at as the start time for log search
    created_at = item.get("created_at")
    start_time = None
    if created_at:
        try:
            dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            start_time = int(dt.timestamp() * 1000)  # CloudWatch uses milliseconds
        except (ValueError, TypeError):
            pass

    # Query parameters from request
    query_params = event.get("queryStringParameters") or {}
    next_token = query_params.get("next_token")
    limit = min(int(query_params.get("limit", "200")), 500)

    try:
        # Fetch log events
        kwargs = {
            "logGroupName": LOG_GROUP,
            "logStreamName": log_stream_name,
            "limit": limit,
            "startFromHead": True,
        }
        if start_time:
            kwargs["startTime"] = start_time
        if next_token:
            kwargs["nextForwardToken"] = next_token

        response = logs_client.get_log_events(**kwargs)

        events = [
            {
                "timestamp": evt["timestamp"],
                "time": datetime.fromtimestamp(
                    evt["timestamp"] / 1000, tz=timezone.utc
                ).isoformat(),
                "message": evt["message"].rstrip("\n"),
            }
            for evt in response.get("events", [])
        ]

        result = {
            "task_id": task_id,
            "ecs_task_id": ecs_task_id,
            "log_group": LOG_GROUP,
            "log_stream": log_stream_name,
            "status": item.get("status", "UNKNOWN"),
            "events": events,
            "count": len(events),
        }

        # Include pagination token if there are more logs
        forward_token = response.get("nextForwardToken")
        if forward_token and events:
            result["next_token"] = forward_token

        return _response(200, result)

    except logs_client.exceptions.ResourceNotFoundException:
        return _response(404, {
            "error": "Log stream not found — the task may not have started yet",
            "task_id": task_id,
            "ecs_task_id": ecs_task_id,
            "log_stream": log_stream_name,
            "status": item.get("status", "UNKNOWN"),
        })
    except ClientError as exc:
        logger.error("CloudWatch error: %s", exc)
        return _response(500, {"error": f"Failed to fetch logs: {str(exc)}"})


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
