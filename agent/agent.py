"""
Computer Use Agent — Placeholder Script
Opens a browser, searches a query on Google, and saves a screenshot.
Uploads all outputs to S3 and updates DynamoDB task status.
"""

import os
import sys
import json
import time
import logging
import traceback
from datetime import datetime, timezone

import boto3
from playwright.sync_api import sync_playwright

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
TASK_ID = os.environ["TASK_ID"]
SEARCH_QUERY = os.environ.get("SEARCH_QUERY", "hello world")
S3_BUCKET = os.environ["S3_BUCKET"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
PROXY_URL = os.environ.get("PROXY_URL", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("agent")

# ---------------------------------------------------------------------------
# AWS Clients
# ---------------------------------------------------------------------------
s3 = boto3.client("s3", region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)


def update_task_status(status: str, extra: dict | None = None):
    """Update the task status in DynamoDB."""
    update_expr = "SET #s = :s, updated_at = :u"
    expr_values = {
        ":s": status,
        ":u": datetime.now(timezone.utc).isoformat(),
    }
    expr_names = {"#s": "status"}

    if extra:
        for key, value in extra.items():
            update_expr += f", {key} = :{key}"
            expr_values[f":{key}"] = value

    table.update_item(
        Key={"task_id": TASK_ID},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
        ExpressionAttributeNames=expr_names,
    )
    logger.info("Task %s status updated to %s", TASK_ID, status)


def upload_to_s3(local_path: str, s3_key: str, content_type: str = "application/octet-stream"):
    """Upload a file to S3."""
    s3.upload_file(
        local_path,
        S3_BUCKET,
        s3_key,
        ExtraArgs={"ContentType": content_type},
    )
    logger.info("Uploaded %s → s3://%s/%s", local_path, S3_BUCKET, s3_key)


def upload_bytes_to_s3(data: bytes, s3_key: str, content_type: str = "application/octet-stream"):
    """Upload bytes directly to S3."""
    s3.put_object(Bucket=S3_BUCKET, Key=s3_key, Body=data, ContentType=content_type)
    logger.info("Uploaded bytes → s3://%s/%s", S3_BUCKET, s3_key)


def send_heartbeat():
    """Write a heartbeat marker to S3 so the health check knows we started."""
    heartbeat = {
        "task_id": TASK_ID,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "status": "alive",
    }
    upload_bytes_to_s3(
        json.dumps(heartbeat).encode(),
        f"tasks/{TASK_ID}/heartbeat.json",
        "application/json",
    )


def run_agent():
    """Main agent logic: open browser → search → screenshot."""
    logger.info("Starting agent for task %s with query: %s", TASK_ID, SEARCH_QUERY)

    # Mark as RUNNING
    update_task_status("RUNNING")

    # Send heartbeat
    send_heartbeat()

    screenshot_path = "/tmp/screenshot.png"
    execution_log_lines = []

    with sync_playwright() as p:
        # Browser launch options
        launch_opts = {
            "headless": True,
            "args": ["--no-sandbox", "--disable-dev-shm-usage"],
        }
        if PROXY_URL:
            launch_opts["proxy"] = {"server": PROXY_URL}
            logger.info("Using proxy: %s", PROXY_URL)

        execution_log_lines.append(f"[{datetime.now(timezone.utc).isoformat()}] Launching browser")
        browser = p.chromium.launch(**launch_opts)

        context = browser.new_context(
            viewport={"width": 1920, "height": 1080},
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
        )
        page = context.new_page()

        # Step 1: Navigate to Google
        execution_log_lines.append(f"[{datetime.now(timezone.utc).isoformat()}] Navigating to Google")
        logger.info("Navigating to Google…")
        page.goto("https://www.google.com", wait_until="domcontentloaded", timeout=30000)
        time.sleep(1)

        # Step 2: Search
        execution_log_lines.append(
            f"[{datetime.now(timezone.utc).isoformat()}] Searching for: {SEARCH_QUERY}"
        )
        logger.info("Searching for: %s", SEARCH_QUERY)

        # Handle consent dialogs (common in some regions)
        try:
            consent_btn = page.locator("button:has-text('Accept all'), button:has-text('I agree')")
            if consent_btn.count() > 0:
                consent_btn.first.click()
                time.sleep(1)
        except Exception:
            pass  # No consent dialog

        search_box = page.locator('textarea[name="q"], input[name="q"]')
        search_box.first.fill(SEARCH_QUERY)
        search_box.first.press("Enter")
        page.wait_for_load_state("domcontentloaded", timeout=15000)
        time.sleep(2)

        # Step 3: Screenshot
        execution_log_lines.append(
            f"[{datetime.now(timezone.utc).isoformat()}] Taking screenshot of search results"
        )
        logger.info("Taking screenshot…")
        page.screenshot(path=screenshot_path, full_page=True)

        execution_log_lines.append(f"[{datetime.now(timezone.utc).isoformat()}] Done — closing browser")
        browser.close()

    # Upload outputs to S3
    logger.info("Uploading outputs to S3…")
    upload_to_s3(screenshot_path, f"tasks/{TASK_ID}/screenshot.png", "image/png")

    execution_log = "\n".join(execution_log_lines)
    upload_bytes_to_s3(
        execution_log.encode(),
        f"tasks/{TASK_ID}/execution.log",
        "text/plain",
    )

    # Mark COMPLETED
    update_task_status("COMPLETED", {"completed_at": datetime.now(timezone.utc).isoformat()})
    logger.info("Agent completed successfully for task %s", TASK_ID)


def main():
    try:
        run_agent()
    except Exception as exc:
        logger.error("Agent failed: %s", exc)
        logger.error(traceback.format_exc())

        # Capture error details and upload
        error_info = {
            "task_id": TASK_ID,
            "error": str(exc),
            "traceback": traceback.format_exc(),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        try:
            upload_bytes_to_s3(
                json.dumps(error_info, indent=2).encode(),
                f"tasks/{TASK_ID}/error.json",
                "application/json",
            )
        except Exception as upload_err:
            logger.error("Failed to upload error info: %s", upload_err)

        update_task_status("FAILED", {"error": str(exc)})
        sys.exit(1)


if __name__ == "__main__":
    main()
