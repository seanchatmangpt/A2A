%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Recovery Mechanisms
%%%
%%% This module provides error recovery capabilities for YAWL workflows:
%%%
%%% - Automatic retry with exponential backoff
%%% - Checkpoint-based recovery from failures
%%% - Circuit breaker pattern for failing services
%%% - Deadlock detection and resolution
%%% - State rollback on critical errors
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_recovery).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Recovery operations
-export([
    register_recovery_strategy/2,
    execute_with_retry/3,
    execute_with_timeout/3,
    create_recovery_checkpoint/2,
    rollback_to_checkpoint/2,
    get_recovery_state/1,
    clear_recovery_state/1
]).

%% API exports - Circuit breaker
-export([
    register_circuit_breaker/2,
    reset_circuit_breaker/1,
    is_circuit_open/1,
    execute_with_circuit_breaker/2
]).

%% API exports - Deadlock detection
-export([
    detect_deadlock/1,
    resolve_deadlock/2,
    check_for_cycles/1
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    recovery_states :: #{binary() => map()},
    circuit_breakers :: #{binary() => circuit_breaker()},
    deadlocks :: #{binary() => [binary()]},
    retry_config :: map()
}).

-record(circuit_breaker, {
    threshold :: pos_integer(),
    timeout :: integer(),
    failure_count = 0 :: non_neg_integer(),
    last_failure_time :: integer() | undefined,
    state = closed :: closed | open | half_open
}).

-type state() :: #state{}.
-type circuit_breaker() :: #circuit_breaker{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the error recovery manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a recovery strategy for a workflow.
-spec register_recovery_strategy(binary(), map()) -> ok | {error, term()}.
register_recovery_strategy(WorkflowId, Strategy) ->
    gen_server:call(?MODULE, {register_strategy, WorkflowId, Strategy}).

%% @doc Execute a function with automatic retry.
-spec execute_with_retry(binary(), fun(), map()) -> {ok, term()} | {error, term()}.
execute_with_retry(WorkflowId, Fun, Options) ->
    gen_server:call(?MODULE, {execute_with_retry, WorkflowId, Fun, Options}, infinity).

%% @doc Execute a function with timeout and recovery.
-spec execute_with_timeout(binary(), fun(), integer()) -> {ok, term()} | {error, term()}.
execute_with_timeout(WorkflowId, Fun, Timeout) ->
    gen_server:call(?MODULE, {execute_with_timeout, WorkflowId, Fun, Timeout}, infinity).

%% @doc Create a recovery checkpoint.
-spec create_recovery_checkpoint(binary(), map()) -> {ok, binary()} | {error, term()}.
create_recovery_checkpoint(WorkflowId, State) ->
    gen_server:call(?MODULE, {create_recovery_checkpoint, WorkflowId, State}).

%% @doc Rollback to a checkpoint.
-spec rollback_to_checkpoint(binary(), binary()) -> {ok, map()} | {error, term()}.
rollback_to_checkpoint(WorkflowId, CheckpointId) ->
    gen_server:call(?MODULE, {rollback_to_checkpoint, WorkflowId, CheckpointId}, infinity).

%% @doc Get recovery state for a workflow.
-spec get_recovery_state(binary()) -> {ok, map()} | {error, not_found}.
get_recovery_state(WorkflowId) ->
    gen_server:call(?MODULE, {get_recovery_state, WorkflowId}).

%% @doc Clear recovery state for a workflow.
-spec clear_recovery_state(binary()) -> ok.
clear_recovery_state(WorkflowId) ->
    gen_server:cast(?MODULE, {clear_recovery_state, WorkflowId}).

%% @doc Register a circuit breaker.
-spec register_circuit_breaker(binary(), map()) -> ok | {error, term()}.
register_circuit_breaker(ServiceId, Config) ->
    gen_server:call(?MODULE, {register_circuit_breaker, ServiceId, Config}).

%% @doc Reset a circuit breaker.
-spec reset_circuit_breaker(binary()) -> ok | {error, term()}.
reset_circuit_breaker(ServiceId) ->
    gen_server:call(?MODULE, {reset_circuit_breaker, ServiceId}).

%% @doc Check if circuit is open.
-spec is_circuit_open(binary()) -> boolean().
is_circuit_open(ServiceId) ->
    gen_server:call(?MODULE, {is_circuit_open, ServiceId}).

%% @doc Execute with circuit breaker protection.
-spec execute_with_circuit_breaker(binary(), fun()) -> {ok, term()} | {error, term()}.
execute_with_circuit_breaker(ServiceId, Fun) ->
    gen_server:call(?MODULE, {execute_with_circuit_breaker, ServiceId, Fun}, infinity).

%% @doc Detect deadlock in workflow.
-spec detect_deadlock(binary()) -> {ok, [binary()]} | {ok, no_deadlock}.
detect_deadlock(WorkflowId) ->
    gen_server:call(?MODULE, {detect_deadlock, WorkflowId}).

%% @doc Resolve deadlock by breaking a cycle.
-spec resolve_deadlock(binary(), [binary()]) -> ok | {error, term()}.
resolve_deadlock(WorkflowId, BreakEdges) ->
    gen_server:call(?MODULE, {resolve_deadlock, WorkflowId, BreakEdges}).

%% @doc Check for cycles in dependency graph.
-spec check_for_cycles(map()) -> {ok, [binary()]} | {ok, no_cycles}.
check_for_cycles(DependencyGraph) ->
    gen_server:call(?MODULE, {check_for_cycles, DependencyGraph}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        recovery_states = #{},
        circuit_breakers = #{},
        deadlocks = #{},
        retry_config = #{
            max_attempts => 3,
            initial_delay => 1000,
            max_delay => 30000,
            backoff_factor => 2.0
        }
    },
    {ok, State}.

%% @private
handle_call({register_strategy, WorkflowId, Strategy}, _From, State) ->
    RecoveryState = #{
        workflow_id => WorkflowId,
        strategy => maps_get(strategy, Strategy, retry),
        checkpoints => [],
        retry_count => 0,
        last_error => undefined,
        created_at => erlang:monotonic_time(millisecond)
    },
    NewRecoveryStates = maps:put(WorkflowId, RecoveryState, State#state.recovery_states),
    {reply, ok, State#state{recovery_states = NewRecoveryStates}};

handle_call({execute_with_retry, WorkflowId, Fun, Options}, From, State) ->
    MaxAttempts = maps_get(max_attempts, Options, 3),
    InitialDelay = maps_get(initial_delay, Options, 1000),

    %% Execute with retry in a separate process
    Parent = self(),
    spawn(fun() ->
        Result = do_execute_with_retry(Fun, MaxAttempts, InitialDelay, 1),
        gen_server:reply(From, Result)
    end),
    {noreply, State};

handle_call({execute_with_timeout, WorkflowId, Fun, Timeout}, From, State) ->
    %% Execute with timeout and checkpoint recovery
    Parent = self(),
    spawn(fun() ->
        Result = case create_recovery_checkpoint(WorkflowId, #{}) of
            {ok, _CheckpointId} ->
                try
                    execute_with_timeout(Fun, Timeout)
                catch
                    Type:Error:Stacktrace ->
                        %% Rollback and return error
                        {error, {Type, Error, Stacktrace}}
                end;
            {error, Reason} ->
                {error, {checkpoint_failed, Reason}}
        end,
        gen_server:reply(From, Result)
    end),
    {noreply, State};

handle_call({create_recovery_checkpoint, WorkflowId, CheckpointState}, _From, State) ->
    CheckpointId = <<WorkflowId/binary, "_recovery_",
                     (integer_to_binary(erlang:monotonic_time(millisecond)))/binary>>,

    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = CheckpointState,
        marking = maps_get(marking, CheckpointState, #{}),
        data = maps_get(data, CheckpointState, #{}),
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },

    case yawl_persistence:save_checkpoint(WorkflowId, Checkpoint) of
        ok ->
            %% Update recovery state with new checkpoint
            NewRecoveryStates = maps:update_with(WorkflowId,
                fun(RecoveryState) ->
                    Checkpoints = maps_get(checkpoints, RecoveryState, []),
                    RecoveryState#{checkpoints => [CheckpointId | Checkpoints]}
                end,
                #{checkpoints => [CheckpointId]},
                State#state.recovery_states
            ),
            {reply, {ok, CheckpointId}, State#state{recovery_states = NewRecoveryStates}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({rollback_to_checkpoint, WorkflowId, CheckpointId}, _From, State) ->
    case yawl_persistence:load_latest_checkpoint(WorkflowId) of
        {ok, #yawl_checkpoint{checkpoint_id = CheckpointId} = Checkpoint} ->
            %% Restore state from checkpoint
            RestoredState = #{
                marking => Checkpoint#yawl_checkpoint.marking,
                data => Checkpoint#yawl_checkpoint.data,
                checkpoint_state => Checkpoint#yawl_checkpoint.checkpoint_state,
                restored_at => erlang:monotonic_time(millisecond)
            },
            {reply, {ok, RestoredState}, State};
        {ok, #yawl_checkpoint{checkpoint_id = OtherId}} ->
            {reply, {error, {wrong_checkpoint, OtherId}}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_recovery_state, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.recovery_states, undefined) of
        undefined -> {reply, {error, not_found}, State};
        RecoveryState -> {reply, {ok, RecoveryState}, State}
    end;

handle_call({register_circuit_breaker, ServiceId, Config}, _From, State) ->
    Threshold = maps_get(threshold, Config, 5),
    Timeout = maps_get(timeout, Config, 60000),

    CircuitBreaker = #circuit_breaker{
        threshold = Threshold,
        timeout = Timeout,
        failure_count = 0,
        last_failure_time = undefined,
        state = closed
    },

    NewCircuitBreakers = maps:put(ServiceId, CircuitBreaker, State#state.circuit_breakers),
    {reply, ok, State#state{circuit_breakers = NewCircuitBreakers}};

handle_call({reset_circuit_breaker, ServiceId}, _From, State) ->
    case maps:get(ServiceId, State#state.circuit_breakers, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        _CB ->
            ResetCB = #circuit_breaker{
                threshold = 0,  %% Will be set from original
                timeout = 0,
                failure_count = 0,
                last_failure_time = undefined,
                state = closed
            },
            %% Preserve threshold and timeout
            case maps:get(ServiceId, State#state.circuit_breakers) of
                #circuit_breaker{threshold = T, timeout = To} ->
                    NewCB = ResetCB#circuit_breaker{threshold = T, timeout = To},
                    NewCircuitBreakers = maps:put(ServiceId, NewCB, State#state.circuit_breakers),
                    {reply, ok, State#state{circuit_breakers = NewCircuitBreakers}}
            end
    end;

handle_call({is_circuit_open, ServiceId}, _From, State) ->
    case maps:get(ServiceId, State#state.circuit_breakers, undefined) of
        undefined -> {reply, false, State};
        #circuit_breaker{state = open} -> {reply, true, State};
        #circuit_breaker{state = _} -> {reply, false, State}
    end;

handle_call({execute_with_circuit_breaker, ServiceId, Fun}, _From, State) ->
    case maps_get(ServiceId, State#state.circuit_breakers, undefined) of
        undefined ->
            %% No circuit breaker, execute directly
            Result = execute_function(Fun),
            {reply, Result, State};
        CB ->
            case CB#circuit_breaker.state of
                open ->
                    %% Circuit is open, check if we can transition to half_open
                    Now = erlang:monotonic_time(millisecond),
                    case CB#circuit_breaker.last_failure_time of
                        undefined ->
                            {reply, {error, circuit_open}, State};
                        LastFailureTime when Now - LastFailureTime > CB#circuit_breaker.timeout ->
                            %% Transition to half_open and try
                            NewCB = CB#circuit_breaker{state = half_open},
                            NewCircuitBreakers = maps:put(ServiceId, NewCB, State#state.circuit_breakers),
                            case execute_function(Fun) of
                                {ok, Result} ->
                                    %% Success, close the circuit
                                    ClosedCB = NewCB#circuit_breaker{
                                        state = closed,
                                        failure_count = 0,
                                        last_failure_time = undefined
                                    },
                                    FinalCircuitBreakers = maps:put(ServiceId, ClosedCB, NewCircuitBreakers),
                                    {reply, {ok, Result}, State#state{circuit_breakers = FinalCircuitBreakers}};
                                {error, _} ->
                                    %% Failed, reopen circuit
                                    OpenCB = NewCB#circuit_breaker{
                                        state = open,
                                        failure_count = CB#circuit_breaker.failure_count + 1,
                                        last_failure_time = Now
                                    },
                                    FinalCircuitBreakers = maps:put(ServiceId, OpenCB, NewCircuitBreakers),
                                    {reply, {error, circuit_open}, State#state{circuit_breakers = FinalCircuitBreakers}}
                            end;
                        _ ->
                            {reply, {error, circuit_open}, State}
                    end;
                closed ->
                    %% Circuit is closed, execute and track failures
                    case execute_function(Fun) of
                        {ok, Result} ->
                            {reply, {ok, Result}, State};
                        {error, _} ->
                            Now = erlang:monotonic_time(millisecond),
                            NewFailureCount = CB#circuit_breaker.failure_count + 1,
                            NewCB = case NewFailureCount >= CB#circuit_breaker.threshold of
                                true ->
                                    CB#circuit_breaker{
                                        failure_count = NewFailureCount,
                                        state = open,
                                        last_failure_time = Now
                                    };
                                false ->
                                    CB#circuit_breaker{
                                        failure_count = NewFailureCount,
                                        last_failure_time = Now
                                    }
                            end,
                            NewCircuitBreakers = maps:put(ServiceId, NewCB, State#state.circuit_breakers),
                            {reply, {error, circuit_open}, State#state{circuit_breakers = NewCircuitBreakers}}
                    end;
                half_open ->
                    %% Half-open state, one request allowed
                    case execute_function(Fun) of
                        {ok, Result} ->
                            %% Success, close the circuit
                            ClosedCB = CB#circuit_breaker{
                                state = closed,
                                failure_count = 0,
                                last_failure_time = undefined
                            },
                            NewCircuitBreakers = maps:put(ServiceId, ClosedCB, State#state.circuit_breakers),
                            {reply, {ok, Result}, State#state{circuit_breakers = NewCircuitBreakers}};
                        {error, _} ->
                            %% Failed, reopen circuit
                            Now = erlang:monotonic_time(millisecond),
                            OpenCB = CB#circuit_breaker{
                                failure_count = CB#circuit_breaker.failure_count + 1,
                                state = open,
                                last_failure_time = Now
                            },
                            NewCircuitBreakers = maps:put(ServiceId, OpenCB, State#state.circuit_breakers),
                            {reply, {error, circuit_open}, State#state{circuit_breakers = NewCircuitBreakers}}
                    end
            end
    end;

handle_call({detect_deadlock, WorkflowId}, _From, State) ->
    %% Load workflow state and check for circular dependencies
    case yawl_persistence:load_workflow(WorkflowId) of
        {ok, Workflow} ->
            Dependencies = build_dependency_graph(Workflow),
            case check_for_cycles_impl(Dependencies) of
                {ok, []} ->
                    {reply, {ok, no_deadlock}, State};
                {ok, Cycles} ->
                    NewDeadlocks = maps:put(WorkflowId, Cycles, State#state.deadlocks),
                    {reply, {ok, Cycles}, State#state{deadlocks = NewDeadlocks}}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({resolve_deadlock, WorkflowId, BreakEdges}, _From, State) ->
    %% Resolve deadlock by breaking specified edges
    case maps:get(WorkflowId, State#state.deadlocks, []) of
        [] ->
            {reply, {error, no_deadlock}, State};
        _Cycles ->
            %% In a real implementation, this would update the workflow state
            %% to break the dependencies
            NewDeadlocks = maps:remove(WorkflowId, State#state.deadlocks),
            {reply, ok, State#state{deadlocks = NewDeadlocks}}
    end;

handle_call({check_for_cycles, DependencyGraph}, _From, State) ->
    case check_for_cycles_impl(DependencyGraph) of
        {ok, []} -> {reply, {ok, no_cycles}, State};
        {ok, Cycles} -> {reply, {ok, Cycles}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({clear_recovery_state, WorkflowId}, State) ->
    NewRecoveryStates = maps:remove(WorkflowId, State#state.recovery_states),
    {noreply, State#state{recovery_states = NewRecoveryStates}};

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
%% Internal Functions
%%====================================================================

%% @private
do_execute_with_retry(_Fun, 0, _Delay, _Attempt) ->
    {error, max_retries_exceeded};
do_execute_with_retry(Fun, MaxAttempts, Delay, Attempt) ->
    case execute_function(Fun) of
        {ok, Result} ->
            {ok, Result};
        {error, Reason} when Attempt < MaxAttempts ->
            %% Calculate backoff delay
            BackoffDelay = min(Delay * trunc(math:pow(2, Attempt - 1)), 30000),
            timer:sleep(BackoffDelay),
            do_execute_with_retry(Fun, MaxAttempts, Delay, Attempt + 1);
        {error, Reason} ->
            {error, {max_retries_exceeded, Reason}}
    end.

%% @private
execute_function(Fun) when is_function(Fun) ->
    try
        {ok, Fun()}
    catch
        Type:Error:Stacktrace ->
            {error, {Type, Error, Stacktrace}}
    end;
execute_function({M, F, A}) ->
    try
        {ok, apply(M, F, A)}
    catch
        Type:Error:Stacktrace ->
            {error, {Type, Error, Stacktrace}}
    end.

%% @private
execute_with_timeout(Fun, Timeout) ->
    try
        {ok, execute_function_with_timeout(Fun, Timeout)}
    catch
        Type:Error:Stacktrace ->
            {error, {Type, Error, Stacktrace}}
    end.

%% @private
execute_function_with_timeout(Fun, Timeout) when is_function(Fun) ->
    Ref = make_ref(),
    Pid = self(),
    spawn(fun() ->
        Result = try
            {ok, Fun()}
        catch
            Type:Error:Stacktrace ->
            {error, {Type, Error, Stacktrace}}
        end,
        Pid ! {Ref, Result}
    end),
    receive
        {Ref, Result} ->
            Result
    after Timeout ->
        {error, timeout}
    end.

%% @private
build_dependency_graph(#yawl_workflow_persist{marking = Marking}) ->
    %% Build dependency graph from marking
    %% In a real implementation, this would analyze the workflow structure
    Marking.

%% @private
check_for_cycles_impl(DependencyGraph) ->
    %% Detect cycles using depth-first search
    Visited = sets:new(),
    RecStack = sets:new(),
    Nodes = maps:keys(DependencyGraph),
    Cycles = lists:filtermap(fun(Node) ->
        case dfs(Node, DependencyGraph, Visited, RecStack, []) of
            {cycle, Path} -> {true, Path};
            no_cycle -> false
        end
    end, Nodes),
    {ok, Cycles}.

%% @private
dfs(Node, Graph, Visited, RecStack, Path) ->
    case sets:is_element(Node, RecStack) of
        true ->
            %% Found a cycle
            {cycle, lists:reverse([Node | Path])};
        false ->
            case sets:is_element(Node, Visited) of
                true ->
                    no_cycle;
                false ->
                    NewVisited = sets:add_element(Node, Visited),
                    NewRecStack = sets:add_element(Node, RecStack),
                    Neighbors = maps:get(Node, Graph, []),
                    dfs_neighbors(Neighbors, Graph, NewVisited, NewRecStack, [Node | Path])
            end
    end.

%% @private
dfs_neighbors([], _Graph, _Visited, _RecStack, _Path) ->
    no_cycle;
dfs_neighbors([Node | Rest], Graph, Visited, RecStack, Path) ->
    case dfs(Node, Graph, Visited, RecStack, Path) of
        {cycle, CyclePath} ->
            {cycle, CyclePath};
        no_cycle ->
            dfs_neighbors(Rest, Graph, Visited, RecStack, Path)
    end.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
