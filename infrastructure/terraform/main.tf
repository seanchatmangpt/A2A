# Terraform Configuration for Craftplan MCP + A2A + elrmcp Infrastructure
# Supports AWS, GCP, and Azure providers

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.50.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.18.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
      command     = "aws"
    }
  }
}

# Generate random suffix for resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Module: Kubernetes Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.0.0"

  cluster_name    = "craftplan-${var.environment}-${random_string.suffix.result}"
  cluster_version = "1.28"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  control_plane_subnet_ids       = module.vpc.public_subnets
  cluster_endpoint_public_access = true

  tags = {
    Environment = var.environment
    Project     = "craftplan-mcp-a2a"
  }

  # EKS Managed Node Groups (v20.0.0 uses eks_managed_node_groups instead of node_groups)
  eks_managed_node_groups = {
    main = {
      name         = "craftplan-node-group"
      min_size     = 1
      max_size     = var.node_group_max_size
      desired_size = var.node_group_size

      instance_types = [var.instance_type]
      capacity_type  = "ON_DEMAND"

      subnet_ids = module.vpc.private_subnets

      tags = {
        Environment = var.environment
        Project     = "craftplan-mcp-a2a"
        NodeGroup   = "craftplan-main"
      }

      labels = {
        environment = var.environment
        project     = "craftplan-mcp-a2a"
        node-type   = "craftplan"
      }

      taints = {
        dedicated = {
          key    = "craftplan"
          value  = "main"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Cluster Security Group
  cluster_security_group_tags = {
    Environment = var.environment
    Project     = "craftplan-mcp-a2a"
  }

  node_security_group_tags = {
    Environment = var.environment
    Project     = "craftplan-mcp-a2a"
  }
}

# Module: VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.4.0"

  name = "craftplan-${var.environment}-${random_string.suffix.result}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = var.environment
    Project     = "craftplan-mcp-a2a"
  }
}

# Module: EKS Add-ons
# Note: kubernetes-addons submodule is not available in eks module v20.0.0
# Consider using helm or kubernetes provider resources directly for add-ons
# module "eks_addons" {
#   source  = "terraform-aws-modules/eks/aws//modules/kubernetes-addons"
#   version = "20.0.0"
#
#   cluster_name     = module.eks.cluster_name
#   cluster_version  = module.eks.cluster_version
#   cluster_endpoint = module.eks.cluster_endpoint
#   cluster_token    = data.aws_eks_cluster_auth.this.token
#
#   # VPC CNI
#   vpc_cni = {
#     most_recent = true
#     before      = null
#     after       = null
#     version     = "v1.12.0-eksbuild.1"
#   }
#
#   # Metrics Server
#   metrics_server = {
#     most_recent = true
#     before      = null
#     after       = null
#     version     = "v0.6.2"
#   }
#
#   # Cluster Autoscaler
#   cluster_autoscaler = {
#     most_recent = true
#     before      = null
#     after       = null
#     version     = "v1.23.0"
#     values      = [file("${path.module}/configs/cluster-autoscaler.yaml")]
#   }
#
#   # AWS Load Balancer Controller
#   aws_load_balancer_controller = {
#     most_recent = true
#     before      = null
#     after       = null
#     version     = "v1.4.7"
#     values      = [file("${path.module}/configs/aws-load-balancer-controller.yaml")]
#   }
# }

# Kubernetes Namespace
resource "kubernetes_namespace" "craftplan" {
  metadata {
    name = "craftplan"

    labels = {
      environment = var.environment
      project     = "craftplan-mcp-a2a"
    }

    annotations = {
      "name" = "craftplan"
    }
  }
}

# Kubernetes Service Account
resource "kubernetes_service_account" "craftplan" {
  metadata {
    name      = "craftplan-service-account"
    namespace = kubernetes_namespace.craftplan.metadata[0].name

    # annotations = {
    #   "eks.amazonaws.com/role-arn" = module.iam_oidc_provider.iam_role_arn
    # }
  }
}

# IAM OIDC Provider
# Note: iam-openid-connect-provider submodule not available in iam module v5.5.0
# Consider creating OIDC provider resources directly
# module "iam_oidc_provider" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-openid-connect-provider"
#   version = "5.5.0"
#
#   create_iam_role             = true
#   create_iam_role_policy      = true
#   iam_role_policy_name_prefix = "craftplan"
#   iam_role_policy_description = "Craftplan EKS IAM Policy"
#   iam_role_name               = "craftplan-${var.environment}-${random_string.suffix.result}"
#   iam_role_path               = "/"
#   iam_role_tags = {
#     Environment = var.environment
#     Project     = "craftplan-mcp-a2a"
#   }
#
#   url             = module.eks.cluster_oidc_issuer_url
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.eks.root_certificates]
# }

# Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
}

output "node_group_name" {
  description = "EKS node group name"
  value       = try(module.eks.eks_managed_node_groups["main"].node_group_id, "")
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "kubernetes_namespace" {
  description = "Kubernetes namespace for Craftplan"
  value       = kubernetes_namespace.craftplan.metadata[0].name
}

output "service_account" {
  description = "Kubernetes service account for Craftplan"
  value       = kubernetes_service_account.craftplan.metadata[0].name
}

# Data sources
# Note: These are only needed for the commented-out modules above
# data "aws_eks_cluster_auth" "this" {
#   name = module.eks.cluster_name
# }

# data "tls_certificate" "eks" {
#   url = module.eks.cluster_oidc_issuer_url
# }