# VPC Service Controls Access Policy
resource "google_access_context_manager_access_policy" "access_policy" {
  parent = "organizations/${var.organization_id}"
  title  = "a2a-access-policy"
}

# VPC Service Controls - Service Perimeter
resource "google_access_context_manager_service_perimeter" "service_perimeter" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/servicePerimeters/a2a_perimeter"
  title  = "A2A Service Perimeter"

  status {
    restricted_services = [
      "storage.googleapis.com",
      "bigquery.googleapis.com",
      "sqladmin.googleapis.com",
      "container.googleapis.com",
      "compute.googleapis.com",
      "aiplatform.googleapis.com",
      "secretmanager.googleapis.com",
    ]

    resources = [
      "projects/${var.project_id}",
    ]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services = [
        "storage.googleapis.com",
        "bigquery.googleapis.com",
        "sqladmin.googleapis.com",
        "container.googleapis.com",
        "compute.googleapis.com",
        "aiplatform.googleapis.com",
        "secretmanager.googleapis.com",
      ]
    }

    ingress_policies {
      ingress_from {
        sources {
          resource = "projects/${var.project_id}"
        }
        identity_type = "ANY_IDENTITY"
      }
      ingress_to {
        resources = ["*"]
        operations {
          service_name = "storage.googleapis.com"
          method_selectors {
            method = "*"
          }
        }
        operations {
          service_name = "bigquery.googleapis.com"
          method_selectors {
            method = "*"
          }
        }
      }
    }

    egress_policies {
      egress_from {
        identity_type = "ANY_USER_ACCOUNT"
      }
      egress_to {
        resources = ["*"]
        operations {
          service_name = "storage.googleapis.com"
          method_selectors {
            method = "*"
          }
        }
      }
    }
  }

  perimeter_type = "PERIMETER_TYPE_REGULAR"
}

# Private Service Connect - Service Attachment
resource "google_compute_service_attachment" "psc_service_attachment" {
  name        = "a2a-psc-service-attachment"
  region      = var.region
  description = "Private Service Connect service attachment for A2A"

  enable_proxy_protocol = false
  connection_preference = "ACCEPT_AUTOMATIC"
  nat_subnets           = [google_compute_subnetwork.psc_subnet.id]
  target_service        = google_compute_forwarding_rule.psc_ilb.id

  consumer_reject_lists = []

  domain_names = ["a2a.psc.example.com"]
}

# Private Service Connect - Subnet for NAT
resource "google_compute_subnetwork" "psc_subnet" {
  name          = "a2a-psc-subnet"
  ip_cidr_range = "10.2.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# Private Service Connect - Internal Load Balancer
resource "google_compute_forwarding_rule" "psc_ilb" {
  name                  = "a2a-psc-ilb"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.psc_backend.id
  all_ports             = true
  network               = google_compute_network.vpc.id
  subnetwork            = google_compute_subnetwork.psc_subnet.id
  allow_global_access   = true
}

# Private Service Connect - Backend Service
resource "google_compute_region_backend_service" "psc_backend" {
  name                  = "a2a-psc-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_health_check.psc_health_check.id]

  backend {
    group           = google_container_cluster.primary.node_pool[0].instance_group_urls[0]
    balancing_mode  = "CONNECTION"
    capacity_scaler = 1.0
  }
}

# Health Check for Private Service Connect
resource "google_compute_health_check" "psc_health_check" {
  name               = "a2a-psc-health-check"
  check_interval_sec = 10
  timeout_sec        = 5

  tcp_health_check {
    port = 80
  }
}

# Cloud Armor Security Policy with DDoS Protection
resource "google_compute_security_policy" "cloud_armor_policy" {
  name        = "a2a-security-policy"
  description = "Cloud Armor security policy with DDoS protection for A2A"

  # DDoS Protection - Adaptive Protection
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }

  # Default rule - allow traffic
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule - allow all"
  }

  # Block known malicious IPs
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = [
          "192.0.2.0/24",   # Example malicious IP range
          "198.51.100.0/24" # Example malicious IP range
        ]
      }
    }
    description = "Block known malicious IP ranges"
  }

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = 2000
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
    description = "Rate limit: 1000 requests per minute per IP"
  }

  # SQL Injection protection
  rule {
    action   = "deny(403)"
    priority = 3000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection attempts"
  }

  # XSS protection
  rule {
    action   = "deny(403)"
    priority = 3100
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block XSS attempts"
  }

  # Local File Inclusion protection
  rule {
    action   = "deny(403)"
    priority = 3200
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
    description = "Block local file inclusion attempts"
  }

  # Remote Code Execution protection
  rule {
    action   = "deny(403)"
    priority = 3300
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }
    description = "Block remote code execution attempts"
  }

  # Remote File Inclusion protection
  rule {
    action   = "deny(403)"
    priority = 3400
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-stable')"
      }
    }
    description = "Block remote file inclusion attempts"
  }

  # Method enforcement
  rule {
    action   = "deny(403)"
    priority = 3500
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('methodenforcement-stable')"
      }
    }
    description = "Block method enforcement violations"
  }

  # Scanner detection
  rule {
    action   = "deny(403)"
    priority = 3600
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('scannerdetection-stable')"
      }
    }
    description = "Block scanner detection"
  }

  # Protocol attack protection
  rule {
    action   = "deny(403)"
    priority = 3700
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('protocolattack-stable')"
      }
    }
    description = "Block protocol attacks"
  }

  # PHP injection protection
  rule {
    action   = "deny(403)"
    priority = 3800
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('php-stable')"
      }
    }
    description = "Block PHP injection attempts"
  }

  # Session fixation protection
  rule {
    action   = "deny(403)"
    priority = 3900
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sessionfixation-stable')"
      }
    }
    description = "Block session fixation attempts"
  }

  # Geographic restriction - Example: Allow only specific regions
  rule {
    action   = "deny(403)"
    priority = 4000
    match {
      expr {
        expression = "origin.region_code in ['CN', 'KP', 'RU']"
      }
    }
    description = "Block traffic from restricted regions"
  }

  # Bot management - Block known bad bots
  rule {
    action   = "deny(403)"
    priority = 5000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('cve-canary')"
      }
    }
    description = "Block CVE exploitation attempts"
  }
}

# Attach Cloud Armor policy to backend service
resource "google_compute_backend_service_security_policy_attachment" "backend_security_policy" {
  backend_service = google_compute_backend_service.default.id
  security_policy = google_compute_security_policy.cloud_armor_policy.id
}

# Cloud Armor Edge Security Policy (for DDoS at edge)
resource "google_compute_security_policy" "edge_security_policy" {
  name        = "a2a-edge-security-policy"
  description = "Edge security policy for additional DDoS protection"
  type        = "CLOUD_ARMOR_EDGE"

  # Default rule
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default edge rule"
  }

  # Edge rate limiting
  rule {
    action   = "rate_based_ban"
    priority = 1000
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
        count        = 2000
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Edge rate limiting: 2000 req/min per IP"
  }
}

# Firewall Rules for DDoS Protection
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "a2a-deny-all-ingress"
  network = google_compute_network.vpc.name

  deny {
    protocol = "all"
  }

  direction   = "INGRESS"
  priority    = 65534
  source_ranges = ["0.0.0.0/0"]

  description = "Default deny all ingress traffic"
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "a2a-allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  direction   = "INGRESS"
  priority    = 1000
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  target_tags = ["http-server", "https-server"]

  description = "Allow health check probes from Google Cloud Load Balancers"
}

resource "google_compute_firewall" "allow_iap" {
  name    = "a2a-allow-iap"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }

  direction   = "INGRESS"
  priority    = 1000
  source_ranges = ["35.235.240.0/20"]

  description = "Allow IAP for secure SSH/RDP access"
}

resource "google_compute_firewall" "allow_lb_traffic" {
  name    = "a2a-allow-lb-traffic"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["load-balancer"]

  description = "Allow traffic from internet to load balancer"
}

# VPC Flow Logs for security monitoring
resource "google_compute_subnetwork" "monitored_subnet" {
  name          = "a2a-monitored-subnet"
  ip_cidr_range = "10.3.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  private_ip_google_access = true
}

# Cloud Armor Custom Rule for Advanced DDoS Protection
resource "google_compute_security_policy" "advanced_ddos_policy" {
  name        = "a2a-advanced-ddos-policy"
  description = "Advanced DDoS protection with custom rules"

  # Adaptive Protection with Auto-Deploy
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "PREMIUM"
    }
  }

  # Advanced rate limiting based on HTTP headers
  rule {
    action   = "rate_based_ban"
    priority = 100
    match {
      expr {
        expression = "true"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "HTTP_HEADER"
      enforce_on_key_name = "X-Forwarded-For"
      rate_limit_threshold {
        count        = 500
        interval_sec = 60
      }
      ban_duration_sec = 900
    }
    description = "Advanced rate limiting based on X-Forwarded-For header"
  }

  # Throttle based on user agent
  rule {
    action   = "throttle"
    priority = 200
    match {
      expr {
        expression = "request.headers['user-agent'].matches('.*bot.*')"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "ALL"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
    description = "Throttle bot traffic"
  }

  # Default allow rule
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}

# Private Google Access for VPC
resource "google_compute_global_address" "private_ip_address" {
  name          = "a2a-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# DNS Policy for Private Google Access
resource "google_dns_policy" "private_google_access" {
  name                      = "a2a-private-google-access"
  enable_inbound_forwarding = true
  enable_logging            = true

  networks {
    network_url = google_compute_network.vpc.id
  }
}

# Router for NAT (with DDoS protection via Cloud NAT)
resource "google_compute_router" "router" {
  name    = "a2a-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# Cloud NAT for secure outbound traffic
resource "google_compute_router_nat" "nat" {
  name                               = "a2a-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  min_ports_per_vm                    = 64
  max_ports_per_vm                    = 65536
  enable_endpoint_independent_mapping = true
  enable_dynamic_port_allocation      = true
}

# SSL Policy for HTTPS Load Balancer
resource "google_compute_ssl_policy" "ssl_policy" {
  name            = "a2a-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# Outputs
output "cloud_armor_policy_id" {
  description = "Cloud Armor security policy ID"
  value       = google_compute_security_policy.cloud_armor_policy.id
}

output "edge_security_policy_id" {
  description = "Edge security policy ID"
  value       = google_compute_security_policy.edge_security_policy.id
}

output "service_perimeter_name" {
  description = "VPC Service Controls perimeter name"
  value       = google_access_context_manager_service_perimeter.service_perimeter.name
}

output "psc_service_attachment_id" {
  description = "Private Service Connect service attachment ID"
  value       = google_compute_service_attachment.psc_service_attachment.id
}

output "advanced_ddos_policy_id" {
  description = "Advanced DDoS protection policy ID"
  value       = google_compute_security_policy.advanced_ddos_policy.id
}
