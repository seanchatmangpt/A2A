%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Task Timeout Handler
%%%
%%% This module provides timeout handling for workflow tasks to prevent
%%% workflows from hanging indefinitely. It supports:
%%%
%%% - Configurable timeout values per task type
%%% - Timeout event handlers and callbacks
%%% - Automatic task cancellation on timeout
%%% - Timeout statistics and monitoring
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_timeout).
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

%% API exports - Timeout management
-export([
    start_timeout/3,
    start_timeout/4,
    cancel_timeout/1,
    extend_timeout/2,
    get_timeout_status/1
]).

%% API exports - Configuration
-export([
    set_default_timeout/1,
    get_default_timeout/0,
    set_task_timeout/2,
    get_task_timeout/1
]).

%% API exports - Statistics
-export([
    get_timeout_stats/0,
    reset_timeout_stats/0
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

%% Define timeout_info record first (before state record uses it)
-record(timeout_info, {
    workitem_id :: binary(),
    workflow_id :: binary(),
    task_id :: atom(),
    timeout :: integer(),
    start_time :: integer(),
    timer_ref :: reference(),
    callback :: pid() | undefined,
    extended_count :: non_neg_integer()
}).

%% Define timeout_stats record first (before state record uses it)
-record(timeout_stats, {
    total_timeouts :: non_neg_integer(),
    active_timeouts :: non_neg_integer(),
    cancelled_timeouts :: non_neg_integer(),
    extended_timeouts :: non_neg_integer()
}).

-record(state, {
    timeouts :: #{binary() => #timeout_info{}},
    default_timeout :: integer(),
    task_timeouts :: #{atom() => integer()},
    stats :: #timeout_stats{}
}).

%%====================================================================
%% Type Definitions
%%====================================================================

-type timeout_duration() :: pos_integer().
-type timeout_callback() :: pid() | function().
-type timeout_status() :: active | expired | cancelled.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the timeout handler.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Start a timeout for a work item.
-spec start_timeout(binary(), binary(), atom()) -> {ok, reference()} | {error, term()}.
start_timeout(WorkitemId, WorkflowId, TaskId) ->
    gen_server:call(?MODULE, {start_timeout, WorkitemId, WorkflowId, TaskId, undefined, ?DEFAULT_TIMEOUT}).

%% @doc Start a timeout with custom duration and callback.
-spec start_timeout(binary(), binary(), atom(), timeout_duration() | {timeout_duration(), timeout_callback()}) ->
    {ok, reference()} | {error, term()}.
start_timeout(WorkitemId, WorkflowId, TaskId, Timeout) when is_integer(Timeout) ->
    gen_server:call(?MODULE, {start_timeout, WorkitemId, WorkflowId, TaskId, undefined, Timeout});
start_timeout(WorkitemId, WorkflowId, TaskId, {Timeout, Callback}) ->
    gen_server:call(?MODULE, {start_timeout, WorkitemId, WorkflowId, TaskId, Callback, Timeout}).

%% @doc Cancel a timeout.
-spec cancel_timeout(binary()) -> ok | {error, term()}.
cancel_timeout(WorkitemId) ->
    gen_server:call(?MODULE, {cancel_timeout, WorkitemId}).

%% @doc Extend a timeout.
-spec extend_timeout(binary(), timeout_duration()) -> ok | {error, term()}.
extend_timeout(WorkitemId, AdditionalTime) ->
    gen_server:call(?MODULE, {extend_timeout, WorkitemId, AdditionalTime}).

%% @doc Get timeout status.
-spec get_timeout_status(binary()) -> {ok, timeout_status(), map()} | {error, term()}.
get_timeout_status(WorkitemId) ->
    gen_server:call(?MODULE, {get_timeout_status, WorkitemId}).

%% @doc Set default timeout for all tasks.
-spec set_default_timeout(timeout_duration()) -> ok.
set_default_timeout(Timeout) ->
    gen_server:call(?MODULE, {set_default_timeout, Timeout}).

%% @doc Get default timeout.
-spec get_default_timeout() -> {ok, timeout_duration()}.
get_default_timeout() ->
    gen_server:call(?MODULE, get_default_timeout).

%% @doc Set timeout for specific task type.
-spec set_task_timeout(atom(), timeout_duration()) -> ok.
set_task_timeout(TaskType, Timeout) ->
    gen_server:call(?MODULE, {set_task_timeout, TaskType, Timeout}).

%% @doc Get timeout for specific task type.
-spec get_task_timeout(atom()) -> {ok, timeout_duration()} | {error, term()}.
get_task_timeout(TaskType) ->
    gen_server:call(?MODULE, {get_task_timeout, TaskType}).

%% @doc Get timeout statistics.
-spec get_timeout_stats() -> {ok, map()}.
get_timeout_stats() ->
    gen_server:call(?MODULE, get_timeout_stats).

%% @doc Reset timeout statistics.
-spec reset_timeout_stats() -> ok.
reset_timeout_stats() ->
    gen_server:call(?MODULE, reset_timeout_stats).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        timeouts = #{},
        default_timeout = ?DEFAULT_TIMEOUT,
        task_timeouts = #{
            human_task => 300000,      % 5 minutes for human tasks
            service_call => 30000,     % 30 seconds for service calls
            code_execution => 60000,   % 1 minute for code execution
            workflow => 300000         % 5 minutes for entire workflow
        },
        stats = #timeout_stats{
            total_timeouts = 0,
            active_timeouts = 0,
            cancelled_timeouts = 0,
            extended_timeouts = 0
        }
    },
    {ok, State}.

%% @private
handle_call({start_timeout, WorkitemId, WorkflowId, TaskId, Callback, Timeout}, _From, State) ->
    %% Determine timeout based on task type
    TaskTimeout = case maps:is_key(TaskId, State#state.task_timeouts) of
        true -> maps:get(TaskId, State#state.task_timeouts);
        false -> Timeout
    end,

    %% Start timer
    TimerRef = erlang:send_after(TaskTimeout, self(), {timeout, WorkitemId}),

    TimeoutInfo = #timeout_info{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        timeout = TaskTimeout,
        start_time = erlang:monotonic_time(millisecond),
        timer_ref = TimerRef,
        callback = Callback,
        extended_count = 0
    },

    NewTimeouts = maps:put(WorkitemId, TimeoutInfo, State#state.timeouts),
    NewStats = State#state.stats#timeout_stats{
        total_timeouts = State#state.stats#timeout_stats.total_timeouts + 1,
        active_timeouts = State#state.stats#timeout_stats.active_timeouts + 1
    },

    {reply, {ok, TimerRef}, State#state{timeouts = NewTimeouts, stats = NewStats}};

handle_call({cancel_timeout, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.timeouts, undefined) of
        undefined ->
            {reply, {error, timeout_not_found}, State};
        #timeout_info{timer_ref = TimerRef} ->
            erlang:cancel_timer(TimerRef),
            NewTimeouts = maps:remove(WorkitemId, State#state.timeouts),
            NewStats = State#state.stats#timeout_stats{
                active_timeouts = max(0, State#state.stats#timeout_stats.active_timeouts - 1),
                cancelled_timeouts = State#state.stats#timeout_stats.cancelled_timeouts + 1
            },
            {reply, ok, State#state{timeouts = NewTimeouts, stats = NewStats}}
    end;

handle_call({extend_timeout, WorkitemId, AdditionalTime}, _From, State) ->
    case maps:get(WorkitemId, State#state.timeouts, undefined) of
        undefined ->
            {reply, {error, timeout_not_found}, State};
        #timeout_info{timer_ref = OldTimerRef, extended_count = Count} = TimeoutInfo ->
            %% Cancel old timer
            erlang:cancel_timer(OldTimerRef),

            %% Start new timer with additional time
            NewTimerRef = erlang:send_after(AdditionalTime, self(), {timeout, WorkitemId}),

            UpdatedInfo = TimeoutInfo#timeout_info{
                timer_ref = NewTimerRef,
                extended_count = Count + 1
            },

            NewTimeouts = maps:put(WorkitemId, UpdatedInfo, State#state.timeouts),
            NewStats = State#state.stats#timeout_stats{
                extended_timeouts = State#state.stats#timeout_stats.extended_timeouts + 1
            },

            {reply, ok, State#state{timeouts = NewTimeouts, stats = NewStats}}
    end;

handle_call({get_timeout_status, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.timeouts, undefined) of
        undefined ->
            {reply, {error, timeout_not_found}, State};
        #timeout_info{
            start_time = StartTime,
            timeout = Timeout,
            extended_count = ExtendedCount
        } ->
            Elapsed = erlang:monotonic_time(millisecond) - StartTime,
            Remaining = max(0, Timeout - Elapsed),
            StatusMap = #{
                status => active,
                remaining_time => Remaining,
                elapsed_time => Elapsed,
                total_timeout => Timeout,
                extended_count => ExtendedCount
            },
            {reply, {ok, active, StatusMap}, State}
    end;

handle_call({set_default_timeout, Timeout}, _From, State) ->
    {reply, ok, State#state{default_timeout = Timeout}};

handle_call(get_default_timeout, _From, State) ->
    {reply, {ok, State#state.default_timeout}, State};

handle_call({set_task_timeout, TaskType, Timeout}, _From, State) ->
    NewTaskTimeouts = maps:put(TaskType, Timeout, State#state.task_timeouts),
    {reply, ok, State#state{task_timeouts = NewTaskTimeouts}};

handle_call({get_task_timeout, TaskType}, _From, State) ->
    case maps:get(TaskType, State#state.task_timeouts, undefined) of
        undefined ->
            {reply, {error, task_type_not_found}, State};
        Timeout ->
            {reply, {ok, Timeout}, State}
    end;

handle_call(get_timeout_stats, _From, State) ->
    Stats = State#state.stats,
    StatsMap = #{
        total_timeouts => Stats#timeout_stats.total_timeouts,
        active_timeouts => Stats#timeout_stats.active_timeouts,
        cancelled_timeouts => Stats#timeout_stats.cancelled_timeouts,
        extended_timeouts => Stats#timeout_stats.extended_timeouts
    },
    {reply, {ok, StatsMap}, State};

handle_call(reset_timeout_stats, _From, State) ->
    NewStats = #timeout_stats{
        total_timeouts = 0,
        active_timeouts = State#state.stats#timeout_stats.active_timeouts,
        cancelled_timeouts = 0,
        extended_timeouts = 0
    },
    {reply, ok, State#state{stats = NewStats}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({timeout, WorkitemId}, State) ->
    case maps:get(WorkitemId, State#state.timeouts, undefined) of
        undefined ->
            {noreply, State};
        #timeout_info{
            workflow_id = WorkflowId,
            task_id = TaskId,
            callback = Callback
        } ->

        %% Log timeout event
        error_logger:warning_msg("YAWL Timeout: Workitem ~p (task ~p) in workflow ~p timed out~n",
                               [WorkitemId, TaskId, WorkflowId]),

        %% Update workitem status to failed with timeout
        catch yawl_workitem_processor:cancel_workitem(WorkflowId, WorkitemId),

        %% Notify callback if set
        case Callback of
            undefined -> ok;
            Pid when is_pid(Pid) ->
                Pid ! {timeout, WorkitemId, TaskId};
            _ when is_function(Callback) ->
                catch Callback(WorkitemId, TaskId)
        end,

        %% Remove timeout and update stats
        NewTimeouts = maps:remove(WorkitemId, State#state.timeouts),
        NewStats = State#state.stats#timeout_stats{
            active_timeouts = max(0, State#state.stats#timeout_stats.active_timeouts - 1)
        },

        {noreply, State#state{timeouts = NewTimeouts, stats = NewStats}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    %% Cancel all active timeouts
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
