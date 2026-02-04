# A2A Erlang - ConfigMap and Secret Verification Guide

This guide describes how ConfigMaps and Secrets are configured and mounted in the A2A Erlang Kubernetes deployment.

## Overview

The A2A Erlang application uses:
- **ConfigMap**: Stores configuration files (`vm.args`, `sys.config`)
- **Secret**: Stores sensitive data (Erlang cookie for distributed nodes)

## Files Structure

### K8s Native Resources
```
k8s/
├── configmap.yaml              # ConfigMap with vm.args and sys.config
├── secret.yaml                 # Secret with erlang-cookie
├── deployment.yaml             # Deployment with volume mounts
├── test-configmap-secret.yaml  # Test pod for verification
└── verify-configmap-secret.sh  # Verification script
```

### Helm Templates
```
helm/a2a-erl/templates/
├── configmap.yaml              # ConfigMap template
├── secret.yaml                 # Secret template
├── deployment.yaml             # Deployment with volume mounts
└── tests/
    └── test-configmap-secret.yaml  # Helm test for verification
```

## Verification

### Quick Verification (K8s Native)

Run the automated verification script:

```bash
cd k8s
./verify-configmap-secret.sh
```

### Manual Verification

#### 1. Check ConfigMap exists

```bash
kubectl get configmap a2a-config -n a2a-system
```

#### 2. Check ConfigMap contents

```bash
kubectl get configmap a2a-config -n a2a-system -o yaml
```

#### 3. Check Secret exists

```bash
kubectl get secret a2a-secret -n a2a-system
```

#### 4. Check Secret contents (base64 decoded)

```bash
kubectl get secret a2a-secret -n a2a-system -o jsonpath='{.data.erlang-cookie}' | base64 -d
```

#### 5. Run test pod

```bash
kubectl apply -f k8s/test-configmap-secret.yaml
kubectl logs a2a-config-test -n a2a-system -f
kubectl delete pod a2a-config-test -n a2a-system
```

#### 6. Check deployment volume mounts

```bash
kubectl get deployment a2a-deployment -n a2a-system -o jsonpath='{.spec.template.spec.volumes}'
kubectl get deployment a2a-deployment -n a2a-system -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'
```

### Helm Verification

#### 1. Install/upgrade release

```bash
helm upgrade --install a2a-erl ./helm/a2a-erl -n a2a-system --create-namespace
```

#### 2. Run Helm tests

```bash
helm test a2a-erl -n a2a-system
```

#### 3. Check rendered templates

```bash
helm template a2a-erl ./helm/a2a-erl -n a2a-system
```

## Configuration Details

### ConfigMap Data

The ConfigMap contains:

| Key | Description |
|-----|-------------|
| `vm.args` | Erlang VM arguments (SMP, ports, processes, etc.) |
| `sys.config` | Application configuration (port, host, logging) |

### Secret Data

The Secret contains:

| Key | Description |
|-----|-------------|
| `erlang-cookie` | Erlang cookie for node distribution |

### Environment Variables

The deployment sets these environment variables:

| Variable | Source | Description |
|----------|--------|-------------|
| `RELEASE_COOKIE` | Secret | Erlang cookie for clustering |
| `PORT` | Direct/ConfigMap | HTTP port (default: 8080) |
| `HOST` | Direct/ConfigMap | HTTP host (default: 0.0.0.0) |
| `SCHEME` | Direct/ConfigMap | HTTP scheme (default: http) |
| `POD_IP` | FieldRef | Pod IP address |
| `ERLANG_NODE` | Config | Node name prefix |
| `RELEASE_DISTRIBUTION` | Config | Distribution mode |

### Volume Mounts

| Volume | Source | Mount Path | Mode |
|--------|--------|------------|------|
| `config` | ConfigMap `a2a-config` | `/opt/a2a_erl/config` | readOnly |
| `tmp` | emptyDir | `/tmp` | readWrite |
| `log` | emptyDir/PVC | `/opt/a2a_erl/log` | readWrite |

## Troubleshooting

### ConfigMap not mounted

Check pod events:

```bash
kubectl describe pod <pod-name> -n a2a-system
```

Look for mount errors or missing ConfigMap references.

### Secret not accessible

Verify the pod has permission to read the secret:

```bash
kubectl auth can-i get secrets -n a2a-system --as=system:serviceaccount:a2a-system:default
```

### Environment variable not set

Check pod environment:

```bash
kubectl exec <pod-name> -n a2a-system -- env | grep RELEASE
```

### Files not readable

Check file permissions in the pod:

```bash
kubectl exec <pod-name> -n a2a-system -- ls -la /opt/a2a_erl/config/
```

## Security Notes

1. **Secret Rotation**: Change the cookie in `secret.yaml` and redeploy
2. **RBAC**: Ensure service accounts have minimal required permissions
3. **Encryption**: Enable at-rest encryption for Secrets in your cluster
4. **Network Policies**: Restrict pod-to-pod communication

## Validation Checklist

- [ ] ConfigMap exists in namespace
- [ ] ConfigMap contains `vm.args` and `sys.config`
- [ ] Secret exists in namespace
- [ ] Secret contains `erlang-cookie`
- [ ] Deployment mounts ConfigMap volume
- [ ] Deployment has `RELEASE_COOKIE` from Secret
- [ ] Test pod completes successfully
- [ ] Helm tests pass
