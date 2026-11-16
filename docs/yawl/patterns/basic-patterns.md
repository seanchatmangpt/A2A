# Basic Workflow Patterns

The seven fundamental YAWL workflow patterns that form the foundation of workflow orchestration.

## Overview

Basic patterns are the building blocks of workflow design. They handle simple, linear execution paths and straightforward routing decisions. These patterns are sufficient for many business processes and can be combined to create more complex workflows.

## Pattern List

1. **Basic Sequential** - Execute tasks in sequence
2. **Parallel Split** - Execute multiple tasks simultaneously
3. **Parallel Join** - Wait for parallel branches to complete
4. **Exclusive Choice** - Choose one path from multiple options
5. **Simple Merge** - Merge multiple paths into one
6. **Interleaved Parallelism** - Execute tasks in any order
7. **Deferred Choice** - Defer path selection until runtime

---

## 1. Basic Sequential

Execute tasks one after another in a defined order.

### Petri Net Representation

```
Places: [start, task1, task2, end]
Transitions: [t1, t2, t3]
Edges: start -> task1 -> task2 -> end
```

### When to Use

- Linear processes with no branching
- Step-by-step procedures
- Sequential dependencies

### Example

```erlang
Config = #{
    pattern_type => sequential,
    name => <<"order_processing">>,
    parameters => #{
        steps => [
            <<"validate_order">>,
            <<"process_payment">>,
            <<"ship_order">>
        ]
    }
}.
```

---

## 2. Parallel Split

Execute multiple tasks simultaneously from a single starting point.

### Petri Net Representation

```
Places: [start, split, a, b, c, sync, end]
Transitions: [split, ta, tb, tc, sync]
Edges: start -> split
      split -> a, split -> b, split -> c
      a -> sync, b -> sync, c -> sync
      sync -> end
```

### When to Use

- Independent tasks that can run concurrently
- Performance optimization through parallelization
- Multi-party notifications

### Example

```erlang
Config = #{
    pattern_type => parallel_split,
    name => <<"parallel_checks">>,
    parameters => #{
        branches => [
            #{task => inventory_check, capabilities => [inventory]},
            #{task => credit_check, capabilities => [credit]},
            #{task => fraud_check, capabilities => [fraud]}
        ]
    }
}.
```

---

## 3. Parallel Join

Wait for multiple parallel branches to complete before proceeding.

### Petri Net Representation

```
Places: [a, b, c, sync, end]
Transitions: [sync]
Edges: a -> sync, b -> sync, c -> sync
      sync -> end (when all inputs have tokens)
```

### When to Use

- Synchronizing parallel tasks
- Waiting for all confirmations before proceeding
- Data aggregation from multiple sources

### Example

```erlang
Config = #{
    pattern_type => parallel_join,
    name => <<"sync_results">>,
    parameters => #{
        required_branches => 3,
        timeout => 60000
    }
}.
```

---

## 4. Exclusive Choice

Choose exactly one path from multiple options based on conditions.

### Petri Net Representation

```
Places: [start, decision, a, b, c, end]
Transitions: [decide, ta, tb, tc]
Edges: start -> decision
      decision -> a (condition1)
      decision -> b (condition2)
      decision -> c (condition3)
      a -> end, b -> end, c -> end
```

### When to Use

- Routing based on data values
- Approval thresholds
- Conditional processing

### Example

```erlang
Config = #{
    pattern_type => exclusive_choice,
    name => <<"amount_based_routing">>,
    parameters => #{
        conditions => [
            #{
                name => low_value,
                condition => fun(Data) -> maps:get(amount, Data) =< 100 end
            },
            #{
                name => medium_value,
                condition => fun(Data) ->
                    Amount = maps:get(amount, Data),
                    Amount > 100 andalso Amount =< 1000
                end
            },
            #{
                name => high_value,
                condition => fun(Data) -> maps:get(amount, Data) > 1000 end
            }
        ]
    }
}.
```

---

## 5. Simple Merge

Merge multiple exclusive paths back into a single flow.

### Petri Net Representation

```
Places: [a, b, c, merged, end]
Transitions: [merge]
Edges: a -> merged, b -> merged, c -> merged
      merged -> end (when any input has token)
```

### When to Use

- Re-converging exclusive choice paths
- Single continuation point after branching
- Simplifying workflow structure

### Example

```erlang
Config = #{
    pattern_type => simple_merge,
    name => <<"merge_paths">>,
    parameters => #{
        input_count => 3
    }
}.
```

---

## 6. Interleaved Parallelism

Execute multiple tasks in any order, possibly concurrently.

### Petri Net Representation

```
Places: [start, ready, task_a, task_b, task_c, done, end]
Transitions: [start_interleave, do_a, do_b, do_c, check_done]
Edges: start -> start_interleave -> ready
      ready -> task_a -> ready
      ready -> task_b -> ready
      ready -> task_c -> ready
      (with mutual exclusion on task execution)
```

### When to Use

- Flexible ordering requirements
- Resource sharing with concurrency control
- Any-order processing

### Example

```erlang
Config = #{
    pattern_type => interleaved_parallelism,
    name => <<"flexible_order">>,
    parameters => #{
        tasks => [task_a, task_b, task_c],
        allow_concurrent => true,
        max_concurrent => 2
    }
}.
```

---

## 7. Deferred Choice

Defer the choice of path until runtime based on actual events.

### Petri Net Representation

```
Places: [start, waiting, option_a, option_b, end]
Transitions: [defer, choose_a, choose_b]
Edges: start -> waiting
      waiting -> option_a (event_a occurs)
      waiting -> option_b (event_b occurs)
      option_a -> end, option_b -> end
```

### When to Use

- External event-based decisions
- Race conditions between alternatives
- Time-sensitive choices

### Example

```erlang
Config = #{
    pattern_type => deferred_choice,
    name => <<"runtime_decision">>,
    parameters => #{
        options => [
            #{
                name => fast_lane,
                trigger => fun(Data) -> maps:get(priority, Data) =:= urgent end
            },
            #{
                name => standard_lane,
                trigger => fun(Data) -> maps:get(priority, Data) =:= normal end
            }
        ],
        timeout => 30000
    }
}.
```

## Pattern Combinations

Basic patterns can be combined to create more complex workflows:

### Sequential + Parallel Split

```erlang
Config = #{
    pattern_type => sequential,
    name => <<"complex_flow">>,
    parameters => #{
        steps => [
            <<"validate">>,
            #{
                pattern => parallel_split,
                branches => [<<"check_a">>, <<"check_b">>]
            },
            #{
                pattern => parallel_join,
                required_branches => 2
            },
            <<"finalize">>
        ]
    }
}.
```

### Exclusive Choice + Simple Merge

```erlang
Config = #{
    pattern_type => exclusive_choice,
    name => <<"routing_with_merge">>,
    parameters => #{
        conditions => [condition_a, condition_b, condition_c],
        merge_after => true
    }
}.
```

## Best Practices

1. **Start Simple**: Use basic patterns before moving to advanced ones
2. **Combine Carefully**: Ensure pattern combinations make logical sense
3. **Document Decisions**: Clearly document why a pattern was chosen
4. **Test Thoroughly**: Test all possible paths through the workflow
5. **Monitor Performance**: Parallel patterns impact resource usage

## When to Move Beyond Basic Patterns

Consider advanced patterns when you need:
- Complex iteration with exit conditions
- Multi-instance processing
- Advanced cancellation scenarios
- Complex resource allocation
- Time-based triggers and deadlines

---

Next: [Advanced Patterns](advanced-patterns.md) | [Back to Patterns](../patterns/)
