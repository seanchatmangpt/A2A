#!/usr/bin/env python3
"""
Performance Benchmark Suite for A2A Protocol
Tests latency, throughput, resource usage, and SLA compliance
"""

import asyncio
import json
import logging
import os
import statistics
import time
import psutil
import aiohttp
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional
from concurrent.futures import ThreadPoolExecutor
import multiprocessing as mp

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class PerformanceMetrics:
    """Performance metrics data structure"""
    test_name: str
    start_time: datetime
    end_time: datetime
    duration_seconds: float

    # Latency metrics (ms)
    min_latency: float
    max_latency: float
    avg_latency: float
    p50_latency: float
    p95_latency: float
    p99_latency: float

    # Throughput metrics
    total_requests: int
    successful_requests: int
    failed_requests: int
    requests_per_second: float

    # Resource metrics
    avg_cpu_percent: float
    max_cpu_percent: float
    avg_memory_mb: float
    max_memory_mb: float
    avg_disk_io_read_mb: float
    avg_disk_io_write_mb: float

    # SLA compliance
    sla_target_latency_ms: float
    sla_target_success_rate: float
    sla_latency_compliance: bool
    sla_success_rate_compliance: bool
    sla_overall_pass: bool

    def to_dict(self):
        """Convert to dictionary"""
        result = asdict(self)
        result['start_time'] = self.start_time.isoformat()
        result['end_time'] = self.end_time.isoformat()
        return result


@dataclass
class SLATargets:
    """SLA target definitions"""
    max_latency_ms: float = 100.0  # 100ms p95 latency
    max_p99_latency_ms: float = 200.0  # 200ms p99 latency
    min_success_rate: float = 99.9  # 99.9% success rate
    max_cpu_percent: float = 80.0  # 80% CPU utilization
    max_memory_mb: float = 512.0  # 512MB memory usage
    min_throughput_rps: float = 100.0  # 100 requests per second


class ResourceMonitor:
    """Monitor system resource usage"""

    def __init__(self, pid: Optional[int] = None):
        self.pid = pid or os.getpid()
        self.process = psutil.Process(self.pid)
        self.monitoring = False
        self.measurements = []
        self.start_io = None

    async def start(self):
        """Start monitoring"""
        self.monitoring = True
        self.measurements = []
        try:
            self.start_io = self.process.io_counters()
        except (psutil.NoSuchProcess, psutil.AccessDenied, ValueError, AttributeError):
            # I/O counters might not be available in all environments
            self.start_io = None
            logger.debug("I/O counters not available in this environment")

        asyncio.create_task(self._monitor())

    async def stop(self) -> Dict[str, float]:
        """Stop monitoring and return metrics"""
        self.monitoring = False
        await asyncio.sleep(0.5)  # Allow final measurement

        if not self.measurements:
            return self._get_empty_metrics()

        # Calculate statistics
        cpu_values = [m['cpu'] for m in self.measurements]
        memory_values = [m['memory'] for m in self.measurements]

        metrics = {
            'avg_cpu_percent': statistics.mean(cpu_values),
            'max_cpu_percent': max(cpu_values),
            'avg_memory_mb': statistics.mean(memory_values),
            'max_memory_mb': max(memory_values),
            'avg_disk_io_read_mb': 0.0,
            'avg_disk_io_write_mb': 0.0
        }

        # Calculate disk I/O if available
        if self.start_io:
            try:
                end_io = self.process.io_counters()
                duration = len(self.measurements) * 0.1  # 100ms intervals
                if duration > 0:
                    read_bytes = end_io.read_bytes - self.start_io.read_bytes
                    write_bytes = end_io.write_bytes - self.start_io.write_bytes
                    metrics['avg_disk_io_read_mb'] = (read_bytes / 1024 / 1024) / duration
                    metrics['avg_disk_io_write_mb'] = (write_bytes / 1024 / 1024) / duration
            except (psutil.NoSuchProcess, psutil.AccessDenied, ValueError, AttributeError):
                logger.debug("I/O counters not available for final measurement")
                pass

        return metrics

    async def _monitor(self):
        """Background monitoring loop"""
        while self.monitoring:
            try:
                cpu = self.process.cpu_percent(interval=0.1)
                memory = self.process.memory_info().rss / 1024 / 1024  # MB

                self.measurements.append({
                    'cpu': cpu,
                    'memory': memory,
                    'timestamp': time.time()
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                logger.warning("Process not accessible for monitoring")
                break

            await asyncio.sleep(0.1)  # Sample every 100ms

    def _get_empty_metrics(self) -> Dict[str, float]:
        """Return empty metrics"""
        return {
            'avg_cpu_percent': 0.0,
            'max_cpu_percent': 0.0,
            'avg_memory_mb': 0.0,
            'max_memory_mb': 0.0,
            'avg_disk_io_read_mb': 0.0,
            'avg_disk_io_write_mb': 0.0
        }


class PerformanceBenchmark:
    """Main performance benchmark suite"""

    def __init__(self, base_url: str = "http://localhost:8001", sla_targets: SLATargets = None):
        self.base_url = base_url
        self.sla_targets = sla_targets or SLATargets()
        self.results: List[PerformanceMetrics] = []

    async def run_all_benchmarks(self) -> List[PerformanceMetrics]:
        """Run all performance benchmarks"""
        logger.info("=" * 80)
        logger.info("Starting A2A Protocol Performance Benchmark Suite")
        logger.info("=" * 80)

        # Test 1: Health Check Latency
        await self.test_health_check_latency()

        # Test 2: API Endpoint Latency
        await self.test_api_endpoint_latency()

        # Test 3: Throughput - Concurrent Requests
        await self.test_concurrent_throughput()

        # Test 4: Burst Load Test
        await self.test_burst_load()

        # Test 5: Sustained Load Test
        await self.test_sustained_load()

        # Test 6: Resource Usage Under Load
        await self.test_resource_usage()

        # Test 7: Agent Discovery Performance
        await self.test_agent_discovery_performance()

        # Test 8: Workflow Orchestration Performance
        await self.test_workflow_performance()

        # Generate summary report
        self.generate_summary_report()

        return self.results

    async def test_health_check_latency(self):
        """Test health check endpoint latency"""
        logger.info("\n--- Test 1: Health Check Latency ---")

        test_name = "health_check_latency"
        num_requests = 1000

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            for i in range(num_requests):
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}/health", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if resp.status == 200:
                            successes += 1
                        else:
                            failures += 1
                except Exception as e:
                    failures += 1
                    logger.debug(f"Request failed: {e}")

                if (i + 1) % 100 == 0:
                    logger.info(f"  Progress: {i + 1}/{num_requests} requests")

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        self._log_metrics(metrics)
        self.results.append(metrics)

    async def test_api_endpoint_latency(self):
        """Test various API endpoint latencies"""
        logger.info("\n--- Test 2: API Endpoint Latency ---")

        endpoints = [
            "/health",
            "/bridge/status",
            "/agents",
            "/workflows",
            "/metrics",
            "/config",
            "/system/info"
        ]

        for endpoint in endpoints:
            await self._test_single_endpoint_latency(endpoint)

    async def _test_single_endpoint_latency(self, endpoint: str):
        """Test latency for a single endpoint"""
        test_name = f"endpoint_latency_{endpoint.replace('/', '_')}"
        num_requests = 500

        logger.info(f"  Testing endpoint: {endpoint}")

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            for _ in range(num_requests):
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}{endpoint}", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if 200 <= resp.status < 300:
                            successes += 1
                        else:
                            failures += 1
                except Exception as e:
                    failures += 1
                    logger.debug(f"Request failed: {e}")

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        logger.info(f"    Avg latency: {metrics.avg_latency:.2f}ms, "
                   f"P95: {metrics.p95_latency:.2f}ms, "
                   f"Success rate: {(successes/num_requests)*100:.2f}%")

        self.results.append(metrics)

    async def test_concurrent_throughput(self):
        """Test throughput with concurrent requests"""
        logger.info("\n--- Test 3: Concurrent Throughput ---")

        concurrency_levels = [10, 50, 100, 200]

        for concurrency in concurrency_levels:
            await self._test_throughput_at_concurrency(concurrency)

    async def _test_throughput_at_concurrency(self, concurrency: int):
        """Test throughput at specific concurrency level"""
        test_name = f"concurrent_throughput_{concurrency}"
        num_requests = 1000

        logger.info(f"  Testing with {concurrency} concurrent connections...")

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        semaphore = asyncio.Semaphore(concurrency)

        async def make_request(session):
            nonlocal successes, failures
            async with semaphore:
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}/health", timeout=aiohttp.ClientTimeout(total=10)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if resp.status == 200:
                            successes += 1
                        else:
                            failures += 1
                except Exception as e:
                    failures += 1

        async with aiohttp.ClientSession() as session:
            tasks = [make_request(session) for _ in range(num_requests)]
            await asyncio.gather(*tasks, return_exceptions=True)

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        logger.info(f"    Throughput: {metrics.requests_per_second:.2f} req/s, "
                   f"Avg latency: {metrics.avg_latency:.2f}ms")

        self.results.append(metrics)

    async def test_burst_load(self):
        """Test system behavior under burst load"""
        logger.info("\n--- Test 4: Burst Load Test ---")

        test_name = "burst_load"
        num_requests = 500
        burst_size = 50

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            for burst in range(num_requests // burst_size):
                tasks = []
                for _ in range(burst_size):
                    async def make_request():
                        nonlocal successes, failures
                        try:
                            req_start = time.perf_counter()
                            async with session.get(f"{self.base_url}/health", timeout=aiohttp.ClientTimeout(total=10)) as resp:
                                await resp.text()
                                req_end = time.perf_counter()

                                latency_ms = (req_end - req_start) * 1000
                                latencies.append(latency_ms)

                                if resp.status == 200:
                                    successes += 1
                                else:
                                    failures += 1
                        except Exception:
                            failures += 1

                    tasks.append(make_request())

                await asyncio.gather(*tasks, return_exceptions=True)
                await asyncio.sleep(0.1)  # Brief pause between bursts

                if (burst + 1) % 2 == 0:
                    logger.info(f"  Completed {(burst + 1) * burst_size} requests")

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        self._log_metrics(metrics)
        self.results.append(metrics)

    async def test_sustained_load(self):
        """Test system under sustained load"""
        logger.info("\n--- Test 5: Sustained Load Test (30 seconds) ---")

        test_name = "sustained_load"
        duration_seconds = 30
        target_rps = 50

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            end_time_target = time.time() + duration_seconds
            request_count = 0

            while time.time() < end_time_target:
                batch_start = time.time()

                async def make_request():
                    nonlocal successes, failures
                    try:
                        req_start = time.perf_counter()
                        async with session.get(f"{self.base_url}/health", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                            await resp.text()
                            req_end = time.perf_counter()

                            latency_ms = (req_end - req_start) * 1000
                            latencies.append(latency_ms)

                            if resp.status == 200:
                                successes += 1
                            else:
                                failures += 1
                    except Exception:
                        failures += 1

                # Send target_rps requests per second
                tasks = [make_request() for _ in range(target_rps)]
                await asyncio.gather(*tasks, return_exceptions=True)

                request_count += target_rps

                # Maintain rate
                elapsed = time.time() - batch_start
                sleep_time = max(0, 1.0 - elapsed)
                await asyncio.sleep(sleep_time)

                if request_count % 250 == 0:
                    logger.info(f"  Progress: {request_count} requests sent")

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        self._log_metrics(metrics)
        self.results.append(metrics)

    async def test_resource_usage(self):
        """Test resource usage patterns"""
        logger.info("\n--- Test 6: Resource Usage Under Load ---")

        test_name = "resource_usage"
        num_requests = 1000
        concurrency = 100

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        semaphore = asyncio.Semaphore(concurrency)

        async def make_request(session):
            nonlocal successes, failures
            async with semaphore:
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}/metrics", timeout=aiohttp.ClientTimeout(total=10)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if resp.status == 200:
                            successes += 1
                        else:
                            failures += 1
                except Exception:
                    failures += 1

        async with aiohttp.ClientSession() as session:
            tasks = [make_request(session) for _ in range(num_requests)]
            await asyncio.gather(*tasks, return_exceptions=True)

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        logger.info(f"  CPU Usage - Avg: {metrics.avg_cpu_percent:.2f}%, "
                   f"Max: {metrics.max_cpu_percent:.2f}%")
        logger.info(f"  Memory Usage - Avg: {metrics.avg_memory_mb:.2f}MB, "
                   f"Max: {metrics.max_memory_mb:.2f}MB")

        self.results.append(metrics)

    async def test_agent_discovery_performance(self):
        """Test agent discovery endpoint performance"""
        logger.info("\n--- Test 7: Agent Discovery Performance ---")

        test_name = "agent_discovery"
        num_requests = 300

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            for _ in range(num_requests):
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}/agents", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if 200 <= resp.status < 300:
                            successes += 1
                        else:
                            failures += 1
                except Exception:
                    failures += 1

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        self._log_metrics(metrics)
        self.results.append(metrics)

    async def test_workflow_performance(self):
        """Test workflow orchestration performance"""
        logger.info("\n--- Test 8: Workflow Orchestration Performance ---")

        test_name = "workflow_orchestration"
        num_requests = 300

        monitor = ResourceMonitor()
        await monitor.start()

        start_time = datetime.now()
        latencies = []
        successes = 0
        failures = 0

        async with aiohttp.ClientSession() as session:
            for _ in range(num_requests):
                try:
                    req_start = time.perf_counter()
                    async with session.get(f"{self.base_url}/workflows", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                        await resp.text()
                        req_end = time.perf_counter()

                        latency_ms = (req_end - req_start) * 1000
                        latencies.append(latency_ms)

                        if 200 <= resp.status < 300:
                            successes += 1
                        else:
                            failures += 1
                except Exception:
                    failures += 1

        end_time = datetime.now()
        resource_metrics = await monitor.stop()

        metrics = self._calculate_metrics(
            test_name, start_time, end_time, latencies,
            successes, failures, resource_metrics
        )

        self._log_metrics(metrics)
        self.results.append(metrics)

    def _calculate_metrics(
        self, test_name: str, start_time: datetime, end_time: datetime,
        latencies: List[float], successes: int, failures: int,
        resource_metrics: Dict[str, float]
    ) -> PerformanceMetrics:
        """Calculate performance metrics"""

        duration = (end_time - start_time).total_seconds()
        total_requests = successes + failures

        if latencies:
            sorted_latencies = sorted(latencies)
            min_latency = min(sorted_latencies)
            max_latency = max(sorted_latencies)
            avg_latency = statistics.mean(sorted_latencies)
            p50_latency = sorted_latencies[int(len(sorted_latencies) * 0.50)]
            p95_latency = sorted_latencies[int(len(sorted_latencies) * 0.95)]
            p99_latency = sorted_latencies[int(len(sorted_latencies) * 0.99)]
        else:
            min_latency = max_latency = avg_latency = 0
            p50_latency = p95_latency = p99_latency = 0

        rps = total_requests / duration if duration > 0 else 0
        success_rate = (successes / total_requests * 100) if total_requests > 0 else 0

        # SLA compliance checks
        sla_latency_pass = p95_latency <= self.sla_targets.max_latency_ms
        sla_success_pass = success_rate >= self.sla_targets.min_success_rate
        sla_overall_pass = sla_latency_pass and sla_success_pass

        return PerformanceMetrics(
            test_name=test_name,
            start_time=start_time,
            end_time=end_time,
            duration_seconds=duration,
            min_latency=min_latency,
            max_latency=max_latency,
            avg_latency=avg_latency,
            p50_latency=p50_latency,
            p95_latency=p95_latency,
            p99_latency=p99_latency,
            total_requests=total_requests,
            successful_requests=successes,
            failed_requests=failures,
            requests_per_second=rps,
            avg_cpu_percent=resource_metrics['avg_cpu_percent'],
            max_cpu_percent=resource_metrics['max_cpu_percent'],
            avg_memory_mb=resource_metrics['avg_memory_mb'],
            max_memory_mb=resource_metrics['max_memory_mb'],
            avg_disk_io_read_mb=resource_metrics['avg_disk_io_read_mb'],
            avg_disk_io_write_mb=resource_metrics['avg_disk_io_write_mb'],
            sla_target_latency_ms=self.sla_targets.max_latency_ms,
            sla_target_success_rate=self.sla_targets.min_success_rate,
            sla_latency_compliance=sla_latency_pass,
            sla_success_rate_compliance=sla_success_pass,
            sla_overall_pass=sla_overall_pass
        )

    def _log_metrics(self, metrics: PerformanceMetrics):
        """Log performance metrics"""
        logger.info(f"\n  Results for {metrics.test_name}:")
        logger.info(f"    Duration: {metrics.duration_seconds:.2f}s")
        logger.info(f"    Total Requests: {metrics.total_requests}")
        logger.info(f"    Success Rate: {(metrics.successful_requests/metrics.total_requests)*100:.2f}%")
        logger.info(f"    Throughput: {metrics.requests_per_second:.2f} req/s")
        logger.info(f"    Latency - Min: {metrics.min_latency:.2f}ms, "
                   f"Avg: {metrics.avg_latency:.2f}ms, "
                   f"Max: {metrics.max_latency:.2f}ms")
        logger.info(f"    Latency - P50: {metrics.p50_latency:.2f}ms, "
                   f"P95: {metrics.p95_latency:.2f}ms, "
                   f"P99: {metrics.p99_latency:.2f}ms")
        logger.info(f"    CPU - Avg: {metrics.avg_cpu_percent:.2f}%, "
                   f"Max: {metrics.max_cpu_percent:.2f}%")
        logger.info(f"    Memory - Avg: {metrics.avg_memory_mb:.2f}MB, "
                   f"Max: {metrics.max_memory_mb:.2f}MB")
        logger.info(f"    SLA Compliance: {'PASS' if metrics.sla_overall_pass else 'FAIL'}")

    def generate_summary_report(self):
        """Generate summary report"""
        logger.info("\n" + "=" * 80)
        logger.info("PERFORMANCE BENCHMARK SUMMARY REPORT")
        logger.info("=" * 80)

        if not self.results:
            logger.warning("No benchmark results available")
            return

        # Overall statistics
        total_tests = len(self.results)
        passed_tests = sum(1 for r in self.results if r.sla_overall_pass)
        failed_tests = total_tests - passed_tests

        logger.info(f"\nOverall Results:")
        logger.info(f"  Total Tests: {total_tests}")
        logger.info(f"  Passed SLA: {passed_tests} ({(passed_tests/total_tests)*100:.1f}%)")
        logger.info(f"  Failed SLA: {failed_tests} ({(failed_tests/total_tests)*100:.1f}%)")

        # SLA Targets
        logger.info(f"\nSLA Targets:")
        logger.info(f"  Max P95 Latency: {self.sla_targets.max_latency_ms}ms")
        logger.info(f"  Max P99 Latency: {self.sla_targets.max_p99_latency_ms}ms")
        logger.info(f"  Min Success Rate: {self.sla_targets.min_success_rate}%")
        logger.info(f"  Max CPU Usage: {self.sla_targets.max_cpu_percent}%")
        logger.info(f"  Max Memory Usage: {self.sla_targets.max_memory_mb}MB")

        # Best and worst performers
        best_latency = min(self.results, key=lambda r: r.avg_latency)
        worst_latency = max(self.results, key=lambda r: r.avg_latency)
        best_throughput = max(self.results, key=lambda r: r.requests_per_second)

        logger.info(f"\nPerformance Highlights:")
        logger.info(f"  Best Latency: {best_latency.test_name} ({best_latency.avg_latency:.2f}ms avg)")
        logger.info(f"  Worst Latency: {worst_latency.test_name} ({worst_latency.avg_latency:.2f}ms avg)")
        logger.info(f"  Best Throughput: {best_throughput.test_name} ({best_throughput.requests_per_second:.2f} req/s)")

        # Failed SLA tests
        failed_sla = [r for r in self.results if not r.sla_overall_pass]
        if failed_sla:
            logger.warning(f"\nSLA Failures ({len(failed_sla)} tests):")
            for result in failed_sla:
                reasons = []
                if not result.sla_latency_compliance:
                    reasons.append(f"P95 latency {result.p95_latency:.2f}ms > {result.sla_target_latency_ms}ms")
                if not result.sla_success_rate_compliance:
                    success_rate = (result.successful_requests / result.total_requests) * 100
                    reasons.append(f"Success rate {success_rate:.2f}% < {result.sla_target_success_rate}%")
                logger.warning(f"  {result.test_name}: {', '.join(reasons)}")

        # Save results to file
        self._save_results()

        logger.info("\n" + "=" * 80)
        logger.info("Benchmark suite completed")
        logger.info("=" * 80)

    def _save_results(self):
        """Save results to JSON file"""
        output_file = f"/home/user/A2A/tests/performance/benchmark_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

        results_data = {
            'timestamp': datetime.now().isoformat(),
            'sla_targets': asdict(self.sla_targets),
            'summary': {
                'total_tests': len(self.results),
                'passed_sla': sum(1 for r in self.results if r.sla_overall_pass),
                'failed_sla': sum(1 for r in self.results if not r.sla_overall_pass)
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
            async with session.get("http://localhost:8001/health", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                if resp.status != 200:
                    logger.warning("API server is not responding correctly. Running in mock mode...")
                    logger.warning("Start the API server first for accurate benchmarks.")
    except Exception as e:
        logger.warning(f"Cannot connect to API server: {e}")
        logger.warning("Please start the API server at http://localhost:8001")
        logger.warning("Some tests may fail or return mock data.")

    # Run benchmarks
    benchmark = PerformanceBenchmark(
        base_url="http://localhost:8001",
        sla_targets=SLATargets(
            max_latency_ms=100.0,
            max_p99_latency_ms=200.0,
            min_success_rate=99.0,
            max_cpu_percent=80.0,
            max_memory_mb=512.0,
            min_throughput_rps=100.0
        )
    )

    await benchmark.run_all_benchmarks()


if __name__ == "__main__":
    asyncio.run(main())
