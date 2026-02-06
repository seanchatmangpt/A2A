%%%-------------------------------------------------------------------
%%% @doc BeamAI Process Agent
%%%
%%% A process-based agent for executing multi-step workflows.
%%% Supports branching, parallel step execution, and result
%%% aggregation. Each process agent manages a pipeline of steps
%%% that can be sequential, parallel, or conditional.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_process_agent).

-behaviour(gen_server).

%% API
-export([
    new/1,
    execute/2,
    step/2,
    get_result/1,
    get_status/1,
    cancel/1,
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

-define(DEFAULT_STEP_TIMEOUT, 60000).

-type step_type() :: sequential | parallel | conditional | tool_call | llm_call.

-record(process_step, {
    id          :: binary(),
    type        :: step_type(),
    name        :: binary(),
    handler     :: fun() | {module(), atom()} | binary(),
    args        :: map(),
    depends_on  :: [binary()],
    condition   :: fun() | undefined,
    timeout     :: pos_integer(),
    status      :: pending | running | completed | failed | skipped,
    result      :: term(),
    error       :: term() | undefined,
    started_at  :: integer() | undefined,
    completed_at :: integer() | undefined
}).

-record(state, {
    id          :: binary(),
    name        :: binary(),
    steps       :: [#process_step{}],
    step_index  :: #{binary() => non_neg_integer()},
    current_step :: non_neg_integer(),
    kernel_ref  :: atom() | pid(),
    status      :: idle | running | completed | failed | cancelled,
    results     :: #{binary() => term()},
    config      :: map(),
    metadata    :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Create a new process agent.
%% Config:
%%   name - Process name
%%   steps - List of step definitions (maps)
%%   kernel_ref - BeamAI kernel reference
-spec new(map()) -> {ok, pid()} | {error, term()}.
new(Config) ->
    gen_server:start_link(?MODULE, Config, []).

%% @doc Execute the process with initial input data.
-spec execute(pid(), map()) -> {ok, map()} | {error, term()}.
execute(Agent, Input) ->
    gen_server:call(Agent, {execute, Input}, infinity).

%% @doc Execute a single step by ID.
-spec step(pid(), binary()) -> {ok, term()} | {error, term()}.
step(Agent, StepId) ->
    gen_server:call(Agent, {step, StepId}, ?DEFAULT_STEP_TIMEOUT).

%% @doc Get the final result of the process execution.
-spec get_result(pid()) -> {ok, map()} | {error, term()}.
get_result(Agent) ->
    gen_server:call(Agent, get_result).

%% @doc Get the current process status.
-spec get_status(pid()) -> map().
get_status(Agent) ->
    gen_server:call(Agent, get_status).

%% @doc Cancel the running process.
-spec cancel(pid()) -> ok.
cancel(Agent) ->
    gen_server:cast(Agent, cancel).

%% @doc Stop the process agent.
-spec stop(pid()) -> ok.
stop(Agent) ->
    gen_server:stop(Agent, normal, 5000).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    Id = maps:get(id, Config, generate_process_id()),
    Name = maps:get(name, Config, <<"unnamed_process">>),
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),
    StepDefs = maps:get(steps, Config, []),

    {Steps, StepIndex} = build_steps(StepDefs),

    State = #state{
        id = Id,
        name = Name,
        steps = Steps,
        step_index = StepIndex,
        current_step = 0,
        kernel_ref = KernelRef,
        status = idle,
        results = #{},
        config = Config,
        metadata = #{created_at => erlang:system_time(millisecond)}
    },
    {ok, State}.

%% @private
handle_call({execute, Input}, _From, #state{status = idle} = State) ->
    NewState = State#state{
        status = running,
        results = #{<<"_input">> => Input}
    },
    case execute_steps(NewState) of
        {ok, FinalState} ->
            FinalResults = FinalState#state.results,
            {reply, {ok, FinalResults}, FinalState#state{status = completed}};
        {error, Reason, ErrState} ->
            {reply, {error, Reason}, ErrState#state{status = failed}}
    end;

handle_call({execute, _Input}, _From, #state{status = Status} = State) ->
    {reply, {error, {invalid_status, Status}}, State};

handle_call({step, StepId}, _From, State) ->
    #state{step_index = Index, steps = Steps, kernel_ref = KernelRef, results = Results} = State,
    case maps:find(StepId, Index) of
        {ok, Idx} ->
            Step = lists:nth(Idx + 1, Steps),
            case execute_single_step(Step, Results, KernelRef) of
                {ok, Result, UpdatedStep} ->
                    NewSteps = replace_step(Steps, Idx, UpdatedStep),
                    NewResults = maps:put(StepId, Result, Results),
                    NewState = State#state{steps = NewSteps, results = NewResults},
                    {reply, {ok, Result}, NewState};
                {error, Reason, UpdatedStep} ->
                    NewSteps = replace_step(Steps, Idx, UpdatedStep),
                    {reply, {error, Reason}, State#state{steps = NewSteps}}
            end;
        error ->
            {reply, {error, {step_not_found, StepId}}, State}
    end;

handle_call(get_result, _From, #state{results = Results, status = Status} = State) ->
    case Status of
        completed -> {reply, {ok, Results}, State};
        failed -> {reply, {error, {process_failed, Results}}, State};
        _ -> {reply, {error, {process_not_complete, Status}}, State}
    end;

handle_call(get_status, _From, State) ->
    #state{id = Id, name = Name, status = Status, steps = Steps,
           current_step = CurrentStep} = State,
    StepStatuses = lists:map(fun(#process_step{id = SId, name = SName, status = SStatus}) ->
        #{id => SId, name => SName, status => SStatus}
    end, Steps),
    StatusMap = #{
        id => Id,
        name => Name,
        status => Status,
        current_step => CurrentStep,
        total_steps => length(Steps),
        steps => StepStatuses
    },
    {reply, StatusMap, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(cancel, State) ->
    logger:info("Process agent ~s cancelled", [State#state.id]),
    {noreply, State#state{status = cancelled}};

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

%% @private Build step records from step definition maps.
-spec build_steps([map()]) -> {[#process_step{}], #{binary() => non_neg_integer()}}.
build_steps(StepDefs) ->
    {Steps, Index, _} = lists:foldl(fun(Def, {Acc, Idx, N}) ->
        StepId = maps:get(id, Def, generate_step_id(N)),
        Step = #process_step{
            id = StepId,
            type = maps:get(type, Def, sequential),
            name = maps:get(name, Def, <<"step_", (integer_to_binary(N))/binary>>),
            handler = maps:get(handler, Def, fun(_) -> {ok, done} end),
            args = maps:get(args, Def, #{}),
            depends_on = maps:get(depends_on, Def, []),
            condition = maps:get(condition, Def, undefined),
            timeout = maps:get(timeout, Def, ?DEFAULT_STEP_TIMEOUT),
            status = pending,
            result = undefined,
            error = undefined,
            started_at = undefined,
            completed_at = undefined
        },
        {Acc ++ [Step], maps:put(StepId, N, Idx), N + 1}
    end, {[], #{}, 0}, StepDefs),
    {Steps, Index}.

%% @private Execute all steps in sequence, handling dependencies.
-spec execute_steps(#state{}) -> {ok, #state{}} | {error, term(), #state{}}.
execute_steps(#state{steps = Steps, kernel_ref = KernelRef, status = cancelled} = State) ->
    {error, cancelled, State};
execute_steps(#state{steps = Steps, kernel_ref = KernelRef, results = Results} = State) ->
    execute_steps_loop(Steps, 0, Results, KernelRef, State).

%% @private Loop through steps.
-spec execute_steps_loop([#process_step{}], non_neg_integer(), map(),
                         atom() | pid(), #state{}) ->
    {ok, #state{}} | {error, term(), #state{}}.
execute_steps_loop([], _Idx, Results, _KernelRef, State) ->
    {ok, State#state{results = Results}};
execute_steps_loop([Step | Rest], Idx, Results, KernelRef, State) ->
    case State#state.status of
        cancelled ->
            {error, cancelled, State};
        _ ->
            %% Check if dependencies are met
            case check_dependencies(Step, Results) of
                true ->
                    %% Check condition
                    case check_condition(Step, Results) of
                        true ->
                            case execute_single_step(Step, Results, KernelRef) of
                                {ok, Result, UpdatedStep} ->
                                    NewResults = maps:put(Step#process_step.id, Result, Results),
                                    NewSteps = replace_step(State#state.steps, Idx, UpdatedStep),
                                    NewState = State#state{
                                        steps = NewSteps,
                                        results = NewResults,
                                        current_step = Idx + 1
                                    },
                                    execute_steps_loop(Rest, Idx + 1, NewResults, KernelRef, NewState);
                                {error, Reason, UpdatedStep} ->
                                    NewSteps = replace_step(State#state.steps, Idx, UpdatedStep),
                                    {error, {step_failed, Step#process_step.id, Reason},
                                     State#state{steps = NewSteps}}
                            end;
                        false ->
                            %% Condition not met, skip step
                            SkippedStep = Step#process_step{status = skipped},
                            NewSteps = replace_step(State#state.steps, Idx, SkippedStep),
                            NewState = State#state{steps = NewSteps, current_step = Idx + 1},
                            execute_steps_loop(Rest, Idx + 1, Results, KernelRef, NewState)
                    end;
                false ->
                    {error, {unmet_dependencies, Step#process_step.id, Step#process_step.depends_on},
                     State}
            end
    end.

%% @private Execute a single process step.
-spec execute_single_step(#process_step{}, map(), atom() | pid()) ->
    {ok, term(), #process_step{}} | {error, term(), #process_step{}}.
execute_single_step(#process_step{type = Type, handler = Handler, args = Args} = Step,
                    Results, KernelRef) ->
    Now = erlang:system_time(millisecond),
    RunningStep = Step#process_step{status = running, started_at = Now},
    try
        %% Merge results into args for access to previous step outputs
        MergedArgs = maps:merge(Args, #{<<"_results">> => Results}),
        Result = case Type of
            tool_call ->
                ToolName = maps:get(tool_name, Args, maps:get(<<"tool_name">>, Args, <<>>)),
                ToolArgs = maps:get(tool_args, Args, maps:get(<<"tool_args">>, Args, #{})),
                beamai_kernel:invoke_tool(KernelRef, ToolName, ToolArgs, #{});
            llm_call ->
                Prompt = maps:get(prompt, Args, maps:get(<<"prompt">>, Args, <<>>)),
                beamai_kernel:chat(KernelRef, Prompt, #{});
            parallel ->
                execute_parallel_substeps(Handler, MergedArgs, KernelRef);
            _ ->
                execute_handler(Handler, MergedArgs, KernelRef)
        end,
        CompletedAt = erlang:system_time(millisecond),
        case Result of
            {ok, Value} ->
                CompletedStep = RunningStep#process_step{
                    status = completed,
                    result = Value,
                    completed_at = CompletedAt
                },
                {ok, Value, CompletedStep};
            {error, Reason} ->
                FailedStep = RunningStep#process_step{
                    status = failed,
                    error = Reason,
                    completed_at = CompletedAt
                },
                {error, Reason, FailedStep};
            Other ->
                CompletedStep = RunningStep#process_step{
                    status = completed,
                    result = Other,
                    completed_at = CompletedAt
                },
                {ok, Other, CompletedStep}
        end
    catch
        Class:Reason:_Stack ->
            FailedStep = RunningStep#process_step{
                status = failed,
                error = {Class, Reason},
                completed_at = erlang:system_time(millisecond)
            },
            {error, {Class, Reason}, FailedStep}
    end.

%% @private Execute a step handler.
-spec execute_handler(fun() | {module(), atom()} | binary(), map(), atom() | pid()) -> term().
execute_handler(Fun, Args, _KernelRef) when is_function(Fun, 1) ->
    Fun(Args);
execute_handler(Fun, Args, KernelRef) when is_function(Fun, 2) ->
    Fun(Args, KernelRef);
execute_handler({Module, Function}, Args, _KernelRef) ->
    Module:Function(Args);
execute_handler(ToolName, Args, KernelRef) when is_binary(ToolName) ->
    beamai_kernel:invoke_tool(KernelRef, ToolName, Args, #{}).

%% @private Execute parallel substeps.
-spec execute_parallel_substeps(term(), map(), atom() | pid()) -> {ok, [term()]}.
execute_parallel_substeps(SubHandlers, Args, KernelRef) when is_list(SubHandlers) ->
    Parent = self(),
    Refs = lists:map(fun(Handler) ->
        Ref = make_ref(),
        spawn_link(fun() ->
            Result = execute_handler(Handler, Args, KernelRef),
            Parent ! {parallel_result, Ref, Result}
        end),
        Ref
    end, SubHandlers),
    Results = collect_parallel_results(Refs, []),
    {ok, Results};
execute_parallel_substeps(_Handler, Args, KernelRef) ->
    %% Not a list of handlers, execute as single
    execute_handler(fun(_) -> ok end, Args, KernelRef).

%% @private Collect results from parallel step execution.
-spec collect_parallel_results([reference()], [term()]) -> [term()].
collect_parallel_results([], Acc) ->
    lists:reverse(Acc);
collect_parallel_results([Ref | Rest], Acc) ->
    receive
        {parallel_result, Ref, Result} ->
            collect_parallel_results(Rest, [Result | Acc])
    after ?DEFAULT_STEP_TIMEOUT ->
        collect_parallel_results(Rest, [{error, timeout} | Acc])
    end.

%% @private Check if all dependencies for a step are met.
-spec check_dependencies(#process_step{}, map()) -> boolean().
check_dependencies(#process_step{depends_on = []}, _Results) ->
    true;
check_dependencies(#process_step{depends_on = Deps}, Results) ->
    lists:all(fun(DepId) -> maps:is_key(DepId, Results) end, Deps).

%% @private Check if a step's condition is met.
-spec check_condition(#process_step{}, map()) -> boolean().
check_condition(#process_step{condition = undefined}, _Results) ->
    true;
check_condition(#process_step{condition = CondFun}, Results) when is_function(CondFun, 1) ->
    try CondFun(Results)
    catch _:_ -> false
    end;
check_condition(_, _) ->
    true.

%% @private Replace a step in the step list by index.
-spec replace_step([#process_step{}], non_neg_integer(), #process_step{}) -> [#process_step{}].
replace_step(Steps, Idx, NewStep) ->
    {Before, [_ | After]} = lists:split(Idx, Steps),
    Before ++ [NewStep | After].

%% @private Generate a unique process identifier.
-spec generate_process_id() -> binary().
generate_process_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"proc-", Hex/binary>>.

%% @private Generate a step identifier.
-spec generate_step_id(non_neg_integer()) -> binary().
generate_step_id(N) ->
    <<"step-", (integer_to_binary(N))/binary>>.
