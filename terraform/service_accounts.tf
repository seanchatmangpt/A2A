# Service Account for A2A Application
resource "google_service_account" "a2a_app" {
  account_id   = "${var.deployment_name}-a2a-app"
  display_name = "A2A Application Service Account"
  description  = "Service account for A2A marketplace application workloads"
  project      = var.project_id
}

# Service Account for A2A API
resource "google_service_account" "a2a_api" {
  account_id   = "${var.deployment_name}-a2a-api"
  display_name = "A2A API Service Account"
  description  = "Service account for A2A API service"
  project      = var.project_id
}

# Service Account for A2A Workers
resource "google_service_account" "a2a_worker" {
  account_id   = "${var.deployment_name}-a2a-worker"
  display_name = "A2A Worker Service Account"
  description  = "Service account for A2A background workers"
  project      = var.project_id
}

# IAM Role Bindings for A2A Application Service Account
resource "google_project_iam_member" "a2a_app_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.a2a_app.email}"
}

resource "google_project_iam_member" "a2a_app_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.a2a_app.email}"
}

resource "google_project_iam_member" "a2a_app_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.a2a_app.email}"
}

resource "google_project_iam_member" "a2a_app_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.a2a_app.email}"
}

# IAM Role Bindings for A2A API Service Account
resource "google_project_iam_member" "a2a_api_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.a2a_api.email}"
}

resource "google_project_iam_member" "a2a_api_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.a2a_api.email}"
}

resource "google_project_iam_member" "a2a_api_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.a2a_api.email}"
}

resource "google_project_iam_member" "a2a_api_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.a2a_api.email}"
}

resource "google_project_iam_member" "a2a_api_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.a2a_api.email}"
}

# IAM Role Bindings for A2A Worker Service Account
resource "google_project_iam_member" "a2a_worker_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.a2a_worker.email}"
}

resource "google_project_iam_member" "a2a_worker_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.a2a_worker.email}"
}

resource "google_project_iam_member" "a2a_worker_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.a2a_worker.email}"
}

resource "google_project_iam_member" "a2a_worker_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.a2a_worker.email}"
}

resource "google_project_iam_member" "a2a_worker_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.a2a_worker.email}"
}

# Workload Identity Binding for A2A Application
resource "google_service_account_iam_member" "a2a_app_workload_identity" {
  service_account_id = google_service_account.a2a_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-app]"
}

# Workload Identity Binding for A2A API
resource "google_service_account_iam_member" "a2a_api_workload_identity" {
  service_account_id = google_service_account.a2a_api.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-api]"
}

# Workload Identity Binding for A2A Worker
resource "google_service_account_iam_member" "a2a_worker_workload_identity" {
  service_account_id = google_service_account.a2a_worker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-worker]"
}

# Service Account for GCP Marketplace Deployer
resource "google_service_account" "marketplace_deployer" {
  account_id   = "${var.deployment_name}-deployer"
  display_name = "GCP Marketplace Deployer"
  description  = "Service account for deploying marketplace application"
  project      = var.project_id
}

# IAM Role Bindings for Marketplace Deployer
resource "google_project_iam_member" "deployer_gke_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.marketplace_deployer.email}"
}

resource "google_project_iam_member" "deployer_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.marketplace_deployer.email}"
}

# Workload Identity Binding for Marketplace Deployer
resource "google_service_account_iam_member" "deployer_workload_identity" {
  service_account_id = google_service_account.marketplace_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/marketplace-deployer]"
}

# Variables
variable "deployment_name" {
  description = "The name of the deployment"
  type        = string
  default     = "a2a"
}

variable "k8s_namespace" {
  description = "The Kubernetes namespace for the application"
  type        = string
  default     = "default"
}

# Outputs
output "a2a_app_service_account_email" {
  description = "Email of the A2A application service account"
  value       = google_service_account.a2a_app.email
}

output "a2a_api_service_account_email" {
  description = "Email of the A2A API service account"
  value       = google_service_account.a2a_api.email
}

output "a2a_worker_service_account_email" {
  description = "Email of the A2A worker service account"
  value       = google_service_account.a2a_worker.email
}

output "marketplace_deployer_service_account_email" {
  description = "Email of the marketplace deployer service account"
  value       = google_service_account.marketplace_deployer.email
}

output "workload_identity_bindings" {
  description = "Workload Identity bindings configured"
  value = {
    a2a_app    = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-app]"
    a2a_api    = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-api]"
    a2a_worker = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/a2a-worker]"
    deployer   = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/marketplace-deployer]"
  }
}
