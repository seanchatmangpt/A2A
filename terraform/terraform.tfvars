# Mock Terraform Variables for Testing
project_id     = "mock-project-123456"
project_number = "123456789012"
region         = "us-central1"
zone           = "us-central1-a"
environment    = "test"

# Cluster configuration
cluster_name     = "a2a-test-cluster"
gke_cluster_name = "a2a-test-cluster"
node_count       = 3

# Network configuration (from main.tf)
deployment_name = "a2a-test"
subnet_cidr     = "10.0.0.0/24"
pods_cidr       = "10.1.0.0/16"
services_cidr   = "10.2.0.0/16"
master_cidr     = "172.16.0.0/28"

# Node configuration
machine_type    = "n1-standard-4"
min_node_count  = 1
max_node_count  = 5
disk_size_gb    = 100
preemptible     = false

# GKE version
gke_version     = "1.28"
release_channel = "REGULAR"

# Security
enable_gke_security_posture    = true
enable_vulnerability_scanning  = true
enable_vpc_service_controls    = false

# Optional
organization_id                = ""
access_policy_id               = ""
workload_service_account_email = ""
allowed_domains                = []
blocked_ip_ranges              = []
secrets                        = {}
