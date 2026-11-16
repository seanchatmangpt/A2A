# Advanced Workflow Patterns

Complex workflow patterns for sophisticated orchestration scenarios.

## Overview

Advanced patterns handle complex routing, iteration, and coordination scenarios beyond the capabilities of basic patterns. These patterns are essential for real-world business processes with multiple decision points, loops, and dynamic execution requirements.

## Pattern List

1. **Multiple Merge** - Merge parallel paths with duplicate processing
2. **Implicit Merge** - Merge without explicit synchronization
3. **N-out-of-N Join** - Wait for N of M parallel branches
4. **Multi-Instance** - Execute task multiple times
5. **Iterative Loop** - Repeat until condition is met
6. **Milestone** - Wait for specific events before proceeding

---

## 1. Multiple Merge

Merge multiple paths where tokens may arrive from different paths at different times, potentially triggering multiple executions of the next task.

### Petri Net Representation

```
Places: [a, b, c, merge, end]
Transitions: [merge]
Edges: a -> merge, b -> merge, c -> merge
      merge -> end (fires for EACH incoming token)
```

### When to Use

- Processing multiple concurrent requests
- Fan-out/fan-in with duplicate handling
- Asynchronous response aggregation

### Example

```erlang
Config = #{
    pattern_type => multiple_merge,
    name => <<"merge_with_duplicates">>,
    parameters => #{
        input_count => 3,
        handle_duplicates => true,
        dedupe_strategy => first_wins
    }
}.
```

---

## 2. Implicit Merge

Merge paths without explicit synchronization point, relying on the workflow engine to handle token management.

### Petri Net Representation

```
Places: [a, b, c, shared_place, end]
Transitions: [process]
Edges: a -> shared_place, b -> shared_place, c -> shared_place
      shared_place -> end
```

### When to Use

- Simple merging without complex synchronization
- Shared resource scenarios
- Performance-critical paths

### Example

```erlang
Config = #{
    pattern_type => implicit_merge,
    name => <<"shared_merge">>,
    parameters => #{
        inputs => [task_a, task_b, task_c],
        shared_resource => <<"database_connection">>
    }
}.
```

---

## 3. N-out-of-N Join

Wait for N out of M parallel branches to complete before proceeding.

### Petri Net Representation

```
Places: [a, b, c, counter, end]
Transitions: [check_n, proceed]
Edges: a -> counter, b -> counter, c -> counter
      counter -> check_n (counts tokens)
      check_n -> proceed (when count >= N)
      proceed -> end
```

### When to Use

- Quorum-based decisions
- Partial results sufficient
- Fault-tolerant parallel execution

### Example

```erlang
Config = #{
    pattern_type => n_out_of_n_join,
    name => <<"majority_vote">>,
    parameters => #{
        total_branches => 5,
        required_branches => 3,
        timeout => 60000,
        on_timeout => use_available
    }
}.
```

### Variations

**2-out-of-3 for reliability:**
```erlang
#{required_branches => 2, total_branches => 3}
```

**Majority decision:**
```erlang
#{required_branches => 3, total_branches => 5}
```

---

## 4. Multi-Instance

Execute a task multiple times, either sequentially or in parallel.

### Types

- **Sequential Multi-Instance**: Execute instances one at a time
- **Parallel Multi-Instance**: Execute all instances simultaneously
- **Synchronized Multi-Instance**: Parallel with barriers

### Petri Net Representation (Parallel)

```
Places: [start, instances[i], end]
Transitions: [spawn, instance[i], join]
Edges: start -> spawn
      spawn -> instance[1], spawn -> instance[2], ..., spawn -> instance[N]
      instance[i] -> join (for all i)
      join -> end (when all complete)
```

### When to Use

- Batch processing
- List item processing
- Parallel processing of independent items

### Example

```erlang
Config = #{
    pattern_type => multi_instance,
    name => <<"batch_processing">>,
    parameters => #{
        num_instances => 10,
        data => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        parallel => true,
        completion_condition => all,  % all | n_percent | custom
        max_parallel => 5
    }
}.
```

### Completion Conditions

```erlang
%% All instances must complete
#{completion_condition => all}

%% 80% completion sufficient
#{completion_condition => {n_percent, 80}}

%% Custom condition
#{completion_condition => {custom, fun(Completed, Total) ->
    Completed >= Total - 1  % Allow one failure
end}}
```

---

## 5. Iterative Loop

Repeat execution until a condition is met, with optional maximum iterations.

### Petri Net Representation

```
Places: [start, loop_body, check, end]
Transitions: [execute, evaluate, exit]
Edges: start -> execute
      execute -> loop_body
      loop_body -> evaluate
      evaluate -> execute (if condition not met)
      evaluate -> exit (if condition met or max reached)
      exit -> end
```

### When to Use

- Retry logic with exponential backoff
- Polling until state change
- Data processing in chunks

### Example

```erlang
Config = #{
    pattern_type => iterative_loop,
    name => <<"retry_with_backoff">>,
    parameters => #{
        condition => fun(Data) ->
            case maps:get(status, Data) of
                success -> stop;
                pending -> continue
            end
        end,
        max_iterations => 10,
        backoff_strategy => exponential,
        initial_delay => 1000,
        max_delay => 60000
    }
}.
```

### Backoff Strategies

```erlang
%% Fixed delay
#{backoff_strategy => fixed, delay => 5000}

%% Exponential backoff
#{backoff_strategy => exponential, initial_delay => 1000, max_delay => 60000}

%% Linear backoff
#{backoff_strategy => linear, increment => 2000}

%% Custom backoff
#{backoff_strategy => {custom, fun(Attempt) ->
    min(1000 * math:pow(2, Attempt), 60000)
end}}
```

---

## 6. Milestone

Wait for a specific event or condition before proceeding, used as a synchronization point.

### Petri Net Representation

```
Places: [before, waiting, after, end]
Transitions: [start_waiting, milestone_reached, proceed]
Edges: before -> start_waiting -> waiting
      waiting -> proceed (when milestone occurs)
      proceed -> after -> end
```

### When to Use

- Gatekeeping on external events
- Synchronization points
- Waiting for approvals

### Example

```erlang
Config = #{
    pattern_type => milestone,
    name => <<"wait_for_approval">>,
    parameters => #{
        milestone_condition => fun(Data) ->
            maps:get(approval_status, Data) =:= approved
        end,
        timeout => 86400000,  % 24 hours
        on_timeout => cancel
    }
}.
```

### Milestone Types

**Event-based milestone:**
```erlang
#{milestone_type => event,
  event_name => payment_received}
```

**Condition-based milestone:**
```erlang
#{milestone_type => condition,
  condition => fun(Data) -> maps:get(balance, Data) > 0 end}
```

**Time-based milestone:**
```erlang
#{milestone_type => time,
  target_time => <<"2024-12-31T23:59:59Z">>}
```

## Pattern Combinations

### Multi-Instance with N-out-of-N Join

```erlang
Config = #{
    pattern_type => multi_instance,
    name => <<"parallel_with_quorum">>,
    parameters => #{
        num_instances => 10,
        parallel => true,
        join_condition => #{
            type => n_out_of_n,
            required => 7,
            total => 10
        }
    }
}.
```

### Iterative Loop with Milestone

```erlang
Config = #{
    pattern_type => iterative_loop,
    name => <<"poll_with_checkpoint">>,
    parameters => #{
        loop_body => fun(Data) -> check_external_system(Data) end,
        condition => fun(Data) -> maps:get(ready, Data, false) end,
        max_iterations => 60,
        milestone => #{
            check_at => [10, 30, 50],
            action => fun(Iteration, Data) ->
                log_progress(Iteration, Data)
            end
        }
    }
}.
```

### Multiple Merge with Resource Allocation

```erlang
Config = #{
    pattern_type => multiple_merge_with_allocation,
    name => <<"merge_with_resources">>,
    parameters => #{
        input_count => 5,
        allocation_strategy => round_robin,
        resources => [resource_1, resource_2, resource_3]
    }
}.
```

## Error Handling

### Retry on Failure

```erlang
Config = #{
    pattern_type => iterative_loop,
    name => <<"retry_until_success">>,
    parameters => #{
        condition => fun(Data) -> maps:get(success, Data, false) end,
        max_iterations => 5,
        on_failure => retry,
        backoff_strategy => exponential
    }
}.
```

### Partial Completion Handling

```erlang
Config = #{
    pattern_type => n_out_of_n_join,
    name => <<"partial_completion">>,
    parameters => #{
        total_branches => 10,
        required_branches => 8,
        on_timeout => use_available,
        handle_failures => log_and_continue
    }
}.
```

## Performance Considerations

### Parallel Instance Limits

```erlang
%% Limit concurrent instances
#{max_parallel => 10,
  queue_when_full => true}
```

### Memory Management

```erlang
%% Stream data instead of loading all
#{data_stream => data_source,
  batch_size => 100}
```

## Best Practices

1. **Use N-out-of-N for fault tolerance** rather than waiting for all
2. **Set reasonable timeouts** on iterative loops
3. **Monitor multi-instance resource usage**
4. **Handle partial failures** gracefully
5. **Log milestone events** for debugging

---

Next: [Cancellation Patterns](cancellation-patterns.md) | [Back to Patterns](../patterns/)
