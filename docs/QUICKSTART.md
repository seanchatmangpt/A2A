# Fortune 5 Enterprise Deployment - Quick Start Guide

This guide provides step-by-step instructions for deploying the A2A Protocol in a Fortune 5 enterprise environment with multi-region infrastructure, advanced security, compliance controls, and high availability.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Pre-Deployment Configuration](#pre-deployment-configuration)
4. [Infrastructure Deployment](#infrastructure-deployment)
5. [Application Deployment](#application-deployment)
6. [Verification](#verification)
7. [Post-Deployment Configuration](#post-deployment-configuration)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

Install the following tools before starting:

```bash
# Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud version

# Terraform (v1.5.0 or later)
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version

# kubectl
gcloud components install kubectl
kubectl version --client

# Helm (v3.12.0 or later)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### GCP Project Requirements

1. **Active GCP Project** with billing enabled
2. **Required APIs** enabled:
   ```bash
   gcloud services enable \
     compute.googleapis.com \
     container.googleapis.com \
     sqladmin.googleapis.com \
     servicenetworking.googleapis.com \
     cloudresourcemanager.googleapis.com \
     iam.googleapis.com \
     storage-api.googleapis.com \
     logging.googleapis.com \
     monitoring.googleapis.com \
     cloudkms.googleapis.com \
     secretmanager.googleapis.com \
     dns.googleapis.com \
     binaryauthorization.googleapis.com
   ```

3. **IAM Permissions**: Your account needs the following roles:
   - `roles/owner` OR all of these roles:
     - `roles/compute.networkAdmin`
     - `roles/container.admin`
     - `roles/iam.serviceAccountAdmin`
     - `roles/resourcemanager.projectIamAdmin`
     - `roles/storage.admin`
     - `roles/cloudsql.admin`
     - `roles/logging.admin`
     - `roles/monitoring.admin`

4. **Resource Quotas**: Verify quotas for:
   - GKE clusters: At least 5 regional clusters
   - CPU: 150 vCPUs per region (minimum)
   - Persistent Disk SSD: 5TB total
   - In-use IP addresses: 50 per region
   - Cloud SQL instances: 5 instances

### Domain and SSL Certificates

1. **Domain Name**: Registered domain for A2A service (e.g., `api.a2a.example.com`)
2. **SSL Certificates**: Either:
   - Use Google-managed certificates (recommended)
   - Provide your own certificates in PEM format

### Network Requirements

1. **Corporate Network CIDR**: For master authorized networks
2. **VPN/Interconnect**: If connecting to on-premises infrastructure
3. **Firewall Rules**: Allow egress to GCP APIs and health check ranges

## Architecture Overview

### Multi-Region Infrastructure

The Fortune 5 deployment spans 5 geographic regions:

- **Primary**: us-central1 (Iowa)
- **Secondary**: us-east1 (South Carolina) - Failover target
- **Tertiary**: us-west1 (Oregon)
- **Europe**: europe-west1 (Belgium)
- **Asia**: asia-east1 (Taiwan)

### Key Components

1. **Global VPC Network** with GLOBAL routing mode
2. **Regional GKE Clusters** with private nodes (3-50 nodes each)
3. **Global HTTPS Load Balancer** with Cloud CDN and Cloud Armor
4. **Cloud SQL PostgreSQL 15** with cross-region replicas
5. **Multi-region Cloud Storage** for data and audit logs
6. **Comprehensive Audit Logging** for compliance (SOX, PCI-DSS, HIPAA, ISO 27001)
7. **Identity-Aware Proxy (IAP)** for enterprise SSO
8. **Cloud KMS** for encryption at rest
9. **Binary Authorization** for container security
10. **Workload Identity** for secure GKE-to-GCP service authentication

## Pre-Deployment Configuration

### 1. Set Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export DOMAIN="a2a.example.com"
export API_DOMAIN="api.${DOMAIN}"
export CLUSTER_NAME="a2a-gke-primary"
export NAMESPACE="a2a-production"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
```

### 2. Create Service Account for Terraform

```bash
gcloud iam service-accounts create terraform-sa \
  --display-name "Terraform Service Account"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/editor"

gcloud iam service-accounts keys create terraform-key.json \
  --iam-account=terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com

export GOOGLE_APPLICATION_CREDENTIALS="${PWD}/terraform-key.json"
```

### 3. Prepare SSL Certificates

#### Option A: Self-Signed Certificates (Development Only)

```bash
cd terraform/certs
mkdir -p certs

# Generate private key
openssl genrsa -out certs/private.key 2048

# Generate self-signed certificate
openssl req -new -x509 -key certs/private.key -out certs/certificate.crt -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=${API_DOMAIN}"
```

#### Option B: Google-Managed Certificates (Production Recommended)

No action needed - certificates will be automatically provisioned during deployment.

### 4. Configure Terraform Variables

```bash
cd terraform
cat > terraform.tfvars <<EOF
project_id = "${PROJECT_ID}"
region     = "${REGION}"
domain     = "${DOMAIN}"

# Network configuration
enable_private_cluster = true
master_ipv4_cidr_block = "172.16.0.0/28"

# GKE configuration
gke_version            = "1.29"
node_machine_type      = "n2-standard-8"
min_node_count         = 3
max_node_count         = 50

# Cloud SQL configuration
db_tier                = "db-custom-8-32768"
db_availability_type   = "REGIONAL"
db_backup_enabled      = true
db_pitr_enabled        = true

# Security configuration
enable_binary_authorization = true
enable_workload_identity    = true
enable_cloud_armor          = true
enable_iap                  = true

# Compliance configuration
audit_log_retention_days = 2555  # 7 years
enable_data_access_logs  = true
enable_vpc_flow_logs     = true

# High availability
enable_multi_region      = true
enable_cross_region_sql  = true

# Monitoring
enable_stackdriver       = true
enable_cloud_logging     = true
enable_cloud_monitoring  = true
EOF
```

## Infrastructure Deployment

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init

# Validate configuration
terraform validate

# Review planned changes
terraform plan -out=tfplan
```

### Step 2: Deploy Core Infrastructure

Deploy in stages to manage dependencies:

```bash
# Stage 1: Network infrastructure
terraform apply -target=google_compute_network.global_vpc \
  -target=google_compute_subnetwork.regional_subnets \
  -target=google_compute_router.regional_routers \
  -target=google_compute_router_nat.regional_nat \
  -auto-approve

# Stage 2: GKE clusters (this takes 10-15 minutes per cluster)
terraform apply -target=google_container_cluster.regional_clusters \
  -target=google_container_node_pool.regional_node_pools \
  -auto-approve

# Stage 3: Cloud SQL databases
terraform apply -target=google_sql_database_instance.primary_sql \
  -target=google_sql_database_instance.replica_sql_secondary \
  -target=google_sql_database_instance.replica_sql_europe \
  -auto-approve

# Stage 4: Load balancer and networking
terraform apply -target=google_compute_global_address.global_lb_ip \
  -target=google_compute_managed_ssl_certificate.global_cert \
  -target=google_compute_backend_service.global_backend \
  -target=google_compute_url_map.global_url_map \
  -target=google_compute_target_https_proxy.https_proxy \
  -target=google_compute_global_forwarding_rule.https_forwarding_rule \
  -auto-approve

# Stage 5: Security and compliance
terraform apply -target=google_compute_security_policy.enterprise_security_policy \
  -target=google_storage_bucket.audit_logs_primary \
  -target=google_logging_project_sink.admin_activity_storage \
  -auto-approve

# Stage 6: Apply remaining resources
terraform apply -auto-approve
```

### Step 3: Capture Outputs

```bash
# Save important outputs
terraform output -json > terraform-outputs.json

# Display key information
echo "Global Load Balancer IP:"
terraform output global_load_balancer_ip

echo "Regional Cluster Names:"
terraform output regional_cluster_names

echo "Primary SQL Instance:"
terraform output primary_sql_instance

echo "DNS Nameservers:"
terraform output dns_nameservers
```

### Step 4: Configure DNS

Update your domain's DNS records with the nameservers from the output:

```bash
# Get nameservers
terraform output dns_nameservers

# Update your domain registrar with these nameservers
# Or create an A record pointing to the load balancer IP
```

Wait for DNS propagation (can take 5-60 minutes):

```bash
watch -n 10 "dig $API_DOMAIN +short"
```

## Application Deployment

### Step 1: Configure kubectl for Multi-Region

```bash
# Get credentials for all regional clusters
declare -a REGIONS=("primary" "secondary" "tertiary" "europe" "asia")

for region in "${REGIONS[@]}"; do
  CLUSTER_NAME=$(terraform output -json regional_cluster_names | jq -r ".${region}")
  CLUSTER_REGION=$(terraform output -json | jq -r ".regions.value.${region}.name")

  gcloud container clusters get-credentials $CLUSTER_NAME \
    --region=$CLUSTER_REGION \
    --project=$PROJECT_ID

  # Rename context for clarity
  kubectl config rename-context \
    "gke_${PROJECT_ID}_${CLUSTER_REGION}_${CLUSTER_NAME}" \
    "a2a-${region}"
done

# Set primary cluster as default
kubectl config use-context a2a-primary
```

### Step 2: Create Kubernetes Namespace

```bash
# Create namespace in all clusters
for region in "${REGIONS[@]}"; do
  kubectl --context=a2a-${region} create namespace $NAMESPACE
  kubectl --context=a2a-${region} label namespace $NAMESPACE \
    environment=production \
    region=${region} \
    tier=fortune5
done
```

### Step 3: Configure Workload Identity

```bash
# Create Kubernetes service account
kubectl --namespace=$NAMESPACE create serviceaccount a2a-sa

# Create GCP service account
gcloud iam service-accounts create a2a-workload \
  --display-name="A2A Workload Identity Service Account"

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/a2a-sa]"

# Annotate Kubernetes service account
kubectl --namespace=$NAMESPACE annotate serviceaccount a2a-sa \
  iam.gke.io/gcp-service-account=a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com

# Grant necessary permissions to GCP service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"
```

### Step 4: Create Secrets

```bash
# Create database password secret
DB_PASSWORD=$(openssl rand -base64 32)
kubectl --namespace=$NAMESPACE create secret generic db-credentials \
  --from-literal=username=a2a_user \
  --from-literal=password=$DB_PASSWORD

# Store in GCP Secret Manager for backup
echo -n $DB_PASSWORD | gcloud secrets create a2a-db-password --data-file=-

# Create API keys
API_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -base64 64)
ENCRYPTION_KEY=$(openssl rand -base64 32)

kubectl --namespace=$NAMESPACE create secret generic api-credentials \
  --from-literal=api-key=$API_KEY \
  --from-literal=jwt-secret=$JWT_SECRET \
  --from-literal=encryption-key=$ENCRYPTION_KEY

# Create TLS secret (if using custom certificates)
kubectl --namespace=$NAMESPACE create secret tls a2a-tls \
  --cert=../terraform/certs/certificate.crt \
  --key=../terraform/certs/private.key
```

### Step 5: Configure Helm Values

```bash
cd ../helm
cat > values-production.yaml <<EOF
# Production Fortune 5 configuration
replicaCount: 5

image:
  registry: gcr.io
  repository: ${PROJECT_ID}/a2a
  tag: "1.0.0"
  pullPolicy: IfNotPresent

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 1Gi

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: "gce"
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "a2a-global-lb-ip"
    networking.gke.io/managed-certificates: "a2a-managed-cert"
    kubernetes.io/ingress.allow-http: "true"
  hosts:
    - host: ${API_DOMAIN}
      paths:
        - path: /
          pathType: Prefix
          servicePort: 80
  ssl:
    enabled: true
    staticIpName: "a2a-global-lb-ip"
  backendConfig:
    enabled: true
    healthCheck:
      checkIntervalSec: 10
      timeoutSec: 5
      healthyThreshold: 2
      unhealthyThreshold: 3
      type: HTTP
      requestPath: /health
      port: 8080
    connectionDraining:
      drainingTimeoutSec: 300
    sessionAffinity:
      affinityType: CLIENT_IP
      affinityCookieTtlSec: 3600
    cdn:
      enabled: true
      cachePolicy:
        includeHost: true
        includeProtocol: true
        includeQueryString: false
    iap:
      enabled: true
      oauthclientCredentials:
        secretName: oauth-client-secret
    securityPolicy:
      name: "a2a-enterprise-security-policy"

serviceAccount:
  create: true
  annotations:
    iam.gke.io/gcp-service-account: a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com
  name: "a2a-sa"

autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 50
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

persistence:
  enabled: true
  storageClass: "standard-rwo"
  accessMode: ReadWriteOnce
  size: 100Gi

secrets:
  gcpSecretManager:
    enabled: true
    projectID: "${PROJECT_ID}"
    serviceAccount: "a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com"
    clusterLocation: "${REGION}"
    secrets:
      - secretKey: "db-password"
        remoteKey: "a2a-db-password"
        version: "latest"
  database:
    enabled: true
    host: "$(terraform output -json | jq -r .primary_sql_instance.value)"
    port: 5432
    name: "a2a_production"
    username: "a2a_user"
    sslMode: "require"

gcp:
  projectId: "${PROJECT_ID}"
  region: "${REGION}"
  workloadIdentity: true
  stackdriver: true
  cloudLogging: true
  cloudMonitoring: true

monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
    scrapeTimeout: 10s

security:
  enabled: true
  authentication:
    enabled: true
    method: "jwt"
  authorization:
    enabled: true
    method: "rbac"
  tls:
    enabled: true
    verify: true

networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: ${NAMESPACE}
      - podSelector:
          matchLabels:
            app: a2a
  egress:
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: TCP
        port: 443
      - protocol: TCP
        port: 5432

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app
              operator: In
              values:
                - a2a
        topologyKey: kubernetes.io/hostname

global:
  environment: "production"

logging:
  level: "info"
  format: "json"
  output: "stdout"

tracing:
  enabled: true
  provider: "stackdriver"
  samplingRate: 0.1
EOF
```

### Step 6: Deploy Application with Helm

```bash
# Add Helm repo (if external charts are needed)
helm repo add stable https://charts.helm.sh/stable
helm repo update

# Deploy to primary cluster
helm upgrade --install a2a . \
  --namespace=$NAMESPACE \
  --values=values.yaml \
  --values=values-production.yaml \
  --create-namespace \
  --wait \
  --timeout=10m \
  --kube-context=a2a-primary

# Deploy to secondary regions (for high availability)
for region in "secondary" "tertiary" "europe" "asia"; do
  helm upgrade --install a2a . \
    --namespace=$NAMESPACE \
    --values=values.yaml \
    --values=values-production.yaml \
    --kube-context=a2a-${region} \
    --wait \
    --timeout=10m
done
```

### Step 7: Verify Deployment

```bash
# Check pod status
kubectl --namespace=$NAMESPACE get pods

# Check service status
kubectl --namespace=$NAMESPACE get services

# Check ingress status
kubectl --namespace=$NAMESPACE get ingress

# View logs
kubectl --namespace=$NAMESPACE logs -l app=a2a --tail=50

# Check horizontal pod autoscaler
kubectl --namespace=$NAMESPACE get hpa
```

## Verification

### 1. Health Check Verification

```bash
# Wait for load balancer to be ready (can take 5-10 minutes)
LB_IP=$(terraform output -raw global_load_balancer_ip)

# Test health endpoint
curl -v http://${LB_IP}/health

# Test with domain (after DNS propagation)
curl -v https://${API_DOMAIN}/health

# Expected response:
# {"status": "healthy", "timestamp": "2026-02-06T12:00:00Z"}
```

### 2. SSL/TLS Verification

```bash
# Check SSL certificate
openssl s_client -connect ${API_DOMAIN}:443 -servername ${API_DOMAIN}

# Verify certificate details
echo | openssl s_client -connect ${API_DOMAIN}:443 -servername ${API_DOMAIN} 2>/dev/null | openssl x509 -noout -dates -subject -issuer

# Test HTTPS endpoint
curl -v https://${API_DOMAIN}/ready
```

### 3. Multi-Region Verification

```bash
# Verify pods in all regions
for region in "${REGIONS[@]}"; do
  echo "=== Region: ${region} ==="
  kubectl --context=a2a-${region} --namespace=$NAMESPACE get pods
  echo ""
done

# Check load balancer backend health
gcloud compute backend-services get-health a2a-global-backend --global
```

### 4. Database Connectivity

```bash
# Test Cloud SQL connection from pod
POD_NAME=$(kubectl --namespace=$NAMESPACE get pods -l app=a2a -o jsonpath='{.items[0].metadata.name}')

kubectl --namespace=$NAMESPACE exec -it $POD_NAME -- sh -c "
  psql -h /cloudsql/${PROJECT_ID}:${REGION}:a2a-sql-primary -U a2a_user -d a2a_production -c 'SELECT version();'
"
```

### 5. Workload Identity Verification

```bash
# Verify workload identity binding
kubectl --namespace=$NAMESPACE exec -it $POD_NAME -- curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

# Should return: a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com
```

### 6. Cloud Armor and Security Policy Verification

```bash
# Check security policy
gcloud compute security-policies describe a2a-enterprise-security-policy

# Test rate limiting (should block after threshold)
for i in {1..1100}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://${API_DOMAIN}/health
done

# Expected: First 1000 requests return 200, subsequent requests return 429
```

### 7. Monitoring and Logging Verification

```bash
# Check if logs are flowing
gcloud logging read "resource.type=k8s_cluster AND resource.labels.cluster_name=a2a-gke-primary" \
  --limit=10 \
  --format=json

# Check if metrics are being collected
gcloud monitoring metrics-descriptors list --filter="metric.type=kubernetes.io/container/cpu/core_usage_time"

# View audit logs
gcloud logging read "logName:cloudaudit.googleapis.com" \
  --limit=10 \
  --format=json
```

### 8. Compliance Verification

```bash
# Verify audit log sinks
gcloud logging sinks list

# Check BigQuery datasets for audit logs
bq ls --project_id=$PROJECT_ID

# Verify data is flowing to audit log buckets
gsutil ls gs://${PROJECT_ID}-audit-logs-primary/
gsutil ls gs://${PROJECT_ID}-audit-logs-secondary/

# Check Pub/Sub topics for SIEM integration
gcloud pubsub topics list
```

### 9. API Functionality Test

```bash
# Test A2A agent discovery endpoint
curl -X GET https://${API_DOMAIN}/api/v1/agents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}"

# Test agent registration
curl -X POST https://${API_DOMAIN}/api/v1/agents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "name": "test-agent",
    "version": "1.0.0",
    "capabilities": ["text", "files"],
    "endpoint": "https://test-agent.example.com"
  }'

# Test task creation
curl -X POST https://${API_DOMAIN}/api/v1/tasks \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "agent_id": "test-agent",
    "action": "process",
    "parameters": {
      "input": "test data"
    }
  }'
```

### 10. Performance and Scalability Test

```bash
# Install load testing tool
sudo apt-get install apache2-utils -y

# Run basic load test
ab -n 10000 -c 100 -H "Authorization: Bearer ${API_KEY}" \
  https://${API_DOMAIN}/health

# Watch HPA scaling
watch -n 5 "kubectl --namespace=$NAMESPACE get hpa"

# Monitor pod autoscaling
watch -n 5 "kubectl --namespace=$NAMESPACE get pods | grep a2a"
```

## Post-Deployment Configuration

### 1. Configure Identity-Aware Proxy (IAP)

```bash
# Create OAuth consent screen (do this once in GCP Console)
# Navigation: APIs & Services > OAuth consent screen

# Create OAuth 2.0 credentials
gcloud iap oauth-brands create --application_title="A2A Protocol" --support_email="support@${DOMAIN}"

# Get brand name
BRAND=$(gcloud iap oauth-brands list --format="value(name)")

# Create OAuth client
gcloud iap oauth-clients create $BRAND --display_name="A2A IAP Client"

# Get client ID and secret
CLIENT_ID=$(gcloud iap oauth-clients list $BRAND --format="value(name)" | cut -d'/' -f4)
CLIENT_SECRET=$(gcloud iap oauth-clients describe $CLIENT_ID --brand=$BRAND --format="value(secret)")

# Create Kubernetes secret
kubectl --namespace=$NAMESPACE create secret generic oauth-client-secret \
  --from-literal=client_id=$CLIENT_ID \
  --from-literal=client_secret=$CLIENT_SECRET

# Enable IAP on backend service
gcloud compute backend-services update a2a-global-backend \
  --global \
  --iap=enabled,oauth2-client-id=$CLIENT_ID,oauth2-client-secret=$CLIENT_SECRET

# Add IAP policy bindings
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service=a2a-global-backend \
  --member=domain:${DOMAIN} \
  --role=roles/iap.httpsResourceAccessor
```

### 2. Configure SLI/SLO Monitoring

```bash
# Create SLI for availability
gcloud slo create \
  --service=a2a-global-backend \
  --display-name="A2A API Availability" \
  --goal=0.999 \
  --calendar-period=month \
  --request-based-sli \
  --sli-good-total-ratio-threshold-filter='resource.type="https_lb_rule" AND metric.type="loadbalancing.googleapis.com/https/request_count" AND metric.labels.response_code_class="2xx"' \
  --sli-total-ratio-threshold-filter='resource.type="https_lb_rule" AND metric.type="loadbalancing.googleapis.com/https/request_count"'

# Create SLI for latency
gcloud slo create \
  --service=a2a-global-backend \
  --display-name="A2A API Latency" \
  --goal=0.99 \
  --calendar-period=month \
  --request-based-sli \
  --latency-threshold=500ms

# Create alerting policy for SLO violations
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="A2A SLO Violation Alert" \
  --condition-display-name="SLO Burn Rate" \
  --condition-threshold-value=0.001 \
  --condition-threshold-duration=300s
```

### 3. Configure Backup and Disaster Recovery

```bash
# Enable automated backups for Cloud SQL
gcloud sql instances patch a2a-sql-primary \
  --backup-start-time=02:00 \
  --enable-bin-log

# Create GKE cluster backup
gcloud beta container backup-restore backup-plans create a2a-backup-plan \
  --project=$PROJECT_ID \
  --location=$REGION \
  --cluster=projects/$PROJECT_ID/locations/$REGION/clusters/a2a-gke-primary \
  --all-namespaces \
  --include-secrets \
  --include-volume-data \
  --backup-schedule-cron="0 2 * * *" \
  --backup-retention-days=30

# Create cross-region bucket replication for audit logs
gsutil replication set \
  gs://${PROJECT_ID}-audit-logs-primary \
  gs://${PROJECT_ID}-audit-logs-secondary
```

### 4. Configure Alerting

```bash
# Create notification channel (email)
gcloud alpha monitoring channels create \
  --display-name="Security Team" \
  --type=email \
  --channel-labels=email_address=security@${DOMAIN}

CHANNEL_ID=$(gcloud alpha monitoring channels list --filter="displayName:'Security Team'" --format="value(name)")

# Create alert for high error rate
gcloud alpha monitoring policies create \
  --notification-channels=$CHANNEL_ID \
  --display-name="High Error Rate Alert" \
  --condition-display-name="Error rate > 5%" \
  --condition-threshold-value=0.05 \
  --condition-threshold-duration=300s \
  --condition-filter='resource.type="k8s_pod" AND metric.type="logging.googleapis.com/user/error_count"'

# Create alert for unauthorized access attempts
gcloud alpha monitoring policies create \
  --notification-channels=$CHANNEL_ID \
  --display-name="Unauthorized Access Alert" \
  --condition-display-name="Failed auth attempts" \
  --condition-threshold-value=10 \
  --condition-threshold-duration=60s \
  --condition-filter='metric.type="logging.googleapis.com/user/unauthorized-access-attempts"'

# Create alert for resource exhaustion
gcloud alpha monitoring policies create \
  --notification-channels=$CHANNEL_ID \
  --display-name="Resource Exhaustion Alert" \
  --condition-display-name="CPU > 90%" \
  --condition-threshold-value=0.9 \
  --condition-threshold-duration=300s \
  --condition-filter='resource.type="k8s_pod" AND metric.type="kubernetes.io/pod/cpu/core_usage_time"'
```

### 5. Configure SIEM Integration

```bash
# Configure log export to external SIEM (Splunk/QRadar/Sentinel)
# Option 1: Pub/Sub pull subscription for SIEM
gcloud pubsub subscriptions create siem-audit-logs-pull \
  --topic=siem-audit-logs \
  --ack-deadline=600 \
  --message-retention-duration=7d

# Option 2: Push subscription to SIEM endpoint
gcloud pubsub subscriptions create siem-audit-logs-push \
  --topic=siem-audit-logs \
  --push-endpoint=https://your-siem-endpoint.example.com/ingest \
  --push-auth-service-account=siem-ingestion@${PROJECT_ID}.iam.gserviceaccount.com

# Option 3: Cloud Storage to SIEM via scheduled transfer
# Your SIEM can pull from gs://${PROJECT_ID}-audit-logs-primary/
```

### 6. Configure Binary Authorization

```bash
# Create attestor for container signing
gcloud container binauthz attestors create a2a-attestor \
  --attestation-authority-note=a2a-attestor-note \
  --attestation-authority-note-project=$PROJECT_ID

# Create signing key
gcloud kms keyrings create a2a-binauthz \
  --location=global

gcloud kms keys create a2a-signer \
  --location=global \
  --keyring=a2a-binauthz \
  --purpose=asymmetric-signing \
  --default-algorithm=rsa-sign-pkcs1-4096-sha512

# Add attestor public key
gcloud container binauthz attestors public-keys add \
  --attestor=a2a-attestor \
  --keyversion=1 \
  --keyversion-key=a2a-signer \
  --keyversion-keyring=a2a-binauthz \
  --keyversion-location=global \
  --keyversion-project=$PROJECT_ID

# Create Binary Authorization policy
cat > /tmp/binauthz-policy.yaml <<EOF
globalPolicyEvaluationMode: ENABLE
defaultAdmissionRule:
  requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/a2a-attestor
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF

gcloud container binauthz policy import /tmp/binauthz-policy.yaml
```

### 7. Configure Cost Optimization

```bash
# Set up budget alerts
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="A2A Production Budget" \
  --budget-amount=10000 \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=75 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100

# Enable committed use discounts (requires manual review)
# Navigate to: Compute Engine > Committed use discounts

# Enable sustained use discounts (automatic)
# Already enabled by default on GCP

# Set up preemptible nodes for non-critical workloads (if applicable)
gcloud container node-pools create preemptible-pool \
  --cluster=a2a-gke-primary \
  --region=$REGION \
  --preemptible \
  --num-nodes=2 \
  --node-labels=workload-type=batch
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Pods Not Starting

```bash
# Check pod status
kubectl --namespace=$NAMESPACE describe pod POD_NAME

# Common issues:
# - Image pull errors: Verify image exists in GCR
# - Resource quota: Check namespace resource limits
# - ConfigMap/Secret missing: Verify all secrets are created
# - Workload Identity: Verify service account annotations

# Fix image pull issues
docker pull gcr.io/${PROJECT_ID}/a2a:1.0.0
docker tag gcr.io/${PROJECT_ID}/a2a:1.0.0 gcr.io/${PROJECT_ID}/a2a:latest
docker push gcr.io/${PROJECT_ID}/a2a:latest
```

#### 2. Load Balancer Not Accessible

```bash
# Check ingress status
kubectl --namespace=$NAMESPACE describe ingress a2a-ingress

# Verify backend health
gcloud compute backend-services get-health a2a-global-backend --global

# Check firewall rules
gcloud compute firewall-rules list --filter="name~'a2a'"

# Verify health check endpoint
kubectl --namespace=$NAMESPACE port-forward POD_NAME 8080:8080
curl http://localhost:8080/health
```

#### 3. SSL Certificate Not Provisioning

```bash
# Check managed certificate status
gcloud compute ssl-certificates describe a2a-global-cert

# Common issues:
# - DNS not propagated: Wait 24-48 hours
# - Domain not verified: Verify domain ownership
# - Certificate quota exceeded: Request quota increase

# Temporary workaround: Use self-signed certificate
kubectl --namespace=$NAMESPACE create secret tls a2a-tls \
  --cert=../terraform/certs/certificate.crt \
  --key=../terraform/certs/private.key
```

#### 4. Database Connection Failures

```bash
# Verify Cloud SQL proxy is running
kubectl --namespace=$NAMESPACE get pods -l app=cloud-sql-proxy

# Test connection from pod
kubectl --namespace=$NAMESPACE exec -it POD_NAME -- sh -c "
  nc -zv localhost 5432
"

# Check Cloud SQL instance status
gcloud sql instances describe a2a-sql-primary

# Verify Workload Identity permissions
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com"
```

#### 5. Workload Identity Not Working

```bash
# Verify service account annotation
kubectl --namespace=$NAMESPACE get serviceaccount a2a-sa -o yaml

# Verify IAM binding
gcloud iam service-accounts get-iam-policy \
  a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com

# Re-bind if necessary
gcloud iam service-accounts add-iam-policy-binding \
  a2a-workload@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/a2a-sa]"
```

#### 6. High Latency or Performance Issues

```bash
# Check resource utilization
kubectl --namespace=$NAMESPACE top pods

# Check HPA status
kubectl --namespace=$NAMESPACE get hpa

# Scale manually if needed
kubectl --namespace=$NAMESPACE scale deployment a2a --replicas=10

# Check Cloud CDN hit rate
gcloud compute backend-services describe a2a-global-backend --global

# Enable Cloud CDN if not already
gcloud compute backend-services update a2a-global-backend \
  --enable-cdn \
  --global
```

#### 7. Audit Logs Not Flowing

```bash
# Check log sink status
gcloud logging sinks describe admin-activity-to-storage

# Verify log sink permissions
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/logging.logWriter"

# Test log generation
gcloud logging write test-log "Test audit log entry" --severity=INFO

# Check BigQuery dataset
bq query --use_legacy_sql=false "
  SELECT COUNT(*) as log_count
  FROM \`${PROJECT_ID}.audit_logs.*\`
  WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
"
```

#### 8. Cross-Region Replication Issues

```bash
# Check SQL replica status
gcloud sql instances describe a2a-sql-replica-secondary

# Check replication lag
gcloud sql instances describe a2a-sql-replica-secondary \
  --format="value(replicaConfiguration.mysqlReplicaConfiguration.replicationLag)"

# Force failover test (CAUTION: Production impact)
gcloud sql instances failover a2a-sql-primary --async
```

#### 9. Binary Authorization Blocking Deployments

```bash
# Check policy
gcloud container binauthz policy export

# Temporarily disable (CAUTION: Security risk)
cat > /tmp/binauthz-policy-permissive.yaml <<EOF
globalPolicyEvaluationMode: ENABLE
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
EOF

gcloud container binauthz policy import /tmp/binauthz-policy-permissive.yaml

# Sign and attest container image
# (See Binary Authorization documentation)
```

#### 10. IAP Authentication Failures

```bash
# Check IAP status
gcloud iap web get-iam-policy --resource-type=backend-services --service=a2a-global-backend

# Add user to IAP access
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service=a2a-global-backend \
  --member=user:user@${DOMAIN} \
  --role=roles/iap.httpsResourceAccessor

# Verify OAuth client configuration
gcloud iap oauth-clients list $BRAND
```

### Getting Help

1. **Check Logs**:
   ```bash
   # Application logs
   kubectl --namespace=$NAMESPACE logs -l app=a2a --tail=100

   # GCP Cloud Logging
   gcloud logging read "resource.type=k8s_cluster" --limit=50
   ```

2. **Review Monitoring Dashboards**:
   - GCP Console > Monitoring > Dashboards
   - GKE Dashboard
   - Cloud SQL Dashboard
   - Load Balancer Dashboard

3. **Contact Support**:
   - A2A GitHub Issues: https://github.com/a2aproject/A2A/issues
   - A2A Discussions: https://github.com/a2aproject/A2A/discussions
   - GCP Support: https://cloud.google.com/support
   - Enterprise Support: enterprise-support@a2a-protocol.org

4. **Documentation**:
   - A2A Protocol Specification: https://a2a-protocol.org/latest/specification/
   - GKE Documentation: https://cloud.google.com/kubernetes-engine/docs
   - Terraform GCP Provider: https://registry.terraform.io/providers/hashicorp/google/latest/docs

## Next Steps

After successful deployment:

1. **Review Security Posture**:
   - Run Security Command Center scan
   - Review IAM permissions
   - Enable VPC Service Controls
   - Configure DLP for sensitive data

2. **Optimize Performance**:
   - Tune autoscaling parameters
   - Configure Cloud CDN cache policies
   - Implement connection pooling
   - Enable query caching

3. **Establish Operations**:
   - Create runbooks for common scenarios
   - Set up on-call rotation
   - Configure incident management
   - Schedule regular disaster recovery tests

4. **Compliance Validation**:
   - Run compliance scans (SOX, PCI-DSS, HIPAA)
   - Review audit log coverage
   - Validate data retention policies
   - Conduct security audit

5. **Cost Optimization**:
   - Review resource utilization
   - Right-size instance types
   - Enable committed use discounts
   - Implement cost allocation tags

6. **Integration**:
   - Connect to existing monitoring systems
   - Integrate with SIEM
   - Set up CI/CD pipelines
   - Configure API gateways

For detailed information on these topics, refer to the complete documentation at https://a2a-protocol.org
