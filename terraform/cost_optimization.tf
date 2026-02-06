# Cost Optimization Resources for GCP

# Preemptible Node Pool for cost savings
resource "google_container_node_pool" "preemptible_nodes" {
  name       = "${var.deployment_name}-preemptible-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 0
    max_node_count = 10
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = true
    spot         = true
    machine_type = var.preemptible_machine_type != "" ? var.preemptible_machine_type : "e2-standard-4"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool_type  = "preemptible"
      workload   = "non-critical"
    }

    # Taints to ensure only appropriate workloads run on preemptible nodes
    taint {
      key    = "preemptible"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-preemptible"]
  }
}

# Spot Node Pool (next generation preemptible) for maximum cost savings
resource "google_container_node_pool" "spot_nodes" {
  name       = "${var.deployment_name}-spot-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 0
    max_node_count = 15
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    spot         = true
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool_type  = "spot"
      workload   = "batch"
    }

    taint {
      key    = "spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-spot"]
  }
}

# Committed Use Discount for Compute Resources
resource "google_compute_commitment" "compute_cud" {
  name        = "${var.deployment_name}-compute-cud"
  description = "1-year committed use discount for cost optimization"

  plan = "TWELVE_MONTH"
  type = "COMPUTE_OPTIMIZED"

  resources {
    type   = "VCPU"
    amount = var.cud_vcpu_amount != "" ? var.cud_vcpu_amount : "4"
  }

  resources {
    type   = "MEMORY"
    amount = var.cud_memory_amount != "" ? var.cud_memory_amount : "16384"
  }

  auto_renew = var.cud_auto_renew != "" ? var.cud_auto_renew : false
}

# Resource Quotas via Namespace (example for cost control)
# Note: This is a placeholder. Actual quotas should be applied via kubectl or K8s manifests
resource "null_resource" "resource_quotas" {
  depends_on = [google_container_cluster.primary]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Resource quotas should be applied via Kubernetes manifests"
      echo "Example quota YAML should be created separately"
    EOT
  }
}

# Budget Alert for GCP Project
resource "google_billing_budget" "project_budget" {
  billing_account = var.billing_account_id
  display_name    = "${var.deployment_name}-monthly-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]

    # Filter by labels if needed
    labels = {
      deployment = var.deployment_name
    }

    # Include all services
    services = []
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency != "" ? var.budget_currency : "USD"
      units         = var.monthly_budget_amount != "" ? var.monthly_budget_amount : "1000"
    }
  }

  # Alert at 50%, 75%, 90%, and 100% of budget
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.75
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  # Forecasted spend alert
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # All updates enabled
  all_updates_rule {
    monitoring_notification_channels = var.budget_notification_channels != null ? var.budget_notification_channels : []
    disable_default_iam_recipients   = false

    # Pub/Sub topic for programmatic budget notifications
    pubsub_topic = var.budget_pubsub_topic != "" ? var.budget_pubsub_topic : null
  }
}

# Notification Channel for Budget Alerts (Email)
resource "google_monitoring_notification_channel" "budget_email" {
  display_name = "${var.deployment_name}-budget-email"
  type         = "email"

  labels = {
    email_address = var.budget_alert_email != "" ? var.budget_alert_email : "admin@example.com"
  }

  enabled = true
}

# Additional Budget for GKE-specific costs
resource "google_billing_budget" "gke_budget" {
  billing_account = var.billing_account_id
  display_name    = "${var.deployment_name}-gke-monthly-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]

    # Filter specifically for Kubernetes Engine
    services = ["services/95FF-2EF5-5EA1"]  # GKE service ID

    labels = {
      deployment = var.deployment_name
    }
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency != "" ? var.budget_currency : "USD"
      units         = var.gke_monthly_budget_amount != "" ? var.gke_monthly_budget_amount : "500"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.95
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
    disable_default_iam_recipients   = false
  }
}

# Cloud Storage Budget (for persistent volumes, backups, etc.)
resource "google_billing_budget" "storage_budget" {
  billing_account = var.billing_account_id
  display_name    = "${var.deployment_name}-storage-monthly-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]

    # Filter for Cloud Storage and Persistent Disk
    services = [
      "services/95FF-2EF5-5EA1",  # Cloud Storage
      "services/9662-B51E-5089"   # Compute Engine (includes persistent disks)
    ]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency != "" ? var.budget_currency : "USD"
      units         = var.storage_monthly_budget_amount != "" ? var.storage_monthly_budget_amount : "200"
    }
  }

  threshold_rules {
    threshold_percent = 0.75
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
    disable_default_iam_recipients   = false
  }
}

# Pub/Sub Topic for Budget Alerts
resource "google_pubsub_topic" "budget_alerts" {
  name = "${var.deployment_name}-budget-alerts"

  labels = {
    deployment = var.deployment_name
    purpose    = "cost-monitoring"
  }

  message_retention_duration = "86400s"  # 1 day
}

# Pub/Sub Subscription for Budget Alerts
resource "google_pubsub_subscription" "budget_alerts_sub" {
  name  = "${var.deployment_name}-budget-alerts-sub"
  topic = google_pubsub_topic.budget_alerts.name

  ack_deadline_seconds = 20

  expiration_policy {
    ttl = ""  # Never expire
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# Variables for Cost Optimization
variable "preemptible_machine_type" {
  description = "Machine type for preemptible nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "cud_vcpu_amount" {
  description = "Number of vCPUs for committed use discount"
  type        = string
  default     = "4"
}

variable "cud_memory_amount" {
  description = "Amount of memory in MB for committed use discount"
  type        = string
  default     = "16384"
}

variable "cud_auto_renew" {
  description = "Auto-renew committed use discount"
  type        = bool
  default     = false
}

variable "billing_account_id" {
  description = "Billing account ID for budget alerts"
  type        = string
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD"
  type        = string
  default     = "1000"
}

variable "gke_monthly_budget_amount" {
  description = "Monthly budget amount for GKE in USD"
  type        = string
  default     = "500"
}

variable "storage_monthly_budget_amount" {
  description = "Monthly budget amount for storage in USD"
  type        = string
  default     = "200"
}

variable "budget_currency" {
  description = "Currency for budget amounts"
  type        = string
  default     = "USD"
}

variable "budget_alert_email" {
  description = "Email address for budget alerts"
  type        = string
  default     = "admin@example.com"
}

variable "budget_notification_channels" {
  description = "List of notification channel IDs for budget alerts"
  type        = list(string)
  default     = []
}

variable "budget_pubsub_topic" {
  description = "Pub/Sub topic for budget notifications"
  type        = string
  default     = ""
}

# Outputs
output "preemptible_node_pool_name" {
  description = "Name of the preemptible node pool"
  value       = google_container_node_pool.preemptible_nodes.name
}

output "spot_node_pool_name" {
  description = "Name of the spot node pool"
  value       = google_container_node_pool.spot_nodes.name
}

output "compute_cud_id" {
  description = "Committed use discount ID"
  value       = google_compute_commitment.compute_cud.id
}

output "project_budget_name" {
  description = "Name of the project budget"
  value       = google_billing_budget.project_budget.display_name
}

output "gke_budget_name" {
  description = "Name of the GKE budget"
  value       = google_billing_budget.gke_budget.display_name
}

output "storage_budget_name" {
  description = "Name of the storage budget"
  value       = google_billing_budget.storage_budget.display_name
}

output "budget_alerts_topic" {
  description = "Pub/Sub topic for budget alerts"
  value       = google_pubsub_topic.budget_alerts.name
}

output "budget_notification_channel" {
  description = "Budget notification channel ID"
  value       = google_monitoring_notification_channel.budget_email.id
}
