import base64
import json
import os
from typing import Any, Dict

from flask import Flask, Request, abort, request
from google.api_core.exceptions import GoogleAPIError
from google.cloud import billing_v1


app = Flask(__name__)


def parse_pubsub_message(req: Request) -> Dict[str, Any]:
    if not req.is_json:
        abort(400, "Expected JSON request")
    envelope = req.get_json(silent=True) or {}
    message = envelope.get("message") or {}
    data_b64 = message.get("data")
    if not data_b64:
        return {}
    try:
        decoded = base64.b64decode(data_b64).decode("utf-8")
        payload = json.loads(decoded)
        return payload
    except Exception:
        abort(400, "Invalid Pub/Sub message data")


def disable_billing(project_id: str) -> None:
    client = billing_v1.CloudBillingClient()
    name = f"projects/{project_id}"
    # Setting billing_account_name to empty string disables billing on the project
    project_billing_info = billing_v1.ProjectBillingInfo(name=name, billing_account_name="")
    client.update_project_billing_info(name=name, project_billing_info=project_billing_info)


@app.route("/", methods=["POST"])  # Pub/Sub push endpoint
def handle_pubsub() -> (str, int):
    payload = parse_pubsub_message(request)

    # Budget notifications from Cloud Billing Budgets API include cost/threshold fields
    # We accept any message and proceed to disable billing to act as a killswitch.
    project_id = os.environ.get("PROJECT_ID")
    if not project_id:
        abort(500, "PROJECT_ID env var not set")

    try:
        disable_billing(project_id)
    except GoogleAPIError as api_err:
        # Log and return 500 so Pub/Sub can retry
        return (f"Failed to disable billing: {api_err}", 500)
    except Exception as e:
        return (f"Unexpected error: {e}", 500)

    # Return 204 so Pub/Sub considers message successfully delivered
    return ("", 204)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))


