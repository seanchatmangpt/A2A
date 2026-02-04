%%% @doc A2A Task Store using ETS
%%%
%%% This module provides persistent storage for tasks using ETS tables.
%%% OTP 28 features: uses optimized ETS with write_concurrency and
%%% read_concurrency options for high-performance concurrent access.
%%%
%%% Tables:
%%% - a2a_tasks: Main task storage {task_id, task_record}
%%% - a2a_task_pids: Maps task_id to gen_statem pid
%%% - a2a_task_contexts: Secondary index for context_id lookups
%%% - a2a_push_configs: Push notification configurations
-module(a2a_task_store).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    register_task/2,
    unregister_task/1,
    update_task/1,
    get_task/1,
    get_task_pid/1,
    list_tasks/1,
    delete_task/1,
    task_count/0,
    %% Push notification config
    add_push_config/2,
    get_push_config/2,
    list_push_configs/1,
    delete_push_config/2
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

-define(TASKS_TABLE, a2a_tasks).
-define(PIDS_TABLE, a2a_task_pids).
-define(CONTEXTS_TABLE, a2a_task_contexts).
-define(PUSH_TABLE, a2a_push_configs).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a new task with its gen_statem pid
-spec register_task(binary(), pid()) -> ok.
register_task(TaskId, Pid) ->
    gen_server:call(?MODULE, {register_task, TaskId, Pid}).

%% @doc Unregister a task (called when gen_statem terminates)
-spec unregister_task(binary()) -> ok.
unregister_task(TaskId) ->
    gen_server:cast(?MODULE, {unregister_task, TaskId}).

%% @doc Update task record in store
-spec update_task(task()) -> ok.
update_task(Task) ->
    TaskId = Task#task.id,
    ContextId = Task#task.context_id,
    Timestamp = (Task#task.status)#task_status.timestamp,

    %% Update main table
    ets:insert(?TASKS_TABLE, {TaskId, Task}),

    %% Update context index
    ets:insert(?CONTEXTS_TABLE, {ContextId, TaskId, Timestamp}),
    ok.

%% @doc Get task by ID
-spec get_task(binary()) -> {ok, task()} | {error, not_found}.
get_task(TaskId) ->
    case ets:lookup(?TASKS_TABLE, TaskId) of
        [{TaskId, Task}] -> {ok, Task};
        [] -> {error, not_found}
    end.

%% @doc Get gen_statem pid for a task
-spec get_task_pid(binary()) -> {ok, pid()} | {error, not_found}.
get_task_pid(TaskId) ->
    case ets:lookup(?PIDS_TABLE, TaskId) of
        [{TaskId, Pid}] ->
            case is_process_alive(Pid) of
                true -> {ok, Pid};
                false -> {error, not_found}
            end;
        [] -> {error, not_found}
    end.

%% @doc List tasks with filtering options
-spec list_tasks(map()) -> {ok, [task()], binary()}.
list_tasks(Opts) ->
    ContextId = maps:get(context_id, Opts, undefined),
    Status = maps:get(status, Opts, undefined),
    PageSize = maps:get(page_size, Opts, 50),
    PageToken = maps:get(page_token, Opts, undefined),
    TimestampAfter = maps:get(status_timestamp_after, Opts, undefined),
    IncludeArtifacts = maps:get(include_artifacts, Opts, false),
    HistoryLength = maps:get(history_length, Opts, undefined),

    %% Build match specification
    Tasks = case ContextId of
        undefined ->
            %% Full table scan
            ets:tab2list(?TASKS_TABLE);
        _ ->
            %% Use context index
            ContextMatches = ets:match(?CONTEXTS_TABLE, {ContextId, '$1', '_'}),
            TaskIds = [Id || [Id] <- ContextMatches],
            lists:filtermap(fun(TId) ->
                case ets:lookup(?TASKS_TABLE, TId) of
                    [{TId, T}] -> {true, {TId, T}};
                    [] -> false
                end
            end, TaskIds)
    end,

    %% Apply filters
    FilteredTasks = lists:filter(fun({_Id, Task}) ->
        filter_task(Task, Status, TimestampAfter)
    end, Tasks),

    %% Sort by timestamp descending
    SortedTasks = lists:sort(fun({_, A}, {_, B}) ->
        (A#task.status)#task_status.timestamp >= (B#task.status)#task_status.timestamp
    end, FilteredTasks),

    %% Apply pagination
    {PagedTasks, NextToken} = paginate(SortedTasks, PageSize, PageToken),

    %% Transform results
    ResultTasks = lists:map(fun({_Id, Task}) ->
        prepare_task_response(Task, IncludeArtifacts, HistoryLength)
    end, PagedTasks),

    {ok, ResultTasks, NextToken}.

%% @doc Delete a task
-spec delete_task(binary()) -> ok.
delete_task(TaskId) ->
    case ets:lookup(?TASKS_TABLE, TaskId) of
        [{TaskId, Task}] ->
            ContextId = Task#task.context_id,
            ets:delete(?TASKS_TABLE, TaskId),
            ets:delete(?PIDS_TABLE, TaskId),
            ets:match_delete(?CONTEXTS_TABLE, {ContextId, TaskId, '_'}),
            ok;
        [] ->
            ok
    end.

%% @doc Get the total count of tasks in the store
-spec task_count() -> non_neg_integer().
task_count() ->
    ets:info(?TASKS_TABLE, size).

%% @doc Add push notification config for a task
-spec add_push_config(binary(), task_push_notification_config()) -> ok.
add_push_config(TaskId, Config) ->
    ConfigId = Config#task_push_notification_config.id,
    ets:insert(?PUSH_TABLE, {{TaskId, ConfigId}, Config}),
    ok.

%% @doc Get push notification config
-spec get_push_config(binary(), binary()) ->
    {ok, task_push_notification_config()} | {error, not_found}.
get_push_config(TaskId, ConfigId) ->
    case ets:lookup(?PUSH_TABLE, {TaskId, ConfigId}) of
        [{{TaskId, ConfigId}, Config}] -> {ok, Config};
        [] -> {error, not_found}
    end.

%% @doc List push notification configs for a task
-spec list_push_configs(binary()) -> [task_push_notification_config()].
list_push_configs(TaskId) ->
    Pattern = {{TaskId, '_'}, '$1'},
    Matches = ets:match(?PUSH_TABLE, Pattern),
    [Config || [Config] <- Matches].

%% @doc Delete push notification config
-spec delete_push_config(binary(), binary()) -> ok.
delete_push_config(TaskId, ConfigId) ->
    ets:delete(?PUSH_TABLE, {TaskId, ConfigId}),
    ok.

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

init([]) ->
    %% Create ETS tables with OTP 28 optimizations
    %% write_concurrency and read_concurrency for high performance
    %% Clean up any existing tables first (in case of previous runs)
    lists:foreach(fun(Table) ->
        case ets:info(Table) of
            undefined -> ok;
            _ -> ets:delete(Table)
        end
    end, [?TASKS_TABLE, ?PIDS_TABLE, ?CONTEXTS_TABLE, ?PUSH_TABLE]),

    _ = ets:new(?TASKS_TABLE, [
        named_table,
        public,
        set,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    _ = ets:new(?PIDS_TABLE, [
        named_table,
        public,
        set,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    %% Bag for context -> task_id mapping (multiple tasks per context)
    _ = ets:new(?CONTEXTS_TABLE, [
        named_table,
        public,
        bag,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    _ = ets:new(?PUSH_TABLE, [
        named_table,
        public,
        set,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    %% Start cleanup timer (every 5 minutes)
    erlang:send_after(300000, self(), cleanup_stale),

    {ok, #{}}.

handle_call({register_task, TaskId, Pid}, _From, State) ->
    %% Monitor the gen_statem process
    erlang:monitor(process, Pid),
    ets:insert(?PIDS_TABLE, {TaskId, Pid}),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({unregister_task, TaskId}, State) ->
    ets:delete(?PIDS_TABLE, TaskId),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    %% Task process died, clean up pid mapping
    Pattern = {'$1', Pid},
    Matches = ets:match(?PIDS_TABLE, Pattern),
    lists:foreach(fun([TaskId]) ->
        ets:delete(?PIDS_TABLE, TaskId)
    end, Matches),
    {noreply, State};

handle_info(cleanup_stale, State) ->
    %% Clean up old terminal tasks (older than 24 hours)
    cleanup_old_tasks(),
    erlang:send_after(300000, self(), cleanup_stale),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%% @doc Handle code changes for hot upgrade/downgrade
%%
%% Supports:
%%   - downgrade: State format reversion for 0.2.0 -> 0.1.0
%%   - upgrade: State format migration for 0.1.0 -> 0.2.0
code_change(OldVsn, State, Extra) ->
    case {OldVsn, Extra} of
        {_, downgrade} ->
            %% Downgrade from 0.2.0 to 0.1.0
            %% Remove push notification config table if it exists
            case ets:info(?PUSH_TABLE) of
                undefined -> ok;
                _ -> ets:delete(?PUSH_TABLE)
            end,
            {ok, State};
        {_, upgrade} ->
            %% Upgrade from 0.1.0 to 0.2.0
            %% Ensure push notification table exists
            case ets:info(?PUSH_TABLE) of
                undefined ->
                    _ = ets:new(?PUSH_TABLE, [
                        named_table,
                        public,
                        set,
                        {keypos, 1},
                        {write_concurrency, auto},
                        {read_concurrency, true}
                    ]);
                _ ->
                    ok
            end,
            {ok, State};
        _ ->
            {ok, State}
    end.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% Filter task based on criteria
-spec filter_task(task(), atom() | undefined, integer() | undefined) -> boolean().
filter_task(Task, Status, TimestampAfter) ->
    StatusMatch = case Status of
        undefined -> true;
        S -> (Task#task.status)#task_status.state =:= S
    end,

    TimestampMatch = case TimestampAfter of
        undefined -> true;
        T -> (Task#task.status)#task_status.timestamp >= T
    end,

    StatusMatch andalso TimestampMatch.

%% Paginate results
-spec paginate([{binary(), task()}], integer(), binary() | undefined) ->
    {[{binary(), task()}], binary()}.
paginate(Tasks, PageSize, undefined) ->
    paginate(Tasks, PageSize, <<"0">>);
paginate(Tasks, PageSize, PageToken) ->
    Offset = try binary_to_integer(PageToken) catch _:_ -> 0 end,

    %% Skip to offset
    AfterOffset = lists:nthtail(min(Offset, length(Tasks)), Tasks),

    %% Take page
    Page = lists:sublist(AfterOffset, PageSize),

    %% Calculate next token
    NextOffset = Offset + length(Page),
    NextToken = if
        NextOffset >= length(Tasks) -> <<>>;
        true -> integer_to_binary(NextOffset)
    end,

    {Page, NextToken}.

%% Prepare task for response (apply history limit, artifacts)
-spec prepare_task_response(task(), boolean(), integer() | undefined) -> task().
prepare_task_response(Task, IncludeArtifacts, HistoryLength) ->
    %% Apply history length limit
    History = case HistoryLength of
        undefined -> Task#task.history;
        0 -> [];
        N when N > 0 ->
            Len = length(Task#task.history),
            if
                Len =< N -> Task#task.history;
                true -> lists:nthtail(Len - N, Task#task.history)
            end;
        _ -> Task#task.history
    end,

    %% Include/exclude artifacts
    Artifacts = case IncludeArtifacts of
        true -> Task#task.artifacts;
        false -> []
    end,

    Task#task{
        history = History,
        artifacts = Artifacts
    }.

%% Clean up old terminal tasks
-spec cleanup_old_tasks() -> ok.
cleanup_old_tasks() ->
    Now = erlang:system_time(millisecond),
    MaxAge = 24 * 60 * 60 * 1000, %% 24 hours in milliseconds
    Cutoff = Now - MaxAge,

    %% Find old tasks
    OldTasks = ets:foldl(fun({TaskId, Task}, Acc) ->
        State = (Task#task.status)#task_status.state,
        Timestamp = (Task#task.status)#task_status.timestamp,
        IsTerminal = lists:member(State, ?TERMINAL_STATES),

        if
            IsTerminal andalso Timestamp < Cutoff ->
                [TaskId | Acc];
            true ->
                Acc
        end
    end, [], ?TASKS_TABLE),

    %% Delete old tasks
    lists:foreach(fun(TaskId) ->
        delete_task(TaskId)
    end, OldTasks),

    logger:info("Cleaned up ~p old tasks", [length(OldTasks)]),
    ok.
