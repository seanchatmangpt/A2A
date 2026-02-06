%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Resource Bridge
%%%
%%% Bridges the YAWL resource manager (yawl_resource_manager) to the
%%% BeamAI tool and agent system. This module:
%%%
%%% - Registers YAWL resources as BeamAI tools
%%% - Maps YAWL resource capabilities to BeamAI tool schemas
%%% - Handles resource allocation through the BeamAI kernel
%%% - Provides unified resource discovery across both systems
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_resource_bridge).
-behaviour(gen_server).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%% API
-export([
    start_link/0,
    register_resources/1,
    allocate/2,
    release/2,
    get_available/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(SERVER, ?MODULE).
-define(SYNC_INTERVAL, 30000).

-record(state, {
    %% resource_id => beamai tool name
    resource_tools = #{} :: #{binary() => binary()},
    %% resource_id => allocation info
    allocations = #{} :: #{binary() => map()},
    %% cached available resources by capability
    capability_cache = #{} :: #{atom() => [binary()]},
    %% reference to BeamAI kernel
    kernel_ref :: atom() | pid() | undefined,
    %% timer ref for periodic sync
    sync_timer :: reference() | undefined
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the resource bridge server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Register YAWL resources as BeamAI tools.
%% Takes a list of resource IDs (or the atom 'all' to register everything).
-spec register_resources([binary()] | all) -> {ok, non_neg_integer()} | {error, term()}.
register_resources(ResourceIds) ->
    gen_server:call(?SERVER, {register_resources, ResourceIds}, 15000).

%% @doc Allocate a resource for a work item, using both YAWL and BeamAI.
%% Returns the resource ID and a tool definition for BeamAI use.
-spec allocate(binary(), [atom()]) -> {ok, binary(), map()} | {error, term()}.
allocate(WorkitemId, RequiredCapabilities) ->
    gen_server:call(?SERVER, {allocate, WorkitemId, RequiredCapabilities}).

%% @doc Release a resource allocation.
-spec release(binary(), binary()) -> ok | {error, term()}.
release(WorkitemId, ResourceId) ->
    gen_server:call(?SERVER, {release, WorkitemId, ResourceId}).

%% @doc Get available resources matching the given capabilities,
%% including both YAWL-registered and BeamAI-registered tools.
-spec get_available([atom()]) -> {ok, [map()]} | {error, term()}.
get_available(RequiredCapabilities) ->
    gen_server:call(?SERVER, {get_available, RequiredCapabilities}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    KernelRef = try_get_kernel(),
    TimerRef = erlang:send_after(?SYNC_INTERVAL, self(), sync_resources),
    logger:info("YAWL-BeamAI resource bridge started"),
    {ok, #state{kernel_ref = KernelRef, sync_timer = TimerRef}}.

%% @private
handle_call({register_resources, ResourceSpec}, _From, State) ->
    #state{resource_tools = ExistingTools, kernel_ref = KernelRef} = State,
    case fetch_yawl_resources(ResourceSpec) of
        {ok, Resources} ->
            {NewTools, RegisteredCount} = lists:foldl(
                fun(Resource, {ToolsAcc, Count}) ->
                    ResourceId = maps:get(resource_id, Resource),
                    case maps:is_key(ResourceId, ToolsAcc) of
                        true ->
                            {ToolsAcc, Count};
                        false ->
                            ToolDef = resource_to_tool(Resource),
                            ToolName = maps:get(name, ToolDef),
                            register_tool_with_kernel(KernelRef, ToolDef),
                            {ToolsAcc#{ResourceId => ToolName}, Count + 1}
                    end
                end,
                {ExistingTools, 0},
                Resources
            ),
            NewState = State#state{resource_tools = NewTools},
            logger:info("Registered ~p YAWL resources as BeamAI tools", [RegisteredCount]),
            {reply, {ok, RegisteredCount}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({allocate, WorkitemId, RequiredCapabilities}, _From, State) ->
    #state{allocations = Allocations, resource_tools = ResourceTools} = State,
    %% Try YAWL resource allocation first
    case try_yawl_allocate(WorkitemId, RequiredCapabilities) of
        {ok, ResourceId, ResourceInfo} ->
            %% Map the allocated resource to its BeamAI tool name
            ToolName = maps:get(ResourceId, ResourceTools, undefined),
            EnrichedInfo = ResourceInfo#{
                beamai_tool => ToolName,
                allocated_via => yawl_resource_manager
            },
            NewAllocations = Allocations#{WorkitemId => #{
                resource_id => ResourceId,
                capabilities => RequiredCapabilities,
                allocated_at => erlang:system_time(millisecond)
            }},
            NewState = State#state{allocations = NewAllocations},
            {reply, {ok, ResourceId, EnrichedInfo}, NewState};
        {error, no_available_resources} ->
            %% Fall back to BeamAI tool-based resources
            case try_beamai_allocate(RequiredCapabilities, State) of
                {ok, ToolName, ToolInfo} ->
                    NewAllocations = Allocations#{WorkitemId => #{
                        tool_name => ToolName,
                        capabilities => RequiredCapabilities,
                        allocated_at => erlang:system_time(millisecond),
                        allocated_via => beamai_kernel
                    }},
                    NewState = State#state{allocations = NewAllocations},
                    {reply, {ok, ToolName, ToolInfo}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({release, WorkitemId, ResourceId}, _From, State) ->
    #state{allocations = Allocations} = State,
    %% Release from YAWL resource manager
    try_yawl_release(WorkitemId, ResourceId),
    NewAllocations = maps:remove(WorkitemId, Allocations),
    {reply, ok, State#state{allocations = NewAllocations}};

handle_call({get_available, RequiredCapabilities}, _From, State) ->
    #state{capability_cache = Cache} = State,
    %% Check cache first
    CacheKey = list_to_atom(lists:flatten(
        lists:join("_", [atom_to_list(C) || C <- lists:sort(RequiredCapabilities)])
    )),
    case maps:find(CacheKey, Cache) of
        {ok, {CachedAt, CachedResult}} when
            erlang:system_time(millisecond) - CachedAt < 5000 ->
            {reply, {ok, CachedResult}, State};
        _ ->
            %% Fetch from both YAWL and BeamAI
            YawlResources = fetch_yawl_by_capabilities(RequiredCapabilities),
            BeamAITools = fetch_beamai_by_capabilities(RequiredCapabilities, State),
            Combined = merge_resource_lists(YawlResources, BeamAITools),
            NewCache = Cache#{CacheKey => {erlang:system_time(millisecond), Combined}},
            {reply, {ok, Combined}, State#state{capability_cache = NewCache}}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(sync_resources, State) ->
    %% Periodic sync: refresh capability cache and check for new resources
    NewState = do_periodic_sync(State),
    TimerRef = erlang:send_after(?SYNC_INTERVAL, self(), sync_resources),
    {noreply, NewState#state{sync_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{sync_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    ok.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Obtain the BeamAI kernel reference.
-spec try_get_kernel() -> atom() | undefined.
try_get_kernel() ->
    case whereis(beamai_kernel) of
        undefined -> undefined;
        _Pid -> beamai_kernel
    end.

%% @private Fetch YAWL resources based on the spec (all or specific IDs).
-spec fetch_yawl_resources([binary()] | all) -> {ok, [map()]} | {error, term()}.
fetch_yawl_resources(all) ->
    case whereis(yawl_resource_manager) of
        undefined -> {ok, []};
        _Pid ->
            case yawl_resource_manager:list_available_resources() of
                {ok, Resources} -> {ok, Resources};
                Error -> Error
            end
    end;
fetch_yawl_resources(ResourceIds) when is_list(ResourceIds) ->
    case whereis(yawl_resource_manager) of
        undefined -> {ok, []};
        _Pid ->
            Resources = lists:filtermap(fun(Id) ->
                case yawl_resource_manager:get_resource(Id) of
                    {ok, R} -> {true, R};
                    _ -> false
                end
            end, ResourceIds),
            {ok, Resources}
    end.

%% @private Convert a YAWL resource map to a BeamAI tool definition.
-spec resource_to_tool(map()) -> map().
resource_to_tool(Resource) ->
    ResourceId = maps:get(resource_id, Resource),
    ResourceName = maps:get(name, Resource, ResourceId),
    ResourceType = maps:get(resource_type, Resource, system),
    Capabilities = maps:get(capabilities, Resource, []),
    CapTags = [ensure_binary(C) || C <- Capabilities],
    #{
        name => <<"yawl_resource.", ResourceId/binary>>,
        function => fun(Args, Context) ->
            invoke_resource(ResourceId, Args, Context)
        end,
        description => <<"YAWL resource: ", (ensure_binary(ResourceName))/binary,
                         " (", (atom_to_binary(ResourceType, utf8))/binary, ")">>,
        parameters => #{
            action => string,
            data => #{<<"type">> => <<"object">>}
        },
        tags => [<<"yawl">>, <<"resource">>, atom_to_binary(ResourceType, utf8) | CapTags],
        metadata => #{
            source => yawl_resource_manager,
            resource_id => ResourceId,
            resource_type => ResourceType,
            capabilities => Capabilities,
            max_capacity => maps:get(max_capacity, Resource, 10)
        }
    }.

%% @private Register a tool definition with the BeamAI kernel.
-spec register_tool_with_kernel(atom() | pid() | undefined, map()) -> ok.
register_tool_with_kernel(undefined, _ToolDef) -> ok;
register_tool_with_kernel(KernelRef, ToolDef) ->
    try beamai:add_tool(KernelRef, ToolDef)
    catch _:_ -> ok
    end.

%% @private Invoke a YAWL resource through its work item interface.
-spec invoke_resource(binary(), map(), map()) -> map().
invoke_resource(ResourceId, Args, _Context) ->
    Action = maps:get(action, Args, maps:get(<<"action">>, Args, <<"execute">>)),
    Data = maps:get(data, Args, maps:get(<<"data">>, Args, #{})),
    case Action of
        <<"status">> ->
            case yawl_resource_manager:get_resource(ResourceId) of
                {ok, Info} -> #{status => ok, resource => Info};
                {error, Reason} -> #{status => error, reason => Reason}
            end;
        <<"execute">> ->
            #{status => ok, resource_id => ResourceId, action => execute, data => Data};
        _ ->
            #{status => error, reason => unknown_action}
    end.

%% @private Try to allocate via YAWL resource manager.
-spec try_yawl_allocate(binary(), [atom()]) -> {ok, binary(), map()} | {error, term()}.
try_yawl_allocate(WorkitemId, RequiredCapabilities) ->
    case whereis(yawl_resource_manager) of
        undefined -> {error, resource_manager_unavailable};
        _Pid ->
            yawl_resource_manager:allocate_resource(WorkitemId, RequiredCapabilities)
    end.

%% @private Try to find a BeamAI tool matching the required capabilities.
-spec try_beamai_allocate([atom()], #state{}) -> {ok, binary(), map()} | {error, term()}.
try_beamai_allocate(RequiredCapabilities, #state{kernel_ref = undefined}) ->
    {error, {no_kernel, RequiredCapabilities}};
try_beamai_allocate(RequiredCapabilities, #state{kernel_ref = KernelRef}) ->
    try
        CapTags = [ensure_binary(C) || C <- RequiredCapabilities],
        AllTools = beamai:tools(KernelRef),
        Matching = lists:filter(fun(ToolDef) ->
            ToolTags = maps:get(tags, ToolDef, []),
            lists:all(fun(Tag) -> lists:member(Tag, ToolTags) end, CapTags)
        end, AllTools),
        case Matching of
            [Tool | _] ->
                ToolName = maps:get(name, Tool),
                {ok, ToolName, #{source => beamai_kernel, tool => Tool}};
            [] ->
                {error, no_matching_tools}
        end
    catch
        _:Err -> {error, Err}
    end.

%% @private Release via YAWL resource manager.
-spec try_yawl_release(binary(), binary()) -> ok.
try_yawl_release(WorkitemId, ResourceId) ->
    case whereis(yawl_resource_manager) of
        undefined -> ok;
        _Pid ->
            try yawl_resource_manager:release_resource(WorkitemId, ResourceId)
            catch _:_ -> ok
            end
    end.

%% @private Fetch YAWL resources by capabilities.
-spec fetch_yawl_by_capabilities([atom()]) -> [map()].
fetch_yawl_by_capabilities(Capabilities) ->
    case whereis(yawl_resource_manager) of
        undefined -> [];
        _Pid ->
            case yawl_resource_manager:find_resources_by_capabilities(Capabilities) of
                {ok, Resources} ->
                    [R#{source => yawl} || R <- Resources];
                _ -> []
            end
    end.

%% @private Fetch BeamAI tools by capability tags.
-spec fetch_beamai_by_capabilities([atom()], #state{}) -> [map()].
fetch_beamai_by_capabilities(_Capabilities, #state{kernel_ref = undefined}) ->
    [];
fetch_beamai_by_capabilities(Capabilities, #state{kernel_ref = KernelRef}) ->
    try
        lists:foldl(fun(Cap, Acc) ->
            Tag = ensure_binary(Cap),
            Tools = beamai:tools_by_tag(KernelRef, Tag),
            ToolMaps = [#{
                resource_id => maps:get(name, T),
                name => maps:get(name, T),
                resource_type => tool,
                capabilities => maps:get(tags, T, []),
                source => beamai
            } || T <- Tools],
            merge_resource_lists(Acc, ToolMaps)
        end, [], Capabilities)
    catch
        _:_ -> []
    end.

%% @private Merge two resource lists, deduplicating by resource_id.
-spec merge_resource_lists([map()], [map()]) -> [map()].
merge_resource_lists(List1, List2) ->
    Map1 = maps:from_list([{maps:get(resource_id, R, maps:get(name, R, <<>>)), R} || R <- List1]),
    Map2 = maps:from_list([{maps:get(resource_id, R, maps:get(name, R, <<>>)), R} || R <- List2]),
    Merged = maps:merge(Map1, Map2),
    maps:values(Merged).

%% @private Periodic sync: clear cache and check for resource changes.
-spec do_periodic_sync(#state{}) -> #state{}.
do_periodic_sync(State) ->
    %% Clear stale capability cache entries
    State#state{capability_cache = #{}}.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
