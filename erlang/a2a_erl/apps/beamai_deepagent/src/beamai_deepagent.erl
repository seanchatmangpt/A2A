%%%-------------------------------------------------------------------
%%% @doc BeamAI DeepAgent - Recursive Planning Agent
%%%
%%% Implements the Planner -> Executor -> Reflector pattern for
%%% complex, multi-step task execution.
%%%
%%% The agent operates in three phases:
%%%   1. Plan: Use LLM to decompose a goal into an execution plan
%%%   2. Execute: Run plan steps using tools, agents, or sub-plans
%%%   3. Reflect: Evaluate results, decide to accept or replan
%%%
%%% Supports recursive planning where reflection can trigger
%%% replanning for failed or incomplete steps.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_deepagent).

-behaviour(gen_server).

%% API
-export([
    new/1,
    plan/2,
    execute/2,
    reflect/2,
    run/2,
    get_plan/1,
    get_result/1,
    get_status/1,
    stop/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(DEFAULT_MAX_REPLANS, 3).
-define(DEFAULT_MAX_DEPTH, 5).
-define(PLAN_TIMEOUT, 120000).

-type plan_step() :: #{
    id := binary(),
    description := binary(),
    type := tool_call | llm_call | sub_plan | agent_call,
    tool => binary(),
    args => map(),
    depends_on => [binary()],
    status => pending | running | completed | failed | skipped,
    result => term(),
    error => term()
}.

-type execution_plan() :: #{
    goal := binary(),
    steps := [plan_step()],
    created_at := integer(),
    version := non_neg_integer(),
    status := pending | executing | completed | failed | replanning
}.

-record(state, {
    id              :: binary(),
    kernel_ref      :: atom() | pid(),
    system_prompt   :: binary(),
    plan            :: execution_plan() | undefined,
    goal            :: binary() | undefined,
    result          :: term() | undefined,
    status          :: idle | planning | executing | reflecting | completed | failed,
    replan_count    :: non_neg_integer(),
    max_replans     :: pos_integer(),
    max_depth       :: pos_integer(),
    current_depth   :: non_neg_integer(),
    execution_log   :: [map()],
    config          :: map(),
    metadata        :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Create a new deep agent.
%% Options:
%%   kernel_ref - BeamAI kernel reference
%%   system_prompt - System prompt for planning/reflection
%%   max_replans - Maximum replan attempts (default: 3)
%%   max_depth - Maximum recursion depth (default: 5)
-spec new(map()) -> {ok, pid()} | {error, term()}.
new(Config) ->
    gen_server:start_link(?MODULE, Config, []).

%% @doc Create an execution plan for the given goal.
-spec plan(pid(), binary()) -> {ok, execution_plan()} | {error, term()}.
plan(Agent, Goal) ->
    gen_server:call(Agent, {plan, Goal}, ?PLAN_TIMEOUT).

%% @doc Execute the current plan (or a specific plan).
-spec execute(pid(), execution_plan() | auto) -> {ok, map()} | {error, term()}.
execute(Agent, PlanOrAuto) ->
    gen_server:call(Agent, {execute, PlanOrAuto}, infinity).

%% @doc Reflect on execution results, potentially triggering a replan.
-spec reflect(pid(), map()) -> {ok, map()} | {error, term()}.
reflect(Agent, Results) ->
    gen_server:call(Agent, {reflect, Results}, ?PLAN_TIMEOUT).

%% @doc Run the full Planner -> Executor -> Reflector cycle for a goal.
-spec run(pid(), binary()) -> {ok, term()} | {error, term()}.
run(Agent, Goal) ->
    gen_server:call(Agent, {run, Goal}, infinity).

%% @doc Get the current execution plan.
-spec get_plan(pid()) -> {ok, execution_plan()} | {error, no_plan}.
get_plan(Agent) ->
    gen_server:call(Agent, get_plan).

%% @doc Get the final result.
-spec get_result(pid()) -> {ok, term()} | {error, term()}.
get_result(Agent) ->
    gen_server:call(Agent, get_result).

%% @doc Get the current agent status.
-spec get_status(pid()) -> map().
get_status(Agent) ->
    gen_server:call(Agent, get_status).

%% @doc Stop the deep agent.
-spec stop(pid()) -> ok.
stop(Agent) ->
    gen_server:stop(Agent, normal, 5000).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    Id = maps:get(id, Config, generate_id()),
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),
    SystemPrompt = maps:get(system_prompt, Config, default_planner_prompt()),
    MaxReplans = maps:get(max_replans, Config, ?DEFAULT_MAX_REPLANS),
    MaxDepth = maps:get(max_depth, Config, ?DEFAULT_MAX_DEPTH),

    State = #state{
        id = Id,
        kernel_ref = KernelRef,
        system_prompt = SystemPrompt,
        plan = undefined,
        goal = undefined,
        result = undefined,
        status = idle,
        replan_count = 0,
        max_replans = MaxReplans,
        max_depth = MaxDepth,
        current_depth = 0,
        execution_log = [],
        config = Config,
        metadata = #{created_at => erlang:system_time(millisecond)}
    },
    logger:info("BeamAI DeepAgent ~s created", [Id]),
    {ok, State}.

%% @private
handle_call({plan, Goal}, _From, State) ->
    NewState = State#state{goal = Goal, status = planning},
    case do_plan(Goal, NewState) of
        {ok, Plan, PlanState} ->
            {reply, {ok, Plan}, PlanState};
        {error, Reason, ErrState} ->
            {reply, {error, Reason}, ErrState#state{status = failed}}
    end;

handle_call({execute, auto}, _From, #state{plan = undefined} = State) ->
    {reply, {error, no_plan}, State};
handle_call({execute, auto}, _From, #state{plan = Plan} = State) ->
    NewState = State#state{status = executing},
    case do_execute(Plan, NewState) of
        {ok, Results, ExecState} ->
            {reply, {ok, Results}, ExecState};
        {error, Reason, ErrState} ->
            {reply, {error, Reason}, ErrState#state{status = failed}}
    end;
handle_call({execute, Plan}, _From, State) when is_map(Plan) ->
    NewState = State#state{plan = Plan, status = executing},
    case do_execute(Plan, NewState) of
        {ok, Results, ExecState} ->
            {reply, {ok, Results}, ExecState};
        {error, Reason, ErrState} ->
            {reply, {error, Reason}, ErrState#state{status = failed}}
    end;

handle_call({reflect, Results}, _From, State) ->
    NewState = State#state{status = reflecting},
    case do_reflect(Results, NewState) of
        {ok, Reflection, RefState} ->
            {reply, {ok, Reflection}, RefState};
        {error, Reason, ErrState} ->
            {reply, {error, Reason}, ErrState}
    end;

handle_call({run, Goal}, From, State) ->
    NewState = State#state{goal = Goal, status = planning},
    %% Run the full cycle asynchronously
    Self = self(),
    spawn_link(fun() ->
        Result = do_full_run(Goal, NewState),
        gen_server:cast(Self, {run_complete, From, Result})
    end),
    {noreply, NewState};

handle_call(get_plan, _From, #state{plan = undefined} = State) ->
    {reply, {error, no_plan}, State};
handle_call(get_plan, _From, #state{plan = Plan} = State) ->
    {reply, {ok, Plan}, State};

handle_call(get_result, _From, #state{result = undefined} = State) ->
    {reply, {error, no_result}, State};
handle_call(get_result, _From, #state{result = Result} = State) ->
    {reply, {ok, Result}, State};

handle_call(get_status, _From, State) ->
    #state{id = Id, status = Status, replan_count = ReplanCount,
           plan = Plan, goal = Goal, current_depth = Depth} = State,
    StatusMap = #{
        id => Id,
        status => Status,
        goal => Goal,
        replan_count => ReplanCount,
        current_depth => Depth,
        has_plan => Plan =/= undefined,
        plan_steps => case Plan of
            undefined -> 0;
            #{steps := Steps} -> length(Steps)
        end,
        execution_log_size => length(State#state.execution_log)
    },
    {reply, StatusMap, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({run_complete, From, {ok, Result, FinalState}}, _State) ->
    gen_server:reply(From, {ok, Result}),
    {noreply, FinalState#state{result = Result, status = completed}};
handle_cast({run_complete, From, {error, Reason, FinalState}}, _State) ->
    gen_server:reply(From, {error, Reason}),
    {noreply, FinalState#state{status = failed}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Run the full Planner -> Executor -> Reflector cycle.
-spec do_full_run(binary(), #state{}) ->
    {ok, term(), #state{}} | {error, term(), #state{}}.
do_full_run(Goal, State) ->
    %% Phase 1: Plan
    case do_plan(Goal, State) of
        {ok, Plan, PlanState} ->
            %% Phase 2: Execute
            case do_execute(Plan, PlanState#state{status = executing}) of
                {ok, Results, ExecState} ->
                    %% Phase 3: Reflect
                    case do_reflect(Results, ExecState#state{status = reflecting}) of
                        {ok, #{<<"accepted">> := true, <<"summary">> := Summary}, RefState} ->
                            {ok, Summary, RefState};
                        {ok, #{<<"accepted">> := false, <<"reason">> := Reason}, RefState} ->
                            %% Reflection says results are not satisfactory
                            maybe_replan(Goal, Reason, Results, RefState);
                        {ok, Reflection, RefState} ->
                            %% Check if accepted (default to true)
                            Accepted = maps:get(<<"accepted">>, Reflection, true),
                            case Accepted of
                                true ->
                                    Summary = maps:get(<<"summary">>, Reflection,
                                                       format_results(Results)),
                                    {ok, Summary, RefState};
                                false ->
                                    Reason = maps:get(<<"reason">>, Reflection, <<"Reflection rejected">>),
                                    maybe_replan(Goal, Reason, Results, RefState)
                            end;
                        {error, Reason, ErrState} ->
                            %% Reflection failed, use execution results
                            logger:warning("Reflection failed: ~p, using execution results", [Reason]),
                            {ok, format_results(Results), ErrState}
                    end;
                {error, Reason, ErrState} ->
                    maybe_replan(Goal, Reason, #{}, ErrState)
            end;
        {error, Reason, ErrState} ->
            {error, {planning_failed, Reason}, ErrState}
    end.

%% @private Maybe attempt to replan if we haven't exceeded the max.
-spec maybe_replan(binary(), term(), map(), #state{}) ->
    {ok, term(), #state{}} | {error, term(), #state{}}.
maybe_replan(Goal, _Reason, _Results, #state{replan_count = Count, max_replans = Max} = State)
  when Count >= Max ->
    {error, {max_replans_exceeded, Count}, State};
maybe_replan(Goal, Reason, PrevResults, State) ->
    #state{replan_count = Count} = State,
    logger:info("DeepAgent replanning (attempt ~p): ~p", [Count + 1, Reason]),
    NewState = State#state{
        replan_count = Count + 1,
        status = planning
    },
    %% Add context about the failure to help the planner
    EnhancedGoal = iolist_to_binary([
        Goal, <<"\n\nPrevious attempt failed: ">>,
        ensure_binary(Reason),
        <<"\nPrevious results: ">>,
        ensure_binary(format_results(PrevResults)),
        <<"\nPlease create an improved plan.">>
    ]),
    do_full_run(EnhancedGoal, NewState).

%% @private Create an execution plan using the LLM.
-spec do_plan(binary(), #state{}) ->
    {ok, execution_plan(), #state{}} | {error, term(), #state{}}.
do_plan(Goal, #state{kernel_ref = KernelRef, system_prompt = SystemPrompt} = State) ->
    PlanPrompt = iolist_to_binary([
        SystemPrompt,
        <<"\n\nCreate a detailed execution plan for the following goal:\n">>,
        Goal,
        <<"\n\nRespond with a JSON object containing:\n">>,
        <<"{\"steps\": [{\"id\": \"step_1\", \"description\": \"...\", ">>,
        <<"\"type\": \"tool_call|llm_call|sub_plan\", ">>,
        <<"\"tool\": \"tool_name\", \"args\": {}, \"depends_on\": []}]}\n">>,
        <<"Only include the JSON object, no other text.">>
    ]),
    try
        case beamai_kernel:chat(KernelRef, PlanPrompt, #{}) of
            {ok, Response} ->
                Plan = parse_plan_response(Goal, Response, State),
                LogEntry = #{
                    phase => planning,
                    goal => Goal,
                    plan => Plan,
                    timestamp => erlang:system_time(millisecond)
                },
                NewState = State#state{
                    plan = Plan,
                    status = planning,
                    execution_log = State#state.execution_log ++ [LogEntry]
                },
                {ok, Plan, NewState};
            {error, Reason} ->
                {error, {llm_planning_failed, Reason}, State}
        end
    catch
        _:Error ->
            {error, {planning_exception, Error}, State}
    end.

%% @private Execute a plan step by step.
-spec do_execute(execution_plan(), #state{}) ->
    {ok, map(), #state{}} | {error, term(), #state{}}.
do_execute(#{steps := Steps} = Plan, State) ->
    #state{kernel_ref = KernelRef} = State,
    ExecutingPlan = Plan#{status => executing},
    execute_plan_steps(Steps, #{}, KernelRef, State#state{plan = ExecutingPlan}).

%% @private Execute plan steps sequentially, respecting dependencies.
-spec execute_plan_steps([plan_step()], map(), atom() | pid(), #state{}) ->
    {ok, map(), #state{}} | {error, term(), #state{}}.
execute_plan_steps([], Results, _KernelRef, State) ->
    UpdatedPlan = (State#state.plan)#{status => completed},
    LogEntry = #{
        phase => execution,
        results => Results,
        timestamp => erlang:system_time(millisecond)
    },
    FinalState = State#state{
        plan = UpdatedPlan,
        execution_log = State#state.execution_log ++ [LogEntry]
    },
    {ok, Results, FinalState};
execute_plan_steps([Step | Rest], Results, KernelRef, State) ->
    StepId = maps:get(id, Step, <<"unknown">>),
    DependsOn = maps:get(depends_on, Step, []),

    %% Check dependencies
    DepsResolved = lists:all(fun(DepId) -> maps:is_key(DepId, Results) end, DependsOn),
    case DepsResolved of
        true ->
            case execute_plan_step(Step, Results, KernelRef, State) of
                {ok, StepResult} ->
                    NewResults = maps:put(StepId, StepResult, Results),
                    execute_plan_steps(Rest, NewResults, KernelRef, State);
                {error, Reason} ->
                    %% Mark step as failed and continue to report
                    NewResults = maps:put(StepId, {error, Reason}, Results),
                    {error, {step_failed, StepId, Reason}, State}
            end;
        false ->
            MissingDeps = [D || D <- DependsOn, not maps:is_key(D, Results)],
            {error, {unmet_dependencies, StepId, MissingDeps}, State}
    end.

%% @private Execute a single plan step.
-spec execute_plan_step(plan_step(), map(), atom() | pid(), #state{}) ->
    {ok, term()} | {error, term()}.
execute_plan_step(#{type := <<"tool_call">>} = Step, Results, KernelRef, _State) ->
    ToolName = maps:get(tool, Step, maps:get(<<"tool">>, Step, <<>>)),
    BaseArgs = maps:get(args, Step, maps:get(<<"args">>, Step, #{})),
    %% Inject dependency results into args
    Args = maps:put(<<"_context">>, Results, BaseArgs),
    try beamai_kernel:invoke_tool(KernelRef, ToolName, Args, #{})
    catch _:Reason -> {error, {tool_call_failed, ToolName, Reason}}
    end;
execute_plan_step(#{type := tool_call} = Step, Results, KernelRef, State) ->
    execute_plan_step(Step#{type => <<"tool_call">>}, Results, KernelRef, State);

execute_plan_step(#{type := <<"llm_call">>} = Step, Results, KernelRef, _State) ->
    Description = maps:get(description, Step, maps:get(<<"description">>, Step, <<>>)),
    Args = maps:get(args, Step, maps:get(<<"args">>, Step, #{})),
    Prompt = case maps:find(<<"prompt">>, Args) of
        {ok, P} -> P;
        error ->
            iolist_to_binary([
                Description,
                <<"\n\nContext from previous steps: ">>,
                jsx:encode(Results)
            ])
    end,
    try beamai_kernel:chat(KernelRef, Prompt, #{})
    catch _:Reason -> {error, {llm_call_failed, Reason}}
    end;
execute_plan_step(#{type := llm_call} = Step, Results, KernelRef, State) ->
    execute_plan_step(Step#{type => <<"llm_call">>}, Results, KernelRef, State);

execute_plan_step(#{type := <<"sub_plan">>} = Step, Results, _KernelRef,
                  #state{current_depth = Depth, max_depth = MaxDepth} = State) ->
    case Depth >= MaxDepth of
        true ->
            {error, {max_depth_exceeded, Depth}};
        false ->
            %% Create a sub-agent for the sub-plan
            SubGoal = maps:get(description, Step, maps:get(<<"description">>, Step, <<>>)),
            SubConfig = (State#state.config)#{
                id => generate_id(),
                max_depth => MaxDepth
            },
            case new(SubConfig) of
                {ok, SubAgent} ->
                    try
                        Result = run(SubAgent, SubGoal),
                        stop(SubAgent),
                        Result
                    catch
                        _:SubErr ->
                            stop(SubAgent),
                            {error, {sub_plan_failed, SubErr}}
                    end;
                {error, Reason} ->
                    {error, {sub_agent_failed, Reason}}
            end
    end;
execute_plan_step(#{type := sub_plan} = Step, Results, KernelRef, State) ->
    execute_plan_step(Step#{type => <<"sub_plan">>}, Results, KernelRef, State);

execute_plan_step(Step, _Results, _KernelRef, _State) ->
    Description = maps:get(description, Step, maps:get(<<"description">>, Step, <<"unknown step">>)),
    {ok, #{step => Description, result => <<"completed (no handler)">>}}.

%% @private Reflect on execution results using the LLM.
-spec do_reflect(map(), #state{}) ->
    {ok, map(), #state{}} | {error, term(), #state{}}.
do_reflect(Results, #state{kernel_ref = KernelRef, goal = Goal} = State) ->
    ReflectionPrompt = iolist_to_binary([
        <<"You are evaluating the results of an execution plan.\n\n">>,
        <<"Original goal: ">>, ensure_binary(Goal),
        <<"\n\nExecution results:\n">>,
        jsx:encode(Results),
        <<"\n\nEvaluate whether the results satisfy the original goal. ">>,
        <<"Respond with a JSON object:\n">>,
        <<"{\"accepted\": true/false, \"reason\": \"explanation\", ">>,
        <<"\"summary\": \"concise result summary\", ">>,
        <<"\"improvements\": [\"suggested improvements if not accepted\"]}\n">>,
        <<"Only include the JSON object, no other text.">>
    ]),
    try
        case beamai_kernel:chat(KernelRef, ReflectionPrompt, #{}) of
            {ok, Response} ->
                Reflection = parse_reflection_response(Response),
                LogEntry = #{
                    phase => reflection,
                    results => Results,
                    reflection => Reflection,
                    timestamp => erlang:system_time(millisecond)
                },
                NewState = State#state{
                    status = reflecting,
                    execution_log = State#state.execution_log ++ [LogEntry]
                },
                {ok, Reflection, NewState};
            {error, Reason} ->
                {error, {reflection_failed, Reason}, State}
        end
    catch
        _:Error ->
            {error, {reflection_exception, Error}, State}
    end.

%% @private Parse the LLM planning response into a plan structure.
-spec parse_plan_response(binary(), binary(), #state{}) -> execution_plan().
parse_plan_response(Goal, Response, _State) ->
    Steps = try
        %% Try to extract JSON from the response
        JsonBin = extract_json(Response),
        Decoded = jsx:decode(JsonBin, [return_maps]),
        RawSteps = maps:get(<<"steps">>, Decoded, []),
        lists:map(fun(RawStep) ->
            #{
                id => maps:get(<<"id">>, RawStep, generate_step_id()),
                description => maps:get(<<"description">>, RawStep, <<>>),
                type => normalize_step_type(maps:get(<<"type">>, RawStep, <<"llm_call">>)),
                tool => maps:get(<<"tool">>, RawStep, undefined),
                args => maps:get(<<"args">>, RawStep, #{}),
                depends_on => maps:get(<<"depends_on">>, RawStep, []),
                status => pending
            }
        end, RawSteps)
    catch
        _:_ ->
            %% Failed to parse, create a single-step plan
            [#{
                id => <<"step_1">>,
                description => Goal,
                type => <<"llm_call">>,
                args => #{<<"prompt">> => Goal},
                depends_on => [],
                status => pending
            }]
    end,
    #{
        goal => Goal,
        steps => Steps,
        created_at => erlang:system_time(millisecond),
        version => 1,
        status => pending
    }.

%% @private Parse the LLM reflection response.
-spec parse_reflection_response(binary()) -> map().
parse_reflection_response(Response) ->
    try
        JsonBin = extract_json(Response),
        jsx:decode(JsonBin, [return_maps])
    catch
        _:_ ->
            %% Failed to parse, assume accepted
            #{
                <<"accepted">> => true,
                <<"reason">> => <<"Could not parse reflection, accepting by default">>,
                <<"summary">> => Response
            }
    end.

%% @private Extract a JSON object from a potentially mixed text response.
-spec extract_json(binary()) -> binary().
extract_json(Text) ->
    %% Find the first { and last } to extract JSON
    case binary:match(Text, <<"{">>) of
        {Start, _} ->
            Rest = binary:part(Text, Start, byte_size(Text) - Start),
            %% Find the matching closing brace
            find_closing_brace(Rest, 0, 0);
        nomatch ->
            Text
    end.

%% @private Find the matching closing brace for JSON extraction.
-spec find_closing_brace(binary(), non_neg_integer(), non_neg_integer()) -> binary().
find_closing_brace(<<>>, _Depth, _Pos) ->
    <<"{}">>;
find_closing_brace(<<${, Rest/binary>>, Depth, Pos) ->
    find_closing_brace(Rest, Depth + 1, Pos + 1);
find_closing_brace(<<$}, Rest/binary>>, 1, Pos) ->
    %% Found matching closing brace
    binary:part(<<${, (binary:part(<<${, Rest/binary>>, 0, Pos + 1))/binary>>,
                0, Pos + 2);
find_closing_brace(<<$}, Rest/binary>>, Depth, Pos) when Depth > 1 ->
    find_closing_brace(Rest, Depth - 1, Pos + 1);
find_closing_brace(<<_, Rest/binary>>, Depth, Pos) ->
    find_closing_brace(Rest, Depth, Pos + 1).

%% @private Normalize step type from string to expected format.
-spec normalize_step_type(binary() | atom()) -> binary().
normalize_step_type(<<"tool_call">>) -> <<"tool_call">>;
normalize_step_type(<<"llm_call">>) -> <<"llm_call">>;
normalize_step_type(<<"sub_plan">>) -> <<"sub_plan">>;
normalize_step_type(<<"agent_call">>) -> <<"agent_call">>;
normalize_step_type(tool_call) -> <<"tool_call">>;
normalize_step_type(llm_call) -> <<"llm_call">>;
normalize_step_type(sub_plan) -> <<"sub_plan">>;
normalize_step_type(_) -> <<"llm_call">>.

%% @private Format results for display.
-spec format_results(map()) -> binary().
format_results(Results) when is_map(Results) ->
    try jsx:encode(Results)
    catch _:_ -> iolist_to_binary(io_lib:format("~p", [Results]))
    end;
format_results(Results) ->
    iolist_to_binary(io_lib:format("~p", [Results])).

%% @private Generate a unique identifier.
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"deep-", Hex/binary>>.

%% @private Generate a step identifier.
-spec generate_step_id() -> binary().
generate_step_id() ->
    Bytes = crypto:strong_rand_bytes(4),
    Hex = binary:encode_hex(Bytes),
    <<"s-", Hex/binary>>.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) when is_integer(V) -> integer_to_binary(V);
ensure_binary(undefined) -> <<"undefined">>;
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).

%% @private Default planner system prompt.
-spec default_planner_prompt() -> binary().
default_planner_prompt() ->
    <<"You are a planning agent. Your role is to decompose complex goals ",
      "into step-by-step execution plans. Each step should be specific, ",
      "actionable, and have clear dependencies. Use tool_call steps for ",
      "concrete actions, llm_call steps for reasoning/analysis, and ",
      "sub_plan steps for complex sub-goals that need their own planning.">>.
