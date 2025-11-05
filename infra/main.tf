terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "+"
  type        = string
}

variable "region" {
  description = "Region for Cloud Run"
  type        = string
  default     = "us-central1"
}

variable "topic_name" {
  description = "Existing Pub/Sub topic name that receives budget alerts"
  type        = string
  default     = "goodin-50e-killswitch"
}

variable "billing_account_id" {
  description = "Billing account ID used by the project (e.g. 012345-6789AB-CDEF01). Needed to grant access for disabling billing."
  type        = string
}

locals {
  service_name = "goodin-killswitch"
}

# Enable required APIs
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# Service account to run the killswitch service
resource "google_service_account" "killswitch" {
  account_id   = "killswitch-runner"
  display_name = "Killswitch Cloud Run runtime"
}

# Allow the service account to update billing info for this project
resource "google_project_iam_member" "billing_project_manager" {
  project = var.project_id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${google_service_account.killswitch.email}"
}

# Optional: allow reading billing account (some orgs require this)
resource "google_billing_account_iam_member" "billing_user" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.user"
  member             = "serviceAccount:${google_service_account.killswitch.email}"
}

# Artifact Registry repo for container image
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "goodin-killswitch"
  description   = "Container images for killswitch"
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

# Cloud Run service (container image to be supplied after first build)
resource "google_cloud_run_v2_service" "service" {
  name     = local.service_name
  location = var.region

  template {
    service_account = google_service_account.killswitch.email

    containers {
      image = var.container_image
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
    }
  }

  depends_on = [google_project_service.services]
}

variable "container_image" {
  description = "Full container image URL for the Cloud Run service"
  type        = string
  default     = ""
}

# Allow Pub/Sub to invoke the service (push subscription uses OIDC)
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  name     = google_cloud_run_v2_service.service.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.killswitch.email}"
}

# Create a push subscription to the existing topic, targeting Cloud Run URL
data "google_pubsub_topic" "budget_topic" {
  name = var.topic_name
}

resource "google_pubsub_subscription" "push_sub" {
  name  = "${local.service_name}-sub"
  topic = data.google_pubsub_topic.budget_topic.name

  push_config {
    push_endpoint = google_cloud_run_v2_service.service.uri
    oidc_token {
      service_account_email = google_service_account.killswitch.email
      audience              = google_cloud_run_v2_service.service.uri
    }
  }

  depends_on = [google_cloud_run_v2_service.service]
}

output "cloud_run_url" {
  value = google_cloud_run_v2_service.service.uri
}


