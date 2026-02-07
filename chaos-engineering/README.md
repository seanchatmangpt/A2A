# Chaos Engineering for A2A Protocol

This directory contains comprehensive chaos engineering tests for the Agent2Agent (A2A) protocol infrastructure using Chaos Mesh.

## Overview

Chaos engineering helps validate the resilience and fault tolerance of A2A components by intentionally injecting failures into the system in a controlled manner.

## Features

### Chaos Experiment Types

1. **Pod Chaos**
   - Pod kill: Randomly terminates pods
   - Pod failure: Simulates pod failures

2. **Network Chaos**
   - Delay: Adds network latency (100ms + 20ms jitter)
   - Loss: Simulates packet loss (25%)
   - Partition: Creates network partitions
   - Bandwidth: Limits network bandwidth (1mbps)

3. **Stress Chaos**
   - CPU stress: Applies CPU load (80%)
   - Memory stress: Consumes memory (256MB)
   - Combined: CPU + Memory pressure

4. **I/O Chaos**
   - I/O delay: Adds disk I/O latency (100ms)
   - I/O faults: Injects I/O errors
   - I/O attribution: Modifies file permissions

5. **HTTP Chaos**
   - HTTP delay: Adds HTTP request latency (500ms)
   - HTTP abort: Aborts HTTP requests
   - HTTP patch: Modifies HTTP responses

6. **DNS Chaos**
   - DNS random: Returns random IPs
   - DNS error: Returns DNS errors

7. **Time Chaos**
   - Time skew: Shifts system time (-1h or +2h)

8. **Workflows**
   - Sequential: Runs chaos experiments in sequence
   - Parallel: Runs multiple experiments simultaneously

## Directory Structure

```
chaos-engineering/
├── manifests/           # Chaos experiment YAML manifests
│   ├── pod-kill-chaos.yaml
│   ├── network-chaos.yaml
│   ├── stress-chaos.yaml
│   ├── io-chaos.yaml
│   ├── http-chaos.yaml
│   ├── dns-chaos.yaml
│   ├── time-chaos.yaml
│   └── workflow-chaos.yaml
├── scripts/            # Automation scripts
│   ├── install-chaos-mesh.sh
│   ├── run-chaos-tests.sh
│   └── monitor-chaos.py
├── reports/            # Test reports and metrics
└── README.md
```

## Quick Start

### 1. Install Chaos Mesh

```bash
cd /home/user/A2A/chaos-engineering
chmod +x scripts/*.sh
./scripts/install-chaos-mesh.sh
```

This will:
- Install kubectl and helm if needed
- Create a kind cluster for testing
- Install Chaos Mesh
- Deploy test workloads
- Set up the Chaos Dashboard

### 2. Run Chaos Tests

```bash
./scripts/run-chaos-tests.sh
```

This will execute all chaos experiments and generate detailed reports.

### 3. Monitor Chaos Experiments

```bash
chmod +x scripts/monitor-chaos.py
./scripts/monitor-chaos.py --duration 300 --interval 10
```

### 4. Access Chaos Dashboard

```bash
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
```

Then open http://localhost:2333 in your browser.

## Manual Testing

### Apply Individual Chaos Experiments

```bash
# Pod chaos
kubectl apply -f manifests/pod-kill-chaos.yaml

# Network chaos
kubectl apply -f manifests/network-chaos.yaml

# Stress chaos
kubectl apply -f manifests/stress-chaos.yaml
```

### Monitor Chaos Experiments

```bash
# List all chaos experiments
kubectl get podchaos,networkchaos,stresschaos,iochaos,httpchaos,dnschaos,timechaos,workflows -n default

# Get detailed status
kubectl describe podchaos pod-kill-test -n default

# View chaos events
kubectl get events -n default --sort-by='.lastTimestamp'
```

### Clean Up Experiments

```bash
# Delete specific experiment
kubectl delete -f manifests/pod-kill-chaos.yaml

# Delete all chaos experiments
kubectl delete podchaos,networkchaos,stresschaos,iochaos,httpchaos,dnschaos,timechaos,workflows --all -n default
```

## Configuration

### Environment Variables

```bash
export CHAOS_MESH_VERSION="2.6.3"
export CHAOS_MESH_NAMESPACE="chaos-mesh"
export KIND_CLUSTER_NAME="a2a-chaos"
export CHAOS_NAMESPACE="default"
export CHAOS_DURATION="60"
```

### Customizing Experiments

Edit the YAML files in `manifests/` to customize:
- Target pods (selector)
- Chaos parameters (delay, loss, etc.)
- Duration
- Schedule (for recurring experiments)

## Chaos Mesh CRDs

Chaos Mesh provides these Custom Resource Definitions:

- `PodChaos`: Pod-level failures
- `NetworkChaos`: Network failures
- `StressChaos`: Resource stress
- `IOChaos`: Disk I/O failures
- `HTTPChaos`: HTTP-level failures
- `DNSChaos`: DNS failures
- `TimeChaos`: Time manipulation
- `Workflow`: Orchestrate multiple chaos experiments

## Best Practices

1. **Start Small**: Begin with low-impact experiments
2. **Monitor Closely**: Watch metrics during chaos injection
3. **Define Success Criteria**: Know what "recovery" means
4. **Document Findings**: Record all observations
5. **Automate**: Integrate chaos tests into CI/CD
6. **Schedule Regularly**: Run chaos tests on a schedule
7. **Test in Staging**: Validate experiments before production

## Observability

### Metrics to Monitor

- Pod restart count
- Service availability
- Response times
- Error rates
- Resource utilization
- Recovery time

### Prometheus Queries

```promql
# Pod restart count
rate(kube_pod_container_status_restarts_total[5m])

# Service availability
up{job="a2a-agent"}

# HTTP error rate
rate(http_requests_total{status=~"5.."}[5m])
```

## Troubleshooting

### Chaos Mesh Not Installing

```bash
# Check Helm repositories
helm repo list

# Verify CRDs
kubectl get crd | grep chaos-mesh

# Check pod status
kubectl get pods -n chaos-mesh
```

### Experiments Not Running

```bash
# Check experiment status
kubectl describe podchaos <experiment-name> -n default

# Check chaos-controller logs
kubectl logs -n chaos-mesh -l app.kubernetes.io/component=controller-manager

# Verify pod labels match selectors
kubectl get pods -n default --show-labels
```

### Recovery Issues

```bash
# Force delete stuck chaos experiments
kubectl delete podchaos <experiment-name> --force --grace-period=0

# Restart affected deployments
kubectl rollout restart deployment/<deployment-name> -n default
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Chaos Engineering Tests

on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly on Monday at 2 AM

jobs:
  chaos-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Chaos Mesh
        run: |
          cd chaos-engineering
          ./scripts/install-chaos-mesh.sh

      - name: Run Chaos Tests
        run: |
          cd chaos-engineering
          ./scripts/run-chaos-tests.sh

      - name: Upload Reports
        uses: actions/upload-artifact@v4
        with:
          name: chaos-reports
          path: chaos-engineering/reports/
```

## Resources

- [Chaos Mesh Documentation](https://chaos-mesh.org/docs/)
- [Chaos Engineering Principles](https://principlesofchaos.org/)
- [A2A Protocol Documentation](https://a2a-protocol.org)

## License

Apache License 2.0 - See [LICENSE](../LICENSE)

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.
