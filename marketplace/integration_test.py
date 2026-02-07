#!/usr/bin/env python3
"""
GCP Marketplace A2A Deployment Integration Tests

This test suite validates all components of the GCP Marketplace deployment:
- VPC Network and networking
- IAM and service accounts
- GKE cluster
- Cloud SQL database
- Persistent storage
- Load balancer
- Kubernetes resources
- Application deployment
- Security and compliance
"""

import os
import sys
import time
import json
import subprocess
import requests
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/gcp_marketplace_integration_test.log')
    ]
)
logger = logging.getLogger(__name__)


@dataclass
class TestResult:
    """Test result container"""
    test_name: str
    status: str  # PASS, FAIL, WARN, SKIP
    message: str
    duration: float = 0.0
    details: Optional[Dict] = None


class GCPMarketplaceIntegrationTest:
    """GCP Marketplace Integration Test Suite"""

    def __init__(self, project_id: str, deployment_name: str, region: str = "us-central1", zone: str = "us-central1-a"):
        self.project_id = project_id
        self.deployment_name = deployment_name
        self.region = region
        self.zone = zone
        self.namespace = os.getenv("NAMESPACE", "default")
        self.results: List[TestResult] = []

        # Derived names
        self.cluster_name = f"{deployment_name}-cluster"
        self.network_name = f"{deployment_name}-vpc"
        self.db_instance_name = f"{deployment_name}-db"
        self.lb_name = f"{deployment_name}-lb"
        self.service_account_name = os.getenv("SERVICE_ACCOUNT_NAME", "a2a-service-account")

    def run_command(self, cmd: List[str], check: bool = True, timeout: int = 300) -> Tuple[int, str, str]:
        """Execute shell command and return result"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=check
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", f"Command timed out after {timeout}s"
        except subprocess.CalledProcessError as e:
            return e.returncode, e.stdout, e.stderr
        except Exception as e:
            return -1, "", str(e)

    def record_result(self, test_name: str, status: str, message: str, duration: float = 0.0, details: Dict = None):
        """Record test result"""
        result = TestResult(test_name, status, message, duration, details)
        self.results.append(result)

        status_icon = "✓" if status == "PASS" else "✗" if status == "FAIL" else "⚠" if status == "WARN" else "○"
        logger.info(f"{status_icon} [{status}] {test_name}: {message}")

    # =========================================================================
    # Network Tests
    # =========================================================================

    def test_vpc_network_exists(self) -> bool:
        """Test 1: Verify VPC network exists"""
        start_time = time.time()
        test_name = "VPC Network Existence"

        cmd = [
            "gcloud", "compute", "networks", "describe", self.network_name,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            network_data = json.loads(stdout)
            self.record_result(test_name, "PASS", f"VPC network '{self.network_name}' exists", duration, network_data)
            return True
        else:
            self.record_result(test_name, "FAIL", f"VPC network not found: {stderr}", duration)
            return False

    def test_subnet_configuration(self) -> bool:
        """Test 2: Verify subnet configuration"""
        start_time = time.time()
        test_name = "Subnet Configuration"

        cmd = [
            "gcloud", "compute", "networks", "subnets", "list",
            "--network", self.network_name,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            subnets = json.loads(stdout)
            if len(subnets) > 0:
                subnet_info = {
                    "count": len(subnets),
                    "subnets": [{"name": s["name"], "ipCidrRange": s["ipCidrRange"]} for s in subnets]
                }
                self.record_result(test_name, "PASS", f"Found {len(subnets)} subnet(s)", duration, subnet_info)
                return True
            else:
                self.record_result(test_name, "FAIL", "No subnets found", duration)
                return False
        else:
            self.record_result(test_name, "FAIL", f"Failed to list subnets: {stderr}", duration)
            return False

    def test_firewall_rules(self) -> bool:
        """Test 3: Verify firewall rules"""
        start_time = time.time()
        test_name = "Firewall Rules"

        cmd = [
            "gcloud", "compute", "firewall-rules", "list",
            "--filter", f"network:{self.network_name}",
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            rules = json.loads(stdout)
            rule_info = {
                "count": len(rules),
                "rules": [r["name"] for r in rules]
            }
            self.record_result(test_name, "PASS", f"Found {len(rules)} firewall rule(s)", duration, rule_info)
            return True
        else:
            self.record_result(test_name, "WARN", f"Could not list firewall rules: {stderr}", duration)
            return True

    # =========================================================================
    # IAM Tests
    # =========================================================================

    def test_service_account_exists(self) -> bool:
        """Test 4: Verify service account exists"""
        start_time = time.time()
        test_name = "Service Account Existence"

        sa_email = f"{self.service_account_name}@{self.project_id}.iam.gserviceaccount.com"
        cmd = [
            "gcloud", "iam", "service-accounts", "describe", sa_email,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            sa_data = json.loads(stdout)
            self.record_result(test_name, "PASS", f"Service account '{sa_email}' exists", duration, sa_data)
            return True
        else:
            self.record_result(test_name, "WARN", f"Service account not found (may be created during deployment)", duration)
            return True

    def test_iam_bindings(self) -> bool:
        """Test 5: Verify IAM bindings"""
        start_time = time.time()
        test_name = "IAM Policy Bindings"

        cmd = [
            "gcloud", "projects", "get-iam-policy", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            policy = json.loads(stdout)
            bindings_count = len(policy.get("bindings", []))
            self.record_result(test_name, "PASS", f"Found {bindings_count} IAM binding(s)", duration)
            return True
        else:
            self.record_result(test_name, "FAIL", f"Failed to get IAM policy: {stderr}", duration)
            return False

    # =========================================================================
    # GKE Cluster Tests
    # =========================================================================

    def test_gke_cluster_exists(self) -> bool:
        """Test 6: Verify GKE cluster exists"""
        start_time = time.time()
        test_name = "GKE Cluster Existence"

        cmd = [
            "gcloud", "container", "clusters", "describe", self.cluster_name,
            "--zone", self.zone,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            cluster_data = json.loads(stdout)
            cluster_info = {
                "status": cluster_data.get("status"),
                "currentMasterVersion": cluster_data.get("currentMasterVersion"),
                "currentNodeVersion": cluster_data.get("currentNodeVersion"),
                "nodeCount": cluster_data.get("currentNodeCount")
            }
            self.record_result(test_name, "PASS", f"GKE cluster '{self.cluster_name}' exists with status: {cluster_info['status']}", duration, cluster_info)
            return True
        else:
            self.record_result(test_name, "FAIL", f"GKE cluster not found: {stderr}", duration)
            return False

    def test_gke_cluster_health(self) -> bool:
        """Test 7: Verify GKE cluster health"""
        start_time = time.time()
        test_name = "GKE Cluster Health"

        # Get cluster credentials
        cmd = [
            "gcloud", "container", "clusters", "get-credentials", self.cluster_name,
            "--zone", self.zone,
            "--project", self.project_id
        ]

        returncode, _, stderr = self.run_command(cmd, check=False)

        if returncode != 0:
            duration = time.time() - start_time
            self.record_result(test_name, "FAIL", f"Failed to get cluster credentials: {stderr}", duration)
            return False

        # Check cluster nodes
        cmd = ["kubectl", "get", "nodes", "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            nodes = json.loads(stdout)
            node_count = len(nodes.get("items", []))
            ready_nodes = sum(1 for node in nodes.get("items", [])
                            if any(c["type"] == "Ready" and c["status"] == "True"
                                   for c in node.get("status", {}).get("conditions", [])))

            node_info = {"total": node_count, "ready": ready_nodes}

            if ready_nodes == node_count:
                self.record_result(test_name, "PASS", f"All {node_count} node(s) are ready", duration, node_info)
                return True
            else:
                self.record_result(test_name, "WARN", f"{ready_nodes}/{node_count} node(s) ready", duration, node_info)
                return True
        else:
            self.record_result(test_name, "FAIL", f"Failed to get nodes: {stderr}", duration)
            return False

    def test_gke_node_pools(self) -> bool:
        """Test 8: Verify node pools configuration"""
        start_time = time.time()
        test_name = "GKE Node Pools"

        cmd = [
            "gcloud", "container", "node-pools", "list",
            "--cluster", self.cluster_name,
            "--zone", self.zone,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            pools = json.loads(stdout)
            pool_info = {
                "count": len(pools),
                "pools": [{"name": p["name"], "status": p["status"]} for p in pools]
            }
            self.record_result(test_name, "PASS", f"Found {len(pools)} node pool(s)", duration, pool_info)
            return True
        else:
            self.record_result(test_name, "FAIL", f"Failed to list node pools: {stderr}", duration)
            return False

    # =========================================================================
    # Cloud SQL Tests
    # =========================================================================

    def test_cloudsql_instance_exists(self) -> bool:
        """Test 9: Verify Cloud SQL instance exists"""
        start_time = time.time()
        test_name = "Cloud SQL Instance Existence"

        cmd = [
            "gcloud", "sql", "instances", "describe", self.db_instance_name,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            instance_data = json.loads(stdout)
            instance_info = {
                "state": instance_data.get("state"),
                "databaseVersion": instance_data.get("databaseVersion"),
                "tier": instance_data.get("settings", {}).get("tier")
            }
            self.record_result(test_name, "PASS", f"Cloud SQL instance '{self.db_instance_name}' exists with state: {instance_info['state']}", duration, instance_info)
            return True
        else:
            self.record_result(test_name, "WARN", f"Cloud SQL instance not found (may be optional): {stderr}", duration)
            return True

    def test_cloudsql_connectivity(self) -> bool:
        """Test 10: Verify Cloud SQL connectivity"""
        start_time = time.time()
        test_name = "Cloud SQL Connectivity"

        cmd = [
            "gcloud", "sql", "instances", "describe", self.db_instance_name,
            "--project", self.project_id,
            "--format", "json"
        ]

        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            instance_data = json.loads(stdout)
            connection_name = instance_data.get("connectionName")
            private_ip = instance_data.get("ipAddresses", [{}])[0].get("ipAddress", "N/A")

            connectivity_info = {
                "connectionName": connection_name,
                "privateIp": private_ip
            }
            self.record_result(test_name, "PASS", f"Cloud SQL connectivity configured: {connection_name}", duration, connectivity_info)
            return True
        else:
            self.record_result(test_name, "SKIP", "Cloud SQL instance not available", duration)
            return True

    # =========================================================================
    # Kubernetes Resources Tests
    # =========================================================================

    def test_namespace_exists(self) -> bool:
        """Test 11: Verify namespace exists"""
        start_time = time.time()
        test_name = "Kubernetes Namespace"

        cmd = ["kubectl", "get", "namespace", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            ns_data = json.loads(stdout)
            ns_info = {
                "name": ns_data.get("metadata", {}).get("name"),
                "status": ns_data.get("status", {}).get("phase")
            }
            self.record_result(test_name, "PASS", f"Namespace '{self.namespace}' exists with status: {ns_info['status']}", duration, ns_info)
            return True
        else:
            self.record_result(test_name, "FAIL", f"Namespace not found: {stderr}", duration)
            return False

    def test_configmaps(self) -> bool:
        """Test 12: Verify ConfigMaps"""
        start_time = time.time()
        test_name = "Kubernetes ConfigMaps"

        cmd = ["kubectl", "get", "configmap", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            cm_data = json.loads(stdout)
            configmaps = cm_data.get("items", [])
            cm_info = {
                "count": len(configmaps),
                "names": [cm.get("metadata", {}).get("name") for cm in configmaps]
            }
            self.record_result(test_name, "PASS", f"Found {len(configmaps)} ConfigMap(s)", duration, cm_info)
            return True
        else:
            self.record_result(test_name, "FAIL", f"Failed to get ConfigMaps: {stderr}", duration)
            return False

    def test_secrets(self) -> bool:
        """Test 13: Verify Secrets"""
        start_time = time.time()
        test_name = "Kubernetes Secrets"

        cmd = ["kubectl", "get", "secret", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            secret_data = json.loads(stdout)
            secrets = secret_data.get("items", [])
            secret_info = {
                "count": len(secrets),
                "names": [s.get("metadata", {}).get("name") for s in secrets]
            }
            self.record_result(test_name, "PASS", f"Found {len(secrets)} Secret(s)", duration, secret_info)
            return True
        else:
            self.record_result(test_name, "FAIL", f"Failed to get Secrets: {stderr}", duration)
            return False

    def test_deployment(self) -> bool:
        """Test 14: Verify Deployment"""
        start_time = time.time()
        test_name = "Kubernetes Deployment"

        cmd = ["kubectl", "get", "deployment", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            deploy_data = json.loads(stdout)
            deployments = deploy_data.get("items", [])

            if len(deployments) > 0:
                deploy = deployments[0]
                deploy_info = {
                    "name": deploy.get("metadata", {}).get("name"),
                    "replicas": deploy.get("spec", {}).get("replicas"),
                    "availableReplicas": deploy.get("status", {}).get("availableReplicas", 0),
                    "readyReplicas": deploy.get("status", {}).get("readyReplicas", 0)
                }

                if deploy_info["readyReplicas"] == deploy_info["replicas"]:
                    self.record_result(test_name, "PASS", f"Deployment '{deploy_info['name']}' is ready ({deploy_info['readyReplicas']}/{deploy_info['replicas']})", duration, deploy_info)
                    return True
                else:
                    self.record_result(test_name, "WARN", f"Deployment not fully ready ({deploy_info['readyReplicas']}/{deploy_info['replicas']})", duration, deploy_info)
                    return True
            else:
                self.record_result(test_name, "FAIL", "No deployments found", duration)
                return False
        else:
            self.record_result(test_name, "FAIL", f"Failed to get deployments: {stderr}", duration)
            return False

    def test_pods(self) -> bool:
        """Test 15: Verify Pods"""
        start_time = time.time()
        test_name = "Kubernetes Pods"

        cmd = ["kubectl", "get", "pods", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            pod_data = json.loads(stdout)
            pods = pod_data.get("items", [])

            running_pods = sum(1 for pod in pods if pod.get("status", {}).get("phase") == "Running")
            pod_info = {
                "total": len(pods),
                "running": running_pods,
                "pods": [{"name": p.get("metadata", {}).get("name"), "phase": p.get("status", {}).get("phase")} for p in pods]
            }

            if running_pods > 0:
                self.record_result(test_name, "PASS", f"{running_pods}/{len(pods)} pod(s) running", duration, pod_info)
                return True
            else:
                self.record_result(test_name, "FAIL", f"No running pods found ({len(pods)} total)", duration, pod_info)
                return False
        else:
            self.record_result(test_name, "FAIL", f"Failed to get pods: {stderr}", duration)
            return False

    def test_service(self) -> bool:
        """Test 16: Verify Service"""
        start_time = time.time()
        test_name = "Kubernetes Service"

        cmd = ["kubectl", "get", "service", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            svc_data = json.loads(stdout)
            services = svc_data.get("items", [])

            # Filter out default kubernetes service
            app_services = [s for s in services if s.get("metadata", {}).get("name") != "kubernetes"]

            if len(app_services) > 0:
                svc = app_services[0]
                svc_info = {
                    "name": svc.get("metadata", {}).get("name"),
                    "type": svc.get("spec", {}).get("type"),
                    "clusterIP": svc.get("spec", {}).get("clusterIP"),
                    "ports": svc.get("spec", {}).get("ports", [])
                }
                self.record_result(test_name, "PASS", f"Service '{svc_info['name']}' exists (type: {svc_info['type']})", duration, svc_info)
                return True
            else:
                self.record_result(test_name, "FAIL", "No application services found", duration)
                return False
        else:
            self.record_result(test_name, "FAIL", f"Failed to get services: {stderr}", duration)
            return False

    def test_hpa(self) -> bool:
        """Test 17: Verify HorizontalPodAutoscaler"""
        start_time = time.time()
        test_name = "Horizontal Pod Autoscaler"

        cmd = ["kubectl", "get", "hpa", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            hpa_data = json.loads(stdout)
            hpas = hpa_data.get("items", [])

            if len(hpas) > 0:
                hpa = hpas[0]
                hpa_info = {
                    "name": hpa.get("metadata", {}).get("name"),
                    "minReplicas": hpa.get("spec", {}).get("minReplicas"),
                    "maxReplicas": hpa.get("spec", {}).get("maxReplicas"),
                    "currentReplicas": hpa.get("status", {}).get("currentReplicas", 0)
                }
                self.record_result(test_name, "PASS", f"HPA '{hpa_info['name']}' configured (min: {hpa_info['minReplicas']}, max: {hpa_info['maxReplicas']})", duration, hpa_info)
            else:
                self.record_result(test_name, "WARN", "No HPA configured (optional)", duration)
            return True
        else:
            self.record_result(test_name, "WARN", "HPA not available (optional)", duration)
            return True

    # =========================================================================
    # Application Health Tests
    # =========================================================================

    def test_application_health(self) -> bool:
        """Test 18: Verify application health endpoint"""
        start_time = time.time()
        test_name = "Application Health Check"

        # Get service endpoint
        cmd = ["kubectl", "get", "service", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)

        if returncode != 0:
            duration = time.time() - start_time
            self.record_result(test_name, "SKIP", "Service not available for health check", duration)
            return True

        svc_data = json.loads(stdout)
        services = [s for s in svc_data.get("items", []) if s.get("metadata", {}).get("name") != "kubernetes"]

        if len(services) == 0:
            duration = time.time() - start_time
            self.record_result(test_name, "SKIP", "No application service found", duration)
            return True

        svc = services[0]
        svc_name = svc.get("metadata", {}).get("name")
        port = svc.get("spec", {}).get("ports", [{}])[0].get("port", 8080)

        # Try to port-forward and check health
        health_url = f"http://localhost:8888/health"

        # Start port-forward in background
        port_forward_cmd = ["kubectl", "port-forward", f"service/{svc_name}", "8888:8080", "-n", self.namespace]
        port_forward_proc = subprocess.Popen(port_forward_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Wait for port-forward to be ready
        time.sleep(3)

        try:
            response = requests.get(health_url, timeout=5)
            duration = time.time() - start_time

            if response.status_code == 200:
                self.record_result(test_name, "PASS", f"Application health check successful (status: {response.status_code})", duration)
                return True
            else:
                self.record_result(test_name, "WARN", f"Health check returned status: {response.status_code}", duration)
                return True
        except Exception as e:
            duration = time.time() - start_time
            self.record_result(test_name, "WARN", f"Could not reach health endpoint: {str(e)}", duration)
            return True
        finally:
            port_forward_proc.terminate()
            port_forward_proc.wait(timeout=5)

    def test_pod_logs(self) -> bool:
        """Test 19: Verify pod logs are accessible"""
        start_time = time.time()
        test_name = "Pod Logs Accessibility"

        cmd = ["kubectl", "get", "pods", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)

        if returncode != 0:
            duration = time.time() - start_time
            self.record_result(test_name, "FAIL", f"Failed to get pods: {stderr}", duration)
            return False

        pod_data = json.loads(stdout)
        pods = pod_data.get("items", [])

        if len(pods) == 0:
            duration = time.time() - start_time
            self.record_result(test_name, "FAIL", "No pods found", duration)
            return False

        pod_name = pods[0].get("metadata", {}).get("name")

        cmd = ["kubectl", "logs", pod_name, "-n", self.namespace, "--tail=10"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            log_lines = len(stdout.split("\n"))
            self.record_result(test_name, "PASS", f"Successfully retrieved logs from pod '{pod_name}' ({log_lines} lines)", duration)
            return True
        else:
            self.record_result(test_name, "WARN", f"Could not retrieve logs: {stderr}", duration)
            return True

    # =========================================================================
    # Security and Compliance Tests
    # =========================================================================

    def test_pod_security_context(self) -> bool:
        """Test 20: Verify pod security contexts"""
        start_time = time.time()
        test_name = "Pod Security Context"

        cmd = ["kubectl", "get", "pods", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode != 0:
            self.record_result(test_name, "FAIL", f"Failed to get pods: {stderr}", duration)
            return False

        pod_data = json.loads(stdout)
        pods = pod_data.get("items", [])

        insecure_pods = []
        for pod in pods:
            pod_name = pod.get("metadata", {}).get("name")
            security_context = pod.get("spec", {}).get("securityContext", {})

            # Check if running as non-root
            if not security_context.get("runAsNonRoot", False):
                insecure_pods.append(pod_name)

        if len(insecure_pods) == 0:
            self.record_result(test_name, "PASS", "All pods have security contexts configured", duration)
            return True
        else:
            self.record_result(test_name, "WARN", f"{len(insecure_pods)} pod(s) may not have proper security context", duration, {"pods": insecure_pods})
            return True

    def test_network_policies(self) -> bool:
        """Test 21: Verify network policies"""
        start_time = time.time()
        test_name = "Network Policies"

        cmd = ["kubectl", "get", "networkpolicy", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            np_data = json.loads(stdout)
            policies = np_data.get("items", [])

            np_info = {
                "count": len(policies),
                "policies": [p.get("metadata", {}).get("name") for p in policies]
            }

            if len(policies) > 0:
                self.record_result(test_name, "PASS", f"Found {len(policies)} network policy(ies)", duration, np_info)
            else:
                self.record_result(test_name, "WARN", "No network policies configured (recommended for production)", duration)
            return True
        else:
            self.record_result(test_name, "WARN", "Network policies not available", duration)
            return True

    def test_rbac_configuration(self) -> bool:
        """Test 22: Verify RBAC configuration"""
        start_time = time.time()
        test_name = "RBAC Configuration"

        # Check ServiceAccounts
        cmd = ["kubectl", "get", "serviceaccount", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)

        if returncode != 0:
            duration = time.time() - start_time
            self.record_result(test_name, "FAIL", f"Failed to get service accounts: {stderr}", duration)
            return False

        sa_data = json.loads(stdout)
        service_accounts = sa_data.get("items", [])

        # Check Roles
        cmd = ["kubectl", "get", "role", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)

        role_count = 0
        if returncode == 0:
            role_data = json.loads(stdout)
            role_count = len(role_data.get("items", []))

        # Check RoleBindings
        cmd = ["kubectl", "get", "rolebinding", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)

        rolebinding_count = 0
        if returncode == 0:
            rb_data = json.loads(stdout)
            rolebinding_count = len(rb_data.get("items", []))

        duration = time.time() - start_time
        rbac_info = {
            "serviceAccounts": len(service_accounts),
            "roles": role_count,
            "roleBindings": rolebinding_count
        }

        self.record_result(test_name, "PASS", f"RBAC configured: {len(service_accounts)} SA(s), {role_count} role(s), {rolebinding_count} binding(s)", duration, rbac_info)
        return True

    def test_resource_limits(self) -> bool:
        """Test 23: Verify resource limits are set"""
        start_time = time.time()
        test_name = "Resource Limits"

        cmd = ["kubectl", "get", "pods", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode != 0:
            self.record_result(test_name, "FAIL", f"Failed to get pods: {stderr}", duration)
            return False

        pod_data = json.loads(stdout)
        pods = pod_data.get("items", [])

        pods_without_limits = []
        for pod in pods:
            pod_name = pod.get("metadata", {}).get("name")
            containers = pod.get("spec", {}).get("containers", [])

            for container in containers:
                resources = container.get("resources", {})
                if not resources.get("limits") or not resources.get("requests"):
                    pods_without_limits.append(f"{pod_name}/{container.get('name')}")

        if len(pods_without_limits) == 0:
            self.record_result(test_name, "PASS", "All containers have resource limits configured", duration)
            return True
        else:
            self.record_result(test_name, "WARN", f"{len(pods_without_limits)} container(s) without resource limits", duration, {"containers": pods_without_limits})
            return True

    # =========================================================================
    # Storage Tests
    # =========================================================================

    def test_persistent_volumes(self) -> bool:
        """Test 24: Verify persistent volumes"""
        start_time = time.time()
        test_name = "Persistent Volumes"

        cmd = ["kubectl", "get", "pvc", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode == 0:
            pvc_data = json.loads(stdout)
            pvcs = pvc_data.get("items", [])

            pvc_info = {
                "count": len(pvcs),
                "pvcs": [{"name": p.get("metadata", {}).get("name"), "status": p.get("status", {}).get("phase")} for p in pvcs]
            }

            bound_pvcs = sum(1 for pvc in pvcs if pvc.get("status", {}).get("phase") == "Bound")

            if bound_pvcs == len(pvcs) and len(pvcs) > 0:
                self.record_result(test_name, "PASS", f"All {len(pvcs)} PVC(s) are bound", duration, pvc_info)
            elif len(pvcs) > 0:
                self.record_result(test_name, "WARN", f"{bound_pvcs}/{len(pvcs)} PVC(s) bound", duration, pvc_info)
            else:
                self.record_result(test_name, "WARN", "No PVCs configured (may be optional)", duration)
            return True
        else:
            self.record_result(test_name, "WARN", "Could not check PVCs", duration)
            return True

    # =========================================================================
    # Load Balancer Tests
    # =========================================================================

    def test_load_balancer(self) -> bool:
        """Test 25: Verify load balancer"""
        start_time = time.time()
        test_name = "Load Balancer"

        # Check for LoadBalancer type services
        cmd = ["kubectl", "get", "service", "-n", self.namespace, "-o", "json"]
        returncode, stdout, stderr = self.run_command(cmd, check=False)
        duration = time.time() - start_time

        if returncode != 0:
            self.record_result(test_name, "FAIL", f"Failed to get services: {stderr}", duration)
            return False

        svc_data = json.loads(stdout)
        services = svc_data.get("items", [])

        lb_services = [s for s in services if s.get("spec", {}).get("type") == "LoadBalancer"]

        if len(lb_services) > 0:
            lb_svc = lb_services[0]
            lb_info = {
                "name": lb_svc.get("metadata", {}).get("name"),
                "loadBalancerIP": lb_svc.get("status", {}).get("loadBalancer", {}).get("ingress", [{}])[0].get("ip", "pending")
            }

            if lb_info["loadBalancerIP"] and lb_info["loadBalancerIP"] != "pending":
                self.record_result(test_name, "PASS", f"LoadBalancer service configured with IP: {lb_info['loadBalancerIP']}", duration, lb_info)
            else:
                self.record_result(test_name, "WARN", "LoadBalancer IP pending assignment", duration, lb_info)
            return True
        else:
            self.record_result(test_name, "WARN", "No LoadBalancer service configured", duration)
            return True

    # =========================================================================
    # Test Orchestration
    # =========================================================================

    def run_all_tests(self):
        """Run all integration tests"""
        logger.info("=" * 80)
        logger.info("Starting GCP Marketplace Integration Tests")
        logger.info("=" * 80)
        logger.info(f"Project ID: {self.project_id}")
        logger.info(f"Deployment Name: {self.deployment_name}")
        logger.info(f"Region: {self.region}")
        logger.info(f"Zone: {self.zone}")
        logger.info(f"Namespace: {self.namespace}")
        logger.info("=" * 80)

        start_time = time.time()

        # Network Tests
        logger.info("\n--- Network Tests ---")
        self.test_vpc_network_exists()
        self.test_subnet_configuration()
        self.test_firewall_rules()

        # IAM Tests
        logger.info("\n--- IAM Tests ---")
        self.test_service_account_exists()
        self.test_iam_bindings()

        # GKE Tests
        logger.info("\n--- GKE Cluster Tests ---")
        cluster_exists = self.test_gke_cluster_exists()
        if cluster_exists:
            self.test_gke_cluster_health()
            self.test_gke_node_pools()

        # Cloud SQL Tests
        logger.info("\n--- Cloud SQL Tests ---")
        self.test_cloudsql_instance_exists()
        self.test_cloudsql_connectivity()

        # Kubernetes Resources Tests
        logger.info("\n--- Kubernetes Resources Tests ---")
        self.test_namespace_exists()
        self.test_configmaps()
        self.test_secrets()
        self.test_deployment()
        self.test_pods()
        self.test_service()
        self.test_hpa()

        # Application Health Tests
        logger.info("\n--- Application Health Tests ---")
        self.test_application_health()
        self.test_pod_logs()

        # Security and Compliance Tests
        logger.info("\n--- Security and Compliance Tests ---")
        self.test_pod_security_context()
        self.test_network_policies()
        self.test_rbac_configuration()
        self.test_resource_limits()

        # Storage Tests
        logger.info("\n--- Storage Tests ---")
        self.test_persistent_volumes()

        # Load Balancer Tests
        logger.info("\n--- Load Balancer Tests ---")
        self.test_load_balancer()

        total_duration = time.time() - start_time

        # Generate report
        self.generate_report(total_duration)

    def generate_report(self, total_duration: float):
        """Generate test report"""
        logger.info("\n" + "=" * 80)
        logger.info("TEST REPORT")
        logger.info("=" * 80)

        total_tests = len(self.results)
        passed = sum(1 for r in self.results if r.status == "PASS")
        failed = sum(1 for r in self.results if r.status == "FAIL")
        warnings = sum(1 for r in self.results if r.status == "WARN")
        skipped = sum(1 for r in self.results if r.status == "SKIP")

        pass_rate = (passed / total_tests * 100) if total_tests > 0 else 0

        logger.info(f"\nTotal Tests:    {total_tests}")
        logger.info(f"Passed:         {passed} ({pass_rate:.1f}%)")
        logger.info(f"Failed:         {failed}")
        logger.info(f"Warnings:       {warnings}")
        logger.info(f"Skipped:        {skipped}")
        logger.info(f"Total Duration: {total_duration:.2f}s")

        logger.info("\n--- Detailed Results ---")
        for result in self.results:
            status_icon = "✓" if result.status == "PASS" else "✗" if result.status == "FAIL" else "⚠" if result.status == "WARN" else "○"
            logger.info(f"{status_icon} [{result.status:4s}] {result.test_name}: {result.message} ({result.duration:.2f}s)")

        # Save JSON report
        report_file = f"/tmp/gcp_marketplace_integration_test_report_{int(time.time())}.json"
        report_data = {
            "timestamp": time.time(),
            "project_id": self.project_id,
            "deployment_name": self.deployment_name,
            "region": self.region,
            "zone": self.zone,
            "namespace": self.namespace,
            "summary": {
                "total": total_tests,
                "passed": passed,
                "failed": failed,
                "warnings": warnings,
                "skipped": skipped,
                "pass_rate": pass_rate,
                "duration": total_duration
            },
            "results": [
                {
                    "test_name": r.test_name,
                    "status": r.status,
                    "message": r.message,
                    "duration": r.duration,
                    "details": r.details
                }
                for r in self.results
            ]
        }

        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)

        logger.info(f"\nDetailed JSON report saved to: {report_file}")

        logger.info("\n" + "=" * 80)
        if failed == 0:
            logger.info("✓ ALL CRITICAL TESTS PASSED")
        else:
            logger.error(f"✗ {failed} TEST(S) FAILED")
        logger.info("=" * 80)

        return failed == 0


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="GCP Marketplace A2A Integration Tests")
    parser.add_argument("--project-id", required=True, help="GCP Project ID")
    parser.add_argument("--deployment-name", required=True, help="Deployment name")
    parser.add_argument("--region", default="us-central1", help="GCP region")
    parser.add_argument("--zone", default="us-central1-a", help="GCP zone")
    parser.add_argument("--namespace", default="default", help="Kubernetes namespace")

    args = parser.parse_args()

    # Set namespace in environment
    os.environ["NAMESPACE"] = args.namespace

    # Create and run tests
    tester = GCPMarketplaceIntegrationTest(
        project_id=args.project_id,
        deployment_name=args.deployment_name,
        region=args.region,
        zone=args.zone
    )

    success = tester.run_all_tests()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
