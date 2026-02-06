%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Retry Policy Manager
%%%
%%% This module provides configurable retry policies for failed operations.
%%% It supports:
%%%
%%% - Exponential backoff with jitter
%%% - Configurable max retry attempts
%%% - Per-task-type retry policies
%%% - Retry statistics and monitoring
%%% - Circuit breaker integration
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_retry).
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

%% API exports - Retry execution
-export([
    execute_with_retry/3,
    execute_with_retry/4,
    retry_workitem/2
]).

%% API exports - Policy management
-export([
    set_retry_policy/2,
    get_retry_policy/1,
    set_default_policy/1,
    get_default_policy/0
]).

%% API exports - Statistics
-export([
    get_retry_stats/0,
    get_retry_stats/1,
    reset_retry_stats/0
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

%% Define retry_policy record first (before state record uses it)
-record(retry_policy, {
    max_attempts :: non_neg_integer(),
    initial_delay :: non_neg_integer(),
    max_delay :: non_neg_integer(),
    backoff_factor :: float(),
    jitter_enabled :: boolean(),
    jitter_factor :: float(),
    retryable_errors :: [term()] | all
}).

%% Define retry_stats record first (before state record uses it)
-record(retry_stats, {
    attempts :: non_neg_integer(),
    successes :: non_neg_integer(),
    failures :: non_neg_integer(),
    last_attempt_time :: integer() | undefined
}).

-record(state, {
    policies :: #{atom() => #retry_policy{}},
    default_policy :: #retry_policy{},
    stats :: #{binary() => #retry_stats{}}
}).

%%====================================================================
%% Type Definitions
%%====================================================================

-type retry_policy() :: #retry_policy{}.
-type retry_result() :: {ok, term()} | {error, term()}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the retry policy manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Execute a function with default retry policy.
-spec execute_with_retry(function(), binary(), atom()) -> retry_result().
execute_with_retry(Function, WorkitemId, TaskType) ->
    gen_server:call(?MODULE, {execute_with_retry, Function, WorkitemId, TaskType, undefined}).

%% @doc Execute a function with custom retry policy.
-spec execute_with_retry(function(), binary(), atom(), retry_policy() | atom()) -> retry_result().
execute_with_retry(Function, WorkitemId, TaskType, PolicyName) when is_atom(PolicyName) ->
    gen_server:call(?MODULE, {execute_with_retry, Function, WorkitemId, TaskType, PolicyName});
execute_with_retry(Function, WorkitemId, TaskType, #retry_policy{} = Policy) ->
    gen_server:call(?MODULE, {execute_with_retry, Function, WorkitemId, TaskType, Policy}).

%% @doc Retry a failed workitem.
-spec retry_workitem(binary(), binary()) -> ok | {error, term()}.
retry_workitem(WorkflowId, WorkitemId) ->
    gen_server:call(?MODULE, {retry_workitem, WorkflowId, WorkitemId}).

%% @doc Set retry policy for a task type.
-spec set_retry_policy(atom(), retry_policy()) -> ok.
set_retry_policy(TaskType, Policy) ->
    gen_server:call(?MODULE, {set_retry_policy, TaskType, Policy}).

%% @doc Get retry policy for a task type.
-spec get_retry_policy(atom()) -> {ok, retry_policy()} | {error, term()}.
get_retry_policy(TaskType) ->
    gen_server:call(?MODULE, {get_retry_policy, TaskType}).

%% @doc Set default retry policy.
-spec set_default_policy(retry_policy()) -> ok.
set_default_policy(Policy) ->
    gen_server:call(?MODULE, {set_default_policy, Policy}).

%% @doc Get default retry policy.
-spec get_default_policy() -> {ok, retry_policy()}.
get_default_policy() ->
    gen_server:call(?MODULE, get_default_policy).

%% @doc Get all retry statistics.
-spec get_retry_stats() -> {ok, map()}.
get_retry_stats() ->
    gen_server:call(?MODULE, get_retry_stats).

%% @doc Get retry statistics for a workitem.
-spec get_retry_stats(binary()) -> {ok, map()} | {error, term()}.
get_retry_stats(WorkitemId) ->
    gen_server:call(?MODULE, {get_retry_stats, WorkitemId}).

%% @doc Reset retry statistics.
-spec reset_retry_stats() -> ok.
reset_retry_stats() ->
    gen_server:call(?MODULE, reset_retry_stats).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    DefaultPolicy = #retry_policy{
        max_attempts = ?MAX_RETRY_ATTEMPTS,
        initial_delay = ?DEFAULT_RETRY_DELAY,
        max_delay = 30000,
        backoff_factor = 2.0,
        jitter_enabled = true,
        jitter_factor = 0.1,
        retryable_errors = all
    },

    State = #state{
        policies = #{
            human_task => DefaultPolicy#retry_policy{max_attempts = 3, initial_delay = 5000},
            service_call => DefaultPolicy#retry_policy{max_attempts = 5, initial_delay = 1000},
            code_execution => DefaultPolicy#retry_policy{max_attempts = 3, initial_delay = 2000}
        },
        default_policy = DefaultPolicy,
        stats = #{}
    },
    {ok, State}.

%% @private
handle_call({execute_with_retry, Function, WorkitemId, TaskType, PolicyInput}, _From, State) ->
    %% Get the policy to use
    Policy = case PolicyInput of
        undefined ->
            case maps:get(TaskType, State#state.policies, undefined) of
                undefined -> State#state.default_policy;
                P -> P
            end;
        PolicyName when is_atom(PolicyName) ->
            maps:get(PolicyName, State#state.policies, State#state.default_policy);
        #retry_policy{} = P ->
            P
    end,

    %% Execute with retry
    {Result, NewStats} = execute_retry_loop(Function, WorkitemId, Policy, 0),

    %% Update statistics
    UpdatedStats = maps:put(WorkitemId, NewStats, State#state.stats),
    {reply, Result, State#state{stats = UpdatedStats}};

handle_call({retry_workitem, WorkflowId, WorkitemId}, _From, State) ->
    %% Load workitem and retry
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, #yawl_workitem_persist{retry_count = RetryCount, task_id = TaskId} = Workitem} ->
            Policy = maps:get(TaskId, State#state.policies, State#state.default_policy),
            MaxAttempts = Policy#retry_policy.max_attempts,

            case RetryCount < MaxAttempts of
                true ->
                    %% Update workitem for retry
                    UpdatedWorkitem = Workitem#yawl_workitem_persist{
                        status = pending,
                        retry_count = RetryCount + 1,
                        error = undefined
                    },
                    case yawl_persistence:save_workitem(UpdatedWorkitem) of
                        ok ->
                            %% Re-queue for processing
                            case yawl_workitem_processor:retry_workitem(WorkflowId, WorkitemId) of
                                ok ->
                                    {reply, ok, State};
                                {error, Reason} ->
                                    {reply, {error, Reason}, State}
                            end;
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                false ->
                    {reply, {error, max_retries_exceeded}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({set_retry_policy, TaskType, Policy}, _From, State) ->
    NewPolicies = maps:put(TaskType, Policy, State#state.policies),
    {reply, ok, State#state{policies = NewPolicies}};

handle_call({get_retry_policy, TaskType}, _From, State) ->
    case maps:get(TaskType, State#state.policies, undefined) of
        undefined ->
            {reply, {error, policy_not_found}, State};
        Policy ->
            {reply, {ok, Policy}, State}
    end;

handle_call({set_default_policy, Policy}, _From, State) ->
    {reply, ok, State#state{default_policy = Policy}};

handle_call(get_default_policy, _From, State) ->
    {reply, {ok, State#state.default_policy}, State};

handle_call(get_retry_stats, _From, State) ->
    StatsMap = maps:map(fun(_WorkitemId, Stats) ->
        #{
            attempts => Stats#retry_stats.attempts,
            successes => Stats#retry_stats.successes,
            failures => Stats#retry_stats.failures,
            last_attempt_time => Stats#retry_stats.last_attempt_time
        }
    end, State#state.stats),
    {reply, {ok, StatsMap}, State};

handle_call({get_retry_stats, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.stats, undefined) of
        undefined ->
            {reply, {error, stats_not_found}, State};
        Stats ->
            StatsMap = #{
                attempts => Stats#retry_stats.attempts,
                successes => Stats#retry_stats.successes,
                failures => Stats#retry_stats.failures,
                last_attempt_time => Stats#retry_stats.last_attempt_time
            },
            {reply, {ok, StatsMap}, State}
    end;

handle_call(reset_retry_stats, _From, State) ->
    {reply, ok, State#state{stats = #{}}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
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
execute_retry_loop(Function, WorkitemId, Policy, Attempt) ->
    MaxAttempts = Policy#retry_policy.max_attempts,

    %% Update stats
    InitialStats = #retry_stats{
        attempts = Attempt,
        successes = 0,
        failures = 0,
        last_attempt_time = erlang:monotonic_time(millisecond)
    },

    case Attempt >= MaxAttempts of
        true ->
            {{error, max_retries_exceeded}, InitialStats};
        false ->
            %% Execute the function
            Result = try
                Function()
            catch
                Type:Error:Stacktrace ->
                    {error, {Type, Error, Stacktrace}}
            end,

            case Result of
                {error, Reason} ->
                    %% Check if error is retryable
                    IsRetryable = case Policy#retry_policy.retryable_errors of
                        all -> true;
                        RetryableErrors -> lists:member(Reason, RetryableErrors)
                    end,

                    case IsRetryable of
                        true when Attempt < MaxAttempts - 1 ->
                            %% Calculate delay with exponential backoff and jitter
                            Delay = calculate_delay(Attempt, Policy),
                            timer:sleep(Delay),

                            %% Retry
                            execute_retry_loop(Function, WorkitemId, Policy, Attempt + 1);
                        _ ->
                            %% Non-retryable or max attempts reached
                            FailedStats = InitialStats#retry_stats{
                                attempts = Attempt + 1,
                                failures = 1
                            },
                            {{error, {max_retries_exceeded, Reason}}, FailedStats}
                    end;
                {ok, _Value} ->
                    %% Success
                    SuccessStats = InitialStats#retry_stats{
                        attempts = Attempt + 1,
                        successes = 1
                    },
                    {Result, SuccessStats};
                _ ->
                    %% Other return value
                    SuccessStats = InitialStats#retry_stats{
                        attempts = Attempt + 1,
                        successes = 1
                    },
                    {Result, SuccessStats}
            end
    end.

%% @private
calculate_delay(Attempt, Policy) ->
    #retry_policy{
        initial_delay = InitialDelay,
        max_delay = MaxDelay,
        backoff_factor = BackoffFactor,
        jitter_enabled = JitterEnabled,
        jitter_factor = JitterFactor
    } = Policy,

    %% Calculate exponential backoff
    BaseDelay = min(InitialDelay * math:pow(BackoffFactor, Attempt), MaxDelay),

    %% Apply jitter if enabled
    case JitterEnabled of
        true ->
            JitterAmount = BaseDelay * JitterFactor,
            RandomJitter = (rand:uniform() * 2 - 1) * JitterAmount,
            max(0, round(BaseDelay + RandomJitter));
        false ->
            round(BaseDelay)
    end.
