%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-A2A Resource Allocation Integration
%%%
%%% This module provides resource allocation coordination between YAWL
%%% workflows and A2A tasks. It ensures that:
%%%
%%% - A2A tasks are properly mapped to YAWL resources
%%% - Resource availability is synchronized between systems
%%% - Resource allocation follows YAWL's allocation strategies
%%% - Resource release happens correctly on task completion
%%%
%%% ## Resource Types
%%%
%%% The integration supports these resource types from YAWL:
%%% - `human`: Human agents/users
%%% - `service`: External services
%%% - `system`: Internal system resources
%%%
%%% ## Usage
%%%
%%% ```erlang
%%% %% Start the resource integration
%%% yawl_a2a_resource_integration:start_link().
%%%
%%% %% Allocate a resource for a task
%%% {ok, ResourceId} = yawl_a2a_resource_integration:allocate_for_task(
%%%     TaskId, [human_task], human
%%% ).
%%%
%%% %% Release a resource when done
%%% ok = yawl_a2a_resource_integration:release_for_task(TaskId, ResourceId).
%%%
%%% %% Get resource info for a task
%%% {ok, ResourceInfo} = yawl_a2a_resource_integration:get_task_resource(TaskId).
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_a2a_resource_integration).
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

%% API - Resource allocation for tasks
-export([
    allocate_for_task/2,
    allocate_for_task/3,
    allocate_for_workitem/1,
    release_for_task/1,
    release_for_task/2,
    release_for_workitem/1
]).

%% API - Resource queries
-export([
    get_task_resource/1,
    get_workitem_resource/1,
    list_task_allocations/0,
    list_resource_allocations/1
]).

%% API - Resource state sync
-export([
    sync_resource_from_a2a/2,
    sync_resource_to_a2a/1,
    update_resource_status/2,
    update_resource_load/2
]).

%% API - Resource pool management
-export([
    register_resource_pool/3,
    unregister_resource_pool/1,
    get_pool_status/1
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").
%% -include("a2a.hrl").  %% A2A headers not available in this context

%%====================================================================
%% Records
%%====================================================================

-record(resource_pool, {
    pool_id :: binary(),
    resource_type :: resource_type(),
    resources :: [binary()],
    allocation_strategy :: round_robin | least_loaded | random,
    current_index :: non_neg_integer()
}).

-record(allocation_stats, {
    total_allocations :: non_neg_integer(),
    total_releases :: non_neg_integer(),
    active_allocations :: non_neg_integer(),
    by_type :: #{resource_type() => non_neg_integer()}
}).

-record(state, {
    %% Task ID -> Resource ID mapping
    task_allocations :: #{binary() => binary()},
    %% Workitem ID -> Resource ID mapping
    workitem_allocations :: #{binary() => binary()},
    %% Resource ID -> Task ID reverse mapping
    resource_to_task :: #{binary() => binary()},
    %% Resource pool tracking
    resource_pools :: #{binary() => #resource_pool{}},
    %% Allocation statistics
    statistics :: #allocation_stats{}
}).


%%====================================================================
%% Type Definitions
%%====================================================================

-type resource_pool() :: #resource_pool{}.
-type allocation_stats() :: #allocation_stats{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the resource integration server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Allocate a resource for a task (auto-detect type).
-spec allocate_for_task(binary(), [atom()]) -> {ok, binary()} | {error, term()}.
allocate_for_task(TaskId, Capabilities) ->
    gen_server:call(?MODULE, {allocate_for_task, TaskId, Capabilities}, infinity).

%% @doc Allocate a specific resource type for a task.
-spec allocate_for_task(binary(), [atom()], resource_type()) ->
    {ok, binary()} | {error, term()}.
allocate_for_task(TaskId, Capabilities, ResourceType) ->
    gen_server:call(?MODULE, {allocate_for_task, TaskId, Capabilities, ResourceType}, infinity).

%% @doc Allocate a resource for a YAWL workitem.
-spec allocate_for_workitem(#yawl_workitem_persist{}) -> {ok, binary()} | {error, term()}.
allocate_for_workitem(Workitem) ->
    gen_server:call(?MODULE, {allocate_for_workitem, Workitem}, infinity).

%% @doc Release the resource allocated for a task.
-spec release_for_task(binary()) -> ok | {error, term()}.
release_for_task(TaskId) ->
    gen_server:call(?MODULE, {release_for_task, TaskId}).

%% @doc Release a specific resource for a task.
-spec release_for_task(binary(), binary()) -> ok | {error, term()}.
release_for_task(TaskId, ResourceId) ->
    gen_server:call(?MODULE, {release_for_task, TaskId, ResourceId}).

%% @doc Release the resource allocated for a workitem.
-spec release_for_workitem(binary()) -> ok | {error, term()}.
release_for_workitem(WorkitemId) ->
    gen_server:call(?MODULE, {release_for_workitem, WorkitemId}).

%% @doc Get the resource allocated to a task.
-spec get_task_resource(binary()) -> {ok, binary()} | {error, not_found}.
get_task_resource(TaskId) ->
    gen_server:call(?MODULE, {get_task_resource, TaskId}).

%% @doc Get the resource allocated to a workitem.
-spec get_workitem_resource(binary()) -> {ok, binary()} | {error, not_found}.
get_workitem_resource(WorkitemId) ->
    gen_server:call(?MODULE, {get_workitem_resource, WorkitemId}).

%% @doc List all task allocations.
-spec list_task_allocations() -> [{binary(), binary()}].
list_task_allocations() ->
    gen_server:call(?MODULE, list_task_allocations).

%% @doc List all allocations for a resource.
-spec list_resource_allocations(binary()) -> [binary()].
list_resource_allocations(ResourceId) ->
    gen_server:call(?MODULE, {list_resource_allocations, ResourceId}).

%% @doc Sync resource state from A2A task update.
-spec sync_resource_from_a2a(binary(), map()) -> ok | {error, term()}.
sync_resource_from_a2a(ResourceId, State) ->
    gen_server:call(?MODULE, {sync_from_a2a, ResourceId, State}).

%% @doc Sync resource state to A2A task metadata.
-spec sync_resource_to_a2a(binary()) -> {ok, map()} | {error, term()}.
sync_resource_to_a2a(ResourceId) ->
    gen_server:call(?MODULE, {sync_to_a2a, ResourceId}).

%% @doc Update resource availability status.
-spec update_resource_status(binary(), resource_status()) -> ok | {error, term()}.
update_resource_status(ResourceId, Status) ->
    yawl_resource_manager:update_resource_status(ResourceId, Status).

%% @doc Update resource load level.
-spec update_resource_load(binary(), non_neg_integer()) -> ok | {error, term()}.
update_resource_load(ResourceId, Load) ->
    yawl_resource_manager:update_resource_load(ResourceId, Load).

%% @doc Register a resource pool.
-spec register_resource_pool(binary(), resource_type(), map()) -> ok | {error, term()}.
register_resource_pool(PoolId, ResourceType, Options) ->
    gen_server:call(?MODULE, {register_pool, PoolId, ResourceType, Options}).

%% @doc Unregister a resource pool.
-spec unregister_resource_pool(binary()) -> ok | {error, term()}.
unregister_resource_pool(PoolId) ->
    gen_server:call(?MODULE, {unregister_pool, PoolId}).

%% @doc Get the status of a resource pool.
-spec get_pool_status(binary()) -> {ok, map()} | {error, term()}.
get_pool_status(PoolId) ->
    gen_server:call(?MODULE, {get_pool_status, PoolId}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        task_allocations = #{},
        workitem_allocations = #{},
        resource_to_task = #{},
        resource_pools = #{},
        statistics = #allocation_stats{
            total_allocations = 0,
            total_releases = 0,
            active_allocations = 0,
            by_type = #{human => 0, service => 0, system => 0}
        }
    },
    {ok, State}.

%% @private
handle_call({allocate_for_task, TaskId, Capabilities}, _From, State) ->
    %% Auto-detect resource type from capabilities
    ResourceType = detect_resource_type(Capabilities),
    handle_call({allocate_for_task, TaskId, Capabilities, ResourceType}, _From, State);

handle_call({allocate_for_task, TaskId, Capabilities, ResourceType}, _From, State) ->
    case maps:get(TaskId, State#state.task_allocations, undefined) of
        undefined ->
            %% Use YAWL resource manager for allocation
            case yawl_resource_manager:allocate_resource(TaskId, ResourceType, Capabilities) of
                {ok, ResourceId, Resource} ->
                    %% Update state
                    NewTaskAllocs = maps:put(TaskId, ResourceId, State#state.task_allocations),
                    NewResourceToTask = maps:put(ResourceId, TaskId, State#state.resource_to_task),

                    %% Update statistics
                    NewStats = update_allocation_stats(ResourceType, State#state.statistics),

                    NewState = State#state{
                        task_allocations = NewTaskAllocs,
                        resource_to_task = NewResourceToTask,
                        statistics = NewStats
                    },

                    %% Notify event system
                    yawl_a2a_events:notify(resource_allocated, #{
                        task_id => TaskId,
                        resource_id => ResourceId,
                        resource_type => ResourceType,
                        resource => Resource
                    }),

                    {reply, {ok, ResourceId}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        ResourceId ->
            %% Already allocated, return existing
            {reply, {ok, ResourceId}, State}
    end;

handle_call({allocate_for_workitem, Workitem}, _From, State) ->
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,

    case maps:get(WorkitemId, State#state.workitem_allocations, undefined) of
        undefined ->
            %% Determine resource type and capabilities from workitem
            {ResourceType, Capabilities} = extract_resource_info(Workitem),

            %% Allocate using YAWL resource manager
            case yawl_resource_manager:allocate_resource(WorkitemId, ResourceType, Capabilities) of
                {ok, ResourceId, Resource} ->
                    %% Update state
                    NewWorkitemAllocs = maps:put(WorkitemId, ResourceId, State#state.workitem_allocations),
                    NewResourceToTask = maps:put(ResourceId, WorkitemId, State#state.resource_to_task),

                    %% Update statistics
                    NewStats = update_allocation_stats(ResourceType, State#state.statistics),

                    NewState = State#state{
                        workitem_allocations = NewWorkitemAllocs,
                        resource_to_task = NewResourceToTask,
                        statistics = NewStats
                    },

                    %% Notify event system
                    yawl_a2a_events:notify(workitem_resource_allocated, #{
                        workitem_id => WorkitemId,
                        resource_id => ResourceId,
                        resource_type => ResourceType
                    }),

                    {reply, {ok, ResourceId}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        ResourceId ->
            %% Already allocated
            {reply, {ok, ResourceId}, State}
    end;

handle_call({release_for_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.task_allocations, undefined) of
        undefined ->
            {reply, {error, no_allocation}, State};
        ResourceId ->
            case yawl_resource_manager:release_resource(TaskId, ResourceId) of
                ok ->
                    NewState = remove_allocation(TaskId, ResourceId, State),

                    %% Notify event system
                    yawl_a2a_events:notify(resource_released, #{
                        task_id => TaskId,
                        resource_id => ResourceId
                    }),

                    {reply, ok, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({release_for_task, TaskId, ResourceId}, _From, State) ->
    case maps:get(TaskId, State#state.task_allocations, undefined) of
        ResourceId ->
            %% Correct resource ID, proceed with release
            case yawl_resource_manager:release_resource(TaskId, ResourceId) of
                ok ->
                    NewState = remove_allocation(TaskId, ResourceId, State),
                    {reply, ok, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        _ ->
            %% Different resource ID, error
            {reply, {error, allocation_mismatch}, State}
    end;

handle_call({release_for_workitem, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitem_allocations, undefined) of
        undefined ->
            {reply, {error, no_allocation}, State};
        ResourceId ->
            case yawl_resource_manager:release_resource(WorkitemId, ResourceId) of
                ok ->
                    NewWorkitemAllocs = maps:remove(WorkitemId, State#state.workitem_allocations),
                    NewResourceToTask = maps:remove(ResourceId, State#state.resource_to_task),
                    NewState = State#state{
                        workitem_allocations = NewWorkitemAllocs,
                        resource_to_task = NewResourceToTask
                    },
                    {reply, ok, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({get_task_resource, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.task_allocations, undefined) of
        undefined -> {reply, {error, not_found}, State};
        ResourceId -> {reply, {ok, ResourceId}, State}
    end;

handle_call({get_workitem_resource, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitem_allocations, undefined) of
        undefined -> {reply, {error, not_found}, State};
        ResourceId -> {reply, {ok, ResourceId}, State}
    end;

handle_call(list_task_allocations, _From, State) ->
    Allocations = maps:to_list(State#state.task_allocations),
    {reply, Allocations, State};

handle_call({list_resource_allocations, ResourceId}, _From, State) ->
    TaskIds = [Task || {Task, Res} <- maps:to_list(State#state.task_allocations),
                        Res =:= ResourceId],
    {reply, TaskIds, State};

handle_call({sync_from_a2a, ResourceId, ResourceState}, _From, State) ->
    %% Sync resource state from A2A task metadata to YAWL
    Status = maps:get(status, ResourceState, available),
    Load = maps:get(load, ResourceState, 0),

    case yawl_resource_manager:update_resource_status(ResourceId, Status) of
        ok ->
            case yawl_resource_manager:update_resource_load(ResourceId, Load) of
                ok ->
                    {reply, ok, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({sync_to_a2a, ResourceId}, _From, State) ->
    %% Get resource info from YAWL and format for A2A
    case yawl_resource_manager:get_resource(ResourceId) of
        {ok, ResourceMap} ->
            ResourceState = #{
                resource_id => ResourceId,
                status => maps:get(status, ResourceMap, available),
                load => maps:get(current_load, ResourceMap, 0),
                capacity => maps:get(max_capacity, ResourceMap, 10),
                type => maps:get(resource_type, ResourceMap, service),
                capabilities => maps:get(capabilities, ResourceMap, [])
            },
            {reply, {ok, ResourceState}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({register_pool, PoolId, ResourceType, Options}, _From, State) ->
    Strategy = maps:get(allocation_strategy, Options, least_loaded),
    Resources = maps:get(resources, Options, []),
    Pool = #resource_pool{
        pool_id = PoolId,
        resource_type = ResourceType,
        resources = Resources,
        allocation_strategy = Strategy,
        current_index = 0
    },
    NewPools = maps:put(PoolId, Pool, State#state.resource_pools),
    {reply, ok, State#state{resource_pools = NewPools}};

handle_call({unregister_pool, PoolId}, _From, State) ->
    NewPools = maps:remove(PoolId, State#state.resource_pools),
    {reply, ok, State#state{resource_pools = NewPools}};

handle_call({get_pool_status, PoolId}, _From, State) ->
    case maps:get(PoolId, State#state.resource_pools, undefined) of
        undefined ->
            {reply, {error, pool_not_found}, State};
        Pool ->
            Status = #{
                pool_id => Pool#resource_pool.pool_id,
                resource_type => Pool#resource_pool.resource_type,
                resource_count => length(Pool#resource_pool.resources),
                allocation_strategy => Pool#resource_pool.allocation_strategy
            },
            {reply, {ok, Status}, State}
    end;

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
detect_resource_type(Capabilities) ->
    case lists:member(human_task, Capabilities) orelse
         lists:member(user_interaction, Capabilities) of
        true -> human;
        false ->
            case lists:member(external_service, Capabilities) of
                true -> service;
                false -> system
            end
    end.

%% @private
extract_resource_info(Workitem) ->
    Data = Workitem#yawl_workitem_persist.data,

    %% Get task type from workitem data
    TaskType = maps_get(task_type, Data, code),

    %% Determine resource type and capabilities based on task
    {ResourceType, Capabilities} = case TaskType of
        human ->
            {human, maps_get(capabilities, Data, [human_task])};
        service ->
            {service, maps_get(capabilities, Data, [external_service])};
        _ ->
            {system, maps_get(capabilities, Data, [code_execution])}
    end,

    {ResourceType, Capabilities}.

%% @private
remove_allocation(TaskId, ResourceId, State) ->
    NewTaskAllocs = maps:remove(TaskId, State#state.task_allocations),
    NewResourceToTask = maps:remove(ResourceId, State#state.resource_to_task),

    %% Update statistics
    OldStats = State#state.statistics,
    NewStats = OldStats#allocation_stats{
        total_releases = OldStats#allocation_stats.total_releases + 1,
        active_allocations = max(0, OldStats#allocation_stats.active_allocations - 1)
    },

    State#state{
        task_allocations = NewTaskAllocs,
        resource_to_task = NewResourceToTask,
        statistics = NewStats
    }.

%% @private
update_allocation_stats(ResourceType, Stats) ->
    ByType = Stats#allocation_stats.by_type,
    CurrentCount = maps:get(ResourceType, ByType, 0),

    Stats#allocation_stats{
        total_allocations = Stats#allocation_stats.total_allocations + 1,
        active_allocations = Stats#allocation_stats.active_allocations + 1,
        by_type = maps:put(ResourceType, CurrentCount + 1, ByType)
    }.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
