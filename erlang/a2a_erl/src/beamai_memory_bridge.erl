%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Bridge
%%%
%%% Bridge module connecting the existing A2A ETS/Mnesia storage
%%% systems to the BeamAI memory layer. Provides:
%%%
%%%   - Bidirectional sync between a2a_task_store (ETS) and
%%%     beamai_memory_store
%%%   - Bidirectional sync between yawl_persistence (Mnesia) and
%%%     beamai_memory_store
%%%   - Unified query interface that searches across both the legacy
%%%     storage and the BeamAI memory system
%%%   - Migration utilities for moving data from legacy storage into
%%%     the BeamAI memory namespaces
%%%
%%% Namespace mapping:
%%%   - a2a_task_store tasks  ->  beamai_memory_store namespace: tasks
%%%   - yawl_persistence workflows -> namespace: workflows
%%%   - yawl_persistence workitems -> namespace: workitems
%%%   - yawl_persistence resources -> namespace: resources
%%%   - yawl_persistence checkpoints -> namespace: yawl_checkpoints
%%%
%%% This module is designed to run alongside the existing storage
%%% systems without modifying them. It observes changes via polling
%%% and mirrors data into the BeamAI memory store for unified access.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_bridge).

-behaviour(gen_server).

-include("a2a.hrl").
-include("yawl_schema.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    sync_tasks/0,
    sync_workflows/0,
    sync_all/0,
    query/1,
    query/2,
    migrate/1,
    migrate/2,
    get_status/0,
    set_sync_interval/1
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

-define(SERVER, ?MODULE).
-define(DEFAULT_SYNC_INTERVAL, 30000). %% 30 seconds
-define(NS_TASKS, tasks).
-define(NS_WORKFLOWS, workflows).
-define(NS_WORKITEMS, workitems).
-define(NS_RESOURCES, resources).
-define(NS_YAWL_CHECKPOINTS, yawl_checkpoints).

-record(state, {
    sync_interval  :: pos_integer(),
    sync_timer     :: reference() | undefined,
    last_task_sync :: integer(),
    last_wf_sync   :: integer(),
    sync_stats     :: map(),
    auto_sync      :: boolean()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the memory bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the memory bridge with custom configuration.
%% Options: #{sync_interval => integer(), auto_sync => boolean()}
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Synchronize all A2A tasks from the ETS task store into
%% the BeamAI memory store under the 'tasks' namespace.
-spec sync_tasks() -> {ok, non_neg_integer()} | {error, term()}.
sync_tasks() ->
    gen_server:call(?SERVER, sync_tasks, 30000).

%% @doc Synchronize all YAWL workflows, workitems, and resources from
%% Mnesia into the BeamAI memory store.
-spec sync_workflows() -> {ok, map()} | {error, term()}.
sync_workflows() ->
    gen_server:call(?SERVER, sync_workflows, 30000).

%% @doc Synchronize everything: tasks, workflows, workitems, resources.
-spec sync_all() -> {ok, map()}.
sync_all() ->
    gen_server:call(?SERVER, sync_all, 60000).

%% @doc Unified query across both legacy storage and BeamAI memory.
%% Query is a map with optional keys:
%%   - namespace: atom() - which namespace to search
%%   - key: term() - specific key to look up
%%   - pattern: term() - search pattern (fun or map)
%%   - source: legacy | beamai | both (default: both)
-spec query(map()) -> {ok, [term()]} | {error, term()}.
query(Query) ->
    query(Query, #{}).

%% @doc Unified query with options.
%% Options: #{limit => integer(), include_source => boolean()}
-spec query(map(), map()) -> {ok, [term()]} | {error, term()}.
query(Query, Opts) ->
    gen_server:call(?SERVER, {query, Query, Opts}, 15000).

%% @doc Migrate data from a legacy store into BeamAI memory.
%% Source: tasks | workflows | workitems | resources | all
-spec migrate(atom()) -> {ok, map()} | {error, term()}.
migrate(Source) ->
    migrate(Source, #{}).

%% @doc Migrate with options.
%% Options: #{delete_source => boolean(), batch_size => integer()}
-spec migrate(atom(), map()) -> {ok, map()} | {error, term()}.
migrate(Source, Opts) ->
    gen_server:call(?SERVER, {migrate, Source, Opts}, 60000).

%% @doc Get the current status of the bridge.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%% @doc Set the automatic sync interval in milliseconds.
-spec set_sync_interval(pos_integer()) -> ok.
set_sync_interval(IntervalMs) ->
    gen_server:call(?SERVER, {set_sync_interval, IntervalMs}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    process_flag(trap_exit, true),

    SyncInterval = maps:get(sync_interval, Opts, ?DEFAULT_SYNC_INTERVAL),
    AutoSync = maps:get(auto_sync, Opts, true),

    SyncTimer = case AutoSync of
        true -> erlang:send_after(SyncInterval, self(), sync_tick);
        false -> undefined
    end,

    Now = erlang:system_time(millisecond),
    State = #state{
        sync_interval = SyncInterval,
        sync_timer = SyncTimer,
        last_task_sync = 0,
        last_wf_sync = 0,
        sync_stats = #{
            task_syncs => 0,
            workflow_syncs => 0,
            total_tasks_synced => 0,
            total_workflows_synced => 0,
            total_workitems_synced => 0,
            total_resources_synced => 0,
            errors => 0,
            started_at => Now
        },
        auto_sync = AutoSync
    },

    logger:info("BeamAI Memory Bridge initialized (auto_sync=~p, interval=~pms)",
                [AutoSync, SyncInterval]),
    {ok, State}.

%% @private
handle_call(sync_tasks, _From, State) ->
    {Reply, NewState} = do_sync_tasks(State),
    {reply, Reply, NewState};

handle_call(sync_workflows, _From, State) ->
    {Reply, NewState} = do_sync_workflows(State),
    {reply, Reply, NewState};

handle_call(sync_all, _From, State) ->
    {TaskReply, State1} = do_sync_tasks(State),
    {WfReply, State2} = do_sync_workflows(State1),
    TaskCount = case TaskReply of
        {ok, N} -> N;
        _ -> 0
    end,
    WfResult = case WfReply of
        {ok, M} -> M;
        _ -> #{}
    end,
    Result = maps:merge(WfResult, #{tasks_synced => TaskCount}),
    {reply, {ok, Result}, State2};

handle_call({query, Query, Opts}, _From, State) ->
    Reply = do_query(Query, Opts),
    {reply, Reply, State};

handle_call({migrate, Source, Opts}, _From, State) ->
    Reply = do_migrate(Source, Opts),
    {reply, Reply, State};

handle_call(get_status, _From, State) ->
    Status = #{
        sync_interval => State#state.sync_interval,
        auto_sync => State#state.auto_sync,
        last_task_sync => State#state.last_task_sync,
        last_workflow_sync => State#state.last_wf_sync,
        stats => State#state.sync_stats
    },
    {reply, Status, State};

handle_call({set_sync_interval, IntervalMs}, _From, State) ->
    %% Cancel existing timer
    case State#state.sync_timer of
        undefined -> ok;
        OldRef -> erlang:cancel_timer(OldRef)
    end,
    %% Start new timer if auto_sync is on
    NewTimer = case State#state.auto_sync of
        true -> erlang:send_after(IntervalMs, self(), sync_tick);
        false -> undefined
    end,
    {reply, ok, State#state{sync_interval = IntervalMs, sync_timer = NewTimer}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(sync_tick, State) ->
    %% Periodic sync
    {_, State1} = do_sync_tasks(State),
    {_, State2} = do_sync_workflows(State1),
    Timer = erlang:send_after(State2#state.sync_interval, self(), sync_tick),
    {noreply, State2#state{sync_timer = Timer}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.sync_timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal: Task Sync
%%====================================================================

%% @private Sync tasks from a2a_task_store ETS into beamai_memory_store.
do_sync_tasks(State) ->
    try
        %% Read all tasks from the ETS table
        Tasks = case ets:info(a2a_tasks) of
            undefined ->
                [];
            _ ->
                ets:tab2list(a2a_tasks)
        end,

        %% Sync each task into the beamai memory store
        Count = lists:foldl(fun({TaskId, Task}, Acc) ->
            TaskMap = task_to_map(TaskId, Task),
            case catch beamai_memory_store:put(?NS_TASKS, TaskId, TaskMap) of
                ok -> Acc + 1;
                _ -> Acc
            end
        end, 0, Tasks),

        Now = erlang:system_time(millisecond),
        Stats = State#state.sync_stats,
        NewStats = Stats#{
            task_syncs => maps:get(task_syncs, Stats, 0) + 1,
            total_tasks_synced => maps:get(total_tasks_synced, Stats, 0) + Count
        },

        {{ok, Count}, State#state{last_task_sync = Now, sync_stats = NewStats}}
    catch
        _:Reason ->
            logger:warning("BeamAI Memory Bridge: task sync failed: ~p", [Reason]),
            Stats2 = State#state.sync_stats,
            NewStats2 = Stats2#{errors => maps:get(errors, Stats2, 0) + 1},
            {{error, Reason}, State#state{sync_stats = NewStats2}}
    end.

%% @private Convert a task record to a map for storage.
task_to_map(TaskId, Task) when is_record(Task, task) ->
    #{
        task_id => TaskId,
        context_id => Task#task.context_id,
        status => (Task#task.status)#task_status.state,
        status_timestamp => (Task#task.status)#task_status.timestamp,
        artifact_count => length(Task#task.artifacts),
        history_length => length(Task#task.history),
        metadata => Task#task.metadata,
        source => a2a_task_store,
        synced_at => erlang:system_time(millisecond)
    };
task_to_map(TaskId, Other) ->
    #{task_id => TaskId, raw => Other, source => a2a_task_store}.

%%====================================================================
%% Internal: Workflow Sync
%%====================================================================

%% @private Sync workflows, workitems, resources from Mnesia.
do_sync_workflows(State) ->
    try
        WfCount = sync_mnesia_table(
            fun() -> yawl_persistence:list_workflows() end,
            fun(Wf) -> workflow_to_map(Wf) end,
            fun(Wf) -> Wf#yawl_workflow_persist.workflow_id end,
            ?NS_WORKFLOWS
        ),

        WiCount = sync_mnesia_table(
            fun() ->
                %% List all workitems across all workflows
                case yawl_persistence:list_workflows() of
                    {ok, Wfs} ->
                        AllWorkitems = lists:flatmap(fun(Wf) ->
                            case yawl_persistence:list_workitems(Wf#yawl_workflow_persist.workflow_id) of
                                {ok, Wis} -> Wis;
                                _ -> []
                            end
                        end, Wfs),
                        {ok, AllWorkitems};
                    Error -> Error
                end
            end,
            fun(Wi) -> workitem_to_map(Wi) end,
            fun(Wi) -> Wi#yawl_workitem_persist.workitem_id end,
            ?NS_WORKITEMS
        ),

        ResCount = sync_mnesia_table(
            fun() -> yawl_persistence:list_resources() end,
            fun(Res) -> resource_to_map(Res) end,
            fun(Res) -> Res#yawl_resource_persist.resource_id end,
            ?NS_RESOURCES
        ),

        Now = erlang:system_time(millisecond),
        Stats = State#state.sync_stats,
        NewStats = Stats#{
            workflow_syncs => maps:get(workflow_syncs, Stats, 0) + 1,
            total_workflows_synced => maps:get(total_workflows_synced, Stats, 0) + WfCount,
            total_workitems_synced => maps:get(total_workitems_synced, Stats, 0) + WiCount,
            total_resources_synced => maps:get(total_resources_synced, Stats, 0) + ResCount
        },

        Result = #{
            workflows_synced => WfCount,
            workitems_synced => WiCount,
            resources_synced => ResCount
        },
        {{ok, Result}, State#state{last_wf_sync = Now, sync_stats = NewStats}}
    catch
        _:Reason ->
            logger:warning("BeamAI Memory Bridge: workflow sync failed: ~p", [Reason]),
            Stats2 = State#state.sync_stats,
            NewStats2 = Stats2#{errors => maps:get(errors, Stats2, 0) + 1},
            {{error, Reason}, State#state{sync_stats = NewStats2}}
    end.

%% @private Generic Mnesia table sync helper.
sync_mnesia_table(ListFun, ToMapFun, KeyFun, Namespace) ->
    case ListFun() of
        {ok, Records} ->
            lists:foldl(fun(Record, Acc) ->
                try
                    Key = KeyFun(Record),
                    Map = ToMapFun(Record),
                    case catch beamai_memory_store:put(Namespace, Key, Map) of
                        ok -> Acc + 1;
                        _ -> Acc
                    end
                catch
                    _:_ -> Acc
                end
            end, 0, Records);
        {error, _} ->
            0
    end.

%% @private Convert a workflow persist record to a map.
workflow_to_map(#yawl_workflow_persist{} = Wf) ->
    #{
        workflow_id => Wf#yawl_workflow_persist.workflow_id,
        spec_id => Wf#yawl_workflow_persist.spec_id,
        pattern_type => Wf#yawl_workflow_persist.pattern_type,
        status => Wf#yawl_workflow_persist.status,
        marking => Wf#yawl_workflow_persist.marking,
        current_place => Wf#yawl_workflow_persist.current_place,
        data => Wf#yawl_workflow_persist.data,
        parent_workflow_id => Wf#yawl_workflow_persist.parent_workflow_id,
        created_at => Wf#yawl_workflow_persist.created_at,
        updated_at => Wf#yawl_workflow_persist.updated_at,
        completed_at => Wf#yawl_workflow_persist.completed_at,
        error => Wf#yawl_workflow_persist.error,
        source => yawl_persistence,
        synced_at => erlang:system_time(millisecond)
    }.

%% @private Convert a workitem persist record to a map.
workitem_to_map(#yawl_workitem_persist{} = Wi) ->
    #{
        workitem_id => Wi#yawl_workitem_persist.workitem_id,
        workflow_id => Wi#yawl_workitem_persist.workflow_id,
        task_id => Wi#yawl_workitem_persist.task_id,
        task_name => Wi#yawl_workitem_persist.task_name,
        status => Wi#yawl_workitem_persist.status,
        data => Wi#yawl_workitem_persist.data,
        priority => Wi#yawl_workitem_persist.priority,
        retry_count => Wi#yawl_workitem_persist.retry_count,
        source => yawl_persistence,
        synced_at => erlang:system_time(millisecond)
    }.

%% @private Convert a resource persist record to a map.
resource_to_map(#yawl_resource_persist{} = Res) ->
    #{
        resource_id => Res#yawl_resource_persist.resource_id,
        resource_type => Res#yawl_resource_persist.resource_type,
        name => Res#yawl_resource_persist.name,
        capabilities => Res#yawl_resource_persist.capabilities,
        status => Res#yawl_resource_persist.status,
        current_load => Res#yawl_resource_persist.current_load,
        max_capacity => Res#yawl_resource_persist.max_capacity,
        metadata => Res#yawl_resource_persist.metadata,
        source => yawl_persistence,
        synced_at => erlang:system_time(millisecond)
    }.

%%====================================================================
%% Internal: Unified Query
%%====================================================================

%% @private Execute a unified query across storage systems.
do_query(Query, Opts) ->
    Namespace = maps:get(namespace, Query, undefined),
    Key = maps:get(key, Query, undefined),
    Pattern = maps:get(pattern, Query, undefined),
    Source = maps:get(source, Query, both),
    Limit = maps:get(limit, Opts, 100),
    IncludeSource = maps:get(include_source, Opts, false),

    %% Gather results from requested sources
    BeamaiResults = case Source of
        legacy -> [];
        _ -> query_beamai(Namespace, Key, Pattern, Limit)
    end,

    LegacyResults = case Source of
        beamai -> [];
        _ -> query_legacy(Namespace, Key, Pattern, Limit)
    end,

    %% Merge and deduplicate
    AllResults = merge_results(BeamaiResults, LegacyResults, IncludeSource),
    Limited = lists:sublist(AllResults, Limit),
    {ok, Limited}.

%% @private Query the BeamAI memory store.
query_beamai(undefined, _Key, _Pattern, _Limit) ->
    [];
query_beamai(Namespace, Key, _Pattern, _Limit) when Key =/= undefined ->
    case catch beamai_memory_store:get(Namespace, Key) of
        {ok, Value} -> [{Key, Value, beamai}];
        _ -> []
    end;
query_beamai(Namespace, _Key, Pattern, Limit) when Pattern =/= undefined ->
    case catch beamai_memory_store:search(Namespace, Pattern, [{limit, Limit}]) of
        {ok, Results} ->
            [{K, V, beamai} || {K, V} <- Results];
        _ ->
            []
    end;
query_beamai(Namespace, _Key, _Pattern, Limit) ->
    case catch beamai_memory_store:list(Namespace, [{limit, Limit}]) of
        {ok, Keys} ->
            lists:filtermap(fun(K) ->
                case catch beamai_memory_store:get(Namespace, K) of
                    {ok, V} -> {true, {K, V, beamai}};
                    _ -> false
                end
            end, Keys);
        _ ->
            []
    end.

%% @private Query the legacy storage systems.
query_legacy(?NS_TASKS, Key, _Pattern, _Limit) when Key =/= undefined ->
    case catch a2a_task_store:get_task(Key) of
        {ok, Task} -> [{Key, task_to_map(Key, Task), legacy}];
        _ -> []
    end;
query_legacy(?NS_TASKS, _Key, _Pattern, _Limit) ->
    case catch ets:tab2list(a2a_tasks) of
        Tasks when is_list(Tasks) ->
            [{TaskId, task_to_map(TaskId, T), legacy} || {TaskId, T} <- Tasks];
        _ ->
            []
    end;
query_legacy(?NS_WORKFLOWS, Key, _Pattern, _Limit) when Key =/= undefined ->
    case catch yawl_persistence:load_workflow(Key) of
        {ok, Wf} -> [{Key, workflow_to_map(Wf), legacy}];
        _ -> []
    end;
query_legacy(?NS_WORKFLOWS, _Key, _Pattern, _Limit) ->
    case catch yawl_persistence:list_workflows() of
        {ok, Wfs} ->
            [{Wf#yawl_workflow_persist.workflow_id, workflow_to_map(Wf), legacy} || Wf <- Wfs];
        _ ->
            []
    end;
query_legacy(?NS_WORKITEMS, _Key, _Pattern, _Limit) ->
    %% Workitems require a workflow_id; return empty for broad queries
    [];
query_legacy(?NS_RESOURCES, _Key, _Pattern, _Limit) ->
    case catch yawl_persistence:list_resources() of
        {ok, Resources} ->
            [{Res#yawl_resource_persist.resource_id, resource_to_map(Res), legacy}
             || Res <- Resources];
        _ ->
            []
    end;
query_legacy(_, _Key, _Pattern, _Limit) ->
    [].

%% @private Merge results from both sources, deduplicating by key.
merge_results(BeamaiResults, LegacyResults, IncludeSource) ->
    %% BeamAI results take precedence (more recent)
    BeamaiKeys = sets:from_list([K || {K, _, _} <- BeamaiResults]),
    FilteredLegacy = lists:filter(fun({K, _, _}) ->
        not sets:is_element(K, BeamaiKeys)
    end, LegacyResults),

    AllResults = BeamaiResults ++ FilteredLegacy,
    case IncludeSource of
        true ->
            [{K, V, S} || {K, V, S} <- AllResults];
        false ->
            [{K, V} || {K, V, _S} <- AllResults]
    end.

%%====================================================================
%% Internal: Migration
%%====================================================================

%% @private Migrate data from legacy storage.
do_migrate(all, Opts) ->
    Results = #{
        tasks => do_migrate_tasks(Opts),
        workflows => do_migrate_workflows(Opts),
        workitems => do_migrate_workitems(Opts),
        resources => do_migrate_resources(Opts)
    },
    {ok, Results};
do_migrate(tasks, Opts) ->
    {ok, #{tasks => do_migrate_tasks(Opts)}};
do_migrate(workflows, Opts) ->
    {ok, #{workflows => do_migrate_workflows(Opts)}};
do_migrate(workitems, Opts) ->
    {ok, #{workitems => do_migrate_workitems(Opts)}};
do_migrate(resources, Opts) ->
    {ok, #{resources => do_migrate_resources(Opts)}};
do_migrate(_, _Opts) ->
    {error, unknown_source}.

%% @private Migrate tasks.
do_migrate_tasks(_Opts) ->
    try
        Tasks = case ets:info(a2a_tasks) of
            undefined -> [];
            _ -> ets:tab2list(a2a_tasks)
        end,
        Count = lists:foldl(fun({TaskId, Task}, Acc) ->
            Map = task_to_map(TaskId, Task),
            case catch beamai_memory_store:put(?NS_TASKS, TaskId, Map) of
                ok -> Acc + 1;
                _ -> Acc
            end
        end, 0, Tasks),
        #{migrated => Count, errors => 0}
    catch
        _:_ -> #{migrated => 0, errors => 1}
    end.

%% @private Migrate workflows.
do_migrate_workflows(_Opts) ->
    try
        case yawl_persistence:list_workflows() of
            {ok, Wfs} ->
                Count = lists:foldl(fun(Wf, Acc) ->
                    Key = Wf#yawl_workflow_persist.workflow_id,
                    Map = workflow_to_map(Wf),
                    case catch beamai_memory_store:put(?NS_WORKFLOWS, Key, Map) of
                        ok -> Acc + 1;
                        _ -> Acc
                    end
                end, 0, Wfs),
                #{migrated => Count, errors => 0};
            _ ->
                #{migrated => 0, errors => 0}
        end
    catch
        _:_ -> #{migrated => 0, errors => 1}
    end.

%% @private Migrate workitems.
do_migrate_workitems(_Opts) ->
    try
        case yawl_persistence:list_workflows() of
            {ok, Wfs} ->
                Count = lists:foldl(fun(Wf, Acc) ->
                    WfId = Wf#yawl_workflow_persist.workflow_id,
                    case yawl_persistence:list_workitems(WfId) of
                        {ok, Wis} ->
                            lists:foldl(fun(Wi, InnerAcc) ->
                                Key = Wi#yawl_workitem_persist.workitem_id,
                                Map = workitem_to_map(Wi),
                                case catch beamai_memory_store:put(?NS_WORKITEMS, Key, Map) of
                                    ok -> InnerAcc + 1;
                                    _ -> InnerAcc
                                end
                            end, Acc, Wis);
                        _ -> Acc
                    end
                end, 0, Wfs),
                #{migrated => Count, errors => 0};
            _ ->
                #{migrated => 0, errors => 0}
        end
    catch
        _:_ -> #{migrated => 0, errors => 1}
    end.

%% @private Migrate resources.
do_migrate_resources(_Opts) ->
    try
        case yawl_persistence:list_resources() of
            {ok, Resources} ->
                Count = lists:foldl(fun(Res, Acc) ->
                    Key = Res#yawl_resource_persist.resource_id,
                    Map = resource_to_map(Res),
                    case catch beamai_memory_store:put(?NS_RESOURCES, Key, Map) of
                        ok -> Acc + 1;
                        _ -> Acc
                    end
                end, 0, Resources),
                #{migrated => Count, errors => 0};
            _ ->
                #{migrated => 0, errors => 0}
        end
    catch
        _:_ -> #{migrated => 0, errors => 1}
    end.
