# GCP Marketplace End-to-End Deployment Tests

This directory contains comprehensive end-to-end tests for the A2A Protocol GCP Marketplace deployment.

## Overview

The test suite validates the complete GCP Marketplace installation flow, including:
- Infrastructure configuration (GKE, networking, databases, storage)
- Kubernetes resource deployment
- Security configuration
- High availability and autoscaling
- Deployment dependencies and ordering

## Test Structure

### Test Files

- **test_gcp_marketplace_e2e.py**: Main end-to-end test suite (876 lines, 43 tests)
- **conftest.py**: pytest configuration and custom markers

## Test Coverage (43 Tests)

### 1. Schema Validation (5 tests)
Tests the `schema.yaml` configuration file:
- ✓ Required fields validation
- ✓ GCP Marketplace type verification (NAME, NAMESPACE, TAG, SERVICE_ACCOUNT, TLS_CERTIFICATE)
- ✓ Property defaults and constraints
- ✓ Resource limits configuration

### 2. Deployer Configuration (3 tests)
Tests the `deployer.yaml` deployment manifest:
- ✓ Resources definition
- ✓ Critical infrastructure components
- ✓ Deployment outputs

### 3. Network Configuration (2 tests)
Tests VPC networking setup:
- ✓ VPC network configuration
- ✓ CIDR ranges (subnet, pods, services, master)
- ✓ No CIDR overlap validation

### 4. GKE Configuration (4 tests)
Tests Google Kubernetes Engine cluster:
- ✓ Cluster configuration
- ✓ Security features (auto-upgrade, auto-repair, network policy, workload identity)
- ✓ Monitoring and logging (Stackdriver)
- ✓ Network dependencies

### 5. Database Configuration (4 tests)
Tests Cloud SQL deployment:
- ✓ PostgreSQL configuration
- ✓ Backup and point-in-time recovery
- ✓ Security settings (SSL, private networking)
- ✓ High availability setup

### 6. Kubernetes Resources (6 tests)
Tests Kubernetes workload deployment:
- ✓ Namespace creation
- ✓ Deployment specification
- ✓ Container configuration (image, ports, resources)
- ✓ Health probes (liveness, readiness, startup)
- ✓ Service configuration
- ✓ Horizontal Pod Autoscaler (HPA)

### 7. Security Configuration (3 tests)
Tests security setup:
- ✓ Service account with workload identity
- ✓ Secrets management (Erlang cookie, DB credentials)
- ✓ ConfigMaps (VM args, system config)

### 8. Dependency Management (3 tests)
Tests resource dependencies:
- ✓ Dependency graph validation
- ✓ Topological sorting for deployment order
- ✓ Database and network dependencies

### 9. End-to-End Deployment (3 tests)
Tests full deployment simulation:
- ✓ Complete deployment flow
- ✓ Output generation
- ✓ All resources deployed in correct order

### 10. Deployment Script Validation (3 tests)
Tests the `deploy.sh` script:
- ✓ Script exists and is executable
- ✓ Required functions present
- ✓ Prerequisites validation

### 11. Marketplace Integration (3 tests)
Tests GCP Marketplace integration:
- ✓ application.yaml exists
- ✓ Application metadata and annotations
- ✓ Dockerfile for deployer image

### 12. Integration Scenarios (3 tests)
Tests advanced scenarios:
- ✓ Custom deployment parameters
- ✓ Schema validator integration
- ✓ Deployment resilience

### 13. Complete E2E Workflow (1 test)
The master test that validates the entire deployment pipeline:
- Schema validation
- Deployer structure validation
- Dependency graph validation
- Topological sorting
- Full deployment simulation
- Output verification

## Running the Tests

### Run all tests
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py -v
```

### Run specific test class
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py::TestSchemaValidation -v
```

### Run with detailed output
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py -v -s
```

### Run only the E2E workflow test
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py::test_complete_e2e_workflow -v -s
```

### Run integration tests
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py -v -m integration
```

### Skip integration tests
```bash
pytest tests/unit/deployment/test_gcp_marketplace_e2e.py -v -m "not integration"
```

## Test Output Example

When running the complete E2E workflow test, you'll see:

```
======================================================================
E2E DEPLOYMENT TEST COMPLETED SUCCESSFULLY
======================================================================

Deployed 14 resources in order:
  1. a2a-network (templates/network.jinja)
  2. a2a-iam (templates/iam.jinja)
  3. a2a-gke-cluster (templates/gke_cluster.jinja)
  4. a2a-cloudsql (templates/cloudsql.jinja)
  5. a2a-storage (templates/storage.jinja)
  6. a2a-deployment (compute.v1.instanceGroupManager)
  7. a2a-loadbalancer (templates/loadbalancer.jinja)
  8. a2a-k8s-namespace (...)
  9. a2a-k8s-configmap (...)
  10. a2a-k8s-secret (...)
  11. a2a-k8s-serviceaccount (...)
  12. a2a-k8s-deployment (...)
  13. a2a-k8s-service (...)
  14. a2a-k8s-hpa (...)

Outputs:
  clusterName: a2a-deployment-cluster
  clusterEndpoint: https://35.1.2.3
  loadBalancerIp: 34.1.2.3
  databaseConnectionName: test-project:us-central1:a2a-deployment-db
  databasePrivateIp: 10.0.0.10
  serviceUrl: http://34.1.2.3
  namespace: a2a-system
  deploymentName: a2a-erl
======================================================================
```

## Key Components Tested

### Infrastructure
- ✓ VPC Network with private Google access
- ✓ GKE cluster with security hardening
- ✓ Cloud SQL PostgreSQL database
- ✓ Persistent storage (PVCs)
- ✓ Load balancer with health checks

### Kubernetes
- ✓ Namespace isolation
- ✓ ConfigMaps and Secrets
- ✓ Service accounts with workload identity
- ✓ Deployments with rolling updates
- ✓ Services (LoadBalancer type)
- ✓ Horizontal Pod Autoscaler

### Security
- ✓ Network policies enabled
- ✓ Private networking for database
- ✓ SSL/TLS required
- ✓ Workload identity for GCP service access
- ✓ Secrets management
- ✓ IAM service accounts

### High Availability
- ✓ Multi-replica deployments
- ✓ Pod autoscaling (HPA)
- ✓ Node autoscaling
- ✓ Regional database availability
- ✓ Rolling updates with zero downtime
- ✓ Health checks and probes

### Monitoring & Observability
- ✓ Stackdriver logging
- ✓ Stackdriver monitoring
- ✓ Prometheus annotations
- ✓ Health endpoints

## Deployment Simulator

The test suite includes a `GCPMarketplaceDeploymentSimulator` class that:
- Parses deployer.yaml configuration (handles Jinja2 templates)
- Builds dependency graph
- Performs topological sorting
- Simulates resource deployment
- Validates deployment outputs
- Tests error scenarios

## Architecture Validated

The tests validate a complete production-ready GCP architecture:

```
Internet
    ↓
Load Balancer (with health checks)
    ↓
GKE Cluster (with network policy, workload identity)
    ├── Namespace (a2a-system)
    ├── ConfigMaps (Erlang/OTP config)
    ├── Secrets (DB credentials, Erlang cookie)
    ├── Service Account (with workload identity)
    ├── Deployment (multi-replica, autoscaling)
    │   └── Pods (health probes, resource limits)
    ├── Service (LoadBalancer)
    └── HPA (CPU/memory based autoscaling)
    ↓
Cloud SQL (private IP, SSL, backups, HA)
Persistent Storage (SSD, with backups)
```

## Contributing

When adding new deployment tests:
1. Add test methods to appropriate test class
2. Use descriptive test names following `test_<feature>_<aspect>` pattern
3. Add docstrings explaining what is being validated
4. Update this README with new test coverage
5. Ensure tests are idempotent and don't depend on external state

## Maintenance

These tests should be updated when:
- GCP Marketplace schema changes
- New infrastructure components are added
- Deployment configuration is modified
- New security features are enabled
- Kubernetes version is upgraded

## Related Files

- `/home/user/A2A/marketplace/schema.yaml` - GCP Marketplace schema
- `/home/user/A2A/marketplace/deployer.yaml` - Deployment Manager configuration
- `/home/user/A2A/marketplace/deploy.sh` - Deployment script
- `/home/user/A2A/marketplace/application.yaml` - Application metadata

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run GCP Marketplace E2E Tests
  run: |
    pytest tests/unit/deployment/test_gcp_marketplace_e2e.py -v --junitxml=test-results.xml
```

## License

These tests are part of the A2A Protocol project and follow the same license terms.
