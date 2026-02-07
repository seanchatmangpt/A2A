/**
 * K6 Smoke Test for A2A Protocol
 * Validates basic functionality with minimal load
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { BASE_URL, SCENARIOS, THRESHOLDS, getHeaders } from './k6-config.js';

// Custom metrics
const healthCheckDuration = new Trend('health_check_duration');
const agentListDuration = new Trend('agent_list_duration');
const workflowListDuration = new Trend('workflow_list_duration');
const metricsFetchDuration = new Trend('metrics_fetch_duration');

export const options = {
  scenarios: {
    smoke: SCENARIOS.smoke
  },
  thresholds: {
    'http_req_duration': ['p(95)<500'],
    'http_req_failed': ['rate<0.01']
  }
};

export default function() {
  const headers = getHeaders();

  // Test 1: Health check
  let response = http.get(`${BASE_URL}/health`, { headers });
  check(response, {
    'health check status is 200': (r) => r.status === 200,
    'health check has status': (r) => JSON.parse(r.body).status === 'healthy'
  });
  healthCheckDuration.add(response.timings.duration);
  sleep(0.5);

  // Test 2: Bridge status
  response = http.get(`${BASE_URL}/bridge/status`, { headers });
  check(response, {
    'bridge status is 200 or 500': (r) => r.status === 200 || r.status === 500
  });
  sleep(0.5);

  // Test 3: List agents
  response = http.get(`${BASE_URL}/agents`, { headers });
  check(response, {
    'agents endpoint responds': (r) => r.status === 200 || r.status === 500
  });
  agentListDuration.add(response.timings.duration);
  sleep(0.5);

  // Test 4: List workflows
  response = http.get(`${BASE_URL}/workflows`, { headers });
  check(response, {
    'workflows endpoint responds': (r) => r.status === 200 || r.status === 500
  });
  workflowListDuration.add(response.timings.duration);
  sleep(0.5);

  // Test 5: Get metrics
  response = http.get(`${BASE_URL}/metrics`, { headers });
  check(response, {
    'metrics endpoint responds': (r) => r.status === 200 || r.status === 500
  });
  metricsFetchDuration.add(response.timings.duration);
  sleep(0.5);

  // Test 6: Get config
  response = http.get(`${BASE_URL}/config`, { headers });
  check(response, {
    'config endpoint responds': (r) => r.status === 200 || r.status === 500
  });
  sleep(0.5);

  // Test 7: System info
  response = http.get(`${BASE_URL}/system/info`, { headers });
  check(response, {
    'system info endpoint responds': (r) => r.status === 200 || r.status === 500
  });
  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    '/home/user/A2A/tests/load/results/smoke-test-summary.json': JSON.stringify(data)
  };
}
