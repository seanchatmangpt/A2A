#!/usr/bin/env python3
"""
SLA Validation Script for A2A Protocol
Validates service level agreements for the A2A system
"""

import asyncio
import json
import logging
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from typing import List, Dict, Any
import aiohttp

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class SLADefinition:
    """Service Level Agreement definition"""
    name: str
    description: str
    metric_type: str  # latency, availability, throughput, resource
    threshold: float
    operator: str  # lt, lte, gt, gte, eq
    critical: bool = True
    measurement_window_seconds: int = 60


@dataclass
class SLAResult:
    """SLA validation result"""
    sla_name: str
    measured_value: float
    threshold: float
    passed: bool
    timestamp: datetime
    details: Dict[str, Any] = None

    def to_dict(self):
        result = asdict(self)
        result['timestamp'] = self.timestamp.isoformat()
        return result


class SLAValidator:
    """Validates SLA compliance for A2A system"""

    def __init__(self, base_url: str = "http://localhost:8001"):
        self.base_url = base_url
        self.sla_definitions = self._define_slas()
        self.results: List[SLAResult] = []

    def _define_slas(self) -> List[SLADefinition]:
        """Define SLA requirements"""
        return [
            # Availability SLAs
            SLADefinition(
                name="System Availability",
                description="System must be available 99.9% of the time",
                metric_type="availability",
                threshold=99.9,
                operator="gte",
                critical=True
            ),
            SLADefinition(
                name="Health Check Success Rate",
                description="Health check must succeed 99.95% of the time",
                metric_type="availability",
                threshold=99.95,
                operator="gte",
                critical=True
            ),

            # Latency SLAs
            SLADefinition(
                name="Health Check P50 Latency",
                description="50th percentile health check latency under 20ms",
                metric_type="latency",
                threshold=20.0,
                operator="lte",
                critical=False
            ),
            SLADefinition(
                name="Health Check P95 Latency",
                description="95th percentile health check latency under 100ms",
                metric_type="latency",
                threshold=100.0,
                operator="lte",
                critical=True
            ),
            SLADefinition(
                name="Health Check P99 Latency",
                description="99th percentile health check latency under 200ms",
                metric_type="latency",
                threshold=200.0,
                operator="lte",
                critical=True
            ),
            SLADefinition(
                name="API Endpoint P95 Latency",
                description="95th percentile API latency under 150ms",
                metric_type="latency",
                threshold=150.0,
                operator="lte",
                critical=True
            ),
            SLADefinition(
                name="Agent Discovery P95 Latency",
                description="95th percentile agent discovery latency under 200ms",
                metric_type="latency",
                threshold=200.0,
                operator="lte",
                critical=False
            ),
            SLADefinition(
                name="Workflow Query P95 Latency",
                description="95th percentile workflow query latency under 200ms",
                metric_type="latency",
                threshold=200.0,
                operator="lte",
                critical=False
            ),

            # Throughput SLAs
            SLADefinition(
                name="Minimum Throughput",
                description="System must handle at least 100 requests/second",
                metric_type="throughput",
                threshold=100.0,
                operator="gte",
                critical=True
            ),
            SLADefinition(
                name="Burst Throughput",
                description="System must handle at least 500 requests/second in burst",
                metric_type="throughput",
                threshold=500.0,
                operator="gte",
                critical=False
            ),

            # Resource SLAs
            SLADefinition(
                name="CPU Utilization",
                description="Average CPU utilization under 80%",
                metric_type="resource",
                threshold=80.0,
                operator="lte",
                critical=False
            ),
            SLADefinition(
                name="Memory Usage",
                description="Average memory usage under 512MB",
                metric_type="resource",
                threshold=512.0,
                operator="lte",
                critical=False
            ),
            SLADefinition(
                name="Peak Memory Usage",
                description="Peak memory usage under 1GB",
                metric_type="resource",
                threshold=1024.0,
                operator="lte",
                critical=True
            ),

            # Error Rate SLAs
            SLADefinition(
                name="Error Rate",
                description="Error rate must be less than 0.1%",
                metric_type="error_rate",
                threshold=0.1,
                operator="lte",
                critical=True
            ),
        ]

    async def validate_all_slas(self) -> List[SLAResult]:
        """Validate all SLA definitions"""
        logger.info("=" * 80)
        logger.info("Starting SLA Validation")
        logger.info("=" * 80)

        # Validate each SLA
        for sla in self.sla_definitions:
            result = await self.validate_sla(sla)
            self.results.append(result)

        # Generate report
        self.generate_report()

        return self.results

    async def validate_sla(self, sla: SLADefinition) -> SLAResult:
        """Validate a single SLA"""
        logger.info(f"\nValidating SLA: {sla.name}")
        logger.info(f"  Description: {sla.description}")
        logger.info(f"  Type: {sla.metric_type}")
        logger.info(f"  Threshold: {sla.threshold} ({sla.operator})")

        try:
            if sla.metric_type == "availability":
                measured_value = await self._measure_availability(sla)
            elif sla.metric_type == "latency":
                measured_value = await self._measure_latency(sla)
            elif sla.metric_type == "throughput":
                measured_value = await self._measure_throughput(sla)
            elif sla.metric_type == "resource":
                measured_value = await self._measure_resource_usage(sla)
            elif sla.metric_type == "error_rate":
                measured_value = await self._measure_error_rate(sla)
            else:
                logger.error(f"Unknown metric type: {sla.metric_type}")
                measured_value = 0.0

            # Compare against threshold
            passed = self._evaluate_threshold(measured_value, sla.threshold, sla.operator)

            result = SLAResult(
                sla_name=sla.name,
                measured_value=measured_value,
                threshold=sla.threshold,
                passed=passed,
                timestamp=datetime.now(),
                details={
                    'metric_type': sla.metric_type,
                    'operator': sla.operator,
                    'critical': sla.critical
                }
            )

            status = "PASS" if passed else "FAIL"
            criticality = " [CRITICAL]" if sla.critical and not passed else ""
            logger.info(f"  Result: {status}{criticality}")
            logger.info(f"  Measured: {measured_value:.2f}")

            return result

        except Exception as e:
            logger.error(f"  Error validating SLA: {e}")
            return SLAResult(
                sla_name=sla.name,
                measured_value=0.0,
                threshold=sla.threshold,
                passed=False,
                timestamp=datetime.now(),
                details={'error': str(e)}
            )

    async def _measure_availability(self, sla: SLADefinition) -> float:
        """Measure system availability"""
        num_checks = 100
        successes = 0

        async with aiohttp.ClientSession() as session:
            for _ in range(num_checks):
                try:
                    async with session.get(
                        f"{self.base_url}/health",
                        timeout=aiohttp.ClientTimeout(total=5)
                    ) as resp:
                        if resp.status == 200:
                            successes += 1
                except Exception:
                    pass

                await asyncio.sleep(0.01)

        availability = (successes / num_checks) * 100
        return availability

    async def _measure_latency(self, sla: SLADefinition) -> float:
        """Measure latency metrics"""
        import time

        # Determine endpoint based on SLA name
        endpoint = "/health"
        if "Agent Discovery" in sla.name:
            endpoint = "/agents"
        elif "Workflow" in sla.name:
            endpoint = "/workflows"
        elif "API Endpoint" in sla.name:
            endpoint = "/metrics"

        num_requests = 200
        latencies = []

        async with aiohttp.ClientSession() as session:
            for _ in range(num_requests):
                try:
                    start = time.perf_counter()
                    async with session.get(
                        f"{self.base_url}{endpoint}",
                        timeout=aiohttp.ClientTimeout(total=5)
                    ) as resp:
                        await resp.text()
                        end = time.perf_counter()
                        latencies.append((end - start) * 1000)  # Convert to ms
                except Exception:
                    pass

        if not latencies:
            return float('inf')

        latencies.sort()

        # Determine percentile based on SLA name
        if "P50" in sla.name:
            return latencies[int(len(latencies) * 0.50)]
        elif "P95" in sla.name:
            return latencies[int(len(latencies) * 0.95)]
        elif "P99" in sla.name:
            return latencies[int(len(latencies) * 0.99)]
        else:
            return sum(latencies) / len(latencies)

    async def _measure_throughput(self, sla: SLADefinition) -> float:
        """Measure throughput"""
        import time

        duration = 5  # 5 seconds
        concurrency = 100 if "Burst" in sla.name else 50

        start_time = time.time()
        request_count = 0
        semaphore = asyncio.Semaphore(concurrency)

        async def make_request(session):
            nonlocal request_count
            async with semaphore:
                try:
                    async with session.get(
                        f"{self.base_url}/health",
                        timeout=aiohttp.ClientTimeout(total=5)
                    ) as resp:
                        await resp.text()
                        request_count += 1
                except Exception:
                    pass

        async with aiohttp.ClientSession() as session:
            # Run for duration
            tasks = []
            while time.time() - start_time < duration:
                task = asyncio.create_task(make_request(session))
                tasks.append(task)
                await asyncio.sleep(0.001)  # Small delay

            await asyncio.gather(*tasks, return_exceptions=True)

        elapsed = time.time() - start_time
        throughput = request_count / elapsed if elapsed > 0 else 0

        return throughput

    async def _measure_resource_usage(self, sla: SLADefinition) -> float:
        """Measure resource usage"""
        import psutil
        import os

        process = psutil.Process(os.getpid())

        if "CPU" in sla.name:
            # Measure CPU over a period
            measurements = []
            for _ in range(10):
                measurements.append(process.cpu_percent(interval=0.1))
                await asyncio.sleep(0.1)
            return sum(measurements) / len(measurements)

        elif "Memory" in sla.name:
            memory_mb = process.memory_info().rss / 1024 / 1024
            return memory_mb

        return 0.0

    async def _measure_error_rate(self, sla: SLADefinition) -> float:
        """Measure error rate"""
        num_checks = 100
        failures = 0

        async with aiohttp.ClientSession() as session:
            for _ in range(num_checks):
                try:
                    async with session.get(
                        f"{self.base_url}/health",
                        timeout=aiohttp.ClientTimeout(total=5)
                    ) as resp:
                        if resp.status != 200:
                            failures += 1
                except Exception:
                    failures += 1

                await asyncio.sleep(0.01)

        error_rate = (failures / num_checks) * 100
        return error_rate

    def _evaluate_threshold(self, value: float, threshold: float, operator: str) -> bool:
        """Evaluate value against threshold"""
        if operator == "lt":
            return value < threshold
        elif operator == "lte":
            return value <= threshold
        elif operator == "gt":
            return value > threshold
        elif operator == "gte":
            return value >= threshold
        elif operator == "eq":
            return abs(value - threshold) < 0.01
        else:
            return False

    def generate_report(self):
        """Generate SLA validation report"""
        logger.info("\n" + "=" * 80)
        logger.info("SLA VALIDATION REPORT")
        logger.info("=" * 80)

        total_slas = len(self.results)
        passed_slas = sum(1 for r in self.results if r.passed)
        failed_slas = total_slas - passed_slas

        critical_failed = [
            r for r in self.results
            if not r.passed and r.details and r.details.get('critical', False)
        ]

        logger.info(f"\nSummary:")
        logger.info(f"  Total SLAs: {total_slas}")
        logger.info(f"  Passed: {passed_slas} ({(passed_slas/total_slas)*100:.1f}%)")
        logger.info(f"  Failed: {failed_slas} ({(failed_slas/total_slas)*100:.1f}%)")
        logger.info(f"  Critical Failures: {len(critical_failed)}")

        # Failed SLAs
        if failed_slas > 0:
            logger.warning(f"\nFailed SLAs:")
            for result in self.results:
                if not result.passed:
                    critical_tag = " [CRITICAL]" if result.details and result.details.get('critical') else ""
                    logger.warning(f"  - {result.sla_name}{critical_tag}")
                    logger.warning(f"    Measured: {result.measured_value:.2f}, Threshold: {result.threshold:.2f}")

        # Save results
        self._save_results()

        # Overall compliance
        if len(critical_failed) > 0:
            logger.error("\n❌ SLA VALIDATION FAILED - Critical SLAs not met")
        elif failed_slas > 0:
            logger.warning("\n⚠️  SLA VALIDATION WARNING - Some non-critical SLAs not met")
        else:
            logger.info("\n✅ SLA VALIDATION PASSED - All SLAs met")

        logger.info("=" * 80)

    def _save_results(self):
        """Save validation results to file"""
        import os

        output_file = f"/home/user/A2A/tests/performance/sla_validation_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

        results_data = {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'total_slas': len(self.results),
                'passed': sum(1 for r in self.results if r.passed),
                'failed': sum(1 for r in self.results if not r.passed),
                'critical_failures': sum(
                    1 for r in self.results
                    if not r.passed and r.details and r.details.get('critical', False)
                )
            },
            'results': [r.to_dict() for r in self.results]
        }

        os.makedirs(os.path.dirname(output_file), exist_ok=True)
        with open(output_file, 'w') as f:
            json.dump(results_data, f, indent=2)

        logger.info(f"\nResults saved to: {output_file}")


async def main():
    """Main entry point"""
    # Check if server is available
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "http://localhost:8001/health",
                timeout=aiohttp.ClientTimeout(total=5)
            ) as resp:
                if resp.status != 200:
                    logger.warning("API server is not responding correctly")
    except Exception as e:
        logger.warning(f"Cannot connect to API server: {e}")
        logger.warning("Please start the API server at http://localhost:8001")

    validator = SLAValidator(base_url="http://localhost:8001")
    await validator.validate_all_slas()


if __name__ == "__main__":
    asyncio.run(main())
