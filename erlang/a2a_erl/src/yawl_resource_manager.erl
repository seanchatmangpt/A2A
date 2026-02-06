%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Resource Manager
%%%
%%% This module handles dynamic resource allocation for YAWL workflows.
%%% It manages:
%%%
%%% - Human resources (users, groups)
%%% - Service resources (external services)
%%% - System resources (internal services)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_resource_manager).
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

%% API exports - Resource management
-export([
    register_resource/2,
    register_resource/3,
    unregister_resource/1,
    get_resource/1,
    list_resources/0,
    list_resources_by_type/1,
    list_available_resources/0
]).

%% API exports - Resource allocation
-export([
    allocate_resource/2,
    allocate_resource/3,
    release_resource/1,
    release_resource/2,
    update_resource_status/2,
    update_resource_load/2
]).

%% API exports - Resource capabilities
-export([
    add_capability/2,
    remove_capability/2,
    find_resources_by_capability/1,
    find_resources_by_capabilities/1
]).

%% API exports - Allocation strategy management
-export([
    set_allocation_strategy/1,
    get_allocation_strategy/0
]).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    resources :: #{binary() => #yawl_resource_persist{}},
    allocations :: #{binary() => binary()},  %% workitem_id => resource_id
    resource_by_type :: #{resource_type() => [binary()]},
    resource_by_capability :: #{atom() => [binary()]},
    allocation_strategy :: round_robin | least_loaded | random,
    round_robin_state :: #{atom() => integer()}  %% Type -> Next index for round-robin
}).


%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the resource manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a resource.
-spec register_resource(binary(), resource_type()) -> {ok, binary()} | {error, term()}.
register_resource(ResourceName, ResourceType) ->
    register_resource(ResourceName, ResourceType, #{}).

%% @doc Register a resource with options.
-spec register_resource(binary(), resource_type(), map()) -> {ok, binary()} | {error, term()}.
register_resource(ResourceName, ResourceType, Options) ->
    gen_server:call(?MODULE, {register_resource, ResourceName, ResourceType, Options}).

%% @doc Unregister a resource.
-spec unregister_resource(binary()) -> ok | {error, term()}.
unregister_resource(ResourceId) ->
    gen_server:call(?MODULE, {unregister_resource, ResourceId}).

%% @doc Get a resource by ID.
-spec get_resource(binary()) -> {ok, map()} | {error, term()}.
get_resource(ResourceId) ->
    gen_server:call(?MODULE, {get_resource, ResourceId}).

%% @doc List all resources.
-spec list_resources() -> {ok, [map()]}.
list_resources() ->
    gen_server:call(?MODULE, list_resources).

%% @doc List resources by type.
-spec list_resources_by_type(resource_type()) -> {ok, [map()]}.
list_resources_by_type(Type) ->
    gen_server:call(?MODULE, {list_resources_by_type, Type}).

%% @doc List available resources.
-spec list_available_resources() -> {ok, [map()]}.
list_available_resources() ->
    gen_server:call(?MODULE, list_available_resources).

%% @doc Allocate a resource for a work item.
-spec allocate_resource(binary(), [atom()]) -> {ok, binary(), map()} | {error, term()}.
allocate_resource(WorkitemId, RequiredCapabilities) ->
    gen_server:call(?MODULE, {allocate_resource, WorkitemId, RequiredCapabilities}).

%% @doc Allocate a specific resource type for a work item.
-spec allocate_resource(binary(), resource_type(), [atom()]) -> {ok, binary(), map()} | {error, term()}.
allocate_resource(WorkitemId, ResourceType, RequiredCapabilities) ->
    gen_server:call(?MODULE, {allocate_resource, WorkitemId, ResourceType, RequiredCapabilities}).

%% @doc Release a resource allocation.
-spec release_resource(binary()) -> ok | {error, term()}.
release_resource(WorkitemId) ->
    gen_server:call(?MODULE, {release_resource, WorkitemId}).

%% @doc Release a specific resource.
-spec release_resource(binary(), binary()) -> ok | {error, term()}.
release_resource(WorkitemId, ResourceId) ->
    gen_server:call(?MODULE, {release_resource, WorkitemId, ResourceId}).

%% @doc Update resource status.
-spec update_resource_status(binary(), resource_status()) -> ok | {error, term()}.
update_resource_status(ResourceId, Status) ->
    gen_server:call(?MODULE, {update_resource_status, ResourceId, Status}).

%% @doc Update resource load.
-spec update_resource_load(binary(), non_neg_integer()) -> ok | {error, term()}.
update_resource_load(ResourceId, Load) ->
    gen_server:call(?MODULE, {update_resource_load, ResourceId, Load}).

%% @doc Add a capability to a resource.
-spec add_capability(binary(), atom()) -> ok | {error, term()}.
add_capability(ResourceId, Capability) ->
    gen_server:call(?MODULE, {add_capability, ResourceId, Capability}).

%% @doc Remove a capability from a resource.
-spec remove_capability(binary(), atom()) -> ok | {error, term()}.
remove_capability(ResourceId, Capability) ->
    gen_server:call(?MODULE, {remove_capability, ResourceId, Capability}).

%% @doc Find resources by capability.
-spec find_resources_by_capability(atom()) -> {ok, [map()]}.
find_resources_by_capability(Capability) ->
    gen_server:call(?MODULE, {find_resources_by_capability, Capability}).

%% @doc Find resources by multiple capabilities (all required).
-spec find_resources_by_capabilities([atom()]) -> {ok, [map()]}.
find_resources_by_capabilities(Capabilities) ->
    gen_server:call(?MODULE, {find_resources_by_capabilities, Capabilities}).

%% @doc Set the allocation strategy.
-spec set_allocation_strategy(round_robin | least_loaded | random) -> ok | {error, term()}.
set_allocation_strategy(Strategy) ->
    gen_server:call(?MODULE, {set_allocation_strategy, Strategy}).

%% @doc Get the current allocation strategy.
-spec get_allocation_strategy() -> {ok, round_robin | least_loaded | random}.
get_allocation_strategy() ->
    gen_server:call(?MODULE, get_allocation_strategy).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        resources = #{},
        allocations = #{},
        resource_by_type = #{human => [], service => [], system => []},
        resource_by_capability = #{},
        allocation_strategy = least_loaded,
        round_robin_state = #{}
    },
    {ok, State}.

%% @private
handle_call({register_resource, ResourceName, ResourceType, Options}, _From, State) ->
    ResourceId = generate_resource_id(ResourceName, ResourceType),

    Capabilities = maps:get(capabilities, Options, []),
    MaxCapacity = maps:get(max_capacity, Options, 10),
    Attributes = maps:get(attributes, Options, #{}),

    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = ResourceType,
        name = ResourceName,
        capabilities = Capabilities,
        attributes = Attributes,
        status = available,
        current_load = 0,
        max_capacity = MaxCapacity,
        last_heartbeat = erlang:monotonic_time(millisecond),
        metadata = maps:get(metadata, Options, #{})
    },

    NewResources = maps:put(ResourceId, Resource, State#state.resources),
    NewByType = update_resource_by_type(ResourceType, ResourceId, State#state.resource_by_type),
    NewByCapability = update_resource_by_capability(Capabilities, ResourceId, State#state.resource_by_capability),

    %% Persist the resource
    case whereis(yawl_persistence) of
        undefined -> ok;
        _Pid -> yawl_persistence:save_resource(Resource)
    end,

    NewState = State#state{
        resources = NewResources,
        resource_by_type = NewByType,
        resource_by_capability = NewByCapability
    },
    {reply, {ok, ResourceId}, NewState};

handle_call({unregister_resource, ResourceId}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        Resource ->
            NewResources = maps:remove(ResourceId, State#state.resources),
            NewByType = remove_resource_by_type(Resource#yawl_resource_persist.resource_type, ResourceId, State#state.resource_by_type),
            NewByCapability = remove_resource_by_capability(Resource#yawl_resource_persist.capabilities, ResourceId, State#state.resource_by_capability),

            NewState = State#state{
                resources = NewResources,
                resource_by_type = NewByType,
                resource_by_capability = NewByCapability
            },
            {reply, ok, NewState}
    end;

handle_call({get_resource, ResourceId}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        Resource ->
            {reply, {ok, resource_to_map(Resource)}, State}
    end;

handle_call(list_resources, _From, State) ->
    Resources = [resource_to_map(R) || R <- maps:values(State#state.resources)],
    {reply, {ok, Resources}, State};

handle_call({list_resources_by_type, Type}, _From, State) ->
    ResourceIds = maps:get(Type, State#state.resource_by_type, []),
    Resources = lists:filtermap(fun(Id) ->
        case maps:get(Id, State#state.resources, undefined) of
            undefined -> false;
            Resource -> {true, resource_to_map(Resource)}
        end
    end, ResourceIds),
    {reply, {ok, Resources}, State};

handle_call(list_available_resources, _From, State) ->
    Resources = maps:filter(fun(_Id, Resource) ->
        case Resource#yawl_resource_persist.status of
            available ->
                Resource#yawl_resource_persist.current_load < Resource#yawl_resource_persist.max_capacity;
            _ -> false
        end
    end, State#state.resources),
    ResourceMaps = lists:map(fun resource_to_map/1, maps:values(Resources)),
    {reply, {ok, ResourceMaps}, State};

handle_call({allocate_resource, WorkitemId, RequiredCapabilities}, _From, State) ->
    case find_best_resource(RequiredCapabilities, State) of
        {ok, ResourceId, Resource} ->
            NewAllocations = maps:put(WorkitemId, ResourceId, State#state.allocations),
            NewResources = maps:update_with(ResourceId,
                fun(R) -> R#yawl_resource_persist{
                    current_load = R#yawl_resource_persist.current_load + 1,
                    status = case R#yawl_resource_persist.current_load + 1 of
                        L when L >= R#yawl_resource_persist.max_capacity -> busy;
                        _ -> R#yawl_resource_persist.status
                    end,
                    last_heartbeat = erlang:monotonic_time(millisecond)
                } end,
                State#state.resources
            ),
            UpdateRoundRobin = update_round_robin_state(Resource#yawl_resource_persist.resource_type, ResourceId, State),
            NewState = State#state{allocations = NewAllocations, resources = NewResources, round_robin_state = UpdateRoundRobin},
            {reply, {ok, ResourceId, resource_to_map(Resource)}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({allocate_resource, WorkitemId, ResourceType, RequiredCapabilities}, _From, State) ->
    ResourceIds = maps:get(ResourceType, State#state.resource_by_type, []),
    case find_best_resource_in_list(ResourceIds, RequiredCapabilities, State) of
        {ok, ResourceId, Resource} ->
            NewAllocations = maps:put(WorkitemId, ResourceId, State#state.allocations),
            NewResources = maps:update_with(ResourceId,
                fun(R) -> R#yawl_resource_persist{
                    current_load = R#yawl_resource_persist.current_load + 1,
                    status = case R#yawl_resource_persist.current_load + 1 of
                        L when L >= R#yawl_resource_persist.max_capacity -> busy;
                        _ -> R#yawl_resource_persist.status
                    end,
                    last_heartbeat = erlang:monotonic_time(millisecond)
                } end,
                State#state.resources
            ),
            UpdateRoundRobin = update_round_robin_state(ResourceType, ResourceId, State),
            NewState = State#state{allocations = NewAllocations, resources = NewResources, round_robin_state = UpdateRoundRobin},
            {reply, {ok, ResourceId, resource_to_map(Resource)}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({release_resource, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.allocations, undefined) of
        undefined ->
            {reply, {error, allocation_not_found}, State};
        ResourceId ->
            NewAllocations = maps:remove(WorkitemId, State#state.allocations),
            NewResources = maps:update_with(ResourceId,
                fun(R) -> R#yawl_resource_persist{
                    current_load = max(0, R#yawl_resource_persist.current_load - 1),
                    status = case R#yawl_resource_persist.current_load - 1 of
                        0 -> available;
                        _ when R#yawl_resource_persist.status =:= busy -> available;
                        _ -> R#yawl_resource_persist.status
                    end,
                    last_heartbeat = erlang:monotonic_time(millisecond)
                } end,
                State#state.resources
            ),
            NewState = State#state{allocations = NewAllocations, resources = NewResources},
            {reply, ok, NewState}
    end;

handle_call({release_resource, WorkitemId, ResourceId}, _From, State) ->
    case maps:get(WorkitemId, State#state.allocations, undefined) of
        ResourceId ->
            NewAllocations = maps:remove(WorkitemId, State#state.allocations),
            NewResources = maps:update_with(ResourceId,
                fun(R) -> R#yawl_resource_persist{
                    current_load = max(0, R#yawl_resource_persist.current_load - 1),
                    status = available,
                    last_heartbeat = erlang:monotonic_time(millisecond)
                } end,
                State#state.resources
            ),
            NewState = State#state{allocations = NewAllocations, resources = NewResources},
            {reply, ok, NewState};
        _ ->
            {reply, {error, allocation_mismatch}, State}
    end;

handle_call({update_resource_status, ResourceId, Status}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        _Resource ->
            NewResources = maps:update_with(ResourceId,
                fun(R) -> R#yawl_resource_persist{status = Status, last_heartbeat = erlang:monotonic_time(millisecond)} end,
                State#state.resources
            ),
            NewState = State#state{resources = NewResources},
            {reply, ok, NewState}
    end;

handle_call({update_resource_load, ResourceId, Load}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        _Resource ->
            NewResources = maps:update_with(ResourceId,
                fun(R) ->
                    NewStatus = case Load >= R#yawl_resource_persist.max_capacity of
                        true -> busy;
                        false when R#yawl_resource_persist.status =:= busy -> available;
                        _ -> R#yawl_resource_persist.status
                    end,
                    R#yawl_resource_persist{
                        current_load = Load,
                        status = NewStatus,
                        last_heartbeat = erlang:monotonic_time(millisecond)
                    } end,
                State#state.resources
            ),
            NewState = State#state{resources = NewResources},
            {reply, ok, NewState}
    end;

handle_call({add_capability, ResourceId, Capability}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        Resource ->
            Capabilities = Resource#yawl_resource_persist.capabilities,
            case lists:member(Capability, Capabilities) of
                true ->
                    {reply, ok, State};
                false ->
                    NewCapabilities = [Capability | Capabilities],
                    NewResource = Resource#yawl_resource_persist{capabilities = NewCapabilities},
                    NewResources = maps:put(ResourceId, NewResource, State#state.resources),
                    NewByCapability = update_resource_by_capability([Capability], ResourceId, State#state.resource_by_capability),
                    NewState = State#state{resources = NewResources, resource_by_capability = NewByCapability},
                    {reply, ok, NewState}
            end
    end;

handle_call({remove_capability, ResourceId, Capability}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        Resource ->
            NewCapabilities = lists:delete(Capability, Resource#yawl_resource_persist.capabilities),
            NewResource = Resource#yawl_resource_persist{capabilities = NewCapabilities},
            NewResources = maps:put(ResourceId, NewResource, State#state.resources),
            NewByCapability = remove_resource_by_capability([Capability], ResourceId, State#state.resource_by_capability),
            NewState = State#state{resources = NewResources, resource_by_capability = NewByCapability},
            {reply, ok, NewState}
    end;

handle_call({find_resources_by_capability, Capability}, _From, State) ->
    ResourceIds = maps:get(Capability, State#state.resource_by_capability, []),
    Resources = lists:filtermap(fun(Id) ->
        case maps:get(Id, State#state.resources, undefined) of
            undefined -> false;
            Resource -> {true, resource_to_map(Resource)}
        end
    end, ResourceIds),
    {reply, {ok, Resources}, State};

handle_call({find_resources_by_capabilities, Capabilities}, _From, State) ->
    %% Find resources that have ALL the required capabilities
    AllResourceIds = lists:foldl(fun(Cap, Acc) ->
        Ids = maps:get(Cap, State#state.resource_by_capability, []),
        sets:to_list(sets:intersection(sets:from_list(Acc), sets:from_list(Ids)))
    end, maps:keys(State#state.resources), Capabilities),

    Resources = lists:filtermap(fun(Id) ->
        case maps:get(Id, State#state.resources, undefined) of
            undefined -> false;
            Resource -> {true, resource_to_map(Resource)}
        end
    end, AllResourceIds),
    {reply, {ok, Resources}, State};

handle_call(set_allocation_strategy, _From, State) ->
    Strategy = State#state.allocation_strategy,
    {reply, {ok, Strategy}, State};

handle_call({set_allocation_strategy, Strategy}, _From, State) ->
    %% Validate strategy
    case lists:member(Strategy, [least_loaded, round_robin, random]) of
        true ->
            NewState = State#state{allocation_strategy = Strategy},
            {reply, ok, NewState};
        false ->
            {reply, {error, invalid_allocation_strategy}, State}
    end;

handle_call(get_allocation_strategy, _From, State) ->
    Strategy = State#state.allocation_strategy,
    {reply, {ok, Strategy}, State};

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
generate_resource_id(ResourceName, ResourceType) ->
    NameHash = erlang:phash2(ResourceName),
    TypeBin = atom_to_binary(ResourceType, utf8),
    Timestamp = erlang:monotonic_time(millisecond),
    <<TypeBin/binary, "_",
      (integer_to_binary(NameHash))/binary, "_",
      (integer_to_binary(Timestamp))/binary>>.

%% @private
update_resource_by_type(ResourceType, ResourceId, ByTypeMap) ->
    CurrentList = maps:get(ResourceType, ByTypeMap, []),
    ByTypeMap#{ResourceType => [ResourceId | CurrentList]}.

%% @private
remove_resource_by_type(ResourceType, ResourceId, ByTypeMap) ->
    CurrentList = maps:get(ResourceType, ByTypeMap, []),
    ByTypeMap#{ResourceType => lists:delete(ResourceId, CurrentList)}.

%% @private
update_resource_by_capability([], _ResourceId, ByCapabilityMap) ->
    ByCapabilityMap;
update_resource_by_capability([Capability | Rest], ResourceId, ByCapabilityMap) ->
    CurrentList = maps:get(Capability, ByCapabilityMap, []),
    NewMap = ByCapabilityMap#{Capability => [ResourceId | CurrentList]},
    update_resource_by_capability(Rest, ResourceId, NewMap).

%% @private
remove_resource_by_capability([], _ResourceId, ByCapabilityMap) ->
    ByCapabilityMap;
remove_resource_by_capability([Capability | Rest], ResourceId, ByCapabilityMap) ->
    CurrentList = maps:get(Capability, ByCapabilityMap, []),
    NewMap = ByCapabilityMap#{Capability => lists:delete(ResourceId, CurrentList)},
    remove_resource_by_capability(Rest, ResourceId, NewMap).

%% @private
find_best_resource(RequiredCapabilities, State) ->
    %% If no capabilities required, consider all resources
    case RequiredCapabilities of
        [] ->
            AllResourceIds = maps:keys(State#state.resources);
        _ ->
            %% Find resources that have all required capabilities
            AllResourceIds = lists:foldl(fun(Cap, Acc) ->
                Ids = maps:get(Cap, State#state.resource_by_capability, []),
                case Acc of
                    [] -> Ids;
                    _ -> lists:filter(fun(Id) -> lists:member(Id, Acc) end, Ids)
                end
            end, [], RequiredCapabilities)
    end,

    %% Filter by availability and capacity
    AvailableIds = lists:filter(fun(Id) ->
        case maps:get(Id, State#state.resources, undefined) of
            undefined -> false;
            Resource ->
                Resource#yawl_resource_persist.status =:= available andalso
                Resource#yawl_resource_persist.current_load < Resource#yawl_resource_persist.max_capacity
        end
    end, AllResourceIds),

    case AvailableIds of
        [] ->
            {error, no_available_resources};
        _ ->
            %% Select based on strategy
            BestId = select_by_strategy(State#state.allocation_strategy, AvailableIds, State#state.resources, State#state.round_robin_state),
            Resource = maps:get(BestId, State#state.resources),
            {ok, BestId, Resource}
    end.

%% @private
find_best_resource_in_list(ResourceIds, RequiredCapabilities, State) ->
    %% Filter by capabilities
    MatchingIds = case RequiredCapabilities of
        [] ->
            %% If no capabilities required, all resources match
            ResourceIds;
        _ ->
            %% Filter by capabilities
            lists:filter(fun(Id) ->
                case maps:get(Id, State#state.resources, undefined) of
                    undefined -> false;
                    Resource ->
                        ResourceCaps = Resource#yawl_resource_persist.capabilities,
                        lists:all(fun(C) -> lists:member(C, ResourceCaps) end, RequiredCapabilities)
                end
            end, ResourceIds)
    end,

    %% Filter by availability and capacity
    AvailableIds = lists:filter(fun(Id) ->
        case maps:get(Id, State#state.resources, undefined) of
            undefined -> false;
            Resource ->
                Resource#yawl_resource_persist.status =:= available andalso
                Resource#yawl_resource_persist.current_load < Resource#yawl_resource_persist.max_capacity
        end
    end, MatchingIds),

    case AvailableIds of
        [] ->
            {error, no_available_resources};
        _ ->
            BestId = select_by_strategy(State#state.allocation_strategy, AvailableIds, State#state.resources, State#state.round_robin_state),
            Resource = maps:get(BestId, State#state.resources),
            {ok, BestId, Resource}
    end.

%% @private
select_by_least_loaded(ResourceIds, Resources) ->
    lists:foldl(fun(Id, BestId) ->
        case maps:get(Id, Resources, undefined) of
            undefined -> BestId;
            Resource ->
                case maps:get(BestId, Resources, undefined) of
                    undefined -> Id;
                    BestResource ->
                        case Resource#yawl_resource_persist.current_load < BestResource#yawl_resource_persist.current_load of
                            true -> Id;
                            false -> BestId
                        end
                end
        end
    end, hd(ResourceIds), ResourceIds).

%% @private
%% @private
resource_to_map(#yawl_resource_persist{} = Resource) ->
    #{
        resource_id => Resource#yawl_resource_persist.resource_id,
        resource_type => Resource#yawl_resource_persist.resource_type,
        name => Resource#yawl_resource_persist.name,
        capabilities => Resource#yawl_resource_persist.capabilities,
        attributes => Resource#yawl_resource_persist.attributes,
        status => Resource#yawl_resource_persist.status,
        current_load => Resource#yawl_resource_persist.current_load,
        max_capacity => Resource#yawl_resource_persist.max_capacity,
        last_heartbeat => Resource#yawl_resource_persist.last_heartbeat,
        metadata => Resource#yawl_resource_persist.metadata
    }.

%%====================================================================
%% Allocation Strategy Functions
%%====================================================================

%% @private
select_by_strategy(Strategy, ResourceIds, Resources, RoundRobinState) ->
    case Strategy of
        least_loaded ->
            select_by_least_loaded(ResourceIds, Resources);
        round_robin ->
            select_by_round_robin(ResourceIds, Resources, RoundRobinState);
        random ->
            select_by_random(ResourceIds, Resources)
    end.

%% @private
select_by_round_robin(ResourceIds, Resources, RoundRobinState) ->
    %% Extract resource types from available resources
    ResourceTypes = lists:foldl(fun(Id, Acc) ->
        case maps:get(Id, Resources, undefined) of
            undefined -> Acc;
            Resource -> [Resource#yawl_resource_persist.resource_type | Acc]
        end
    end, [], ResourceIds),

    case ResourceTypes of
        [] ->
            %% Fallback to least loaded if no types
            select_by_least_loaded(ResourceIds, Resources);
        _ ->
            %% Get unique resource types
            UniqueTypes = lists:usort(ResourceTypes),

            %% Get resource IDs grouped by type
            ResourcesByType = maps:fold(fun(Type, Ids, Acc) ->
                Acc#{Type => lists:filter(fun(Id) -> lists:member(Id, Ids) end, ResourceIds)}
            end, #{}, #{
                human => ResourceIds,
                service => ResourceIds,
                system => ResourceIds
            }),

            %% Try to get next resource from each type using round-robin
            SelectedId = select_round_robin_by_type(UniqueTypes, ResourcesByType, Resources, RoundRobinState, 1),
            case SelectedId of
                undefined -> select_by_least_loaded(ResourceIds, Resources);
                _ -> SelectedId
            end
    end.

%% @private
select_round_robin_by_type([], _ResourcesByType, _Resources, _RoundRobinState, _Depth) ->
    %% Fallback to first available if no type selection found
    undefined;

select_round_robin_by_type([Type | Rest], ResourcesByType, Resources, RoundRobinState, Depth) when Depth =< 3 ->
    %% Get resources for this type
    TypeResources = maps:get(Type, ResourcesByType, []),

    if TypeResources =/= [] ->
        %% Get next round-robin index for this type
        NextIndex = maps:get(Type, RoundRobinState, 0),
        SelectedIndex = NextIndex rem length(TypeResources),
        SelectedId = lists:nth(SelectedIndex + 1, TypeResources),

        %% Verify the selected resource is still available
        case maps:get(SelectedId, Resources, undefined) of
            undefined ->
                %% Remove invalid resource and try again
                NewTypeResources = lists:delete(SelectedId, TypeResources),
                case NewTypeResources of
                    [] ->
                        %% Try next type
                        select_round_robin_by_type(Rest, ResourcesByType, Resources, RoundRobinState, Depth + 1);
                    _ ->
                        %% Select from remaining resources
                        NewResourcesByType = ResourcesByType#{Type => NewTypeResources},
                        select_round_robin_by_type([Type | Rest], NewResourcesByType, Resources, RoundRobinState, Depth + 1)
                end;
            Resource ->
                if Resource#yawl_resource_persist.status =:= available andalso
                   Resource#yawl_resource_persist.current_load < Resource#yawl_resource_persist.max_capacity ->
                    %% Found a valid resource
                    SelectedId;
                true ->
                    %% Resource not available, try next
                    select_round_robin_by_type(Rest, ResourcesByType, Resources, RoundRobinState, Depth + 1)
                end
        end;
    true ->
        %% No resources for this type, try next
        select_round_robin_by_type(Rest, ResourcesByType, Resources, RoundRobinState, Depth + 1)
    end.

%% @private
select_by_random(ResourceIds, Resources) ->
    case ResourceIds of
        [] ->
            undefined;
        _ ->
            %% Select a random resource that is available and has capacity
            AvailableIds = lists:filter(fun(Id) ->
                case maps:get(Id, Resources, undefined) of
                    undefined -> false;
                    Resource ->
                        Resource#yawl_resource_persist.status =:= available andalso
                        Resource#yawl_resource_persist.current_load < Resource#yawl_resource_persist.max_capacity
                end
            end, ResourceIds),

            case AvailableIds of
                [] ->
                    %% No available resources, return first as fallback
                    hd(ResourceIds);
                _ ->
                    %% Select random from available
                    RandIndex = rand:uniform(length(AvailableIds)),
                    lists:nth(RandIndex, AvailableIds)
            end
    end.

%% @private
update_round_robin_state(ResourceType, _ResourceId, State) ->
    RoundRobinState = State#state.round_robin_state,
    CurrentIndex = maps:get(ResourceType, RoundRobinState, 0),
    RoundRobinState#{ResourceType => CurrentIndex + 1}.
