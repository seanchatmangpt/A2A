%%%-------------------------------------------------------------------
%%% @doc
%%% Mock Resource Manager for Testing YAWL Resource Allocation Patterns
%%%
%%% This module provides a mock implementation of the resource manager
%%% for testing resource allocation patterns without requiring external
%%% dependencies. It simulates:
%%%
%%% - Resource registration and management
%%% - Resource allocation with capacity constraints
%%% - Resource deallocation
%%% - Workitem lifecycle tracking
%%% - Workflow simulation
%%% - Allocation strategies (round_robin, least_loaded, random)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_mock_resource_manager).
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
    register_resource/3,
    unregister_resource/1,
    get_resource_state/1,
    list_resources/0,
    set_allocation_strategy/1,
    get_allocation_strategy/0
]).

%% API exports - Resource allocation
-export([
    allocate_resource/2,
    release_resource/1,
    get_allocated_resource/1
]).

%% API exports - Workitem tracking
-export([
    record_workitem_start/1,
    record_workitem_complete/1,
    get_workitem_status/1,
    record_choice/2,
    get_workitem_choice/1,
    get_completed_workitems/1
]).

%% API exports - Workflow simulation
-export([
    start_workflow_simulation/2,
    end_workflow_simulation/1,
    get_workflow_status/1
]).

-include_lib("yawl_types.hrl").
-include_lib("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(resource_state, {
    resource_id :: binary(),
    resource_type :: resource_type(),
    name :: binary(),
    capabilities :: [atom()],
    max_capacity :: non_neg_integer(),
    current_load :: non_neg_integer(),
    allocation_status :: available | allocated | busy,
    created_at :: integer()
}).

-record(workitem_state, {
    workitem_id :: binary(),
    status :: pending | running | completed | failed,
    allocated_resource :: binary() | undefined,
    choice :: atom() | undefined,
    start_time :: integer() | undefined,
    complete_time :: integer() | undefined
}).

-record(workflow_state, {
    workflow_id :: binary(),
    pattern_type :: atom(),
    status :: running | completed | failed,
    workitems :: [binary()],
    start_time :: integer(),
    end_time :: integer() | undefined
}).

-record(state, {
    resources :: #{binary() => #resource_state{}},
    workitems :: #{binary() => #workitem_state{}},
    workflows :: #{binary() => #workflow_state{}},
    allocations :: #{binary() => binary()},  %% workitem_id => resource_id
    allocation_strategy :: round_robin | least_loaded | random,
    resource_counter :: non_neg_integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the mock resource manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a resource.
-spec register_resource(binary(), resource_type(), map()) ->
    {ok, binary()} | {error, term()}.
register_resource(ResourceName, ResourceType, Options) ->
    gen_server:call(?MODULE, {register_resource, ResourceName, ResourceType, Options}).

%% @doc Unregister a resource.
-spec unregister_resource(binary()) -> ok | {error, term()}.
unregister_resource(ResourceId) ->
    gen_server:call(?MODULE, {unregister_resource, ResourceId}).

%% @doc Get resource state.
-spec get_resource_state(binary()) -> {ok, map()} | {error, term()}.
get_resource_state(ResourceId) ->
    gen_server:call(?MODULE, {get_resource_state, ResourceId}).

%% @doc List all resources.
-spec list_resources() -> {ok, [map()]}.
list_resources() ->
    gen_server:call(?MODULE, list_resources).

%% @doc Set allocation strategy.
-spec set_allocation_strategy(round_robin | least_loaded | random) -> ok.
set_allocation_strategy(Strategy) ->
    gen_server:call(?MODULE, {set_allocation_strategy, Strategy}).

%% @doc Get current allocation strategy.
-spec get_allocation_strategy() -> {ok, atom()}.
get_allocation_strategy() ->
    gen_server:call(?MODULE, get_allocation_strategy).

%% @doc Allocate a resource for a workitem.
-spec allocate_resource(binary(), [atom()]) ->
    {ok, binary(), map()} | {error, term()}.
allocate_resource(WorkitemId, RequiredCapabilities) ->
    gen_server:call(?MODULE, {allocate_resource, WorkitemId, RequiredCapabilities}).

%% @doc Release a resource allocation.
-spec release_resource(binary()) -> ok | {error, term()}.
release_resource(WorkitemId) ->
    gen_server:call(?MODULE, {release_resource, WorkitemId}).

%% @doc Get allocated resource for a workitem.
-spec get_allocated_resource(binary()) ->
    {ok, binary()} | {error, workitem_not_allocated}.
get_allocated_resource(WorkitemId) ->
    gen_server:call(?MODULE, {get_allocated_resource, WorkitemId}).

%% @doc Record workitem start.
-spec record_workitem_start(binary()) -> ok.
record_workitem_start(WorkitemId) ->
    gen_server:cast(?MODULE, {record_workitem_start, WorkitemId}).

%% @doc Record workitem completion.
-spec record_workitem_complete(binary()) -> ok.
record_workitem_complete(WorkitemId) ->
    gen_server:cast(?MODULE, {record_workitem_complete, WorkitemId}).

%% @doc Get workitem status.
-spec get_workitem_status(binary()) -> {ok, atom()} | {error, term()}.
get_workitem_status(WorkitemId) ->
    gen_server:call(?MODULE, {get_workitem_status, WorkitemId}).

%% @doc Record a choice for a workitem (for deferred choice patterns).
-spec record_choice(binary(), atom()) -> ok.
record_choice(WorkitemId, Choice) ->
    gen_server:cast(?MODULE, {record_choice, WorkitemId, Choice}).

%% @doc Get workitem choice.
-spec get_workitem_choice(binary()) -> {ok, atom()} | {error, term()}.
get_workitem_choice(WorkitemId) ->
    gen_server:call(?MODULE, {get_workitem_choice, WorkitemId}).

%% @doc Get completed workitems matching a prefix.
-spec get_completed_workitems(binary()) -> [binary()].
get_completed_workitems(Prefix) ->
    gen_server:call(?MODULE, {get_completed_workitems, Prefix}).

%% @doc Start workflow simulation.
-spec start_workflow_simulation(binary(), atom()) -> ok.
start_workflow_simulation(WorkflowId, PatternType) ->
    gen_server:cast(?MODULE, {start_workflow, WorkflowId, PatternType}).

%% @doc End workflow simulation.
-spec end_workflow_simulation(binary()) -> {ok, completed} | {error, term()}.
end_workflow_simulation(WorkflowId) ->
    gen_server:call(?MODULE, {end_workflow, WorkflowId}).

%% @doc Get workflow status.
-spec get_workflow_status(binary()) -> {ok, atom()} | {error, term()}.
get_workflow_status(WorkflowId) ->
    gen_server:call(?MODULE, {get_workflow_status, WorkflowId}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        resources = #{},
        workitems = #{},
        workflows = #{},
        allocations = #{},
        allocation_strategy = least_loaded,
        resource_counter = 0
    },
    {ok, State}.

%% @private
handle_call({register_resource, ResourceName, ResourceType, Options}, _From, State) ->
    ResourceId = generate_resource_id(ResourceName, State#state.resource_counter),
    Capabilities = maps:get(capabilities, Options, []),
    MaxCapacity = maps:get(max_capacity, Options, 10),

    ResourceState = #resource_state{
        resource_id = ResourceId,
        resource_type = ResourceType,
        name = ResourceName,
        capabilities = Capabilities,
        max_capacity = MaxCapacity,
        current_load = 0,
        allocation_status = available,
        created_at = erlang:monotonic_time(millisecond)
    },

    NewResources = maps:put(ResourceId, ResourceState, State#state.resources),
    NewState = State#state{
        resources = NewResources,
        resource_counter = State#state.resource_counter + 1
    },
    {reply, {ok, ResourceId}, NewState};

handle_call({unregister_resource, ResourceId}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        _Resource ->
            NewResources = maps:remove(ResourceId, State#state.resources),
            %% Remove any allocations for this resource
            NewAllocations = maps:filter(fun(_WI, RI) -> RI =/= ResourceId end,
                State#state.allocations),
            NewState = State#state{resources = NewResources, allocations = NewAllocations},
            {reply, ok, NewState}
    end;

handle_call({get_resource_state, ResourceId}, _From, State) ->
    case maps:get(ResourceId, State#state.resources, undefined) of
        undefined ->
            {reply, {error, resource_not_found}, State};
        Resource ->
            StateMap = #{
                resource_id => Resource#resource_state.resource_id,
                resource_type => Resource#resource_state.resource_type,
                name => Resource#resource_state.name,
                capabilities => Resource#resource_state.capabilities,
                max_capacity => Resource#resource_state.max_capacity,
                current_load => Resource#resource_state.current_load,
                allocation_status => Resource#resource_state.allocation_status
            },
            {reply, {ok, StateMap}, State}
    end;

handle_call(list_resources, _From, State) ->
    ResourceList = maps:fold(fun(_Id, Resource, Acc) ->
        [#{
            resource_id => Resource#resource_state.resource_id,
            resource_type => Resource#resource_state.resource_type,
            name => Resource#resource_state.name,
            capabilities => Resource#resource_state.capabilities,
            max_capacity => Resource#resource_state.max_capacity,
            current_load => Resource#resource_state.current_load,
            allocation_status => Resource#resource_state.allocation_status
        } | Acc]
    end, [], State#state.resources),
    {reply, {ok, ResourceList}, State};

handle_call({set_allocation_strategy, Strategy}, _From, State) ->
    case lists:member(Strategy, [round_robin, least_loaded, random]) of
        true ->
            {reply, ok, State#state{allocation_strategy = Strategy}};
        false ->
            {reply, {error, invalid_strategy}, State}
    end;

handle_call(get_allocation_strategy, _From, State) ->
    {reply, {ok, State#state.allocation_strategy}, State};

handle_call({allocate_resource, WorkitemId, RequiredCapabilities}, _From, State) ->
    %% Find available resources
    AvailableResources = maps:filter(fun(_Id, Resource) ->
        Resource#resource_state.allocation_status =/= busy andalso
        Resource#resource_state.current_load < Resource#resource_state.max_capacity andalso
        (RequiredCapabilities =:= [] orelse
            lists:any(fun(C) -> lists:member(C, Resource#resource_state.capabilities) end,
                RequiredCapabilities))
    end, State#state.resources),

    case maps:keys(AvailableResources) of
        [] ->
            {reply, {error, no_available_resources}, State};
        ResourceIds ->
            %% Select based on strategy
            SelectedId = select_by_strategy(
                State#state.allocation_strategy,
                ResourceIds,
                AvailableResources
            ),

            %% Update resource state
            NewResources = maps:update_with(SelectedId, fun(Resource) ->
                NewLoad = Resource#resource_state.current_load + 1,
                NewStatus = case NewLoad >= Resource#resource_state.max_capacity of
                    true -> busy;
                    false -> allocated
                end,
                Resource#resource_state{
                    current_load = NewLoad,
                    allocation_status = NewStatus
                }
            end, State#state.resources),

            %% Track allocation
            NewAllocations = maps:put(WorkitemId, SelectedId, State#state.allocations),

            %% Update or create workitem state
            NewWorkitems = maps:put(WorkitemId, #workitem_state{
                workitem_id = WorkitemId,
                status = allocated,
                allocated_resource = SelectedId,
                start_time = undefined,
                complete_time = undefined
            }, State#state.workitems),

            ResourceMap = #{
                resource_id => SelectedId,
                allocated_at => erlang:monotonic_time(millisecond)
            },

            NewState = State#state{
                resources = NewResources,
                allocations = NewAllocations,
                workitems = NewWorkitems
            },
            {reply, {ok, SelectedId, ResourceMap}, NewState}
    end;

handle_call({release_resource, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.allocations, undefined) of
        undefined ->
            {reply, {error, allocation_not_found}, State};
        ResourceId ->
            %% Update resource state
            NewResources = maps:update_with(ResourceId, fun(Resource) ->
                NewLoad = max(0, Resource#resource_state.current_load - 1),
                NewStatus = case NewLoad of
                    0 -> available;
                    _ when Resource#resource_state.allocation_status =:= busy -> allocated;
                    _ -> Resource#resource_state.allocation_status
                end,
                Resource#resource_state{
                    current_load = NewLoad,
                    allocation_status = NewStatus
                }
            end, State#state.resources),

            %% Remove allocation
            NewAllocations = maps:remove(WorkitemId, State#state.allocations),

            NewState = State#state{resources = NewResources, allocations = NewAllocations},
            {reply, ok, NewState}
    end;

handle_call({get_allocated_resource, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.allocations, undefined) of
        undefined ->
            {reply, {error, workitem_not_allocated}, State};
        ResourceId ->
            {reply, {ok, ResourceId}, State}
    end;

handle_call({get_workitem_status, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {reply, {error, workitem_not_found}, State};
        WIState ->
            {reply, {ok, WIState#workitem_state.status}, State}
    end;

handle_call({get_workitem_choice, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {reply, {error, workitem_not_found}, State};
        WIState ->
            case WIState#workitem_state.choice of
                undefined -> {reply, {error, no_choice_recorded}, State};
                Choice -> {reply, {ok, Choice}, State}
            end
    end;

handle_call({get_completed_workitems, Prefix}, _From, State) ->
    CompletedWorkitems = lists:filtermap(fun(WIId) ->
        case binary:match(WIId, Prefix) of
            nomatch -> false;
            _ ->
                case maps:get(WIId, State#state.workitems, undefined) of
                    undefined -> false;
                    #workitem_state{status = completed} -> {true, WIId};
                    _ -> false
                end
        end
    end, maps:keys(State#state.workitems)),
    {reply, CompletedWorkitems, State};

handle_call({end_workflow, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined ->
            {reply, {error, workflow_not_found}, State};
        WFState ->
            NewWFState = WFState#workflow_state{
                status = completed,
                end_time = erlang:monotonic_time(millisecond)
            },
            NewWorkflows = maps:put(WorkflowId, NewWFState, State#state.workflows),
            NewState = State#state{workflows = NewWorkflows},
            {reply, {ok, completed}, NewState}
    end;

handle_call({get_workflow_status, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined ->
            {reply, {error, workflow_not_found}, State};
        WFState ->
            {reply, {ok, WFState#workflow_state.status}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({record_workitem_start, WorkitemId}, State) ->
    NewWorkitems = maps:update_with(WorkitemId, fun(WIState) ->
        WIState#workitem_state{
            status = running,
            start_time = erlang:monotonic_time(millisecond)
        }
    end, State#state.workitems, #workitem_state{
        workitem_id = WorkitemId,
        status = running,
        start_time = erlang:monotonic_time(millisecond)
    }),
    {noreply, State#state{workitems = NewWorkitems}};

handle_cast({record_workitem_complete, WorkitemId}, State) ->
    NewWorkitems = maps:update_with(WorkitemId, fun(WIState) ->
        WIState#workitem_state{
            status = completed,
            complete_time = erlang:monotonic_time(millisecond)
        }
    end, State#state.workitems),
    {noreply, State#state{workitems = NewWorkitems}};

handle_cast({record_choice, WorkitemId, Choice}, State) ->
    NewWorkitems = maps:update_with(WorkitemId, fun(WIState) ->
        WIState#workitem_state{choice = Choice}
    end, State#state.workitems, #workitem_state{
        workitem_id = WorkitemId,
        status = pending,
        choice = Choice
    }),
    {noreply, State#state{workitems = NewWorkitems}};

handle_cast({start_workflow, WorkflowId, PatternType}, State) ->
    WorkflowState = #workflow_state{
        workflow_id = WorkflowId,
        pattern_type = PatternType,
        status = running,
        workitems = [],
        start_time = erlang:monotonic_time(millisecond),
        end_time = undefined
    },
    NewWorkflows = maps:put(WorkflowId, WorkflowState, State#state.workflows),
    {noreply, State#state{workflows = NewWorkflows}};

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
generate_resource_id(Name, Counter) ->
    NameHash = erlang:phash2(Name),
    Timestamp = erlang:monotonic_time(millisecond),
    <<"mock_res_", (integer_to_binary(NameHash))/binary, "_",
      (integer_to_binary(Counter))/binary, "_",
      (integer_to_binary(Timestamp))/binary>>.

%% @private
select_by_strategy(least_loaded, ResourceIds, Resources) ->
    %% Find resource with minimum current load
    lists:foldl(fun(Id, BestId) ->
        Resource = maps:get(Id, Resources),
        BestResource = maps:get(BestId, Resources),
        case Resource#resource_state.current_load < BestResource#resource_state.current_load of
            true -> Id;
            false -> BestId
        end
    end, hd(ResourceIds), tl(ResourceIds));

select_by_strategy(round_robin, ResourceIds, _Resources) ->
    %% Simple round-robin: select first available
    %% In a real implementation, we'd track the last selected index
    hd(ResourceIds);

select_by_strategy(random, ResourceIds, _Resources) ->
    %% Select random resource
    Index = rand:uniform(length(ResourceIds)),
    lists:nth(Index, ResourceIds).
