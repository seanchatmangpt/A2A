# Multi-Region Infrastructure for Fortune 5 Enterprise
# Global Load Balancing, Multi-Region GKE, Cross-Region Failover

# Regional Variables
locals {
  regions = {
    primary = {
      name = "us-central1"
      zones = ["us-central1-a", "us-central1-b", "us-central1-c"]
      cidr = "10.0.0.0/16"
      pods_cidr = "10.100.0.0/16"
      services_cidr = "10.200.0.0/16"
      master_cidr = "172.16.0.0/28"
    }
    secondary = {
      name = "us-east1"
      zones = ["us-east1-b", "us-east1-c", "us-east1-d"]
      cidr = "10.1.0.0/16"
      pods_cidr = "10.101.0.0/16"
      services_cidr = "10.201.0.0/16"
      master_cidr = "172.16.1.0/28"
    }
    tertiary = {
      name = "us-west1"
      zones = ["us-west1-a", "us-west1-b", "us-west1-c"]
      cidr = "10.2.0.0/16"
      pods_cidr = "10.102.0.0/16"
      services_cidr = "10.202.0.0/16"
      master_cidr = "172.16.2.0/28"
    }
    europe = {
      name = "europe-west1"
      zones = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
      cidr = "10.3.0.0/16"
      pods_cidr = "10.103.0.0/16"
      services_cidr = "10.203.0.0/16"
      master_cidr = "172.16.3.0/28"
    }
    asia = {
      name = "asia-east1"
      zones = ["asia-east1-a", "asia-east1-b", "asia-east1-c"]
      cidr = "10.4.0.0/16"
      pods_cidr = "10.104.0.0/16"
      services_cidr = "10.204.0.0/16"
      master_cidr = "172.16.4.0/28"
    }
  }
}

# Global VPC Network with GLOBAL routing for cross-region communication
resource "google_compute_network" "global_vpc" {
  name                            = "a2a-global-vpc"
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  delete_default_routes_on_create = false
}

# Regional Subnets
resource "google_compute_subnetwork" "regional_subnets" {
  for_each = local.regions

  name          = "a2a-subnet-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = each.value.name
  network       = google_compute_network.global_vpc.id

  secondary_ip_range {
    range_name    = "pods-${each.key}"
    ip_cidr_range = each.value.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services-${each.key}"
    ip_cidr_range = each.value.services_cidr
  }

  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Routers for each region
resource "google_compute_router" "regional_routers" {
  for_each = local.regions

  name    = "a2a-router-${each.key}"
  region  = each.value.name
  network = google_compute_network.global_vpc.id

  bgp {
    asn = 64512
  }
}

# Cloud NAT for each region
resource "google_compute_router_nat" "regional_nat" {
  for_each = local.regions

  name                               = "a2a-nat-${each.key}"
  router                             = google_compute_router.regional_routers[each.key].name
  region                             = each.value.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Multi-Region GKE Clusters
resource "google_container_cluster" "regional_clusters" {
  for_each = local.regions

  name     = "a2a-gke-${each.key}"
  location = each.value.name

  network    = google_compute_network.global_vpc.id
  subnetwork = google_compute_subnetwork.regional_subnets[each.key].id

  min_master_version       = "1.29"
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-${each.key}"
    services_secondary_range_name = "services-${each.key}"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = each.value.master_cidr
  }

  # Master authorized networks - restrict to corporate networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gcp_filestore_csi_driver_config {
      enabled = true
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  # Enable Dataplane V2 for advanced networking
  datapath_provider = "ADVANCED_DATAPATH"

  # Security posture
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Enable cost allocation tracking
  resource_labels = {
    environment = "production"
    region      = each.key
    tier        = "fortune5"
    managed_by  = "terraform"
  }
}

# Regional Node Pools with autoscaling
resource "google_container_node_pool" "regional_node_pools" {
  for_each = local.regions

  name     = "a2a-nodepool-${each.key}"
  location = each.value.name
  cluster  = google_container_cluster.regional_clusters[each.key].name

  initial_node_count = 3

  autoscaling {
    min_node_count  = 3
    max_node_count  = 50
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
    strategy        = "SURGE"
  }

  node_config {
    preemptible  = false
    machine_type = "n2-standard-8"
    disk_size_gb = 100
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      environment = "production"
      region      = each.key
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    gcfs_config {
      enabled = true
    }

    tags = ["gke-node", "a2a-gke-${each.key}"]
  }
}

# Global Static IP for Load Balancer
resource "google_compute_global_address" "global_lb_ip" {
  name         = "a2a-global-lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# Global SSL Certificate (Managed)
resource "google_compute_managed_ssl_certificate" "global_cert" {
  name = "a2a-global-cert"

  managed {
    domains = ["api.a2a.example.com", "*.a2a.example.com"]
  }
}

# Self-signed SSL Certificate (fallback)
resource "google_compute_ssl_certificate" "self_signed" {
  name_prefix = "a2a-self-signed-"
  private_key = file("${path.module}/certs/private.key")
  certificate = file("${path.module}/certs/certificate.crt")

  lifecycle {
    create_before_destroy = true
  }
}

# Health Check for Backend Services
resource "google_compute_health_check" "http_health_check" {
  name                = "a2a-http-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port               = 80
    request_path       = "/health"
    proxy_header       = "NONE"
    response           = ""
    port_specification = "USE_FIXED_PORT"
  }

  log_config {
    enable = true
  }
}

# Health Check for HTTPS Backend Services
resource "google_compute_health_check" "https_health_check" {
  name                = "a2a-https-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  https_health_check {
    port               = 443
    request_path       = "/health"
    proxy_header       = "NONE"
    port_specification = "USE_FIXED_PORT"
  }

  log_config {
    enable = true
  }
}

# Backend Service with Multi-Region Backends
resource "google_compute_backend_service" "global_backend" {
  name                            = "a2a-global-backend"
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = 30
  health_checks                   = [google_compute_health_check.http_health_check.id]
  connection_draining_timeout_sec = 300
  load_balancing_scheme           = "EXTERNAL_MANAGED"

  # Enable Cloud CDN
  enable_cdn = true

  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 3600
    max_ttl                      = 86400
    client_ttl                   = 7200
    negative_caching             = true
    serve_while_stale            = 86400
    signed_url_cache_max_age_sec = 7200

    cache_key_policy {
      include_host           = true
      include_protocol       = true
      include_query_string   = true
      query_string_whitelist = ["user", "session"]
    }
  }

  # Outlier detection for automatic failover
  outlier_detection {
    consecutive_errors                    = 5
    consecutive_gateway_failure           = 3
    enforcing_consecutive_errors          = 100
    enforcing_consecutive_gateway_failure = 100
    enforcing_success_rate                = 100
    interval {
      seconds = 10
    }
    base_ejection_time {
      seconds = 30
    }
    max_ejection_percent       = 50
    success_rate_minimum_hosts = 5
    success_rate_request_volume = 100
    success_rate_stdev_factor  = 1900
  }

  # Circuit breaker for reliability
  circuit_breakers {
    max_requests_per_connection = 1000
    max_connections             = 10000
    max_pending_requests        = 1000
    max_requests                = 10000
    max_retries                 = 3
  }

  # Session affinity
  session_affinity = "CLIENT_IP"
  affinity_cookie_ttl_sec = 3600

  # Logging
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # IAP (Identity-Aware Proxy) for enterprise security
  iap {
    oauth2_client_id     = ""
    oauth2_client_secret = ""
  }
}

# Network Endpoint Groups for each region
resource "google_compute_region_network_endpoint_group" "regional_negs" {
  for_each = local.regions

  name                  = "a2a-neg-${each.key}"
  network_endpoint_type = "GCE_VM_IP_PORT"
  region                = each.value.name
  network               = google_compute_network.global_vpc.id
  subnetwork            = google_compute_subnetwork.regional_subnets[each.key].id
}

# URL Map for routing
resource "google_compute_url_map" "global_url_map" {
  name            = "a2a-global-url-map"
  default_service = google_compute_backend_service.global_backend.id

  host_rule {
    hosts        = ["api.a2a.example.com"]
    path_matcher = "api-paths"
  }

  path_matcher {
    name            = "api-paths"
    default_service = google_compute_backend_service.global_backend.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.global_backend.id
    }

    path_rule {
      paths   = ["/health"]
      service = google_compute_backend_service.global_backend.id
    }
  }
}

# HTTP to HTTPS Redirect
resource "google_compute_url_map" "https_redirect" {
  name = "a2a-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Target HTTP Proxy (for redirect)
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "a2a-http-proxy"
  url_map = google_compute_url_map.https_redirect.id
}

# Target HTTPS Proxy
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "a2a-https-proxy"
  url_map          = google_compute_url_map.global_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.global_cert.id]
  ssl_policy       = google_compute_ssl_policy.enterprise_ssl_policy.id
}

# SSL Policy for Enterprise Security
resource "google_compute_ssl_policy" "enterprise_ssl_policy" {
  name            = "a2a-enterprise-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# Global Forwarding Rule (HTTPS)
resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name                  = "a2a-https-forwarding-rule"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_address            = google_compute_global_address.global_lb_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Global Forwarding Rule (HTTP)
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name                  = "a2a-http-forwarding-rule"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.global_lb_ip.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "enterprise_security_policy" {
  name        = "a2a-enterprise-security-policy"
  description = "Enterprise security policy with DDoS protection and WAF"

  # Default rule - allow all
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule"
  }

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 1000
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limiting rule"
  }

  # Block SQL injection
  rule {
    action   = "deny(403)"
    priority = "2000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection attacks"
  }

  # Block XSS attacks
  rule {
    action   = "deny(403)"
    priority = "3000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block XSS attacks"
  }

  # Block LFI attacks
  rule {
    action   = "deny(403)"
    priority = "4000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
    description = "Block Local File Inclusion attacks"
  }

  # Block RCE attacks
  rule {
    action   = "deny(403)"
    priority = "5000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }
    description = "Block Remote Code Execution attacks"
  }

  # Geo-blocking example (block specific countries if needed)
  rule {
    action   = "deny(403)"
    priority = "6000"
    match {
      expr {
        expression = "origin.region_code == 'CN' || origin.region_code == 'RU'"
      }
    }
    description = "Geo-blocking for high-risk regions"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# Attach Cloud Armor to Backend Service
resource "google_compute_backend_service_security_policy_attachment" "armor_attachment" {
  backend_service   = google_compute_backend_service.global_backend.id
  security_policy   = google_compute_security_policy.enterprise_security_policy.id
}

# Cloud DNS for global traffic management
resource "google_dns_managed_zone" "global_dns_zone" {
  name        = "a2a-global-dns-zone"
  dns_name    = "a2a.example.com."
  description = "Global DNS zone for A2A"
  visibility  = "public"

  dnssec_config {
    state = "on"
  }
}

# DNS A record pointing to global load balancer
resource "google_dns_record_set" "global_lb_record" {
  managed_zone = google_dns_managed_zone.global_dns_zone.name
  name         = "api.${google_dns_managed_zone.global_dns_zone.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.global_lb_ip.address]
}

# Multi-Region Cloud SQL Instance (Primary)
resource "google_sql_database_instance" "primary_sql" {
  name             = "a2a-sql-primary"
  database_version = "POSTGRES_15"
  region           = local.regions.primary.name

  settings {
    tier              = "db-custom-8-32768"
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_size         = 500
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.global_vpc.id
      require_ssl     = true
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
    }

    database_flags {
      name  = "max_connections"
      value = "1000"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }
  }

  deletion_protection = true
}

# Cloud SQL Replica in secondary region
resource "google_sql_database_instance" "replica_sql_secondary" {
  name                 = "a2a-sql-replica-secondary"
  database_version     = "POSTGRES_15"
  region               = local.regions.secondary.name
  master_instance_name = google_sql_database_instance.primary_sql.name

  replica_configuration {
    failover_target = true
  }

  settings {
    tier              = "db-custom-8-32768"
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.global_vpc.id
      require_ssl     = true
    }
  }

  deletion_protection = true
}

# Cloud SQL Replica in Europe
resource "google_sql_database_instance" "replica_sql_europe" {
  name                 = "a2a-sql-replica-europe"
  database_version     = "POSTGRES_15"
  region               = local.regions.europe.name
  master_instance_name = google_sql_database_instance.primary_sql.name

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = "db-custom-8-32768"
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.global_vpc.id
      require_ssl     = true
    }
  }

  deletion_protection = true
}

# Multi-Region Cloud Storage Bucket
resource "google_storage_bucket" "multi_region_bucket" {
  name          = "a2a-multi-region-bucket"
  location      = "US"
  storage_class = "MULTI_REGIONAL"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = ""
  }

  logging {
    log_bucket = "a2a-logs-bucket"
  }
}

# Firewall Rules
resource "google_compute_firewall" "allow_internal_multi_region" {
  name    = "a2a-allow-internal-multi-region"
  network = google_compute_network.global_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    for region in local.regions : region.cidr
  ]

  target_tags = ["gke-node"]
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "a2a-allow-health-checks"
  network = google_compute_network.global_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["gke-node"]
}

# Firewall rule for load balancer
resource "google_compute_firewall" "allow_lb" {
  name    = "a2a-allow-lb"
  network = google_compute_network.global_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
}

# Global VPC Peering for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.global_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = []
}

# Outputs
output "global_load_balancer_ip" {
  description = "Global Load Balancer IP address"
  value       = google_compute_global_address.global_lb_ip.address
}

output "regional_cluster_endpoints" {
  description = "GKE cluster endpoints by region"
  value = {
    for region, cluster in google_container_cluster.regional_clusters :
    region => cluster.endpoint
  }
  sensitive = true
}

output "regional_cluster_names" {
  description = "GKE cluster names by region"
  value = {
    for region, cluster in google_container_cluster.regional_clusters :
    region => cluster.name
  }
}

output "primary_sql_instance" {
  description = "Primary Cloud SQL instance name"
  value       = google_sql_database_instance.primary_sql.name
}

output "sql_replica_instances" {
  description = "Cloud SQL replica instance names"
  value = {
    secondary = google_sql_database_instance.replica_sql_secondary.name
    europe    = google_sql_database_instance.replica_sql_europe.name
  }
}

output "dns_nameservers" {
  description = "DNS nameservers for the global DNS zone"
  value       = google_dns_managed_zone.global_dns_zone.name_servers
}

output "multi_region_bucket" {
  description = "Multi-region storage bucket name"
  value       = google_storage_bucket.multi_region_bucket.name
}
