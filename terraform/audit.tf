# ================================================================================
# CLOUD AUDIT LOGGING - FORTUNE 5 ENTERPRISE CONFIGURATION
# ================================================================================
# Comprehensive audit logging for compliance, security monitoring, and SIEM integration
# Supports SOX, PCI-DSS, HIPAA, ISO 27001, and other regulatory requirements

# ================================================================================
# AUDIT LOG CONFIGURATION
# ================================================================================

# Organization-level audit config (if applicable)
resource "google_project_iam_audit_config" "all_services" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Specific service audit configs for critical services
resource "google_project_iam_audit_config" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "sqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_project_iam_audit_config" "kubernetes" {
  project = var.project_id
  service = "container.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# ================================================================================
# CLOUD STORAGE BUCKETS FOR AUDIT LOGS
# ================================================================================

# Primary audit log bucket - long-term retention
resource "google_storage_bucket" "audit_logs_primary" {
  name          = "${var.project_id}-audit-logs-primary"
  location      = "US"
  storage_class = "COLDLINE"
  project       = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
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

  lifecycle_rule {
    condition {
      age = 2555  # 7 years for compliance
    }
    action {
      type = "Delete"
    }
  }

  retention_policy {
    retention_period = 220752000  # 7 years in seconds
    is_locked        = false
  }

  logging {
    log_bucket = google_storage_bucket.access_logs.name
  }

  labels = {
    purpose     = "audit-logs"
    compliance  = "sox-pci-hipaa"
    retention   = "7-years"
    environment = "production"
  }
}

# Secondary audit log bucket - geo-redundant
resource "google_storage_bucket" "audit_logs_secondary" {
  name          = "${var.project_id}-audit-logs-secondary"
  location      = "EU"
  storage_class = "COLDLINE"
  project       = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
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

  lifecycle_rule {
    condition {
      age = 2555
    }
    action {
      type = "Delete"
    }
  }

  retention_policy {
    retention_period = 220752000
    is_locked        = false
  }

  labels = {
    purpose     = "audit-logs-backup"
    compliance  = "sox-pci-hipaa"
    retention   = "7-years"
    environment = "production"
  }
}

# Access logs bucket for bucket access auditing
resource "google_storage_bucket" "access_logs" {
  name          = "${var.project_id}-bucket-access-logs"
  location      = "US"
  storage_class = "STANDARD"
  project       = var.project_id

  uniform_bucket_level_access = true

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
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose = "access-logs"
  }
}

# Security logs bucket for immediate analysis
resource "google_storage_bucket" "security_logs" {
  name          = "${var.project_id}-security-logs"
  location      = "US"
  storage_class = "STANDARD"
  project       = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = {
    purpose     = "security-monitoring"
    environment = "production"
  }
}

# ================================================================================
# BIGQUERY DATASET FOR AUDIT LOG ANALYTICS
# ================================================================================

resource "google_bigquery_dataset" "audit_logs" {
  dataset_id                 = "audit_logs"
  project                    = var.project_id
  location                   = "US"
  description                = "Audit logs for compliance and security analytics"
  default_table_expiration_ms = 220752000000  # 7 years in milliseconds

  labels = {
    purpose    = "audit-analytics"
    compliance = "sox-pci-hipaa"
  }

  access {
    role          = "OWNER"
    user_by_email = "serviceAccount:${google_service_account.audit_log_writer.email}"
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }
}

resource "google_bigquery_dataset" "security_analytics" {
  dataset_id                 = "security_analytics"
  project                    = var.project_id
  location                   = "US"
  description                = "Security event analytics and threat detection"
  default_table_expiration_ms = 31536000000  # 1 year

  labels = {
    purpose = "security-analytics"
  }

  access {
    role          = "OWNER"
    user_by_email = "serviceAccount:${google_service_account.audit_log_writer.email}"
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }
}

# ================================================================================
# PUB/SUB TOPICS FOR SIEM INTEGRATION
# ================================================================================

# Primary SIEM topic for real-time log streaming
resource "google_pubsub_topic" "siem_logs" {
  name    = "siem-audit-logs"
  project = var.project_id

  message_retention_duration = "604800s"  # 7 days

  labels = {
    purpose = "siem-integration"
    target  = "splunk-qradar-sentinel"
  }
}

# Security events topic for high-priority alerts
resource "google_pubsub_topic" "security_events" {
  name    = "security-events"
  project = var.project_id

  message_retention_duration = "86400s"  # 1 day

  labels = {
    purpose  = "security-alerts"
    priority = "high"
  }
}

# Compliance events topic
resource "google_pubsub_topic" "compliance_events" {
  name    = "compliance-events"
  project = var.project_id

  message_retention_duration = "604800s"

  labels = {
    purpose    = "compliance-monitoring"
    compliance = "sox-pci-hipaa"
  }
}

# Data access topic for sensitive data monitoring
resource "google_pubsub_topic" "data_access" {
  name    = "data-access-logs"
  project = var.project_id

  message_retention_duration = "604800s"

  labels = {
    purpose = "data-access-monitoring"
  }
}

# ================================================================================
# PUB/SUB SUBSCRIPTIONS FOR SIEM CONSUMERS
# ================================================================================

resource "google_pubsub_subscription" "siem_pull" {
  name    = "siem-audit-logs-pull"
  topic   = google_pubsub_topic.siem_logs.name
  project = var.project_id

  ack_deadline_seconds = 600

  message_retention_duration = "604800s"

  retain_acked_messages = false

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = {
    consumer = "siem"
  }
}

resource "google_pubsub_subscription" "security_events_push" {
  name    = "security-events-push"
  topic   = google_pubsub_topic.security_events.name
  project = var.project_id

  ack_deadline_seconds = 300

  message_retention_duration = "86400s"

  labels = {
    consumer = "security-team"
  }
}

# ================================================================================
# SERVICE ACCOUNT FOR LOG SINKS
# ================================================================================

resource "google_service_account" "audit_log_writer" {
  account_id   = "audit-log-writer"
  display_name = "Audit Log Writer Service Account"
  description  = "Service account for writing audit logs to sinks"
  project      = var.project_id
}

# Storage permissions
resource "google_storage_bucket_iam_member" "primary_writer" {
  bucket = google_storage_bucket.audit_logs_primary.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.audit_log_writer.email}"
}

resource "google_storage_bucket_iam_member" "secondary_writer" {
  bucket = google_storage_bucket.audit_logs_secondary.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.audit_log_writer.email}"
}

resource "google_storage_bucket_iam_member" "security_writer" {
  bucket = google_storage_bucket.security_logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.audit_log_writer.email}"
}

# BigQuery permissions
resource "google_bigquery_dataset_iam_member" "audit_editor" {
  dataset_id = google_bigquery_dataset.audit_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project    = var.project_id
}

resource "google_bigquery_dataset_iam_member" "security_editor" {
  dataset_id = google_bigquery_dataset.security_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project    = var.project_id
}

# Pub/Sub permissions
resource "google_pubsub_topic_iam_member" "siem_publisher" {
  topic   = google_pubsub_topic.siem_logs.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "security_publisher" {
  topic   = google_pubsub_topic.security_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "compliance_publisher" {
  topic   = google_pubsub_topic.compliance_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "data_access_publisher" {
  topic   = google_pubsub_topic.data_access.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.audit_log_writer.email}"
  project = var.project_id
}

# ================================================================================
# LOG SINKS - ADMIN ACTIVITY
# ================================================================================

resource "google_logging_project_sink" "admin_activity_storage" {
  name        = "admin-activity-to-storage"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs_primary.name}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Factivity"
    OR logName:"cloudaudit.googleapis.com%2Fsystem_event"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_logging_project_sink" "admin_activity_bigquery" {
  name        = "admin-activity-to-bigquery"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.audit_logs.dataset_id}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Factivity"
    OR logName:"cloudaudit.googleapis.com%2Fsystem_event"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_logging_project_sink" "admin_activity_pubsub" {
  name        = "admin-activity-to-pubsub"
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.siem_logs.name}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Factivity"
    OR logName:"cloudaudit.googleapis.com%2Fsystem_event"
  EOT

  unique_writer_identity = true
}

# ================================================================================
# LOG SINKS - DATA ACCESS
# ================================================================================

resource "google_logging_project_sink" "data_access_storage" {
  name        = "data-access-to-storage"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs_primary.name}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Fdata_access"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_logging_project_sink" "data_access_bigquery" {
  name        = "data-access-to-bigquery"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.audit_logs.dataset_id}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Fdata_access"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_logging_project_sink" "data_access_pubsub" {
  name        = "data-access-to-pubsub"
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.data_access.name}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com%2Fdata_access"
  EOT

  unique_writer_identity = true
}

# ================================================================================
# LOG SINKS - SECURITY EVENTS
# ================================================================================

resource "google_logging_project_sink" "security_events" {
  name        = "security-events-to-storage"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.security_logs.name}"

  filter = <<-EOT
    (protoPayload.methodName=~"^.*[Ss]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName=~"^.*[Gg]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName=~"^.*create.*"
    OR protoPayload.methodName=~"^.*delete.*"
    OR protoPayload.methodName:"setMetadata"
    OR protoPayload.methodName:"beta.compute.instances.insert"
    OR protoPayload.methodName:"v1.compute.instances.delete"
    OR protoPayload.methodName:"storage.objects.create"
    OR protoPayload.methodName:"storage.objects.delete"
    OR protoPayload.methodName:"storage.buckets.delete"
    OR protoPayload.methodName:"cloudsql.instances.delete"
    OR protoPayload.serviceName:"iam.googleapis.com"
    OR protoPayload.serviceName:"cloudkms.googleapis.com"
    OR severity >= "ERROR")
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_logging_project_sink" "security_events_pubsub" {
  name        = "security-events-to-pubsub"
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.security_events.name}"

  filter = <<-EOT
    (protoPayload.methodName=~"^.*[Ss]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName=~"^.*[Gg]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName=~"^.*create.*"
    OR protoPayload.methodName=~"^.*delete.*"
    OR protoPayload.methodName:"setMetadata"
    OR protoPayload.serviceName:"iam.googleapis.com"
    OR protoPayload.serviceName:"cloudkms.googleapis.com"
    OR severity >= "ERROR")
  EOT

  unique_writer_identity = true
}

# ================================================================================
# LOG SINKS - COMPLIANCE MONITORING
# ================================================================================

resource "google_logging_project_sink" "compliance_logs" {
  name        = "compliance-logs"
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.compliance_events.name}"

  filter = <<-EOT
    (resource.type:"gcs_bucket"
    OR resource.type:"bigquery_dataset"
    OR resource.type:"cloudsql_database"
    OR resource.type:"k8s_cluster"
    OR protoPayload.serviceName:"compute.googleapis.com"
    OR protoPayload.serviceName:"container.googleapis.com"
    OR protoPayload.serviceName:"storage.googleapis.com"
    OR protoPayload.serviceName:"sqladmin.googleapis.com"
    OR protoPayload.serviceName:"iam.googleapis.com")
    AND logName:"cloudaudit.googleapis.com"
  EOT

  unique_writer_identity = true
}

# Secondary geo-redundant sink
resource "google_logging_project_sink" "compliance_storage_eu" {
  name        = "compliance-logs-eu-backup"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs_secondary.name}"

  filter = <<-EOT
    logName:"cloudaudit.googleapis.com"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# ================================================================================
# LOG SINKS - IAM AND AUTHENTICATION
# ================================================================================

resource "google_logging_project_sink" "iam_logs" {
  name        = "iam-authentication-logs"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.security_analytics.dataset_id}"

  filter = <<-EOT
    protoPayload.serviceName:"iam.googleapis.com"
    OR protoPayload.serviceName:"iamcredentials.googleapis.com"
    OR protoPayload.serviceName:"sts.googleapis.com"
    OR protoPayload.serviceName:"cloudidentity.googleapis.com"
    OR protoPayload.methodName=~"^.*[Ss]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName=~"^.*[Gg]et[Ii]am[Pp]olicy$"
    OR protoPayload.methodName:"GenerateAccessToken"
    OR protoPayload.methodName:"SignBlob"
    OR protoPayload.methodName:"SignJwt"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# ================================================================================
# LOG SINKS - NETWORK SECURITY
# ================================================================================

resource "google_logging_project_sink" "network_logs" {
  name        = "network-security-logs"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.security_analytics.dataset_id}"

  filter = <<-EOT
    resource.type:"gce_firewall_rule"
    OR resource.type:"gce_route"
    OR resource.type:"gce_network"
    OR resource.type:"gce_subnetwork"
    OR logName:"compute.googleapis.com/firewall"
    OR protoPayload.serviceName:"compute.googleapis.com"
    AND (protoPayload.methodName:"firewalls.insert"
    OR protoPayload.methodName:"firewalls.delete"
    OR protoPayload.methodName:"firewalls.patch"
    OR protoPayload.methodName:"networks.insert"
    OR protoPayload.methodName:"networks.delete"
    OR protoPayload.methodName:"subnetworks.insert"
    OR protoPayload.methodName:"subnetworks.delete")
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# ================================================================================
# LOG SINKS - GKE SECURITY
# ================================================================================

resource "google_logging_project_sink" "gke_security" {
  name        = "gke-security-logs"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.security_analytics.dataset_id}"

  filter = <<-EOT
    resource.type:"k8s_cluster"
    OR resource.type:"k8s_pod"
    OR resource.type:"k8s_node"
    OR protoPayload.serviceName:"container.googleapis.com"
    OR logName:"cloudaudit.googleapis.com%2Factivity"
    AND protoPayload.resourceName=~"^projects/.*/zones/.*/clusters/.*"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# ================================================================================
# LOG SINKS - DATABASE ACCESS
# ================================================================================

resource "google_logging_project_sink" "database_access" {
  name        = "database-access-logs"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.audit_logs.dataset_id}"

  filter = <<-EOT
    protoPayload.serviceName:"cloudsql.googleapis.com"
    OR resource.type:"cloudsql_database"
    OR logName:"cloudaudit.googleapis.com%2Fdata_access"
    AND protoPayload.resourceName=~"^projects/.*/instances/.*"
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# ================================================================================
# IAM BINDINGS FOR LOG SINK WRITERS
# ================================================================================

resource "google_project_iam_member" "admin_activity_storage_writer" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = google_logging_project_sink.admin_activity_storage.writer_identity
}

resource "google_project_iam_member" "admin_activity_bigquery_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.admin_activity_bigquery.writer_identity
}

resource "google_project_iam_member" "admin_activity_pubsub_writer" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.admin_activity_pubsub.writer_identity
}

resource "google_project_iam_member" "data_access_storage_writer" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = google_logging_project_sink.data_access_storage.writer_identity
}

resource "google_project_iam_member" "data_access_bigquery_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.data_access_bigquery.writer_identity
}

resource "google_project_iam_member" "data_access_pubsub_writer" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.data_access_pubsub.writer_identity
}

resource "google_project_iam_member" "security_events_storage_writer" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = google_logging_project_sink.security_events.writer_identity
}

resource "google_project_iam_member" "security_events_pubsub_writer" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.security_events_pubsub.writer_identity
}

resource "google_project_iam_member" "compliance_pubsub_writer" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.compliance_logs.writer_identity
}

resource "google_project_iam_member" "compliance_storage_writer" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = google_logging_project_sink.compliance_storage_eu.writer_identity
}

resource "google_project_iam_member" "iam_logs_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.iam_logs.writer_identity
}

resource "google_project_iam_member" "network_logs_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.network_logs.writer_identity
}

resource "google_project_iam_member" "gke_security_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.gke_security.writer_identity
}

resource "google_project_iam_member" "database_access_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.database_access.writer_identity
}

# ================================================================================
# LOG METRICS FOR SECURITY MONITORING
# ================================================================================

resource "google_logging_metric" "unauthorized_access_attempts" {
  name    = "unauthorized-access-attempts"
  project = var.project_id
  filter  = <<-EOT
    protoPayload.status.code="7"
    OR protoPayload.status.code="16"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Unauthorized Access Attempts"

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User attempting access"
    }

    labels {
      key         = "method"
      value_type  = "STRING"
      description = "API method called"
    }
  }

  label_extractors = {
    "user"   = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
    "method" = "EXTRACT(protoPayload.methodName)"
  }
}

resource "google_logging_metric" "iam_policy_changes" {
  name    = "iam-policy-changes"
  project = var.project_id
  filter  = <<-EOT
    protoPayload.methodName:"SetIamPolicy"
    OR protoPayload.methodName:"setIamPolicy"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "IAM Policy Changes"

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User making policy change"
    }

    labels {
      key         = "resource"
      value_type  = "STRING"
      description = "Resource affected"
    }
  }

  label_extractors = {
    "user"     = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
    "resource" = "EXTRACT(protoPayload.resourceName)"
  }
}

resource "google_logging_metric" "firewall_rule_changes" {
  name    = "firewall-rule-changes"
  project = var.project_id
  filter  = <<-EOT
    resource.type:"gce_firewall_rule"
    AND (protoPayload.methodName:"firewalls.insert"
    OR protoPayload.methodName:"firewalls.delete"
    OR protoPayload.methodName:"firewalls.patch")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Firewall Rule Changes"

    labels {
      key         = "action"
      value_type  = "STRING"
      description = "Action performed"
    }

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User making change"
    }
  }

  label_extractors = {
    "action" = "EXTRACT(protoPayload.methodName)"
    "user"   = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}

resource "google_logging_metric" "bucket_deletions" {
  name    = "bucket-deletions"
  project = var.project_id
  filter  = <<-EOT
    protoPayload.methodName:"storage.buckets.delete"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Storage Bucket Deletions"

    labels {
      key         = "bucket"
      value_type  = "STRING"
      description = "Bucket deleted"
    }

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User performing deletion"
    }
  }

  label_extractors = {
    "bucket" = "EXTRACT(protoPayload.resourceName)"
    "user"   = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}

resource "google_logging_metric" "sql_instance_deletions" {
  name    = "sql-instance-deletions"
  project = var.project_id
  filter  = <<-EOT
    protoPayload.serviceName:"cloudsql.googleapis.com"
    AND protoPayload.methodName:"cloudsql.instances.delete"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Cloud SQL Instance Deletions"

    labels {
      key         = "instance"
      value_type  = "STRING"
      description = "SQL instance deleted"
    }

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User performing deletion"
    }
  }

  label_extractors = {
    "instance" = "EXTRACT(protoPayload.resourceName)"
    "user"     = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}

resource "google_logging_metric" "privileged_role_assignments" {
  name    = "privileged-role-assignments"
  project = var.project_id
  filter  = <<-EOT
    protoPayload.methodName:"SetIamPolicy"
    AND (protoPayload.request.policy.bindings.role:"roles/owner"
    OR protoPayload.request.policy.bindings.role:"roles/editor"
    OR protoPayload.request.policy.bindings.role:"roles/iam.securityAdmin"
    OR protoPayload.request.policy.bindings.role:"roles/iam.serviceAccountAdmin"
    OR protoPayload.request.policy.bindings.role:"roles/resourcemanager.organizationAdmin")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Privileged Role Assignments"

    labels {
      key         = "role"
      value_type  = "STRING"
      description = "Role assigned"
    }

    labels {
      key         = "user"
      value_type  = "STRING"
      description = "User assigning role"
    }
  }

  label_extractors = {
    "role" = "EXTRACT(protoPayload.request.policy.bindings.role)"
    "user" = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
  }
}

# ================================================================================
# OUTPUTS
# ================================================================================

output "audit_log_bucket_primary" {
  description = "Primary audit log storage bucket"
  value       = google_storage_bucket.audit_logs_primary.name
}

output "audit_log_bucket_secondary" {
  description = "Secondary audit log storage bucket (geo-redundant)"
  value       = google_storage_bucket.audit_logs_secondary.name
}

output "security_log_bucket" {
  description = "Security log storage bucket"
  value       = google_storage_bucket.security_logs.name
}

output "audit_bigquery_dataset" {
  description = "BigQuery dataset for audit log analytics"
  value       = google_bigquery_dataset.audit_logs.dataset_id
}

output "security_bigquery_dataset" {
  description = "BigQuery dataset for security analytics"
  value       = google_bigquery_dataset.security_analytics.dataset_id
}

output "siem_topic" {
  description = "Pub/Sub topic for SIEM integration"
  value       = google_pubsub_topic.siem_logs.name
}

output "security_events_topic" {
  description = "Pub/Sub topic for security events"
  value       = google_pubsub_topic.security_events.name
}

output "compliance_events_topic" {
  description = "Pub/Sub topic for compliance events"
  value       = google_pubsub_topic.compliance_events.name
}

output "data_access_topic" {
  description = "Pub/Sub topic for data access logs"
  value       = google_pubsub_topic.data_access.name
}

output "audit_log_writer_email" {
  description = "Service account email for audit log writer"
  value       = google_service_account.audit_log_writer.email
}

output "log_sinks" {
  description = "Map of all log sinks created"
  value = {
    admin_activity_storage  = google_logging_project_sink.admin_activity_storage.name
    admin_activity_bigquery = google_logging_project_sink.admin_activity_bigquery.name
    admin_activity_pubsub   = google_logging_project_sink.admin_activity_pubsub.name
    data_access_storage     = google_logging_project_sink.data_access_storage.name
    data_access_bigquery    = google_logging_project_sink.data_access_bigquery.name
    data_access_pubsub      = google_logging_project_sink.data_access_pubsub.name
    security_events         = google_logging_project_sink.security_events.name
    security_events_pubsub  = google_logging_project_sink.security_events_pubsub.name
    compliance_logs         = google_logging_project_sink.compliance_logs.name
    compliance_storage_eu   = google_logging_project_sink.compliance_storage_eu.name
    iam_logs                = google_logging_project_sink.iam_logs.name
    network_logs            = google_logging_project_sink.network_logs.name
    gke_security            = google_logging_project_sink.gke_security.name
    database_access         = google_logging_project_sink.database_access.name
  }
}
