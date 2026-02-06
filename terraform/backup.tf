# ============================================================================
# GCP Backup and Disaster Recovery Configuration
# ============================================================================

# Variables for backup configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "backup_region_primary" {
  description = "Primary region for backups"
  type        = string
  default     = "us-central1"
}

variable "backup_region_secondary" {
  description = "Secondary region for disaster recovery"
  type        = string
  default     = "us-east1"
}

variable "backup_region_tertiary" {
  description = "Tertiary region for disaster recovery"
  type        = string
  default     = "europe-west1"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for backups"
  type        = bool
  default     = true
}

variable "snapshot_schedule_hour" {
  description = "Hour of day to take snapshots (0-23)"
  type        = number
  default     = 2
}

variable "enable_disaster_recovery" {
  description = "Enable disaster recovery features"
  type        = bool
  default     = true
}

# ============================================================================
# Cloud Storage Buckets for Backups
# ============================================================================

# Primary backup bucket with versioning and lifecycle management
resource "google_storage_bucket" "backup_primary" {
  name          = "${var.deployment_name}-backups-${var.backup_region_primary}"
  location      = var.backup_region_primary
  project       = var.project_id
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 7
      num_newer_versions    = 3
      with_state           = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.backup_key.id
  }

  labels = {
    deployment = var.deployment_name
    managed_by = "terraform"
    purpose    = "backup"
    region     = var.backup_region_primary
  }

  depends_on = [
    google_project_service_identity.gcs_account,
    google_kms_crypto_key_iam_binding.gcs_key_binding
  ]
}

# Secondary backup bucket for cross-region replication
resource "google_storage_bucket" "backup_secondary" {
  count         = var.enable_cross_region_replication ? 1 : 0
  name          = "${var.deployment_name}-backups-${var.backup_region_secondary}"
  location      = var.backup_region_secondary
  project       = var.project_id
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.backup_key_secondary[0].id
  }

  labels = {
    deployment = var.deployment_name
    managed_by = "terraform"
    purpose    = "backup-replica"
    region     = var.backup_region_secondary
  }

  depends_on = [
    google_project_service_identity.gcs_account,
    google_kms_crypto_key_iam_binding.gcs_key_binding_secondary
  ]
}

# Tertiary backup bucket for multi-region disaster recovery
resource "google_storage_bucket" "backup_tertiary" {
  count         = var.enable_disaster_recovery ? 1 : 0
  name          = "${var.deployment_name}-backups-${var.backup_region_tertiary}"
  location      = var.backup_region_tertiary
  project       = var.project_id
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.backup_key_tertiary[0].id
  }

  labels = {
    deployment = var.deployment_name
    managed_by = "terraform"
    purpose    = "disaster-recovery"
    region     = var.backup_region_tertiary
  }

  depends_on = [
    google_project_service_identity.gcs_account,
    google_kms_crypto_key_iam_binding.gcs_key_binding_tertiary
  ]
}

# ============================================================================
# KMS Encryption Keys for Backups
# ============================================================================

# KMS Key Ring for backup encryption - Primary
resource "google_kms_key_ring" "backup_keyring" {
  name     = "${var.deployment_name}-backup-keyring"
  location = var.backup_region_primary
  project  = var.project_id
}

# KMS Crypto Key for backup encryption - Primary
resource "google_kms_crypto_key" "backup_key" {
  name            = "${var.deployment_name}-backup-key"
  key_ring        = google_kms_key_ring.backup_keyring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    deployment = var.deployment_name
    purpose    = "backup-encryption"
  }
}

# KMS Key Ring for backup encryption - Secondary
resource "google_kms_key_ring" "backup_keyring_secondary" {
  count    = var.enable_cross_region_replication ? 1 : 0
  name     = "${var.deployment_name}-backup-keyring-secondary"
  location = var.backup_region_secondary
  project  = var.project_id
}

# KMS Crypto Key for backup encryption - Secondary
resource "google_kms_crypto_key" "backup_key_secondary" {
  count           = var.enable_cross_region_replication ? 1 : 0
  name            = "${var.deployment_name}-backup-key-secondary"
  key_ring        = google_kms_key_ring.backup_keyring_secondary[0].id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    deployment = var.deployment_name
    purpose    = "backup-encryption-secondary"
  }
}

# KMS Key Ring for backup encryption - Tertiary
resource "google_kms_key_ring" "backup_keyring_tertiary" {
  count    = var.enable_disaster_recovery ? 1 : 0
  name     = "${var.deployment_name}-backup-keyring-tertiary"
  location = var.backup_region_tertiary
  project  = var.project_id
}

# KMS Crypto Key for backup encryption - Tertiary
resource "google_kms_crypto_key" "backup_key_tertiary" {
  count           = var.enable_disaster_recovery ? 1 : 0
  name            = "${var.deployment_name}-backup-key-tertiary"
  key_ring        = google_kms_key_ring.backup_keyring_tertiary[0].id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    deployment = var.deployment_name
    purpose    = "backup-encryption-tertiary"
  }
}

# Service account for GCS
resource "google_project_service_identity" "gcs_account" {
  provider = google
  project  = var.project_id
  service  = "storage.googleapis.com"
}

# IAM binding for GCS to use KMS key - Primary
resource "google_kms_crypto_key_iam_binding" "gcs_key_binding" {
  crypto_key_id = google_kms_crypto_key.backup_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.gcs_account.email}",
  ]
}

# IAM binding for GCS to use KMS key - Secondary
resource "google_kms_crypto_key_iam_binding" "gcs_key_binding_secondary" {
  count         = var.enable_cross_region_replication ? 1 : 0
  crypto_key_id = google_kms_crypto_key.backup_key_secondary[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.gcs_account.email}",
  ]
}

# IAM binding for GCS to use KMS key - Tertiary
resource "google_kms_crypto_key_iam_binding" "gcs_key_binding_tertiary" {
  count         = var.enable_disaster_recovery ? 1 : 0
  crypto_key_id = google_kms_crypto_key.backup_key_tertiary[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.gcs_account.email}",
  ]
}

# ============================================================================
# Compute Disk Snapshot Schedules
# ============================================================================

# Resource policy for daily snapshots
resource "google_compute_resource_policy" "daily_snapshot" {
  name    = "${var.deployment_name}-daily-snapshot-policy"
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = format("%02d:00", var.snapshot_schedule_hour)
      }
    }

    retention_policy {
      max_retention_days    = var.backup_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = {
        deployment = var.deployment_name
        managed_by = "terraform"
        schedule   = "daily"
      }
      storage_locations = [var.backup_region_primary]
      guest_flush       = true
    }
  }
}

# Resource policy for hourly snapshots (critical data)
resource "google_compute_resource_policy" "hourly_snapshot" {
  name    = "${var.deployment_name}-hourly-snapshot-policy"
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      hourly_schedule {
        hours_in_cycle = 4
        start_time     = "00:00"
      }
    }

    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = {
        deployment = var.deployment_name
        managed_by = "terraform"
        schedule   = "hourly"
      }
      storage_locations = [var.backup_region_primary]
      guest_flush       = true
    }
  }
}

# Resource policy for weekly snapshots
resource "google_compute_resource_policy" "weekly_snapshot" {
  name    = "${var.deployment_name}-weekly-snapshot-policy"
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      weekly_schedule {
        day_of_weeks {
          day        = "SUNDAY"
          start_time = format("%02d:00", var.snapshot_schedule_hour)
        }
      }
    }

    retention_policy {
      max_retention_days    = 90
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = {
        deployment = var.deployment_name
        managed_by = "terraform"
        schedule   = "weekly"
      }
      storage_locations = [var.backup_region_primary, var.backup_region_secondary]
      guest_flush       = true
    }
  }
}

# ============================================================================
# Cloud SQL Backup Export Configuration
# ============================================================================

# Service account for Cloud SQL backup exports
resource "google_service_account" "sql_backup_sa" {
  account_id   = "${var.deployment_name}-sql-backup"
  display_name = "Cloud SQL Backup Service Account"
  project      = var.project_id
}

# Grant Cloud SQL Admin role to backup service account
resource "google_project_iam_member" "sql_backup_admin" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.sql_backup_sa.email}"
}

# Grant Storage Admin role for backup exports
resource "google_storage_bucket_iam_member" "sql_backup_storage" {
  bucket = google_storage_bucket.backup_primary.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sql_backup_sa.email}"
}

# Grant Storage Admin role for secondary bucket
resource "google_storage_bucket_iam_member" "sql_backup_storage_secondary" {
  count  = var.enable_cross_region_replication ? 1 : 0
  bucket = google_storage_bucket.backup_secondary[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sql_backup_sa.email}"
}

# Cloud Scheduler job for automated SQL backups to GCS
resource "google_cloud_scheduler_job" "sql_backup_export" {
  name             = "${var.deployment_name}-sql-backup-export"
  description      = "Automated Cloud SQL backup export to GCS"
  schedule         = "0 3 * * *" # Daily at 3 AM
  time_zone        = "America/Los_Angeles"
  attempt_deadline = "320s"
  region           = var.region
  project          = var.project_id

  http_target {
    http_method = "POST"
    uri         = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${var.deployment_name}-db/export"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      exportContext = {
        kind     = "sql#exportContext"
        fileType = "SQL"
        uri      = "gs://${google_storage_bucket.backup_primary.name}/sql-exports/${var.deployment_name}-db-$(date +%Y%m%d-%H%M%S).sql.gz"
        databases = [var.database_name]
        sqlExportOptions = {
          schemaOnly = false
          mysqlExportOptions = {
            masterData = 0
          }
        }
      }
    }))

    oauth_token {
      service_account_email = google_service_account.sql_backup_sa.email
    }
  }

  retry_config {
    retry_count = 3
  }
}

# ============================================================================
# Cross-Region Replication with Storage Transfer Service
# ============================================================================

# Service account for Storage Transfer Service
resource "google_service_account" "storage_transfer_sa" {
  count        = var.enable_cross_region_replication ? 1 : 0
  account_id   = "${var.deployment_name}-transfer"
  display_name = "Storage Transfer Service Account"
  project      = var.project_id
}

# Grant Storage Admin role to transfer service account
resource "google_storage_bucket_iam_member" "transfer_source" {
  count  = var.enable_cross_region_replication ? 1 : 0
  bucket = google_storage_bucket.backup_primary.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.storage_transfer_sa[0].email}"
}

resource "google_storage_bucket_iam_member" "transfer_destination_secondary" {
  count  = var.enable_cross_region_replication ? 1 : 0
  bucket = google_storage_bucket.backup_secondary[0].name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.storage_transfer_sa[0].email}"
}

resource "google_storage_bucket_iam_member" "transfer_destination_tertiary" {
  count  = var.enable_disaster_recovery ? 1 : 0
  bucket = google_storage_bucket.backup_tertiary[0].name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.storage_transfer_sa[0].email}"
}

# Storage Transfer Job - Primary to Secondary
resource "google_storage_transfer_job" "backup_replication_secondary" {
  count       = var.enable_cross_region_replication ? 1 : 0
  description = "Daily backup replication from primary to secondary region"
  project     = var.project_id

  transfer_spec {
    gcs_data_source {
      bucket_name = google_storage_bucket.backup_primary.name
    }

    gcs_data_sink {
      bucket_name = google_storage_bucket.backup_secondary[0].name
    }

    transfer_options {
      delete_objects_unique_in_sink = false
      overwrite_objects_already_existing_in_sink = false
      overwrite_when = "DIFFERENT"
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 1
      day   = 1
    }

    start_time_of_day {
      hours   = 4
      minutes = 0
      seconds = 0
    }

    repeat_interval = "86400s" # Daily
  }

  depends_on = [
    google_storage_bucket_iam_member.transfer_source,
    google_storage_bucket_iam_member.transfer_destination_secondary
  ]
}

# Storage Transfer Job - Primary to Tertiary
resource "google_storage_transfer_job" "backup_replication_tertiary" {
  count       = var.enable_disaster_recovery ? 1 : 0
  description = "Daily backup replication from primary to tertiary region for DR"
  project     = var.project_id

  transfer_spec {
    gcs_data_source {
      bucket_name = google_storage_bucket.backup_primary.name
    }

    gcs_data_sink {
      bucket_name = google_storage_bucket.backup_tertiary[0].name
    }

    transfer_options {
      delete_objects_unique_in_sink = false
      overwrite_objects_already_existing_in_sink = false
      overwrite_when = "DIFFERENT"
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 1
      day   = 1
    }

    start_time_of_day {
      hours   = 5
      minutes = 0
      seconds = 0
    }

    repeat_interval = "86400s" # Daily
  }

  depends_on = [
    google_storage_bucket_iam_member.transfer_source,
    google_storage_bucket_iam_member.transfer_destination_tertiary
  ]
}

# ============================================================================
# GKE Persistent Volume Backup Configuration
# ============================================================================

# Service account for Volume Snapshots
resource "google_service_account" "volume_snapshot_sa" {
  account_id   = "${var.deployment_name}-volume-snapshot"
  display_name = "GKE Volume Snapshot Service Account"
  project      = var.project_id
}

# Grant Compute Storage Admin role
resource "google_project_iam_member" "volume_snapshot_admin" {
  project = var.project_id
  role    = "roles/compute.storageAdmin"
  member  = "serviceAccount:${google_service_account.volume_snapshot_sa.email}"
}

# Workload Identity binding for volume snapshots
resource "google_service_account_iam_member" "volume_snapshot_workload_identity" {
  service_account_id = google_service_account.volume_snapshot_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[kube-system/volume-snapshot-controller]"
}

# ============================================================================
# Disaster Recovery - Multi-Region Resources
# ============================================================================

# DR Cloud SQL Instance (standby in secondary region)
resource "google_sql_database_instance" "dr_replica" {
  count                = var.enable_disaster_recovery ? 1 : 0
  name                 = "${var.deployment_name}-db-dr"
  master_instance_name = google_sql_database_instance.main.name
  region               = var.backup_region_secondary
  database_version     = var.database_version
  project              = var.project_id

  replica_configuration {
    failover_target = true
  }

  settings {
    tier              = var.database_tier
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = var.database_ipv4_enabled
      require_ssl  = true
    }

    user_labels = {
      deployment = var.deployment_name
      managed_by = "terraform"
      role       = "disaster-recovery"
    }
  }
}

# ============================================================================
# Backup Monitoring and Alerting
# ============================================================================

# Cloud Monitoring notification channel
resource "google_monitoring_notification_channel" "backup_alerts" {
  display_name = "${var.deployment_name}-backup-alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email_address
  }

  enabled = true
}

variable "alert_email_address" {
  description = "Email address for backup alerts"
  type        = string
  default     = "alerts@example.com"
}

# Alert policy for failed backups
resource "google_monitoring_alert_policy" "backup_failure" {
  display_name = "${var.deployment_name}-backup-failure-alert"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud SQL Backup Failure"

    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/backup/failed\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.backup_alerts.id]

  alert_strategy {
    auto_close = "86400s" # 24 hours
  }

  documentation {
    content   = "Cloud SQL backup has failed. Please investigate immediately."
    mime_type = "text/markdown"
  }
}

# Alert policy for snapshot failures
resource "google_monitoring_alert_policy" "snapshot_failure" {
  display_name = "${var.deployment_name}-snapshot-failure-alert"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Disk Snapshot Failure"

    condition_threshold {
      filter          = "resource.type=\"gce_disk\" AND metric.type=\"compute.googleapis.com/snapshot/create_failures\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.backup_alerts.id]

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "Disk snapshot creation has failed. Please check snapshot policies."
    mime_type = "text/markdown"
  }
}

# ============================================================================
# Backup Verification and Testing
# ============================================================================

# Cloud Function for backup verification (requires separate deployment)
resource "google_storage_bucket" "backup_verification_code" {
  name          = "${var.deployment_name}-backup-verification-code"
  location      = var.backup_region_primary
  project       = var.project_id
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    deployment = var.deployment_name
    purpose    = "cloud-function-code"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "backup_bucket_primary" {
  description = "Primary backup bucket name"
  value       = google_storage_bucket.backup_primary.name
}

output "backup_bucket_secondary" {
  description = "Secondary backup bucket name"
  value       = var.enable_cross_region_replication ? google_storage_bucket.backup_secondary[0].name : null
}

output "backup_bucket_tertiary" {
  description = "Tertiary backup bucket name for disaster recovery"
  value       = var.enable_disaster_recovery ? google_storage_bucket.backup_tertiary[0].name : null
}

output "backup_encryption_key_primary" {
  description = "KMS key for backup encryption (primary region)"
  value       = google_kms_crypto_key.backup_key.id
}

output "snapshot_policy_daily" {
  description = "Daily snapshot policy name"
  value       = google_compute_resource_policy.daily_snapshot.name
}

output "snapshot_policy_hourly" {
  description = "Hourly snapshot policy name"
  value       = google_compute_resource_policy.hourly_snapshot.name
}

output "snapshot_policy_weekly" {
  description = "Weekly snapshot policy name"
  value       = google_compute_resource_policy.weekly_snapshot.name
}

output "sql_backup_service_account" {
  description = "Service account for SQL backup exports"
  value       = google_service_account.sql_backup_sa.email
}

output "storage_transfer_service_account" {
  description = "Service account for storage transfer operations"
  value       = var.enable_cross_region_replication ? google_service_account.storage_transfer_sa[0].email : null
}

output "dr_database_instance" {
  description = "Disaster recovery database instance name"
  value       = var.enable_disaster_recovery ? google_sql_database_instance.dr_replica[0].name : null
}

output "backup_monitoring_channel" {
  description = "Monitoring notification channel for backup alerts"
  value       = google_monitoring_notification_channel.backup_alerts.id
}
