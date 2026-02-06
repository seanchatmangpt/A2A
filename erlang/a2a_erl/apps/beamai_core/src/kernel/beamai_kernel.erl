%%%-------------------------------------------------------------------
%%% @doc BeamAI Kernel implementation.
%%% A gen_server that manages the tool registry, LLM providers,
%%% filter pipeline, and execution context for the BeamAI framework.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_kernel).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    default/0,
    get_or_create/1,
    add_tool/2,
    add_tools/2,
    add_llm/3,
    add_filter/2,
    add_filter/4,
    invoke_tool/4,
    chat/3,
    chat_with_tools/3,
    list_tools/1,
    list_tools/2,
    tools_by_tag/2,
    context/1
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

-define(DEFAULT_NAME, beamai_kernel).

-record(state, {
    name            :: atom(),
    tools    = #{}  :: #{binary() => map()},
    llms     = #{}  :: #{atom() => map()},
    filters  = []   :: [map()],
    context  = #{}  :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the default kernel process.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(?DEFAULT_NAME).

%% @doc Start a named kernel process.
-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [Name], []).

%% @doc Return the default kernel registered name.
-spec default() -> atom().
default() ->
    ?DEFAULT_NAME.

%% @doc Get an existing kernel by name, or create one dynamically.
-spec get_or_create(atom()) -> atom().
get_or_create(Name) ->
    case whereis(Name) of
        undefined ->
            case beamai_core_sup:start_link() of
                {ok, _Pid} -> Name;
                {error, {already_started, _Pid}} -> Name;
                _Error -> Name
            end;
        _Pid ->
            Name
    end.

%% @doc Add a single tool definition to the kernel.
-spec add_tool(atom() | pid(), map()) -> ok.
add_tool(KernelRef, ToolDef) ->
    gen_server:call(KernelRef, {add_tool, ToolDef}).

%% @doc Add multiple tool definitions to the kernel.
-spec add_tools(atom() | pid(), [map()]) -> ok.
add_tools(KernelRef, ToolDefs) ->
    gen_server:call(KernelRef, {add_tools, ToolDefs}).

%% @doc Add an LLM provider with options.
-spec add_llm(atom() | pid(), atom(), map() | proplists:proplist()) -> ok.
add_llm(KernelRef, Provider, Opts) ->
    gen_server:call(KernelRef, {add_llm, Provider, Opts}).

%% @doc Add a global filter function.
-spec add_filter(atom() | pid(), fun()) -> ok.
add_filter(KernelRef, FilterFun) ->
    gen_server:call(KernelRef, {add_filter, FilterFun}).

%% @doc Add a stage-specific named filter with priority.
-spec add_filter(atom() | pid(), atom(), binary(), fun()) -> ok.
add_filter(KernelRef, Stage, Name, FilterFun) ->
    gen_server:call(KernelRef, {add_filter, Stage, Name, FilterFun}).

%% @doc Invoke a named tool with args and context.
-spec invoke_tool(atom() | pid(), binary() | atom(), map(), map()) ->
    {ok, term()} | {error, term()}.
invoke_tool(KernelRef, ToolName, Args, Context) ->
    gen_server:call(KernelRef, {invoke_tool, ToolName, Args, Context}, 30000).

%% @doc Send a chat message to the default LLM.
-spec chat(atom() | pid(), binary() | map(), map()) ->
    {ok, binary()} | {error, term()}.
chat(KernelRef, Message, Opts) ->
    gen_server:call(KernelRef, {chat, Message, Opts}, 60000).

%% @doc Send a chat message with tool use enabled.
-spec chat_with_tools(atom() | pid(), binary() | map(), map()) ->
    {ok, binary()} | {error, term()}.
chat_with_tools(KernelRef, Message, Opts) ->
    gen_server:call(KernelRef, {chat_with_tools, Message, Opts}, 60000).

%% @doc List all registered tools.
-spec list_tools(atom() | pid()) -> [map()].
list_tools(KernelRef) ->
    gen_server:call(KernelRef, list_tools).

%% @doc List tools matching filter criteria.
-spec list_tools(atom() | pid(), map()) -> [map()].
list_tools(KernelRef, Filter) ->
    gen_server:call(KernelRef, {list_tools, Filter}).

%% @doc List tools matching a specific tag.
-spec tools_by_tag(atom() | pid(), binary()) -> [map()].
tools_by_tag(KernelRef, Tag) ->
    gen_server:call(KernelRef, {tools_by_tag, Tag}).

%% @doc Get the current execution context.
-spec context(atom() | pid()) -> map().
context(KernelRef) ->
    gen_server:call(KernelRef, get_context).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init([Name]) ->
    DefaultLlm = beamai_config:get(default_llm, anthropic),
    Providers = beamai_config:get(providers, []),
    InitialLlms = maps:from_list([
        {Provider, maps:from_list(ProvOpts)}
        || {Provider, ProvOpts} <- Providers
    ]),
    InitialContext = #{
        kernel_name => Name,
        started_at => erlang:system_time(millisecond),
        default_llm => DefaultLlm
    },
    {ok, #state{
        name = Name,
        llms = InitialLlms,
        context = InitialContext
    }}.

%% @private
handle_call({add_tool, ToolDef}, _From, #state{tools = Tools} = State) ->
    Name = maps:get(name, ToolDef),
    NameBin = ensure_binary(Name),
    NewTools = Tools#{NameBin => ToolDef},
    {reply, ok, State#state{tools = NewTools}};

handle_call({add_tools, ToolDefs}, _From, #state{tools = Tools} = State) ->
    NewTools = lists:foldl(
        fun(ToolDef, Acc) ->
            Name = maps:get(name, ToolDef),
            NameBin = ensure_binary(Name),
            Acc#{NameBin => ToolDef}
        end,
        Tools,
        ToolDefs
    ),
    {reply, ok, State#state{tools = NewTools}};

handle_call({add_llm, Provider, Opts}, _From, #state{llms = Llms} = State) ->
    OptsMap = case is_list(Opts) of
        true -> maps:from_list(Opts);
        false -> Opts
    end,
    NewLlms = Llms#{Provider => OptsMap},
    {reply, ok, State#state{llms = NewLlms}};

handle_call({add_filter, FilterFun}, _From, #state{filters = Filters} = State) ->
    FilterDef = beamai_filter:new(FilterFun),
    NewFilters = Filters ++ [FilterDef],
    {reply, ok, State#state{filters = NewFilters}};

handle_call({add_filter, Stage, Name, FilterFun}, _From, #state{filters = Filters} = State) ->
    FilterDef = beamai_filter:new(Stage, Name, FilterFun),
    NewFilters = Filters ++ [FilterDef],
    {reply, ok, State#state{filters = NewFilters}};

handle_call({invoke_tool, ToolName, Args, Context}, _From,
            #state{tools = Tools, filters = Filters} = State) ->
    ToolNameBin = ensure_binary(ToolName),
    case maps:find(ToolNameBin, Tools) of
        {ok, ToolDef} ->
            %% Apply pre-invoke filters
            FilteredArgs = beamai_filter:apply_filters(
                pre_invoke, Filters, #{args => Args, context => Context, tool => ToolNameBin}
            ),
            FinalArgs = maps:get(args, FilteredArgs, Args),
            FinalContext = maps:get(context, FilteredArgs, Context),
            %% Execute the tool
            Result = beamai_tool:execute(ToolDef, FinalArgs, FinalContext),
            %% Apply post-invoke filters
            PostFiltered = beamai_filter:apply_filters(
                post_invoke, Filters, #{result => Result, context => FinalContext, tool => ToolNameBin}
            ),
            FinalResult = maps:get(result, PostFiltered, Result),
            {reply, FinalResult, State};
        error ->
            {reply, {error, {tool_not_found, ToolNameBin}}, State}
    end;

handle_call({chat, Message, Opts}, _From,
            #state{llms = Llms, filters = Filters, context = Ctx} = State) ->
    %% Apply pre-chat filters
    PreData = #{message => Message, opts => Opts, context => Ctx},
    Filtered = beamai_filter:apply_filters(pre_chat, Filters, PreData),
    FinalMessage = maps:get(message, Filtered, Message),
    FinalOpts = maps:get(opts, Filtered, Opts),
    %% Determine which LLM to use
    DefaultLlm = maps:get(default_llm, Ctx, anthropic),
    Provider = maps:get(provider, FinalOpts, DefaultLlm),
    LlmConfig = maps:get(Provider, Llms, #{}),
    %% Build the request
    Result = do_chat(Provider, LlmConfig, FinalMessage, FinalOpts),
    %% Apply post-chat filters
    PostData = #{result => Result, context => Ctx},
    PostFiltered = beamai_filter:apply_filters(post_chat, Filters, PostData),
    FinalResult = maps:get(result, PostFiltered, Result),
    {reply, FinalResult, State};

handle_call({chat_with_tools, Message, Opts}, _From,
            #state{tools = Tools, llms = Llms, filters = Filters, context = Ctx} = State) ->
    %% Build tool descriptions for the LLM
    ToolDescriptions = [beamai_tool:to_llm_format(T) || T <- maps:values(Tools)],
    %% Merge tool descriptions into opts
    OptsWithTools = Opts#{tools => ToolDescriptions},
    %% Apply pre-chat filters
    PreData = #{message => Message, opts => OptsWithTools, context => Ctx},
    Filtered = beamai_filter:apply_filters(pre_chat, Filters, PreData),
    FinalMessage = maps:get(message, Filtered, Message),
    FinalOpts = maps:get(opts, Filtered, OptsWithTools),
    %% Determine which LLM to use
    DefaultLlm = maps:get(default_llm, Ctx, anthropic),
    Provider = maps:get(provider, FinalOpts, DefaultLlm),
    LlmConfig = maps:get(Provider, Llms, #{}),
    %% Send to LLM
    Result = do_chat(Provider, LlmConfig, FinalMessage, FinalOpts),
    %% Apply post-chat filters
    PostData = #{result => Result, context => Ctx},
    PostFiltered = beamai_filter:apply_filters(post_chat, Filters, PostData),
    FinalResult = maps:get(result, PostFiltered, Result),
    {reply, FinalResult, State};

handle_call(list_tools, _From, #state{tools = Tools} = State) ->
    {reply, maps:values(Tools), State};

handle_call({list_tools, Filter}, _From, #state{tools = Tools} = State) ->
    AllTools = maps:values(Tools),
    Filtered = lists:filter(
        fun(ToolDef) -> beamai_tool:matches_filter(ToolDef, Filter) end,
        AllTools
    ),
    {reply, Filtered, State};

handle_call({tools_by_tag, Tag}, _From, #state{tools = Tools} = State) ->
    AllTools = maps:values(Tools),
    Tagged = lists:filter(
        fun(ToolDef) ->
            Tags = maps:get(tags, ToolDef, []),
            lists:member(Tag, Tags)
        end,
        AllTools
    ),
    {reply, Tagged, State};

handle_call(get_context, _From, #state{context = Ctx} = State) ->
    {reply, Ctx, State};

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

%% @private
%% @doc Execute a chat request against an LLM provider.
%% This is a placeholder that builds the HTTP request structure.
%% Actual LLM-specific logic will live in beamai_llm app modules.
-spec do_chat(atom(), map(), binary() | map(), map()) ->
    {ok, binary()} | {error, term()}.
do_chat(Provider, LlmConfig, Message, Opts) ->
    Model = maps:get(model, LlmConfig, default_model(Provider)),
    Messages = case is_map(Message) of
        true -> [Message];
        false -> [#{<<"role">> => <<"user">>, <<"content">> => Message}]
    end,
    RequestBody = #{
        <<"model">> => Model,
        <<"messages">> => Messages
    },
    FinalBody = case maps:get(tools, Opts, undefined) of
        undefined -> RequestBody;
        ToolDescs -> RequestBody#{<<"tools">> => ToolDescs}
    end,
    Url = provider_url(Provider),
    case beamai_http_client:post_json(Url, FinalBody, auth_headers(Provider)) of
        {ok, _Status, _Headers, RespBody} ->
            extract_response(Provider, RespBody);
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
-spec default_model(atom()) -> binary().
default_model(anthropic) -> <<"claude-sonnet-4-20250514">>;
default_model(openai) -> <<"gpt-4">>;
default_model(_) -> <<"unknown">>.

%% @private
-spec provider_url(atom()) -> binary().
provider_url(anthropic) -> <<"https://api.anthropic.com/v1/messages">>;
provider_url(openai) -> <<"https://api.openai.com/v1/chat/completions">>;
provider_url(_) -> <<"">>.

%% @private
-spec auth_headers(atom()) -> [{binary(), binary()}].
auth_headers(anthropic) ->
    ApiKey = beamai_config:get(anthropic_api_key, <<"">>),
    [
        {<<"x-api-key">>, ensure_binary(ApiKey)},
        {<<"anthropic-version">>, <<"2023-06-01">>}
    ];
auth_headers(openai) ->
    ApiKey = beamai_config:get(openai_api_key, <<"">>),
    [{<<"Authorization">>, <<"Bearer ", (ensure_binary(ApiKey))/binary>>}];
auth_headers(_) ->
    [].

%% @private
-spec extract_response(atom(), map() | binary()) -> {ok, binary()} | {error, term()}.
extract_response(anthropic, Body) when is_map(Body) ->
    case maps:get(<<"content">>, Body, []) of
        [#{<<"text">> := Text} | _] -> {ok, Text};
        _ -> {error, {unexpected_response, Body}}
    end;
extract_response(openai, Body) when is_map(Body) ->
    case maps:get(<<"choices">>, Body, []) of
        [#{<<"message">> := #{<<"content">> := Content}} | _] -> {ok, Content};
        _ -> {error, {unexpected_response, Body}}
    end;
extract_response(_Provider, Body) ->
    {error, {unsupported_provider_response, Body}}.

%% @private
-spec ensure_binary(atom() | binary() | list()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V).
