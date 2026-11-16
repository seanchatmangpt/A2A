# Research API Endpoints

API endpoints for advanced research features including reachability analysis, partial order discovery, and LLM validation.

## Overview

Research endpoints provide access to advanced workflow analysis capabilities:

- **Reachability Analysis**: O(P²+T²) state space exploration
- **Partial Order Discovery**: Process structure discovery
- **LLM Validation**: AI-assisted workflow verification
- **OCPM**: Object-centric process mining
- **CPN**: Colored Petri Net analysis

## Reachability Analysis

### Get Reachability Graph

Computes the reachability graph for a workflow.

```http
POST /api/research/reachability
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id": "seq_abc123",
  "options": {
    "include_markings": true,
    "max_depth": 100,
    "prune_deadlocks": true
  }
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "analysis_id": "reach_xyz789",
  "statistics": {
    "total_states": 42,
    "reachable_states": 38,
    "deadlock_states": 2,
    "final_states": 1,
    "cycles": 3,
    "analysis_time_ms": 150
  },
  "states": [
    {
      "state_id": "s0",
      "marking": {"p1": 1, "p2": 0, "p3": 0},
      "type": "initial",
      "transitions_out": ["t1"]
    },
    {
      "state_id": "s1",
      "marking": {"p1": 0, "p2": 1, "p3": 0},
      "type": "intermediate",
      "transitions_in": ["t1"],
      "transitions_out": ["t2"]
    }
  ],
  "transitions": [
    {
      "transition_id": "t1",
      "from_state": "s0",
      "to_state": "s1",
      "label": "validate_order"
    }
  ]
}
```

### Check State Reachability

Checks if a specific state is reachable.

```http
POST /api/research/reachability/check-state
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id": "seq_abc123",
  "target_marking": {
    "p1": 0,
    "p2": 0,
    "p3": 1
  }
}
```

### Response

```json
{
  "reachable": true,
  "path": [
    {"state": "s0", "transition": "t1", "next_state": "s1"},
    {"state": "s1", "transition": "t2", "next_state": "s2"}
  ],
  "distance": 2
}
```

## Partial Order Discovery

### Discover Partial Order

Discovers the partial order structure from event logs.

```http
POST /api/research/partial-order/discover
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id": "seq_abc123",
  "algorithm": "alpha",
  "options": {
    "include_loops": true,
    "merge_short_loops": true
  }
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "algorithm": "alpha",
  "partial_order": {
    "places": [
      {"id": "p1", "type": "source", "label": "start"},
      {"id": "p2", "type": "normal", "label": "processing"},
      {"id": "p3", "type": "sink", "label": "end"}
    ],
    "transitions": [
      {"id": "t1", "label": "validate"},
      {"id": "t2", "label": "process"},
      {"id": "t3", "label": "complete"}
    ],
    "flows": [
      {"from": "p1", "to": "t1"},
      {"from": "t1", "to": "p2"},
      {"from": "p2", "to": "t2"},
      {"from": "t2", "to": "p3"}
    ],
    "relations": {
      "sequence": [["t1", "t2"], ["t2", "t3"]],
      "parallel": [],
      "choice": []
    }
  }
}
```

### Get Concurrency Relations

Gets concurrency relations between transitions.

```http
GET /api/research/partial-order/concurrency/{workflow_id}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "relations": {
    "causality": [
      ["t1", "t2"],
      ["t2", "t3"]
    ],
    "conflict": [
      ["t2a", "t2b"]
    ],
    "concurrency": [
      ["t3a", "t3b"],
      ["t4a", "t4b"]
    ]
  }
}
```

## LLM Validation

### Validate Workflow

Validates a workflow using LLM analysis.

```http
POST /api/research/llm/validate
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id": "seq_abc123",
  "aspects": [
    "correctness",
    "soundness",
    "completeness",
    "consistency"
  ],
  "options": {
    "explain_errors": true,
    "suggest_fixes": true
  }
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "validation_id": "llm_val_xyz",
  "overall_result": "valid",
  "aspects": {
    "correctness": {
      "result": "valid",
      "confidence": 0.95,
      "explanation": "All transitions are properly defined"
    },
    "soundness": {
      "result": "valid",
      "confidence": 0.92,
      "explanation": "No unreachable states or dead transitions detected"
    },
    "completeness": {
      "result": "warning",
      "confidence": 0.88,
      "explanation": "Some edge cases may not be handled",
      "suggestions": [
        "Add timeout handling for external service calls",
        "Consider adding error recovery for payment failures"
      ]
    },
    "consistency": {
      "result": "valid",
      "confidence": 0.97,
      "explanation": "Data flow is consistent across all paths"
    }
  },
  "issues": [],
  "suggestions": [
    "Add timeout handling for external service calls"
  ]
}
```

### Compare Workflows

Compares two workflows for semantic equivalence.

```http
POST /api/research/llm/compare
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id_1": "seq_abc123",
  "workflow_id_2": "seq_def456",
  "comparison_type": "equivalence"
}
```

### Response

```json
{
  "workflow_id_1": "seq_abc123",
  "workflow_id_2": "seq_def456",
  "equivalent": true,
  "similarity_score": 0.95,
  "differences": {
    "structural": [],
    "behavioral": [
      {
        "aspect": "timeout_handling",
        "workflow_1": "not implemented",
        "workflow_2": "implemented with 30s timeout"
      }
    ]
  }
}
```

## OCPM (Object-Centric Process Mining)

### Get Object Types

Gets all object types in an object-centric log.

```http
GET /api/research/ocpm/object-types/{log_id}
```

### Response

```json
{
  "log_id": "ocpm_log_1",
  "object_types": [
    {
      "type": "order",
      "attributes": ["id", "customer_id", "amount", "status"]
    },
    {
      "type": "item",
      "attributes": ["id", "product_id", "quantity"]
    },
    {
      "type": "payment",
      "attributes": ["id", "amount", "method", "status"]
    }
  ]
}
```

### Get Object Centric Event Log

Gets the object-centric event log.

```http
GET /api/research/ocpm/events/{log_id}
```

### Response

```json
{
  "log_id": "ocpm_log_1",
  "events": [
    {
      "event_id": "e1",
      "activity": "create_order",
      "timestamp": "2024-01-01T10:00:00Z",
      "objects": {
        "order": ["order_1"],
        "item": ["item_1", "item_2"]
      }
    },
    {
      "event_id": "e2",
      "activity": "process_payment",
      "timestamp": "2024-01-01T10:01:00Z",
      "objects": {
        "order": ["order_1"],
        "payment": ["payment_1"]
      }
    }
  ]
}
```

### Discover OCPM Model

Discovers an object-centric process model.

```http
POST /api/research/ocpm/discover
Content-Type: application/json
```

### Request Body

```json
{
  "log_id": "ocpm_log_1",
  "algorithm": "ocpm_inductive",
  "options": {
    "object_type_lifecycle": true
  }
}
```

### Response

```json
{
  "log_id": "ocpm_log_1",
  "model": {
    "object_types": ["order", "item", "payment"],
    "activities": [
      {
        "name": "create_order",
        "input_objects": ["item"],
        "output_objects": ["order"]
      },
      {
        "name": "process_payment",
        "input_objects": ["order"],
        "output_objects": ["payment"]
      }
    ],
    "lifecycles": {
      "order": ["created", "paid", "shipped", "completed"],
      "item": ["added", "processed"],
      "payment": ["pending", "completed", "failed"]
    }
  }
}
```

## CPN (Colored Petri Nets)

### Get CPN Model

Gets the Colored Petri Net representation of a workflow.

```http
GET /api/research/cpn/model/{workflow_id}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "cpn_model": {
    "places": [
      {
        "id": "p1",
        "name": "input",
        "color_set": "INT",
        "initial_marking": [1]
      },
      {
        "id": "p2",
        "name": "processing",
        "color_set": "PRODUCT",
        "initial_marking": []
      },
      {
        "id": "p3",
        "name": "output",
        "color_set": "INT",
        "initial_marking": []
      }
    ],
    "transitions": [
      {
        "id": "t1",
        "name": "process",
        "guard": "x > 0",
        "code": "output(x * 2)"
      }
    ],
    "arcs": [
      {
        "from": "p1",
        "to": "t1",
        "expression": "x"
      },
      {
        "from": "t1",
        "to": "p3",
        "expression": "x * 2"
      }
    ],
    "color_sets": {
      "INT": "integer",
      "PRODUCT": "record {id: INT, name: STRING, value: REAL}"
    }
  }
}
```

### Simulate CPN

Simulates execution of a Colored Petri Net.

```http
POST /api/research/cpn/simulate
Content-Type: application/json
```

### Request Body

```json
{
  "workflow_id": "seq_abc123",
  "initial_marking": {
    "p1": [1, 2, 3],
    "p2": []
  },
  "steps": 10
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "simulation_id": "sim_xyz789",
  "steps": [
    {
      "step": 1,
      "enabled_transitions": ["t1"],
      "fired_transition": "t1",
      "marking_before": {"p1": [1, 2, 3], "p2": []},
      "marking_after": {"p1": [2, 3], "p2": [2]}
    },
    {
      "step": 2,
      "enabled_transitions": ["t1"],
      "fired_transition": "t1",
      "marking_before": {"p1": [2, 3], "p2": [2]},
      "marking_after": {"p1": [3], "p2": [2, 4]}
    }
  ],
  "final_marking": {
    "p1": [],
    "p2": [2, 4, 6]
  }
}
```

## Research Job Management

### List Research Jobs

Lists all research analysis jobs.

```http
GET /api/research/jobs?status=running
```

### Response

```json
{
  "jobs": [
    {
      "job_id": "job_xyz789",
      "type": "reachability",
      "workflow_id": "seq_abc123",
      "status": "running",
      "progress": 45,
      "started_at": "2024-01-01T10:00:00Z"
    }
  ]
}
```

### Get Job Status

Gets the status of a research job.

```http
GET /api/research/jobs/{job_id}
```

### Response

```json
{
  "job_id": "job_xyz789",
  "type": "reachability",
  "status": "completed",
  "progress": 100,
  "started_at": "2024-01-01T10:00:00Z",
  "completed_at": "2024-01-01T10:02:30Z",
  "result": {...}
}
```

### Cancel Job

Cancels a running research job.

```http
POST /api/research/jobs/{job_id}/cancel
```

---

Next: [Back to Overview](overview.md) | [Research Features](../research/)
