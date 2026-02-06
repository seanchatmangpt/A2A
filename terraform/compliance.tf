locals {
  compliance_labels = {
    compliance_pci_dss  = "true"
    compliance_soc2     = "true"
    compliance_hipaa    = "true"
    compliance_iso27001 = "true"
    data_classification = "confidential"
    environment         = var.environment
  }

  audit_log_retention_days      = 2555
  backup_retention_days         = 2555
  access_log_retention_days     = 730
  security_log_retention_days   = 2555
  application_log_retention_days = 90
}

resource "google_project_service" "compliance_apis" {
  for_each = toset([
    "accesscontextmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "securitycenter.googleapis.com",
    "dlp.googleapis.com",
    "datacatalog.googleapis.com",
    "cloudaudit.googleapis.com",
    "binaryauthorization.googleapis.com",
    "policytroubleshooter.googleapis.com",
    "accessapproval.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

resource "google_kms_key_ring" "compliance_keyring" {
  name     = "${var.deployment_name}-compliance-keyring"
  location = var.region

  depends_on = [google_project_service.compliance_apis]
}

resource "google_kms_crypto_key" "data_encryption_key" {
  name            = "${var.deployment_name}-data-encryption-key"
  key_ring        = google_kms_key_ring.compliance_keyring.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  labels = local.compliance_labels
}

resource "google_kms_crypto_key" "database_encryption_key" {
  name            = "${var.deployment_name}-database-encryption-key"
  key_ring        = google_kms_key_ring.compliance_keyring.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  labels = local.compliance_labels
}

resource "google_kms_crypto_key" "backup_encryption_key" {
  name            = "${var.deployment_name}-backup-encryption-key"
  key_ring        = google_kms_key_ring.compliance_keyring.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  labels = local.compliance_labels
}

resource "google_kms_crypto_key" "secrets_encryption_key" {
  name            = "${var.deployment_name}-secrets-encryption-key"
  key_ring        = google_kms_key_ring.compliance_keyring.id
  rotation_period = "2592000s"

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  labels = local.compliance_labels
}

resource "google_logging_project_bucket_config" "audit_logs" {
  project        = var.project_id
  location       = "global"
  retention_days = local.audit_log_retention_days
  bucket_id      = "_Default"

  locked         = true
  enable_analytics = true
}

resource "google_logging_project_bucket_config" "security_logs" {
  project        = var.project_id
  location       = var.region
  retention_days = local.security_log_retention_days
  bucket_id      = "${var.deployment_name}-security-logs"

  locked         = true
  enable_analytics = true

  depends_on = [google_project_service.compliance_apis]
}

resource "google_logging_project_bucket_config" "access_logs" {
  project        = var.project_id
  location       = var.region
  retention_days = local.access_log_retention_days
  bucket_id      = "${var.deployment_name}-access-logs"

  locked         = true
  enable_analytics = true

  depends_on = [google_project_service.compliance_apis]
}

resource "google_logging_project_sink" "audit_sink" {
  name        = "${var.deployment_name}-audit-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs_bucket.name}"

  filter = <<-EOT
    protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"
    OR
    logName:"cloudaudit.googleapis.com"
  EOT

  unique_writer_identity = true

  depends_on = [google_project_service.compliance_apis]
}

resource "google_logging_project_sink" "security_sink" {
  name        = "${var.deployment_name}-security-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.security_logs_bucket.name}"

  filter = <<-EOT
    (severity >= ERROR)
    OR
    (protoPayload.authenticationInfo.principalEmail!="")
    OR
    (protoPayload.authorizationInfo:*)
    OR
    (resource.type="gce_firewall_rule")
    OR
    (resource.type="k8s_cluster")
  EOT

  unique_writer_identity = true

  depends_on = [google_project_service.compliance_apis]
}

resource "google_logging_project_sink" "data_access_sink" {
  name        = "${var.deployment_name}-data-access-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.data_access_logs_bucket.name}"

  filter = <<-EOT
    protoPayload.methodName:"storage.objects.get"
    OR
    protoPayload.methodName:"storage.objects.create"
    OR
    protoPayload.methodName:"storage.objects.delete"
    OR
    protoPayload.methodName:"sql.instances.get"
    OR
    protoPayload.methodName:"sql.instances.update"
    OR
    protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"
    AND protoPayload.resourceName=~".*database.*"
  EOT

  unique_writer_identity = true

  depends_on = [google_project_service.compliance_apis]
}

resource "google_storage_bucket" "audit_logs_bucket" {
  name          = "${var.project_id}-${var.deployment_name}-audit-logs"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = local.audit_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 365
      matches_storage_class = ["COLDLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }

  logging {
    log_bucket = google_storage_bucket.logs_of_logs_bucket.name
  }

  labels = merge(local.compliance_labels, {
    purpose = "audit-logs"
  })
}

resource "google_storage_bucket" "security_logs_bucket" {
  name          = "${var.project_id}-${var.deployment_name}-security-logs"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = local.security_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 365
      matches_storage_class = ["COLDLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }

  logging {
    log_bucket = google_storage_bucket.logs_of_logs_bucket.name
  }

  labels = merge(local.compliance_labels, {
    purpose = "security-logs"
  })
}

resource "google_storage_bucket" "data_access_logs_bucket" {
  name          = "${var.project_id}-${var.deployment_name}-data-access-logs"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = local.access_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }

  logging {
    log_bucket = google_storage_bucket.logs_of_logs_bucket.name
  }

  labels = merge(local.compliance_labels, {
    purpose = "data-access-logs"
  })
}

resource "google_storage_bucket" "logs_of_logs_bucket" {
  name          = "${var.project_id}-${var.deployment_name}-logs-of-logs"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.data_encryption_key.id
  }

  labels = merge(local.compliance_labels, {
    purpose = "meta-logs"
  })
}

resource "google_storage_bucket_iam_member" "audit_logs_writer" {
  bucket = google_storage_bucket.audit_logs_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_sink.writer_identity
}

resource "google_storage_bucket_iam_member" "security_logs_writer" {
  bucket = google_storage_bucket.security_logs_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.security_sink.writer_identity
}

resource "google_storage_bucket_iam_member" "data_access_logs_writer" {
  bucket = google_storage_bucket.data_access_logs_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.data_access_sink.writer_identity
}

resource "google_project_iam_audit_config" "project_audit_all" {
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

resource "google_project_iam_audit_config" "storage_audit" {
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

resource "google_project_iam_audit_config" "sql_audit" {
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

resource "google_project_iam_audit_config" "compute_audit" {
  project = var.project_id
  service = "compute.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }
}

resource "google_project_iam_audit_config" "container_audit" {
  project = var.project_id
  service = "container.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }
}

resource "google_project_iam_audit_config" "iam_audit" {
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

resource "google_monitoring_alert_policy" "unauthorized_access_attempts" {
  display_name = "${var.deployment_name}-unauthorized-access-attempts"
  combiner     = "OR"

  conditions {
    display_name = "Unauthorized access attempts"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/unauthorized_access\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true
}

resource "google_monitoring_alert_policy" "failed_authentication" {
  display_name = "${var.deployment_name}-failed-authentication"
  combiner     = "OR"

  conditions {
    display_name = "Failed authentication attempts"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/failed_auth\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true
}

resource "google_monitoring_alert_policy" "encryption_key_usage" {
  display_name = "${var.deployment_name}-encryption-key-usage"
  combiner     = "OR"

  conditions {
    display_name = "Encryption key unusual usage"

    condition_threshold {
      filter          = "resource.type=\"cloudkms_key\" AND metric.type=\"cloudkms.googleapis.com/kms/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1000

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true
}

resource "google_monitoring_alert_policy" "data_exfiltration" {
  display_name = "${var.deployment_name}-data-exfiltration"
  combiner     = "OR"

  conditions {
    display_name = "Unusual data egress"

    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/network/sent_bytes_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1073741824

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "3600s"
  }

  enabled = true
}

resource "google_monitoring_alert_policy" "privilege_escalation" {
  display_name = "${var.deployment_name}-privilege-escalation"
  combiner     = "OR"

  conditions {
    display_name = "IAM policy changes"

    condition_threshold {
      filter          = "resource.type=\"project\" AND protoPayload.methodName=\"SetIamPolicy\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true
}

resource "google_compute_security_policy" "pci_dss_policy" {
  name        = "${var.deployment_name}-pci-dss-policy"
  description = "PCI-DSS security policy for web application firewall"

  rule {
    action   = "deny(403)"
    priority = 1000

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }

    description = "Block SQL injection attempts"
  }

  rule {
    action   = "deny(403)"
    priority = 1001

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }

    description = "Block XSS attempts"
  }

  rule {
    action   = "deny(403)"
    priority = 1002

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }

    description = "Block local file inclusion attempts"
  }

  rule {
    action   = "deny(403)"
    priority = 1003

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }

    description = "Block remote code execution attempts"
  }

  rule {
    action   = "deny(403)"
    priority = 1004

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-stable')"
      }
    }

    description = "Block remote file inclusion attempts"
  }

  rule {
    action   = "deny(403)"
    priority = 2000

    match {
      expr {
        expression = "origin.region_code == 'CN' || origin.region_code == 'KP' || origin.region_code == 'IR' || origin.region_code == 'SY'"
      }
    }

    description = "Block high-risk countries"
  }

  rule {
    action   = "rate_based_ban"
    priority = 3000

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }

      ban_duration_sec = 600
    }

    description = "Rate limiting for DDoS protection"
  }

  rule {
    action   = "allow"
    priority = 2147483647

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }

    description = "Default allow rule"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  name    = "${var.deployment_name}-deny-all-ingress"
  network = google_compute_network.vpc.name

  priority  = 65534
  direction = "INGRESS"

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_all_egress" {
  name    = "${var.deployment_name}-deny-all-egress"
  network = google_compute_network.vpc.name

  priority  = 65534
  direction = "EGRESS"

  deny {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_https_ingress" {
  name    = "${var.deployment_name}-allow-https-ingress"
  network = google_compute_network.vpc.name

  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["https-server"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.deployment_name}-allow-health-check"
  network = google_compute_network.vpc.name

  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["allow-health-check"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_secret_manager_secret" "compliance_secrets" {
  for_each = toset([
    "database-password",
    "api-key",
    "encryption-key",
    "jwt-secret",
    "oauth-client-secret"
  ])

  secret_id = "${var.deployment_name}-${each.key}"

  replication {
    user_managed {
      replicas {
        location = var.region

        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_encryption_key.id
        }
      }

      replicas {
        location = var.region == "us-central1" ? "us-east1" : "us-central1"

        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_encryption_key.id
        }
      }
    }
  }

  labels = merge(local.compliance_labels, {
    secret_type = each.key
  })

  depends_on = [google_project_service.compliance_apis]
}

resource "google_binary_authorization_policy" "policy" {
  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.project_id}/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = []
  }

  global_policy_evaluation_mode = "ENABLE"
}

resource "google_access_context_manager_access_policy" "access_policy" {
  parent = "organizations/${var.organization_id}"
  title  = "${var.deployment_name}-access-policy"
  scopes = ["projects/${data.google_project.project.number}"]

  depends_on = [google_project_service.compliance_apis]
}

resource "google_access_context_manager_access_level" "access_level_ip" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/accessLevels/${var.deployment_name}_ip_level"
  title  = "${var.deployment_name}-ip-access-level"

  basic {
    conditions {
      ip_subnetworks = var.authorized_networks
    }
  }
}

resource "google_access_context_manager_access_level" "access_level_device" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/accessLevels/${var.deployment_name}_device_level"
  title  = "${var.deployment_name}-device-access-level"

  basic {
    conditions {
      device_policy {
        require_screen_lock              = true
        require_admin_approval           = true
        require_corp_owned               = true
        allowed_encryption_statuses      = ["ENCRYPTED"]
        allowed_device_management_levels = ["COMPLETE"]

        os_constraints {
          minimum_version = "10.0"
          os_type         = "DESKTOP_WINDOWS"
        }

        os_constraints {
          minimum_version = "11.0"
          os_type         = "DESKTOP_MAC"
        }

        os_constraints {
          minimum_version = "8.0"
          os_type         = "DESKTOP_CHROME_OS"
        }
      }
    }
  }
}

resource "google_access_context_manager_service_perimeter" "service_perimeter" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/servicePerimeters/${var.deployment_name}_perimeter"
  title  = "${var.deployment_name}-service-perimeter"

  status {
    restricted_services = [
      "storage.googleapis.com",
      "sqladmin.googleapis.com",
      "bigquery.googleapis.com",
      "bigtable.googleapis.com",
      "cloudkms.googleapis.com",
      "secretmanager.googleapis.com"
    ]

    access_levels = [
      google_access_context_manager_access_level.access_level_ip.name,
      google_access_context_manager_access_level.access_level_device.name
    ]

    resources = ["projects/${data.google_project.project.number}"]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services = [
        "storage.googleapis.com",
        "sqladmin.googleapis.com",
        "logging.googleapis.com",
        "monitoring.googleapis.com"
      ]
    }
  }
}

resource "google_data_loss_prevention_inspect_template" "phi_pii_template" {
  parent       = "projects/${var.project_id}"
  display_name = "${var.deployment_name}-phi-pii-inspect-template"
  description  = "Template for detecting PHI and PII data"

  inspect_config {
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }

    info_types {
      name = "EMAIL_ADDRESS"
    }

    info_types {
      name = "PHONE_NUMBER"
    }

    info_types {
      name = "US_SOCIAL_SECURITY_NUMBER"
    }

    info_types {
      name = "PASSPORT"
    }

    info_types {
      name = "MEDICAL_RECORD_NUMBER"
    }

    info_types {
      name = "US_HEALTHCARE_NPI"
    }

    info_types {
      name = "PERSON_NAME"
    }

    info_types {
      name = "DATE_OF_BIRTH"
    }

    info_types {
      name = "ETHNIC_GROUP"
    }

    min_likelihood = "POSSIBLE"

    rule_set {
      info_types {
        name = "CREDIT_CARD_NUMBER"
      }

      rules {
        exclusion_rule {
          matching_type = "MATCHING_TYPE_FULL_MATCH"
          dictionary {
            word_list {
              words = ["0000000000000000", "1111111111111111"]
            }
          }
        }
      }
    }

    limits {
      max_findings_per_item    = 0
      max_findings_per_request = 0
    }
  }

  depends_on = [google_project_service.compliance_apis]
}

resource "google_data_loss_prevention_job_trigger" "database_scan" {
  parent       = "projects/${var.project_id}"
  display_name = "${var.deployment_name}-database-phi-pii-scan"
  description  = "Automated scan for PHI/PII in databases"

  triggers {
    schedule {
      recurrence_period_duration = "86400s"
    }
  }

  inspect_job {
    inspect_template_name = google_data_loss_prevention_inspect_template.phi_pii_template.name

    storage_config {
      cloud_storage_options {
        file_set {
          url = "gs://${google_storage_bucket.audit_logs_bucket.name}/*"
        }
      }
    }

    actions {
      save_findings {
        output_config {
          table {
            project_id = var.project_id
            dataset_id = "dlp_findings"
          }
        }
      }
    }

    actions {
      pub_sub {
        topic = "projects/${var.project_id}/topics/${var.deployment_name}-dlp-findings"
      }
    }
  }

  depends_on = [google_project_service.compliance_apis]
}

resource "google_organization_policy" "require_os_login" {
  org_id     = var.organization_id
  constraint = "compute.requireOsLogin"

  boolean_policy {
    enforced = true
  }
}

resource "google_organization_policy" "skip_default_network" {
  org_id     = var.organization_id
  constraint = "compute.skipDefaultNetworkCreation"

  boolean_policy {
    enforced = true
  }
}

resource "google_organization_policy" "disable_sa_key_creation" {
  org_id     = var.organization_id
  constraint = "iam.disableServiceAccountKeyCreation"

  boolean_policy {
    enforced = true
  }
}

resource "google_organization_policy" "require_shielded_vm" {
  org_id     = var.organization_id
  constraint = "compute.requireShieldedVm"

  boolean_policy {
    enforced = true
  }
}

resource "google_organization_policy" "disable_guest_attributes" {
  org_id     = var.organization_id
  constraint = "compute.disableGuestAttributesAccess"

  boolean_policy {
    enforced = true
  }
}

resource "google_organization_policy" "allowed_policy_member_domains" {
  org_id     = var.organization_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      values = var.allowed_domains
    }
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

output "compliance_kms_keyring_id" {
  description = "KMS keyring ID for compliance encryption"
  value       = google_kms_key_ring.compliance_keyring.id
}

output "audit_logs_bucket" {
  description = "Bucket name for audit logs"
  value       = google_storage_bucket.audit_logs_bucket.name
}

output "security_logs_bucket" {
  description = "Bucket name for security logs"
  value       = google_storage_bucket.security_logs_bucket.name
}

output "data_access_logs_bucket" {
  description = "Bucket name for data access logs"
  value       = google_storage_bucket.data_access_logs_bucket.name
}

output "security_policy_id" {
  description = "Security policy ID for PCI-DSS WAF"
  value       = google_compute_security_policy.pci_dss_policy.id
}

output "service_perimeter_name" {
  description = "VPC Service Controls perimeter name"
  value       = google_access_context_manager_service_perimeter.service_perimeter.name
}

output "dlp_inspect_template" {
  description = "DLP inspect template for PHI/PII detection"
  value       = google_data_loss_prevention_inspect_template.phi_pii_template.name
}
