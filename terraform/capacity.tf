# Enterprise-Scale Capacity Management for GKE

# General Purpose Node Pool for standard workloads
resource "google_container_node_pool" "general_purpose" {
  name       = "${var.deployment_name}-general-purpose-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.general_node_count

  autoscaling {
    min_node_count       = var.general_min_node_count
    max_node_count       = var.general_max_node_count
    location_policy      = "BALANCED"
    total_min_node_count = var.general_total_min_node_count
    total_max_node_count = var.general_total_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.general_machine_type
    disk_size_gb = var.general_disk_size_gb
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool-type  = "general-purpose"
      workload   = "standard"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-gke", "general-purpose"]

    taint {
      key    = "workload-type"
      value  = "general"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}

# Compute-Optimized Node Pool for CPU-intensive workloads
resource "google_container_node_pool" "compute_optimized" {
  name       = "${var.deployment_name}-compute-optimized-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.compute_node_count

  autoscaling {
    min_node_count       = var.compute_min_node_count
    max_node_count       = var.compute_max_node_count
    location_policy      = "BALANCED"
    total_min_node_count = var.compute_total_min_node_count
    total_max_node_count = var.compute_total_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.compute_machine_type
    disk_size_gb = var.compute_disk_size_gb
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool-type  = "compute-optimized"
      workload   = "cpu-intensive"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-gke", "compute-optimized"]

    taint {
      key    = "workload-type"
      value  = "compute"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}

# Memory-Optimized Node Pool for memory-intensive workloads
resource "google_container_node_pool" "memory_optimized" {
  name       = "${var.deployment_name}-memory-optimized-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.memory_node_count

  autoscaling {
    min_node_count       = var.memory_min_node_count
    max_node_count       = var.memory_max_node_count
    location_policy      = "BALANCED"
    total_min_node_count = var.memory_total_min_node_count
    total_max_node_count = var.memory_total_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.memory_machine_type
    disk_size_gb = var.memory_disk_size_gb
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool-type  = "memory-optimized"
      workload   = "memory-intensive"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-gke", "memory-optimized"]

    taint {
      key    = "workload-type"
      value  = "memory"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}

# Spot/Preemptible Node Pool for fault-tolerant batch workloads
resource "google_container_node_pool" "spot" {
  name       = "${var.deployment_name}-spot-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.spot_node_count

  autoscaling {
    min_node_count       = var.spot_min_node_count
    max_node_count       = var.spot_max_node_count
    location_policy      = "ANY"
    total_min_node_count = var.spot_total_min_node_count
    total_max_node_count = var.spot_total_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    spot         = true
    machine_type = var.spot_machine_type
    disk_size_gb = var.spot_disk_size_gb
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool-type  = "spot"
      workload   = "batch"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-gke", "spot"]

    taint {
      key    = "workload-type"
      value  = "spot"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 1
    strategy        = "SURGE"
  }
}

# GPU Node Pool for ML/AI workloads
resource "google_container_node_pool" "gpu" {
  count      = var.enable_gpu_pool ? 1 : 0
  name       = "${var.deployment_name}-gpu-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.gpu_node_count

  autoscaling {
    min_node_count       = var.gpu_min_node_count
    max_node_count       = var.gpu_max_node_count
    location_policy      = "BALANCED"
    total_min_node_count = var.gpu_total_min_node_count
    total_max_node_count = var.gpu_total_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type
    disk_size_gb = var.gpu_disk_size_gb
    disk_type    = "pd-ssd"

    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count_per_node
      gpu_driver_installation_config {
        gpu_driver_version = "DEFAULT"
      }
      gpu_sharing_config {
        gpu_sharing_strategy       = var.gpu_sharing_strategy
        max_shared_clients_per_gpu = var.gpu_max_shared_clients
      }
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      deployment = var.deployment_name
      pool-type  = "gpu"
      workload   = "ml-ai"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", "${var.deployment_name}-gke", "gpu"]

    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }
}

# Cluster Autoscaler Configuration
resource "google_container_cluster" "autoscaler_config" {
  name     = google_container_cluster.primary.name
  location = var.region

  cluster_autoscaling {
    enabled             = var.enable_cluster_autoscaling
    autoscaling_profile = var.autoscaling_profile

    resource_limits {
      resource_type = "cpu"
      minimum       = var.cluster_cpu_min
      maximum       = var.cluster_cpu_max
    }

    resource_limits {
      resource_type = "memory"
      minimum       = var.cluster_memory_min
      maximum       = var.cluster_memory_max
    }

    auto_provisioning_defaults {
      service_account = var.node_service_account
      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]

      management {
        auto_repair  = true
        auto_upgrade = true
      }

      shielded_instance_config {
        enable_secure_boot          = true
        enable_integrity_monitoring = true
      }

      disk_size = var.auto_provisioning_disk_size
      disk_type = var.auto_provisioning_disk_type

      upgrade_settings {
        max_surge       = 1
        max_unavailable = 0
        strategy        = "SURGE"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      network,
      subnetwork,
      initial_node_count,
      remove_default_node_pool
    ]
  }
}

# Vertical Pod Autoscaler Configuration
resource "google_container_cluster" "vpa_config" {
  name     = google_container_cluster.primary.name
  location = var.region

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  lifecycle {
    ignore_changes = [
      network,
      subnetwork,
      initial_node_count,
      remove_default_node_pool,
      cluster_autoscaling
    ]
  }
}

# Variables for Capacity Management

# General Purpose Node Pool Variables
variable "general_node_count" {
  description = "Initial node count for general purpose pool"
  type        = number
  default     = 3
}

variable "general_min_node_count" {
  description = "Minimum nodes per zone for general purpose pool"
  type        = number
  default     = 1
}

variable "general_max_node_count" {
  description = "Maximum nodes per zone for general purpose pool"
  type        = number
  default     = 10
}

variable "general_total_min_node_count" {
  description = "Total minimum nodes across all zones for general purpose pool"
  type        = number
  default     = 3
}

variable "general_total_max_node_count" {
  description = "Total maximum nodes across all zones for general purpose pool"
  type        = number
  default     = 30
}

variable "general_machine_type" {
  description = "Machine type for general purpose nodes"
  type        = string
  default     = "n2-standard-4"
}

variable "general_disk_size_gb" {
  description = "Disk size for general purpose nodes"
  type        = number
  default     = 100
}

# Compute-Optimized Node Pool Variables
variable "compute_node_count" {
  description = "Initial node count for compute-optimized pool"
  type        = number
  default     = 2
}

variable "compute_min_node_count" {
  description = "Minimum nodes per zone for compute-optimized pool"
  type        = number
  default     = 0
}

variable "compute_max_node_count" {
  description = "Maximum nodes per zone for compute-optimized pool"
  type        = number
  default     = 20
}

variable "compute_total_min_node_count" {
  description = "Total minimum nodes across all zones for compute-optimized pool"
  type        = number
  default     = 0
}

variable "compute_total_max_node_count" {
  description = "Total maximum nodes across all zones for compute-optimized pool"
  type        = number
  default     = 60
}

variable "compute_machine_type" {
  description = "Machine type for compute-optimized nodes"
  type        = string
  default     = "c2-standard-8"
}

variable "compute_disk_size_gb" {
  description = "Disk size for compute-optimized nodes"
  type        = number
  default     = 100
}

# Memory-Optimized Node Pool Variables
variable "memory_node_count" {
  description = "Initial node count for memory-optimized pool"
  type        = number
  default     = 2
}

variable "memory_min_node_count" {
  description = "Minimum nodes per zone for memory-optimized pool"
  type        = number
  default     = 0
}

variable "memory_max_node_count" {
  description = "Maximum nodes per zone for memory-optimized pool"
  type        = number
  default     = 15
}

variable "memory_total_min_node_count" {
  description = "Total minimum nodes across all zones for memory-optimized pool"
  type        = number
  default     = 0
}

variable "memory_total_max_node_count" {
  description = "Total maximum nodes across all zones for memory-optimized pool"
  type        = number
  default     = 45
}

variable "memory_machine_type" {
  description = "Machine type for memory-optimized nodes"
  type        = string
  default     = "n2-highmem-8"
}

variable "memory_disk_size_gb" {
  description = "Disk size for memory-optimized nodes"
  type        = number
  default     = 100
}

# Spot Node Pool Variables
variable "spot_node_count" {
  description = "Initial node count for spot pool"
  type        = number
  default     = 0
}

variable "spot_min_node_count" {
  description = "Minimum nodes per zone for spot pool"
  type        = number
  default     = 0
}

variable "spot_max_node_count" {
  description = "Maximum nodes per zone for spot pool"
  type        = number
  default     = 50
}

variable "spot_total_min_node_count" {
  description = "Total minimum nodes across all zones for spot pool"
  type        = number
  default     = 0
}

variable "spot_total_max_node_count" {
  description = "Total maximum nodes across all zones for spot pool"
  type        = number
  default     = 150
}

variable "spot_machine_type" {
  description = "Machine type for spot nodes"
  type        = string
  default     = "n2-standard-4"
}

variable "spot_disk_size_gb" {
  description = "Disk size for spot nodes"
  type        = number
  default     = 50
}

# GPU Node Pool Variables
variable "enable_gpu_pool" {
  description = "Enable GPU node pool"
  type        = bool
  default     = false
}

variable "gpu_node_count" {
  description = "Initial node count for GPU pool"
  type        = number
  default     = 0
}

variable "gpu_min_node_count" {
  description = "Minimum nodes per zone for GPU pool"
  type        = number
  default     = 0
}

variable "gpu_max_node_count" {
  description = "Maximum nodes per zone for GPU pool"
  type        = number
  default     = 10
}

variable "gpu_total_min_node_count" {
  description = "Total minimum nodes across all zones for GPU pool"
  type        = number
  default     = 0
}

variable "gpu_total_max_node_count" {
  description = "Total maximum nodes across all zones for GPU pool"
  type        = number
  default     = 30
}

variable "gpu_machine_type" {
  description = "Machine type for GPU nodes"
  type        = string
  default     = "n1-standard-8"
}

variable "gpu_disk_size_gb" {
  description = "Disk size for GPU nodes"
  type        = number
  default     = 200
}

variable "gpu_type" {
  description = "Type of GPU to attach"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count_per_node" {
  description = "Number of GPUs per node"
  type        = number
  default     = 1
}

variable "gpu_sharing_strategy" {
  description = "GPU sharing strategy (TIME_SHARING or MPS)"
  type        = string
  default     = "TIME_SHARING"
}

variable "gpu_max_shared_clients" {
  description = "Maximum number of containers sharing a GPU"
  type        = number
  default     = 2
}

# Cluster Autoscaling Variables
variable "enable_cluster_autoscaling" {
  description = "Enable cluster-level autoscaling"
  type        = bool
  default     = true
}

variable "autoscaling_profile" {
  description = "Autoscaling profile (BALANCED or OPTIMIZE_UTILIZATION)"
  type        = string
  default     = "BALANCED"
}

variable "cluster_cpu_min" {
  description = "Minimum CPU cores for the cluster"
  type        = number
  default     = 16
}

variable "cluster_cpu_max" {
  description = "Maximum CPU cores for the cluster"
  type        = number
  default     = 1000
}

variable "cluster_memory_min" {
  description = "Minimum memory (GB) for the cluster"
  type        = number
  default     = 64
}

variable "cluster_memory_max" {
  description = "Maximum memory (GB) for the cluster"
  type        = number
  default     = 4000
}

variable "node_service_account" {
  description = "Service account for auto-provisioned nodes"
  type        = string
  default     = ""
}

variable "auto_provisioning_disk_size" {
  description = "Disk size for auto-provisioned nodes"
  type        = number
  default     = 100
}

variable "auto_provisioning_disk_type" {
  description = "Disk type for auto-provisioned nodes"
  type        = string
  default     = "pd-ssd"
}

# Vertical Pod Autoscaling Variables
variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling"
  type        = bool
  default     = true
}

# Deployment name variable (should already exist but including for completeness)
variable "deployment_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "a2a"
}

# Outputs for Capacity Management

output "general_purpose_pool_name" {
  description = "Name of the general purpose node pool"
  value       = google_container_node_pool.general_purpose.name
}

output "compute_optimized_pool_name" {
  description = "Name of the compute-optimized node pool"
  value       = google_container_node_pool.compute_optimized.name
}

output "memory_optimized_pool_name" {
  description = "Name of the memory-optimized node pool"
  value       = google_container_node_pool.memory_optimized.name
}

output "spot_pool_name" {
  description = "Name of the spot node pool"
  value       = google_container_node_pool.spot.name
}

output "gpu_pool_name" {
  description = "Name of the GPU node pool"
  value       = var.enable_gpu_pool ? google_container_node_pool.gpu[0].name : null
}

output "cluster_autoscaling_enabled" {
  description = "Whether cluster autoscaling is enabled"
  value       = var.enable_cluster_autoscaling
}

output "vertical_pod_autoscaling_enabled" {
  description = "Whether vertical pod autoscaling is enabled"
  value       = var.enable_vertical_pod_autoscaling
}

output "total_max_nodes" {
  description = "Total maximum nodes across all pools"
  value = var.general_total_max_node_count + var.compute_total_max_node_count + var.memory_total_max_node_count + var.spot_total_max_node_count + (var.enable_gpu_pool ? var.gpu_total_max_node_count : 0)
}

output "autoscaling_profile" {
  description = "The autoscaling profile used"
  value       = var.autoscaling_profile
}
