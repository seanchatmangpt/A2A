# YAWL Patterns Deep Dive

## Overview

This tutorial provides an in-depth exploration of YAWL workflow patterns. You'll learn about the fundamental patterns, how to implement them, and when to use each pattern. We'll cover everything from basic sequences to complex multi-instance patterns with practical examples.

## Prerequisites

- Complete the [Erlang Introduction Tutorial](erlang-intro.md)
- Complete the [First Workflow Tutorial](first-workflow.md)
- Understanding of basic YAWL concepts (places, transitions, tokens)

## What are YAWL Patterns?

YAWL patterns are reusable workflow building blocks that solve common business problems. Each pattern represents a specific workflow structure that can be combined to create complex business processes.

### Pattern Categories

1. **Basic Patterns**: Simple workflow structures
2. **Advanced Patterns**: Complex control flow
3. **Multi-Instance Patterns**: Repeatable workflow elements
4. **Resource Patterns**: Human and system resource handling
5. **Time Patterns**: Time-based workflow behavior

## 1. Basic Sequential Pattern

### Pattern Description
A linear sequence of activities where each step must complete before the next begins.

### When to Use
- Simple approval chains
- Linear processes
- Sequential data processing

### Implementation

```erlang
-module(yawl_sequential_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [start, step1, step2, step3, completed].
trsn_lst() -> [start_step1, start_step2, start_step3].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(start_step1) -> [start];
preset(start_step2) -> [step1];
preset(start_step3) -> [step2].

postset(start_step1) -> [step1];
postset(start_step2) -> [step2];
postset(start_step3) -> [step3, completed].

is_enabled(start_step1, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(start_step2, Mode, _UsrInfo) -> has_token(step1, Mode).
is_enabled(start_step3, Mode, _UsrInfo) -> has_token(step2, Mode).

fire(start_step1, _Mode, UsrInfo) ->
    Data1 = create_step1_data(UsrInfo),
    {produce, #{step1 => [{step1, Data1}]}};
fire(start_step2, _Mode, UsrInfo) ->
    Data2 = create_step2_data(UsrInfo),
    {produce, #{step2 => [{step2, Data2}]}};
fire(start_step3, _Mode, UsrInfo) ->
    Data3 = create_step3_data(UsrInfo),
    {produce, #{step3 => [{step3, Data3}], completed => [completed_token]}}.

trigger(_Place, _Token, _UsrInfo) -> pass.
```

### Usage Example

```erlang
% Create sequential workflow
SequentialSpec = #{
    workflow_id => <<"sequential_test">>,
    pattern_type => basic_sequential,
    steps => [validate, process, approve],
    data => #{initial_data => "some_data"}
}.
```

## 2. Exclusive Choice Pattern

### Pattern Description
A decision point where exactly one of several paths is taken based on conditions.

### When to Use
- Approval workflows (approve/reject)
- Conditional routing
- Business rule decisions

### Implementation

```erlang
-module(yawl_exclusive_choice_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [start, condition, path_a, path_b, path_c, end_a, end_b, end_c].
trsn_lst() -> [evaluate_condition, choose_a, choose_b, choose_c].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(evaluate_condition) -> [start];
preset(choose_a) -> [condition];
preset(choose_b) -> [condition];
preset(choose_c) -> [condition].

postset(evaluate_condition) -> [condition];
postset(choose_a) -> [path_a, end_a];
postset(choose_b) -> [path_b, end_b];
postset(choose_c) -> [path_c, end_c].

is_enabled(evaluate_condition, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(choose_a, Mode, _UsrInfo) ->
    has_token(condition, Mode) and meets_condition_a(Mode).
is_enabled(choose_b, Mode, _UsrInfo) ->
    has_token(condition, Mode) and meets_condition_b(Mode).
is_enabled(choose_c, Mode, _UsrInfo) ->
    has_token(condition, Mode) and meets_condition_c(Mode).

fire(evaluate_condition, _Mode, UsrInfo) ->
    Condition = evaluate_conditions(UsrInfo),
    {produce, #{condition => [{condition, Condition}]}};
fire(choose_a, _Mode, _UsrInfo) ->
    {produce, #{path_a => [path_a_token]}};
fire(choose_b, _Mode, _UsrInfo) ->
    {produce, #{path_b => [path_b_token]}};
fire(choose_c, _Mode, _UsrInfo) ->
    {produce, #{path_c => [path_c_token]}}.

trigger(condition, {condition, _}, _UsrInfo) -> pass;
trigger(end_a, _, _UsrInfo) -> pass;
trigger(end_b, _, _UsrInfo) -> pass;
trigger(end_c, _, _UsrInfo) -> pass.

% Helper functions
meets_condition_a(Mode) ->
    case get_condition_value(Mode) of
        low_cost -> true;
        _ -> false
    end.

meets_condition_b(Mode) ->
    case get_condition_value(Mode) of
        medium_cost -> true;
        _ -> false
    end.

meets_condition_c(Mode) ->
    case get_condition_value(Mode) of
        high_cost -> true;
        _ -> false
    end.

evaluate_conditions(UsrInfo) ->
    Amount = maps:get(amount, UsrInfo, 0),
    case Amount of
        Amount when Amount < 100 -> low_cost;
        Amount when Amount =< 1000 -> medium_cost;
        _ -> high_cost
    end.

get_condition_value(Mode) ->
    case maps:get(condition, Mode, []) of
        [{condition, Value}] -> Value;
        _ -> undefined
    end.
```

### Usage Example

```erlang
% Create exclusive choice workflow
ChoiceSpec = #{
    workflow_id => <<"payment_choice">>,
    pattern_type => exclusive_choice,
    conditions => #{
        low_cost => #{
            path => "fast_payment",
            threshold => 100
        },
        medium_cost => #{
            path => "standard_payment",
            threshold => 1000
        },
        high_cost => #{
            path => "review_payment",
            threshold => infinity
        }
    }
}.
```

## 3. Parallel Split Pattern

### Pattern Description
A workflow fork into multiple parallel branches that execute simultaneously.

### When to Use
- Concurrent processing
- Independent tasks
- Parallel data processing

### Implementation

```erlang
-module(yawl_parallel_split_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [start, decision, branch_a, branch_b, branch_c, sync_point, completed].
trsn_lst() -> [start_parallel, execute_a, execute_b, execute_c, synchronize].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(start_parallel) -> [start];
preset(execute_a) -> [decision];
preset(execute_b) -> [decision];
preset(execute_c) -> [decision];
preset(synchronize) -> [branch_a, branch_b, branch_c].

postset(start_parallel) -> [decision];
postset(execute_a) -> [branch_a];
postset(execute_b) -> [branch_b];
postset(execute_c) -> [branch_c];
postset(synchronize) -> [sync_point, completed].

is_enabled(start_parallel, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(execute_a, Mode, _UsrInfo) -> has_token(decision, Mode).
is_enabled(execute_b, Mode, _UsrInfo) -> has_token(decision, Mode).
is_enabled(execute_c, Mode, _UsrInfo) -> has_token(decision, Mode).
is_enabled(synchronize, Mode, _UsrInfo) ->
    has_token(branch_a, Mode) andalso
    has_token(branch_b, Mode) andalso
    has_token(branch_c, Mode).

fire(start_parallel, _Mode, _UsrInfo) ->
    {produce, #{decision => [decision_token]}};
fire(execute_a, _Mode, UsrInfo) ->
    Data = create_branch_a_data(UsrInfo),
    {produce, #{branch_a => [{branch_a, Data}]}};
fire(execute_b, _Mode, UsrInfo) ->
    Data = create_branch_b_data(UsrInfo),
    {produce, #{branch_b => [{branch_b, Data}]}};
fire(execute_c, _Mode, UsrInfo) ->
    Data = create_branch_c_data(UsrInfo),
    {produce, #{branch_c => [{branch_c, Data}]}};
fire(synchronize, _Mode, _UsrInfo) ->
    {produce, #{sync_point => [sync_token], completed => [completed_token]}}.

trigger(_Place, _Token, _UsrInfo) -> pass.
```

### Usage Example

```erlang
% Create parallel split workflow
ParallelSpec = #{
    workflow_id => <<"order_parallel">>,
    pattern_type => parallel_split,
    branches => [
        #{
            id => inventory_check,
            data => #{type => inventory}
        },
        #{
            id => credit_check,
            data => #{type => credit}
        },
        #{
            id => fraud_check,
            data => #{type => fraud}
        }
    ]
}.
```

## 4. Simple Merge Pattern

### Pattern Description
Multiple paths converge into a single path when all branches are complete.

### When to Use
- Waiting for all parallel tasks
- Task aggregation
- Final coordination

### Implementation

```erlang
-module(yawl_simple_merge_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [start, task1, task2, task3, merge_point, completed].
trsn_lst() -> [execute_task1, execute_task2, execute_task3, complete_tasks].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(execute_task1) -> [start];
preset(execute_task2) -> [start];
preset(execute_task3) -> [start];
preset(complete_tasks) -> [task1, task2, task3].

postset(execute_task1) -> [task1];
postset(execute_task2) -> [task2];
postset(execute_task3) -> [task3];
postset(complete_tasks) -> [merge_point, completed].

is_enabled(execute_task1, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(execute_task2, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(execute_task3, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(complete_tasks, Mode, _UsrInfo) ->
    has_token(task1, Mode) andalso
    has_token(task2, Mode) andalso
    has_token(task3, Mode).

fire(execute_task1, _Mode, UsrInfo) ->
    Result1 = perform_task1(UsrInfo),
    {produce, #{task1 => [{task1, Result1}]}};
fire(execute_task2, _Mode, UsrInfo) ->
    Result2 = perform_task2(UsrInfo),
    {produce, #{task2 => [{task2, Result2}]}};
fire(execute_task3, _Mode, UsrInfo) ->
    Result3 = perform_task3(UsrInfo),
    {produce, #{task3 => [{task3, Result3}]}};
fire(complete_tasks, _Mode, _UsrInfo) ->
    {produce, #{merge_point => [merge_token], completed => [completed_token]}}.

trigger(_Place, _Token, _UsrInfo) -> pass.

% Task functions
perform_task1(UsrInfo) ->
    #{
        task_id => task1,
        data => maps:get(input_data, UsrInfo, <<>>),
        result => task1_completed,
        timestamp => erlang:system_time(millisecond)
    }.

perform_task2(UsrInfo) ->
    #{
        task_id => task2,
        data => maps:get(input_data, UsrInfo, <<>>),
        result => task2_completed,
        timestamp => erlang:system_time(millisecond)
    }.

perform_task3(UsrInfo) ->
    #{
        task_id => task3,
        data => maps:get(input_data, UsrInfo, <<>>),
        result => task3_completed,
        timestamp => erlang:system_time(millisecond)
    }.
```

## 5. Multi-Instance Pattern

### Pattern Description
Repeats a task multiple times for multiple items or instances.

### When to Use
- Batch processing
- Multiple approvals
- Iterative operations

### Implementation

```erlang
-module(yawl_multi_instance_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

-define(MAX_INSTANCES, 10).

place_lst() -> [
    start,
    loop_start,
    create_instances,
    instances_created,
    process_instance,
    instances_complete,
    completed
].
trsn_lst() -> [
    initialize_loop,
    create_multi_instances,
    process_single_instance,
    check_completion
].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(initialize_loop) -> [start];
preset(create_multi_instances) -> [loop_start];
preset(process_single_instance) -> [instances_created];
preset(check_completion) -> [instances_complete].

postset(initialize_loop) -> [loop_start];
postset(create_multi_instances) -> [instances_created];
postset(process_single_instance) -> [instances_complete];
postset(check_completion) -> [loop_start, completed].

is_enabled(initialize_loop, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(create_multi_instances, Mode, _UsrInfo) -> has_token(loop_start, Mode).
is_enabled(process_single_instance, Mode, _UsrInfo) ->
    has_tokens(instances_created, Mode).
is_enabled(check_completion, Mode, _UsrInfo) ->
    has_token(instances_complete, Mode).

fire(initialize_loop, _Mode, UsrInfo) ->
    InstanceCount = get_instance_count(UsrInfo),
    {produce, #{loop_start => [init_token]}};
fire(create_multi_instances, _Mode, UsrInfo) ->
    InstanceCount = get_instance_count(UsrInfo),
    Instances = create_instances(InstanceCount, UsrInfo),
    {produce, #{instances_created => Instances}};
fire(process_single_instance, Mode, UsrInfo) ->
    Instance = get_next_instance(Mode),
    Result = process_instance(Instance, UsrInfo),
    {produce, #{instances_complete => [result_token]}};
fire(check_completion, Mode, _UsrInfo) ->
    ProcessedCount = get_processed_count(Mode),
    TotalCount = get_total_count(Mode),
    case ProcessedCount >= TotalCount of
        true ->
            {produce, #{completed => [completed_token]}};
        false ->
            {produce, #{loop_start => [continue_token]}}
    end.

trigger(_Place, _Token, _UsrInfo) -> pass.

% Helper functions
get_instance_count(UsrInfo) ->
    case maps:get(items, UsrInfo, []) of
        Items when length(Items) > 0 -> length(Items);
        _ -> 5  % Default count
    end.

create_instances(Count, UsrInfo) ->
    Items = maps:get(items, UsrInfo, lists:seq(1, Count)),
    lists:map(fun(Item) ->
        {instance, #{
            id => generate_instance_id(),
            data => Item,
            status => pending
        }}
    end, Items).

get_next_instance(Mode) ->
    % In real implementation, this would track which instances need processing
    #{id => next_instance, data => sample_data}.

process_instance(Instance, _UsrInfo) ->
    % Simulate processing
    Instance#{status => processed, processed_at => erlang:system_time(millisecond)}.

get_processed_count(Mode) ->
    case maps:get(instances_complete, Mode, []) of
        Results -> length(Results);
        _ -> 0
    end.

get_total_count(Mode) ->
    case maps:get(instances_created, Mode, []) of
        Instances -> length(Instances);
        _ -> 0
    end.

generate_instance_id() ->
    list_to_binary("instance_" ++ integer_to_list(erlang:unique_integer([positive]))).
```

### Usage Example

```erlang
% Create multi-instance workflow
MultiInstanceSpec = #{
    workflow_id => <<"batch_processing">>,
    pattern_type => multi_instance,
    configuration => #{
        max_instances => 10,
        data_source => orders,
        process_function => process_order,
        completion_condition => all
    }
}.
```

## 6. Cancellation Pattern

### Pattern Description
Aborts part of a workflow when certain conditions are met.

### When to Use
- Exception handling
- Timeout scenarios
- Business rule violations

### Implementation

```erlang
-module(yawl_cancellation_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [
    start,
    normal_flow,
    check_timeout,
    timeout_occurred,
    cancel_branch,
    cancelled,
    completed
].
trsn_lst() -> [
    start_normal,
    check_timeout_condition,
    trigger_cancellation,
    complete_successfully,
    handle_cancel
].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(start_normal) -> [start];
preset(check_timeout_condition) -> [normal_flow];
preset(trigger_cancellation) -> [timeout_occurred];
preset(complete_successfully) -> [normal_flow];
preset(handle_cancel) -> [cancel_branch].

postset(start_normal) -> [normal_flow];
postset(check_timeout_condition) -> [timeout_occurred, normal_flow];
postset(trigger_cancellation) -> [cancelled];
postset(complete_successfully) -> [completed];
postset(handle_cancel) -> [cancelled].

is_enabled(start_normal, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(check_timeout_condition, Mode, _UsrInfo) -> has_token(normal_flow, Mode).
is_enabled(trigger_cancellation, Mode, _UsrInfo) -> has_token(timeout_occurred, Mode).
is_enabled(complete_successfully, Mode, _UsrInfo) ->
    has_token(normal_flow, Mode) and not has_token(timeout_occurred, Mode).
is_enabled(handle_cancel, Mode, _UsrInfo) -> has_token(cancel_branch, Mode).

fire(start_normal, _Mode, UsrInfo) ->
    Data = create_workflow_data(UsrInfo),
    {produce, #{normal_flow => [{flow, Data}]}};
fire(check_timeout_condition, Mode, _UsrInfo) ->
    case is_timeout(Mode, UsrInfo) of
        true ->
            {produce, #{timeout_occurred => [timeout_token]}};
        false ->
            {produce, #{}}
    end};
fire(trigger_cancellation, _Mode, _UsrInfo) ->
    {produce, #{cancel_branch => [cancel_token]}};
fire(complete_successfully, Mode, _UsrInfo) ->
    {produce, #{completed => [success_token]}};
fire(handle_cancel, _Mode, _UsrInfo) ->
    {produce, #{cancelled => [cancel_token]}}.

trigger(normal_flow, {flow, _}, _UsrInfo) -> pass;
trigger(cancelled, _, _UsrInfo) -> drop;
trigger(completed, _, _UsrInfo) -> pass.

% Helper functions
is_timeout(Mode, UsrInfo) ->
    StartTime = maps:get(start_time, Mode, erlang:system_time(millisecond)),
    Timeout = maps:get(timeout, UsrInfo, 30000),  % 30 seconds default
    (erlang:system_time(millisecond) - StartTime) > Timeout.

create_workflow_data(UsrInfo) ->
    #{
        workflow_id => generate_id(<<"workflow">>),
        start_time => erlang:system_time(millisecond),
        timeout => maps:get(timeout, UsrInfo, 30000),
        data => maps:get(input_data, UsrInfo, <<>>)
    }.
```

## 7. Iterative Loop Pattern

### Pattern Description
Repeats a workflow loop until a termination condition is met.

### When to Use
- Retry mechanisms
- Iterative processing
- Convergent processes

### Implementation

```erlang
-module(yawl_iterative_loop_pattern).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [
    start,
    check_condition,
    loop_body,
    process_iteration,
    continue_loop,
    exit_loop,
    completed
].
trsn_lst() -> [
    initialize_loop,
    evaluate_condition,
    execute_iteration,
    continue,
    exit,
    finalize
].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(initialize_loop) -> [start];
preset(evaluate_condition) -> [check_condition];
preset(execute_iteration) -> [loop_body];
preset(continue) -> [process_iteration];
preset(exit) -> [process_iteration];
preset(finalize) -> [exit_loop].

postset(initialize_loop) -> [check_condition];
postset(evaluate_condition) -> [loop_body];
postset(execute_iteration) -> [process_iteration];
postset(continue) -> [loop_body];
postset(exit) -> [exit_loop];
postset(finalize) -> [completed].

is_enabled(initialize_loop, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(evaluate_condition, Mode, _UsrInfo) -> has_token(check_condition, Mode).
is_enabled(execute_iteration, Mode, _UsrInfo) -> has_token(loop_body, Mode).
is_enabled(continue, Mode, _UsrInfo) ->
    has_token(process_iteration, Mode) and should_continue(Mode);
is_enabled(exit, Mode, _UsrInfo) ->
    has_token(process_iteration, Mode) and not should_continue(Mode).
is_enabled(finalize, Mode, _UsrInfo) -> has_token(exit_loop, Mode).

fire(initialize_loop, _Mode, UsrInfo) ->
    InitialState = create_loop_state(UsrInfo),
    {produce, #{check_condition => [state, InitialState]}};
fire(evaluate_condition, Mode, _UsrInfo) ->
    State = get_loop_state(Mode),
    ConditionResult = evaluate_condition(State, UsrInfo),
    {produce, #{loop_body => [iteration, ConditionResult]}};
fire(execute_iteration, _Mode, UsrInfo) ->
    IterationResult = perform_iteration(UsrInfo),
    {produce, #{process_iteration => [result, IterationResult]}};
fire(continue, Mode, _UsrInfo) ->
    State = update_loop_state(Mode, continue),
    {produce, #{loop_body => [state, State]}};
fire(exit, Mode, _UsrInfo) ->
    State = update_loop_state(Mode, exit),
    {produce, #{exit_loop => [state, State]}};
fire(finalize, _Mode, _UsrInfo) ->
    {produce, #{completed => [completed_token]}}.

trigger(check_condition, {state, _}, _UsrInfo) -> pass;
trigger(loop_body, {iteration, _}, _UsrInfo) -> pass;
trigger(process_iteration, {result, _}, _UsrInfo) -> pass;
trigger(exit_loop, {state, _}, _UsrInfo) -> pass.

% Helper functions
create_loop_state(UsrInfo) ->
    #{
        iteration => 1,
        max_iterations => maps:get(max_iterations, UsrInfo, 10),
        data => maps:get(input_data, UsrInfo, <<>>),
        results => [],
        continue => true
    }.

get_loop_state(Mode) ->
    case maps:get(check_condition, Mode, []) of
        [{state, State}] -> State;
        _ -> #{}
    end.

update_loop_state(Mode, Action) ->
    CurrentState = get_loop_state(Mode),
    case Action of
        continue ->
            CurrentState#{
                iteration => maps:get(iteration, CurrentState) + 1,
                continue => should_continue(CurrentState)
            };
        exit ->
            CurrentState#{continue => false}
    end.

should_continue(State) ->
    Iteration = maps:get(iteration, State, 0),
    MaxIterations = maps:get(max_iterations, State, 10),
    Converged = check_convergence(State),
    Iteration < MaxIterations andalso not Converged.

check_convergence(State) ->
    % Simple convergence check - in real implementation, this would be more complex
    Results = maps:get(results, State, []),
    length(Results) >= 3.

evaluate_condition(State, _UsrInfo) ->
    % Return condition evaluation result
    maps:get(continue, State, true).

perform_iteration(UsrInfo) ->
    % Perform the actual iteration work
    #{
        iteration_data => maps:get(input_data, UsrInfo, <<>>),
        result => iteration_completed,
        timestamp => erlang:system_time(millisecond)
    }.
```

## 8. Complex Pattern Combination

Real-world workflows often combine multiple patterns:

```erlang
-module(yawl_complex_workflow).
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() -> [
    start,
    validation,
    % Exclusive choice paths
    low_cost_path,
    medium_cost_path,
    high_cost_path,
    % Parallel split
    parallel_start,
    inventory_check,
    credit_check,
    fraud_check,
    % Simple merge
    all_checks_complete,
    % Multi-instance
    batch_start,
    batch_processing,
    batch_complete,
    completion
].
trsn_lst() -> [
    validate_order,
    route_low_cost,
    route_medium_cost,
    route_high_cost,
    start_parallel_checks,
    check_inventory,
    check_credit,
    check_fraud,
    complete_checks,
    start_batch_processing,
    process_batch,
    finalize_order
].

init_marking(start, _UsrInfo) -> [workflow_token].
init_marking(_Place, _UsrInfo) -> [].

preset(validate_order) -> [start];
preset(route_low_cost) -> [validation];
preset(route_medium_cost) -> [validation];
preset(route_high_cost) -> [validation];
preset(start_parallel_checks) -> [low_cost_path, medium_cost_path, high_cost_path];
preset(check_inventory) -> [parallel_start];
preset(check_credit) -> [parallel_start];
preset(check_fraud) -> [parallel_start];
preset(complete_checks) -> [inventory_check, credit_check, fraud_check];
preset(start_batch_processing) -> [all_checks_complete];
preset(process_batch) -> [batch_start];
preset(finalize_order) -> [batch_complete].

postset(validate_order) -> [validation];
postset(route_low_cost) -> [low_cost_path];
postset(route_medium_cost) -> [medium_cost_path];
postset(route_high_cost) -> [high_cost_path];
postset(start_parallel_checks) -> [parallel_start];
postset(check_inventory) -> [inventory_check];
postset(check_credit) -> [credit_check];
postset(check_fraud) -> [fraud_check];
postset(complete_checks) -> [all_checks_complete];
postset(start_batch_processing) -> [batch_start];
postset(process_batch) -> [batch_complete];
postset(finalize_order) -> [completion].

is_enabled(validate_order, Mode, _UsrInfo) -> has_token(start, Mode).
is_enabled(route_low_cost, Mode, _UsrInfo) -> has_token(validation, Mode) and is_low_cost(Mode).
is_enabled(route_medium_cost, Mode, _UsrInfo) -> has_token(validation, Mode) and is_medium_cost(Mode).
is_enabled(route_high_cost, Mode, _UsrInfo) -> has_token(validation, Mode) and is_high_cost(Mode).
is_enabled(start_parallel_checks, Mode, _UsrInfo) ->
    has_token(low_cost_path, Mode) orelse
    has_token(medium_cost_path, Mode) orelse
    has_token(high_cost_path, Mode).
is_enabled(check_inventory, Mode, _UsrInfo) -> has_token(parallel_start, Mode).
is_enabled(check_credit, Mode, _UsrInfo) -> has_token(parallel_start, Mode).
is_enabled(check_fraud, Mode, _UsrInfo) -> has_token(parallel_start, Mode).
is_enabled(complete_checks, Mode, _UsrInfo) ->
    has_token(inventory_check, Mode) andalso
    has_token(credit_check, Mode) andalso
    has_token(fraud_check, Mode).
is_enabled(start_batch_processing, Mode, _UsrInfo) -> has_token(all_checks_complete, Mode).
is_enabled(process_batch, Mode, _UsrInfo) -> has_token(batch_start, Mode).
is_enabled(finalize_order, Mode, _UsrInfo) -> has_token(batch_complete, Mode).

fire(validate_order, _Mode, UsrInfo) ->
    OrderData = create_order_data(UsrInfo),
    {produce, #{validation => [{order, OrderData}]}};
fire(route_low_cost, _Mode, _UsrInfo) ->
    {produce, #{low_cost_path => [low_cost_token]}};
fire(route_medium_cost, _Mode, _UsrInfo) ->
    {produce, #{medium_cost_path => [medium_cost_token]}};
fire(route_high_cost, _Mode, _UsrInfo) ->
    {produce, #{high_cost_path => [high_cost_token]}};
fire(start_parallel_checks, _Mode, _UsrInfo) ->
    {produce, #{parallel_start => [start_token]}};
fire(check_inventory, _Mode, UsrInfo) ->
    Result = check_inventory(UsrInfo),
    {produce, #{inventory_check => [{result, Result}]}};
fire(check_credit, _Mode, UsrInfo) ->
    Result = check_credit(UsrInfo),
    {produce, #{credit_check => [{result, Result}]}};
fire(check_fraud, _Mode, UsrInfo) ->
    Result = check_fraud(UsrInfo),
    {produce, #{fraud_check => [{result, Result}]}};
fire(complete_checks, _Mode, _UsrInfo) ->
    {produce, #{all_checks_complete => [complete_token]}};
fire(start_batch_processing, _Mode, UsrInfo) ->
    BatchItems = create_batch_items(UsrInfo),
    {produce, #{batch_start => [{items, BatchItems}]}};
fire(process_batch, Mode, _UsrInfo) ->
    Processed = process_batch_items(Mode),
    {produce, #{batch_complete => [{results, Processed}]}};
fire(finalize_order, _Mode, _UsrInfo) ->
    {produce, #{completion => [completion_token]}}.

trigger(_Place, _Token, _UsrInfo) -> pass.

% Helper functions
create_order_data(UsrInfo) ->
    maps:get(order_data, UsrInfo, #{}).

is_low_cost(Mode) ->
    case maps:get(validation, Mode, []) of
        [{order, Order}] -> maps:get(amount, Order, 0) < 100;
        _ -> false
    end.

is_medium_cost(Mode) ->
    case maps:get(validation, Mode, []) of
        [{order, Order}] ->
            Amount = maps:get(amount, Order, 0),
            Amount >= 100 and Amount =< 1000;
        _ -> false
    end.

is_high_cost(Mode) ->
    case maps:get(validation, Mode, []) of
        [{order, Order}] -> maps:get(amount, Order, 0) > 1000;
        _ -> false
    end.

check_inventory(UsrInfo) ->
    #{
        check_type => inventory,
        result => ok,
        timestamp => erlang:system_time(millisecond)
    }.

check_credit(UsrInfo) ->
    #{
        check_type => credit,
        result => ok,
        timestamp => erlang:system_time(millisecond)
    }.

check_fraud(UsrInfo) ->
    #{
        check_type => fraud,
        result => ok,
        timestamp => erlang:system_time(millisecond)
    }.

create_batch_items(UsrInfo) ->
    lists:map(fun(I) ->
        #{id => list_to_binary("item_" ++ integer_to_list(I)), quantity => I}
    end, lists:seq(1, 5)).

process_batch_items(Mode) ->
    case maps:get(batch_start, Mode, []) of
        [{items, Items}] ->
            lists:map(fun(Item) ->
                Item#{status => processed}
            end, Items);
        _ -> []
    end.
```

## Pattern Selection Guide

| Pattern | Use Case | Complexity | Performance |
|---------|----------|------------|-------------|
| Sequential | Linear processes | Low | High |
| Exclusive Choice | Decision points | Low | High |
| Parallel Split | Concurrent tasks | Medium | Medium |
| Simple Merge | Task aggregation | Medium | Medium |
| Multi-Instance | Batch processing | High | Low |
| Cancellation | Exception handling | Medium | Medium |
| Iterative Loop | Retry mechanisms | High | Variable |

## Best Practices

1. **Keep Patterns Simple**: Each pattern should do one thing well
2. **Use Composition**: Combine patterns for complex workflows
3. **Document Business Rules**: Clearly state when each path is taken
4. **Test Thoroughly**: Test all possible paths and combinations
5. **Consider Performance**: Some patterns have performance implications
6. **Error Handling**: Always include error handling paths

## Real-World Examples

### E-commerce Order Processing

```erlang
% Combines: Sequential + Exclusive Choice + Parallel Split + Multi-Instance
order_processing_workflow() ->
    #{
        workflow_id => <<"ecommerce_order">>,
        pattern_sequence => [
            {validate, sequential},
            {route_payment, exclusive_choice},
            {perform_checks, parallel_split},
            {ship_items, multi_instance}
        ]
    }.
```

### Loan Approval Process

```erlang
% Combines: Sequential + Exclusive Choice + Cancellation + Iterative Loop
loan_approval_workflow() ->
    #{
        workflow_id => <<"loan_approval">>,
        pattern_sequence => [
            {initial_review, sequential},
            {risk_assessment, exclusive_choice},
            {request_additional_info, iterative_loop},
            {final_decision, exclusive_choice},
            {handle_rejection, cancellation}
        ]
    }.
```

## Next Steps

Now that you understand YAWL patterns in depth, you're ready to:

1. **Business Workflows**: Study how these patterns apply to real business scenarios
2. **REST API**: Learn to expose your pattern-based workflows via HTTP
3. **Testing**: Implement comprehensive pattern testing strategies
4. **Performance**: Optimize pattern combinations for performance

## Key Takeaways

1. **Patterns are building blocks**: Combine them to create complex workflows
2. **Each pattern has a purpose**: Choose the right pattern for the problem
3. **Performance matters**: Consider scalability implications
4. **Error handling**: Always include failure scenarios
5. **Documentation**: Clearly document your pattern choices
6. **Testing**: Test all paths and edge cases

YAWL patterns provide a powerful way to model complex business processes systematically!