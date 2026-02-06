# Security Policies for GCP Marketplace
# Organization Policies, Binary Authorization, Pod Security, Security Scanning

# Organization Policies
# Restrict domain membership
resource "google_organization_policy" "domain_restricted_sharing" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      values = var.allowed_domains
    }
  }
}

# Disable service account key creation
resource "google_organization_policy" "disable_service_account_key_creation" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "iam.disableServiceAccountKeyCreation"

  boolean_policy {
    enforced = true
  }
}

# Require OS Login
resource "google_organization_policy" "require_os_login" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "compute.requireOsLogin"

  boolean_policy {
    enforced = true
  }
}

# Disable VM serial port access
resource "google_organization_policy" "disable_serial_port_access" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "compute.disableSerialPortAccess"

  boolean_policy {
    enforced = true
  }
}

# Require Shielded VMs
resource "google_organization_policy" "require_shielded_vm" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "compute.requireShieldedVm"

  boolean_policy {
    enforced = true
  }
}

# Restrict allowed external IPs
resource "google_organization_policy" "restrict_external_ips" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "compute.vmExternalIpAccess"

  list_policy {
    deny {
      all = true
    }
  }
}

# Disable uniform bucket level access
resource "google_organization_policy" "enforce_uniform_bucket_level_access" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "storage.uniformBucketLevelAccess"

  boolean_policy {
    enforced = true
  }
}

# Restrict public IP access on Cloud SQL
resource "google_organization_policy" "restrict_cloudsql_public_ip" {
  count      = var.organization_id != "" ? 1 : 0
  org_id     = var.organization_id
  constraint = "sql.restrictPublicIp"

  boolean_policy {
    enforced = true
  }
}

# Project-level Organization Policies
resource "google_project_organization_policy" "domain_restricted_sharing" {
  project    = var.project_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      values = var.allowed_domains
    }
  }
}

resource "google_project_organization_policy" "require_os_login" {
  project    = var.project_id
  constraint = "compute.requireOsLogin"

  boolean_policy {
    enforced = true
  }
}

# Binary Authorization Policy
resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.project_id}/*"
  }

  admission_whitelist_patterns {
    name_pattern = "us-docker.pkg.dev/${var.project_id}/*"
  }

  admission_whitelist_patterns {
    name_pattern = "marketplace.gcr.io/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [
      google_binary_authorization_attestor.attestor.name
    ]
  }

  global_policy_evaluation_mode = "ENABLE"
}

# Binary Authorization Attestor
resource "google_binary_authorization_attestor" "attestor" {
  project = var.project_id
  name    = "${var.environment}-attestor"

  attestation_authority_note {
    note_reference = google_container_analysis_note.note.name
  }
}

# Container Analysis Note for Attestation
resource "google_container_analysis_note" "note" {
  project = var.project_id
  name    = "${var.environment}-attestor-note"

  attestation_authority {
    hint {
      human_readable_name = "Attestor for ${var.environment} environment"
    }
  }
}

# Attestor IAM
resource "google_binary_authorization_attestor_iam_member" "attestor_viewer" {
  project  = var.project_id
  attestor = google_binary_authorization_attestor.attestor.name
  role     = "roles/binaryauthorization.attestorsViewer"
  member   = "serviceAccount:${var.project_number}@cloudservices.gserviceaccount.com"
}

# Container Analysis API
resource "google_project_service" "containeranalysis" {
  project            = var.project_id
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}

# Binary Authorization API
resource "google_project_service" "binaryauthorization" {
  project            = var.project_id
  service            = "binaryauthorization.googleapis.com"
  disable_on_destroy = false
}

# Container Scanning API
resource "google_project_service" "containerscanning" {
  project            = var.project_id
  service            = "containerscanning.googleapis.com"
  disable_on_destroy = false
}

# Security Scanner API
resource "google_project_service" "securityscanner" {
  project            = var.project_id
  service            = "websecurityscanner.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry with vulnerability scanning
resource "google_artifact_registry_repository" "secure_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.environment}-secure-images"
  description   = "Secure container images repository with vulnerability scanning"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }
}

# Artifact Registry IAM for scanning
resource "google_artifact_registry_repository_iam_member" "scanner" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.secure_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${var.project_number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

# Security Command Center (if available)
resource "google_project_service" "securitycenter" {
  project            = var.project_id
  service            = "securitycenter.googleapis.com"
  disable_on_destroy = false
}

# Pod Security Policy (Note: Deprecated in K8s 1.25+, use Pod Security Standards)
# This creates a Kubernetes PSP via kubectl after cluster creation
resource "null_resource" "pod_security_policies" {
  depends_on = [var.gke_cluster_name]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${var.gke_cluster_name} --region ${var.region} --project ${var.project_id}

      kubectl apply -f - <<EOF
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'runtime/default'
    apparmor.security.beta.kubernetes.io/allowedProfileNames: 'runtime/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName: 'runtime/default'
    apparmor.security.beta.kubernetes.io/defaultProfileName: 'runtime/default'
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: restricted-psp-user
rules:
- apiGroups:
  - policy
  resources:
  - podsecuritypolicies
  verbs:
  - use
  resourceNames:
  - restricted
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: restricted-psp-all-serviceaccounts
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: restricted-psp-user
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:serviceaccounts
EOF
    EOT
  }
}

# GKE Security Posture and Workload Vulnerability Scanning
resource "google_container_cluster" "security_config" {
  count   = var.enable_gke_security_posture ? 1 : 0
  project = var.project_id
  name    = var.gke_cluster_name
  location = var.region

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  lifecycle {
    ignore_changes = [
      node_pool,
      initial_node_count,
    ]
  }
}

# Network Security Policy for GKE
resource "null_resource" "network_policy" {
  depends_on = [var.gke_cluster_name]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud container clusters get-credentials ${var.gke_cluster_name} --region ${var.region} --project ${var.project_id}

      kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF
    EOT
  }
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "policy" {
  project = var.project_id
  name    = "${var.environment}-security-policy"

  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = var.blocked_ip_ranges
      }
    }
    description = "Deny access from blocked IP ranges"
  }

  rule {
    action   = "rate_based_ban"
    priority = "2000"
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
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limit requests"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# VPC Service Controls (Advanced Security)
resource "google_access_context_manager_service_perimeter" "perimeter" {
  count  = var.enable_vpc_service_controls ? 1 : 0
  parent = "accessPolicies/${var.access_policy_id}"
  name   = "accessPolicies/${var.access_policy_id}/servicePerimeters/${var.environment}_perimeter"
  title  = "${var.environment} Security Perimeter"

  status {
    restricted_services = [
      "storage.googleapis.com",
      "bigquery.googleapis.com",
      "sqladmin.googleapis.com",
    ]

    resources = [
      "projects/${var.project_number}"
    ]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services = [
        "storage.googleapis.com",
        "bigquery.googleapis.com",
      ]
    }
  }
}

# Secret Manager for secure secrets storage
resource "google_secret_manager_secret" "secrets" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.key

  replication {
    automatic = true
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = google_secret_manager_secret.secrets[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.workload_service_account_email}"
}

# Data Loss Prevention (DLP) API
resource "google_project_service" "dlp" {
  project            = var.project_id
  service            = "dlp.googleapis.com"
  disable_on_destroy = false
}

# Audit logging configuration
resource "google_project_iam_audit_config" "project" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Vulnerability scanning configuration for Container Registry
resource "google_container_analysis_occurrence" "vulnerability_scan" {
  count        = var.enable_vulnerability_scanning ? 1 : 0
  project      = var.project_id
  resource_uri = "https://gcr.io/${var.project_id}"
  note_name    = "projects/${var.project_id}/notes/vulnerability-scanning"

  attestation {
    serialized_payload = base64encode(jsonencode({
      critical_vulnerability = false
    }))
  }
}

# Security Health Analytics
resource "google_project_service" "securityposture" {
  project            = var.project_id
  service            = "securityposture.googleapis.com"
  disable_on_destroy = false
}

# Outputs
output "binary_authorization_policy_name" {
  description = "Binary Authorization policy name"
  value       = google_binary_authorization_policy.policy.name
}

output "attestor_name" {
  description = "Binary Authorization attestor name"
  value       = google_binary_authorization_attestor.attestor.name
}

output "secure_repository_url" {
  description = "Secure Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_repo.repository_id}"
}

output "cloud_armor_policy_id" {
  description = "Cloud Armor security policy ID"
  value       = google_compute_security_policy.policy.id
}

output "security_apis_enabled" {
  description = "List of enabled security APIs"
  value = [
    google_project_service.containeranalysis.service,
    google_project_service.binaryauthorization.service,
    google_project_service.containerscanning.service,
    google_project_service.securityscanner.service,
    google_project_service.securitycenter.service,
  ]
}
