# Global IP Address
resource "google_compute_global_address" "lb_ip" {
  name         = "${var.deployment_name}-lb-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# Health Check
resource "google_compute_health_check" "http_health_check" {
  name                = "${var.deployment_name}-http-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    request_path       = "/health"
    proxy_header       = "NONE"
  }

  log_config {
    enable = true
  }
}

# Backend Service
resource "google_compute_backend_service" "backend" {
  name                            = "${var.deployment_name}-backend-service"
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = 30
  connection_draining_timeout_sec = 300
  session_affinity                = "CLIENT_IP"
  affinity_cookie_ttl_sec         = 3600

  health_checks = [google_compute_health_check.http_health_check.id]

  backend {
    balancing_mode               = "RATE"
    max_rate_per_instance        = 100
    capacity_scaler              = 1.0
    group                        = google_compute_region_network_endpoint_group.neg.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  iap {
    oauth2_client_id     = var.iap_oauth2_client_id
    oauth2_client_secret = var.iap_oauth2_client_secret
  }

  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    default_ttl                  = 3600
    client_ttl                   = 7200
    max_ttl                      = 86400
    negative_caching             = true
    serve_while_stale            = 86400

    cache_key_policy {
      include_host           = true
      include_protocol       = true
      include_query_string   = false
    }
  }
}

# Network Endpoint Group (NEG) for GKE
resource "google_compute_region_network_endpoint_group" "neg" {
  name                  = "${var.deployment_name}-neg"
  network_endpoint_type = "GCE_VM_IP_PORT"
  region                = var.region
  network               = google_compute_network.vpc.id
  subnetwork            = google_compute_subnetwork.gke_subnet.id
}

# URL Map
resource "google_compute_url_map" "url_map" {
  name            = "${var.deployment_name}-url-map"
  default_service = google_compute_backend_service.backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.backend.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.backend.id
    }

    path_rule {
      paths   = ["/static/*"]
      service = google_compute_backend_service.backend.id
    }
  }
}

# Managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = "${var.deployment_name}-ssl-cert"

  managed {
    domains = var.ssl_domains
  }
}

# Self-signed SSL Certificate (fallback)
resource "google_compute_ssl_certificate" "self_signed" {
  name_prefix = "${var.deployment_name}-self-signed-"
  private_key = var.ssl_private_key
  certificate = var.ssl_certificate

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Target Proxy
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "${var.deployment_name}-https-proxy"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = var.use_managed_ssl ? [google_compute_managed_ssl_certificate.ssl_cert.id] : [google_compute_ssl_certificate.self_signed.id]

  ssl_policy = google_compute_ssl_policy.ssl_policy.id
}

# HTTP Target Proxy (for redirect)
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.deployment_name}-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

# SSL Policy
resource "google_compute_ssl_policy" "ssl_policy" {
  name            = "${var.deployment_name}-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# Global Forwarding Rule (HTTPS)
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.deployment_name}-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}

# Global Forwarding Rule (HTTP)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.deployment_name}-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.deployment_name}-allow-health-check"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-node", "${var.deployment_name}-gke"]
}

# Firewall rule for load balancer
resource "google_compute_firewall" "allow_lb" {
  name    = "${var.deployment_name}-allow-lb"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node", "${var.deployment_name}-gke"]
}

# Variables
variable "deployment_name" {
  description = "The name of the deployment"
  type        = string
  default     = "a2a"
}

variable "iap_oauth2_client_id" {
  description = "OAuth2 client ID for IAP"
  type        = string
  default     = ""
}

variable "iap_oauth2_client_secret" {
  description = "OAuth2 client secret for IAP"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_domains" {
  description = "List of domains for managed SSL certificate"
  type        = list(string)
  default     = []
}

variable "use_managed_ssl" {
  description = "Use managed SSL certificate"
  type        = bool
  default     = true
}

variable "ssl_private_key" {
  description = "Private key for self-signed SSL certificate"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_certificate" {
  description = "Certificate for self-signed SSL"
  type        = string
  default     = ""
}

# Outputs
output "load_balancer_ip" {
  description = "The IP address of the load balancer"
  value       = google_compute_global_address.lb_ip.address
}

output "backend_service_id" {
  description = "The ID of the backend service"
  value       = google_compute_backend_service.backend.id
}

output "url_map_id" {
  description = "The ID of the URL map"
  value       = google_compute_url_map.url_map.id
}

output "https_forwarding_rule_id" {
  description = "The ID of the HTTPS forwarding rule"
  value       = google_compute_global_forwarding_rule.https.id
}

output "http_forwarding_rule_id" {
  description = "The ID of the HTTP forwarding rule"
  value       = google_compute_global_forwarding_rule.http.id
}
