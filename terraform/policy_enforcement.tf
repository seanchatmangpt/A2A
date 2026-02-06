# OPA Gatekeeper and Policy Enforcement Configuration

# Kubernetes provider for policy resources
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Data source for GKE cluster credentials
data "google_client_config" "default" {}

data "google_container_cluster" "primary" {
  name     = google_container_cluster.primary.name
  location = google_container_cluster.primary.location
  project  = var.project_id
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# Create namespace for Gatekeeper
resource "kubernetes_namespace" "gatekeeper_system" {
  metadata {
    name = "gatekeeper-system"
    labels = {
      "admission.gatekeeper.sh/ignore" = "no-self-managing"
      "app"                            = "gatekeeper"
      "control-plane"                  = "controller-manager"
    }
  }
}

# Deploy OPA Gatekeeper using Helm
resource "helm_release" "gatekeeper" {
  name       = "gatekeeper"
  repository = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart      = "gatekeeper"
  version    = "3.14.0"
  namespace  = kubernetes_namespace.gatekeeper_system.metadata[0].name

  set {
    name  = "replicas"
    value = "3"
  }

  set {
    name  = "auditInterval"
    value = "60"
  }

  set {
    name  = "constraintViolationsLimit"
    value = "20"
  }

  set {
    name  = "auditFromCache"
    value = "true"
  }

  set {
    name  = "validatingWebhookFailurePolicy"
    value = "Fail"
  }

  set {
    name  = "enableExternalData"
    value = "true"
  }

  set {
    name  = "enableGeneratorResourceExpansion"
    value = "true"
  }

  set {
    name  = "mutatingWebhookFailurePolicy"
    value = "Fail"
  }

  depends_on = [
    kubernetes_namespace.gatekeeper_system
  ]
}

# Constraint Template: Required Labels
resource "kubernetes_manifest" "ct_required_labels" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequiredlabels"
      annotations = {
        description = "Requires resources to contain specified labels with values matching provided regular expressions"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequiredLabels"
          }
          validation = {
            openAPIV3Schema = {
              type = "object"
              properties = {
                labels = {
                  type        = "array"
                  description = "A list of labels and values the object must specify"
                  items = {
                    type = "object"
                    properties = {
                      key = {
                        type        = "string"
                        description = "The required label"
                      }
                      allowedRegex = {
                        type        = "string"
                        description = "Regex for allowed values"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8srequiredlabels

            violation[{"msg": msg, "details": {"missing_labels": missing}}] {
              provided := {label | input.review.object.metadata.labels[label]}
              required := {label | label := input.parameters.labels[_].key}
              missing := required - provided
              count(missing) > 0
              msg := sprintf("you must provide labels: %v", [missing])
            }

            violation[{"msg": msg}] {
              value := input.review.object.metadata.labels[key]
              expected := input.parameters.labels[_]
              expected.key == key
              not re_match(expected.allowedRegex, value)
              msg := sprintf("Label <%v: %v> does not satisfy allowed regex: %v", [key, value, expected.allowedRegex])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint Template: Container Resource Limits
resource "kubernetes_manifest" "ct_container_limits" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8scontainerlimits"
      annotations = {
        description = "Requires containers to have resource limits set"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sContainerLimits"
          }
          validation = {
            openAPIV3Schema = {
              type = "object"
              properties = {
                cpu = {
                  type        = "string"
                  description = "Maximum CPU limit"
                }
                memory = {
                  type        = "string"
                  description = "Maximum memory limit"
                }
              }
            }
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8scontainerlimits

            missing_limits(container) {
              not container.resources.limits
            }

            missing_limits(container) {
              not container.resources.limits.cpu
            }

            missing_limits(container) {
              not container.resources.limits.memory
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              missing_limits(container)
              msg := sprintf("Container <%v> must have CPU and memory limits set", [container.name])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.initContainers[_]
              missing_limits(container)
              msg := sprintf("Init container <%v> must have CPU and memory limits set", [container.name])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint Template: Disallow Privileged Containers
resource "kubernetes_manifest" "ct_privileged_containers" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8spsprivilegedcontainer"
      annotations = {
        description = "Disallows privileged containers"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sPSPPrivilegedContainer"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8spsprivilegedcontainer

            violation[{"msg": msg, "details": {}}] {
              c := input_containers[_]
              c.securityContext.privileged
              msg := sprintf("Privileged container is not allowed: %v", [c.name])
            }

            input_containers[c] {
              c := input.review.object.spec.containers[_]
            }

            input_containers[c] {
              c := input.review.object.spec.initContainers[_]
            }

            input_containers[c] {
              c := input.review.object.spec.ephemeralContainers[_]
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint Template: Allowed Repositories
resource "kubernetes_manifest" "ct_allowed_repos" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8sallowedrepos"
      annotations = {
        description = "Restricts container images to an allowed list of repositories"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sAllowedRepos"
          }
          validation = {
            openAPIV3Schema = {
              type = "object"
              properties = {
                repos = {
                  type        = "array"
                  description = "List of allowed container repository prefixes"
                  items = {
                    type = "string"
                  }
                }
              }
            }
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8sallowedrepos

            violation[{"msg": msg}] {
              container := input.review.object.spec.containers[_]
              satisfied := [good | repo = input.parameters.repos[_] ; good = startswith(container.image, repo)]
              not any(satisfied)
              msg := sprintf("container <%v> has an invalid image repo <%v>, allowed repos are %v", [container.name, container.image, input.parameters.repos])
            }

            violation[{"msg": msg}] {
              container := input.review.object.spec.initContainers[_]
              satisfied := [good | repo = input.parameters.repos[_] ; good = startswith(container.image, repo)]
              not any(satisfied)
              msg := sprintf("initContainer <%v> has an invalid image repo <%v>, allowed repos are %v", [container.name, container.image, input.parameters.repos])
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint Template: Block NodePort Services
resource "kubernetes_manifest" "ct_block_nodeport" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8sblocknodeport"
      annotations = {
        description = "Blocks creation of NodePort services"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sBlockNodePort"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8sblocknodeport

            violation[{"msg": msg}] {
              input.review.kind.kind == "Service"
              input.review.object.spec.type == "NodePort"
              msg := "Services of type NodePort are not allowed"
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint Template: Require PodDisruptionBudget
resource "kubernetes_manifest" "ct_require_pdb" {
  manifest = {
    apiVersion = "templates.gatekeeper.sh/v1"
    kind       = "ConstraintTemplate"
    metadata = {
      name = "k8srequirepdb"
      annotations = {
        description = "Requires deployments with replicas > 1 to have a PodDisruptionBudget"
      }
    }
    spec = {
      crd = {
        spec = {
          names = {
            kind = "K8sRequirePDB"
          }
        }
      }
      targets = [
        {
          target = "admission.k8s.gatekeeper.sh"
          rego   = <<-EOT
            package k8srequirepdb

            violation[{"msg": msg}] {
              input.review.kind.kind == "Deployment"
              replicas := input.review.object.spec.replicas
              replicas > 1
              not has_pdb
              msg := sprintf("Deployment %v has %v replicas but no PodDisruptionBudget", [input.review.object.metadata.name, replicas])
            }

            has_pdb {
              pdb := data.inventory.cluster["policy/v1"]["PodDisruptionBudget"][_][_]
              pdb.spec.selector.matchLabels == input.review.object.spec.selector.matchLabels
            }
          EOT
        }
      ]
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Constraint: Enforce Required Labels on Namespaces
resource "kubernetes_manifest" "constraint_namespace_labels" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sRequiredLabels"
    metadata = {
      name = "namespace-must-have-labels"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Namespace"]
          }
        ]
      }
      parameters = {
        labels = [
          {
            key          = "environment"
            allowedRegex = "^(dev|staging|prod)$"
          },
          {
            key          = "team"
            allowedRegex = "^[a-z0-9-]+$"
          }
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_required_labels]
}

# Constraint: Enforce Required Labels on Pods
resource "kubernetes_manifest" "constraint_pod_labels" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sRequiredLabels"
    metadata = {
      name = "pods-must-have-labels"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
        namespaceSelector = {
          matchExpressions = [
            {
              key      = "admission.gatekeeper.sh/ignore"
              operator = "DoesNotExist"
            }
          ]
        }
      }
      parameters = {
        labels = [
          {
            key          = "app"
            allowedRegex = "^[a-z0-9-]+$"
          },
          {
            key          = "version"
            allowedRegex = "^[a-z0-9.-]+$"
          }
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_required_labels]
}

# Constraint: Enforce Container Resource Limits
resource "kubernetes_manifest" "constraint_container_limits" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sContainerLimits"
    metadata = {
      name = "container-must-have-limits"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
        namespaceSelector = {
          matchExpressions = [
            {
              key      = "admission.gatekeeper.sh/ignore"
              operator = "DoesNotExist"
            }
          ]
        }
      }
      parameters = {
        cpu    = "2000m"
        memory = "4Gi"
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_container_limits]
}

# Constraint: Block Privileged Containers
resource "kubernetes_manifest" "constraint_no_privileged" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sPSPPrivilegedContainer"
    metadata = {
      name = "block-privileged-containers"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
        excludedNamespaces = [
          "kube-system",
          "gatekeeper-system"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_privileged_containers]
}

# Constraint: Allowed Container Repositories
resource "kubernetes_manifest" "constraint_allowed_repos" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sAllowedRepos"
    metadata = {
      name = "allowed-container-repos"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Pod"]
          }
        ]
        namespaceSelector = {
          matchExpressions = [
            {
              key      = "admission.gatekeeper.sh/ignore"
              operator = "DoesNotExist"
            }
          ]
        }
      }
      parameters = {
        repos = [
          "gcr.io/${var.project_id}/",
          "us-docker.pkg.dev/${var.project_id}/",
          "docker.io/library/",
          "gcr.io/google-containers/",
          "k8s.gcr.io/",
          "registry.k8s.io/"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_allowed_repos]
}

# Constraint: Block NodePort Services
resource "kubernetes_manifest" "constraint_block_nodeport" {
  manifest = {
    apiVersion = "constraints.gatekeeper.sh/v1beta1"
    kind       = "K8sBlockNodePort"
    metadata = {
      name = "block-nodeport-services"
    }
    spec = {
      match = {
        kinds = [
          {
            apiGroups = [""]
            kinds     = ["Service"]
          }
        ]
        excludedNamespaces = [
          "kube-system"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.ct_block_nodeport]
}

# Create Config Sync for Policy Automation
resource "kubernetes_namespace" "config_management_system" {
  metadata {
    name = "config-management-system"
    labels = {
      "configmanagement.gke.io/system" = "true"
    }
  }
}

# ConfigMap for Policy Bundle
resource "kubernetes_config_map" "policy_bundle" {
  metadata {
    name      = "policy-bundle"
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
  }

  data = {
    "compliance-policies.yaml" = yamlencode({
      policies = {
        pci_dss = {
          enabled     = true
          description = "PCI DSS compliance policies"
          controls = [
            "encryption-at-rest",
            "encryption-in-transit",
            "access-control",
            "audit-logging"
          ]
        }
        soc2 = {
          enabled     = true
          description = "SOC 2 compliance policies"
          controls = [
            "access-management",
            "change-management",
            "incident-response",
            "monitoring-logging"
          ]
        }
        hipaa = {
          enabled     = true
          description = "HIPAA compliance policies"
          controls = [
            "data-encryption",
            "access-audit",
            "data-backup",
            "secure-transmission"
          ]
        }
        cis_benchmark = {
          enabled     = true
          description = "CIS Kubernetes Benchmark"
          controls = [
            "rbac-enabled",
            "pod-security-standards",
            "network-policies",
            "audit-logs"
          ]
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.gatekeeper_system]
}

# Gatekeeper Audit ConfigMap
resource "kubernetes_config_map" "gatekeeper_audit" {
  metadata {
    name      = "gatekeeper-audit-config"
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
  }

  data = {
    "audit-config.yaml" = yamlencode({
      auditInterval          = "60s"
      constraintViolations   = 20
      auditFromCache         = true
      auditChunkSize         = 500
      emitAuditEvents        = true
      emitAdmissionEvents    = true
      logLevel               = "INFO"
      enablePubsub           = false
      metricsBackends        = ["prometheus"]
      exportFormat           = "json"
      violationLogging       = true
      constraintViolationLog = true
    })
  }

  depends_on = [kubernetes_namespace.gatekeeper_system]
}

# Create Service Account for Policy Automation
resource "kubernetes_service_account" "policy_automation" {
  metadata {
    name      = "policy-automation"
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.policy_automation.email
    }
  }
}

# GCP Service Account for Policy Automation
resource "google_service_account" "policy_automation" {
  account_id   = "${var.deployment_name}-policy-auto"
  display_name = "Policy Automation Service Account"
  project      = var.project_id
}

# Workload Identity binding for Policy Automation
resource "google_service_account_iam_member" "policy_automation_workload_identity" {
  service_account_id = google_service_account.policy_automation.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace.gatekeeper_system.metadata[0].name}/${kubernetes_service_account.policy_automation.metadata[0].name}]"
}

# Grant necessary permissions to Policy Automation SA
resource "google_project_iam_member" "policy_automation_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.policy_automation.email}"
}

resource "google_project_iam_member" "policy_automation_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.policy_automation.email}"
}

# ClusterRole for Policy Automation
resource "kubernetes_cluster_role" "policy_automation" {
  metadata {
    name = "policy-automation"
  }

  rule {
    api_groups = ["constraints.gatekeeper.sh"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["templates.gatekeeper.sh"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["status.gatekeeper.sh"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

# ClusterRoleBinding for Policy Automation
resource "kubernetes_cluster_role_binding" "policy_automation" {
  metadata {
    name = "policy-automation"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.policy_automation.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.policy_automation.metadata[0].name
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
  }
}

# CronJob for Policy Compliance Reporting
resource "kubernetes_cron_job_v1" "policy_compliance_report" {
  metadata {
    name      = "policy-compliance-report"
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
    labels = {
      app       = "policy-compliance"
      component = "reporting"
    }
  }

  spec {
    schedule                      = "0 */6 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          app       = "policy-compliance"
          component = "reporting"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app       = "policy-compliance"
              component = "reporting"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.policy_automation.metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "compliance-reporter"
              image = "bitnami/kubectl:latest"

              command = ["/bin/sh", "-c"]
              args = [
                <<-EOT
                  echo "=== Policy Compliance Report ===" &&
                  echo "Generated at: $(date)" &&
                  echo "" &&
                  echo "=== Constraint Status ===" &&
                  kubectl get constraints --all-namespaces -o wide &&
                  echo "" &&
                  echo "=== Audit Results ===" &&
                  kubectl get constraints --all-namespaces -o json | jq '.items[] | select(.status.violations != null) | {name: .metadata.name, violations: .status.totalViolations}' &&
                  echo "" &&
                  echo "=== Gatekeeper Metrics ===" &&
                  kubectl get --raw /metrics | grep gatekeeper || true
                EOT
              ]

              resources {
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
                requests = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.policy_automation,
    helm_release.gatekeeper
  ]
}

# NetworkPolicy for Gatekeeper
resource "kubernetes_network_policy" "gatekeeper" {
  metadata {
    name      = "gatekeeper-webhook"
    namespace = kubernetes_namespace.gatekeeper_system.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "control-plane" = "controller-manager"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {}
      }

      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      to {
        namespace_selector {}
      }

      ports {
        protocol = "TCP"
        port     = "443"
      }

      ports {
        protocol = "TCP"
        port     = "6443"
      }
    }

    egress {
      to {
        namespace_selector {}
      }

      ports {
        protocol = "TCP"
        port     = "53"
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }

  depends_on = [helm_release.gatekeeper]
}

# Outputs for Policy Enforcement
output "gatekeeper_namespace" {
  description = "Namespace where Gatekeeper is deployed"
  value       = kubernetes_namespace.gatekeeper_system.metadata[0].name
}

output "policy_automation_sa_email" {
  description = "Email of the GCP service account for policy automation"
  value       = google_service_account.policy_automation.email
}

output "gatekeeper_webhook_status" {
  description = "Status of Gatekeeper deployment"
  value       = helm_release.gatekeeper.status
}

output "constraint_templates" {
  description = "List of deployed constraint templates"
  value = [
    kubernetes_manifest.ct_required_labels.manifest.metadata.name,
    kubernetes_manifest.ct_container_limits.manifest.metadata.name,
    kubernetes_manifest.ct_privileged_containers.manifest.metadata.name,
    kubernetes_manifest.ct_allowed_repos.manifest.metadata.name,
    kubernetes_manifest.ct_block_nodeport.manifest.metadata.name,
    kubernetes_manifest.ct_require_pdb.manifest.metadata.name
  ]
}

output "active_constraints" {
  description = "List of active policy constraints"
  value = [
    "namespace-must-have-labels",
    "pods-must-have-labels",
    "container-must-have-limits",
    "block-privileged-containers",
    "allowed-container-repos",
    "block-nodeport-services"
  ]
}

output "compliance_frameworks" {
  description = "Supported compliance frameworks"
  value = [
    "PCI DSS",
    "SOC 2",
    "HIPAA",
    "CIS Kubernetes Benchmark"
  ]
}
