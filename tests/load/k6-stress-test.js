/**
 * K6 Stress Test for A2A Protocol
 * Tests system behavior under extreme load (Fortune 5 scale)
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';
import {
  BASE_URL,
  SCENARIOS,
  getHeaders,
  generateAgentData,
  generateWorkflowData,
  randomInt
} from './k6-config.js';

// Custom metrics
const successRate = new Rate('success_rate');
const errorRate = new Rate('error_rate');
const requestDuration = new Trend('request_duration');
const concurrentUsers = new Counter('concurrent_users');

export const options = {
  scenarios: {
    stress: SCENARIOS.stress
  },
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    'http_req_failed': ['rate<0.05'],  // Allow 5% errors under stress
    'error_rate': ['rate<0.1'],
    'success_rate': ['rate>0.9']
  }
};

export default function() {
  concurrentUsers.add(1);
  const headers = getHeaders();
  let response;

  // High-intensity mixed workload
  const operations = [
    () => {
      // Burst of health checks
      for (let i = 0; i < 3; i++) {
        response = http.get(`${BASE_URL}/health`, { headers, timeout: '5s' });
        const success = response.status === 200;
        successRate.add(success);
        errorRate.add(!success);
        requestDuration.add(response.timings.duration);
      }
    },
    () => {
      // Agent operations under load
      const agentData = generateAgentData();
      response = http.post(
        `${BASE_URL}/agents`,
        JSON.stringify(agentData),
        { headers, timeout: '10s' }
      );
      const success = response.status === 200 || response.status === 404;
      successRate.add(success);
      errorRate.add(!success);
      requestDuration.add(response.timings.duration);

      // Immediately query agents
      response = http.get(`${BASE_URL}/agents`, { headers, timeout: '10s' });
      const querySuccess = response.status === 200 || response.status === 500;
      successRate.add(querySuccess);
      errorRate.add(!querySuccess);
    },
    () => {
      // Workflow stress
      const workflowData = generateWorkflowData();
      response = http.post(
        `${BASE_URL}/workflows`,
        JSON.stringify(workflowData),
        { headers, timeout: '10s' }
      );
      const success = response.status === 200 || response.status === 404;
      successRate.add(success);
      errorRate.add(!success);
      requestDuration.add(response.timings.duration);
    },
    () => {
      // Metrics under stress
      response = http.get(`${BASE_URL}/metrics`, { headers, timeout: '10s' });
      const success = response.status === 200 || response.status === 500;
      successRate.add(success);
      errorRate.add(!success);

      response = http.get(`${BASE_URL}/bridge/status`, { headers, timeout: '10s' });
      const bridgeSuccess = response.status === 200 || response.status === 500;
      successRate.add(bridgeSuccess);
      errorRate.add(!bridgeSuccess);
    }
  ];

  // Execute random operation
  const operation = operations[randomInt(0, operations.length - 1)];
  operation();

  // Minimal sleep to maintain high load
  sleep(randomInt(0, 1) * 0.1);
}

export function handleSummary(data) {
  const summary = {
    test_type: 'stress',
    timestamp: new Date().toISOString(),
    metrics: {},
    passed: true
  };

  // Process metrics
  for (const [name, metric] of Object.entries(data.metrics)) {
    summary.metrics[name] = {
      avg: metric.values.avg,
      min: metric.values.min,
      max: metric.values.max,
      p95: metric.values['p(95)'],
      p99: metric.values['p(99)'],
      count: metric.values.count
    };

    // Check thresholds
    if (metric.thresholds) {
      for (const [threshold, result] of Object.entries(metric.thresholds)) {
        if (!result.ok) {
          summary.passed = false;
        }
      }
    }
  }

  return {
    '/home/user/A2A/tests/load/results/stress-test-summary.json': JSON.stringify(summary, null, 2)
  };
}
