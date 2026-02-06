# Cloud KMS Key Ring
resource "google_kms_key_ring" "keyring" {
  name     = "${var.deployment_name}-keyring"
  location = var.region
}

# CMEK for GKE ETCD encryption
resource "google_kms_crypto_key" "gke_etcd_key" {
  name     = "${var.deployment_name}-gke-etcd-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

# CMEK for Cloud SQL
resource "google_kms_crypto_key" "cloudsql_key" {
  name     = "${var.deployment_name}-cloudsql-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

# CMEK for GCS buckets
resource "google_kms_crypto_key" "gcs_key" {
  name     = "${var.deployment_name}-gcs-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

# CMEK for Compute Engine persistent disks
resource "google_kms_crypto_key" "disk_key" {
  name     = "${var.deployment_name}-disk-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
}

# Application-layer encryption key for sensitive data
resource "google_kms_crypto_key" "app_data_key" {
  name     = "${var.deployment_name}-app-data-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  purpose = "ENCRYPT_DECRYPT"
}

# Application-layer encryption key for PII
resource "google_kms_crypto_key" "pii_key" {
  name     = "${var.deployment_name}-pii-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  purpose = "ENCRYPT_DECRYPT"
}

# Secrets encryption key for application secrets
resource "google_kms_crypto_key" "secrets_key" {
  name     = "${var.deployment_name}-secrets-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  purpose = "ENCRYPT_DECRYPT"
}

# Secrets Manager secret encrypted with CMEK
resource "google_secret_manager_secret" "app_secrets" {
  secret_id = "${var.deployment_name}-app-secrets"

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_key.id
        }
      }
    }
  }

  labels = {
    deployment = var.deployment_name
    encrypted  = "cmek"
  }
}

# IAM binding for GKE to use ETCD encryption key
resource "google_kms_crypto_key_iam_member" "gke_etcd_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.gke_etcd_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@container-engine-robot.iam.gserviceaccount.com"
}

# IAM binding for Cloud SQL to use encryption key
resource "google_kms_crypto_key_iam_member" "cloudsql_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.cloudsql_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"
}

# IAM binding for GCS to use encryption key
resource "google_kms_crypto_key_iam_member" "gcs_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.gcs_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# IAM binding for Compute Engine to use disk encryption key
resource "google_kms_crypto_key_iam_member" "disk_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.disk_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com"
}

# IAM binding for application service account to use app data key
resource "google_kms_crypto_key_iam_member" "app_data_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.app_data_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app_sa.email}"
}

# IAM binding for application service account to use PII key
resource "google_kms_crypto_key_iam_member" "pii_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.pii_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app_sa.email}"
}

# IAM binding for application service account to use secrets key
resource "google_kms_crypto_key_iam_member" "secrets_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.secrets_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app_sa.email}"
}

# IAM binding for application service account to access secrets
resource "google_secret_manager_secret_iam_member" "app_secrets_accessor" {
  secret_id = google_secret_manager_secret.app_secrets.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app_sa.email}"
}

# Data source for project number
data "google_project" "project" {
  project_id = var.project_id
}

# Database encryption configuration
resource "google_kms_crypto_key" "database_field_encryption_key" {
  name     = "${var.deployment_name}-db-field-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "2592000s" # 30 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  purpose = "ENCRYPT_DECRYPT"
}

# IAM binding for database field encryption
resource "google_kms_crypto_key_iam_member" "db_field_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.database_field_encryption_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app_sa.email}"
}

# Key for encrypting backup data
resource "google_kms_crypto_key" "backup_key" {
  name     = "${var.deployment_name}-backup-key"
  key_ring = google_kms_key_ring.keyring.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  purpose = "ENCRYPT_DECRYPT"
}

# IAM binding for backup encryption
resource "google_kms_crypto_key_iam_member" "backup_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.backup_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.app_sa.email}"
}

# Outputs for encryption keys
output "kms_keyring_id" {
  description = "The ID of the KMS key ring"
  value       = google_kms_key_ring.keyring.id
}

output "gke_etcd_key_id" {
  description = "The ID of the GKE ETCD encryption key"
  value       = google_kms_crypto_key.gke_etcd_key.id
}

output "cloudsql_key_id" {
  description = "The ID of the Cloud SQL encryption key"
  value       = google_kms_crypto_key.cloudsql_key.id
}

output "gcs_key_id" {
  description = "The ID of the GCS encryption key"
  value       = google_kms_crypto_key.gcs_key.id
}

output "app_data_key_id" {
  description = "The ID of the application data encryption key"
  value       = google_kms_crypto_key.app_data_key.id
}

output "pii_key_id" {
  description = "The ID of the PII encryption key"
  value       = google_kms_crypto_key.pii_key.id
}

output "secrets_key_id" {
  description = "The ID of the secrets encryption key"
  value       = google_kms_crypto_key.secrets_key.id
}

output "database_field_encryption_key_id" {
  description = "The ID of the database field encryption key"
  value       = google_kms_crypto_key.database_field_encryption_key.id
}

output "backup_key_id" {
  description = "The ID of the backup encryption key"
  value       = google_kms_crypto_key.backup_key.id
}

output "app_secrets_id" {
  description = "The ID of the application secrets"
  value       = google_secret_manager_secret.app_secrets.id
}
