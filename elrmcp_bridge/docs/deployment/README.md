# Deployment Guide

This guide provides detailed instructions for deploying the elrmcp bridge in various environments.

## Deployment Options

The elrmcp bridge can be deployed in several ways:

1. **Standalone Deployment** - Direct Erlang application
2. **Docker Container** - Containerized deployment
3. **Kubernetes** - Orchestration with Helm
4. **Cloud Platforms** - AWS, GCP, Azure

## Prerequisites

- Erlang/OTP 23+
- Docker (for container deployment)
- Kubernetes (for K8s deployment)
- Helm 3.x (for K8s deployment)

## Standalone Deployment

### 1. Build the Application

```bash
make compile
```

### 2. Configure the Application

Edit `config/bridge.config`:

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 100
    }
  }
}
```

### 3. Start the Application

```bash
make start
```

### 4. Systemd Service (Optional)

Create `/etc/systemd/system/elrmcp-bridge.service`:

```ini
[Unit]
Description=elrmcp Bridge
After=network.target

[Service]
Type=simple
User=elrmcp
Group=elrmcp
WorkingDirectory=/opt/elrmcp-bridge
ExecStart=/opt/elrmcp-bridge/_build/default/rel/elrmcp_bridge/bin/elrmcp_bridge foreground
Restart=always
RestartSec=5
Environment=LOG_LEVEL=info
Environment=CRAFTPLAN_URL=http://localhost:8090

[Install]
WantedBy=multi-user.target
```

### 5. Enable the Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable elrmcp-bridge
sudo systemctl start elrmcp-bridge
```

## Docker Deployment

### 1. Build the Docker Image

```bash
docker build -t elrmcp-bridge:latest .
```

### 2. Run with Docker

```bash
docker run -d \
  --name elrmcp-bridge \
  -p 8091:8091 \
  -p 9090:9090 \
  -v /opt/elrmcp-bridge/config:/etc/elrmcp-bridge \
  -e CRAFTPLAN_URL=http://craftplan-mcp:8090 \
  -e LOG_LEVEL=info \
  elrmcp-bridge:latest
```

### 3. Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'
services:
  elrmcp-bridge:
    image: elrmcp-bridge:latest
    ports:
      - "8091:8091"
      - "9090:9090"
    environment:
      - CRAFTPLAN_URL=http://craftplan-mcp:8090
      - LOG_LEVEL=info
      - BRIDGE_RATE_LIMIT=100
    volumes:
      - ./config:/etc/elrmcp-bridge
    depends_on:
      - craftplan-mcp
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8091/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  craftplan-mcp:
    image: craftplan-mcp:latest
    ports:
      - "8090:8090"
    environment:
      - LOG_LEVEL=info
    restart: unless-stopped
```

### 4. Docker Compose with Networking

```bash
docker-compose up -d
docker network ls
docker network inspect elrmcp-bridge_default
```

## Kubernetes Deployment

### 1. Using Helm (Recommended)

```bash
helm install elrmcp-bridge ./deployment/helm/elrmcp-bridge \
  --set config.craftplan.url="http://craftplan-mcp:8090" \
  --set replicaCount=3 \
  --set service.type=LoadBalancer
```

### 2. Using kubectl

```bash
kubectl apply -f deployment/k8s/namespace.yaml
kubectl apply -f deployment/k8s/configmap.yaml
kubectl apply -f deployment/k8s/deployment.yaml
kubectl apply -f deployment/k8s/service.yaml
```

### 3. Kubernetes Configuration

#### Custom Configuration

```yaml
# values-custom.yaml
replicaCount: 3
service:
  type: LoadBalancer
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
config:
  craftplan:
    url: "http://craftplan-mcp.default.svc.cluster.local:8090"
  rateLimiting:
    requestsPerSecond: 150
  performance:
    enableCaching: true
    cacheSize: 2000
resources:
  requests:
    cpu: "200m"
    memory: "512Mi"
  limits:
    cpu: "1000m"
    memory: "1Gi"
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilization: 70
  targetMemoryUtilization: 80
```

#### Apply Custom Values

```bash
helm upgrade elrmcp-bridge ./deployment/helm/elrmcp-bridge \
  -f values-custom.yaml
```

### 4. Monitoring and Logging

#### Prometheus Monitoring

```yaml
# monitoring-values.yaml
monitoring:
  enabled: true
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s
```

#### Logging with Fluentd

```yaml
# logging-values.yaml
podAnnotations:
  fluentd.influxdb.tag: "elrmcp.bridge"
```

## Cloud Platform Deployment

### AWS ECS

#### 1. Create Task Definition

```json
{
  "family": "elrmcp-bridge",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "elrmcp-bridge",
      "image": "your-account.dkr.ecr.us-east-1.amazonaws.com/elrmcp-bridge:latest",
      "portMappings": [
        {
          "containerPort": 8091,
          "protocol": "tcp"
        },
        {
          "containerPort": 9090,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "CRAFTPLAN_URL",
          "value": "http://craftplan-mcp:8090"
        },
        {
          "name": "LOG_LEVEL",
          "value": "info"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/elrmcp-bridge",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

#### 2. Deploy Service

```bash
aws ecs create-service \
  --cluster your-cluster \
  --service-name elrmcp-bridge \
  --task-definition elrmcp-bridge:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-1234],securityGroups=[sg-1234],assignPublicIp=ENABLED}"
```

### Google Cloud Run

#### 1. Build and Push Image

```bash
gcloud builds submit --tag gcr.io/your-project/elrmcp-bridge
```

#### 2. Deploy to Cloud Run

```bash
gcloud run deploy elrmcp-bridge \
  --image gcr.io/your-project/elrmcp-bridge \
  --platform managed \
  --region us-central1 \
  --set-env-vars CRAFTPLAN_URL=http://craftplan-mcp:8090,LOG_LEVEL=info \
  --allow-unauthenticated
```

### Azure Container Instances

#### 1. Deploy ACI

```bash
az container create \
  --resource-group your-resource-group \
  --name elrmcp-bridge \
  --image your-registry.azurecr.io/elrmcp-bridge \
  --ports 8091 9090 \
  --environment-variables CRAFTPLAN_URL=http://craftplan-mcp:8090 LOG_LEVEL=info \
  --dns-name-label elrmcp-bridge-123 \
  --location eastus
```

## Configuration Management

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CRAFTPLAN_URL` | Craftplan MCP server URL | `http://localhost:8090` |
| `LOG_LEVEL` | Logging level | `info` |
| `BRIDGE_TIMEOUT` | Request timeout in ms | `30000` |
| `BRIDGE_RATE_LIMIT` | Rate limit per second | `100` |
| `BRIDGE_CACHE_SIZE` | Cache size | `1000` |
| `BRIDGE_CACHE_TTL` | Cache TTL in ms | `300000` |

### Configuration Files

#### Bridge Configuration

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 100,
      "burst_size": 10
    },
    "tool_management": {
      "whitelist": [],
      "blacklist": ["admin_tools"]
    },
    "performance": {
      "enable_caching": true,
      "cache_size": 1000,
      "cache_ttl": 300000
    }
  }
}
```

#### VM Arguments

```erlang
## Kernel
+K true
+zdbbl 128000

## Process Limits
+P 1048576
+A 64

## Memory
-heap_type optimal
-hms 64 +hmsz 64 +hmtvm 128
```

## Security Considerations

### Network Security

1. **Firewall Rules**
   - Only allow necessary ports
   - Restrict access to trusted IPs
   - Use network security groups

2. **TLS/SSL**
   - Enable HTTPS for external access
   - Use valid certificates
   - Implement certificate rotation

3. **Authentication**
   - Use API keys for authentication
   - Implement JWT tokens
   - Regularly rotate credentials

### Container Security

1. **Image Security**
   - Use official base images
   - Regularly update dependencies
   - Scan for vulnerabilities

2. **Runtime Security**
   - Use non-root users
   - Implement resource limits
   - Enable read-only filesystems

3. **Secret Management**
   - Use secrets management systems
   - Avoid hardcoded credentials
   - Implement access controls

### Monitoring and Alerting

1. **Health Checks**
   - Implement health endpoints
   - Monitor application metrics
   - Set up alerts for critical issues

2. **Logging**
   - Centralized logging
   - Log level management
   - Log rotation and retention

3. **Performance Monitoring**
   - Request latency
   - Error rates
   - Resource utilization

## Troubleshooting

### Common Issues

1. **Pod crashes**
   - Check resource limits
   - Review logs for errors
   - Verify configuration

2. **Connection issues**
   - Check network policies
   - Verify service endpoints
   - Test connectivity

3. **Performance issues**
   - Monitor resource usage
   - Check for memory leaks
   - Optimize configuration

### Debug Commands

```bash
# Check pod status
kubectl get pods -n elrmcp-bridge

# View logs
kubectl logs -f deployment/elrmcp-bridge -n elrmcp-bridge

# Describe pod
kubectl describe pod elrmcp-bridge-1234 -n elrmcp-bridge

# Check events
kubectl get events -n elrmcp-bridge

# Check configmap
kubectl get configmap elrmcp-bridge-config -n elrmcp-bridge -o yaml
```

## Backup and Recovery

### Configuration Backup

```bash
# Backup ConfigMap
kubectl get configmap elrmcp-bridge-config -n elrmcp-bridge -o yaml > backup-config.yaml

# Backup secrets
kubectl get secrets -n elrmcp-bridge -o yaml > backup-secrets.yaml
```

### Disaster Recovery

1. **Automated Backups**
   - Schedule regular backups
   - Store in multiple locations
   - Test recovery procedures

2. **High Availability**
   - Deploy multiple replicas
   - Use load balancing
   - Implement failover

3. **Rollback Strategy**
   - Version deployments
   - Enable rollback capabilities
   - Test rollback procedures

## Scaling

### Horizontal Scaling

1. **Manual Scaling**
   ```bash
   kubectl scale deployment elrmcp-bridge --replicas=5 -n elrmcp-bridge
   ```

2. **Auto Scaling**
   ```yaml
   # Enable HPA
   autoscaling:
     enabled: true
     minReplicas: 3
     maxReplicas: 10
     targetCPUUtilization: 70
   ```

### Vertical Scaling

```yaml
# Adjust resource limits
resources:
  requests:
    cpu: "500m"
    memory: "1Gi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

## Maintenance

### Updates and Patches

1. **Regular Updates**
   - Monitor security advisories
   - Apply patches promptly
   - Test updates in staging

2. **Version Management**
   - Use semantic versioning
   - Maintain change logs
   - Communicate changes

### Scheduled Maintenance

1. **Planned Downtime**
   - Schedule during low usage
   - Notify stakeholders
   - Have rollback plan

2. **Emergency Maintenance**
   - Respond quickly to issues
   - Minimize impact
   - Document incidents

## Best Practices

### Configuration Management

1. **Use environment-specific configs**
2. **Implement configuration validation**
3. **Secure sensitive configuration**
4. **Version configuration files**

### Monitoring

1. **Monitor key metrics**
2. **Set up alerts**
3. **Monitor dependencies**
4. **Track performance**

### Security

1. **Follow least privilege principle**
2. **Regular security audits**
3. **Implement logging and monitoring**
4. **Keep dependencies updated**