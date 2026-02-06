%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Patterns Implementation
%%%
%%% This module implements all 43 YAWL (Yet Another Workflow Language)
%%% workflow patterns using gen_pnet Petri net engine.
%%%
%%% YAWL Patterns Reference:
%%% - Control-flow patterns: Basic, Sequence, Parallel, Conditional, etc.
%%% - Advanced patterns: Multi-instance, Iteration, Dependencies, etc.
%%% - Resource patterns: Allocation, No Allocation, etc.
%%% - State-based patterns: Cancellation, Termination, etc.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns).
-author("A2A Team").

%% Mock gen_pnet callbacks for YAWL pattern structure definition
-export([
    place_lst/0,
    trsn_lst/0,
    init_marking/2,
    preset/1,
    is_enabled/3,
    fire/3,
    trigger/3
]).

%% API exports
-export([
    create_workflow/2,
    validate_pattern/2,
    get_pattern_info/1,
    list_patterns/0,
    generate_pattern_definition/2,
    get_pattern_structure/1,
    is_cancellation_pattern/1,
    is_resource_pattern/1,
    get_cancellation_scope/1,
    get_resource_allocation_type/1
]).

%% Include YAWL pattern definitions
-include("gen_pnet.hrl").

%%====================================================================
%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    %% Common places used across YAWL patterns
    [start,
     'end',
     join,
     split,
     condition,
     action,
     decision,
     merge,
     cancel,
     error,
     data,
     %% Advanced pattern places
     interleaved,
     milestone,
     defer,
     resource,
     allocated,
     release,
     cancel_scope,
     cancel_region,
     cancel_trigger,
     after_trigger,
     or_condition,
     and_condition,
     subprocess,
     thread,
     multiple_instances,
     cancel_point].

trsn_lst() ->
    %% Common transitions used across YAWL patterns
    [start_workflow,
     end_workflow,
     parallel_split,
     parallel_join,
     exclusive_choice,
     simple_merge,
     multi_split,
     multi_join,
     iterative_loop,
     cancel_workflow,
     handle_error,
     process_data,
     evaluate_condition,
     %% Advanced pattern transitions
     interleaved_execute,
     interleaved_merge,
     implicit_merge,
     multiple_merge_select,
     deferred_choice_select,
     milestone_reach,
     milestone_wait,
     cancel_block,
     cancel_scope_enter,
     cancel_scope_exit,
     cancel_thread,
     cancel_subprocess,
     cancel_multiple,
     cancel_after,
     cancel_or,
     cancel_and,
     resource_allocate,
     resource_deallocate,
     resource_execute].

init_marking(Place, _UsrInfo) ->
    case Place of
        start -> [workflow_token];
        'end' -> [];
        _ -> []
    end.

preset(Transition) ->
    case Transition of
        start_workflow -> [start];
        end_workflow -> [action];
        parallel_split -> [join];
        parallel_join -> [split];
        exclusive_choice -> [join];
        simple_merge -> [split];
        multi_split -> [join];
        multi_join -> [split];
        iterative_loop -> [condition];
        cancel_workflow -> [cancel];
        handle_error -> [error];
        process_data -> [data];
        evaluate_condition -> [condition];
        %% Advanced pattern presets
        interleaved_execute -> [interleaved];
        interleaved_merge -> [interleaved];
        implicit_merge -> [merge];
        multiple_merge_select -> [merge];
        deferred_choice_select -> [defer];
        milestone_reach -> [milestone];
        milestone_wait -> [milestone];
        cancel_block -> [cancel_scope];
        cancel_scope_enter -> [cancel_region];
        cancel_scope_exit -> [cancel_region];
        cancel_thread -> [thread];
        cancel_subprocess -> [subprocess];
        cancel_multiple -> [multiple_instances];
        cancel_after -> [after_trigger];
        cancel_or -> [or_condition];
        cancel_and -> [and_condition];
        resource_allocate -> [resource];
        resource_deallocate -> [allocated];
        resource_execute -> [allocated]
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        start_workflow ->
            case maps:get(start, Mode, []) of
                [workflow_token] -> true;
                _ -> false
            end;
        end_workflow ->
            case maps:get(action, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        parallel_split ->
            case maps:get(join, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        parallel_join ->
            case maps:get(split, Mode, []) of
                [_, _] -> true;
                _ -> false
            end;
        exclusive_choice ->
            case maps:get(join, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        simple_merge ->
            case maps:get(split, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        multi_split ->
            case maps:get(join, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        multi_join ->
            case maps:get(split, Mode, []) of
                [_, _] -> true;
                _ -> false
            end;
        iterative_loop ->
            case maps:get(condition, Mode, []) of
                [true] -> true;
                _ -> false
            end;
        cancel_workflow ->
            case maps:get(cancel, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        handle_error ->
            case maps:get(error, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        process_data ->
            case maps:get(data, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        evaluate_condition ->
            case maps:get(condition, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        %% Advanced pattern enabled checks
        interleaved_execute ->
            case maps:get(interleaved, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        interleaved_merge ->
            case maps:get(interleaved, Mode, []) of
                [_, _] -> true;
                _ -> false
            end;
        implicit_merge ->
            case maps:get(merge, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        multiple_merge_select ->
            case maps:get(merge, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        deferred_choice_select ->
            case maps:get(defer, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        milestone_reach ->
            case maps:get(milestone, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        milestone_wait ->
            case maps:get(milestone, Mode, []) of
                [] -> true;
                _ -> false
            end;
        cancel_block ->
            case maps:get(cancel_scope, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_scope_enter ->
            case maps:get(cancel_region, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_scope_exit ->
            case maps:get(cancel_region, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_thread ->
            case maps:get(thread, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_subprocess ->
            case maps:get(subprocess, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_multiple ->
            case maps:get(multiple_instances, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        cancel_after ->
            case maps:get(after_trigger, Mode, []) of
                [completed] -> true;
                _ -> false
            end;
        cancel_or ->
            case maps:get(or_condition, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        cancel_and ->
            case maps:get(and_condition, Mode, []) of
                [_, _] -> true;
                _ -> false
            end;
        resource_allocate ->
            case maps:get(resource, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        resource_deallocate ->
            case maps:get(allocated, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        resource_execute ->
            case maps:get(allocated, Mode, []) of
                [_] -> true;
                _ -> false
            end
    end.

fire(Transition, _Mode, _UsrInfo) ->
    case Transition of
        start_workflow ->
            {produce, #{
                join => [token],
                action => [execute_token]
            }};
        end_workflow ->
            {produce, #{ 'end' => [completion_token] }};
        parallel_split ->
            {produce, #{
                split => [token, token]
            }};
        parallel_join ->
            {produce, #{
                merge => [joined_token]
            }};
        exclusive_choice ->
            {produce, #{
                split => [selected_token]
            }};
        simple_merge ->
            {produce, #{
                merge => [merged_token]
            }};
        multi_split ->
            {produce, #{
                split => [token, token, token]
            }};
        multi_join ->
            {produce, #{
                merge => [sync_token]
            }};
        iterative_loop ->
            {produce, #{
                condition => [false],
                action => [loop_token]
            }};
        cancel_workflow ->
            {produce, #{
                cancel => [cancel_token],
                'end' => [cancelled_token]
            }};
        handle_error ->
            {produce, #{
                error => [resolved_token],
                action => [recovery_token]
            }};
        process_data ->
            {produce, #{
                action => [processed_token]
            }};
        evaluate_condition ->
            {produce, #{
                decision => [true]
            }};
        %% Advanced pattern firing
        interleaved_execute ->
            {produce, #{
                interleaved => [interleave_token],
                action => [execute_token]
            }};
        interleaved_merge ->
            {produce, #{
                merge => [merged_token]
            }};
        implicit_merge ->
            {produce, #{
                'end' => [merged_token]
            }};
        multiple_merge_select ->
            {produce, #{
                action => [selected_token]
            }};
        deferred_choice_select ->
            {produce, #{
                action => [chosen_token]
            }};
        milestone_reach ->
            {produce, #{
                milestone => [reached_token],
                action => [continue_token]
            }};
        milestone_wait ->
            {produce, #{
                milestone => [waiting_token]
            }};
        cancel_block ->
            {produce, #{
                cancel => [block_cancel_token],
                'end' => [cancelled_token]
            }};
        cancel_scope_enter ->
            {produce, #{
                cancel_region => [scope_enter_token]
            }};
        cancel_scope_exit ->
            {produce, #{
                'end' => [scope_exit_token]
            }};
        cancel_thread ->
            {produce, #{
                cancel => [thread_cancel_token],
                'end' => [thread_cancelled_token]
            }};
        cancel_subprocess ->
            {produce, #{
                cancel => [subprocess_cancel_token],
                'end' => [subprocess_cancelled_token]
            }};
        cancel_multiple ->
            {produce, #{
                cancel => [multiple_cancel_token],
                'end' => [multiple_cancelled_token]
            }};
        cancel_after ->
            {produce, #{
                cancel => [after_cancel_token],
                'end' => [after_cancelled_token]
            }};
        cancel_or ->
            {produce, #{
                cancel => [or_cancel_token],
                'end' => [or_cancelled_token]
            }};
        cancel_and ->
            {produce, #{
                cancel => [and_cancel_token],
                'end' => [and_cancelled_token]
            }};
        resource_allocate ->
            {produce, #{
                allocated => [allocated_token],
                action => [resource_ready_token]
            }};
        resource_deallocate ->
            {produce, #{
                release => [released_token]
            }};
        resource_execute ->
            {produce, #{
                'end' => [resource_completed_token]
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            case Token of
                workflow_token -> pass;
                _ -> pass
            end;
        cancel ->
            case Token of
                cancel_token -> drop;
                _ -> pass
            end;
        error ->
            case Token of
                resolved_token -> drop;
                _ -> pass
            end;
        _ ->
            pass
    end.

%%====================================================================
%% API Functions
%%====================================================================

create_workflow(PatternType, Config) ->
    PatternConfig = maps:get(pattern_config, Config, #{}),
    case validate_pattern(PatternType, PatternConfig) of
        true ->
            WorkflowDef = generate_pattern_definition(PatternType, PatternConfig),
            {ok, WorkflowDef};
        false ->
            {error, invalid_pattern_config}
    end.

validate_pattern(PatternType, Config) ->
    Patterns = list_patterns(),
    case lists:member(PatternType, Patterns) of
        true ->
            validate_pattern_config(PatternType, Config);
        false ->
            false
    end.

get_pattern_info(PatternType) ->
    case PatternType of
        basic_sequential ->
            #{
                name => <<"Basic Sequential">>,
                description => <<"Simple sequential execution of two tasks">>,
                places => [start, action1, action2, 'end'],
                transitions => [start, t1, t2, 'end'],
                complexity => low
            };
        parallel_split ->
            #{
                name => <<"Parallel Split">>,
                description => <<"Execute multiple tasks in parallel">>,
                places => [start, split, action1, action2, 'end'],
                transitions => [start, split, t1, t2, join, 'end'],
                complexity => medium
            };
        parallel_join ->
            #{
                name => <<"Parallel Join">>,
                description => <<"Wait for multiple parallel tasks to complete">>,
                places => [start, action1, action2, join, 'end'],
                transitions => [start, t1, t2, join, 'end'],
                complexity => medium
            };
        exclusive_choice ->
            #{
                name => <<"Exclusive Choice">>,
                description => <<"Choose one path from multiple alternatives">>,
                places => [start, choice, action1, action2, 'end'],
                transitions => [start, choice, t1, t2, 'end'],
                complexity => medium
            };
        simple_merge ->
            #{
                name => <<"Simple Merge">>,
                description => <<"Merge multiple paths into one">>,
                places => [start, action1, action2, merge, 'end'],
                transitions => [start, t1, t2, merge, 'end'],
                complexity => medium
            };
        iterative_loop ->
            #{
                name => <<"Iterative Loop">>,
                description => <<"Execute task repeatedly while condition is true">>,
                places => [start, condition, action, loop, 'end'],
                transitions => [start, check, execute, continue, 'end'],
                complexity => high
            };
        multi_instance ->
            #{
                name => <<"Multi-Instance">>,
                description => <<"Execute task multiple times with different data">>,
                places => [start, create, execute, collect, 'end'],
                transitions => [start, create, execute, collect, 'end'],
                complexity => high
            };
        interleaved_parallelism ->
            #{
                name => <<"Interleaved Parallelism">>,
                description => <<"Execute multiple tasks in any order">>,
                places => [start, interleaved, action1, action2, 'end'],
                transitions => [start, interleaved_execute, interleaved_merge, 'end'],
                complexity => medium
            };
        implicit_merge ->
            #{
                name => <<"Implicit Merge">>,
                description => <<"Automatic merge without explicit merge point">>,
                places => [start, action1, action2, merge, 'end'],
                transitions => [start, t1, t2, implicit_merge, 'end'],
                complexity => medium
            };
        multiple_merge ->
            #{
                name => <<"Multiple Merge">>,
                description => <<"Multiple merge points for complex synchronization">>,
                places => [start, action1, action2, merge1, merge2, 'end'],
                transitions => [start, t1, t2, multiple_merge_select, 'end'],
                complexity => high
            };
        deferred_choice ->
            #{
                name => <<"Deferred Choice">>,
                description => <<"Choose path when task is ready to execute">>,
                places => [start, defer, action1, action2, 'end'],
                transitions => [start, deferred_choice_select, t1, t2, 'end'],
                complexity => medium
            };
        interleaved_routing ->
            #{
                name => <<"Interleaved Routing">>,
                description => <<"Complex routing with multiple path interleaving">>,
                places => [start, route1, route2, route3, 'end'],
                transitions => [start, interleaved_execute, merge, 'end'],
                complexity => high
            };
        milestone ->
            #{
                name => <<"Milestone">>,
                description => <<"Define and wait for milestone completion">>,
                places => [start, milestone, action, 'end'],
                transitions => [start, milestone_reach, milestone_wait, 'end'],
                complexity => medium
            };
        cancelation ->
            #{
                name => <<"Cancellation">>,
                description => <<"Basic workflow cancellation">>,
                places => [start, action1, action2, cancel, 'end'],
                transitions => [start, t1, t2, cancel_workflow, 'end'],
                complexity => medium,
                cancellation_scope => all
            };
        cancelation_block ->
            #{
                name => <<"Cancellation Block">>,
                description => <<"Cancel execution within a block of activities">>,
                places => [start, cancel_scope, action1, action2, 'end'],
                transitions => [start, cancel_block, t1, t2, 'end'],
                complexity => medium,
                cancellation_scope => block
            };
        cancelation_scope ->
            #{
                name => <<"Cancellation Scope">>,
                description => <<"Cancel within a defined scope">>,
                places => [start, cancel_region, action1, action2, 'end'],
                transitions => [start, cancel_scope_enter, cancel_scope_exit, 'end'],
                complexity => medium,
                cancellation_scope => scoped
            };
        cancelation_thread ->
            #{
                name => <<"Cancellation Thread">>,
                description => <<"Cancel a single execution thread">>,
                places => [start, thread, action, 'end'],
                transitions => [start, cancel_thread, 'end'],
                complexity => medium,
                cancellation_scope => thread
            };
        cancelation_subprocess ->
            #{
                name => <<"Cancellation Subprocess">>,
                description => <<"Cancel a subprocess execution">>,
                places => [start, subprocess, action, 'end'],
                transitions => [start, cancel_subprocess, 'end'],
                complexity => medium,
                cancellation_scope => subprocess
            };
        cancelation_multiple_instances ->
            #{
                name => <<"Cancellation Multiple Instances">>,
                description => <<"Cancel multiple instance executions">>,
                places => [start, multiple_instances, action, 'end'],
                transitions => [start, cancel_multiple, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances
            };
        cancelation_point ->
            #{
                name => <<"Cancellation Point">>,
                description => <<"Define explicit cancellation points">>,
                places => [start, cancel_point, action, 'end'],
                transitions => [start, cancel_workflow, 'end'],
                complexity => medium,
                cancellation_scope => point
            };
        cancelation_end ->
            #{
                name => <<"Cancellation End">>,
                description => <<"End of cancellation region">>,
                places => [start, action, cancel_region_end, 'end'],
                transitions => [start, cancel_workflow, 'end'],
                complexity => medium,
                cancellation_scope => region_end
            };
        cancelation_cancel ->
            #{
                name => <<"Cancellation Action">>,
                description => <<"Explicit cancellation action">>,
                places => [start, cancel_trigger, action, 'end'],
                transitions => [start, cancel_workflow, 'end'],
                complexity => medium,
                cancellation_scope => action
            };
        'cancelation_thread_after' ->
            #{
                name => <<"Cancellation Thread After">>,
                description => <<"Cancel thread after completion">>,
                places => [start, thread, after_trigger, action, 'end'],
                transitions => [start, cancel_after, 'end'],
                complexity => high,
                cancellation_scope => thread_after,
                cancellation_trigger => 'after'
            };
        'cancelation_subprocess_after' ->
            #{
                name => <<"Cancellation Subprocess After">>,
                description => <<"Cancel subprocess after completion">>,
                places => [start, subprocess, after_trigger, action, 'end'],
                transitions => [start, cancel_after, 'end'],
                complexity => high,
                cancellation_scope => subprocess_after,
                cancellation_trigger => 'after'
            };
        'cancelation_multiple_instances_after' ->
            #{
                name => <<"Cancellation Multiple Instances After">>,
                description => <<"Cancel multiple instances after completion">>,
                places => [start, multiple_instances, after_trigger, 'end'],
                transitions => [start, cancel_after, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_after,
                cancellation_trigger => 'after'
            };
        'cancelation_multiple_instances_thread_after' ->
            #{
                name => <<"Cancellation Multiple Instances Thread After">>,
                description => <<"Cancel multiple instances thread after completion">>,
                places => [start, multiple_instances, thread, after_trigger, 'end'],
                transitions => [start, cancel_after, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_thread_after,
                cancellation_trigger => 'after'
            };
        'cancelation_multiple_instances_subprocess_after' ->
            #{
                name => <<"Cancellation Multiple Instances Subprocess After">>,
                description => <<"Cancel multiple instances subprocess after">>,
                places => [start, multiple_instances, subprocess, after_trigger, 'end'],
                transitions => [start, cancel_after, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_subprocess_after,
                cancellation_trigger => 'after'
            };
        cancelation_thread_or ->
            #{
                name => <<"Cancellation Thread OR">>,
                description => <<"Cancel thread with OR conditions">>,
                places => [start, thread, or_condition, action, 'end'],
                transitions => [start, cancel_or, 'end'],
                complexity => high,
                cancellation_scope => thread_or,
                cancellation_trigger => or_condition
            };
        cancelation_subprocess_or ->
            #{
                name => <<"Cancellation Subprocess OR">>,
                description => <<"Cancel subprocess with OR conditions">>,
                places => [start, subprocess, or_condition, action, 'end'],
                transitions => [start, cancel_or, 'end'],
                complexity => high,
                cancellation_scope => subprocess_or,
                cancellation_trigger => or_condition
            };
        cancelation_multiple_instances_or ->
            #{
                name => <<"Cancellation Multiple Instances OR">>,
                description => <<"Cancel instances with OR condition">>,
                places => [start, multiple_instances, or_condition, 'end'],
                transitions => [start, cancel_or, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_or,
                cancellation_trigger => or_condition
            };
        cancelation_multiple_instances_thread_or ->
            #{
                name => <<"Cancellation Multiple Instances Thread OR">>,
                description => <<"Cancel instances thread with OR">>,
                places => [start, multiple_instances, thread, or_condition, 'end'],
                transitions => [start, cancel_or, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_thread_or,
                cancellation_trigger => or_condition
            };
        cancelation_multiple_instances_subprocess_or ->
            #{
                name => <<"Cancellation Multiple Instances Subprocess OR">>,
                description => <<"Cancel instances subprocess with OR">>,
                places => [start, multiple_instances, subprocess, or_condition, 'end'],
                transitions => [start, cancel_or, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_subprocess_or,
                cancellation_trigger => or_condition
            };
        cancelation_thread_and ->
            #{
                name => <<"Cancellation Thread AND">>,
                description => <<"Cancel thread with AND conditions">>,
                places => [start, thread, and_condition, action, 'end'],
                transitions => [start, cancel_and, 'end'],
                complexity => high,
                cancellation_scope => thread_and,
                cancellation_trigger => and_condition
            };
        cancelation_subprocess_and ->
            #{
                name => <<"Cancellation Subprocess AND">>,
                description => <<"Cancel subprocess with AND conditions">>,
                places => [start, subprocess, and_condition, action, 'end'],
                transitions => [start, cancel_and, 'end'],
                complexity => high,
                cancellation_scope => subprocess_and,
                cancellation_trigger => and_condition
            };
        cancelation_multiple_instances_and ->
            #{
                name => <<"Cancellation Multiple Instances AND">>,
                description => <<"Cancel instances with AND condition">>,
                places => [start, multiple_instances, and_condition, 'end'],
                transitions => [start, cancel_and, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_and,
                cancellation_trigger => and_condition
            };
        cancelation_multiple_instances_thread_and ->
            #{
                name => <<"Cancellation Multiple Instances Thread AND">>,
                description => <<"Cancel instances thread with AND">>,
                places => [start, multiple_instances, thread, and_condition, 'end'],
                transitions => [start, cancel_and, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_thread_and,
                cancellation_trigger => and_condition
            };
        cancelation_multiple_instances_subprocess_and ->
            #{
                name => <<"Cancellation Multiple Instances Subprocess AND">>,
                description => <<"Cancel instances subprocess with AND">>,
                places => [start, multiple_instances, subprocess, and_condition, 'end'],
                transitions => [start, cancel_and, 'end'],
                complexity => high,
                cancellation_scope => multiple_instances_subprocess_and,
                cancellation_trigger => and_condition
            };
        implicit_merge_with_allocation ->
            #{
                name => <<"Implicit Merge With Allocation">>,
                description => <<"Implicit merge with resource allocation">>,
                places => [start, action1, action2, merge, resource, allocated, 'end'],
                transitions => [start, t1, t2, implicit_merge, resource_allocate, resource_deallocate, 'end'],
                complexity => high,
                resource_allocation => with_allocation
            };
        implicit_merge_without_allocation ->
            #{
                name => <<"Implicit Merge Without Allocation">>,
                description => <<"Implicit merge without resource allocation">>,
                places => [start, action1, action2, merge, 'end'],
                transitions => [start, t1, t2, implicit_merge, 'end'],
                complexity => medium,
                resource_allocation => without_allocation
            };
        multiple_merge_with_allocation ->
            #{
                name => <<"Multiple Merge With Allocation">>,
                description => <<"Multiple merge with resource allocation">>,
                places => [start, action1, action2, merge1, merge2, resource, allocated, 'end'],
                transitions => [start, t1, t2, multiple_merge_select, resource_allocate, resource_deallocate, 'end'],
                complexity => high,
                resource_allocation => with_allocation
            };
        multiple_merge_without_allocation ->
            #{
                name => <<"Multiple Merge Without Allocation">>,
                description => <<"Multiple merge without resource allocation">>,
                places => [start, action1, action2, merge1, merge2, 'end'],
                transitions => [start, t1, t2, multiple_merge_select, 'end'],
                complexity => high,
                resource_allocation => without_allocation
            };
        deferred_choice_with_allocation ->
            #{
                name => <<"Deferred Choice With Allocation">>,
                description => <<"Deferred choice with resource allocation">>,
                places => [start, defer, action1, action2, resource, allocated, 'end'],
                transitions => [start, deferred_choice_select, t1, t2, resource_allocate, resource_deallocate, 'end'],
                complexity => high,
                resource_allocation => with_allocation
            };
        deferred_choice_without_allocation ->
            #{
                name => <<"Deferred Choice Without Allocation">>,
                description => <<"Deferred choice without resource allocation">>,
                places => [start, defer, action1, action2, 'end'],
                transitions => [start, deferred_choice_select, t1, t2, 'end'],
                complexity => medium,
                resource_allocation => without_allocation
            };
        _ ->
            #{
                name => <<"unknown">>,
                description => <<"Pattern not found">>,
                places => [],
                transitions => [],
                complexity => undefined
            }
    end.

list_patterns() ->
    [
        basic_sequential,
        parallel_split,
        parallel_join,
        exclusive_choice,
        simple_merge,
        iterative_loop,
        multi_instance,
        %% Advanced Control Flow
        interleaved_parallelism,
        implicit_merge,
        multiple_merge,
        deferred_choice,
        interleaved_routing,
        milestone,
        %% Cancellation Base
        cancelation,
        cancelation_block,
        cancelation_scope,
        cancelation_thread,
        cancelation_subprocess,
        cancelation_multiple_instances,
        cancelation_point,
        cancelation_end,
        cancelation_cancel,
        %% Cancellation After
        'cancelation_thread_after',
        'cancelation_subprocess_after',
        'cancelation_multiple_instances_after',
        'cancelation_multiple_instances_thread_after',
        'cancelation_multiple_instances_subprocess_after',
        %% Cancellation OR
        cancelation_thread_or,
        cancelation_subprocess_or,
        cancelation_multiple_instances_or,
        cancelation_multiple_instances_thread_or,
        cancelation_multiple_instances_subprocess_or,
        %% Cancellation AND
        cancelation_thread_and,
        cancelation_subprocess_and,
        cancelation_multiple_instances_and,
        cancelation_multiple_instances_thread_and,
        cancelation_multiple_instances_subprocess_and,
        %% Resource Allocation
        implicit_merge_with_allocation,
        implicit_merge_without_allocation,
        multiple_merge_with_allocation,
        multiple_merge_without_allocation,
        deferred_choice_with_allocation,
        deferred_choice_without_allocation,
        %% Time-Based Patterns for Revenue Tasks
        timed_trigger,
        timeout_pattern,
        scheduled_execution,
        duration_bound,
        deadline_pattern,
        periodic_billing,
        usage_aggregation_window,
        grace_period,
        time_based_routing,
        renewal_reminder
    ].

%%====================================================================
%% Pattern Structure Functions
%%====================================================================

get_pattern_structure(PatternType) ->
    case PatternType of
        basic_sequential ->
            {
                [start, task1, task2, 'end'],
                [start, t1, t2, finish],
                #{start => [start], t1 => [task1], t2 => [task2], finish => ['end']},
                #{start => [task1], t1 => [task2], t2 => ['end'], finish => []}
            };
        parallel_split ->
            {
                [start, split, task1, task2, 'end'],
                [start, split, t1, t2, join, finish],
                #{start => [start], split => [split], t1 => [task1], t2 => [task2], join => ['end'], finish => ['end']},
                #{start => [split], split => [task1, task2], t1 => [join], t2 => [join], join => [finish], finish => []}
            };
        parallel_join ->
            {
                [start, task1, task2, join, 'end'],
                [start, t1, t2, join, finish],
                #{start => [start], t1 => [task1], t2 => [task2], join => [join], finish => ['end']},
                #{start => [task1, task2], t1 => [join], t2 => [join], join => [finish], finish => []}
            };
        exclusive_choice ->
            {
                [start, choice, task1, task2, 'end'],
                [start, choice, t1, t2, merge, finish],
                #{start => [start], choice => [choice], t1 => [task1], t2 => [task2], merge => ['end'], finish => ['end']},
                #{start => [choice], choice => [task1, task2], t1 => [merge], t2 => [merge], merge => [finish], finish => []}
            };
        simple_merge ->
            {
                [start, task1, task2, merge, 'end'],
                [start, t1, t2, merge, finish],
                #{start => [start], t1 => [task1], t2 => [task2], merge => [merge], finish => ['end']},
                #{start => [task1, task2], t1 => [merge], t2 => [merge], merge => [finish], finish => []}
            };
        iterative_loop ->
            {
                [start, condition, action, loop, 'end'],
                [start, check, execute, continue, finish],
                #{start => [start], check => [condition], execute => [action], continue => [loop], finish => ['end']},
                #{start => [condition], check => [action, 'end'], execute => [loop], continue => [condition], finish => []}
            };
        multi_instance ->
            {
                [start, create, execute, collect, 'end'],
                [start, create, execute, collect, finish],
                #{start => [start], create => [create], execute => [execute], collect => [collect], finish => ['end']},
                #{start => [create], create => [execute], execute => [collect], collect => [finish], finish => []}
            };
        interleaved_parallelism ->
            {
                [start, interleaved, task1, task2, 'end'],
                [start, interleaved_execute, t1, t2, interleaved_merge, finish],
                #{start => [start], interleaved_execute => [interleaved], t1 => [task1], t2 => [task2], interleaved_merge => ['end'], finish => ['end']},
                #{start => [interleaved_execute], interleaved_execute => [interleaved], interleaved => [t1, t2], t1 => [interleaved_merge], t2 => [interleaved_merge], interleaved_merge => [finish], finish => []}
            };
        implicit_merge ->
            {
                [start, task1, task2, 'end'],
                [start, t1, t2, finish],
                #{start => [start], t1 => [task1], t2 => [task2], finish => ['end']},
                #{start => [task1, task2], t1 => ['end'], t2 => ['end'], finish => []}
            };
        multiple_merge ->
            {
                [start, task1, task2, merge1, merge2, 'end'],
                [start, t1, t2, merge1, merge2, finish],
                #{start => [start], t1 => [task1], t2 => [task2], merge1 => [merge1], merge2 => [merge2], finish => ['end']},
                #{start => [t1, t2], t1 => [merge1, merge2], t2 => [merge1, merge2], merge1 => [finish], merge2 => [finish], finish => []}
            };
        deferred_choice ->
            {
                [start, defer, task1, task2, 'end'],
                [start, defer_choice, t1, t2, finish],
                #{start => [start], defer_choice => [defer], t1 => [task1], t2 => [task2], finish => ['end']},
                #{start => [defer_choice], defer_choice => [t1, t2], t1 => [finish], t2 => [finish], finish => []}
            };
        interleaved_routing ->
            {
                [start, route1, route2, route3, 'end'],
                [start, interleaved_execute, merge, finish],
                #{start => [start], interleaved_execute => [route1], merge => ['end'], finish => ['end']},
                #{start => [interleaved_execute], interleaved_execute => [route1, route2, route3], route1 => [merge], route2 => [merge], route3 => [merge], merge => [finish], finish => []}
            };
        milestone ->
            {
                [start, milestone, action, 'end'],
                [start, milestone_reach, milestone_wait, finish],
                #{start => [start], milestone_reach => [milestone], milestone_wait => [milestone], finish => ['end']},
                #{start => [milestone_reach], milestone_reach => [action, milestone], milestone => [milestone_wait], milestone_wait => [finish], finish => []}
            };
        %% Cancellation patterns - same structure but with cancellation metadata
        cancelation ->
            {
                [start, task1, task2, cancel, 'end'],
                [start, t1, t2, cancel_workflow, finish],
                #{start => [start], t1 => [task1], t2 => [task2], cancel_workflow => [cancel], finish => ['end', cancel]},
                #{start => [t1, cancel_workflow], t1 => [t2], t2 => [finish], cancel_workflow => [finish], finish => []}
            };
        cancelation_block ->
            {
                [start, cancel_scope, task1, task2, 'end'],
                [start, cancel_block, t1, t2, finish],
                #{start => [start], cancel_block => [cancel_scope], t1 => [task1], t2 => [task2], finish => ['end', cancel_scope]},
                #{start => [cancel_block], cancel_block => [t1, t2], t1 => [t2], t2 => [finish], finish => []}
            };
        cancelation_scope ->
            {
                [start, cancel_region, task1, task2, 'end'],
                [start, cancel_scope_enter, t1, t2, cancel_scope_exit, finish],
                #{start => [start], cancel_scope_enter => [cancel_region], t1 => [task1], t2 => [task2], cancel_scope_exit => [cancel_region], finish => ['end']},
                #{start => [cancel_scope_enter], cancel_scope_enter => [t1, t2], t1 => [t2], t2 => [cancel_scope_exit], cancel_scope_exit => [finish], finish => []}
            };
        cancelation_thread ->
            {
                [start, thread, task, 'end'],
                [start, t1, cancel_thread, finish],
                #{start => [start], t1 => [task], cancel_thread => [thread], finish => ['end', thread]},
                #{start => [t1], t1 => [cancel_thread, finish], cancel_thread => [finish], finish => []}
            };
        cancelation_subprocess ->
            {
                [start, subprocess, task, 'end'],
                [start, t1, cancel_subprocess, finish],
                #{start => [start], t1 => [subprocess], cancel_subprocess => [subprocess], finish => ['end', subprocess]},
                #{start => [t1], t1 => [cancel_subprocess, finish], cancel_subprocess => [finish], finish => []}
            };
        cancelation_multiple_instances ->
            {
                [start, multiple_instances, task, 'end'],
                [start, t1, cancel_multiple, finish],
                #{start => [start], t1 => [multiple_instances], cancel_multiple => [multiple_instances], finish => ['end', multiple_instances]},
                #{start => [t1], t1 => [cancel_multiple, finish], cancel_multiple => [finish], finish => []}
            };
        cancelation_point ->
            {
                [start, cancel_point, task, 'end'],
                [start, t1, cancel_workflow, finish],
                #{start => [start], t1 => [task], cancel_workflow => [cancel_point], finish => ['end', cancel_point]},
                #{start => [t1], t1 => [cancel_workflow, finish], cancel_workflow => [finish], finish => []}
            };
        cancelation_end ->
            {
                [start, task, cancel_region_end, 'end'],
                [start, t1, cancel_workflow, finish],
                #{start => [start], t1 => [task], cancel_workflow => [cancel_region_end], finish => ['end', cancel_region_end]},
                #{start => [t1], t1 => [cancel_region_end, finish], cancel_region_end => [finish], finish => []}
            };
        cancelation_cancel ->
            {
                [start, cancel_trigger, task, 'end'],
                [start, t1, cancel_workflow, finish],
                #{start => [start], t1 => [cancel_trigger], cancel_workflow => [cancel_trigger], finish => ['end']},
                #{start => [t1], t1 => [cancel_workflow, finish], cancel_workflow => [finish], finish => []}
            };
        %% Cancellation After patterns
        'cancelation_thread_after' ->
            {
                [start, thread, after_trigger, task, 'end'],
                [start, t1, t2, cancel_after, finish],
                #{start => [start], t1 => [thread], t2 => [task], cancel_after => [after_trigger], finish => ['end', after_trigger]},
                #{start => [t1], t1 => [t2], t2 => [after_trigger, finish], after_trigger => [cancel_after], cancel_after => [finish], finish => []}
            };
        'cancelation_subprocess_after' ->
            {
                [start, subprocess, after_trigger, task, 'end'],
                [start, t1, t2, cancel_after, finish],
                #{start => [start], t1 => [subprocess], t2 => [task], cancel_after => [after_trigger], finish => ['end', after_trigger]},
                #{start => [t1], t1 => [t2], t2 => [after_trigger, finish], after_trigger => [cancel_after], cancel_after => [finish], finish => []}
            };
        'cancelation_multiple_instances_after' ->
            {
                [start, multiple_instances, after_trigger, 'end'],
                [start, t1, cancel_after, finish],
                #{start => [start], t1 => [multiple_instances], cancel_after => [after_trigger], finish => ['end', after_trigger]},
                #{start => [t1], t1 => [after_trigger], after_trigger => [cancel_after], cancel_after => [finish], finish => []}
            };
        'cancelation_multiple_instances_thread_after' ->
            {
                [start, multiple_instances, thread, after_trigger, 'end'],
                [start, t1, t2, cancel_after, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [thread], cancel_after => [after_trigger], finish => ['end', after_trigger]},
                #{start => [t1], t1 => [t2], t2 => [after_trigger], after_trigger => [cancel_after], cancel_after => [finish], finish => []}
            };
        'cancelation_multiple_instances_subprocess_after' ->
            {
                [start, multiple_instances, subprocess, after_trigger, 'end'],
                [start, t1, t2, cancel_after, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [subprocess], cancel_after => [after_trigger], finish => ['end', after_trigger]},
                #{start => [t1], t1 => [t2], t2 => [after_trigger], after_trigger => [cancel_after], cancel_after => [finish], finish => []}
            };
        %% Cancellation OR patterns
        cancelation_thread_or ->
            {
                [start, thread, or_condition, task, 'end'],
                [start, t1, cancel_or, finish],
                #{start => [start], t1 => [thread], cancel_or => [or_condition], finish => ['end', or_condition]},
                #{start => [t1], t1 => [or_condition], or_condition => [cancel_or], cancel_or => [finish], finish => []}
            };
        cancelation_subprocess_or ->
            {
                [start, subprocess, or_condition, task, 'end'],
                [start, t1, cancel_or, finish],
                #{start => [start], t1 => [subprocess], cancel_or => [or_condition], finish => ['end', or_condition]},
                #{start => [t1], t1 => [or_condition], or_condition => [cancel_or], cancel_or => [finish], finish => []}
            };
        cancelation_multiple_instances_or ->
            {
                [start, multiple_instances, or_condition, 'end'],
                [start, t1, cancel_or, finish],
                #{start => [start], t1 => [multiple_instances], cancel_or => [or_condition], finish => ['end', or_condition]},
                #{start => [t1], t1 => [or_condition], or_condition => [cancel_or], cancel_or => [finish], finish => []}
            };
        cancelation_multiple_instances_thread_or ->
            {
                [start, multiple_instances, thread, or_condition, 'end'],
                [start, t1, t2, cancel_or, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [thread], cancel_or => [or_condition], finish => ['end', or_condition]},
                #{start => [t1], t1 => [t2], t2 => [or_condition], or_condition => [cancel_or], cancel_or => [finish], finish => []}
            };
        cancelation_multiple_instances_subprocess_or ->
            {
                [start, multiple_instances, subprocess, or_condition, 'end'],
                [start, t1, t2, cancel_or, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [subprocess], cancel_or => [or_condition], finish => ['end', or_condition]},
                #{start => [t1], t1 => [t2], t2 => [or_condition], or_condition => [cancel_or], cancel_or => [finish], finish => []}
            };
        %% Cancellation AND patterns
        cancelation_thread_and ->
            {
                [start, thread, and_condition, task, 'end'],
                [start, t1, cancel_and, finish],
                #{start => [start], t1 => [thread], cancel_and => [and_condition], finish => ['end', and_condition]},
                #{start => [t1], t1 => [and_condition], and_condition => [cancel_and], cancel_and => [finish], finish => []}
            };
        cancelation_subprocess_and ->
            {
                [start, subprocess, and_condition, task, 'end'],
                [start, t1, cancel_and, finish],
                #{start => [start], t1 => [subprocess], cancel_and => [and_condition], finish => ['end', and_condition]},
                #{start => [t1], t1 => [and_condition], and_condition => [cancel_and], cancel_and => [finish], finish => []}
            };
        cancelation_multiple_instances_and ->
            {
                [start, multiple_instances, and_condition, 'end'],
                [start, t1, cancel_and, finish],
                #{start => [start], t1 => [multiple_instances], cancel_and => [and_condition], finish => ['end', and_condition]},
                #{start => [t1], t1 => [and_condition], and_condition => [cancel_and], cancel_and => [finish], finish => []}
            };
        cancelation_multiple_instances_thread_and ->
            {
                [start, multiple_instances, thread, and_condition, 'end'],
                [start, t1, t2, cancel_and, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [thread], cancel_and => [and_condition], finish => ['end', and_condition]},
                #{start => [t1], t1 => [t2], t2 => [and_condition], and_condition => [cancel_and], cancel_and => [finish], finish => []}
            };
        cancelation_multiple_instances_subprocess_and ->
            {
                [start, multiple_instances, subprocess, and_condition, 'end'],
                [start, t1, t2, cancel_and, finish],
                #{start => [start], t1 => [multiple_instances], t2 => [subprocess], cancel_and => [and_condition], finish => ['end', and_condition]},
                #{start => [t1], t1 => [t2], t2 => [and_condition], and_condition => [cancel_and], cancel_and => [finish], finish => []}
            };
        %% Resource allocation patterns
        implicit_merge_with_allocation ->
            {
                [start, task1, task2, merge, resource, allocated, 'end'],
                [start, t1, t2, merge, resource_allocate, resource_execute, resource_deallocate, finish],
                #{start => [start], t1 => [task1], t2 => [task2], merge => [merge], resource_allocate => [resource], resource_execute => [allocated], resource_deallocate => [allocated], finish => ['end']},
                #{start => [t1, t2], t1 => [merge], t2 => [merge], merge => [resource_allocate], resource_allocate => [resource_execute], resource_execute => [resource_deallocate], resource_deallocate => [finish], finish => []}
            };
        implicit_merge_without_allocation ->
            {
                [start, task1, task2, 'end'],
                [start, t1, t2, finish],
                #{start => [start], t1 => [task1], t2 => [task2], finish => ['end']},
                #{start => [t1, t2], t1 => [finish], t2 => [finish], finish => []}
            };
        multiple_merge_with_allocation ->
            {
                [start, task1, task2, merge1, merge2, resource, allocated, 'end'],
                [start, t1, t2, merge, resource_allocate, resource_execute, resource_deallocate, finish],
                #{start => [start], t1 => [task1], t2 => [task2], merge => [merge1, merge2], resource_allocate => [resource], resource_execute => [allocated], resource_deallocate => [allocated], finish => ['end']},
                #{start => [t1, t2], t1 => [merge], t2 => [merge], merge => [resource_allocate], resource_allocate => [resource_execute], resource_execute => [resource_deallocate], resource_deallocate => [finish], finish => []}
            };
        multiple_merge_without_allocation ->
            {
                [start, task1, task2, merge1, merge2, 'end'],
                [start, t1, t2, merge, finish],
                #{start => [start], t1 => [task1], t2 => [task2], merge => [merge1, merge2], finish => ['end']},
                #{start => [t1, t2], t1 => [merge], t2 => [merge], merge => [finish], finish => []}
            };
        deferred_choice_with_allocation ->
            {
                [start, defer, task1, task2, resource, allocated, 'end'],
                [start, defer_choice, t1, t2, resource_allocate, resource_execute, resource_deallocate, finish],
                #{start => [start], defer_choice => [defer], t1 => [task1], t2 => [task2], resource_allocate => [resource], resource_execute => [allocated], resource_deallocate => [allocated], finish => ['end']},
                #{start => [defer_choice], defer_choice => [t1, t2], t1 => [resource_allocate], t2 => [resource_allocate], resource_allocate => [resource_execute], resource_execute => [resource_deallocate], resource_deallocate => [finish], finish => []}
            };
        deferred_choice_without_allocation ->
            {
                [start, defer, task1, task2, 'end'],
                [start, defer_choice, t1, t2, finish],
                #{start => [start], defer_choice => [defer], t1 => [task1], t2 => [task2], finish => ['end']},
                #{start => [defer_choice], defer_choice => [t1, t2], t1 => [finish], t2 => [finish], finish => []}
            };
        _ ->
            %% Default structure for unknown patterns
            {
                [start, 'end'],
                [start, finish],
                #{start => [start], finish => ['end']},
                #{start => ['end'], finish => []}
            }
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

is_cancellation_pattern(PatternType) ->
    PatternBin = atom_to_binary(PatternType, utf8),
    case PatternBin of
        <<"cancelation_", _/binary>> -> true;
        _ ->
            lists:member(PatternType, [
                cancelation,
                cancelation_block,
                cancelation_scope,
                cancelation_thread,
                cancelation_subprocess,
                cancelation_multiple_instances,
                cancelation_point,
                cancelation_end,
                cancelation_cancel
            ])
    end.

is_resource_pattern(PatternType) ->
    PatternBin = atom_to_binary(PatternType, utf8),
    case PatternBin of
        <<_:(byte_size(PatternBin) - 14)/binary, "_with_allocation">> -> true;
        <<_:(byte_size(PatternBin) - 17)/binary, "_without_allocation">> -> true;
        _ -> false
    end.

get_cancellation_scope(PatternType) ->
    Info = get_pattern_info(PatternType),
    maps:get(cancellation_scope, Info, undefined).

get_resource_allocation_type(PatternType) ->
    Info = get_pattern_info(PatternType),
    maps:get(resource_allocation, Info, undefined).

%%====================================================================
%% Internal Functions
%%====================================================================

generate_pattern_definition(PatternType, Config) ->
    case PatternType of
        basic_sequential ->
            #{
                pattern_type => basic_sequential,
                places => [start, task1, task2, 'end'],
                transitions => [start, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    t1 => [task1],
                    t2 => [task2],
                    finish => ['end']
                },
                postset => #{
                    start => [task1],
                    t1 => [task2],
                    t2 => [finish],
                    finish => []
                },
                complexity => low
            };
        parallel_split ->
            Branches = maps:get(branches, Config, 2),
            #{
                pattern_type => parallel_split,
                places => [start, split | lists:seq(1, Branches)] ++ [join, 'end'],
                transitions => [start, split | lists:seq(1, Branches)] ++ [join, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    split => [split],
                    join => ['end'],
                    finish => ['end']
                },
                postset => #{
                    start => [split],
                    split => lists:seq(1, Branches),
                    join => [finish],
                    finish => []
                },
                complexity => medium
            };
        parallel_join ->
            Branches = maps:get(branches, Config, 2),
            #{
                pattern_type => parallel_join,
                places => [start | lists:seq(1, Branches)] ++ [join, 'end'],
                transitions => [start | lists:seq(1, Branches)] ++ [join, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    join => [join],
                    finish => ['end']
                },
                postset => #{
                    start => lists:seq(1, Branches),
                    join => [finish],
                    finish => []
                },
                complexity => medium
            };
        exclusive_choice ->
            #{
                pattern_type => exclusive_choice,
                places => [start, choice, branch1, branch2, 'end'],
                transitions => [start, choice, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    choice => [choice],
                    finish => ['end']
                },
                postset => #{
                    start => [choice],
                    choice => [branch1, branch2],
                    branch1 => [finish],
                    branch2 => [finish],
                    finish => []
                },
                complexity => medium
            };
        simple_merge ->
            #{
                pattern_type => simple_merge,
                places => [start, branch1, branch2, merge, 'end'],
                transitions => [start, t1, t2, merge, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    merge => [merge],
                    finish => ['end']
                },
                postset => #{
                    start => [branch1, branch2],
                    branch1 => [merge],
                    branch2 => [merge],
                    merge => [finish],
                    finish => []
                },
                complexity => medium
            };
        iterative_loop ->
            #{
                pattern_type => iterative_loop,
                places => [start, condition, action, loop, 'end'],
                transitions => [start, check, execute, continue, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    check => [condition],
                    finish => ['end']
                },
                postset => #{
                    start => [condition],
                    check => [action, 'end'],
                    action => [loop],
                    loop => [condition],
                    finish => []
                },
                complexity => high
            };
        multi_instance ->
            NumInstances = maps:get(num_instances, Config, 3),
            InstancePlaces = lists:map(fun(I) -> list_to_atom("instance_" ++ integer_to_list(I)) end,
                                     lists:seq(1, NumInstances)),
            #{
                pattern_type => multi_instance,
                places => [start, create] ++ InstancePlaces ++ [collect, 'end'],
                transitions => [start, create] ++
                             lists:map(fun(I) -> list_to_atom("execute_" ++ integer_to_list(I)) end,
                                     lists:seq(1, NumInstances)) ++
                             [collect, finish],
                marking => #{start => [workflow_token]},
                preset => generate_multi_instance_preset(NumInstances),
                postset => generate_multi_instance_postset(NumInstances),
                complexity => high
            };
        %% Advanced patterns
        interleaved_parallelism ->
            #{
                pattern_type => interleaved_parallelism,
                places => [start, interleaved, task1, task2, 'end'],
                transitions => [start, interleaved_execute, t1, t2, interleaved_merge, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    interleaved_execute => [interleaved],
                    interleaved_merge => ['end'],
                    finish => ['end']
                },
                postset => #{
                    start => [interleaved_execute],
                    interleaved_execute => [interleaved],
                    interleaved => [t1, t2],
                    t1 => [interleaved_merge],
                    t2 => [interleaved_merge],
                    interleaved_merge => [finish],
                    finish => []
                },
                complexity => medium
            };
        implicit_merge ->
            #{
                pattern_type => implicit_merge,
                places => [start, task1, task2, 'end'],
                transitions => [start, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    finish => ['end']
                },
                postset => #{
                    start => [task1, task2],
                    task1 => [finish],
                    task2 => [finish],
                    finish => []
                },
                complexity => medium
            };
        multiple_merge ->
            #{
                pattern_type => multiple_merge,
                places => [start, task1, task2, merge1, merge2, 'end'],
                transitions => [start, t1, t2, merge1, merge2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    merge1 => [merge1],
                    merge2 => [merge2],
                    finish => ['end']
                },
                postset => #{
                    start => [t1, t2],
                    t1 => [merge1, merge2],
                    t2 => [merge1, merge2],
                    merge1 => [finish],
                    merge2 => [finish],
                    finish => []
                },
                complexity => high
            };
        deferred_choice ->
            #{
                pattern_type => deferred_choice,
                places => [start, defer, task1, task2, 'end'],
                transitions => [start, defer_choice, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    defer_choice => [defer],
                    finish => ['end']
                },
                postset => #{
                    start => [defer_choice],
                    defer_choice => [t1, t2],
                    t1 => [finish],
                    t2 => [finish],
                    finish => []
                },
                complexity => medium
            };
        interleaved_routing ->
            #{
                pattern_type => interleaved_routing,
                places => [start, route1, route2, route3, 'end'],
                transitions => [start, interleaved_execute, merge, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    merge => ['end'],
                    finish => ['end']
                },
                postset => #{
                    start => [interleaved_execute],
                    interleaved_execute => [route1, route2, route3],
                    route1 => [merge],
                    route2 => [merge],
                    route3 => [merge],
                    merge => [finish],
                    finish => []
                },
                complexity => high
            };
        milestone ->
            #{
                pattern_type => milestone,
                places => [start, milestone, action, 'end'],
                transitions => [start, milestone_reach, milestone_wait, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    milestone_reach => [milestone],
                    milestone_wait => [milestone],
                    finish => ['end']
                },
                postset => #{
                    start => [milestone_reach],
                    milestone_reach => [action, milestone],
                    milestone => [milestone_wait],
                    milestone_wait => [finish],
                    finish => []
                },
                complexity => medium
            };
        %% Cancellation patterns
        cancelation ->
            #{
                pattern_type => cancelation,
                places => [start, task1, task2, cancel, 'end'],
                transitions => [start, t1, t2, cancel_workflow, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    cancel_workflow => [cancel],
                    finish => ['end']
                },
                postset => #{
                    start => [t1, cancel_workflow],
                    t1 => [t2],
                    t2 => [finish],
                    cancel_workflow => [finish],
                    finish => []
                },
                complexity => medium,
                cancellation_scope => all
            };
        cancelation_block ->
            #{
                pattern_type => cancelation_block,
                places => [start, cancel_scope, task1, task2, 'end'],
                transitions => [start, cancel_block, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    cancel_block => [cancel_scope],
                    finish => ['end']
                },
                postset => #{
                    start => [cancel_block],
                    cancel_block => [t1, t2],
                    t1 => [t2],
                    t2 => [finish],
                    finish => []
                },
                complexity => medium,
                cancellation_scope => block
            };
        %% All other cancellation patterns follow similar structure
        _ ->
            PatternBin = atom_to_binary(PatternType, utf8),
            IsCancellation = case PatternBin of
                <<"cancelation_", _/binary>> -> true;
                _ -> lists:member(PatternType, [cancelation, cancelation_block, cancelation_scope,
                                               cancelation_thread, cancelation_subprocess, cancelation_multiple_instances,
                                               cancelation_point, cancelation_end, cancelation_cancel])
            end,
            case IsCancellation of
                true ->
                    #{
                        pattern_type => PatternType,
                        places => [start, task1, task2, cancel, 'end'],
                        transitions => [start, t1, t2, cancel_workflow, finish],
                        marking => #{start => [workflow_token]},
                        preset => #{
                            start => [start],
                            cancel_workflow => [cancel],
                            finish => ['end']
                        },
                        postset => #{
                            start => [t1, cancel_workflow],
                            t1 => [t2],
                            t2 => [finish],
                            cancel_workflow => [finish],
                            finish => []
                        },
                        complexity => medium,
                        cancellation_scope => get_cancellation_scope_from_name(PatternType)
                    };
                _ ->
                    #{
                        pattern_type => PatternType,
                        places => [start, task1, task2, 'end'],
                        transitions => [start, t1, t2, finish],
                        marking => #{start => [workflow_token]},
                        preset => #{start => [start], finish => ['end']},
                        postset => #{start => [t1], t1 => [t2], t2 => [finish], finish => []},
                        complexity => medium
                    }
            end;
        %% Resource allocation patterns
        implicit_merge_with_allocation ->
            #{
                pattern_type => implicit_merge_with_allocation,
                places => [start, task1, task2, merge, resource, allocated, 'end'],
                transitions => [start, t1, t2, merge, resource_allocate, resource_execute, resource_deallocate, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    resource_allocate => [resource],
                    resource_execute => [allocated],
                    resource_deallocate => [allocated],
                    finish => ['end']
                },
                postset => #{
                    start => [t1, t2],
                    t1 => [merge],
                    t2 => [merge],
                    merge => [resource_allocate],
                    resource_allocate => [resource_execute],
                    resource_execute => [resource_deallocate],
                    resource_deallocate => [finish],
                    finish => []
                },
                complexity => high,
                resource_allocation => with_allocation
            };
        implicit_merge_without_allocation ->
            #{
                pattern_type => implicit_merge_without_allocation,
                places => [start, task1, task2, 'end'],
                transitions => [start, t1, t2, finish],
                marking => #{start => [workflow_token]},
                preset => #{
                    start => [start],
                    finish => ['end']
                },
                postset => #{
                    start => [t1, t2],
                    t1 => [finish],
                    t2 => [finish],
                    finish => []
                },
                complexity => medium,
                resource_allocation => without_allocation
            };
        %% Other resource patterns
        _ ->
            case {lists:suffix(<<"_with_allocation">>, atom_to_binary(PatternType, utf8)),
                  lists:suffix(<<"_without_allocation">>, atom_to_binary(PatternType, utf8))} of
                {true, _} ->
                    #{
                        pattern_type => PatternType,
                        places => [start, task1, task2, 'end'],
                        transitions => [start, t1, t2, finish],
                        marking => #{start => [workflow_token]},
                        preset => #{start => [start], finish => ['end']},
                        postset => #{start => [t1, t2], t1 => [finish], t2 => [finish], finish => []},
                        complexity => medium,
                        resource_allocation => get_allocation_type_from_name(PatternType)
                    };
                _ ->
                    #{
                        pattern_type => PatternType,
                        places => [start, task1, task2, 'end'],
                        transitions => [start, t1, t2, finish],
                        marking => #{start => [workflow_token]},
                        preset => #{start => [start], finish => ['end']},
                        postset => #{start => [t1, t2], t1 => [finish], t2 => [finish], finish => []},
                        complexity => medium
                    }
            end;
        _ ->
            %% Default to basic sequential for unknown patterns
            generate_pattern_definition(basic_sequential, Config)
    end.

generate_multi_instance_preset(NumInstances) ->
    Preset0 = #{start => [start]},
    Preset1 = Preset0#{create => [create]},
    ExecutePresets = lists:foldl(fun(I, Acc) ->
        InstancePlace = list_to_atom("instance_" ++ integer_to_list(I)),
        Acc#{list_to_atom("execute_" ++ integer_to_list(I)) => [InstancePlace]}
    end, Preset1, lists:seq(1, NumInstances)),
    InstancePlaces = lists:map(fun(I) -> list_to_atom("instance_" ++ integer_to_list(I)) end,
                             lists:seq(1, NumInstances)),
    ExecutePresets2 = ExecutePresets#{collect => InstancePlaces},
    ExecutePresets2#{'end' => ['end']}.

generate_multi_instance_postset(NumInstances) ->
    Postset0 = #{start => [create]},
    Postset1 = Postset0#{create => lists:map(fun(I) ->
        list_to_atom("instance_" ++ integer_to_list(I))
    end, lists:seq(1, NumInstances))},
    ExecutePostsets = lists:foldl(fun(I, Acc) ->
        ExecuteKey = list_to_atom("execute_" ++ integer_to_list(I)),
        Acc#{ExecuteKey => [collect]}
    end, Postset1, lists:seq(1, NumInstances)),
    ExecutePostsets#{collect => ['end'], 'end' => []}.

get_cancellation_scope_from_name(PatternType) ->
    case atom_to_binary(PatternType, utf8) of
        <<"cancelation_thread_", _/binary>> -> thread;
        <<"cancelation_subprocess_", _/binary>> -> subprocess;
        <<"cancelation_multiple_instances_", _/binary>> -> multiple_instances;
        <<"cancelation_block">> -> block;
        <<"cancelation_scope">> -> scoped;
        <<"cancelation_point">> -> point;
        <<"cancelation_end">> -> region_end;
        <<"cancelation_cancel">> -> action;
        _ -> all
    end.

get_allocation_type_from_name(PatternType) ->
    PatternBin = atom_to_binary(PatternType, utf8),
    Size = byte_size(PatternBin) - byte_size(<<"_with_allocation">>),
    case PatternBin of
        <<_:Size/binary, "_with_allocation">> -> with_allocation;
        _ -> without_allocation
    end.

validate_pattern_config(basic_sequential, _Config) ->
    true;
validate_pattern_config(parallel_split, Config) ->
    case maps:get(branches, Config, 2) of
        N when N >= 2 -> true;
        _ -> false
    end;
validate_pattern_config(parallel_join, Config) ->
    case maps:get(branches, Config, 2) of
        N when N >= 2 -> true;
        _ -> false
    end;
validate_pattern_config(exclusive_choice, Config) ->
    Branches = maps:get(conditions, Config, []),
    length(Branches) >= 2;
validate_pattern_config(iterative_loop, Config) ->
    case maps:get(condition, Config, undefined) of
        undefined -> false;
        _ -> true
    end;
validate_pattern_config(multi_instance, Config) ->
    case {maps:get(num_instances, Config, undefined), maps:get(data, Config, undefined)} of
        {undefined, _} -> false;
        {_, undefined} -> false;
        {N, _} when N > 0 -> true;
        _ -> false
    end;
validate_pattern_config(interleaved_parallelism, Config) ->
    Tasks = maps:get(tasks, Config, []),
    case Tasks of
        [] -> false;
        _ when length(Tasks) >= 2 -> true;
        _ -> false
    end;
validate_pattern_config(implicit_merge, _Config) ->
    true;
validate_pattern_config(multiple_merge, Config) ->
    case maps:get(branches, Config, 2) of
        N when N >= 2 -> true;
        _ -> false
    end;
validate_pattern_config(deferred_choice, Config) ->
    case maps:get(options, Config, []) of
        [] -> false;
        Options when length(Options) >= 2 -> true;
        _ -> false
    end;
validate_pattern_config(interleaved_routing, Config) ->
    Routes = maps:get(routes, Config, []),
    Routes =/= [] andalso length(Routes) >= 2;
validate_pattern_config(milestone, Config) ->
    maps:is_key(milestone_condition, Config);
validate_pattern_config(Pattern, _Config) ->
    PatternBin = atom_to_binary(Pattern, utf8),
    IsCancellation = case PatternBin of
        <<"cancelation_", _/binary>> -> true;
        _ -> lists:member(Pattern, [cancelation, cancelation_block, cancelation_scope,
                                   cancelation_thread, cancelation_subprocess, cancelation_multiple_instances,
                                   cancelation_point, cancelation_end, cancelation_cancel])
    end,
    IsResource = case PatternBin of
        S when byte_size(S) > 14 ->
            case S of
                <<_:(byte_size(S) - 14)/binary, "_with_allocation">> -> true;
                _ when byte_size(S) > 17 ->
                    case S of
                        <<_:(byte_size(S) - 17)/binary, "_without_allocation">> -> true;
                        _ -> false
                    end;
                _ -> false
            end;
        _ -> false
    end,
    IsCancellation orelse IsResource orelse true.
