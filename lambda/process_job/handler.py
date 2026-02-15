"""
Lambda: Process Job
Triggered by SQS — provisions an ECS Fargate task to run the agent.
"""

import json
import os
import logging
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client("ecs")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
ECS_CLUSTER = os.environ["ECS_CLUSTER"]
TASK_DEFINITION = os.environ["TASK_DEFINITION"]
SUBNETS = os.environ["SUBNETS"].split(",")
SECURITY_GROUP = os.environ["SECURITY_GROUP"]
S3_BUCKET = os.environ["S3_BUCKET"]
CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "agent")
PROXY_URL = os.environ.get("PROXY_URL", "")

table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """Process SQS messages — each message triggers one ECS Fargate task."""
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        task_id = body["task_id"]
        query = body.get("query", "hello world")
        tenant_id = body.get("tenant_id", "default")

        logger.info("Processing job: task_id=%s query=%s", task_id, query)

        # Update status to PROVISIONING
        _update_status(task_id, "PROVISIONING")

        try:
            # Run ECS Fargate task
            response = ecs.run_task(
                cluster=ECS_CLUSTER,
                taskDefinition=TASK_DEFINITION,
                launchType="FARGATE",
                count=1,
                networkConfiguration={
                    "awsvpcConfiguration": {
                        "subnets": SUBNETS,
                        "securityGroups": [SECURITY_GROUP],
                        "assignPublicIp": "DISABLED",
                    }
                },
                overrides={
                    "containerOverrides": [
                        {
                            "name": CONTAINER_NAME,
                            "environment": [
                                {"name": "TASK_ID", "value": task_id},
                                {"name": "SEARCH_QUERY", "value": query},
                                {"name": "S3_BUCKET", "value": S3_BUCKET},
                                {"name": "DYNAMODB_TABLE", "value": TABLE_NAME},
                                # {"name": "PROXY_URL", "value": PROXY_URL},
                                {"name": "TENANT_ID", "value": tenant_id},
                            ],
                        }
                    ]
                },
                tags=[
                    {"key": "TaskId", "value": task_id},
                    {"key": "TenantId", "value": tenant_id},
                    {"key": "Project", "value": "infra-demo"},
                ],
            )

            # Check for failures
            failures = response.get("failures", [])
            if failures:
                error_msg = "; ".join(f.get("reason", "Unknown") for f in failures)
                logger.error("ECS RunTask failures: %s", error_msg)
                _update_status(task_id, "FAILED", error=f"ECS provisioning failed: {error_msg}")
                continue

            ecs_task_arn = response["tasks"][0]["taskArn"]
            # Extract short task ID from ARN (last segment after /)
            ecs_task_id = ecs_task_arn.split("/")[-1]
            logger.info("ECS task started: %s (id: %s)", ecs_task_arn, ecs_task_id)
            _update_status(task_id, "PROVISIONED", ecs_task_arn=ecs_task_arn, ecs_task_id=ecs_task_id)

        except Exception as exc:
            logger.error("Failed to run ECS task for %s: %s", task_id, exc)
            _update_status(task_id, "FAILED", error=str(exc))
            raise  # Let SQS retry


def _update_status(task_id: str, status: str, error: str = None, ecs_task_arn: str = None, ecs_task_id: str = None):
    """Update task status in DynamoDB."""
    update_expr = "SET #s = :s, updated_at = :u"
    expr_values = {
        ":s": status,
        ":u": datetime.now(timezone.utc).isoformat(),
    }
    expr_names = {"#s": "status"}

    if error:
        update_expr += ", errorLog = :e"
        expr_values[":e"] = error
    if ecs_task_arn:
        update_expr += ", ecs_task_arn = :arn"
        expr_values[":arn"] = ecs_task_arn
    if ecs_task_id:
        update_expr += ", ecs_task_id = :tid"
        expr_values[":tid"] = ecs_task_id

    table.update_item(
        Key={"task_id": task_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
        ExpressionAttributeNames=expr_names,
    )
