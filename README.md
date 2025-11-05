## Goodin Killswitch (Budget Reached -> Disable Billing)

This project deploys a Cloud Run service that is triggered by a Pub/Sub push subscription from your budget alert topic. When it receives a message, it disables billing for the target project, preventing further spend.

### Prerequisites
- gcloud CLI authenticated to the correct org/account
- Terraform >= 1.5
- Permissions:
  - On the target project: ability to enable services and create resources
  - On the billing account: ability to grant `roles/billing.user` (or stronger) to the runtime service account

### Configure
Update these values when running Terraform:
- `project_id`: GCP project ID to protect
- `region`: Cloud Run region (default `europe-north1`)
- `topic_name`: Existing Pub/Sub topic that receives budget alerts (e.g. `goodin-50e-killswitch`)
- `billing_account_id`: Your billing account ID (format `012345-6789AB-CDEF01`)

### Build and push the container
1) Create an Artifact Registry repo (Terraform will create it). If running first-time, apply Terraform once to create the repo, then cancel after repo creation.

2) Build and push image (replace vars):
```bash
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

REGION=europe-north1
PROJECT_ID=goodin-analytics
REPO=goodin-killswitch
IMAGE=${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/service:latest

cd app
docker build -t ${IMAGE} .
docker push ${IMAGE}
```

### Deploy with Terraform
From the repo root:
```bash
cd infra
terraform init
terraform apply
```

Terraform will:
- Create a runtime service account
- Grant it permissions to disable billing
- Deploy the Cloud Run service
- Create a Pub/Sub push subscription pointed at the service URL (in `topic_project_id`)

### Budget Alert Topic
Ensure your budgets are configured to publish to the topic referenced by `topic_name` (e.g. `projects/goodinanalytics/topics/goodin-50e-killswitch`).

### Security Notes
- The push subscription uses OIDC with the service account and requires `roles/run.invoker` only.
- The runtime service account needs `roles/billing.projectManager` on the target project and read on the billing account. Your org may require `roles/billing.admin` on the billing account to detach; adjust as needed.

### Remote state (optional but recommended)
Copy `infra/backend.tf.example` to `infra/backend.tf` and set your GCS bucket for Terraform state. Re-run `terraform init` to migrate state.

### Cross-project permissions
If the topic lives in another project (e.g., `goodinanalytics`), your deploy credentials need `roles/pubsub.admin` or at least `roles/pubsub.subscriber` on that project to create the subscription. The push to Cloud Run uses OIDC with the runtime service account, which already has `roles/run.invoker` in this config.


