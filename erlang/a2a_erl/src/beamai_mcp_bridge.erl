%%%-------------------------------------------------------------------
%%% @doc BeamAI MCP Bridge
%%%
%%% Connects the existing elrmcp_bridge infrastructure to the new
%%% BeamAI MCP implementation. Provides a unified tool registry
%%% across both MCP implementations and forwards requests between
%%% the two systems.
%%%
%%% This bridge enables:
%%% - Tools registered in elrmcp_bridge to be available via beamai_mcp
%%% - Tools registered in beamai_mcp to be available via elrmcp_bridge
%%% - Unified MCP request handling across both systems
%%% - Cross-system resource and prompt access
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_bridge).

-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    register_tools/0,
    handle_request/2,
    forward/2,
    get_unified_tools/0,
    get_unified_resources/0,
    sync/0,
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
-define(SYNC_INTERVAL_MS, 30000). %% 30 seconds

-record(tool_entry, {
    name        :: binary(),
    source      :: elrmcp | beamai_mcp,
    definition  :: map(),
    registered_at :: integer()
}).

-record(state, {
    tools           :: #{binary() => #tool_entry{}},
    resources       :: #{binary() => map()},
    config          :: map(),
    sync_ref        :: reference() | undefined,
    kernel_ref      :: atom() | pid(),
    stats           :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the MCP bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the MCP bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Register all tools from both MCP systems into the unified registry.
-spec register_tools() -> ok.
register_tools() ->
    gen_server:call(?SERVER, register_tools).

%% @doc Handle an MCP request, routing to the appropriate backend.
-spec handle_request(binary(), map()) -> {ok, map()} | {error, map()}.
handle_request(Method, Params) ->
    gen_server:call(?SERVER, {handle_request, Method, Params}, 30000).

%% @doc Forward a request from one MCP system to the other.
%% Target is either `elrmcp' or `beamai_mcp'.
-spec forward(elrmcp | beamai_mcp, map()) -> {ok, map()} | {error, term()}.
forward(Target, Request) ->
    gen_server:call(?SERVER, {forward, Target, Request}, 30000).

%% @doc Get the unified list of tools from both systems.
-spec get_unified_tools() -> [map()].
get_unified_tools() ->
    gen_server:call(?SERVER, get_unified_tools).

%% @doc Get the unified list of resources from both systems.
-spec get_unified_resources() -> [map()].
get_unified_resources() ->
    gen_server:call(?SERVER, get_unified_resources).

%% @doc Manually trigger a sync between the two MCP systems.
-spec sync() -> ok.
sync() ->
    gen_server:cast(?SERVER, sync).

%% @doc Get the bridge status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),

    State = #state{
        tools = #{},
        resources = #{},
        config = Config,
        sync_ref = undefined,
        kernel_ref = KernelRef,
        stats = #{
            requests_handled => 0,
            forwards => 0,
            syncs => 0,
            errors => 0
        }
    },

    %% Initial sync
    State2 = do_sync(State),

    %% Schedule periodic sync
    SyncRef = erlang:send_after(?SYNC_INTERVAL_MS, self(), sync),

    logger:info("BeamAI MCP bridge started"),
    {ok, State2#state{sync_ref = SyncRef}}.

%% @private
handle_call(register_tools, _From, State) ->
    NewState = do_register_tools(State),
    {reply, ok, NewState};

handle_call({handle_request, Method, Params}, _From, State) ->
    {Result, NewState} = do_handle_request(Method, Params, State),
    Handled = maps:get(requests_handled, NewState#state.stats, 0),
    NewStats = (NewState#state.stats)#{requests_handled => Handled + 1},
    {reply, Result, NewState#state{stats = NewStats}};

handle_call({forward, Target, Request}, _From, State) ->
    Result = do_forward(Target, Request),
    Forwards = maps:get(forwards, State#state.stats, 0),
    NewStats = (State#state.stats)#{forwards => Forwards + 1},
    {reply, Result, State#state{stats = NewStats}};

handle_call(get_unified_tools, _From, #state{tools = Tools} = State) ->
    ToolList = maps:fold(fun(_Name, #tool_entry{definition = Def, source = Source}, Acc) ->
        [Def#{<<"_source">> => atom_to_binary(Source, utf8)} | Acc]
    end, [], Tools),
    {reply, lists:reverse(ToolList), State};

handle_call(get_unified_resources, _From, #state{resources = Resources} = State) ->
    ResourceList = maps:values(Resources),
    {reply, ResourceList, State};

handle_call(get_status, _From, State) ->
    #state{tools = Tools, resources = Resources, stats = Stats} = State,
    ElrmcpTools = maps:fold(fun(_K, #tool_entry{source = elrmcp}, Count) -> Count + 1;
                                (_K, _, Count) -> Count
                            end, 0, Tools),
    BeamaiTools = maps:fold(fun(_K, #tool_entry{source = beamai_mcp}, Count) -> Count + 1;
                                (_K, _, Count) -> Count
                            end, 0, Tools),
    Status = #{
        total_tools => map_size(Tools),
        elrmcp_tools => ElrmcpTools,
        beamai_mcp_tools => BeamaiTools,
        total_resources => map_size(Resources),
        elrmcp_available => is_elrmcp_available(),
        beamai_mcp_available => is_beamai_mcp_available(),
        stats => Stats
    },
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(sync, State) ->
    NewState = do_sync(State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(sync, State) ->
    NewState = do_sync(State),
    %% Reschedule
    SyncRef = erlang:send_after(?SYNC_INTERVAL_MS, self(), sync),
    {noreply, NewState#state{sync_ref = SyncRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{sync_ref = Ref}) ->
    case Ref of
        undefined -> ok;
        _ -> erlang:cancel_timer(Ref)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Handle an MCP request by routing to the appropriate backend.
-spec do_handle_request(binary(), map(), #state{}) ->
    {{ok, map()} | {error, map()}, #state{}}.
do_handle_request(<<"tools/list">>, _Params, #state{tools = Tools} = State) ->
    ToolList = maps:fold(fun(_Name, #tool_entry{definition = Def}, Acc) ->
        [Def | Acc]
    end, [], Tools),
    {{ok, #{<<"tools">> => lists:reverse(ToolList)}}, State};

do_handle_request(<<"tools/call">>, Params, State) ->
    ToolName = maps:get(<<"name">>, Params, <<>>),
    Args = maps:get(<<"arguments">>, Params, #{}),
    #state{tools = Tools} = State,
    case maps:find(ToolName, Tools) of
        {ok, #tool_entry{source = Source}} ->
            %% Route to the appropriate backend
            Result = case Source of
                beamai_mcp ->
                    try_beamai_mcp_tool_call(ToolName, Args);
                elrmcp ->
                    try_elrmcp_tool_call(ToolName, Args)
            end,
            case Result of
                {ok, Content} ->
                    {{ok, #{<<"content">> => Content, <<"isError">> => false}}, State};
                {error, Reason} ->
                    ErrContent = [#{<<"type">> => <<"text">>,
                                    <<"text">> => format_error(Reason)}],
                    {{ok, #{<<"content">> => ErrContent, <<"isError">> => true}}, State}
            end;
        error ->
            %% Try both backends
            case try_beamai_mcp_tool_call(ToolName, Args) of
                {ok, Content} ->
                    {{ok, #{<<"content">> => Content, <<"isError">> => false}}, State};
                {error, _} ->
                    case try_elrmcp_tool_call(ToolName, Args) of
                        {ok, Content} ->
                            {{ok, #{<<"content">> => Content, <<"isError">> => false}}, State};
                        {error, Reason} ->
                            ErrMsg = iolist_to_binary(
                                io_lib:format("Tool not found: ~s (~p)", [ToolName, Reason])),
                            {{error, #{<<"code">> => -32601,
                                       <<"message">> => ErrMsg}}, State}
                    end
            end
    end;

do_handle_request(<<"resources/list">>, _Params, #state{resources = Resources} = State) ->
    ResourceList = maps:values(Resources),
    {{ok, #{<<"resources">> => ResourceList}}, State};

do_handle_request(Method, Params, State) ->
    %% Try beamai_mcp_server first, then forward if not handled
    case is_beamai_mcp_available() of
        true ->
            case beamai_mcp_server:handle_request(Method, Params) of
                {ok, Result} -> {{ok, Result}, State};
                {error, #{<<"code">> := -32601}} ->
                    %% Method not found in beamai_mcp, try elrmcp
                    try_elrmcp_request(Method, Params, State);
                {error, Error} ->
                    {{error, Error}, State}
            end;
        false ->
            try_elrmcp_request(Method, Params, State)
    end.

%% @private Try to handle a request via elrmcp.
-spec try_elrmcp_request(binary(), map(), #state{}) ->
    {{ok, map()} | {error, map()}, #state{}}.
try_elrmcp_request(_Method, _Params, State) ->
    %% elrmcp bridge integration point
    %% The actual implementation depends on the elrmcp_bridge API
    {{error, #{<<"code">> => -32601,
               <<"message">> => <<"Method not available in any MCP backend">>}}, State}.

%% @private Forward a request to a specific target.
-spec do_forward(elrmcp | beamai_mcp, map()) -> {ok, map()} | {error, term()}.
do_forward(beamai_mcp, #{<<"method">> := Method, <<"params">> := Params}) ->
    case is_beamai_mcp_available() of
        true -> beamai_mcp_server:handle_request(Method, Params);
        false -> {error, beamai_mcp_not_available}
    end;
do_forward(beamai_mcp, Request) when is_map(Request) ->
    Method = maps:get(<<"method">>, Request, <<>>),
    Params = maps:get(<<"params">>, Request, #{}),
    do_forward(beamai_mcp, #{<<"method">> => Method, <<"params">> => Params});
do_forward(elrmcp, _Request) ->
    %% elrmcp bridge forwarding integration point
    {error, elrmcp_forward_not_implemented};
do_forward(Target, _Request) ->
    {error, {unknown_target, Target}}.

%% @private Synchronize tools from both MCP systems.
-spec do_sync(#state{}) -> #state{}.
do_sync(State) ->
    #state{stats = Stats} = State,
    State2 = sync_beamai_mcp_tools(State),
    State3 = sync_elrmcp_tools(State2),
    State4 = sync_resources(State3),
    Syncs = maps:get(syncs, Stats, 0),
    NewStats = Stats#{syncs => Syncs + 1},
    State4#state{stats = NewStats}.

%% @private Sync tools from beamai_mcp_server.
-spec sync_beamai_mcp_tools(#state{}) -> #state{}.
sync_beamai_mcp_tools(#state{tools = Tools} = State) ->
    case is_beamai_mcp_available() of
        true ->
            try
                case beamai_mcp_server:list_tools() of
                    {ok, ToolList} ->
                        Now = erlang:system_time(millisecond),
                        NewTools = lists:foldl(fun(ToolDef, Acc) ->
                            Name = maps:get(<<"name">>, ToolDef, <<>>),
                            Entry = #tool_entry{
                                name = Name,
                                source = beamai_mcp,
                                definition = ToolDef,
                                registered_at = Now
                            },
                            maps:put(Name, Entry, Acc)
                        end, Tools, ToolList),
                        State#state{tools = NewTools};
                    _ ->
                        State
                end
            catch
                _:_ -> State
            end;
        false ->
            State
    end.

%% @private Sync tools from elrmcp bridge.
-spec sync_elrmcp_tools(#state{}) -> #state{}.
sync_elrmcp_tools(#state{tools = Tools} = State) ->
    %% Integration point for elrmcp_bridge tool synchronization
    %% This will pull tools from the elrmcp_bridge when it is available
    case is_elrmcp_available() of
        true ->
            try
                %% Try to get tools from elrmcp_bridge
                %% The actual function depends on the elrmcp_bridge API
                State
            catch
                _:_ -> State
            end;
        false ->
            State
    end.

%% @private Sync resources from both systems.
-spec sync_resources(#state{}) -> #state{}.
sync_resources(#state{resources = Resources} = State) ->
    case is_beamai_mcp_available() of
        true ->
            try
                case beamai_mcp_server:list_resources() of
                    {ok, ResourceList} ->
                        NewResources = lists:foldl(fun(ResDef, Acc) ->
                            Uri = maps:get(<<"uri">>, ResDef, <<>>),
                            maps:put(Uri, ResDef, Acc)
                        end, Resources, ResourceList),
                        State#state{resources = NewResources};
                    _ ->
                        State
                end
            catch
                _:_ -> State
            end;
        false ->
            State
    end.

%% @private Register unified tools into the BeamAI kernel.
-spec do_register_tools(#state{}) -> #state{}.
do_register_tools(#state{tools = Tools, kernel_ref = KernelRef} = State) ->
    case whereis(KernelRef) of
        undefined ->
            logger:warning("MCP bridge: kernel ~p not available for tool registration", [KernelRef]),
            State;
        _Pid ->
            maps:foreach(fun(Name, #tool_entry{definition = Def, source = Source}) ->
                ToolDef = #{
                    name => Name,
                    description => maps:get(<<"description">>, Def, <<>>),
                    parameters => maps:get(<<"inputSchema">>, Def, #{}),
                    function => fun(Args, _Ctx) ->
                        case Source of
                            beamai_mcp -> try_beamai_mcp_tool_call(Name, Args);
                            elrmcp -> try_elrmcp_tool_call(Name, Args)
                        end
                    end,
                    tags => [<<"mcp">>, atom_to_binary(Source, utf8)],
                    metadata => #{mcp_source => Source}
                },
                try beamai_kernel:add_tool(KernelRef, ToolDef)
                catch _:_ -> ok
                end
            end, Tools),
            logger:info("MCP bridge: registered ~p tools with kernel", [map_size(Tools)]),
            State
    end.

%% @private Try to call a tool via beamai_mcp_server.
-spec try_beamai_mcp_tool_call(binary(), map()) -> {ok, [map()]} | {error, term()}.
try_beamai_mcp_tool_call(ToolName, Args) ->
    case is_beamai_mcp_available() of
        true ->
            try beamai_mcp_server:call_tool(ToolName, Args)
            catch _:Reason -> {error, {beamai_mcp_call_failed, Reason}}
            end;
        false ->
            {error, beamai_mcp_not_available}
    end.

%% @private Try to call a tool via elrmcp bridge.
-spec try_elrmcp_tool_call(binary(), map()) -> {ok, [map()]} | {error, term()}.
try_elrmcp_tool_call(_ToolName, _Args) ->
    %% Integration point for elrmcp_bridge tool calls
    {error, elrmcp_tool_call_not_implemented}.

%% @private Check if beamai_mcp_server is available.
-spec is_beamai_mcp_available() -> boolean().
is_beamai_mcp_available() ->
    whereis(beamai_mcp_server) =/= undefined.

%% @private Check if elrmcp bridge is available.
-spec is_elrmcp_available() -> boolean().
is_elrmcp_available() ->
    %% Check for the elrmcp_bridge process or module
    case code:is_loaded(elrmcp_bridge) of
        {file, _} -> true;
        false ->
            case code:ensure_loaded(elrmcp_bridge) of
                {module, _} -> true;
                _ -> false
            end
    end.

%% @private Format an error term as a binary.
-spec format_error(term()) -> binary().
format_error(Reason) when is_binary(Reason) -> Reason;
format_error(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8);
format_error(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).
