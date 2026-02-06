%%%-------------------------------------------------------------------
%%% @doc BeamAI MCP Server Implementation
%%%
%%% Implements the Model Context Protocol (MCP) server, handling
%%% tool list/call requests, resource requests, and prompt requests.
%%% Integrates with the BeamAI kernel tool registry to expose
%%% registered tools as MCP tools.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_server).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    handle_request/2,
    list_tools/0,
    call_tool/2,
    list_resources/0,
    get_resource/1,
    list_prompts/0,
    get_prompt/2,
    register_tool/1,
    register_resource/1,
    register_prompt/1,
    get_capabilities/0
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
-define(MCP_VERSION, <<"2024-11-05">>).

-record(mcp_tool, {
    name        :: binary(),
    description :: binary(),
    input_schema :: map(),
    handler     :: fun() | {module(), atom()}
}).

-record(mcp_resource, {
    uri         :: binary(),
    name        :: binary(),
    description :: binary(),
    mime_type   :: binary(),
    handler     :: fun() | {module(), atom()}
}).

-record(mcp_prompt, {
    name        :: binary(),
    description :: binary(),
    arguments   :: [map()],
    template    :: binary() | fun()
}).

-record(state, {
    config      :: map(),
    tools       :: #{binary() => #mcp_tool{}},
    resources   :: #{binary() => #mcp_resource{}},
    prompts     :: #{binary() => #mcp_prompt{}},
    kernel_ref  :: atom() | pid() | undefined,
    stats       :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the MCP server with the given configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Handle an incoming MCP JSON-RPC request.
%% Returns a JSON-RPC response map.
-spec handle_request(binary(), map()) -> {ok, map()} | {error, map()}.
handle_request(Method, Params) ->
    gen_server:call(?SERVER, {handle_request, Method, Params}, 30000).

%% @doc List all registered MCP tools.
-spec list_tools() -> {ok, [map()]}.
list_tools() ->
    gen_server:call(?SERVER, list_tools).

%% @doc Call an MCP tool by name with arguments.
-spec call_tool(binary(), map()) -> {ok, [map()]} | {error, term()}.
call_tool(ToolName, Args) ->
    gen_server:call(?SERVER, {call_tool, ToolName, Args}, 30000).

%% @doc List all registered MCP resources.
-spec list_resources() -> {ok, [map()]}.
list_resources() ->
    gen_server:call(?SERVER, list_resources).

%% @doc Get an MCP resource by URI.
-spec get_resource(binary()) -> {ok, [map()]} | {error, term()}.
get_resource(Uri) ->
    gen_server:call(?SERVER, {get_resource, Uri}).

%% @doc List all registered MCP prompts.
-spec list_prompts() -> {ok, [map()]}.
list_prompts() ->
    gen_server:call(?SERVER, list_prompts).

%% @doc Get an MCP prompt by name with arguments.
-spec get_prompt(binary(), map()) -> {ok, map()} | {error, term()}.
get_prompt(Name, Args) ->
    gen_server:call(?SERVER, {get_prompt, Name, Args}).

%% @doc Register a tool definition with the MCP server.
-spec register_tool(map()) -> ok | {error, term()}.
register_tool(ToolDef) ->
    gen_server:call(?SERVER, {register_tool, ToolDef}).

%% @doc Register a resource definition with the MCP server.
-spec register_resource(map()) -> ok | {error, term()}.
register_resource(ResourceDef) ->
    gen_server:call(?SERVER, {register_resource, ResourceDef}).

%% @doc Register a prompt definition with the MCP server.
-spec register_prompt(map()) -> ok | {error, term()}.
register_prompt(PromptDef) ->
    gen_server:call(?SERVER, {register_prompt, PromptDef}).

%% @doc Get the MCP server capabilities.
-spec get_capabilities() -> map().
get_capabilities() ->
    gen_server:call(?SERVER, get_capabilities).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),
    State = #state{
        config = Config,
        tools = #{},
        resources = #{},
        prompts = #{},
        kernel_ref = KernelRef,
        stats = #{
            requests_handled => 0,
            tool_calls => 0,
            resource_reads => 0,
            errors => 0
        }
    },
    %% Sync tools from kernel if available
    State2 = sync_kernel_tools(State),
    logger:info("BeamAI MCP server started (protocol version ~s)", [?MCP_VERSION]),
    {ok, State2}.

%% @private
handle_call({handle_request, Method, Params}, _From, State) ->
    {Result, NewState} = do_handle_request(Method, Params, State),
    Handled = maps:get(requests_handled, NewState#state.stats, 0),
    NewStats = (NewState#state.stats)#{requests_handled => Handled + 1},
    {reply, Result, NewState#state{stats = NewStats}};

handle_call(list_tools, _From, #state{tools = Tools} = State) ->
    ToolList = maps:fold(fun(_Name, Tool, Acc) ->
        [tool_to_map(Tool) | Acc]
    end, [], Tools),
    {reply, {ok, lists:reverse(ToolList)}, State};

handle_call({call_tool, ToolName, Args}, _From, State) ->
    #state{tools = Tools, kernel_ref = KernelRef, stats = Stats} = State,
    case maps:find(ToolName, Tools) of
        {ok, Tool} ->
            Result = execute_mcp_tool(Tool, Args, KernelRef),
            CallCount = maps:get(tool_calls, Stats, 0),
            NewStats = Stats#{tool_calls => CallCount + 1},
            {reply, Result, State#state{stats = NewStats}};
        error ->
            %% Try kernel tools as fallback
            case try_kernel_tool(KernelRef, ToolName, Args) of
                {ok, _} = Result ->
                    CallCount = maps:get(tool_calls, Stats, 0),
                    NewStats = Stats#{tool_calls => CallCount + 1},
                    {reply, Result, State#state{stats = NewStats}};
                {error, _} = Err ->
                    ErrCount = maps:get(errors, Stats, 0),
                    NewStats = Stats#{errors => ErrCount + 1},
                    {reply, Err, State#state{stats = NewStats}}
            end
    end;

handle_call(list_resources, _From, #state{resources = Resources} = State) ->
    ResourceList = maps:fold(fun(_Uri, Res, Acc) ->
        [resource_to_map(Res) | Acc]
    end, [], Resources),
    {reply, {ok, lists:reverse(ResourceList)}, State};

handle_call({get_resource, Uri}, _From, #state{resources = Resources, stats = Stats} = State) ->
    case maps:find(Uri, Resources) of
        {ok, Resource} ->
            Result = read_resource(Resource),
            Reads = maps:get(resource_reads, Stats, 0),
            NewStats = Stats#{resource_reads => Reads + 1},
            {reply, Result, State#state{stats = NewStats}};
        error ->
            ErrCount = maps:get(errors, Stats, 0),
            NewStats = Stats#{errors => ErrCount + 1},
            {reply, {error, {resource_not_found, Uri}}, State#state{stats = NewStats}}
    end;

handle_call(list_prompts, _From, #state{prompts = Prompts} = State) ->
    PromptList = maps:fold(fun(_Name, Prompt, Acc) ->
        [prompt_to_map(Prompt) | Acc]
    end, [], Prompts),
    {reply, {ok, lists:reverse(PromptList)}, State};

handle_call({get_prompt, Name, Args}, _From, #state{prompts = Prompts} = State) ->
    case maps:find(Name, Prompts) of
        {ok, Prompt} ->
            Result = render_prompt(Prompt, Args),
            {reply, Result, State};
        error ->
            {reply, {error, {prompt_not_found, Name}}, State}
    end;

handle_call({register_tool, ToolDef}, _From, #state{tools = Tools} = State) ->
    case validate_tool_def(ToolDef) of
        {ok, Tool} ->
            NewTools = maps:put(Tool#mcp_tool.name, Tool, Tools),
            {reply, ok, State#state{tools = NewTools}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({register_resource, ResourceDef}, _From, #state{resources = Resources} = State) ->
    case validate_resource_def(ResourceDef) of
        {ok, Resource} ->
            NewResources = maps:put(Resource#mcp_resource.uri, Resource, Resources),
            {reply, ok, State#state{resources = NewResources}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({register_prompt, PromptDef}, _From, #state{prompts = Prompts} = State) ->
    case validate_prompt_def(PromptDef) of
        {ok, Prompt} ->
            NewPrompts = maps:put(Prompt#mcp_prompt.name, Prompt, Prompts),
            {reply, ok, State#state{prompts = NewPrompts}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_capabilities, _From, State) ->
    Caps = #{
        <<"protocolVersion">> => ?MCP_VERSION,
        <<"capabilities">> => #{
            <<"tools">> => #{<<"listChanged">> => true},
            <<"resources">> => #{<<"subscribe">> => false, <<"listChanged">> => true},
            <<"prompts">> => #{<<"listChanged">> => true}
        },
        <<"serverInfo">> => #{
            <<"name">> => <<"beamai-mcp-server">>,
            <<"version">> => <<"0.1.0">>
        }
    },
    {reply, Caps, State};

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
%% Internal functions
%%====================================================================

%% @private Handle an MCP JSON-RPC method call.
-spec do_handle_request(binary(), map(), #state{}) -> {{ok, map()} | {error, map()}, #state{}}.
do_handle_request(<<"initialize">>, _Params, State) ->
    Caps = #{
        <<"protocolVersion">> => ?MCP_VERSION,
        <<"capabilities">> => #{
            <<"tools">> => #{<<"listChanged">> => true},
            <<"resources">> => #{<<"subscribe">> => false, <<"listChanged">> => true},
            <<"prompts">> => #{<<"listChanged">> => true}
        },
        <<"serverInfo">> => #{
            <<"name">> => <<"beamai-mcp-server">>,
            <<"version">> => <<"0.1.0">>
        }
    },
    {{ok, Caps}, State};

do_handle_request(<<"tools/list">>, _Params, #state{tools = Tools} = State) ->
    ToolList = maps:fold(fun(_Name, Tool, Acc) ->
        [tool_to_map(Tool) | Acc]
    end, [], Tools),
    {{ok, #{<<"tools">> => lists:reverse(ToolList)}}, State};

do_handle_request(<<"tools/call">>, Params, State) ->
    ToolName = maps:get(<<"name">>, Params, <<>>),
    Args = maps:get(<<"arguments">>, Params, #{}),
    #state{tools = Tools, kernel_ref = KernelRef, stats = Stats} = State,
    case maps:find(ToolName, Tools) of
        {ok, Tool} ->
            case execute_mcp_tool(Tool, Args, KernelRef) of
                {ok, Content} ->
                    Result = #{<<"content">> => Content, <<"isError">> => false},
                    CallCount = maps:get(tool_calls, Stats, 0),
                    NewStats = Stats#{tool_calls => CallCount + 1},
                    {{ok, Result}, State#state{stats = NewStats}};
                {error, Reason} ->
                    ErrContent = [#{<<"type">> => <<"text">>,
                                    <<"text">> => format_error(Reason)}],
                    Result = #{<<"content">> => ErrContent, <<"isError">> => true},
                    ErrCount = maps:get(errors, Stats, 0),
                    NewStats = Stats#{errors => ErrCount + 1},
                    {{ok, Result}, State#state{stats = NewStats}}
            end;
        error ->
            case try_kernel_tool(KernelRef, ToolName, Args) of
                {ok, Content} ->
                    Result = #{<<"content">> => Content, <<"isError">> => false},
                    {{ok, Result}, State};
                {error, Reason} ->
                    ErrMsg = format_error({tool_not_found, ToolName, Reason}),
                    {{error, #{<<"code">> => -32601,
                               <<"message">> => ErrMsg}}, State}
            end
    end;

do_handle_request(<<"resources/list">>, _Params, #state{resources = Resources} = State) ->
    ResourceList = maps:fold(fun(_Uri, Res, Acc) ->
        [resource_to_map(Res) | Acc]
    end, [], Resources),
    {{ok, #{<<"resources">> => lists:reverse(ResourceList)}}, State};

do_handle_request(<<"resources/read">>, Params, #state{resources = Resources, stats = Stats} = State) ->
    Uri = maps:get(<<"uri">>, Params, <<>>),
    case maps:find(Uri, Resources) of
        {ok, Resource} ->
            case read_resource(Resource) of
                {ok, Contents} ->
                    Reads = maps:get(resource_reads, Stats, 0),
                    NewStats = Stats#{resource_reads => Reads + 1},
                    {{ok, #{<<"contents">> => Contents}}, State#state{stats = NewStats}};
                {error, Reason} ->
                    ErrMsg = format_error(Reason),
                    {{error, #{<<"code">> => -32002, <<"message">> => ErrMsg}}, State}
            end;
        error ->
            {{error, #{<<"code">> => -32002,
                       <<"message">> => <<"Resource not found: ", Uri/binary>>}}, State}
    end;

do_handle_request(<<"prompts/list">>, _Params, #state{prompts = Prompts} = State) ->
    PromptList = maps:fold(fun(_Name, Prompt, Acc) ->
        [prompt_to_map(Prompt) | Acc]
    end, [], Prompts),
    {{ok, #{<<"prompts">> => lists:reverse(PromptList)}}, State};

do_handle_request(<<"prompts/get">>, Params, #state{prompts = Prompts} = State) ->
    Name = maps:get(<<"name">>, Params, <<>>),
    Args = maps:get(<<"arguments">>, Params, #{}),
    case maps:find(Name, Prompts) of
        {ok, Prompt} ->
            case render_prompt(Prompt, Args) of
                {ok, Result} ->
                    {{ok, Result}, State};
                {error, Reason} ->
                    ErrMsg = format_error(Reason),
                    {{error, #{<<"code">> => -32002, <<"message">> => ErrMsg}}, State}
            end;
        error ->
            {{error, #{<<"code">> => -32002,
                       <<"message">> => <<"Prompt not found: ", Name/binary>>}}, State}
    end;

do_handle_request(<<"ping">>, _Params, State) ->
    {{ok, #{}}, State};

do_handle_request(Method, _Params, State) ->
    {{error, #{<<"code">> => -32601,
               <<"message">> => <<"Method not found: ", Method/binary>>}}, State}.

%% @private Sync tools from the BeamAI kernel.
-spec sync_kernel_tools(#state{}) -> #state{}.
sync_kernel_tools(#state{kernel_ref = KernelRef, tools = ExistingTools} = State) ->
    try
        case whereis(KernelRef) of
            undefined -> State;
            _Pid ->
                KernelTools = beamai_kernel:list_tools(KernelRef),
                NewTools = lists:foldl(fun(ToolDef, Acc) ->
                    Name = maps:get(name, ToolDef, <<>>),
                    case maps:is_key(Name, Acc) of
                        true -> Acc; %% Don't overwrite explicitly registered tools
                        false ->
                            McpTool = #mcp_tool{
                                name = Name,
                                description = maps:get(description, ToolDef, <<>>),
                                input_schema = maps:get(parameters, ToolDef, #{}),
                                handler = {beamai_kernel, invoke_tool}
                            },
                            maps:put(Name, McpTool, Acc)
                    end
                end, ExistingTools, KernelTools),
                State#state{tools = NewTools}
        end
    catch
        _:_ -> State
    end.

%% @private Execute an MCP tool.
-spec execute_mcp_tool(#mcp_tool{}, map(), atom() | pid() | undefined) ->
    {ok, [map()]} | {error, term()}.
execute_mcp_tool(#mcp_tool{handler = Fun, name = Name}, Args, _KernelRef)
  when is_function(Fun, 1) ->
    try
        Result = Fun(Args),
        {ok, format_tool_result(Name, Result)}
    catch
        Class:Reason:Stack ->
            logger:error("MCP tool ~s failed: ~p:~p~n~p", [Name, Class, Reason, Stack]),
            {error, {tool_execution_failed, Name, Reason}}
    end;
execute_mcp_tool(#mcp_tool{handler = Fun, name = Name}, Args, _KernelRef)
  when is_function(Fun, 2) ->
    try
        Result = Fun(Args, #{}),
        {ok, format_tool_result(Name, Result)}
    catch
        Class:Reason:Stack ->
            logger:error("MCP tool ~s failed: ~p:~p~n~p", [Name, Class, Reason, Stack]),
            {error, {tool_execution_failed, Name, Reason}}
    end;
execute_mcp_tool(#mcp_tool{handler = {beamai_kernel, invoke_tool}, name = Name}, Args, KernelRef)
  when KernelRef =/= undefined ->
    try
        case beamai_kernel:invoke_tool(KernelRef, Name, Args, #{}) of
            {ok, Result} ->
                {ok, format_tool_result(Name, Result)};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Reason:Stack ->
            logger:error("MCP kernel tool ~s failed: ~p:~p~n~p", [Name, Class, Reason, Stack]),
            {error, {tool_execution_failed, Name, Reason}}
    end;
execute_mcp_tool(#mcp_tool{handler = {Module, Function}, name = Name}, Args, _KernelRef) ->
    try
        Result = Module:Function(Args),
        {ok, format_tool_result(Name, Result)}
    catch
        Class:Reason:Stack ->
            logger:error("MCP tool ~s (~p:~p) failed: ~p:~p~n~p",
                         [Name, Module, Function, Class, Reason, Stack]),
            {error, {tool_execution_failed, Name, Reason}}
    end.

%% @private Try to call a tool through the kernel as fallback.
-spec try_kernel_tool(atom() | pid() | undefined, binary(), map()) ->
    {ok, [map()]} | {error, term()}.
try_kernel_tool(undefined, ToolName, _Args) ->
    {error, {tool_not_found, ToolName}};
try_kernel_tool(KernelRef, ToolName, Args) ->
    try
        case whereis(KernelRef) of
            undefined ->
                {error, {kernel_not_available, KernelRef}};
            _Pid ->
                case beamai_kernel:invoke_tool(KernelRef, ToolName, Args, #{}) of
                    {ok, Result} ->
                        {ok, format_tool_result(ToolName, Result)};
                    {error, Reason} ->
                        {error, Reason}
                end
        end
    catch
        _:Error -> {error, Error}
    end.

%% @private Format a tool result as MCP content.
-spec format_tool_result(binary(), term()) -> [map()].
format_tool_result(_Name, Result) when is_binary(Result) ->
    [#{<<"type">> => <<"text">>, <<"text">> => Result}];
format_tool_result(_Name, Result) when is_map(Result) ->
    [#{<<"type">> => <<"text">>, <<"text">> => jsx:encode(Result)}];
format_tool_result(_Name, Result) when is_list(Result) ->
    [#{<<"type">> => <<"text">>, <<"text">> => jsx:encode(Result)}];
format_tool_result(_Name, Result) ->
    Text = iolist_to_binary(io_lib:format("~p", [Result])),
    [#{<<"type">> => <<"text">>, <<"text">> => Text}].

%% @private Read a resource and return its contents.
-spec read_resource(#mcp_resource{}) -> {ok, [map()]} | {error, term()}.
read_resource(#mcp_resource{uri = Uri, mime_type = MimeType, handler = Fun})
  when is_function(Fun, 1) ->
    try
        case Fun(Uri) of
            {ok, Content} when is_binary(Content) ->
                {ok, [#{<<"uri">> => Uri, <<"mimeType">> => MimeType, <<"text">> => Content}]};
            {ok, Content} when is_map(Content) ->
                {ok, [#{<<"uri">> => Uri, <<"mimeType">> => MimeType,
                        <<"text">> => jsx:encode(Content)}]};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Reason:_Stack ->
            {error, {resource_read_failed, Class, Reason}}
    end;
read_resource(#mcp_resource{handler = {Module, Function}, uri = Uri, mime_type = MimeType}) ->
    try
        case Module:Function(Uri) of
            {ok, Content} when is_binary(Content) ->
                {ok, [#{<<"uri">> => Uri, <<"mimeType">> => MimeType, <<"text">> => Content}]};
            {ok, Content} when is_map(Content) ->
                {ok, [#{<<"uri">> => Uri, <<"mimeType">> => MimeType,
                        <<"text">> => jsx:encode(Content)}]};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Reason:_Stack ->
            {error, {resource_read_failed, Class, Reason}}
    end;
read_resource(#mcp_resource{uri = Uri}) ->
    {error, {no_handler, Uri}}.

%% @private Render a prompt template with arguments.
-spec render_prompt(#mcp_prompt{}, map()) -> {ok, map()} | {error, term()}.
render_prompt(#mcp_prompt{name = Name, description = Desc, template = Template}, Args)
  when is_binary(Template) ->
    %% Simple template substitution: replace {{key}} with value
    RenderedText = maps:fold(fun(Key, Value, Acc) ->
        Pattern = <<"{{", (ensure_binary(Key))/binary, "}}">>,
        binary:replace(Acc, Pattern, ensure_binary(Value), [global])
    end, Template, Args),
    {ok, #{
        <<"description">> => Desc,
        <<"messages">> => [#{
            <<"role">> => <<"user">>,
            <<"content">> => #{
                <<"type">> => <<"text">>,
                <<"text">> => RenderedText
            }
        }]
    }};
render_prompt(#mcp_prompt{name = Name, description = Desc, template = Fun}, Args)
  when is_function(Fun, 1) ->
    try
        Messages = Fun(Args),
        {ok, #{<<"description">> => Desc, <<"messages">> => Messages}}
    catch
        _:Reason ->
            {error, {prompt_render_failed, Name, Reason}}
    end;
render_prompt(#mcp_prompt{name = Name}, _Args) ->
    {error, {invalid_template, Name}}.

%% @private Convert a tool record to an MCP map.
-spec tool_to_map(#mcp_tool{}) -> map().
tool_to_map(#mcp_tool{name = Name, description = Desc, input_schema = Schema}) ->
    #{
        <<"name">> => Name,
        <<"description">> => Desc,
        <<"inputSchema">> => normalize_schema(Schema)
    }.

%% @private Convert a resource record to an MCP map.
-spec resource_to_map(#mcp_resource{}) -> map().
resource_to_map(#mcp_resource{uri = Uri, name = Name, description = Desc, mime_type = Mime}) ->
    #{
        <<"uri">> => Uri,
        <<"name">> => Name,
        <<"description">> => Desc,
        <<"mimeType">> => Mime
    }.

%% @private Convert a prompt record to an MCP map.
-spec prompt_to_map(#mcp_prompt{}) -> map().
prompt_to_map(#mcp_prompt{name = Name, description = Desc, arguments = Args}) ->
    #{
        <<"name">> => Name,
        <<"description">> => Desc,
        <<"arguments">> => Args
    }.

%% @private Validate and construct a tool definition.
-spec validate_tool_def(map()) -> {ok, #mcp_tool{}} | {error, term()}.
validate_tool_def(#{name := Name, handler := Handler} = Def) ->
    {ok, #mcp_tool{
        name = ensure_binary(Name),
        description = ensure_binary(maps:get(description, Def, <<>>)),
        input_schema = maps:get(input_schema, Def, #{<<"type">> => <<"object">>}),
        handler = Handler
    }};
validate_tool_def(_) ->
    {error, {invalid_tool_def, missing_required_fields}}.

%% @private Validate and construct a resource definition.
-spec validate_resource_def(map()) -> {ok, #mcp_resource{}} | {error, term()}.
validate_resource_def(#{uri := Uri, name := Name} = Def) ->
    {ok, #mcp_resource{
        uri = ensure_binary(Uri),
        name = ensure_binary(Name),
        description = ensure_binary(maps:get(description, Def, <<>>)),
        mime_type = ensure_binary(maps:get(mime_type, Def, <<"text/plain">>)),
        handler = maps:get(handler, Def, undefined)
    }};
validate_resource_def(_) ->
    {error, {invalid_resource_def, missing_required_fields}}.

%% @private Validate and construct a prompt definition.
-spec validate_prompt_def(map()) -> {ok, #mcp_prompt{}} | {error, term()}.
validate_prompt_def(#{name := Name, template := Template} = Def) ->
    {ok, #mcp_prompt{
        name = ensure_binary(Name),
        description = ensure_binary(maps:get(description, Def, <<>>)),
        arguments = maps:get(arguments, Def, []),
        template = Template
    }};
validate_prompt_def(_) ->
    {error, {invalid_prompt_def, missing_required_fields}}.

%% @private Normalize a schema map to JSON Schema format.
-spec normalize_schema(map()) -> map().
normalize_schema(Schema) when map_size(Schema) =:= 0 ->
    #{<<"type">> => <<"object">>, <<"properties">> => #{}};
normalize_schema(Schema) ->
    case maps:is_key(<<"type">>, Schema) of
        true -> Schema;
        false ->
            #{<<"type">> => <<"object">>, <<"properties">> => Schema}
    end.

%% @private Format an error term as a binary string.
-spec format_error(term()) -> binary().
format_error(Reason) when is_binary(Reason) -> Reason;
format_error(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8);
format_error(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) when is_integer(V) -> integer_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
