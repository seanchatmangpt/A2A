%%%-------------------------------------------------------------------
%%% @doc BeamAI DeepAgent YAWL Integration
%%% Integrates beamai_deepagent (Planner -> Executor -> Reflector)
%%% with YAWL workflows for planning, execution, reflection, and
%%% optimization of workflow definitions.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_deepagent_yawl).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

-export([plan_workflow/1, execute_plan/2, reflect_on_execution/2,
         optimize_workflow/1]).

-spec plan_workflow(map()) -> {ok, map()} | {error, term()}.
plan_workflow(WorkflowDef) ->
    Pattern = maps:get(pattern_type, WorkflowDef, basic_sequential),
    Spec = beamai_yawl_patterns_adapter:adapt_pattern(Pattern),
    Tools = build_tools(WorkflowDef),
    K = beamai_kernel:add_tools(beamai_kernel:new(#{name => <<"planner">>}), Tools),
    Opts = #{kernel => K, role => planner,
             prompt => plan_prompt(Pattern, Spec)},
    case beamai_deepagent:new(Opts) of
        {ok, DS} ->
            Input = #{workflow => WorkflowDef, pattern => Spec},
            case beamai_agent:run(DS, Input) of
                {ok, R, _} -> {ok, normalize_plan(R, WorkflowDef)};
                {error, E} -> {error, {planning_failed, E}}
            end;
        {error, E} -> {error, {agent_init_failed, E}}
    end.

-spec execute_plan(map(), map()) -> {ok, map()} | {error, term()}.
execute_plan(Plan, Input) ->
    Steps = maps:get(steps, Plan, []),
    Tools = [beamai_tool:new(maps:get(name, S, <<"step">>),
              fun(A) -> #{executed => true, args => A} end) || S <- Steps],
    K = beamai_kernel:add_tools(beamai_kernel:new(#{name => <<"executor">>}), Tools),
    Opts = #{kernel => K, role => executor,
             prompt => <<"Execute the YAWL workflow plan step by step.">>},
    case beamai_agent:new(Opts) of
        {ok, AS} ->
            case beamai_agent:run(AS, maps:merge(Input, #{plan => Plan})) of
                {ok, R, _} -> {ok, #{status => completed, result => R, plan => Plan}};
                {error, E} -> {error, {execution_failed, E}}
            end;
        {error, E} -> {error, {agent_init_failed, E}}
    end.

-spec reflect_on_execution(map(), map()) -> {ok, map()} | {error, term()}.
reflect_on_execution(Plan, ExecResult) ->
    Ctx = beamai:context(#{plan => Plan, result => ExecResult}),
    Prompt = <<"Analyze the YAWL workflow execution. Evaluate completion, "
               "failures, bottlenecks, and suggest improvements.">>,
    case beamai:chat(Ctx, Prompt) of
        {ok, Analysis} ->
            Score = case maps:get(status, ExecResult, unknown) of
                completed -> 1.0; failed -> 0.0; _ -> 0.5
            end,
            {ok, #{analysis => Analysis, plan => Plan,
                   result => ExecResult, score => Score,
                   improvements => extract_improvements(Analysis)}};
        {error, E} -> {error, {reflection_failed, E}}
    end.

-spec optimize_workflow(map()) -> {ok, map()} | {error, term()}.
optimize_workflow(WorkflowDef) ->
    case plan_workflow(WorkflowDef) of
        {ok, Plan} ->
            case execute_plan(Plan, #{dry_run => true}) of
                {ok, DryResult} ->
                    case reflect_on_execution(Plan, DryResult) of
                        {ok, Ref} ->
                            Imps = maps:get(improvements, Ref, []),
                            Opt = apply_improvements(WorkflowDef, Imps),
                            {ok, #{original => WorkflowDef, optimized => Opt,
                                   reflection => Ref, plan => Plan}};
                        {error, E} -> {error, E}
                    end;
                {error, E} -> {error, E}
            end;
        {error, E} -> {error, E}
    end.

%% Internal
build_tools(WDef) ->
    WIs = maps:get(work_items, WDef, []),
    Trs = maps:get(transitions, WDef, []),
    WiTools = [beamai_yawl_bridge:map_workitem_to_tool(WI) || WI <- WIs],
    TrTools = [beamai_tool:new(<<"plan_", (to_bin(T))/binary>>,
                fun(A) -> #{planned => true, transition => to_bin(T), args => A} end)
               || T <- Trs],
    WiTools ++ TrTools.

plan_prompt(Pattern, Spec) ->
    PType = maps:get(type, Spec, unknown),
    iolist_to_binary([<<"Create an execution plan for YAWL pattern '">>,
        atom_to_binary(Pattern, utf8), <<"' (process type '">>,
        atom_to_binary(PType, utf8), <<"'). List steps with dependencies.">>]).

normalize_plan(R, WDef) when is_map(R) ->
    #{steps => maps:get(steps, R, []),
      pattern => maps:get(pattern_type, WDef, unknown), raw => R};
normalize_plan(R, WDef) ->
    #{steps => [], pattern => maps:get(pattern_type, WDef, unknown), raw => R}.

extract_improvements(A) when is_map(A) -> maps:get(improvements, A, []);
extract_improvements(_) -> [].

apply_improvements(WDef, []) -> WDef;
apply_improvements(WDef, Imps) ->
    WDef#{optimizations => Imps, optimized_at => erlang:system_time(millisecond)}.

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_bin(V) when is_list(V) -> list_to_binary(V).
