# Cloud SQL Instance
resource "google_sql_database_instance" "main" {
  name             = "${var.deployment_name}-db"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  settings {
    tier              = var.database_tier
    availability_type = var.database_availability_type
    disk_type         = "PD_SSD"
    disk_size         = var.database_disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.database_disk_autoresize_limit

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = var.database_ipv4_enabled
      private_network = google_compute_network.vpc.id
      require_ssl     = true

      dynamic "authorized_networks" {
        for_each = var.database_authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    database_flags {
      name  = "max_connections"
      value = var.database_max_connections
    }

    user_labels = {
      deployment = var.deployment_name
      managed_by = "terraform"
    }
  }

  deletion_protection = var.database_deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Private VPC Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.deployment_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Database
resource "google_sql_database" "database" {
  name     = var.database_name
  instance = google_sql_database_instance.main.name
  project  = var.project_id
}

# Root/Admin User Password
resource "random_password" "db_root_password" {
  length  = 32
  special = true
}

# Application User Password
resource "random_password" "db_app_password" {
  length  = 32
  special = true
}

# Root User
resource "google_sql_user" "root" {
  name     = "root"
  instance = google_sql_database_instance.main.name
  password = random_password.db_root_password.result
  project  = var.project_id
}

# Application User
resource "google_sql_user" "app_user" {
  name     = var.database_app_user
  instance = google_sql_database_instance.main.name
  password = random_password.db_app_password.result
  project  = var.project_id
}

# Read Replica (Optional)
resource "google_sql_database_instance" "read_replica" {
  count                = var.database_enable_read_replica ? 1 : 0
  name                 = "${var.deployment_name}-db-replica"
  master_instance_name = google_sql_database_instance.main.name
  region               = var.database_replica_region
  database_version     = var.database_version
  project              = var.project_id

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = var.database_ipv4_enabled
      private_network = google_compute_network.vpc.id
      require_ssl     = true
    }

    user_labels = {
      deployment = var.deployment_name
      managed_by = "terraform"
      role       = "read-replica"
    }
  }
}

# Variables
variable "database_version" {
  description = "The database version (e.g., POSTGRES_15, MYSQL_8_0)"
  type        = string
  default     = "POSTGRES_15"
}

variable "database_tier" {
  description = "The machine type for the database instance"
  type        = string
  default     = "db-custom-2-7680"
}

variable "database_availability_type" {
  description = "Availability type for the database (ZONAL or REGIONAL)"
  type        = string
  default     = "REGIONAL"
}

variable "database_disk_size" {
  description = "Initial disk size in GB"
  type        = number
  default     = 100
}

variable "database_disk_autoresize_limit" {
  description = "Maximum disk size for autoresize in GB"
  type        = number
  default     = 500
}

variable "database_ipv4_enabled" {
  description = "Whether to enable IPv4 for the database"
  type        = bool
  default     = false
}

variable "database_authorized_networks" {
  description = "List of authorized networks for database access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "database_max_connections" {
  description = "Maximum number of database connections"
  type        = string
  default     = "100"
}

variable "database_deletion_protection" {
  description = "Enable deletion protection for the database"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "The name of the database to create"
  type        = string
  default     = "app_db"
}

variable "database_app_user" {
  description = "The application database user"
  type        = string
  default     = "app_user"
}

variable "database_enable_read_replica" {
  description = "Enable read replica for the database"
  type        = bool
  default     = false
}

variable "database_replica_region" {
  description = "Region for the read replica"
  type        = string
  default     = "us-east1"
}

variable "deployment_name" {
  description = "The name of the deployment"
  type        = string
  default     = "a2a"
}

# Outputs
output "database_instance_name" {
  description = "The name of the database instance"
  value       = google_sql_database_instance.main.name
}

output "database_connection_name" {
  description = "The connection name of the database instance"
  value       = google_sql_database_instance.main.connection_name
}

output "database_private_ip" {
  description = "The private IP address of the database instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_public_ip" {
  description = "The public IP address of the database instance"
  value       = google_sql_database_instance.main.public_ip_address
}

output "database_name" {
  description = "The name of the created database"
  value       = google_sql_database.database.name
}

output "database_root_password" {
  description = "The root user password"
  value       = random_password.db_root_password.result
  sensitive   = true
}

output "database_app_user" {
  description = "The application user name"
  value       = google_sql_user.app_user.name
}

output "database_app_password" {
  description = "The application user password"
  value       = random_password.db_app_password.result
  sensitive   = true
}

output "database_replica_connection_name" {
  description = "The connection name of the read replica"
  value       = var.database_enable_read_replica ? google_sql_database_instance.read_replica[0].connection_name : null
}
