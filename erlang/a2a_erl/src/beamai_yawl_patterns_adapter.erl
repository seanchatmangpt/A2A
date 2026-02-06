%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Patterns Adapter
%%%
%%% Adapts YAWL workflow patterns (as defined in yawl_patterns.erl)
%%% to BeamAI process steps. Provides bidirectional mapping between:
%%%
%%% - Sequence pattern      -> BeamAI sequential process steps
%%% - Parallel split/join   -> BeamAI parallel execution
%%% - Exclusive choice      -> BeamAI conditional branching
%%% - Deferred choice       -> BeamAI event-driven selection
%%% - Multiple instance     -> BeamAI dynamic spawning
%%% - Cancellation patterns -> BeamAI interrupt handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_patterns_adapter).

-include("../include/yawl_types.hrl").

%% API exports
-export([
    adapt_pattern/1,
    to_process_step/1,
    from_process_result/1,
    validate_pattern/1
]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Adapt a YAWL pattern type to a BeamAI process definition.
%% Takes a YAWL pattern type atom or a full #yawl_pattern{} record
%% and returns a BeamAI-compatible process step structure.
-spec adapt_pattern(atom() | #yawl_pattern{}) -> {ok, map()} | {error, term()}.
adapt_pattern(PatternType) when is_atom(PatternType) ->
    case pattern_to_beamai(PatternType) of
        {error, _} = Err -> Err;
        ProcessDef -> {ok, ProcessDef}
    end;
adapt_pattern(#yawl_pattern{type = PatternType} = Pattern) ->
    case pattern_to_beamai(PatternType) of
        {error, _} = Err ->
            Err;
        ProcessDef ->
            %% Enrich with pattern metadata
            Enriched = ProcessDef#{
                places => Pattern#yawl_pattern.places,
                transitions => Pattern#yawl_pattern.transitions,
                preset => Pattern#yawl_pattern.preset,
                postset => Pattern#yawl_pattern.postset,
                complexity => Pattern#yawl_pattern.complexity,
                yawl_metadata => Pattern#yawl_pattern.metadata
            },
            {ok, Enriched}
    end;
adapt_pattern(_) ->
    {error, invalid_pattern_input}.

%% @doc Convert a YAWL workflow config to a list of BeamAI process steps.
%% Takes a workflow definition map and returns ordered BeamAI steps.
-spec to_process_step(map()) -> {ok, [map()]} | {error, term()}.
to_process_step(#{pattern_type := PatternType} = WorkflowDef) ->
    Tasks = maps:get(tasks, WorkflowDef, []),
    case adapt_pattern(PatternType) of
        {ok, ProcessDef} ->
            StepType = maps:get(step_type, ProcessDef, sequential),
            Steps = build_steps(StepType, Tasks, ProcessDef),
            {ok, Steps};
        {error, _} = Err ->
            Err
    end;
to_process_step(#{tasks := Tasks}) ->
    %% Default to sequential if no pattern type specified
    Steps = build_steps(sequential, Tasks, #{step_type => sequential}),
    {ok, Steps};
to_process_step(_) ->
    {error, invalid_workflow_definition}.

%% @doc Convert a BeamAI process result back to a YAWL-compatible result.
%% Maps BeamAI execution outcomes to YAWL workflow state updates.
-spec from_process_result(map()) -> {ok, map()} | {error, term()}.
from_process_result(#{status := Status} = Result) ->
    YawlStatus = beamai_status_to_yawl(Status),
    OutputData = maps:get(output, Result, maps:get(data, Result, #{})),
    YawlResult = #{
        status => YawlStatus,
        data => OutputData,
        completed_steps => maps:get(completed_steps, Result, []),
        execution_time => maps:get(execution_time_ms, Result, 0),
        metadata => #{
            source => beamai,
            original_status => Status,
            converted_at => erlang:system_time(millisecond)
        }
    },
    %% Handle pattern-specific result translation
    PatternResult = case maps:get(pattern_type, Result, undefined) of
        undefined -> YawlResult;
        PatternType -> enrich_pattern_result(PatternType, YawlResult, Result)
    end,
    {ok, PatternResult};
from_process_result(_) ->
    {error, invalid_process_result}.

%% @doc Validate that a YAWL pattern can be adapted to BeamAI.
%% Checks structural compatibility and returns any warnings.
-spec validate_pattern(atom() | #yawl_pattern{}) -> {ok, map()} | {error, term()}.
validate_pattern(PatternType) when is_atom(PatternType) ->
    case pattern_to_beamai(PatternType) of
        {error, Reason} ->
            {error, {unsupported_pattern, Reason}};
        ProcessDef ->
            Warnings = check_adaptation_warnings(PatternType, ProcessDef),
            {ok, #{
                pattern => PatternType,
                beamai_type => maps:get(step_type, ProcessDef, unknown),
                supported => true,
                warnings => Warnings,
                capabilities_required => maps:get(capabilities, ProcessDef, [])
            }}
    end;
validate_pattern(#yawl_pattern{type = PatternType}) ->
    validate_pattern(PatternType);
validate_pattern(_) ->
    {error, invalid_input}.

%%====================================================================
%% Internal Functions - Pattern Mapping
%%====================================================================

%% @private Map a YAWL pattern type to a BeamAI process definition.
-spec pattern_to_beamai(atom()) -> map() | {error, term()}.

%% Basic control-flow patterns
pattern_to_beamai(basic_sequential) ->
    #{
        step_type => sequential,
        execution_mode => serial,
        description => <<"Sequential execution of tasks in order">>,
        capabilities => []
    };

pattern_to_beamai(parallel_split) ->
    #{
        step_type => parallel,
        execution_mode => fork,
        join_condition => all,
        description => <<"Fork into multiple parallel branches">>,
        capabilities => [parallel_execution]
    };

pattern_to_beamai(parallel_join) ->
    #{
        step_type => parallel,
        execution_mode => join,
        join_condition => all,
        description => <<"Synchronize parallel branches (wait for all)">>,
        capabilities => [parallel_execution]
    };

pattern_to_beamai(exclusive_choice) ->
    #{
        step_type => conditional,
        execution_mode => branch,
        selection => exclusive,
        description => <<"Choose exactly one branch based on condition">>,
        capabilities => [conditional_branching]
    };

pattern_to_beamai(simple_merge) ->
    #{
        step_type => conditional,
        execution_mode => merge,
        merge_type => simple,
        description => <<"Merge multiple exclusive branches into one">>,
        capabilities => [conditional_branching]
    };

pattern_to_beamai(iterative_loop) ->
    #{
        step_type => loop,
        execution_mode => iterate,
        loop_type => while,
        description => <<"Repeatedly execute until condition is false">>,
        capabilities => [loop_execution]
    };

pattern_to_beamai(multi_instance) ->
    #{
        step_type => dynamic_spawn,
        execution_mode => multi_instance,
        instance_creation => dynamic,
        description => <<"Spawn multiple instances of a task dynamically">>,
        capabilities => [dynamic_spawning, parallel_execution]
    };

%% Advanced patterns
pattern_to_beamai(deferred_choice) ->
    #{
        step_type => event_driven,
        execution_mode => deferred_select,
        trigger => external_event,
        description => <<"Select branch based on first external event received">>,
        capabilities => [event_handling]
    };

pattern_to_beamai(interleaved_parallelism) ->
    #{
        step_type => interleaved,
        execution_mode => interleave,
        ordering => arbitrary,
        description => <<"Execute tasks in any order, one at a time">>,
        capabilities => [interleaved_execution]
    };

pattern_to_beamai(interleaved_routing) ->
    #{
        step_type => interleaved,
        execution_mode => routed_interleave,
        ordering => constrained,
        description => <<"Execute tasks in constrained interleaved order">>,
        capabilities => [interleaved_execution]
    };

pattern_to_beamai(implicit_merge) ->
    #{
        step_type => conditional,
        execution_mode => merge,
        merge_type => implicit,
        description => <<"Implicitly merge branches without synchronization">>,
        capabilities => [conditional_branching]
    };

pattern_to_beamai(multiple_merge) ->
    #{
        step_type => conditional,
        execution_mode => merge,
        merge_type => multiple,
        description => <<"Merge that activates for every incoming branch">>,
        capabilities => [conditional_branching, parallel_execution]
    };

pattern_to_beamai(milestone) ->
    #{
        step_type => guarded,
        execution_mode => milestone_gate,
        guard_type => state_based,
        description => <<"Task enabled only when milestone state is active">>,
        capabilities => [state_monitoring]
    };

%% Cancellation patterns -> BeamAI interrupt handling
pattern_to_beamai(cancelation) ->
    cancellation_step(block, <<"Cancel active tasks in a region">>);
pattern_to_beamai(cancelation_block) ->
    cancellation_step(block, <<"Cancel all tasks within a block scope">>);
pattern_to_beamai(cancelation_scope) ->
    cancellation_step(scope, <<"Cancel all tasks within a named scope">>);
pattern_to_beamai(cancelation_thread) ->
    cancellation_step(thread, <<"Cancel a specific execution thread">>);
pattern_to_beamai(cancelation_subprocess) ->
    cancellation_step(subprocess, <<"Cancel an entire subprocess">>);
pattern_to_beamai(cancelation_multiple_instances) ->
    cancellation_step(multi_instance, <<"Cancel all instances of a multi-instance task">>);
pattern_to_beamai(cancelation_point) ->
    cancellation_step(point, <<"Cancel at a specific cancellation point">>);
pattern_to_beamai(cancelation_end) ->
    cancellation_step(end_cancel, <<"Cancel upon reaching end state">>);

%% Catch-all for other cancellation pattern variants
pattern_to_beamai(Pattern) ->
    case yawl_patterns:is_cancellation_pattern(Pattern) of
        true ->
            cancellation_step(generic, <<"Cancellation pattern: ",
                (atom_to_binary(Pattern, utf8))/binary>>);
        false ->
            {error, {unsupported_pattern, Pattern}}
    end.

%% @private Build a cancellation/interrupt step definition.
-spec cancellation_step(atom(), binary()) -> map().
cancellation_step(CancelType, Description) ->
    #{
        step_type => interrupt,
        execution_mode => cancel,
        cancel_type => CancelType,
        description => Description,
        capabilities => [interrupt_handling, cancellation]
    }.

%%====================================================================
%% Internal Functions - Step Building
%%====================================================================

%% @private Build BeamAI process steps from YAWL tasks based on step type.
-spec build_steps(atom(), list(), map()) -> [map()].
build_steps(sequential, Tasks, _ProcessDef) ->
    lists:map(fun(Task) -> task_to_sequential_step(Task) end, Tasks);

build_steps(parallel, Tasks, ProcessDef) ->
    JoinCondition = maps:get(join_condition, ProcessDef, all),
    [#{
        step_id => <<"parallel_group">>,
        step_type => parallel,
        join_condition => JoinCondition,
        branches => lists:map(fun(Task) -> task_to_sequential_step(Task) end, Tasks)
    }];

build_steps(conditional, Tasks, ProcessDef) ->
    Selection = maps:get(selection, ProcessDef, exclusive),
    [#{
        step_id => <<"conditional_branch">>,
        step_type => conditional,
        selection => Selection,
        branches => lists:map(fun(Task) ->
            Condition = maps:get(condition, Task, true),
            #{
                condition => Condition,
                step => task_to_sequential_step(Task)
            }
        end, Tasks)
    }];

build_steps(loop, Tasks, _ProcessDef) ->
    [#{
        step_id => <<"loop_body">>,
        step_type => loop,
        loop_condition => maps:get(condition, hd(Tasks), true),
        body => lists:map(fun(Task) -> task_to_sequential_step(Task) end, Tasks)
    }];

build_steps(dynamic_spawn, Tasks, _ProcessDef) ->
    [#{
        step_id => <<"multi_instance">>,
        step_type => dynamic_spawn,
        instance_template => task_to_sequential_step(hd(Tasks)),
        cardinality => length(Tasks),
        join_condition => all
    }];

build_steps(interrupt, Tasks, ProcessDef) ->
    CancelType = maps:get(cancel_type, ProcessDef, block),
    [#{
        step_id => <<"interrupt_scope">>,
        step_type => interrupt,
        cancel_type => CancelType,
        protected_steps => lists:map(fun(Task) -> task_to_sequential_step(Task) end, Tasks),
        interrupt_handler => #{action => cancel, propagate => false}
    }];

build_steps(_Other, Tasks, _ProcessDef) ->
    %% Default to sequential for unknown types
    lists:map(fun(Task) -> task_to_sequential_step(Task) end, Tasks).

%% @private Convert a single YAWL task map to a BeamAI sequential step.
-spec task_to_sequential_step(map()) -> map().
task_to_sequential_step(Task) ->
    TaskId = maps:get(task_id, Task, maps:get(id, Task, generate_step_id())),
    #{
        step_id => ensure_binary(TaskId),
        step_type => task_type_to_step(maps:get(type, Task, automatic)),
        name => maps:get(name, Task, ensure_binary(TaskId)),
        input_schema => maps:get(input_schema, Task, #{}),
        output_schema => maps:get(output_schema, Task, #{}),
        config => maps:get(config, Task, #{}),
        timeout_ms => maps:get(timeout, Task, 30000),
        retry_policy => maps:get(retry_policy, Task, #{max_retries => 0})
    }.

%% @private Map YAWL task types to BeamAI step types.
-spec task_type_to_step(atom()) -> atom().
task_type_to_step(automatic) -> tool_call;
task_type_to_step(manual) -> human_input;
task_type_to_step(service) -> tool_call;
task_type_to_step(human) -> human_input;
task_type_to_step(llm) -> llm_chat;
task_type_to_step(Other) -> Other.

%%====================================================================
%% Internal Functions - Status Mapping
%%====================================================================

%% @private Convert BeamAI process status to YAWL workflow status.
-spec beamai_status_to_yawl(atom()) -> atom().
beamai_status_to_yawl(pending) -> pending;
beamai_status_to_yawl(executing) -> running;
beamai_status_to_yawl(completed) -> completed;
beamai_status_to_yawl(failed) -> failed;
beamai_status_to_yawl(cancelled) -> cancelled;
beamai_status_to_yawl(waiting_input) -> pending;
beamai_status_to_yawl(interrupted) -> cancelled;
beamai_status_to_yawl(_Other) -> pending.

%% @private Enrich a result map with pattern-specific data.
-spec enrich_pattern_result(atom(), map(), map()) -> map().
enrich_pattern_result(parallel_split, YawlResult, BeamAIResult) ->
    BranchResults = maps:get(branch_results, BeamAIResult, []),
    YawlResult#{
        branch_results => BranchResults,
        all_branches_completed => lists:all(
            fun(BR) -> maps:get(status, BR, pending) =:= completed end,
            BranchResults
        )
    };
enrich_pattern_result(exclusive_choice, YawlResult, BeamAIResult) ->
    YawlResult#{
        selected_branch => maps:get(selected_branch, BeamAIResult, undefined),
        condition_evaluated => maps:get(condition, BeamAIResult, undefined)
    };
enrich_pattern_result(multi_instance, YawlResult, BeamAIResult) ->
    YawlResult#{
        instance_count => maps:get(instance_count, BeamAIResult, 0),
        instance_results => maps:get(instance_results, BeamAIResult, [])
    };
enrich_pattern_result(_PatternType, YawlResult, _BeamAIResult) ->
    YawlResult.

%%====================================================================
%% Internal Functions - Validation
%%====================================================================

%% @private Check for any warnings when adapting a pattern.
-spec check_adaptation_warnings(atom(), map()) -> [binary()].
check_adaptation_warnings(PatternType, ProcessDef) ->
    Warnings0 = [],
    %% Warn about complexity
    Warnings1 = case maps:get(capabilities, ProcessDef, []) of
        Caps when length(Caps) > 2 ->
            [<<"Pattern requires multiple advanced capabilities">> | Warnings0];
        _ ->
            Warnings0
    end,
    %% Warn about cancellation patterns losing fine-grained control
    Warnings2 = case maps:get(step_type, ProcessDef, undefined) of
        interrupt ->
            [<<"Cancellation semantics may differ between YAWL and BeamAI">> | Warnings1];
        _ ->
            Warnings1
    end,
    %% Warn about resource patterns
    Warnings3 = case yawl_patterns:is_resource_pattern(PatternType) of
        true ->
            [<<"Resource allocation patterns require beamai_yawl_resource_bridge">> | Warnings2];
        false ->
            Warnings2
    end,
    Warnings3.

%%====================================================================
%% Internal Functions - Utilities
%%====================================================================

%% @private Generate a unique step identifier.
-spec generate_step_id() -> binary().
generate_step_id() ->
    Rand = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    <<"step_", Rand/binary>>.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
