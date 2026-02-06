%%%-------------------------------------------------------------------
%%% @doc BeamAI Tool Bridge.
%%%
%%% Bridge connecting existing A2A handler implementations and YAWL
%%% service registry entries as BeamAI tools. This enables:
%%% - Registering each a2a_handler implementation as a BeamAI tool
%%% - Converting handler callback format to tool execution format
%%% - Exposing YAWL service registry entries as invocable tools
%%% - Bidirectional tool discovery between A2A and BeamAI
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tool_bridge).

-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    register_handler/2,
    register_handler/3,
    register_service/2,
    register_service/3,
    unregister_handler/1,
    unregister_service/1,
    list_tools/0,
    execute/3,
    sync_from_bridge/0,
    sync_from_registry/0,
    get_status/0
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

%%====================================================================
%% Records
%%====================================================================

-record(handler_tool, {
    name        :: binary(),
    module      :: module(),
    description :: binary(),
    tags        :: [binary()],
    metadata    :: map(),
    registered_at :: integer()
}).

-record(service_tool, {
    name        :: binary(),
    service_id  :: binary(),
    service_name :: binary(),
    endpoint    :: binary(),
    tags        :: [binary()],
    metadata    :: map(),
    registered_at :: integer()
}).

-record(state, {
    handler_tools  :: #{binary() => #handler_tool{}},
    service_tools  :: #{binary() => #service_tool{}},
    auto_sync      :: boolean(),
    sync_interval  :: non_neg_integer(),
    sync_timer     :: reference() | undefined
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the tool bridge with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the tool bridge with options.
%% Options:
%%   auto_sync      - Automatically sync tools from beamai_bridge (default true)
%%   sync_interval  - Sync interval in ms (default 60000)
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Register an a2a_handler module as a BeamAI tool.
-spec register_handler(binary(), module()) -> ok | {error, term()}.
register_handler(ToolName, Module) ->
    register_handler(ToolName, Module, #{}).

%% @doc Register a handler with additional options.
%% Options:
%%   description - Tool description
%%   tags        - List of tags
%%   metadata    - Additional metadata
-spec register_handler(binary(), module(), map()) -> ok | {error, term()}.
register_handler(ToolName, Module, Opts) ->
    gen_server:call(?SERVER, {register_handler, ensure_binary(ToolName), Module, Opts}).

%% @doc Register a YAWL service registry entry as a BeamAI tool.
-spec register_service(binary(), binary()) -> ok | {error, term()}.
register_service(ToolName, ServiceName) ->
    register_service(ToolName, ServiceName, #{}).

%% @doc Register a service with additional options.
-spec register_service(binary(), binary(), map()) -> ok | {error, term()}.
register_service(ToolName, ServiceName, Opts) ->
    gen_server:call(?SERVER, {register_service, ensure_binary(ToolName),
                              ensure_binary(ServiceName), Opts}).

%% @doc Unregister a handler-based tool.
-spec unregister_handler(binary()) -> ok | {error, not_found}.
unregister_handler(ToolName) ->
    gen_server:call(?SERVER, {unregister_handler, ensure_binary(ToolName)}).

%% @doc Unregister a service-based tool.
-spec unregister_service(binary()) -> ok | {error, not_found}.
unregister_service(ToolName) ->
    gen_server:call(?SERVER, {unregister_service, ensure_binary(ToolName)}).

%% @doc List all tools registered through this bridge.
-spec list_tools() -> [map()].
list_tools() ->
    gen_server:call(?SERVER, list_tools).

%% @doc Execute a bridged tool by name.
-spec execute(binary(), map(), map()) -> {ok, term()} | {error, term()}.
execute(ToolName, Args, Context) ->
    gen_server:call(?SERVER, {execute, ensure_binary(ToolName), Args, Context}, 60000).

%% @doc Sync handlers from the existing beamai_bridge module.
%% Reads registered handlers and creates corresponding BeamAI tools.
-spec sync_from_bridge() -> {ok, non_neg_integer()} | {error, term()}.
sync_from_bridge() ->
    gen_server:call(?SERVER, sync_from_bridge).

%% @doc Sync services from yawl_service_registry.
%% Reads registered services and creates corresponding BeamAI tools.
-spec sync_from_registry() -> {ok, non_neg_integer()} | {error, term()}.
sync_from_registry() ->
    gen_server:call(?SERVER, sync_from_registry).

%% @doc Get bridge status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    AutoSync = maps:get(auto_sync, Opts, true),
    SyncInterval = maps:get(sync_interval, Opts, 60000),

    TimerRef = case AutoSync of
        true ->
            %% Schedule initial sync after a short delay
            erlang:send_after(5000, self(), sync),
            {ok, TRef} = timer:send_interval(SyncInterval, sync),
            TRef;
        false ->
            undefined
    end,

    logger:info("BeamAI tool bridge started (auto_sync: ~p)", [AutoSync]),

    {ok, #state{
        handler_tools = #{},
        service_tools = #{},
        auto_sync = AutoSync,
        sync_interval = SyncInterval,
        sync_timer = TimerRef
    }}.

%% @private
handle_call({register_handler, ToolName, Module, Opts}, _From, State) ->
    case validate_handler(Module) of
        ok ->
            HandlerTool = #handler_tool{
                name = ToolName,
                module = Module,
                description = maps:get(description, Opts, handler_description(Module)),
                tags = maps:get(tags, Opts, [<<"a2a_handler">>, <<"bridge">>]),
                metadata = maps:get(metadata, Opts, #{}),
                registered_at = erlang:system_time(millisecond)
            },
            NewHandlers = maps:put(ToolName, HandlerTool, State#state.handler_tools),

            %% Also register in beamai_tools if available
            register_in_beamai_tools(ToolName, HandlerTool),

            logger:info("Registered handler ~p as tool: ~s", [Module, ToolName]),
            {reply, ok, State#state{handler_tools = NewHandlers}};
        {error, _} = Err ->
            {reply, Err, State}
    end;

handle_call({register_service, ToolName, ServiceName, Opts}, _From, State) ->
    case lookup_service(ServiceName) of
        {ok, ServiceInfo} ->
            ServiceTool = #service_tool{
                name = ToolName,
                service_id = maps:get(service_id, ServiceInfo, ServiceName),
                service_name = ServiceName,
                endpoint = maps:get(endpoint, ServiceInfo, <<>>),
                tags = maps:get(tags, Opts, [<<"service">>, <<"bridge">>]),
                metadata = maps:merge(
                    maps:get(metadata, ServiceInfo, #{}),
                    maps:get(metadata, Opts, #{})
                ),
                registered_at = erlang:system_time(millisecond)
            },
            NewServices = maps:put(ToolName, ServiceTool, State#state.service_tools),

            %% Also register in beamai_tools if available
            register_service_in_beamai_tools(ToolName, ServiceTool),

            logger:info("Registered service ~s as tool: ~s", [ServiceName, ToolName]),
            {reply, ok, State#state{service_tools = NewServices}};
        {error, _} = Err ->
            {reply, Err, State}
    end;

handle_call({unregister_handler, ToolName}, _From, State) ->
    case maps:is_key(ToolName, State#state.handler_tools) of
        true ->
            NewHandlers = maps:remove(ToolName, State#state.handler_tools),
            catch beamai_tools:unregister(ToolName),
            {reply, ok, State#state{handler_tools = NewHandlers}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call({unregister_service, ToolName}, _From, State) ->
    case maps:is_key(ToolName, State#state.service_tools) of
        true ->
            NewServices = maps:remove(ToolName, State#state.service_tools),
            catch beamai_tools:unregister(ToolName),
            {reply, ok, State#state{service_tools = NewServices}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call(list_tools, _From, State) ->
    HandlerList = maps:fold(fun(_Name, HT, Acc) ->
        [handler_tool_to_map(HT) | Acc]
    end, [], State#state.handler_tools),

    ServiceList = maps:fold(fun(_Name, ST, Acc) ->
        [service_tool_to_map(ST) | Acc]
    end, [], State#state.service_tools),

    {reply, HandlerList ++ ServiceList, State};

handle_call({execute, ToolName, Args, Context}, _From, State) ->
    Result = case maps:find(ToolName, State#state.handler_tools) of
        {ok, HandlerTool} ->
            execute_handler_tool(HandlerTool, Args, Context);
        error ->
            case maps:find(ToolName, State#state.service_tools) of
                {ok, ServiceTool} ->
                    execute_service_tool(ServiceTool, Args, Context);
                error ->
                    {error, {tool_not_found, ToolName}}
            end
    end,
    {reply, Result, State};

handle_call(sync_from_bridge, _From, State) ->
    {Count, NewState} = do_sync_from_bridge(State),
    {reply, {ok, Count}, NewState};

handle_call(sync_from_registry, _From, State) ->
    {Count, NewState} = do_sync_from_registry(State),
    {reply, {ok, Count}, NewState};

handle_call(get_status, _From, State) ->
    Status = #{
        handler_count => map_size(State#state.handler_tools),
        service_count => map_size(State#state.service_tools),
        auto_sync => State#state.auto_sync,
        handlers => [handler_tool_to_map(HT) || HT <- maps:values(State#state.handler_tools)],
        services => [service_tool_to_map(ST) || ST <- maps:values(State#state.service_tools)]
    },
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(sync, State) ->
    {_BridgeCount, State1} = do_sync_from_bridge(State),
    {_RegistryCount, State2} = do_sync_from_registry(State1),
    {noreply, State2};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.sync_timer of
        undefined -> ok;
        Ref -> timer:cancel(Ref)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Handler Execution
%%====================================================================

%% @private
execute_handler_tool(#handler_tool{module = Module} = _HT, Args, Context) ->
    %% Create a minimal task and message for the handler
    TaskId = generate_id(),
    ContextId = maps:get(context_id, Context, generate_id()),

    %% Build a message from Args
    MessageContent = case Args of
        #{message := Msg} when is_binary(Msg) -> Msg;
        #{<<"message">> := Msg} when is_binary(Msg) -> Msg;
        _ -> jsx:encode(Args)
    end,

    Message = #message{
        message_id = generate_id(),
        context_id = ContextId,
        task_id = TaskId,
        role = user,
        parts = [#part{content = {text, MessageContent}}],
        metadata = maps:get(metadata, Context, #{})
    },

    Task = #task{
        id = TaskId,
        context_id = ContextId,
        status = #task_status{
            state = submitted,
            timestamp = erlang:system_time(millisecond)
        },
        metadata = #{}
    },

    try
        case Module:init(Task, Message) of
            {ok, HandlerState} ->
                case Module:process(Task, HandlerState) of
                    {ok, Result} ->
                        {ok, Result};
                    {error, Reason} ->
                        {error, {handler_error, Reason}};
                    {input_required, Prompt} ->
                        {ok, #{status => input_required, prompt => Prompt}};
                    {auth_required, Details} ->
                        {ok, #{status => auth_required, details => Details}}
                end;
            {error, Reason} ->
                {error, {handler_init_error, Reason}}
        end
    catch
        Class:Error:Stack ->
            logger:error("Handler tool ~p execution failed: ~p:~p~n~p",
                        [Module, Class, Error, Stack]),
            {error, {handler_crash, Class, Error}}
    end.

%%====================================================================
%% Internal Functions - Service Execution
%%====================================================================

%% @private
execute_service_tool(#service_tool{service_name = ServiceName}, Args, Context) ->
    try
        Options = maps:with([method, path, timeout, content_type], Context),
        yawl_service_registry:call_service(ServiceName, Args, Options)
    catch
        _:Reason ->
            {error, {service_call_error, Reason}}
    end.

%%====================================================================
%% Internal Functions - Sync
%%====================================================================

%% @private
do_sync_from_bridge(State) ->
    try
        case whereis(beamai_bridge) of
            undefined ->
                {0, State};
            _Pid ->
                Handlers = beamai_bridge:list_handlers(),
                Count = lists:foldl(fun({Name, Module}, Acc) ->
                    ToolName = handler_to_tool_name(Name),
                    case maps:is_key(ToolName, State#state.handler_tools) of
                        true -> Acc;
                        false ->
                            HT = #handler_tool{
                                name = ToolName,
                                module = Module,
                                description = handler_description(Module),
                                tags = [<<"a2a_handler">>, <<"bridge">>, <<"synced">>],
                                metadata = #{synced_from => beamai_bridge},
                                registered_at = erlang:system_time(millisecond)
                            },
                            register_in_beamai_tools(ToolName, HT),
                            Acc + 1
                    end
                end, 0, Handlers),
                %% Update state with new handlers
                NewHandlers = lists:foldl(fun({Name, Module}, Acc) ->
                    ToolName = handler_to_tool_name(Name),
                    HT = #handler_tool{
                        name = ToolName,
                        module = Module,
                        description = handler_description(Module),
                        tags = [<<"a2a_handler">>, <<"bridge">>, <<"synced">>],
                        metadata = #{synced_from => beamai_bridge},
                        registered_at = erlang:system_time(millisecond)
                    },
                    maps:put(ToolName, HT, Acc)
                end, State#state.handler_tools, Handlers),
                {Count, State#state{handler_tools = NewHandlers}}
        end
    catch
        _:_ -> {0, State}
    end.

%% @private
do_sync_from_registry(State) ->
    try
        case whereis(yawl_service_registry) of
            undefined ->
                {0, State};
            _Pid ->
                {ok, Services} = yawl_service_registry:list_services(),
                Count = lists:foldl(fun(ServiceMap, Acc) ->
                    ServiceName = maps:get(service_name, ServiceMap, <<>>),
                    ToolName = service_to_tool_name(ServiceName),
                    case maps:is_key(ToolName, State#state.service_tools) of
                        true -> Acc;
                        false ->
                            ST = #service_tool{
                                name = ToolName,
                                service_id = maps:get(service_id, ServiceMap, <<>>),
                                service_name = ServiceName,
                                endpoint = maps:get(endpoint, ServiceMap, <<>>),
                                tags = [<<"service">>, <<"registry">>, <<"synced">>],
                                metadata = #{
                                    synced_from => yawl_service_registry,
                                    service_type => maps:get(service_type, ServiceMap, unknown)
                                },
                                registered_at = erlang:system_time(millisecond)
                            },
                            register_service_in_beamai_tools(ToolName, ST),
                            Acc + 1
                    end
                end, 0, Services),
                NewServices = lists:foldl(fun(ServiceMap, Acc) ->
                    ServiceName = maps:get(service_name, ServiceMap, <<>>),
                    ToolName = service_to_tool_name(ServiceName),
                    ST = #service_tool{
                        name = ToolName,
                        service_id = maps:get(service_id, ServiceMap, <<>>),
                        service_name = ServiceName,
                        endpoint = maps:get(endpoint, ServiceMap, <<>>),
                        tags = [<<"service">>, <<"registry">>, <<"synced">>],
                        metadata = #{
                            synced_from => yawl_service_registry,
                            service_type => maps:get(service_type, ServiceMap, unknown)
                        },
                        registered_at = erlang:system_time(millisecond)
                    },
                    maps:put(ToolName, ST, Acc)
                end, State#state.service_tools, Services),
                {Count, State#state{service_tools = NewServices}}
        end
    catch
        _:_ -> {0, State}
    end.

%%====================================================================
%% Internal Functions - Registration
%%====================================================================

%% @private
%% Register a handler tool in the beamai_tools registry.
register_in_beamai_tools(ToolName, #handler_tool{module = Module, description = Desc,
                                                   tags = Tags, metadata = Meta}) ->
    try
        Handler = fun(Args, Context) ->
            HT = #handler_tool{
                name = ToolName,
                module = Module,
                description = Desc,
                tags = Tags,
                metadata = Meta,
                registered_at = 0
            },
            execute_handler_tool(HT, Args, Context)
        end,
        ToolDef = #{
            handler => Handler,
            description => Desc,
            tags => Tags,
            metadata => Meta#{source => a2a_handler, module => Module},
            schema => #{}
        },
        beamai_tools:register(ToolName, ToolDef)
    catch
        _:_ -> ok  %% beamai_tools may not be running yet
    end.

%% @private
%% Register a service tool in the beamai_tools registry.
register_service_in_beamai_tools(ToolName, #service_tool{service_name = SvcName,
                                                          endpoint = Endpoint,
                                                          tags = Tags, metadata = Meta}) ->
    try
        Handler = fun(Args, Context) ->
            ST = #service_tool{
                name = ToolName,
                service_id = <<>>,
                service_name = SvcName,
                endpoint = Endpoint,
                tags = Tags,
                metadata = Meta,
                registered_at = 0
            },
            execute_service_tool(ST, Args, Context)
        end,
        ToolDef = #{
            handler => Handler,
            description => <<"Service: ", SvcName/binary, " (", Endpoint/binary, ")">>,
            tags => Tags,
            metadata => Meta#{source => service_registry, endpoint => Endpoint},
            schema => #{}
        },
        beamai_tools:register(ToolName, ToolDef)
    catch
        _:_ -> ok
    end.

%%====================================================================
%% Internal Functions - Utility
%%====================================================================

%% @private
validate_handler(Module) ->
    try
        Exports = Module:module_info(exports),
        Required = [{init, 2}, {process, 2}, {handle_message, 2}],
        case lists:all(fun(Fn) -> lists:member(Fn, Exports) end, Required) of
            true -> ok;
            false -> {error, {missing_callbacks, Module}}
        end
    catch
        _:_ -> {error, {module_not_loaded, Module}}
    end.

%% @private
lookup_service(ServiceName) ->
    try
        yawl_service_registry:discover_service(ServiceName)
    catch
        _:_ -> {error, {service_not_found, ServiceName}}
    end.

%% @private
handler_description(Module) ->
    try
        Attrs = Module:module_info(attributes),
        case proplists:get_value(description, Attrs, undefined) of
            undefined ->
                ModBin = atom_to_binary(Module, utf8),
                <<"A2A handler: ", ModBin/binary>>;
            [Desc] when is_list(Desc) ->
                list_to_binary(Desc);
            _ ->
                ModBin = atom_to_binary(Module, utf8),
                <<"A2A handler: ", ModBin/binary>>
        end
    catch
        _:_ ->
            ModBin = atom_to_binary(Module, utf8),
            <<"A2A handler: ", ModBin/binary>>
    end.

%% @private
handler_to_tool_name(Name) when is_atom(Name) ->
    <<"a2a_handler_", (atom_to_binary(Name, utf8))/binary>>;
handler_to_tool_name(Name) when is_binary(Name) ->
    <<"a2a_handler_", Name/binary>>.

%% @private
service_to_tool_name(ServiceName) when is_binary(ServiceName) ->
    <<"service_", ServiceName/binary>>;
service_to_tool_name(ServiceName) when is_atom(ServiceName) ->
    <<"service_", (atom_to_binary(ServiceName, utf8))/binary>>.

%% @private
handler_tool_to_map(#handler_tool{} = HT) ->
    #{
        name => HT#handler_tool.name,
        type => handler,
        module => HT#handler_tool.module,
        description => HT#handler_tool.description,
        tags => HT#handler_tool.tags,
        metadata => HT#handler_tool.metadata,
        registered_at => HT#handler_tool.registered_at
    }.

%% @private
service_tool_to_map(#service_tool{} = ST) ->
    #{
        name => ST#service_tool.name,
        type => service,
        service_name => ST#service_tool.service_name,
        endpoint => ST#service_tool.endpoint,
        tags => ST#service_tool.tags,
        metadata => ST#service_tool.metadata,
        registered_at => ST#service_tool.registered_at
    }.

%% @private
generate_id() ->
    Bytes = crypto:strong_rand_bytes(12),
    binary:encode_hex(Bytes).

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V)   -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V)   -> list_to_binary(V).
