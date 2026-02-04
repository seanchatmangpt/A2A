# Terraform Outputs for Craftplan MCP + A2A + elrmcp Infrastructure

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
  sensitive   = false
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = false
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "node_group_name" {
  description = "EKS node group name"
  value       = module.eks.node_groups["main"].name
  sensitive   = false
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
  sensitive   = false
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
  sensitive   = false
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
  sensitive   = false
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace for Craftplan"
  value       = kubernetes_namespace.craftplan.metadata[0].name
  sensitive   = false
}

output "service_account" {
  description = "Kubernetes service account for Craftplan"
  value       = kubernetes_service_account.craftplan.metadata[0].name
  sensitive   = false
}

output "load_balancer_arn" {
  description = "Application Load Balancer ARN"
  value       = module.eks.kubelet[0].load_balancer_arn
  sensitive   = false
}

output "load_balancer_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.eks.kubelet[0].load_balancer_dns_name
  sensitive   = false
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = module.rds.cluster_endpoint
  sensitive   = true
}

output "database_port" {
  description = "Database port"
  value       = module.rds.cluster_port
  sensitive   = false
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.redis.primary_endpoint_address
  sensitive   = true
}

output "redis_port" {
  description = "Redis port"
  value       = module.redis.port
  sensitive   = false
}

output "minio_endpoint" {
  description = "MinIO endpoint"
  value       = module.minio.endpoint
  sensitive   = false
}

output "minio_console_endpoint" {
  description = "MinIO console endpoint"
  value       = module.minio.console_endpoint
  sensitive   = false
}

output "prometheus_endpoint" {
  description = "Prometheus endpoint"
  value       = "http://grafana.${module.eks.kubelet[0].load_balancer_dns_name}/prometheus"
  sensitive   = false
}

output "grafana_endpoint" {
  description = "Grafana endpoint"
  value       = "http://grafana.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "alertmanager_endpoint" {
  description = "Alertmanager endpoint"
  value       = "http://alertmanager.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "loki_endpoint" {
  description = "Loki endpoint"
  value       = "http://loki.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "craftplan_ingress_url" {
  description = "Craftplan ingress URL"
  value       = "http://craftplan.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "mcp_server_ingress_url" {
  description = "MCP server ingress URL"
  value       = "http://mcp.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "a2a_agent_ingress_url" {
  description = "A2A agent ingress URL"
  value       = "http://a2a.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "elrmcp_ingress_url" {
  description = "elrmcp ingress URL"
  value       = "http://elrmcp.${module.eks.kubelet[0].load_balancer_dns_name}"
  sensitive   = false
}

output "kubernetes_config" {
  description = "Kubernetes configuration file content"
  value       = local.kubeconfig
  sensitive   = true
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
  sensitive   = false
}

output "environment" {
  description = "Environment name"
  value       = var.environment
  sensitive   = false
}

output "total_nodes" {
  description = "Total number of nodes in the cluster"
  value       = module.eks.node_groups["main"].scale_desired
  sensitive   = false
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
  sensitive   = false
}

output "node_instance_types" {
  description = "Node instance types"
  value       = module.eks.node_groups["main"].instance_types
  sensitive   = false
}

output "cluster_status" {
  description = "EKS cluster status"
  value       = module.eks.cluster_status
  sensitive   = false
}

output "cluster_platform_version" {
  description = "EKS cluster platform version"
  value       = module.eks.cluster_platform_version
  sensitive   = false
}

output "cluster_update_version" {
  description = "EKS cluster update version"
  value       = module.eks.cluster_update_version
  sensitive   = false
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
  sensitive   = false
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
  sensitive   = false
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
  sensitive   = false
}

output "availability_zones" {
  description = "Availability zones"
  value       = module.vpc.azs
  sensitive   = false
}

output "nat_gateway_public_ips" {
  description = "NAT gateway public IPs"
  value       = module.vpc.nat_public_ips
  sensitive   = false
}