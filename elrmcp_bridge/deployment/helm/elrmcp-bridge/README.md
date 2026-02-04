# elrmcp Bridge Helm Chart

A Helm chart for deploying the elrmcp MCP Bridge to Kubernetes clusters.

## Introduction

This chart deploys the elrmcp bridge, which connects elrmcp to Craftplan MCP servers with dynamic tool registration and request forwarding capabilities.

## Prerequisites

- Kubernetes cluster (v1.16+)
- Helm 3.x
- `kubectl` CLI

## Installation

### Install the Chart

```bash
helm install elrmcp-bridge ./deployment/helm/elrmcp-bridge
```

### Install with custom configuration

```bash
helm install elrmcp-bridge ./deployment/helm/elrmcp-bridge \
  --set replicaCount=3 \
  --set service.type=LoadBalancer \
  --set config.craftplan.url="http://custom-craftplan:8090"
```

### Install from repository (if published)

```bash
helm repo add elrmcp-bridge https://your-repo.com/charts
helm install elrmcp-bridge elrmcp-bridge/elrmcp-bridge
```

## Configuration

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `2` |
| `image.repository` | Image repository | `elrmcp-bridge` |
| `image.tag` | Image tag | `1.0.0` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Service type | `ClusterIP` |
| `service.ports.mcp.port` | MCP service port | `8091` |
| `service.ports.metrics.port` | Metrics service port | `9090` |
| `config.craftplan.url` | Craftplan MCP URL | `"http://craftplan-mcp:8090"` |
| `config.craftplan.timeout` | Request timeout | `30000` |
| `config.rateLimiting.enabled` | Enable rate limiting | `true` |
| `config.rateLimiting.requestsPerSecond` | Rate limit RPS | `100` |
| `config.rateLimiting.burstSize` | Burst size | `10` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `256Mi` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Min replicas | `2` |
| `autoscaling.maxReplicas` | Max replicas | `10` |
| `autoscaling.targetCPUUtilization` | Target CPU utilization | `70` |
| `autoscaling.targetMemoryUtilization` | Target memory utilization | `80` |

### Example Configuration

```yaml
# values.yaml
replicaCount: 3
service:
  type: LoadBalancer
  ports:
    mcp:
      port: 8091
      targetPort: 8091
    metrics:
      port: 9090
      targetPort: 9090
config:
  craftplan:
    url: "http://craftplan-mcp:8090"
    timeout: 30000
    authToken: "your-secret-token"
  rateLimiting:
    enabled: true
    requestsPerSecond: 150
    burstSize: 20
  toolManagement:
    whitelist: ["customer_management", "order_management"]
    cacheTtl: 600000
  performance:
    enableCaching: true
    cacheSize: 2000
    requestTimeout: 45000
  logging:
    level: debug
    enableMetrics: true
    requestLogging: true
    errorLogging: true
  security:
    validateInputs: true
    sanitizeOutputs: true
    maxRequestSize: 2097152
    allowedOrigins: ["*"]
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilization: 70
  targetMemoryUtilization: 80
```

### Network Configuration

```yaml
# Enable network policies
networkPolicy:
  enabled: true
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: elrmcp
      ports:
        - port: 8091
          protocol: TCP
        - port: 9090
          protocol: TCP

# Configure ingress
ingress:
  enabled: true
  className: "nginx"
  annotations:
    kubernetes.io/ingress.class: nginx
    kubernetes.io/tls-acme: "true"
  hosts:
    - host: elrmcp-bridge.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: elrmcp-bridge-tls
      hosts:
        - elrmcp-bridge.example.com
```

### Monitoring and Observability

```yaml
# Enable Prometheus monitoring
monitoring:
  enabled: true
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s

# Enable OpenTelemetry
telemetry:
  enabled: true
  otel:
    enabled: true
    service_name: elrmcp-bridge
    resource_attributes:
      service.version: "1.0.0"
      deployment.environment: "production"
```

### Security Configuration

```yaml
# Configure security context
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Configure service account
serviceAccount:
  create: true
  name: elrmcp-bridge
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/elrmcp-bridge
```

## Usage

### Check deployment status

```bash
helm status elrmcp-bridge
```

### View logs

```bash
kubectl logs -f deployment/elrmcp-bridge -n default
```

### Check metrics

```bash
kubectl get --raw '/apis/metrics.k8s.io/v1beta1/namespaces/default/pods' | jq '.'
```

### Scale the deployment

```bash
helm upgrade elrmcp-bridge ./deployment/helm/elrmcp-bridge --set replicaCount=4
```

### Configure autoscaling

```bash
helm upgrade elrmcp-bridge ./deployment/helm/elrmcp-bridge \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=3 \
  --set autoscaling.maxReplicas=10
```

## Uninstall

```bash
helm uninstall elrmcp-bridge
```

## Troubleshooting

### Common Issues

1. **Pod fails to start**:
```bash
kubectl describe pod -l app=elrmcp-bridge
kubectl logs -l app=elrmcp-bridge --previous
```

2. **Service not accessible**:
```bash
kubectl describe service elrmcp-bridge-service
```

3. **Configuration issues**:
```bash
kubectl get configmap elrmcp-bridge-config -o yaml
```

4. **HPA not working**:
```bash
kubectl get hpa elrmcp-bridge-hpa -o yaml
```

### Debug Commands

```bash
# Check pod status
kubectl get pods -l app=elrmcp-bridge

# Check service endpoints
kubectl get endpoints elrmcp-bridge-service

# Check pod events
kubectl get events -l app=elrmcp-bridge

# Describe deployment
kubectl describe deployment elrmcp-bridge
```

## Support

For support, please open an issue in the GitHub repository or contact the development team.