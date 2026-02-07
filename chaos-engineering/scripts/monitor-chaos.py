#!/usr/bin/env python3
"""
Chaos Engineering Monitoring Script for A2A Project
Monitors chaos experiments and collects detailed metrics
"""

import json
import os
import subprocess
import time
from datetime import datetime
from typing import Dict, List, Any
import sys

class ChaosMonitor:
    def __init__(self, namespace: str = "default", report_dir: str = "/home/user/A2A/chaos-engineering/reports"):
        self.namespace = namespace
        self.report_dir = report_dir
        self.metrics = []

    def run_kubectl(self, args: List[str]) -> str:
        """Run kubectl command and return output"""
        try:
            cmd = ["kubectl"] + args
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Error running kubectl: {e}")
            return ""

    def get_chaos_experiments(self) -> Dict[str, List[str]]:
        """Get all active chaos experiments"""
        experiments = {
            "podchaos": [],
            "networkchaos": [],
            "stresschaos": [],
            "iochaos": [],
            "httpchaos": [],
            "dnschaos": [],
            "timechaos": [],
            "workflows": []
        }

        for exp_type in experiments.keys():
            output = self.run_kubectl(["get", exp_type, "-n", self.namespace, "-o", "json"])
            if output:
                data = json.loads(output)
                experiments[exp_type] = [item["metadata"]["name"] for item in data.get("items", [])]

        return experiments

    def get_pod_metrics(self) -> Dict[str, Any]:
        """Collect pod metrics"""
        output = self.run_kubectl(["get", "pods", "-n", self.namespace, "-o", "json"])
        if not output:
            return {}

        data = json.loads(output)
        pods = data.get("items", [])

        metrics = {
            "total": len(pods),
            "running": 0,
            "pending": 0,
            "failed": 0,
            "succeeded": 0,
            "unknown": 0,
            "pods": []
        }

        for pod in pods:
            phase = pod["status"].get("phase", "Unknown")
            metrics[phase.lower()] = metrics.get(phase.lower(), 0) + 1

            pod_info = {
                "name": pod["metadata"]["name"],
                "phase": phase,
                "restarts": sum(cs.get("restartCount", 0) for cs in pod["status"].get("containerStatuses", [])),
                "ready": self.is_pod_ready(pod)
            }
            metrics["pods"].append(pod_info)

        return metrics

    def is_pod_ready(self, pod: Dict) -> bool:
        """Check if pod is ready"""
        conditions = pod["status"].get("conditions", [])
        for condition in conditions:
            if condition["type"] == "Ready":
                return condition["status"] == "True"
        return False

    def get_deployment_metrics(self) -> List[Dict[str, Any]]:
        """Collect deployment metrics"""
        output = self.run_kubectl(["get", "deployments", "-n", self.namespace, "-o", "json"])
        if not output:
            return []

        data = json.loads(output)
        deployments = data.get("items", [])

        metrics = []
        for deploy in deployments:
            spec = deploy.get("spec", {})
            status = deploy.get("status", {})

            metrics.append({
                "name": deploy["metadata"]["name"],
                "replicas": spec.get("replicas", 0),
                "ready_replicas": status.get("readyReplicas", 0),
                "available_replicas": status.get("availableReplicas", 0),
                "unavailable_replicas": status.get("unavailableReplicas", 0),
                "updated_replicas": status.get("updatedReplicas", 0)
            })

        return metrics

    def get_service_metrics(self) -> List[Dict[str, Any]]:
        """Collect service metrics"""
        output = self.run_kubectl(["get", "services", "-n", self.namespace, "-o", "json"])
        if not output:
            return []

        data = json.loads(output)
        services = data.get("items", [])

        metrics = []
        for svc in services:
            spec = svc.get("spec", {})
            metrics.append({
                "name": svc["metadata"]["name"],
                "type": spec.get("type", "ClusterIP"),
                "cluster_ip": spec.get("clusterIP"),
                "ports": [{"port": p.get("port"), "protocol": p.get("protocol")} for p in spec.get("ports", [])]
            })

        return metrics

    def collect_snapshot(self) -> Dict[str, Any]:
        """Collect a complete metrics snapshot"""
        return {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "chaos_experiments": self.get_chaos_experiments(),
            "pods": self.get_pod_metrics(),
            "deployments": self.get_deployment_metrics(),
            "services": self.get_service_metrics()
        }

    def monitor(self, duration: int = 300, interval: int = 10):
        """Monitor chaos experiments for specified duration"""
        print(f"Starting chaos monitoring for {duration} seconds...")
        print(f"Collecting metrics every {interval} seconds")
        print(f"Report will be saved to: {self.report_dir}")

        start_time = time.time()
        end_time = start_time + duration

        while time.time() < end_time:
            snapshot = self.collect_snapshot()
            self.metrics.append(snapshot)

            # Print summary
            pod_metrics = snapshot["pods"]
            print(f"\n[{snapshot['timestamp']}]")
            print(f"  Pods: {pod_metrics['total']} total, {pod_metrics['running']} running, {pod_metrics.get('failed', 0)} failed")

            active_experiments = sum(len(v) for v in snapshot["chaos_experiments"].values())
            print(f"  Active chaos experiments: {active_experiments}")

            elapsed = int(time.time() - start_time)
            remaining = int(end_time - time.time())
            print(f"  Elapsed: {elapsed}s, Remaining: {remaining}s")

            time.sleep(interval)

        self.save_report()

    def save_report(self):
        """Save monitoring report to file"""
        os.makedirs(self.report_dir, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        report_file = os.path.join(self.report_dir, f"chaos-monitoring-{timestamp}.json")

        report = {
            "metadata": {
                "namespace": self.namespace,
                "start_time": self.metrics[0]["timestamp"] if self.metrics else None,
                "end_time": self.metrics[-1]["timestamp"] if self.metrics else None,
                "snapshot_count": len(self.metrics)
            },
            "snapshots": self.metrics,
            "summary": self.generate_summary()
        }

        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"\n\nMonitoring report saved to: {report_file}")

        # Also create a human-readable summary
        self.save_summary_report(report)

    def generate_summary(self) -> Dict[str, Any]:
        """Generate summary statistics from collected metrics"""
        if not self.metrics:
            return {}

        total_snapshots = len(self.metrics)

        # Calculate pod statistics
        pod_running = [s["pods"]["running"] for s in self.metrics]
        pod_failed = [s["pods"].get("failed", 0) for s in self.metrics]

        # Calculate deployment statistics
        all_deployments = {}
        for snapshot in self.metrics:
            for deploy in snapshot["deployments"]:
                name = deploy["name"]
                if name not in all_deployments:
                    all_deployments[name] = {"ready": [], "unavailable": []}
                all_deployments[name]["ready"].append(deploy["ready_replicas"])
                all_deployments[name]["unavailable"].append(deploy.get("unavailable_replicas", 0))

        return {
            "duration_seconds": total_snapshots * 10,
            "total_snapshots": total_snapshots,
            "pods": {
                "avg_running": sum(pod_running) / len(pod_running) if pod_running else 0,
                "max_running": max(pod_running) if pod_running else 0,
                "min_running": min(pod_running) if pod_running else 0,
                "total_failures": sum(pod_failed)
            },
            "deployments": {
                name: {
                    "avg_ready": sum(stats["ready"]) / len(stats["ready"]) if stats["ready"] else 0,
                    "max_unavailable": max(stats["unavailable"]) if stats["unavailable"] else 0
                }
                for name, stats in all_deployments.items()
            }
        }

    def save_summary_report(self, report: Dict[str, Any]):
        """Save a human-readable summary report"""
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        summary_file = os.path.join(self.report_dir, f"chaos-summary-{timestamp}.txt")

        with open(summary_file, 'w') as f:
            f.write("=" * 80 + "\n")
            f.write("CHAOS ENGINEERING MONITORING SUMMARY\n")
            f.write("=" * 80 + "\n\n")

            metadata = report["metadata"]
            f.write(f"Namespace: {metadata['namespace']}\n")
            f.write(f"Start Time: {metadata['start_time']}\n")
            f.write(f"End Time: {metadata['end_time']}\n")
            f.write(f"Total Snapshots: {metadata['snapshot_count']}\n\n")

            summary = report["summary"]
            f.write("POD STATISTICS:\n")
            f.write("-" * 80 + "\n")
            pod_stats = summary.get("pods", {})
            f.write(f"  Average Running Pods: {pod_stats.get('avg_running', 0):.2f}\n")
            f.write(f"  Max Running Pods: {pod_stats.get('max_running', 0)}\n")
            f.write(f"  Min Running Pods: {pod_stats.get('min_running', 0)}\n")
            f.write(f"  Total Failures: {pod_stats.get('total_failures', 0)}\n\n")

            f.write("DEPLOYMENT STATISTICS:\n")
            f.write("-" * 80 + "\n")
            for deploy_name, deploy_stats in summary.get("deployments", {}).items():
                f.write(f"  {deploy_name}:\n")
                f.write(f"    Average Ready Replicas: {deploy_stats['avg_ready']:.2f}\n")
                f.write(f"    Max Unavailable Replicas: {deploy_stats['max_unavailable']}\n")

            f.write("\n" + "=" * 80 + "\n")

        print(f"Summary report saved to: {summary_file}")

def main():
    """Main function"""
    import argparse

    parser = argparse.ArgumentParser(description="Monitor chaos engineering experiments")
    parser.add_argument("--namespace", "-n", default="default", help="Kubernetes namespace")
    parser.add_argument("--duration", "-d", type=int, default=300, help="Monitoring duration in seconds")
    parser.add_argument("--interval", "-i", type=int, default=10, help="Snapshot interval in seconds")
    parser.add_argument("--report-dir", "-r", default="/home/user/A2A/chaos-engineering/reports", help="Report directory")

    args = parser.parse_args()

    monitor = ChaosMonitor(namespace=args.namespace, report_dir=args.report_dir)

    try:
        monitor.monitor(duration=args.duration, interval=args.interval)
    except KeyboardInterrupt:
        print("\n\nMonitoring interrupted by user")
        monitor.save_report()
        sys.exit(0)

if __name__ == "__main__":
    main()
