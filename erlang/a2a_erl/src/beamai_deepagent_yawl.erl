%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI DeepAgent Integration for YAWL Workflows
%%%
%%% Integrates BeamAI's DeepAgent architecture (Planner -> Executor ->
%%% Reflector) with the YAWL workflow engine. This module:
%%%
%%% - Uses DeepAgent's Planner to create YAWL workflow execution plans
%%% - Uses DeepAgent's Executor to drive workflow step execution
%%% - Uses DeepAgent's Reflector to analyze and improve workflows
%%% - Supports iterative workflow optimization via reflection loops
%%%
%%% The Planner-Executor-Reflector cycle enables LLM-driven workflow
%%% orchestration where the LLM can reason about task dependencies,
%%% resource availability, and execution outcomes.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_deepagent_yawl).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%% API
-export([
    plan_workflow/1,
    execute_plan/2,
    reflect_on_execution/2,
    optimize_workflow/1
]).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Plan the execution of a YAWL workflow using DeepAgent's Planner.
%% Analyzes the workflow definition, available resources, and constraints
%% to produce an optimized execution plan.
%%
%% Returns a plan map containing ordered steps, resource assignments,
%% parallel opportunities, and estimated execution metrics.
-spec plan_workflow(map()) -> {ok, map()} | {error, term()}.
plan_workflow(WorkflowDef) ->
    WorkflowId = maps:get(workflow_id, WorkflowDef,
                  maps:get(id, WorkflowDef, generate_id(<<"wf">>))),
    Tasks = maps:get(tasks, WorkflowDef, []),
    PatternType = maps:get(pattern_type, WorkflowDef, basic_sequential),

    %% Phase 1: Analyze workflow structure
    Structure = analyze_workflow_structure(Tasks, PatternType),

    %% Phase 2: Check resource availability
    ResourceInfo = gather_resource_info(Tasks),

    %% Phase 3: Build the planning prompt for the LLM
    PlanningPrompt = build_planning_prompt(WorkflowId, Structure, ResourceInfo),

    %% Phase 4: Execute planning via BeamAI LLM
    case invoke_planner(PlanningPrompt) of
        {ok, LlmPlan} ->
            %% Phase 5: Validate and structure the plan
            Plan = structure_plan(WorkflowId, LlmPlan, Structure, ResourceInfo),
            {ok, Plan};
        {error, Reason} ->
            %% Fall back to rule-based planning
            FallbackPlan = build_fallback_plan(WorkflowId, Tasks, PatternType),
            logger:warning("LLM planner failed (~p), using fallback plan", [Reason]),
            {ok, FallbackPlan}
    end.

%% @doc Execute a previously created plan against the YAWL workflow.
%% Drives step-by-step execution, handling branching decisions and
%% resource allocation as directed by the plan.
-spec execute_plan(map(), map()) -> {ok, map()} | {error, term()}.
execute_plan(Plan, InputData) ->
    WorkflowId = maps:get(workflow_id, Plan),
    Steps = maps:get(steps, Plan, []),
    StartTime = erlang:system_time(millisecond),

    %% Execute each step in the plan
    {StepResults, FinalState} = execute_steps(Steps, InputData, WorkflowId, [], #{}),

    EndTime = erlang:system_time(millisecond),
    ExecutionResult = #{
        workflow_id => WorkflowId,
        plan_id => maps:get(plan_id, Plan, <<"unknown">>),
        status => determine_overall_status(StepResults),
        step_results => StepResults,
        execution_time_ms => EndTime - StartTime,
        final_state => FinalState,
        started_at => StartTime,
        completed_at => EndTime,
        metadata => #{
            total_steps => length(Steps),
            completed_steps => count_by_status(completed, StepResults),
            failed_steps => count_by_status(failed, StepResults)
        }
    },
    {ok, ExecutionResult}.

%% @doc Reflect on the execution results using DeepAgent's Reflector.
%% Analyzes what worked well, what failed, and generates improvement
%% suggestions for future workflow executions.
-spec reflect_on_execution(map(), map()) -> {ok, map()} | {error, term()}.
reflect_on_execution(Plan, ExecutionResult) ->
    WorkflowId = maps:get(workflow_id, Plan),

    %% Build the reflection prompt
    ReflectionPrompt = build_reflection_prompt(Plan, ExecutionResult),

    %% Execute reflection via BeamAI LLM
    case invoke_reflector(ReflectionPrompt) of
        {ok, LlmReflection} ->
            Reflection = structure_reflection(WorkflowId, LlmReflection, ExecutionResult),
            {ok, Reflection};
        {error, Reason} ->
            %% Fall back to rule-based reflection
            FallbackReflection = build_fallback_reflection(ExecutionResult),
            logger:warning("LLM reflector failed (~p), using rule-based reflection", [Reason]),
            {ok, FallbackReflection}
    end.

%% @doc Run a full optimize cycle: Plan -> Execute -> Reflect -> Replan.
%% Performs one iteration of the DeepAgent optimization loop.
-spec optimize_workflow(map()) -> {ok, map()} | {error, term()}.
optimize_workflow(WorkflowDef) ->
    %% Step 1: Plan
    case plan_workflow(WorkflowDef) of
        {ok, Plan} ->
            InputData = maps:get(input_data, WorkflowDef, #{}),
            %% Step 2: Execute
            case execute_plan(Plan, InputData) of
                {ok, ExecutionResult} ->
                    %% Step 3: Reflect
                    case reflect_on_execution(Plan, ExecutionResult) of
                        {ok, Reflection} ->
                            %% Step 4: Generate optimized workflow definition
                            Improvements = maps:get(improvements, Reflection, []),
                            OptimizedDef = apply_improvements(WorkflowDef, Improvements),
                            {ok, #{
                                original_workflow => WorkflowDef,
                                plan => Plan,
                                execution_result => ExecutionResult,
                                reflection => Reflection,
                                optimized_workflow => OptimizedDef,
                                optimization_cycle => 1,
                                timestamp => erlang:system_time(millisecond)
                            }};
                        {error, ReflectErr} ->
                            {error, {reflection_failed, ReflectErr}}
                    end;
                {error, ExecErr} ->
                    {error, {execution_failed, ExecErr}}
            end;
        {error, PlanErr} ->
            {error, {planning_failed, PlanErr}}
    end.

%%%===================================================================
%%% Internal Functions - Workflow Analysis
%%%===================================================================

%% @private Analyze the structure of a YAWL workflow.
-spec analyze_workflow_structure(list(), atom()) -> map().
analyze_workflow_structure(Tasks, PatternType) ->
    TaskCount = length(Tasks),
    HasHumanTasks = lists:any(fun(T) ->
        maps:get(type, T, automatic) =:= human orelse
        maps:get(type, T, automatic) =:= manual
    end, Tasks),
    HasServiceTasks = lists:any(fun(T) ->
        maps:get(type, T, automatic) =:= service
    end, Tasks),
    Dependencies = extract_dependencies(Tasks),
    ParallelOpportunities = find_parallel_opportunities(Tasks, Dependencies),
    #{
        task_count => TaskCount,
        pattern_type => PatternType,
        has_human_tasks => HasHumanTasks,
        has_service_tasks => HasServiceTasks,
        dependencies => Dependencies,
        parallel_opportunities => ParallelOpportunities,
        critical_path => compute_critical_path(Tasks, Dependencies),
        estimated_complexity => estimate_complexity(TaskCount, PatternType)
    }.

%% @private Extract task dependencies from the task list.
-spec extract_dependencies(list()) -> map().
extract_dependencies(Tasks) ->
    lists:foldl(fun(Task, Acc) ->
        TaskId = maps:get(task_id, Task, maps:get(id, Task, <<"unknown">>)),
        Deps = maps:get(depends_on, Task, []),
        Acc#{TaskId => Deps}
    end, #{}, Tasks).

%% @private Find tasks that can be executed in parallel.
-spec find_parallel_opportunities(list(), map()) -> [[term()]].
find_parallel_opportunities(Tasks, Dependencies) ->
    %% Tasks with no mutual dependencies can run in parallel
    TaskIds = [maps:get(task_id, T, maps:get(id, T, <<"unknown">>)) || T <- Tasks],
    %% Group independent tasks
    lists:foldl(fun(TaskId, Groups) ->
        Deps = maps:get(TaskId, Dependencies, []),
        case Deps of
            [] ->
                %% No dependencies; can run in the first group
                case Groups of
                    [] -> [[TaskId]];
                    [FirstGroup | Rest] -> [[TaskId | FirstGroup] | Rest]
                end;
            _ ->
                %% Has dependencies; start a new group after all deps
                Groups ++ [[TaskId]]
        end
    end, [], TaskIds).

%% @private Compute a simple critical path estimate.
-spec compute_critical_path(list(), map()) -> [term()].
compute_critical_path(Tasks, Dependencies) ->
    %% Simple: longest dependency chain
    TaskIds = [maps:get(task_id, T, maps:get(id, T, <<"unknown">>)) || T <- Tasks],
    lists:foldl(fun(TaskId, Longest) ->
        Chain = build_dep_chain(TaskId, Dependencies, []),
        case length(Chain) > length(Longest) of
            true -> Chain;
            false -> Longest
        end
    end, [], TaskIds).

%% @private Build a dependency chain for a task.
-spec build_dep_chain(term(), map(), list()) -> list().
build_dep_chain(TaskId, Dependencies, Visited) ->
    case lists:member(TaskId, Visited) of
        true -> Visited;
        false ->
            Deps = maps:get(TaskId, Dependencies, []),
            NewVisited = [TaskId | Visited],
            case Deps of
                [] -> NewVisited;
                [Dep | _] -> build_dep_chain(Dep, Dependencies, NewVisited)
            end
    end.

%% @private Estimate workflow complexity.
-spec estimate_complexity(non_neg_integer(), atom()) -> low | medium | high.
estimate_complexity(TaskCount, _PatternType) when TaskCount =< 3 -> low;
estimate_complexity(TaskCount, _PatternType) when TaskCount =< 10 -> medium;
estimate_complexity(_TaskCount, _PatternType) -> high.

%%%===================================================================
%%% Internal Functions - Resource Gathering
%%%===================================================================

%% @private Gather information about available resources for planning.
-spec gather_resource_info(list()) -> map().
gather_resource_info(Tasks) ->
    RequiredCapabilities = lists:usort(lists:flatten([
        maps:get(required_capabilities, T, []) || T <- Tasks
    ])),
    AvailableResources = case whereis(yawl_resource_manager) of
        undefined -> [];
        _Pid ->
            try
                case yawl_resource_manager:list_available_resources() of
                    {ok, Rs} -> Rs;
                    _ -> []
                end
            catch _:_ -> []
            end
    end,
    #{
        required_capabilities => RequiredCapabilities,
        available_resources => AvailableResources,
        resource_count => length(AvailableResources)
    }.

%%%===================================================================
%%% Internal Functions - LLM Invocation
%%%===================================================================

%% @private Build the planning prompt for the LLM.
-spec build_planning_prompt(binary(), map(), map()) -> binary().
build_planning_prompt(WorkflowId, Structure, ResourceInfo) ->
    TaskCount = maps:get(task_count, Structure, 0),
    PatternType = maps:get(pattern_type, Structure, basic_sequential),
    Complexity = maps:get(estimated_complexity, Structure, medium),
    ResourceCount = maps:get(resource_count, ResourceInfo, 0),
    iolist_to_binary([
        <<"You are a workflow execution planner. Plan the execution of workflow '">>,
        WorkflowId, <<"'.\n\n">>,
        <<"Workflow has ">>, integer_to_binary(TaskCount), <<" tasks.\n">>,
        <<"Pattern type: ">>, atom_to_binary(PatternType, utf8), <<"\n">>,
        <<"Complexity: ">>, atom_to_binary(Complexity, utf8), <<"\n">>,
        <<"Available resources: ">>, integer_to_binary(ResourceCount), <<"\n">>,
        <<"Has human tasks: ">>, atom_to_binary(maps:get(has_human_tasks, Structure, false), utf8), <<"\n\n">>,
        <<"Create an execution plan with: step ordering, resource assignments, ">>,
        <<"parallel execution opportunities, and estimated timing.">>
    ]).

%% @private Invoke the BeamAI LLM for planning.
-spec invoke_planner(binary()) -> {ok, binary()} | {error, term()}.
invoke_planner(Prompt) ->
    case whereis(beamai_kernel) of
        undefined -> {error, kernel_unavailable};
        _Pid ->
            try
                beamai:chat(beamai_kernel, Prompt, #{
                    system => <<"You are a YAWL workflow planning agent. "
                                "Output structured execution plans.">>,
                    temperature => 0.3
                })
            catch
                _:Err -> {error, Err}
            end
    end.

%% @private Build the reflection prompt for the LLM.
-spec build_reflection_prompt(map(), map()) -> binary().
build_reflection_prompt(Plan, ExecutionResult) ->
    Status = maps:get(status, ExecutionResult, unknown),
    ExecTime = maps:get(execution_time_ms, ExecutionResult, 0),
    TotalSteps = maps:get(total_steps, maps:get(metadata, ExecutionResult, #{}), 0),
    FailedSteps = maps:get(failed_steps, maps:get(metadata, ExecutionResult, #{}), 0),
    PlanId = maps:get(plan_id, Plan, <<"unknown">>),
    iolist_to_binary([
        <<"Reflect on the execution of plan '">>, PlanId, <<"'.\n\n">>,
        <<"Overall status: ">>, atom_to_binary(Status, utf8), <<"\n">>,
        <<"Execution time: ">>, integer_to_binary(ExecTime), <<"ms\n">>,
        <<"Total steps: ">>, integer_to_binary(TotalSteps), <<"\n">>,
        <<"Failed steps: ">>, integer_to_binary(FailedSteps), <<"\n\n">>,
        <<"Analyze: What went well? What failed? How can the workflow be improved? ">>,
        <<"Suggest specific improvements for task ordering, resource allocation, ">>,
        <<"and error handling.">>
    ]).

%% @private Invoke the BeamAI LLM for reflection.
-spec invoke_reflector(binary()) -> {ok, binary()} | {error, term()}.
invoke_reflector(Prompt) ->
    case whereis(beamai_kernel) of
        undefined -> {error, kernel_unavailable};
        _Pid ->
            try
                beamai:chat(beamai_kernel, Prompt, #{
                    system => <<"You are a workflow optimization reflector. "
                                "Analyze execution results and suggest improvements.">>,
                    temperature => 0.5
                })
            catch
                _:Err -> {error, Err}
            end
    end.

%%%===================================================================
%%% Internal Functions - Plan Structuring
%%%===================================================================

%% @private Structure the LLM plan output into a usable plan map.
-spec structure_plan(binary(), binary(), map(), map()) -> map().
structure_plan(WorkflowId, LlmPlan, Structure, ResourceInfo) ->
    Tasks = maps:get(dependencies, Structure, #{}),
    ParallelOps = maps:get(parallel_opportunities, Structure, []),
    PlanId = generate_id(<<"plan">>),
    %% Build steps from the workflow structure (enhanced by LLM suggestions)
    Steps = build_plan_steps(Tasks, ParallelOps, ResourceInfo),
    #{
        plan_id => PlanId,
        workflow_id => WorkflowId,
        steps => Steps,
        parallel_groups => ParallelOps,
        resource_assignments => maps:get(available_resources, ResourceInfo, []),
        llm_suggestions => LlmPlan,
        pattern_type => maps:get(pattern_type, Structure, basic_sequential),
        estimated_complexity => maps:get(estimated_complexity, Structure, medium),
        created_at => erlang:system_time(millisecond)
    }.

%% @private Build plan steps from task dependencies and parallel opportunities.
-spec build_plan_steps(map(), list(), map()) -> [map()].
build_plan_steps(TaskDeps, ParallelGroups, _ResourceInfo) ->
    %% Flatten parallel groups into ordered steps with execution hints
    StepIndex = lists:foldl(fun(Group, {Acc, Idx}) ->
        GroupSteps = lists:map(fun(TaskId) ->
            Deps = maps:get(TaskId, TaskDeps, []),
            #{
                step_index => Idx,
                task_id => TaskId,
                dependencies => Deps,
                parallel_group => length(Group) > 1,
                execution_hint => case length(Group) > 1 of
                    true -> parallel;
                    false -> sequential
                end
            }
        end, Group),
        {Acc ++ GroupSteps, Idx + 1}
    end, {[], 1}, ParallelGroups),
    element(1, StepIndex).

%% @private Build a fallback plan when the LLM is unavailable.
-spec build_fallback_plan(binary(), list(), atom()) -> map().
build_fallback_plan(WorkflowId, Tasks, PatternType) ->
    PlanId = generate_id(<<"plan">>),
    Steps = lists:map(fun({Idx, Task}) ->
        TaskId = maps:get(task_id, Task, maps:get(id, Task, <<"unknown">>)),
        #{
            step_index => Idx,
            task_id => TaskId,
            dependencies => maps:get(depends_on, Task, []),
            parallel_group => false,
            execution_hint => sequential
        }
    end, lists:zip(lists:seq(1, length(Tasks)), Tasks)),
    #{
        plan_id => PlanId,
        workflow_id => WorkflowId,
        steps => Steps,
        parallel_groups => [],
        resource_assignments => [],
        llm_suggestions => <<"Fallback: sequential execution">>,
        pattern_type => PatternType,
        estimated_complexity => estimate_complexity(length(Tasks), PatternType),
        created_at => erlang:system_time(millisecond),
        is_fallback => true
    }.

%%%===================================================================
%%% Internal Functions - Plan Execution
%%%===================================================================

%% @private Execute the plan steps sequentially/in parallel as directed.
-spec execute_steps([map()], map(), binary(), [map()], map()) -> {[map()], map()}.
execute_steps([], _InputData, _WorkflowId, Results, AccState) ->
    {lists:reverse(Results), AccState};
execute_steps([Step | Rest], InputData, WorkflowId, Results, AccState) ->
    TaskId = maps:get(task_id, Step, <<"unknown">>),
    StepInput = maps:merge(InputData, AccState),
    StepStart = erlang:system_time(millisecond),
    %% Execute the step through the YAWL bridge
    StepResult = execute_single_step(WorkflowId, TaskId, StepInput),
    StepEnd = erlang:system_time(millisecond),
    ResultEntry = #{
        task_id => TaskId,
        step_index => maps:get(step_index, Step, 0),
        status => maps:get(status, StepResult, unknown),
        result => StepResult,
        execution_time_ms => StepEnd - StepStart
    },
    %% Merge step output into accumulated state
    NewAccState = maps:merge(AccState, maps:get(output, StepResult, #{})),
    execute_steps(Rest, InputData, WorkflowId, [ResultEntry | Results], NewAccState).

%% @private Execute a single workflow step.
-spec execute_single_step(binary(), term(), map()) -> map().
execute_single_step(WorkflowId, TaskId, InputData) ->
    case whereis(beamai_yawl_bridge) of
        undefined ->
            %% Direct YAWL execution without BeamAI bridge
            case whereis(yawl_workitem_processor) of
                undefined ->
                    #{status => skipped, reason => no_processor};
                _Pid ->
                    Workitem = #yawl_workitem_persist{
                        workitem_id = generate_id(<<"wi">>),
                        workflow_id = WorkflowId,
                        task_id = TaskId,
                        task_name = ensure_binary(TaskId),
                        status = pending,
                        data = InputData,
                        retry_count = 0,
                        priority = normal
                    },
                    try
                        case yawl_workitem_processor:process_workitem(Workitem) of
                            {ok, Result} ->
                                #{status => completed, output => Result};
                            {error, Reason} ->
                                #{status => failed, reason => Reason}
                        end
                    catch
                        _:Err ->
                            #{status => error, reason => Err}
                    end
            end;
        _BridgePid ->
            try
                KernelRef = beamai_kernel,
                ToolName = <<WorkflowId/binary, ".", (ensure_binary(TaskId))/binary>>,
                Context = #{workflow_id => WorkflowId, task_id => TaskId},
                case beamai:invoke_tool(KernelRef, ToolName, InputData, Context) of
                    {ok, Result} ->
                        #{status => completed, output => Result};
                    {error, {tool_not_found, _}} ->
                        %% Tool not registered; try direct execution
                        #{status => skipped, reason => tool_not_found};
                    {error, Reason} ->
                        #{status => failed, reason => Reason}
                end
            catch
                _:Err ->
                    #{status => error, reason => Err}
            end
    end.

%%%===================================================================
%%% Internal Functions - Reflection Structuring
%%%===================================================================

%% @private Structure the LLM reflection into a usable map.
-spec structure_reflection(binary(), binary(), map()) -> map().
structure_reflection(WorkflowId, LlmReflection, ExecutionResult) ->
    Status = maps:get(status, ExecutionResult, unknown),
    FailedSteps = [R || R <- maps:get(step_results, ExecutionResult, []),
                        maps:get(status, R, unknown) =:= failed],
    Improvements = derive_improvements(FailedSteps, Status),
    #{
        workflow_id => WorkflowId,
        overall_assessment => Status,
        llm_analysis => LlmReflection,
        failed_steps => FailedSteps,
        improvements => Improvements,
        execution_time_ms => maps:get(execution_time_ms, ExecutionResult, 0),
        reflected_at => erlang:system_time(millisecond)
    }.

%% @private Build a fallback reflection when the LLM is unavailable.
-spec build_fallback_reflection(map()) -> map().
build_fallback_reflection(ExecutionResult) ->
    Status = maps:get(status, ExecutionResult, unknown),
    FailedSteps = [R || R <- maps:get(step_results, ExecutionResult, []),
                        maps:get(status, R, unknown) =:= failed],
    #{
        overall_assessment => Status,
        llm_analysis => <<"Fallback reflection: LLM unavailable">>,
        failed_steps => FailedSteps,
        improvements => derive_improvements(FailedSteps, Status),
        execution_time_ms => maps:get(execution_time_ms, ExecutionResult, 0),
        is_fallback => true,
        reflected_at => erlang:system_time(millisecond)
    }.

%% @private Derive improvement suggestions from execution results.
-spec derive_improvements(list(), atom()) -> [map()].
derive_improvements(FailedSteps, OverallStatus) ->
    BaseImprovements = case OverallStatus of
        completed -> [];
        failed ->
            [#{type => retry_policy, suggestion => <<"Add retry policies for failing steps">>}];
        _ ->
            [#{type => monitoring, suggestion => <<"Add monitoring for incomplete workflows">>}]
    end,
    StepImprovements = lists:map(fun(Step) ->
        TaskId = maps:get(task_id, Step, <<"unknown">>),
        Reason = maps:get(reason, maps:get(result, Step, #{}), unknown),
        #{
            type => step_fix,
            task_id => TaskId,
            failure_reason => Reason,
            suggestion => <<"Review and fix task ", (ensure_binary(TaskId))/binary>>
        }
    end, FailedSteps),
    BaseImprovements ++ StepImprovements.

%% @private Apply improvements to a workflow definition.
-spec apply_improvements(map(), [map()]) -> map().
apply_improvements(WorkflowDef, Improvements) ->
    %% Add retry policies for steps that need them
    Tasks = maps:get(tasks, WorkflowDef, []),
    RetryTasks = lists:foldl(fun(Improvement, Acc) ->
        case maps:get(type, Improvement, unknown) of
            retry_policy ->
                %% Add retry policy to all tasks
                lists:map(fun(T) ->
                    ExistingRetry = maps:get(retry_policy, T, #{}),
                    case maps:get(max_retries, ExistingRetry, 0) of
                        0 -> T#{retry_policy => #{max_retries => 3, delay_ms => 1000}};
                        _ -> T
                    end
                end, Acc);
            step_fix ->
                TaskId = maps:get(task_id, Improvement, undefined),
                lists:map(fun(T) ->
                    TId = maps:get(task_id, T, maps:get(id, T, undefined)),
                    case TId =:= TaskId of
                        true -> T#{needs_review => true};
                        false -> T
                    end
                end, Acc);
            _ ->
                Acc
        end
    end, Tasks, Improvements),
    WorkflowDef#{
        tasks => RetryTasks,
        optimization_applied => true,
        improvements_count => length(Improvements),
        optimized_at => erlang:system_time(millisecond)
    }.

%%%===================================================================
%%% Internal Functions - Utilities
%%%===================================================================

%% @private Determine the overall status from step results.
-spec determine_overall_status([map()]) -> atom().
determine_overall_status([]) -> completed;
determine_overall_status(StepResults) ->
    HasFailed = lists:any(fun(R) ->
        maps:get(status, R, unknown) =:= failed orelse
        maps:get(status, R, unknown) =:= error
    end, StepResults),
    AllCompleted = lists:all(fun(R) ->
        S = maps:get(status, R, unknown),
        S =:= completed orelse S =:= skipped
    end, StepResults),
    case {HasFailed, AllCompleted} of
        {true, _} -> failed;
        {_, true} -> completed;
        _ -> partial
    end.

%% @private Count step results with a given status.
-spec count_by_status(atom(), [map()]) -> non_neg_integer().
count_by_status(Status, StepResults) ->
    length([R || R <- StepResults, maps:get(status, R, unknown) =:= Status]).

%% @private Generate a unique identifier.
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Rand = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<Prefix/binary, "_", Ts/binary, "_", Rand/binary>>.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
