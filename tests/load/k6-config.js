/**
 * K6 Load Testing Configuration for A2A Protocol
 * Fortune 5 Scale Testing - Simulating millions of users
 */

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8001';
export const API_KEY = __ENV.API_KEY || '';

// Fortune 5 Scale Configuration
export const SCALE_CONFIG = {
  // Peak concurrent users during business hours
  peak_concurrent_users: 50000,

  // Total daily active users
  daily_active_users: 5000000,

  // Requests per second at peak
  peak_rps: 100000,

  // Average response time SLA (ms)
  response_time_sla: 200,

  // P95 response time SLA (ms)
  p95_response_time_sla: 500,

  // P99 response time SLA (ms)
  p99_response_time_sla: 1000,

  // Error rate threshold (%)
  error_rate_threshold: 0.1
};

// Test Scenarios
export const SCENARIOS = {
  // Smoke test - Basic functionality check
  smoke: {
    executor: 'constant-vus',
    vus: 10,
    duration: '1m'
  },

  // Load test - Normal peak load
  load: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m', target: 1000 },  // Ramp up
      { duration: '5m', target: 1000 },  // Stay at peak
      { duration: '2m', target: 0 }      // Ramp down
    ]
  },

  // Stress test - Beyond normal capacity
  stress: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m', target: 2000 },
      { duration: '5m', target: 5000 },
      { duration: '2m', target: 10000 },
      { duration: '5m', target: 10000 },
      { duration: '3m', target: 0 }
    ]
  },

  // Spike test - Sudden traffic surge
  spike: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '1m', target: 1000 },
      { duration: '30s', target: 10000 },  // Sudden spike
      { duration: '3m', target: 10000 },
      { duration: '1m', target: 1000 },
      { duration: '1m', target: 0 }
    ]
  },

  // Soak test - Extended duration at moderate load
  soak: {
    executor: 'constant-vus',
    vus: 2000,
    duration: '30m'
  },

  // Fortune 5 scale simulation
  fortune5: {
    executor: 'ramping-arrival-rate',
    startRate: 1000,
    timeUnit: '1s',
    preAllocatedVUs: 5000,
    maxVUs: 50000,
    stages: [
      { duration: '5m', target: 10000 },   // Morning ramp
      { duration: '10m', target: 50000 },  // Business hours peak
      { duration: '10m', target: 100000 }, // Absolute peak
      { duration: '10m', target: 50000 },  // Evening
      { duration: '5m', target: 10000 }    // Night
    ]
  }
};

// Performance Thresholds
export const THRESHOLDS = {
  // HTTP request duration
  'http_req_duration': [
    `p(95)<${SCALE_CONFIG.p95_response_time_sla}`,
    `p(99)<${SCALE_CONFIG.p99_response_time_sla}`,
    `avg<${SCALE_CONFIG.response_time_sla}`
  ],

  // HTTP request failed
  'http_req_failed': [
    `rate<${SCALE_CONFIG.error_rate_threshold / 100}`
  ],

  // Requests per second
  'http_reqs': ['rate>1000'],

  // Iteration duration
  'iteration_duration': ['p(95)<2000'],

  // Custom metrics
  'agent_registration_duration': ['p(95)<300'],
  'workflow_execution_duration': ['p(95)<500'],
  'health_check_duration': ['p(95)<100']
};

// Headers
export function getHeaders() {
  const headers = {
    'Content-Type': 'application/json'
  };

  if (API_KEY) {
    headers['X-API-Key'] = API_KEY;
  }

  return headers;
}

// Helper to generate random data
export function randomString(length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Generate agent data
export function generateAgentData() {
  return {
    agent_id: `agent-${randomString(16)}`,
    name: `TestAgent-${randomString(8)}`,
    version: `1.0.${randomInt(0, 100)}`,
    capabilities: [
      'text-processing',
      'data-analysis',
      'workflow-execution'
    ],
    endpoints: {
      task: '/task',
      status: '/status'
    },
    metadata: {
      region: ['us-east-1', 'us-west-2', 'eu-west-1'][randomInt(0, 2)],
      tier: ['standard', 'premium', 'enterprise'][randomInt(0, 2)]
    }
  };
}

// Generate workflow data
export function generateWorkflowData() {
  return {
    workflow_config: {
      workflow_id: `workflow-${randomString(16)}`,
      name: `TestWorkflow-${randomString(8)}`,
      steps: [
        {
          id: 'step1',
          type: 'agent-task',
          agent_capability: 'text-processing'
        },
        {
          id: 'step2',
          type: 'agent-task',
          agent_capability: 'data-analysis'
        }
      ]
    }
  };
}
