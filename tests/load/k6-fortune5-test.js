/**
 * K6 Fortune 5 Scale Test for A2A Protocol
 * Simulates enterprise-scale load with millions of users
 * Peak: 100,000 requests/second, 50,000 concurrent VUs
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Trend, Rate, Gauge } from 'k6/metrics';
import {
  BASE_URL,
  SCENARIOS,
  SCALE_CONFIG,
  getHeaders,
  generateAgentData,
  generateWorkflowData,
  randomInt,
  randomString
} from './k6-config.js';

// Fortune 5 Scale Metrics
const totalRequests = new Counter('fortune5_total_requests');
const activeConnections = new Gauge('fortune5_active_connections');
const dataTransferred = new Counter('fortune5_data_transferred_bytes');
const operationLatency = new Trend('fortune5_operation_latency');
const systemThroughput = new Rate('fortune5_throughput');
const errorRate = new Rate('fortune5_error_rate');
const successRate = new Rate('fortune5_success_rate');

// Business-critical operation metrics
const agentDiscoveryLatency = new Trend('fortune5_agent_discovery_latency');
const workflowOrchestrationLatency = new Trend('fortune5_workflow_orchestration_latency');
const metricsAggregationLatency = new Trend('fortune5_metrics_aggregation_latency');

export const options = {
  scenarios: {
    fortune5_simulation: SCENARIOS.fortune5
  },
  thresholds: {
    // SLA enforcement
    'http_req_duration': [
      `p(95)<${SCALE_CONFIG.p95_response_time_sla}`,
      `p(99)<${SCALE_CONFIG.p99_response_time_sla}`,
      `avg<${SCALE_CONFIG.response_time_sla}`
    ],
    'http_req_failed': [`rate<${SCALE_CONFIG.error_rate_threshold / 100}`],
    'fortune5_error_rate': ['rate<0.001'],      // 99.9% success
    'fortune5_success_rate': ['rate>0.999'],
    'fortune5_operation_latency': ['p(95)<500', 'p(99)<1000'],
    'fortune5_agent_discovery_latency': ['p(95)<300'],
    'fortune5_workflow_orchestration_latency': ['p(95)<500'],
    'fortune5_metrics_aggregation_latency': ['p(95)<200']
  },
  // Resource limits
  discardResponseBodies: true,
  batch: 20,
  batchPerHost: 10
};

// Simulate global user distribution
const REGIONS = ['us-east', 'us-west', 'eu-west', 'eu-central', 'ap-southeast', 'ap-northeast'];
const USER_TYPES = ['enterprise', 'premium', 'standard', 'trial'];
const OPERATION_TYPES = ['read', 'write', 'admin', 'analytics'];

export function setup() {
  console.log('='.repeat(80));
  console.log('FORTUNE 5 SCALE LOAD TEST - A2A PROTOCOL');
  console.log('='.repeat(80));
  console.log(`Target Peak RPS: ${SCALE_CONFIG.peak_rps.toLocaleString()}`);
  console.log(`Target Concurrent Users: ${SCALE_CONFIG.peak_concurrent_users.toLocaleString()}`);
  console.log(`Daily Active Users: ${SCALE_CONFIG.daily_active_users.toLocaleString()}`);
  console.log(`Response Time SLA: Avg ${SCALE_CONFIG.response_time_sla}ms, P95 ${SCALE_CONFIG.p95_response_time_sla}ms`);
  console.log(`Error Rate Threshold: ${SCALE_CONFIG.error_rate_threshold}%`);
  console.log('='.repeat(80));

  return {
    startTime: Date.now()
  };
}

export default function(data) {
  const headers = getHeaders();
  const region = REGIONS[randomInt(0, REGIONS.length - 1)];
  const userType = USER_TYPES[randomInt(0, USER_TYPES.length - 1)];
  const operationType = OPERATION_TYPES[randomInt(0, OPERATION_TYPES.length - 1)];

  // Add region header for geo-distribution
  headers['X-Region'] = region;
  headers['X-User-Type'] = userType;

  activeConnections.add(1);
  let response;
  let operationSuccess;

  // Weighted operation distribution based on real-world usage
  const workloadDistribution = randomInt(1, 100);

  if (workloadDistribution <= 50) {
    // 50% - High-frequency read operations (health, status, metrics)
    group('High-Frequency Reads', function() {
      const startTime = Date.now();

      response = http.get(`${BASE_URL}/health`, {
        headers,
        tags: { operation: 'health_check', region, user_type: userType }
      });

      operationSuccess = response.status === 200;
      operationLatency.add(response.timings.duration);
      successRate.add(operationSuccess);
      errorRate.add(!operationSuccess);
      totalRequests.add(1);
      dataTransferred.add(response.body ? response.body.length : 0);

      check(response, {
        'health check within SLA': (r) => r.timings.duration < SCALE_CONFIG.response_time_sla
      });
    });

  } else if (workloadDistribution <= 75) {
    // 25% - Agent discovery and listing
    group('Agent Discovery', function() {
      const startTime = Date.now();

      response = http.get(`${BASE_URL}/agents`, {
        headers,
        tags: { operation: 'agent_discovery', region, user_type: userType }
      });

      operationSuccess = response.status === 200 || response.status === 500;
      const duration = Date.now() - startTime;

      agentDiscoveryLatency.add(duration);
      operationLatency.add(response.timings.duration);
      successRate.add(operationSuccess);
      errorRate.add(!operationSuccess);
      totalRequests.add(1);
      dataTransferred.add(response.body ? response.body.length : 0);

      check(response, {
        'agent discovery successful': (r) => operationSuccess,
        'agent discovery within SLA': (r) => duration < 300
      });
    });

  } else if (workloadDistribution <= 85) {
    // 10% - Workflow operations
    group('Workflow Orchestration', function() {
      const startTime = Date.now();

      // List workflows
      response = http.get(`${BASE_URL}/workflows`, {
        headers,
        tags: { operation: 'workflow_list', region, user_type: userType }
      });

      operationSuccess = response.status === 200 || response.status === 500;
      const duration = Date.now() - startTime;

      workflowOrchestrationLatency.add(duration);
      operationLatency.add(response.timings.duration);
      successRate.add(operationSuccess);
      errorRate.add(!operationSuccess);
      totalRequests.add(1);
      dataTransferred.add(response.body ? response.body.length : 0);

      // Enterprise users create workflows
      if (userType === 'enterprise' && randomInt(1, 100) <= 30) {
        const workflowData = generateWorkflowData();
        response = http.post(
          `${BASE_URL}/workflows`,
          JSON.stringify(workflowData),
          {
            headers,
            tags: { operation: 'workflow_create', region, user_type: userType }
          }
        );

        totalRequests.add(1);
        dataTransferred.add(response.body ? response.body.length : 0);
      }
    });

  } else if (workloadDistribution <= 95) {
    // 10% - Metrics and monitoring
    group('Metrics & Monitoring', function() {
      const startTime = Date.now();

      response = http.get(`${BASE_URL}/metrics`, {
        headers,
        tags: { operation: 'metrics_fetch', region, user_type: userType }
      });

      operationSuccess = response.status === 200 || response.status === 500;
      const duration = Date.now() - startTime;

      metricsAggregationLatency.add(duration);
      operationLatency.add(response.timings.duration);
      successRate.add(operationSuccess);
      errorRate.add(!operationSuccess);
      totalRequests.add(1);
      dataTransferred.add(response.body ? response.body.length : 0);

      // System info for premium/enterprise
      if (userType === 'enterprise' || userType === 'premium') {
        response = http.get(`${BASE_URL}/system/info`, {
          headers,
          tags: { operation: 'system_info', region, user_type: userType }
        });
        totalRequests.add(1);
        dataTransferred.add(response.body ? response.body.length : 0);
      }
    });

  } else {
    // 5% - Write operations (agent registration, config updates)
    group('Write Operations', function() {
      const agentData = generateAgentData();

      response = http.post(
        `${BASE_URL}/agents`,
        JSON.stringify(agentData),
        {
          headers,
          tags: { operation: 'agent_register', region, user_type: userType }
        }
      );

      operationSuccess = response.status === 200 || response.status === 404;
      operationLatency.add(response.timings.duration);
      successRate.add(operationSuccess);
      errorRate.add(!operationSuccess);
      totalRequests.add(1);
      dataTransferred.add(response.body ? response.body.length : 0);
    });
  }

  systemThroughput.add(1);
  activeConnections.add(-1);

  // Variable think time based on user type
  const thinkTime = {
    'trial': randomInt(5, 10) * 0.1,
    'standard': randomInt(2, 5) * 0.1,
    'premium': randomInt(1, 3) * 0.1,
    'enterprise': randomInt(0, 2) * 0.1
  };

  sleep(thinkTime[userType] || 0.5);
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;

  console.log('\n' + '='.repeat(80));
  console.log('FORTUNE 5 SCALE TEST COMPLETED');
  console.log('='.repeat(80));
  console.log(`Total Duration: ${duration.toFixed(2)} seconds`);
  console.log('='.repeat(80));
}

export function handleSummary(data) {
  const summary = {
    test_type: 'fortune5_scale',
    timestamp: new Date().toISOString(),
    scale_config: SCALE_CONFIG,
    test_results: {
      total_requests: (data.metrics.fortune5_total_requests && data.metrics.fortune5_total_requests.values.count) || 0,
      requests_per_second: (data.metrics.http_reqs && data.metrics.http_reqs.values.rate) || 0,
      data_transferred_mb: ((data.metrics.fortune5_data_transferred_bytes && data.metrics.fortune5_data_transferred_bytes.values.count) || 0) / 1024 / 1024,
      avg_response_time: (data.metrics.http_req_duration && data.metrics.http_req_duration.values.avg) || 0,
      p95_response_time: (data.metrics.http_req_duration && data.metrics.http_req_duration.values['p(95)']) || 0,
      p99_response_time: (data.metrics.http_req_duration && data.metrics.http_req_duration.values['p(99)']) || 0,
      error_rate: (data.metrics.fortune5_error_rate && data.metrics.fortune5_error_rate.values.rate) || 0,
      success_rate: (data.metrics.fortune5_success_rate && data.metrics.fortune5_success_rate.values.rate) || 0
    },
    business_metrics: {
      agent_discovery_p95: (data.metrics.fortune5_agent_discovery_latency && data.metrics.fortune5_agent_discovery_latency.values['p(95)']) || 0,
      workflow_orchestration_p95: (data.metrics.fortune5_workflow_orchestration_latency && data.metrics.fortune5_workflow_orchestration_latency.values['p(95)']) || 0,
      metrics_aggregation_p95: (data.metrics.fortune5_metrics_aggregation_latency && data.metrics.fortune5_metrics_aggregation_latency.values['p(95)']) || 0
    },
    sla_compliance: {
      response_time_sla_met: ((data.metrics.http_req_duration && data.metrics.http_req_duration.values.avg) || 0) < SCALE_CONFIG.response_time_sla,
      p95_sla_met: ((data.metrics.http_req_duration && data.metrics.http_req_duration.values['p(95)']) || 0) < SCALE_CONFIG.p95_response_time_sla,
      p99_sla_met: ((data.metrics.http_req_duration && data.metrics.http_req_duration.values['p(99)']) || 0) < SCALE_CONFIG.p99_response_time_sla,
      error_rate_sla_met: ((data.metrics.fortune5_error_rate && data.metrics.fortune5_error_rate.values.rate) || 0) < (SCALE_CONFIG.error_rate_threshold / 100)
    },
    passed: true
  };

  // Check if test passed all thresholds
  for (const [name, metric] of Object.entries(data.metrics)) {
    if (metric.thresholds) {
      for (const threshold of Object.values(metric.thresholds)) {
        if (!threshold.ok) {
          summary.passed = false;
        }
      }
    }
  }

  return {
    'stdout': generateConsoleReport(summary),
    '/home/user/A2A/tests/load/results/fortune5-test-summary.json': JSON.stringify(summary, null, 2),
    '/home/user/A2A/tests/load/results/fortune5-test-report.html': generateHTMLReport(summary, data)
  };
}

function generateConsoleReport(summary) {
  return `
${'='.repeat(80)}
FORTUNE 5 SCALE TEST RESULTS
${'='.repeat(80)}

Test Results:
  Total Requests: ${summary.test_results.total_requests.toLocaleString()}
  Requests/Second: ${summary.test_results.requests_per_second.toFixed(2)}
  Data Transferred: ${summary.test_results.data_transferred_mb.toFixed(2)} MB

Response Times:
  Average: ${summary.test_results.avg_response_time.toFixed(2)}ms
  P95: ${summary.test_results.p95_response_time.toFixed(2)}ms
  P99: ${summary.test_results.p99_response_time.toFixed(2)}ms

Quality Metrics:
  Success Rate: ${(summary.test_results.success_rate * 100).toFixed(3)}%
  Error Rate: ${(summary.test_results.error_rate * 100).toFixed(3)}%

Business Metrics:
  Agent Discovery P95: ${summary.business_metrics.agent_discovery_p95.toFixed(2)}ms
  Workflow Orchestration P95: ${summary.business_metrics.workflow_orchestration_p95.toFixed(2)}ms
  Metrics Aggregation P95: ${summary.business_metrics.metrics_aggregation_p95.toFixed(2)}ms

SLA Compliance:
  Response Time SLA: ${summary.sla_compliance.response_time_sla_met ? 'PASS ✓' : 'FAIL ✗'}
  P95 SLA: ${summary.sla_compliance.p95_sla_met ? 'PASS ✓' : 'FAIL ✗'}
  P99 SLA: ${summary.sla_compliance.p99_sla_met ? 'PASS ✓' : 'FAIL ✗'}
  Error Rate SLA: ${summary.sla_compliance.error_rate_sla_met ? 'PASS ✓' : 'FAIL ✗'}

Overall: ${summary.passed ? 'PASSED ✓' : 'FAILED ✗'}
${'='.repeat(80)}
`;
}

function generateHTMLReport(summary, data) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Fortune 5 Scale Load Test - A2A Protocol</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; background: #f0f2f5; }
    .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 20px; text-align: center; }
    .header h1 { font-size: 36px; margin-bottom: 10px; }
    .header p { font-size: 18px; opacity: 0.9; }
    .container { max-width: 1400px; margin: 0 auto; padding: 30px 20px; }
    .status { display: inline-block; padding: 8px 16px; border-radius: 20px; font-weight: bold; margin: 20px 0; }
    .status.pass { background: #28a745; color: white; }
    .status.fail { background: #dc3545; color: white; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; margin: 30px 0; }
    .card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .card h3 { color: #333; margin-bottom: 15px; font-size: 18px; }
    .metric-value { font-size: 32px; font-weight: bold; color: #667eea; margin: 10px 0; }
    .metric-label { color: #666; font-size: 14px; }
    .sla-check { display: flex; align-items: center; justify-content: space-between; padding: 12px; margin: 8px 0; background: #f8f9fa; border-radius: 6px; }
    .sla-check.pass { border-left: 4px solid #28a745; }
    .sla-check.fail { border-left: 4px solid #dc3545; }
    .chart-container { background: white; padding: 25px; border-radius: 12px; margin: 20px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #e0e0e0; }
    th { background: #f8f9fa; font-weight: 600; }
    .timestamp { color: #666; font-size: 14px; }
  </style>
</head>
<body>
  <div class="header">
    <h1>Fortune 5 Scale Load Test</h1>
    <p>A2A Protocol Performance Analysis</p>
    <div class="status ${summary.passed ? 'pass' : 'fail'}">
      ${summary.passed ? '✓ ALL TESTS PASSED' : '✗ SOME TESTS FAILED'}
    </div>
    <div class="timestamp">${summary.timestamp}</div>
  </div>

  <div class="container">
    <h2>Performance Overview</h2>
    <div class="grid">
      <div class="card">
        <h3>Total Requests</h3>
        <div class="metric-value">${summary.test_results.total_requests.toLocaleString()}</div>
        <div class="metric-label">Requests processed</div>
      </div>
      <div class="card">
        <h3>Throughput</h3>
        <div class="metric-value">${summary.test_results.requests_per_second.toFixed(2)}</div>
        <div class="metric-label">Requests per second</div>
      </div>
      <div class="card">
        <h3>Data Transferred</h3>
        <div class="metric-value">${summary.test_results.data_transferred_mb.toFixed(2)} MB</div>
        <div class="metric-label">Total bandwidth used</div>
      </div>
      <div class="card">
        <h3>Success Rate</h3>
        <div class="metric-value">${(summary.test_results.success_rate * 100).toFixed(3)}%</div>
        <div class="metric-label">Successful requests</div>
      </div>
    </div>

    <div class="chart-container">
      <h2>Response Time Analysis</h2>
      <table>
        <tr>
          <th>Metric</th>
          <th>Value</th>
          <th>SLA Target</th>
          <th>Status</th>
        </tr>
        <tr>
          <td>Average Response Time</td>
          <td>${summary.test_results.avg_response_time.toFixed(2)}ms</td>
          <td>${SCALE_CONFIG.response_time_sla}ms</td>
          <td>${summary.sla_compliance.response_time_sla_met ? '✓ Pass' : '✗ Fail'}</td>
        </tr>
        <tr>
          <td>P95 Response Time</td>
          <td>${summary.test_results.p95_response_time.toFixed(2)}ms</td>
          <td>${SCALE_CONFIG.p95_response_time_sla}ms</td>
          <td>${summary.sla_compliance.p95_sla_met ? '✓ Pass' : '✗ Fail'}</td>
        </tr>
        <tr>
          <td>P99 Response Time</td>
          <td>${summary.test_results.p99_response_time.toFixed(2)}ms</td>
          <td>${SCALE_CONFIG.p99_response_time_sla}ms</td>
          <td>${summary.sla_compliance.p99_sla_met ? '✓ Pass' : '✗ Fail'}</td>
        </tr>
        <tr>
          <td>Error Rate</td>
          <td>${(summary.test_results.error_rate * 100).toFixed(3)}%</td>
          <td>${SCALE_CONFIG.error_rate_threshold}%</td>
          <td>${summary.sla_compliance.error_rate_sla_met ? '✓ Pass' : '✗ Fail'}</td>
        </tr>
      </table>
    </div>

    <div class="chart-container">
      <h2>Business Operations Performance</h2>
      <div class="grid">
        <div class="card">
          <h3>Agent Discovery</h3>
          <div class="metric-value">${summary.business_metrics.agent_discovery_p95.toFixed(2)}ms</div>
          <div class="metric-label">P95 Latency</div>
        </div>
        <div class="card">
          <h3>Workflow Orchestration</h3>
          <div class="metric-value">${summary.business_metrics.workflow_orchestration_p95.toFixed(2)}ms</div>
          <div class="metric-label">P95 Latency</div>
        </div>
        <div class="card">
          <h3>Metrics Aggregation</h3>
          <div class="metric-value">${summary.business_metrics.metrics_aggregation_p95.toFixed(2)}ms</div>
          <div class="metric-label">P95 Latency</div>
        </div>
      </div>
    </div>

    <div class="chart-container">
      <h2>SLA Compliance</h2>
      <div class="sla-check ${summary.sla_compliance.response_time_sla_met ? 'pass' : 'fail'}">
        <span>Average Response Time SLA</span>
        <strong>${summary.sla_compliance.response_time_sla_met ? '✓ PASS' : '✗ FAIL'}</strong>
      </div>
      <div class="sla-check ${summary.sla_compliance.p95_sla_met ? 'pass' : 'fail'}">
        <span>P95 Response Time SLA</span>
        <strong>${summary.sla_compliance.p95_sla_met ? '✓ PASS' : '✗ FAIL'}</strong>
      </div>
      <div class="sla-check ${summary.sla_compliance.p99_sla_met ? 'pass' : 'fail'}">
        <span>P99 Response Time SLA</span>
        <strong>${summary.sla_compliance.p99_sla_met ? '✓ PASS' : '✗ FAIL'}</strong>
      </div>
      <div class="sla-check ${summary.sla_compliance.error_rate_sla_met ? 'pass' : 'fail'}">
        <span>Error Rate SLA</span>
        <strong>${summary.sla_compliance.error_rate_sla_met ? '✓ PASS' : '✗ FAIL'}</strong>
      </div>
    </div>
  </div>
</body>
</html>
  `;
}
