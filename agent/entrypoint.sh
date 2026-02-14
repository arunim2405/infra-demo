#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Entrypoint for the Computer Use Agent container
# - Sends an initial heartbeat to S3 so health checks know the task started
# - Runs the agent with a 25-minute timeout (buffer under ECS 30-min stop)
# - On timeout / failure, marks the task as FAILED/HUNG in DynamoDB
# ============================================================================

TIMEOUT_SECONDS=${AGENT_TIMEOUT_SECONDS:-1500}  # 25 minutes

echo "[entrypoint] Task ID: ${TASK_ID}"
echo "[entrypoint] Search Query: ${SEARCH_QUERY:-hello world}"
echo "[entrypoint] Timeout: ${TIMEOUT_SECONDS}s"

# Run the agent with a timeout
if timeout "${TIMEOUT_SECONDS}" python /app/agent.py; then
    echo "[entrypoint] Agent completed successfully."
    exit 0
else
    EXIT_CODE=$?
    if [ "${EXIT_CODE}" -eq 124 ]; then
        echo "[entrypoint] ERROR: Agent exceeded timeout of ${TIMEOUT_SECONDS}s — marking as HUNG."
        # Best-effort status update
        python -c "
import boto3, os
from datetime import datetime, timezone
table = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION','us-east-1')).Table(os.environ['DYNAMODB_TABLE'])
table.update_item(
    Key={'task_id': os.environ['TASK_ID']},
    UpdateExpression='SET #s = :s, updated_at = :u, error = :e',
    ExpressionAttributeValues={':s': 'HUNG', ':u': datetime.now(timezone.utc).isoformat(), ':e': 'Agent timed out after ${TIMEOUT_SECONDS}s'},
    ExpressionAttributeNames={'#s': 'status'}
)
" 2>/dev/null || true
        exit 1
    else
        echo "[entrypoint] Agent exited with code ${EXIT_CODE}."
        exit "${EXIT_CODE}"
    fi
fi
