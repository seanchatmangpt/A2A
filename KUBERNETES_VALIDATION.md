# Kubernetes Manifest Validation

This repository includes automated validation scripts for Kubernetes YAML manifests using kubeconform.

## Quick Start

```bash
# Run validation (shows all results including CRDs)
./validate-k8s-manifests-detailed.sh

# Run validation (skip Custom Resource Definitions)
./validate-k8s-manifests-detailed.sh --skip-crds
```

## Available Scripts

### 1. validate-k8s-manifests.sh
Basic validation script that validates all Kubernetes manifests.

**Features:**
- Automatically installs kubeconform if not present
- Validates all standard Kubernetes resources
- Reports CRD schema errors
- Color-coded output

### 2. validate-k8s-manifests-detailed.sh
Enhanced validation script with better CRD handling.

**Features:**
- All features from the basic script
- Distinguishes between real errors and CRD schema issues
- Optional `--skip-crds` flag to ignore Custom Resources
- Detailed summary report
- Lists all failed files and CRD files separately

## Validation Results

### Last Run: Sat Feb 7 05:39:31 UTC 2026

**Summary:**
- Total manifests: 97
- ✓ Passed: 16 standard Kubernetes manifests
- ⚠ CRDs: 10 custom resource definitions
- ⊘ Skipped: 71 Helm templates
- ✗ Failed: 0

### Validated Manifests

All standard Kubernetes resources passed validation:

**elrmcp_bridge deployment:**
- `/home/user/A2A/elrmcp_bridge/deployment/k8s/hpa.yaml`
- `/home/user/A2A/elrmcp_bridge/deployment/k8s/deployment.yaml`
- `/home/user/A2A/elrmcp_bridge/deployment/k8s/namespace.yaml`
- `/home/user/A2A/elrmcp_bridge/deployment/k8s/configmap.yaml`
- `/home/user/A2A/elrmcp_bridge/deployment/k8s/service.yaml`

**erlang/a2a_erl deployment:**
- `/home/user/A2A/erlang/a2a_erl/k8s/ingress.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/deployment.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/namespace.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/pvc.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/configmap.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/ingress-tls.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/secret.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/service.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/log-check.yaml`
- `/home/user/A2A/erlang/a2a_erl/k8s/storage-check.yaml`

**Generated resources:**
- `/home/user/A2A/generated/demo_deployment.yaml`

### Custom Resource Definitions (CRDs)

The following CRDs require schemas for full validation:

**Marketplace Resources (2):**
- `marketplace/partner.yaml` - PartnerMetadata
- `marketplace/billing.yaml` - BillingConfiguration

**Chaos Engineering Resources (8):**
- `chaos-engineering/manifests/time-chaos.yaml` - TimeChaos
- `chaos-engineering/manifests/dns-chaos.yaml` - DNSChaos
- `chaos-engineering/manifests/network-chaos.yaml` - NetworkChaos
- `chaos-engineering/manifests/pod-kill-chaos.yaml` - PodChaos
- `chaos-engineering/manifests/io-chaos.yaml` - IOChaos
- `chaos-engineering/manifests/workflow-chaos.yaml` - Workflow
- `chaos-engineering/manifests/stress-chaos.yaml` - StressChaos
- `chaos-engineering/manifests/http-chaos.yaml` - HTTPChaos

### Skipped Files

Helm templates (71 files) containing Go template syntax (`{{ }}`) are automatically detected and skipped during validation.

## About kubeconform

kubeconform is a Kubernetes manifest validator that validates YAML files against Kubernetes schemas.

**Features:**
- Fast validation
- Supports multiple Kubernetes versions
- Can validate Custom Resource Definitions with additional schemas
- Actively maintained

**Installation:**
The validation scripts automatically install kubeconform v0.6.4 to `~/.local/bin/` if not already present.

## CI/CD Integration

To integrate validation into your CI/CD pipeline:

```bash
# Add to your GitHub Actions, GitLab CI, or other CI system
./validate-k8s-manifests-detailed.sh --skip-crds
```

This will:
- Exit with code 0 if all standard manifests are valid
- Exit with code 1 if any manifest has validation errors
- Skip CRD validation to avoid false positives

## Troubleshooting

### CRD Validation Errors

If you see errors for Custom Resources:
1. Use `--skip-crds` flag to ignore them
2. Install CRD schemas separately if needed
3. CRD errors are expected and don't indicate invalid YAML

### Helm Template Errors

Helm templates containing `{{ }}` syntax are automatically skipped. If you need to validate Helm charts:
1. Use `helm template` to render templates first
2. Then validate the rendered output

## Additional Resources

- [kubeconform GitHub](https://github.com/yannh/kubeconform)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- Full validation report: `k8s-validation-report.txt`
