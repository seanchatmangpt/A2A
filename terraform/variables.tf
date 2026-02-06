variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "a2a-cluster"
}

variable "node_count" {
  description = "The number of nodes in the cluster"
  type        = number
  default     = 3
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "organization_id" {
  description = "GCP Organization ID for organization policies"
  type        = string
  default     = ""
}

variable "project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "allowed_domains" {
  description = "List of allowed domains for organization policy"
  type        = list(string)
  default     = []
}

variable "gke_cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "a2a-cluster"
}

variable "enable_gke_security_posture" {
  description = "Enable GKE security posture management"
  type        = bool
  default     = true
}

variable "blocked_ip_ranges" {
  description = "List of IP ranges to block in Cloud Armor"
  type        = list(string)
  default     = []
}

variable "enable_vpc_service_controls" {
  description = "Enable VPC Service Controls"
  type        = bool
  default     = false
}

variable "access_policy_id" {
  description = "Access Context Manager policy ID for VPC Service Controls"
  type        = string
  default     = ""
}

variable "secrets" {
  description = "Map of secrets to create in Secret Manager"
  type        = map(string)
  default     = {}
}

variable "workload_service_account_email" {
  description = "Service account email for workload identity"
  type        = string
  default     = ""
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}
