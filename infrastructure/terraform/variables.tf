# Terraform Variables for Craftplan MCP + A2A + elrmcp Infrastructure

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "staging"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production"
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "m6g.large"
}

variable "node_group_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 3
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 5
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus, Grafana, etc.)"
  type        = bool
  default     = true
}

variable "enable_ingress" {
  description = "Enable ingress controller"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable cluster autoscaling"
  type        = bool
  default     = true
}

variable "craftplan_replicas" {
  description = "Number of Craftplan replicas"
  type        = number
  default     = 2
}

variable "mcp_server_replicas" {
  description = "Number of MCP server replicas"
  type        = number
  default     = 2
}

variable "a2a_agent_replicas" {
  description = "Number of A2A agent replicas"
  type        = number
  default     = 2
}

variable "elrmcp_replicas" {
  description = "Number of elrmcp replicas"
  type        = number
  default     = 2
}

variable "enable_database" {
  description = "Enable managed database (RDS/PostgreSQL)"
  type        = bool
  default     = true
}

variable "database_instance_class" {
  description = "Database instance class"
  type        = string
  default     = "db.t3.large"
}

variable "database_allocated_storage" {
  description = "Database allocated storage in GB"
  type        = number
  default     = 20
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "craftplan"
}

variable "database_username" {
  description = "Database username"
  type        = string
  default     = "craftplan_user"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "craftplan_password"
}

variable "enable_redis" {
  description = "Enable Redis cache"
  type        = bool
  default     = true
}

variable "redis_instance_type" {
  description = "Redis instance type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_node_count" {
  description = "Redis node count"
  type        = number
  default     = 1
}

variable "enable_minio" {
  description = "Enable MinIO object storage"
  type        = bool
  default     = true
}

variable "minio_storage_size" {
  description = "MinIO storage size in GB"
  type        = number
  default     = 50
}

variable "enable_logging" {
  description = "Enable logging stack (Loki, Promtail)"
  type        = bool
  default     = true
}

variable "enable_alerting" {
  description = "Enable alerting stack"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "timezone" {
  description = "Timezone for scheduling and alerts"
  type        = string
  default     = "UTC"
}

variable "enable_vpn_access" {
  description = "Enable VPN access to the cluster"
  type        = bool
  default     = false
}

variable "vpn_cidr" {
  description = "VPN CIDR for access"
  type        = string
  default     = "10.10.0.0/24"
}

variable "cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "spot_instances_enabled" {
  description = "Enable spot instances for node groups"
  type        = bool
  default     = true
}

variable "spot_instance_types" {
  description = "Spot instance types to use"
  type        = list(string)
  default     = ["m6g.large", "m6g.xlarge", "m5.large", "m5.xlarge"]
}

variable "enable_backup" {
  description = "Enable backup and disaster recovery"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Backup window in UTC"
  type        = string
  default     = "03:00-04:00"
}