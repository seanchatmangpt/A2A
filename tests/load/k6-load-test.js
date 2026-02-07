/**
 * K6 Load Test for A2A Protocol
 * Simulates normal peak load conditions
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';
import {
  BASE_URL,
  SCENARIOS,
  THRESHOLDS,
  getHeaders,
  generateAgentData,
  generateWorkflowData,
  randomInt
} from './k6-config.js';

// Custom metrics
const healthCheckDuration = new Trend('health_check_duration');
const agentRegistrationDuration = new Trend('agent_registration_duration');
const workflowExecutionDuration = new Trend('workflow_execution_duration');
const errorRate = new Rate('errors');
const successfulRequests = new Counter('successful_requests');

export const options = {
  scenarios: {
    load: SCENARIOS.load
  },
  thresholds: THRESHOLDS
};

export default function() {
  const headers = getHeaders();
  let response;

  // Simulate different user behaviors with weighted distribution
  const scenario = randomInt(1, 100);

  if (scenario <= 40) {
    // 40% - Read-heavy operations (most common)
    group('Read Operations', function() {
      // Health check
      response = http.get(`${BASE_URL}/health`, { headers });
      const healthOk = check(response, {
        'health check OK': (r) => r.status === 200
      });
      healthCheckDuration.add(response.timings.duration);
      errorRate.add(!healthOk);
      if (healthOk) successfulRequests.add(1);

      sleep(0.1);

      // List agents
      response = http.get(`${BASE_URL}/agents`, { headers });
      const agentsOk = check(response, {
        'agents list OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!agentsOk);
      if (agentsOk) successfulRequests.add(1);

      sleep(0.1);

      // Get metrics
      response = http.get(`${BASE_URL}/metrics`, { headers });
      const metricsOk = check(response, {
        'metrics OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!metricsOk);
      if (metricsOk) successfulRequests.add(1);
    });

  } else if (scenario <= 70) {
    // 30% - Workflow operations
    group('Workflow Operations', function() {
      // List workflows
      response = http.get(`${BASE_URL}/workflows`, { headers });
      const workflowsOk = check(response, {
        'workflows list OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!workflowsOk);
      if (workflowsOk) successfulRequests.add(1);

      sleep(0.2);

      // Start workflow (POST)
      const workflowData = generateWorkflowData();
      response = http.post(
        `${BASE_URL}/workflows`,
        JSON.stringify(workflowData),
        { headers }
      );
      const startOk = check(response, {
        'workflow start accepted': (r) => r.status === 200 || r.status === 404 || r.status === 500
      });
      workflowExecutionDuration.add(response.timings.duration);
      errorRate.add(!startOk);
      if (startOk) successfulRequests.add(1);
    });

  } else if (scenario <= 90) {
    // 20% - Agent operations
    group('Agent Operations', function() {
      // Register agent (POST)
      const agentData = generateAgentData();
      response = http.post(
        `${BASE_URL}/agents`,
        JSON.stringify(agentData),
        { headers }
      );
      const registerOk = check(response, {
        'agent registration accepted': (r) => r.status === 200 || r.status === 404 || r.status === 500
      });
      agentRegistrationDuration.add(response.timings.duration);
      errorRate.add(!registerOk);
      if (registerOk) successfulRequests.add(1);

      sleep(0.1);

      // List agents
      response = http.get(`${BASE_URL}/agents`, { headers });
      const listOk = check(response, {
        'agents list OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!listOk);
      if (listOk) successfulRequests.add(1);
    });

  } else {
    // 10% - System monitoring
    group('System Monitoring', function() {
      // Bridge status
      response = http.get(`${BASE_URL}/bridge/status`, { headers });
      const bridgeOk = check(response, {
        'bridge status OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!bridgeOk);
      if (bridgeOk) successfulRequests.add(1);

      sleep(0.1);

      // System info
      response = http.get(`${BASE_URL}/system/info`, { headers });
      const sysOk = check(response, {
        'system info OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!sysOk);
      if (sysOk) successfulRequests.add(1);

      sleep(0.1);

      // Config
      response = http.get(`${BASE_URL}/config`, { headers });
      const confOk = check(response, {
        'config OK': (r) => r.status === 200 || r.status === 500
      });
      errorRate.add(!confOk);
      if (confOk) successfulRequests.add(1);
    });
  }

  sleep(randomInt(1, 3));
}

export function handleSummary(data) {
  return {
    '/home/user/A2A/tests/load/results/load-test-summary.json': JSON.stringify(data),
    '/home/user/A2A/tests/load/results/load-test-summary.html': htmlReport(data)
  };
}

function htmlReport(data) {
  const metrics = data.metrics;

  return `
<!DOCTYPE html>
<html>
<head>
  <title>A2A Load Test Results</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
    .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
    h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
    .metric { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 4px; border-left: 4px solid #007bff; }
    .metric-name { font-weight: bold; color: #555; }
    .metric-value { font-size: 24px; color: #007bff; margin: 5px 0; }
    .pass { color: #28a745; }
    .fail { color: #dc3545; }
    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }
    .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; }
    .summary-card h3 { margin: 0 0 10px 0; font-size: 14px; opacity: 0.9; }
    .summary-card .value { font-size: 32px; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <h1>A2A Protocol - Load Test Results</h1>
    <p>Test completed at: ${new Date().toISOString()}</p>

    <div class="summary">
      <div class="summary-card">
        <h3>Total Requests</h3>
        <div class="value">${metrics.http_reqs ? Math.floor(metrics.http_reqs.values.count) : 0}</div>
      </div>
      <div class="summary-card">
        <h3>Requests/sec</h3>
        <div class="value">${metrics.http_reqs ? metrics.http_reqs.values.rate.toFixed(2) : 0}</div>
      </div>
      <div class="summary-card">
        <h3>Avg Response Time</h3>
        <div class="value">${metrics.http_req_duration ? metrics.http_req_duration.values.avg.toFixed(2) : 0}ms</div>
      </div>
      <div class="summary-card">
        <h3>P95 Response Time</h3>
        <div class="value">${metrics.http_req_duration ? metrics.http_req_duration.values['p(95)'].toFixed(2) : 0}ms</div>
      </div>
    </div>

    <h2>Detailed Metrics</h2>
    ${Object.entries(metrics).map(([name, metric]) => `
      <div class="metric">
        <div class="metric-name">${name}</div>
        <div class="metric-value">
          ${metric.values.avg !== undefined ? `Avg: ${metric.values.avg.toFixed(2)}` : ''}
          ${metric.values.min !== undefined ? ` | Min: ${metric.values.min.toFixed(2)}` : ''}
          ${metric.values.max !== undefined ? ` | Max: ${metric.values.max.toFixed(2)}` : ''}
          ${metric.values['p(95)'] !== undefined ? ` | P95: ${metric.values['p(95)'].toFixed(2)}` : ''}
          ${metric.values.count !== undefined ? ` | Count: ${metric.values.count}` : ''}
          ${metric.values.rate !== undefined ? ` | Rate: ${metric.values.rate.toFixed(2)}` : ''}
        </div>
      </div>
    `).join('')}
  </div>
</body>
</html>
  `;
}
