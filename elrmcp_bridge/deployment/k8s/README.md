# Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the elrmcp bridge.

## Files

- `namespace.yaml` - Creates the elrmcp-bridge namespace
- `configmap.yaml` - Application configuration
- `service.yaml` - Kubernetes service definition
- `deployment.yaml` - Deployment configuration
- `hpa.yaml` - Horizontal Pod Autoscaler

## Prerequisites

- Kubernetes cluster (v1.16+)
- Helm 3.x (for Helm chart)
- `kubectl` CLI

## Installation

### Using kubectl

1. Create the namespace:
```bash
kubectl apply -f namespace.yaml
```

2. Apply the configuration:
```bash
kubectl apply -f configmap.yaml
```

3. Deploy the application:
```bash
kubectl apply -f deployment.yaml
```

4. Create the service:
```bash
kubectl apply -f service.yaml
```

5. Apply autoscaling (optional):
```bash
kubectl apply -f hpa.yaml
```

### Using Helm

1. Add the Helm repository (if available):
```bash
helm repo add elrmcp-bridge https://your-repo.com/charts
```

2. Install the chart:
```bash
helm install elrmcp-bridge ./deployment/helm/elrmcp-bridge
```

3. Upgrade the chart:
```bash
helm upgrade elrmcp-bridge ./deployment/helm/elrmcp-bridge
```

4. Delete the release:
```bash
helm delete elrmcp-bridge
```

## Configuration

The configuration is stored in `configmap.yaml` and includes:

- Bridge settings
- Craftplan MCP connection
- Rate limiting
- Performance tuning
- Security settings

## Monitoring

### Check deployment status:
```bash
kubectl get pods -n elrmcp-bridge
kubectl get services -n elrmcp-bridge
kubectl get hpa -n elrmcp-bridge
```

### View logs:
```bash
kubectl logs -f deployment/elrmcp-bridge -n elrmcp-bridge
```

### Check metrics:
```bash
kubectl get --raw '/apis/metrics.k8s.io/v1beta1/namespaces/elrmcp-bridge/pods' | jq '.'
```

## Scaling

### Manual scaling:
```bash
kubectl scale deployment elrmcp-bridge --replicas=3 -n elrmcp-bridge
```

### Automatic scaling (via HPA):
The HPA automatically scales between 2 and 10 replicas based on CPU and memory utilization.

## Troubleshooting

### Common issues:

1. **Pod stuck in pending**:
```bash
kubectl describe pod -l app=elrmcp-bridge -n elrmcp-bridge
```

2. **Pod crash loop**:
```bash
kubectl logs -l app=elrmcp-bridge -n elrmcp-bridge --previous
```

3. **Service not accessible**:
```bash
kubectl describe service elrmcp-bridge-service -n elrmcp-bridge
```

4. **Configuration issues**:
```bash
kubectl get configmap elrmcp-bridge-config -n elrmcp-bridge -o yaml
```

## Cleanup

Delete all resources:
```bash
kubectl delete namespace elrmcp-bridge
```

## Security

The deployment includes security best practices:
- Read-only root filesystem
- Non-root user execution
- Resource limits
- Pod security context
- Network policies (optional)