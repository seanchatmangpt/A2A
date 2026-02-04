# Terraform Infrastructure as Code for Craftplan MCP + A2A + elrmcp

This Terraform configuration provisions a complete Kubernetes infrastructure for the Craftplan MCP + A2A + elrmcp integration.

## Features

- **EKS Cluster**: Production-ready Kubernetes cluster with autoscaling
- **VPC Networking**: Secure networking with public and private subnets
- **Managed Services**: RDS PostgreSQL, ElastiCache Redis, S3 storage
- **Monitoring Stack**: Prometheus, Grafana, Alertmanager, Loki
- **Load Balancing**: Application Load Balancer with SSL termination
- **Security**: IAM roles, security groups, network ACLs
- **Cost Optimization**: Spot instances, auto-scaling, resource limits

## Prerequisites

### Required Tools
- Terraform v1.5.0 or higher
- AWS CLI v2 or higher
- kubectl
- helm

### AWS Requirements
- AWS account with appropriate permissions
- S3 bucket for Terraform state (optional, but recommended)
- DynamoDB table for Terraform state lock (optional, but recommended)

### IAM Permissions Required
- EC2 permissions for EKS nodes
- VPC permissions for networking
- IAM permissions for roles and policies
- S3 permissions for state storage
- RDS permissions for managed database

## Quick Start

### 1. Initialize Terraform
```bash
terraform init
```

### 2. Plan the Deployment
```bash
terraform plan -var-file=staging.tfvars
```

### 3. Apply the Configuration
```bash
terraform apply -var-file=staging.tfvars
```

### 4. Configure kubectl
```bash
aws eks update-kubeconfig --region ${AWS_REGION} --name $(terraform output -raw cluster_name)
```

## Configuration Options

### Environment Variables
Create a `terraform.tfvars` file for your environment:

```hcl
environment = "production"
aws_region  = "us-west-2"
instance_type = "m6g.xlarge"
node_group_size = 5
node_group_max_size = 10
```

### Available Variables

#### Core Infrastructure
- `environment`: Environment name (dev, staging, production)
- `aws_region`: AWS region for deployment
- `instance_type`: EC2 instance type for EKS nodes
- `node_group_size`: Desired number of nodes
- `node_group_max_size`: Maximum number of nodes

#### Service Configuration
- `craftplan_replicas`: Number of Craftplan replicas
- `mcp_server_replicas`: Number of MCP server replicas
- `a2a_agent_replicas`: Number of A2A agent replicas
- `elrmcp_replicas`: Number of elrmcp replicas

#### Managed Services
- `enable_database`: Enable managed database
- `database_instance_class`: Database instance type
- `database_allocated_storage`: Database storage size
- `enable_redis`: Enable Redis cache
- `enable_minio`: Enable MinIO object storage

#### Cost Optimization
- `enable_auto_scaling`: Enable cluster autoscaling
- `spot_instances_enabled`: Enable spot instances
- `cost_optimization`: Enable cost optimization

### Environment-Specific Configurations

#### Development
```hcl
environment = "dev"
node_group_size = 2
node_group_max_size = 3
craftplan_replicas = 1
mcp_server_replicas = 1
a2a_agent_replicas = 1
elrmcp_replicas = 1
```

#### Staging
```hcl
environment = "staging"
node_group_size = 3
node_group_max_size = 5
craftplan_replicas = 2
mcp_server_replicas = 2
a2a_agent_replicas = 2
elrmcp_replicas = 2
```

#### Production
```hcl
environment = "production"
node_group_size = 5
node_group_max_size = 10
craftplan_replicas = 3
mcp_server_replicas = 3
a2a_agent_replicas = 3
elrmcp_replicas = 3
```

## Outputs

### Cluster Information
- `cluster_name`: EKS cluster name
- `cluster_endpoint`: EKS cluster endpoint
- `cluster_certificate_authority_data`: Cluster CA data
- `kubernetes_namespace`: Kubernetes namespace

### Network Information
- `vpc_id`: VPC ID
- `private_subnets`: Private subnet IDs
- `public_subnets`: Public subnet IDs

### Load Balancer
- `load_balancer_arn`: ALB ARN
- `load_balancer_dns_name`: ALB DNS name

### Service Endpoints
- `database_endpoint`: Database endpoint
- `redis_endpoint`: Redis endpoint
- `minio_endpoint`: MinIO endpoint
- `prometheus_endpoint`: Prometheus endpoint
- `grafana_endpoint`: Grafana endpoint

### Application URLs
- `craftplan_ingress_url`: Craftplan ingress URL
- `mcp_server_ingress_url`: MCP server ingress URL
- `a2a_agent_ingress_url`: A2A agent ingress URL
- `elrmcp_ingress_url`: elrmcp ingress URL

## Monitoring and Logging

### Prometheus Metrics
- Cluster and node metrics
- Application metrics
- Custom business metrics

### Grafana Dashboards
- Cluster overview
- Application performance
- Resource utilization
- Error rates and latency

### Logging with Loki
- Application logs
- System logs
- Access logs
- Error logs

### Alerting
- Health alerts
- Performance alerts
- Resource alerts
- Cost alerts

## Cost Management

### Cost Optimization Features
- Spot instances for non-critical workloads
- Auto-scaling based on demand
- Resource limits and quotas
- Scheduled scaling

### Cost Monitoring
- CloudWatch billing alarms
- Resource utilization metrics
- Cost allocation tags
- Budget alerts

## Security

### Network Security
- VPC with public/private subnets
- Security groups for traffic control
- Network ACLs for additional security
- VPN access option

### IAM Security
- Role-based access control
- Least privilege principle
- OIDC integration for Kubernetes
- Temporary credentials

### Application Security
- TLS/SSL encryption
- Container security scanning
- Secret management
- Network policies

## Backup and Disaster Recovery

### Backup Strategy
- Automated database backups
- S3 bucket versioning
- Configuration backup via Git
- Infrastructure as code

### Recovery Procedures
- Automated cluster recovery
- Point-in-time recovery for database
- Application rollbacks
- Disaster recovery drills

## Troubleshooting

### Common Issues

#### Cluster Connection Issues
```bash
# Check cluster status
aws eks describe-cluster --name $CLUSTER_NAME

# Check node status
kubectl get nodes
kubectl get pods -A

# Check kubeconfig
kubectl cluster-info
```

#### Service Access Issues
```bash
# Check load balancer status
aws elbv2 describe-load-balancers --names $LOAD_BALANCER_NAME

# Check ingress status
kubectl get ingress -n craftplan

# Test service connectivity
curl http://$INGRESS_URL/health
```

#### Performance Issues
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n craftplan

# Check cluster autoscaler status
kubectl get deployment cluster-autoscaler -n kube-system
```

### Debug Commands
```bash
# Check pod logs
kubectl logs -n craftplan <pod-name>

# Describe pod
kubectl describe pod -n craftplan <pod-name>

# Check events
kubectl get events -n craftplan

# Check resource usage
kubectl describe node <node-name>
```

## Scaling

### Horizontal Scaling
- Use HPA for application scaling
- Use VPA for resource optimization
- Use cluster autoscaler for node scaling

### Vertical Scaling
- Adjust resource limits
- Resize instance types
- Increase storage capacity

## Maintenance

### Regular Maintenance Tasks
- Apply OS patches
- Update Kubernetes version
- Update cluster autoscaler
- Clean up unused resources

### Scheduled Maintenance
- Monthly security updates
- Quarterly major version updates
- Yearly infrastructure reviews

## Support

### Documentation
- [EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Documentation](https://www.terraform.io/docs/)

### Support Channels
- AWS Support
- Kubernetes Community
- Terraform Community
- Project-specific documentation

## License

This project is licensed under the MIT License.