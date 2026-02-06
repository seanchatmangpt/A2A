# A2A Protocol - Administrator's Guide

## Table of Contents

- [1. Overview](#1-overview)
- [2. Operations](#2-operations)
  - [2.1 Deployment](#21-deployment)
  - [2.2 Configuration Management](#22-configuration-management)
  - [2.3 Service Management](#23-service-management)
  - [2.4 Maintenance](#24-maintenance)
- [3. Monitoring](#3-monitoring)
  - [3.1 Health Checks](#31-health-checks)
  - [3.2 Metrics](#32-metrics)
  - [3.3 Logging](#33-logging)
  - [3.4 Alerting](#34-alerting)
- [4. Scaling](#4-scaling)
  - [4.1 Horizontal Scaling](#41-horizontal-scaling)
  - [4.2 Vertical Scaling](#42-vertical-scaling)
  - [4.3 Auto-Scaling](#43-auto-scaling)
  - [4.4 Load Balancing](#44-load-balancing)
- [5. Backup and Restore](#5-backup-and-restore)
  - [5.1 Backup Strategy](#51-backup-strategy)
  - [5.2 Backup Procedures](#52-backup-procedures)
  - [5.3 Restore Procedures](#53-restore-procedures)
  - [5.4 Verification](#54-verification)
- [6. Disaster Recovery](#6-disaster-recovery)
  - [6.1 Recovery Objectives](#61-recovery-objectives)
  - [6.2 Failure Scenarios](#62-failure-scenarios)
  - [6.3 Recovery Procedures](#63-recovery-procedures)
  - [6.4 Testing](#64-testing)

---

## 1. Overview

This guide provides comprehensive operational procedures for administering A2A Protocol infrastructure. The A2A Protocol enables agent-to-agent communication across diverse AI systems, requiring robust operational practices to ensure high availability, performance, and reliability.

### Architecture Components

- **A2A Agents**: Erlang/OTP-based agent services
- **MCP Servers**: Model Context Protocol integration layer
- **ELRMCP Bridge**: Erlang-MCP interoperability bridge
- **Craftplan**: Task orchestration and planning services
- **Infrastructure**: Kubernetes clusters, load balancers, storage
- **Monitoring**: Prometheus, Grafana, Loki for observability

---

## 2. Operations

### 2.1 Deployment

#### 2.1.1 Kubernetes Deployment

**Prerequisites:**
- Kubernetes cluster (v1.24+)
- kubectl configured with cluster access
- Helm 3.x installed
- Docker registry access

**Deploy A2A Services:**

```bash
# Create namespace
kubectl create namespace a2a-system

# Apply namespace configuration
kubectl apply -f erlang/a2a_erl/k8s/namespace.yaml

# Deploy ConfigMaps and Secrets
kubectl apply -f erlang/a2a_erl/k8s/configmap.yaml
kubectl apply -f erlang/a2a_erl/k8s/secret.yaml

# Deploy persistent volumes
kubectl apply -f erlang/a2a_erl/k8s/pvc.yaml

# Deploy services
kubectl apply -f erlang/a2a_erl/k8s/service.yaml

# Deploy application
kubectl apply -f erlang/a2a_erl/k8s/deployment.yaml

# Deploy ingress (optional)
kubectl apply -f erlang/a2a_erl/k8s/ingress.yaml
```

**Verify deployment:**

```bash
# Check pod status
kubectl get pods -n a2a-system

# Check service endpoints
kubectl get svc -n a2a-system

# Check deployment status
kubectl rollout status deployment/a2a-deployment -n a2a-system

# Verify health
kubectl exec -n a2a-system deployment/a2a-deployment -- curl -f http://localhost:8080/health
```

#### 2.1.2 Terraform Infrastructure

**Deploy complete infrastructure:**

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var-file=production.tfvars

# Apply infrastructure
terraform apply -var-file=production.tfvars

# Configure kubectl
aws eks update-kubeconfig --region us-west-2 --name $(terraform output -raw cluster_name)

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

**Infrastructure outputs:**

```bash
# Get cluster endpoint
terraform output cluster_endpoint

# Get load balancer DNS
terraform output load_balancer_dns_name

# Get monitoring endpoints
terraform output prometheus_endpoint
terraform output grafana_endpoint
```

#### 2.1.3 Docker Compose Deployment

**For development/testing:**

```bash
cd erlang/a2a_erl

# Production deployment
docker-compose up -d

# Development with live reload
docker-compose --profile dev up a2a-dev

# View logs
docker-compose logs -f a2a-erl

# Stop services
docker-compose down
```

### 2.2 Configuration Management

#### 2.2.1 ConfigMap Updates

**Update application configuration:**

```bash
# Edit ConfigMap
kubectl edit configmap a2a-config -n a2a-system

# Or apply from file
kubectl apply -f erlang/a2a_erl/k8s/configmap.yaml

# Restart pods to pick up changes
kubectl rollout restart deployment/a2a-deployment -n a2a-system

# Verify configuration
kubectl get configmap a2a-config -n a2a-system -o yaml
```

**Key configuration files:**
- `vm.args`: Erlang VM arguments (memory, processes, networking)
- `sys.config`: Application configuration (ports, features, logging)

#### 2.2.2 Secret Management

**Rotate Erlang cookie:**

```bash
# Generate new cookie
NEW_COOKIE=$(openssl rand -base64 32)

# Update secret
kubectl create secret generic a2a-secret \
  --from-literal=erlang-cookie=$NEW_COOKIE \
  --dry-run=client -o yaml | kubectl apply -n a2a-system -f -

# Rolling restart to apply
kubectl rollout restart deployment/a2a-deployment -n a2a-system
```

**Best practices:**
- Rotate secrets quarterly or after security incidents
- Use external secret managers (AWS Secrets Manager, Vault)
- Never commit secrets to version control
- Enable encryption at rest for etcd

#### 2.2.3 Environment Variables

**Update deployment environment:**

```bash
# Edit deployment
kubectl edit deployment a2a-deployment -n a2a-system

# Or patch specific variables
kubectl set env deployment/a2a-deployment -n a2a-system \
  PORT=8080 \
  SCHEME=https \
  ERL_MAX_PORTS=131072
```

### 2.3 Service Management

#### 2.3.1 Service Status

**Check service health:**

```bash
# Get all services
kubectl get svc -n a2a-system

# Describe service details
kubectl describe svc a2a-service -n a2a-system

# Check endpoints
kubectl get endpoints a2a-service -n a2a-system

# Test connectivity
kubectl run -n a2a-system test-pod --rm -i --tty --image=curlimages/curl -- \
  curl http://a2a-service:8080/health
```

#### 2.3.2 Rolling Updates

**Update application version:**

```bash
# Update image
kubectl set image deployment/a2a-deployment -n a2a-system \
  a2a-erl=a2a-erl:v1.2.0

# Monitor rollout
kubectl rollout status deployment/a2a-deployment -n a2a-system

# Check rollout history
kubectl rollout history deployment/a2a-deployment -n a2a-system

# Rollback if needed
kubectl rollout undo deployment/a2a-deployment -n a2a-system
```

**Rollout strategy:**
- MaxSurge: 1 (one additional pod during update)
- MaxUnavailable: 0 (zero downtime)
- Default strategy: RollingUpdate

#### 2.3.3 Pod Management

**Common pod operations:**

```bash
# List pods
kubectl get pods -n a2a-system -o wide

# View pod logs
kubectl logs -n a2a-system -l app=a2a-erl --tail=100 -f

# Execute commands in pod
kubectl exec -n a2a-system deployment/a2a-deployment -- bin/a2a_erl versions

# Debug pod
kubectl debug -n a2a-system -it pod/a2a-deployment-xxx --image=busybox

# Delete pod (will be recreated)
kubectl delete pod -n a2a-system a2a-deployment-xxx
```

### 2.4 Maintenance

#### 2.4.1 Regular Maintenance Tasks

**Daily:**
- Monitor service health and availability
- Review error logs and alerts
- Check resource utilization
- Verify backup completion

**Weekly:**
- Review performance metrics
- Analyze capacity trends
- Update documentation
- Test alert notifications

**Monthly:**
- Apply security patches
- Review and rotate credentials
- Audit access logs
- Disaster recovery drill
- Capacity planning review

**Quarterly:**
- Kubernetes version upgrade
- Dependency updates
- Security audit
- Performance baseline update

#### 2.4.2 Maintenance Windows

**Schedule maintenance:**

```bash
# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance (OS updates, hardware, etc.)

# Uncordon node
kubectl uncordon <node-name>

# Verify node is ready
kubectl get nodes
```

**Application maintenance:**

```bash
# Scale down replicas
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=0

# Perform maintenance (database migration, etc.)

# Scale back up
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=2

# Verify health
kubectl get pods -n a2a-system
```

#### 2.4.3 Log Rotation

**Configure log retention:**

```bash
# Update logging driver settings in docker-compose.yml
# Or configure in Kubernetes DaemonSet for log forwarder

# Manual log cleanup
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  find /opt/a2a_erl/log -name "*.log" -mtime +7 -delete

# Configure automatic rotation via logrotate
```

---

## 3. Monitoring

### 3.1 Health Checks

#### 3.1.1 Kubernetes Probes

**Liveness Probe:**
- Endpoint: `GET /health`
- Initial delay: 30s
- Period: 10s
- Timeout: 5s
- Failure threshold: 3

**Readiness Probe:**
- Endpoint: `GET /health`
- Initial delay: 10s
- Period: 5s
- Timeout: 3s
- Failure threshold: 3

**Startup Probe:**
- Endpoint: `GET /health`
- Initial delay: 5s
- Period: 5s
- Timeout: 3s
- Failure threshold: 12

#### 3.1.2 Health Check Endpoints

**Manual health checks:**

```bash
# Internal health check
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  curl -f http://localhost:8080/health

# External health check
curl -f http://<load-balancer-dns>/health

# Detailed health status
curl http://<load-balancer-dns>/health/detailed
```

**Expected responses:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime": 3600,
  "checks": {
    "database": "ok",
    "erlang_vm": "ok",
    "memory": "ok",
    "disk": "ok"
  }
}
```

### 3.2 Metrics

#### 3.2.1 Prometheus Configuration

**Prometheus scrapes metrics from:**
- Application endpoints (port 8080)
- Kubernetes API server
- Node exporters
- cAdvisor

**Key metrics to monitor:**

**Application Metrics:**
- `a2a_requests_total`: Total HTTP requests
- `a2a_request_duration_seconds`: Request latency
- `a2a_active_tasks`: Active agent tasks
- `a2a_task_duration_seconds`: Task completion time
- `a2a_errors_total`: Error count by type

**Erlang VM Metrics:**
- `erlang_vm_memory_bytes_total`: Total memory usage
- `erlang_vm_process_count`: Process count
- `erlang_vm_port_count`: Port count
- `erlang_vm_ets_tables`: ETS table count
- `erlang_vm_schedulers`: Scheduler utilization

**System Metrics:**
- `node_cpu_seconds_total`: CPU usage
- `node_memory_MemAvailable_bytes`: Available memory
- `node_disk_io_time_seconds_total`: Disk I/O
- `node_network_transmit_bytes_total`: Network traffic

#### 3.2.2 Grafana Dashboards

**Access Grafana:**

```bash
# Get Grafana URL
terraform output grafana_endpoint

# Or port-forward
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open http://localhost:3000
```

**Pre-configured dashboards:**
- A2A Cluster Overview
- Application Performance
- Erlang VM Monitoring
- Resource Utilization
- Error Rates and Latency
- Task Processing Metrics

**Custom queries:**

```promql
# 95th percentile request latency
histogram_quantile(0.95,
  rate(a2a_request_duration_seconds_bucket[5m]))

# Error rate
rate(a2a_errors_total[5m])

# Memory usage percentage
100 * (1 - (erlang_vm_memory_bytes_free / erlang_vm_memory_bytes_total))

# Active connections
sum(a2a_active_connections)
```

### 3.3 Logging

#### 3.3.1 Log Collection

**Log architecture:**
- Applications write to stdout/stderr
- Kubernetes captures container logs
- Loki aggregates and stores logs
- Grafana provides log exploration

**View logs:**

```bash
# Kubernetes logs
kubectl logs -n a2a-system -l app=a2a-erl --tail=100 -f

# All containers in pod
kubectl logs -n a2a-system pod/a2a-deployment-xxx --all-containers

# Previous pod logs
kubectl logs -n a2a-system pod/a2a-deployment-xxx --previous

# Export logs
kubectl logs -n a2a-system deployment/a2a-deployment > a2a.log
```

#### 3.3.2 Log Levels

**Configure log levels:**

```erlang
% In sys.config
{kernel, [
  {logger_level, info},
  {logger, [
    {handler, default, logger_std_h, #{
      level => info,
      formatter => {logger_formatter, #{
        single_line => true,
        template => [time, " [", level, "] ", msg, "\n"]
      }}
    }}
  ]}
]}
```

**Log levels:**
- `emergency`: System is unusable
- `alert`: Action must be taken immediately
- `critical`: Critical conditions
- `error`: Error conditions
- `warning`: Warning conditions
- `notice`: Normal but significant
- `info`: Informational messages
- `debug`: Debug-level messages

#### 3.3.3 Log Analysis

**Common log queries in Loki:**

```logql
# All errors in last hour
{namespace="a2a-system"} |= "error" | json

# Failed requests
{namespace="a2a-system"} | json | status >= 400

# High latency requests
{namespace="a2a-system"} | json | duration > 1000

# Specific task errors
{namespace="a2a-system"} | json | task_id="xyz" |= "error"
```

### 3.4 Alerting

#### 3.4.1 Alert Rules

**Critical alerts:**

```yaml
# High error rate
- alert: HighErrorRate
  expr: rate(a2a_errors_total[5m]) > 0.05
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: High error rate detected
    description: Error rate is {{ $value }} errors/sec

# Service down
- alert: ServiceDown
  expr: up{job="a2a-service"} == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: A2A service is down
    description: Service {{ $labels.instance }} is unreachable

# High memory usage
- alert: HighMemoryUsage
  expr: erlang_vm_memory_bytes_total / node_memory_MemTotal_bytes > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: High memory usage
    description: Memory usage is {{ $value | humanizePercentage }}
```

**Warning alerts:**

```yaml
# Pod restarts
- alert: PodRestarts
  expr: rate(kube_pod_container_status_restarts_total{namespace="a2a-system"}[15m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: Pod restarting frequently
    description: Pod {{ $labels.pod }} has restarted {{ $value }} times

# High latency
- alert: HighLatency
  expr: histogram_quantile(0.95, rate(a2a_request_duration_seconds_bucket[5m])) > 1
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: High request latency
    description: 95th percentile latency is {{ $value }}s
```

#### 3.4.2 Alert Channels

**Configure notifications:**

```yaml
# Alertmanager configuration
receivers:
  - name: 'team-pagerduty'
    pagerduty_configs:
      - service_key: <pagerduty-key>
        severity: '{{ .GroupLabels.severity }}'

  - name: 'team-slack'
    slack_configs:
      - api_url: <slack-webhook-url>
        channel: '#alerts'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'team-email'
    email_configs:
      - to: 'ops@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
```

**Alert routing:**

```yaml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'team-slack'
  routes:
    - match:
        severity: critical
      receiver: 'team-pagerduty'
    - match:
        severity: warning
      receiver: 'team-slack'
```

---

## 4. Scaling

### 4.1 Horizontal Scaling

#### 4.1.1 Manual Scaling

**Scale deployment:**

```bash
# Scale to specific replica count
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=5

# Verify scaling
kubectl get deployment a2a-deployment -n a2a-system
kubectl get pods -n a2a-system -l app=a2a-erl

# Check pod distribution across nodes
kubectl get pods -n a2a-system -o wide
```

**Scaling considerations:**
- Minimum replicas: 2 (for high availability)
- Maximum replicas: 10 (default HPA limit)
- Each replica requires: 256Mi-1Gi memory, 250m-1000m CPU
- Distributed Erlang clustering requires headless service

#### 4.1.2 Service Mesh Scaling

**For multi-region deployments:**

```bash
# Deploy to additional regions
kubectl config use-context us-west-2
kubectl apply -f erlang/a2a_erl/k8s/

kubectl config use-context eu-west-1
kubectl apply -f erlang/a2a_erl/k8s/

# Configure global load balancer
# Route traffic based on latency/geography
```

### 4.2 Vertical Scaling

#### 4.2.1 Resource Limits

**Update resource requests/limits:**

```bash
# Edit deployment
kubectl edit deployment a2a-deployment -n a2a-system

# Or apply patch
kubectl patch deployment a2a-deployment -n a2a-system -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "a2a-erl",
          "resources": {
            "requests": {
              "memory": "512Mi",
              "cpu": "500m"
            },
            "limits": {
              "memory": "2Gi",
              "cpu": "2000m"
            }
          }
        }]
      }
    }
  }
}'
```

**Resource sizing guidelines:**

| Workload | CPU Request | CPU Limit | Memory Request | Memory Limit |
|----------|-------------|-----------|----------------|--------------|
| Small    | 250m        | 500m      | 256Mi          | 512Mi        |
| Medium   | 500m        | 1000m     | 512Mi          | 1Gi          |
| Large    | 1000m       | 2000m     | 1Gi            | 2Gi          |
| XLarge   | 2000m       | 4000m     | 2Gi            | 4Gi          |

#### 4.2.2 VM Tuning

**Erlang VM configuration:**

```bash
# In vm.args ConfigMap
+P 1048576              # Maximum processes
+Q 262144               # Maximum ports
+K true                 # Enable kernel polling
+A 64                   # Async thread pool size
+SDio 64                # Dirty I/O schedulers
+SDcpu 8                # Dirty CPU schedulers
+zdbbl 65536            # Distribution buffer busy limit
```

**Memory allocation:**

```bash
# Set heap size limits
+hms 8192               # Minimum heap size (words)
+hmbs 46422             # Minimum binary virtual heap size (words)

# Set ETS table limits
+e 65536                # ETS table limit
```

### 4.3 Auto-Scaling

#### 4.3.1 Horizontal Pod Autoscaler (HPA)

**HPA configuration:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: a2a-hpa
  namespace: a2a-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a2a-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
```

**Monitor HPA:**

```bash
# Check HPA status
kubectl get hpa -n a2a-system

# Describe HPA with events
kubectl describe hpa a2a-hpa -n a2a-system

# Watch scaling events
kubectl get hpa a2a-hpa -n a2a-system --watch
```

#### 4.3.2 Cluster Autoscaler

**Node autoscaling:**

```bash
# Configure cluster autoscaler
# In Terraform or EKS node group settings
enable_auto_scaling = true
node_group_size = 3
node_group_max_size = 10
node_group_min_size = 2

# Monitor cluster autoscaler
kubectl logs -n kube-system -l app=cluster-autoscaler
```

#### 4.3.3 Custom Metrics Scaling

**Scale based on custom metrics:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: a2a-hpa-custom
  namespace: a2a-system
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a2a-deployment
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Pods
    pods:
      metric:
        name: a2a_active_tasks
      target:
        type: AverageValue
        averageValue: "100"
  - type: External
    external:
      metric:
        name: queue_depth
        selector:
          matchLabels:
            queue_name: a2a-tasks
      target:
        type: AverageValue
        averageValue: "50"
```

### 4.4 Load Balancing

#### 4.4.1 Kubernetes Service Load Balancing

**Service configuration:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: a2a-service
  namespace: a2a-system
spec:
  type: LoadBalancer  # or ClusterIP with Ingress
  sessionAffinity: ClientIP  # For sticky sessions
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
  selector:
    app: a2a-erl
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
```

#### 4.4.2 Ingress Load Balancing

**Ingress with TLS:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: a2a-ingress
  namespace: a2a-system
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  tls:
  - hosts:
    - a2a.example.com
    secretName: a2a-tls
  rules:
  - host: a2a.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: a2a-service
            port:
              number: 8080
```

#### 4.4.3 Global Load Balancing

**Multi-region traffic distribution:**

```bash
# AWS Global Accelerator configuration
resource "aws_globalaccelerator_accelerator" "a2a" {
  name            = "a2a-global"
  ip_address_type = "IPV4"
  enabled         = true
}

resource "aws_globalaccelerator_listener" "a2a" {
  accelerator_arn = aws_globalaccelerator_accelerator.a2a.id
  protocol        = "TCP"
  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "us_west" {
  listener_arn = aws_globalaccelerator_listener.a2a.id
  endpoint_group_region = "us-west-2"
  health_check_interval_seconds = 30
  health_check_path = "/health"

  endpoint_configuration {
    endpoint_id = aws_lb.us_west.arn
    weight      = 100
  }
}
```

---

## 5. Backup and Restore

### 5.1 Backup Strategy

#### 5.1.1 Backup Types

**Configuration Backups:**
- Kubernetes manifests (daily via Git)
- ConfigMaps and Secrets (daily)
- Helm values (versioned in Git)
- Terraform state (automatic S3 versioning)

**Data Backups:**
- Persistent volumes (daily snapshots)
- Database dumps (hourly incremental, daily full)
- Application logs (retained 30 days)
- Metrics data (retained 90 days)

**Backup Schedule:**

| Backup Type | Frequency | Retention | Method |
|-------------|-----------|-----------|--------|
| Config | On change | Indefinite | Git |
| PV Snapshots | Daily | 30 days | Volume snapshots |
| Database | Hourly/Daily | 30 days | pg_dump/automated |
| Logs | Continuous | 30 days | Loki |
| Metrics | Continuous | 90 days | Prometheus |
| Application State | Daily | 7 days | Custom export |

### 5.2 Backup Procedures

#### 5.2.1 Configuration Backup

**Backup Kubernetes resources:**

```bash
# Backup all resources in namespace
kubectl get all,cm,secret,pvc,ingress -n a2a-system -o yaml > a2a-backup-$(date +%Y%m%d).yaml

# Backup specific resources
kubectl get deployment/a2a-deployment -n a2a-system -o yaml > deployment-backup.yaml
kubectl get configmap/a2a-config -n a2a-system -o yaml > configmap-backup.yaml

# Backup with encryption for secrets
kubectl get secret -n a2a-system -o yaml | \
  openssl enc -aes-256-cbc -salt -out secrets-backup-$(date +%Y%m%d).enc

# Commit to Git
git add .
git commit -m "backup: Configuration snapshot $(date +%Y%m%d)"
git push
```

#### 5.2.2 Persistent Volume Backup

**Create volume snapshots:**

```bash
# Using Kubernetes VolumeSnapshot
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: a2a-log-snapshot
  namespace: a2a-system
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: a2a-log-pvc

# Apply snapshot
kubectl apply -f volume-snapshot.yaml

# Verify snapshot
kubectl get volumesnapshot -n a2a-system

# AWS EBS snapshot
aws ec2 create-snapshot \
  --volume-id vol-xxxxx \
  --description "A2A log volume backup $(date +%Y%m%d)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=a2a-backup}]'
```

#### 5.2.3 Database Backup

**PostgreSQL backup (if using):**

```bash
# Full backup
kubectl exec -n a2a-system deployment/postgres -- \
  pg_dump -U a2a_user -d a2a_db -F custom -f /backup/a2a-$(date +%Y%m%d).dump

# Copy backup out
kubectl cp a2a-system/postgres-pod:/backup/a2a-$(date +%Y%m%d).dump \
  ./backups/a2a-$(date +%Y%m%d).dump

# Automated backup with retention
kubectl create cronjob a2a-db-backup -n a2a-system \
  --image=postgres:14 \
  --schedule="0 2 * * *" \
  -- /bin/sh -c 'pg_dump -U $POSTGRES_USER -d $POSTGRES_DB -F custom | \
     aws s3 cp - s3://a2a-backups/db-$(date +%Y%m%d).dump'
```

#### 5.2.4 Application State Backup

**Export application state:**

```bash
# Export Erlang persistent term storage
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_backup:export("/tmp/state-backup.dets")'

# Copy export
kubectl cp a2a-system/a2a-deployment-xxx:/tmp/state-backup.dets \
  ./backups/state-$(date +%Y%m%d).dets

# Backup ETS tables
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_backup:export_ets("/tmp/ets-backup.tab")'
```

#### 5.2.5 Automated Backup Script

```bash
#!/bin/bash
# backup-a2a.sh - Comprehensive backup script

set -euo pipefail

BACKUP_DIR="/backups/a2a/$(date +%Y%m%d)"
NAMESPACE="a2a-system"
S3_BUCKET="s3://a2a-backups"

mkdir -p "$BACKUP_DIR"

# Backup configurations
echo "Backing up configurations..."
kubectl get all,cm,secret,pvc,ingress -n "$NAMESPACE" -o yaml \
  > "$BACKUP_DIR/k8s-resources.yaml"

# Backup persistent volumes
echo "Creating volume snapshots..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: a2a-backup-$(date +%Y%m%d)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: a2a-data-pvc
EOF

# Upload to S3
echo "Uploading to S3..."
aws s3 sync "$BACKUP_DIR" "$S3_BUCKET/$(date +%Y%m%d)/" \
  --storage-class STANDARD_IA

# Cleanup old backups (keep 30 days)
find /backups/a2a -type d -mtime +30 -exec rm -rf {} +

# Send notification
curl -X POST "$SLACK_WEBHOOK" -d "{\"text\":\"A2A backup completed: $(date)\"}"

echo "Backup completed successfully"
```

### 5.3 Restore Procedures

#### 5.3.1 Configuration Restore

**Restore from backup:**

```bash
# Restore all resources
kubectl apply -f a2a-backup-20260206.yaml

# Restore specific resources
kubectl apply -f deployment-backup.yaml
kubectl apply -f configmap-backup.yaml

# Restore secrets (decrypt first)
openssl enc -aes-256-cbc -d -in secrets-backup-20260206.enc | \
  kubectl apply -f -

# Verify restoration
kubectl get all -n a2a-system
kubectl rollout status deployment/a2a-deployment -n a2a-system
```

#### 5.3.2 Persistent Volume Restore

**Restore from snapshot:**

```bash
# Create PVC from snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: a2a-data-pvc-restored
  namespace: a2a-system
spec:
  storageClassName: gp3
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: a2a-backup-20260206
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io

# Apply restoration
kubectl apply -f pvc-restore.yaml

# Update deployment to use restored PVC
kubectl patch deployment a2a-deployment -n a2a-system -p '
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [{
          "name": "data",
          "persistentVolumeClaim": {
            "claimName": "a2a-data-pvc-restored"
          }
        }]
      }
    }
  }
}'
```

#### 5.3.3 Database Restore

**Restore PostgreSQL:**

```bash
# Stop application to prevent writes
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=0

# Restore database
kubectl cp ./backups/a2a-20260206.dump a2a-system/postgres-pod:/tmp/

kubectl exec -n a2a-system deployment/postgres -- \
  pg_restore -U a2a_user -d a2a_db --clean --if-exists \
  /tmp/a2a-20260206.dump

# Verify restoration
kubectl exec -n a2a-system deployment/postgres -- \
  psql -U a2a_user -d a2a_db -c "\dt"

# Restart application
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=2
```

#### 5.3.4 Application State Restore

**Import application state:**

```bash
# Copy backup to pod
kubectl cp ./backups/state-20260206.dets \
  a2a-system/a2a-deployment-xxx:/tmp/state-backup.dets

# Import state
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_backup:import("/tmp/state-backup.dets")'

# Verify import
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_backup:verify_import()'
```

#### 5.3.5 Point-in-Time Restore

**Restore to specific timestamp:**

```bash
# List available backups
aws s3 ls s3://a2a-backups/ --recursive | grep 20260206

# Download specific backup
aws s3 cp s3://a2a-backups/20260206/k8s-resources.yaml ./

# Restore configuration
kubectl apply -f k8s-resources.yaml

# Restore PV from snapshot at specific time
# (Use snapshot created closest to desired timestamp)
```

### 5.4 Verification

#### 5.4.1 Backup Verification

**Test backup integrity:**

```bash
# Verify backup files exist
ls -lh /backups/a2a/$(date +%Y%m%d)/

# Check S3 backup
aws s3 ls s3://a2a-backups/$(date +%Y%m%d)/ --recursive

# Verify snapshot status
kubectl get volumesnapshot -n a2a-system

# Test YAML syntax
kubectl apply --dry-run=client -f a2a-backup-20260206.yaml

# Validate compressed archives
tar -tzf backup.tar.gz > /dev/null
gzip -t backup.tar.gz
```

#### 5.4.2 Restore Testing

**Periodic restore drills:**

```bash
#!/bin/bash
# Monthly restore drill

# Create test namespace
kubectl create namespace a2a-restore-test

# Restore to test namespace
kubectl apply -f a2a-backup-latest.yaml -n a2a-restore-test

# Verify services start
kubectl wait --for=condition=ready pod -l app=a2a-erl \
  -n a2a-restore-test --timeout=300s

# Run smoke tests
kubectl run smoke-test -n a2a-restore-test --rm -i --tty \
  --image=curlimages/curl -- curl http://a2a-service:8080/health

# Cleanup test namespace
kubectl delete namespace a2a-restore-test

# Log results
echo "Restore drill completed: $(date)" >> restore-drill.log
```

---

## 6. Disaster Recovery

### 6.1 Recovery Objectives

**Recovery Time Objective (RTO):**
- Critical systems: 15 minutes
- Production services: 1 hour
- Non-critical services: 4 hours

**Recovery Point Objective (RPO):**
- Configuration: 0 (Git versioned)
- Application data: 1 hour
- Logs: 5 minutes
- Metrics: 1 minute

**Service Level Objectives:**
- Availability: 99.9% (8.76 hours downtime/year)
- Error rate: < 0.1%
- Response time: p95 < 500ms
- Data loss: < 1 hour

### 6.2 Failure Scenarios

#### 6.2.1 Pod Failure

**Automatic recovery:**
- Kubernetes restarts failed pods automatically
- Liveness/readiness probes detect failures
- Health checks trigger pod replacement

**Manual intervention:**

```bash
# Check pod status
kubectl get pods -n a2a-system
kubectl describe pod a2a-deployment-xxx -n a2a-system

# View pod logs
kubectl logs a2a-deployment-xxx -n a2a-system --previous

# Delete unhealthy pod (will be recreated)
kubectl delete pod a2a-deployment-xxx -n a2a-system

# Force reschedule
kubectl rollout restart deployment/a2a-deployment -n a2a-system
```

#### 6.2.2 Node Failure

**Automatic recovery:**
- Kubernetes reschedules pods to healthy nodes
- Node auto-repair (GKE/EKS managed nodes)
- Cluster autoscaler provisions new nodes

**Manual recovery:**

```bash
# Check node status
kubectl get nodes

# Cordon failing node
kubectl cordon node-name

# Drain node
kubectl drain node-name --ignore-daemonsets --delete-emptydir-data

# Replace node (cloud provider specific)
# AWS:
aws ec2 terminate-instances --instance-ids i-xxxxx
# Autoscaling group will replace it

# Verify pods rescheduled
kubectl get pods -n a2a-system -o wide
```

#### 6.2.3 Cluster Failure

**Multi-cluster failover:**

```bash
# Switch to backup cluster
kubectl config use-context backup-cluster

# Verify backup cluster health
kubectl get nodes
kubectl get pods -n a2a-system

# Update DNS to point to backup cluster
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dns-failover.json

# Monitor traffic switchover
kubectl top pods -n a2a-system
```

**Cluster restoration:**

```bash
# Provision new cluster (Terraform)
cd infrastructure/terraform
terraform apply -var-file=production.tfvars

# Restore from backup
kubectl apply -f s3://a2a-backups/latest/k8s-resources.yaml

# Restore persistent volumes
kubectl apply -f pv-restore.yaml

# Verify services
kubectl get all -n a2a-system
kubectl rollout status deployment/a2a-deployment -n a2a-system

# Switch DNS back
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dns-restore.json
```

#### 6.2.4 Data Center Failure

**Geographic failover:**

```bash
# Regional failover procedure
# 1. Detect failure (monitoring alerts)
# 2. Activate backup region

# Switch context to backup region
kubectl config use-context us-east-1

# Verify services running
kubectl get pods -n a2a-system -o wide

# Update global load balancer
terraform apply -target=aws_globalaccelerator_endpoint_group.us_east

# 3. Restore latest data to backup region
aws s3 sync s3://a2a-backups-us-west-2 s3://a2a-backups-us-east-1

# 4. Import application state
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_backup:import_from_s3("us-west-2")'

# 5. Monitor recovery
kubectl top pods -n a2a-system
kubectl logs -n a2a-system -l app=a2a-erl -f
```

#### 6.2.5 Complete System Failure

**Full disaster recovery:**

```bash
# 1. Provision infrastructure from scratch
cd infrastructure/terraform
terraform init
terraform apply -var-file=dr.tfvars

# 2. Configure kubectl
aws eks update-kubeconfig --name a2a-dr-cluster --region us-east-1

# 3. Restore all configurations
aws s3 cp s3://a2a-backups/latest/k8s-resources.yaml ./
kubectl apply -f k8s-resources.yaml

# 4. Restore persistent data
kubectl apply -f pv-restore-all.yaml

# 5. Restore database
kubectl apply -f database-restore.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n a2a-system
kubectl exec -n a2a-system deployment/postgres -- \
  pg_restore -U a2a_user -d a2a_db /backup/latest.dump

# 6. Start application
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=2

# 7. Verify functionality
./scripts/smoke-test.sh

# 8. Update DNS
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dns-dr.json

# 9. Monitor and verify
watch kubectl get pods -n a2a-system
```

### 6.3 Recovery Procedures

#### 6.3.1 Pre-Incident Preparation

**Runbook checklist:**

- [ ] Backup systems verified and tested
- [ ] Contact list updated (on-call, escalation)
- [ ] Recovery credentials accessible
- [ ] Documentation up to date
- [ ] DR infrastructure provisioned and tested
- [ ] Monitoring and alerting configured
- [ ] Team trained on procedures

**Emergency access:**

```bash
# Break-glass credentials stored in:
# - Password manager (1Password, LastPass)
# - Sealed envelope in safe
# - Encrypted file in S3

# Emergency kubectl config
aws s3 cp s3://a2a-emergency/kubeconfig ~/.kube/config-emergency
export KUBECONFIG=~/.kube/config-emergency

# Emergency AWS access
aws s3 cp s3://a2a-emergency/credentials ~/.aws/credentials-emergency
export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials-emergency
```

#### 6.3.2 Incident Response

**Response phases:**

1. **Detection (0-5 minutes)**
   - Alert received via PagerDuty/monitoring
   - Initial assessment of severity
   - Activate incident response team

2. **Assessment (5-15 minutes)**
   - Determine scope and impact
   - Identify affected components
   - Estimate recovery time
   - Declare incident level

3. **Response (15-60 minutes)**
   - Execute recovery procedures
   - Communicate with stakeholders
   - Monitor recovery progress
   - Document actions taken

4. **Recovery (1-4 hours)**
   - Restore full service
   - Verify functionality
   - Resume normal operations
   - Monitor for issues

5. **Post-Incident (1-7 days)**
   - Conduct post-mortem
   - Update documentation
   - Implement preventive measures
   - Test improvements

**Incident communication:**

```bash
# Status page update
curl -X POST https://api.statuspage.io/v1/pages/xxx/incidents \
  -H "Authorization: OAuth xxx" \
  -d '{
    "incident": {
      "name": "A2A Service Degradation",
      "status": "investigating",
      "impact_override": "major",
      "body": "Investigating connectivity issues in us-west-2"
    }
  }'

# Slack notification
curl -X POST $SLACK_WEBHOOK -d '{
  "text": "INCIDENT: A2A service down - Recovery in progress",
  "attachments": [{
    "color": "danger",
    "fields": [
      {"title": "Severity", "value": "P1", "short": true},
      {"title": "Status", "value": "Investigating", "short": true},
      {"title": "ETA", "value": "30 minutes", "short": true}
    ]
  }]
}'
```

#### 6.3.3 Recovery Validation

**Post-recovery checks:**

```bash
# 1. Service health
kubectl get all -n a2a-system
kubectl rollout status deployment/a2a-deployment -n a2a-system

# 2. Endpoint availability
for i in {1..10}; do
  curl -f http://a2a.example.com/health || echo "FAIL"
  sleep 1
done

# 3. Functional testing
./scripts/integration-test.sh

# 4. Performance baseline
kubectl top pods -n a2a-system
curl http://a2a.example.com/metrics | grep a2a_request_duration

# 5. Data integrity
kubectl exec -n a2a-system deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_health:check_data_integrity()'

# 6. Log review
kubectl logs -n a2a-system -l app=a2a-erl --since=1h | grep -i error

# 7. Monitoring verification
# Check Grafana dashboards
# Verify alerts resolved
# Confirm metrics collecting
```

### 6.4 Testing

#### 6.4.1 Chaos Engineering

**Planned failure injection:**

```bash
# Install chaos-mesh
kubectl apply -f https://mirrors.chaos-mesh.org/v2.5.0/chaos-mesh.yaml

# Pod failure test
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure-test
  namespace: a2a-system
spec:
  action: pod-failure
  mode: one
  selector:
    namespaces:
      - a2a-system
    labelSelectors:
      app: a2a-erl
  duration: "30s"

# Network partition test
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-partition
  namespace: a2a-system
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - a2a-system
    labelSelectors:
      app: a2a-erl
  duration: "1m"

# Apply chaos
kubectl apply -f chaos-tests/

# Monitor recovery
watch kubectl get pods -n a2a-system
```

#### 6.4.2 DR Drills

**Quarterly DR exercise:**

```bash
#!/bin/bash
# dr-drill.sh - Disaster recovery drill

set -euo pipefail

echo "=== DR Drill Starting: $(date) ==="

# 1. Simulate failure
echo "Simulating primary region failure..."
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=0

# 2. Activate DR
echo "Activating DR procedures..."
kubectl config use-context dr-cluster
terraform apply -target=module.dr_cluster -auto-approve

# 3. Restore data
echo "Restoring from backup..."
./scripts/restore-from-backup.sh --region us-east-1

# 4. Verify services
echo "Verifying service health..."
kubectl wait --for=condition=ready pod -l app=a2a-erl -n a2a-system --timeout=300s

# 5. Run tests
echo "Running smoke tests..."
./scripts/smoke-test.sh

# 6. Switch DNS (simulation)
echo "DNS failover simulation..."
echo "Would update Route53 to point to DR cluster"

# 7. Monitor
echo "Monitoring DR cluster..."
kubectl top pods -n a2a-system

# 8. Document results
echo "=== DR Drill Completed: $(date) ===" | tee -a dr-drill.log
echo "Recovery time: $SECONDS seconds" | tee -a dr-drill.log

# 9. Cleanup (restore primary)
echo "Restoring primary cluster..."
kubectl config use-context primary-cluster
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=2

echo "DR drill complete. Review dr-drill.log for details."
```

#### 6.4.3 Backup Restore Testing

**Monthly backup validation:**

```bash
#!/bin/bash
# validate-backups.sh

BACKUP_DATE=$(date -d "yesterday" +%Y%m%d)

# Test configuration restore
kubectl create namespace a2a-test
kubectl apply -f backups/$BACKUP_DATE/k8s-resources.yaml -n a2a-test

# Test PV restore
kubectl apply -f backups/$BACKUP_DATE/pv-snapshot.yaml -n a2a-test

# Test database restore
kubectl exec -n a2a-test deployment/postgres -- \
  pg_restore -U test -d test_db /backup/$BACKUP_DATE.dump

# Verify integrity
kubectl exec -n a2a-test deployment/a2a-deployment -- \
  bin/a2a_erl eval 'a2a_health:check_all()'

# Cleanup
kubectl delete namespace a2a-test

# Log results
if [ $? -eq 0 ]; then
  echo "Backup validation SUCCESS: $BACKUP_DATE" >> backup-validation.log
else
  echo "Backup validation FAILED: $BACKUP_DATE" >> backup-validation.log
  # Send alert
  curl -X POST $SLACK_WEBHOOK -d '{"text":"Backup validation failed!"}'
fi
```

---

## Appendix

### A. Quick Reference

**Common Commands:**

```bash
# Status checks
kubectl get all -n a2a-system
kubectl top pods -n a2a-system
kubectl logs -n a2a-system -l app=a2a-erl --tail=100 -f

# Scaling
kubectl scale deployment/a2a-deployment -n a2a-system --replicas=N

# Updates
kubectl set image deployment/a2a-deployment -n a2a-system a2a-erl=a2a-erl:vX.Y.Z
kubectl rollout status deployment/a2a-deployment -n a2a-system
kubectl rollout undo deployment/a2a-deployment -n a2a-system

# Debugging
kubectl describe pod <pod-name> -n a2a-system
kubectl exec -n a2a-system deployment/a2a-deployment -- bin/a2a_erl versions
kubectl debug -n a2a-system -it pod/<pod-name> --image=busybox

# Backups
kubectl get all,cm,secret,pvc -n a2a-system -o yaml > backup.yaml
kubectl apply -f volume-snapshot.yaml
```

### B. Monitoring Dashboards

**Grafana Dashboard URLs:**
- Cluster Overview: `/d/a2a-cluster/`
- Application Performance: `/d/a2a-app/`
- Erlang VM Metrics: `/d/a2a-erlang/`
- Resource Utilization: `/d/a2a-resources/`

**Prometheus Queries:**
```promql
# Request rate
rate(a2a_requests_total[5m])

# Error rate
rate(a2a_errors_total[5m]) / rate(a2a_requests_total[5m])

# Latency
histogram_quantile(0.95, rate(a2a_request_duration_seconds_bucket[5m]))

# Memory usage
erlang_vm_memory_bytes_total / node_memory_MemTotal_bytes
```

### C. Escalation Contacts

**Incident Severity Levels:**

| Level | Description | Response Time | Escalation |
|-------|-------------|---------------|------------|
| P0 | Complete outage | Immediate | CTO, VP Eng |
| P1 | Major degradation | 15 minutes | Engineering Director |
| P2 | Minor degradation | 1 hour | Team Lead |
| P3 | Non-critical issue | 4 hours | On-call Engineer |

**On-Call Rotation:**
- Primary: oncall-primary@example.com
- Secondary: oncall-secondary@example.com
- Escalation: engineering-leads@example.com

### D. Related Documentation

- [A2A Protocol Specification](specification.md)
- [Infrastructure Terraform README](../infrastructure/terraform/README.md)
- [Release Management Guide](../erlang/a2a_erl/RELEASE_GUIDE.md)
- [ConfigMap and Secret Guide](../erlang/a2a_erl/k8s/CONFIGMAP_SECRET_GUIDE.md)
- [HotCI Integration](../erlang/a2a_erl/docs/HOTCI_INTEGRATION.md)

### E. Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-06 | 1.0.0 | Initial release |

---

**Document Control:**
- **Owner:** Infrastructure Team
- **Review Cycle:** Quarterly
- **Last Updated:** 2026-02-06
- **Next Review:** 2026-05-06
