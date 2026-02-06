# A2A Terraform Infrastructure

Terraform configuration for deploying the A2A marketplace application infrastructure on Google Cloud Platform (GCP).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| google | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| google | ~> 5.0 |
| random | n/a |

## Resources

| Name | Type |
|------|------|
| [google_compute_backend_service.backend](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_backend_service) | resource |
| [google_compute_firewall.allow_health_check](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.allow_internal](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.allow_lb](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_global_address.lb_ip](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_global_address.private_ip_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_global_forwarding_rule.http](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_global_forwarding_rule.https](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_health_check.http_health_check](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_managed_ssl_certificate.ssl_cert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate) | resource |
| [google_compute_network.vpc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_region_network_endpoint_group.neg](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group) | resource |
| [google_compute_router.router](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.nat](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |
| [google_compute_ssl_certificate.self_signed](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ssl_certificate) | resource |
| [google_compute_ssl_policy.ssl_policy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ssl_policy) | resource |
| [google_compute_subnetwork.gke_subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_compute_target_http_proxy.http_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_http_proxy) | resource |
| [google_compute_target_https_proxy.https_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_https_proxy) | resource |
| [google_compute_url_map.url_map](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |
| [google_container_cluster.primary](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster) | resource |
| [google_container_node_pool.primary_nodes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_node_pool) | resource |
| [google_project_iam_member.a2a_api_cloudsql](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_api_logging](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_api_monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_api_storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_api_trace](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_app_logging](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_app_monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_app_storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_app_trace](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_worker_logging](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_worker_monitoring](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_worker_pubsub](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_worker_storage](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.a2a_worker_trace](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.deployer_gke_admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.deployer_sa_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_service_account.a2a_api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.a2a_app](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.a2a_worker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.marketplace_deployer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.a2a_api_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.a2a_app_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.a2a_worker_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.deployer_workload_identity](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_networking_connection.private_vpc_connection](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |
| [google_sql_database.database](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |
| [google_sql_database_instance.main](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_database_instance.read_replica](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_sql_user.app_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [google_sql_user.root](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user) | resource |
| [random_password.db_app_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.db_root_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project\_id | The GCP project ID | `string` | n/a | yes |
| cluster\_labels | The GCE resource labels to apply to the cluster | `map(string)` | `{}` | no |
| cluster\_name | The name of the GKE cluster | `string` | `"a2a-cluster"` | no |
| database\_app\_user | The application database user | `string` | `"app_user"` | no |
| database\_authorized\_networks | List of authorized networks for database access | <pre>list(object({<br>    name  = string<br>    value = string<br>  }))</pre> | `[]` | no |
| database\_availability\_type | Availability type for the database (ZONAL or REGIONAL) | `string` | `"REGIONAL"` | no |
| database\_deletion\_protection | Enable deletion protection for the database | `bool` | `true` | no |
| database\_disk\_autoresize\_limit | Maximum disk size for autoresize in GB | `number` | `500` | no |
| database\_disk\_size | Initial disk size in GB | `number` | `100` | no |
| database\_enable\_read\_replica | Enable read replica for the database | `bool` | `false` | no |
| database\_ipv4\_enabled | Whether to enable IPv4 for the database | `bool` | `false` | no |
| database\_max\_connections | Maximum number of database connections | `string` | `"100"` | no |
| database\_name | The name of the database to create | `string` | `"app_db"` | no |
| database\_replica\_region | Region for the read replica | `string` | `"us-east1"` | no |
| database\_tier | The machine type for the database instance | `string` | `"db-custom-2-7680"` | no |
| database\_version | The database version (e.g., POSTGRES\_15, MYSQL\_8\_0) | `string` | `"POSTGRES_15"` | no |
| deployment\_name | The name of the deployment | `string` | `"a2a"` | no |
| disk\_size\_gb | Disk size in GB for GKE nodes | `number` | n/a | yes |
| enable\_private\_endpoint | Whether the master's internal IP address is used as the cluster endpoint | `bool` | `false` | no |
| gke\_version | Minimum GKE master version | `string` | n/a | yes |
| iap\_oauth2\_client\_id | OAuth2 client ID for IAP | `string` | `""` | no |
| iap\_oauth2\_client\_secret | OAuth2 client secret for IAP | `string` | `""` | no |
| k8s\_namespace | The Kubernetes namespace for the application | `string` | `"default"` | no |
| machine\_type | GKE node machine type | `string` | n/a | yes |
| maintenance\_start\_time | Time window specified for daily maintenance operations | `string` | `"03:00"` | no |
| master\_authorized\_networks | List of master authorized networks | <pre>list(object({<br>    cidr_block   = string<br>    display_name = string<br>  }))</pre> | `[]` | no |
| master\_cidr | CIDR block for GKE master | `string` | n/a | yes |
| master\_ipv4\_cidr\_block | The IP range in CIDR notation to use for the hosted master network | `string` | `"172.16.0.0/28"` | no |
| max\_node\_count | Maximum number of nodes in the cluster for autoscaling | `number` | n/a | yes |
| min\_node\_count | Minimum number of nodes in the cluster for autoscaling | `number` | n/a | yes |
| network | The VPC network to host the cluster | `string` | n/a | yes |
| node\_count | The number of nodes in the cluster | `number` | `3` | no |
| pods\_cidr | CIDR block for pods secondary range | `string` | n/a | yes |
| pods\_range\_name | The name of the secondary range for pods | `string` | `"pods"` | no |
| preemptible | Use preemptible nodes | `bool` | n/a | yes |
| region | The GCP region for resources | `string` | `"us-central1"` | no |
| release\_channel | The release channel of this cluster | `string` | `"REGULAR"` | no |
| services\_cidr | CIDR block for services secondary range | `string` | n/a | yes |
| services\_range\_name | The name of the secondary range for services | `string` | `"services"` | no |
| ssl\_certificate | Certificate for self-signed SSL | `string` | `""` | no |
| ssl\_domains | List of domains for managed SSL certificate | `list(string)` | `[]` | no |
| ssl\_private\_key | Private key for self-signed SSL certificate | `string` | `""` | no |
| subnet\_cidr | CIDR block for GKE subnet | `string` | n/a | yes |
| subnetwork | The subnetwork to host the cluster | `string` | n/a | yes |
| use\_managed\_ssl | Use managed SSL certificate | `bool` | `true` | no |
| zone | The GCP zone for resources | `string` | `"us-central1-a"` | no |

## Outputs

| Name | Description |
|------|-------------|
| a2a\_api\_service\_account\_email | Email of the A2A API service account |
| a2a\_app\_service\_account\_email | Email of the A2A application service account |
| a2a\_worker\_service\_account\_email | Email of the A2A worker service account |
| backend\_service\_id | The ID of the backend service |
| cluster\_ca\_certificate | The public certificate authority of the cluster |
| cluster\_endpoint | The IP address of the cluster master |
| cluster\_location | The location of the cluster |
| cluster\_name | The name of the cluster |
| database\_app\_password | The application user password |
| database\_app\_user | The application user name |
| database\_connection\_name | The connection name of the database instance |
| database\_instance\_name | The name of the database instance |
| database\_name | The name of the created database |
| database\_private\_ip | The private IP address of the database instance |
| database\_public\_ip | The public IP address of the database instance |
| database\_replica\_connection\_name | The connection name of the read replica |
| database\_root\_password | The root user password |
| http\_forwarding\_rule\_id | The ID of the HTTP forwarding rule |
| https\_forwarding\_rule\_id | The ID of the HTTPS forwarding rule |
| load\_balancer\_ip | The IP address of the load balancer |
| marketplace\_deployer\_service\_account\_email | Email of the marketplace deployer service account |
| url\_map\_id | The ID of the URL map |
| workload\_identity\_bindings | Workload Identity bindings configured |
| workload\_identity\_pool | The workload identity pool |

## Modules

No modules.

## Usage

```hcl
terraform init
terraform plan
terraform apply
```

### Example terraform.tfvars

```hcl
project_id      = "my-gcp-project"
region          = "us-central1"
zone            = "us-central1-a"
deployment_name = "a2a-production"

# Network Configuration
subnet_cidr   = "10.0.0.0/24"
pods_cidr     = "10.1.0.0/16"
services_cidr = "10.2.0.0/16"
master_cidr   = "172.16.0.0/28"

# GKE Configuration
cluster_name      = "a2a-gke-cluster"
gke_version       = "1.28"
machine_type      = "n1-standard-4"
disk_size_gb      = 100
node_count        = 3
min_node_count    = 3
max_node_count    = 10
preemptible       = false
release_channel   = "REGULAR"

# Database Configuration
database_version           = "POSTGRES_15"
database_tier              = "db-custom-2-7680"
database_availability_type = "REGIONAL"
database_disk_size         = 100
database_name              = "a2a_production"
database_app_user          = "a2a_app"

# Load Balancer Configuration
ssl_domains       = ["example.com", "www.example.com"]
use_managed_ssl   = true

# Kubernetes Configuration
k8s_namespace = "a2a-production"
```

## Architecture

This Terraform configuration deploys a complete GCP infrastructure for the A2A marketplace application including:

### Networking
- VPC with custom subnets
- Cloud Router and Cloud NAT for egress traffic
- Firewall rules for internal communication and load balancer access

### Compute (GKE)
- GKE cluster with Workload Identity enabled
- Separate node pool with autoscaling
- Private cluster configuration with authorized networks

### Database (Cloud SQL)
- Cloud SQL PostgreSQL instance with high availability
- Private IP connectivity via VPC peering
- Automated backups and point-in-time recovery
- Optional read replica support

### Load Balancing
- Global HTTP(S) Load Balancer
- Managed SSL certificates
- Health checks and backend services
- Cloud CDN configuration
- Identity-Aware Proxy (IAP) support

### IAM & Security
- Service accounts for application components (app, API, worker)
- Workload Identity bindings for Kubernetes service accounts
- Least-privilege IAM role assignments
- Marketplace deployer service account

## Notes

- The infrastructure uses private networking where possible for enhanced security
- Workload Identity is configured for secure access from GKE to GCP services
- Database passwords are randomly generated and marked as sensitive outputs
- SSL certificates can be either managed by Google or self-signed
- All resources are tagged with deployment name for easy identification
