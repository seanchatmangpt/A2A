# Terraform Outputs for GCP Marketplace - GKE Cluster

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
  sensitive   = false
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = false
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_client_certificate" {
  description = "GKE cluster client certificate"
  value       = google_container_cluster.primary.master_auth[0].client_certificate
  sensitive   = true
}

output "cluster_client_key" {
  description = "GKE cluster client key"
  value       = google_container_cluster.primary.master_auth[0].client_key
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes config for connecting to the cluster"
  value = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name           = google_container_cluster.primary.name
    cluster_endpoint       = google_container_cluster.primary.endpoint
    cluster_ca_certificate = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
    project_id             = var.gcp_project
    region                 = var.gcp_region
  })
  sensitive = true
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig for kubectl access"
  value = {
    host                   = google_container_cluster.primary.endpoint
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
  sensitive = true
}

output "gke_cluster_location" {
  description = "GKE cluster location (region or zone)"
  value       = google_container_cluster.primary.location
  sensitive   = false
}

output "gke_cluster_version" {
  description = "GKE cluster master version"
  value       = google_container_cluster.primary.master_version
  sensitive   = false
}

output "node_pool_name" {
  description = "Primary node pool name"
  value       = google_container_node_pool.primary_nodes.name
  sensitive   = false
}

output "node_pool_version" {
  description = "Primary node pool version"
  value       = google_container_node_pool.primary_nodes.version
  sensitive   = false
}

output "node_pool_instance_group_urls" {
  description = "Node pool instance group URLs"
  value       = google_container_node_pool.primary_nodes.instance_group_urls
  sensitive   = false
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
  sensitive   = false
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
  sensitive   = false
}

output "subnet_cidr" {
  description = "Subnet CIDR range"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
  sensitive   = false
}

output "pods_ip_range" {
  description = "IP range for pods"
  value       = google_compute_subnetwork.subnet.secondary_ip_range[0].ip_cidr_range
  sensitive   = false
}

output "services_ip_range" {
  description = "IP range for services"
  value       = google_compute_subnetwork.subnet.secondary_ip_range[1].ip_cidr_range
  sensitive   = false
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project
  sensitive   = false
}

output "region" {
  description = "GCP region"
  value       = var.gcp_region
  sensitive   = false
}

output "zone" {
  description = "GCP zone"
  value       = var.gcp_zone
  sensitive   = false
}

output "service_account_email" {
  description = "Service account email for GKE nodes"
  value       = google_service_account.gke_service_account.email
  sensitive   = false
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace for application"
  value       = kubernetes_namespace.craftplan.metadata[0].name
  sensitive   = false
}

output "service_account_name" {
  description = "Kubernetes service account name"
  value       = kubernetes_service_account.craftplan.metadata[0].name
  sensitive   = false
}

output "workload_identity_service_account" {
  description = "GCP service account for Workload Identity"
  value       = google_service_account.workload_identity.email
  sensitive   = false
}

output "cluster_ipv4_cidr" {
  description = "IPv4 CIDR block for the cluster"
  value       = google_container_cluster.primary.cluster_ipv4_cidr
  sensitive   = false
}

output "services_ipv4_cidr" {
  description = "IPv4 CIDR block for services"
  value       = google_container_cluster.primary.services_ipv4_cidr
  sensitive   = false
}

output "master_authorized_networks" {
  description = "Master authorized networks configuration"
  value       = google_container_cluster.primary.master_authorized_networks_config
  sensitive   = false
}

output "cluster_secondary_range_name" {
  description = "Secondary range name for cluster pods"
  value       = google_container_cluster.primary.ip_allocation_policy[0].cluster_secondary_range_name
  sensitive   = false
}

output "services_secondary_range_name" {
  description = "Secondary range name for services"
  value       = google_container_cluster.primary.ip_allocation_policy[0].services_secondary_range_name
  sensitive   = false
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.gcp_region} --project ${var.gcp_project}"
  sensitive   = false
}

output "console_url" {
  description = "GCP Console URL for the cluster"
  value       = "https://console.cloud.google.com/kubernetes/clusters/details/${var.gcp_region}/${google_container_cluster.primary.name}?project=${var.gcp_project}"
  sensitive   = false
}

output "ingress_gateway_ip" {
  description = "Ingress gateway external IP address"
  value       = try(google_compute_address.ingress_ip.address, null)
  sensitive   = false
}

output "load_balancer_ip" {
  description = "Load balancer IP for external access"
  value       = try(google_compute_global_address.lb_ip.address, null)
  sensitive   = false
}
