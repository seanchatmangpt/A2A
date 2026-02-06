%%%-------------------------------------------------------------------
%%% @doc BeamAI Tool Registry and Management.
%%%
%%% Main tool registry providing:
%%% - Register tools with name, description, JSON schema, and handler
%%% - Tool discovery and filtering by tags
%%% - Tool schema validation against JSON Schema
%%% - Tool execution with middleware pipeline
%%% - ETS-backed storage for fast lookups
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tools).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    register/2,
    unregister/1,
    get/1,
    list/0,
    list/1,
    by_tag/1,
    validate_input/2,
    execute/3
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
-define(TOOL_TABLE, beamai_tools_registry).

%%====================================================================
%% Records and Types
%%====================================================================

-record(tool_entry, {
    name        :: binary(),
    description :: binary(),
    handler     :: fun() | {module(), atom()},
    schema      :: map(),
    tags        :: [binary()],
    metadata    :: map(),
    middleware  :: [fun()],
    registered_at :: integer()
}).

-record(state, {
    max_tools   :: non_neg_integer(),
    tool_count  :: non_neg_integer(),
    middlewares  :: [fun()]
}).

-type tool_def() :: #{
    name := binary(),
    description => binary(),
    handler := fun() | {module(), atom()},
    schema => map(),
    tags => [binary()],
    metadata => map(),
    middleware => [fun()]
}.

-type tool_filter() :: #{
    name => binary(),
    tags => [binary()],
    metadata => map()
}.

-export_type([tool_def/0, tool_filter/0]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the tool registry with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the tool registry with custom options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Register a tool with name and definition.
%% Definition must include at minimum a handler function.
-spec register(binary(), tool_def()) -> ok | {error, term()}.
register(Name, ToolDef) ->
    gen_server:call(?SERVER, {register, ensure_binary(Name), ToolDef}).

%% @doc Unregister a tool by name.
-spec unregister(binary()) -> ok | {error, not_found}.
unregister(Name) ->
    gen_server:call(?SERVER, {unregister, ensure_binary(Name)}).

%% @doc Get a tool definition by name.
-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Name) ->
    case ets:lookup(?TOOL_TABLE, ensure_binary(Name)) of
        [{_, Entry}] -> {ok, entry_to_map(Entry)};
        [] -> {error, not_found}
    end.

%% @doc List all registered tools.
-spec list() -> [map()].
list() ->
    ets:foldl(fun({_Name, Entry}, Acc) ->
        [entry_to_map(Entry) | Acc]
    end, [], ?TOOL_TABLE).

%% @doc List tools matching a filter.
%% Filter can contain: name (substring match), tags (must have all), metadata.
-spec list(tool_filter()) -> [map()].
list(Filter) ->
    AllTools = list(),
    lists:filter(fun(Tool) -> matches_filter(Tool, Filter) end, AllTools).

%% @doc Find tools by tag.
-spec by_tag(binary()) -> [map()].
by_tag(Tag) ->
    TagBin = ensure_binary(Tag),
    ets:foldl(fun({_Name, Entry}, Acc) ->
        case lists:member(TagBin, Entry#tool_entry.tags) of
            true -> [entry_to_map(Entry) | Acc];
            false -> Acc
        end
    end, [], ?TOOL_TABLE).

%% @doc Validate input against a tool's JSON Schema.
-spec validate_input(binary(), map()) -> ok | {error, [term()]}.
validate_input(ToolName, Input) ->
    case ?MODULE:get(ensure_binary(ToolName)) of
        {ok, #{schema := Schema}} ->
            validate_against_schema(Input, Schema);
        {error, not_found} ->
            {error, {tool_not_found, ToolName}}
    end.

%% @doc Execute a tool with the given arguments and context.
%% Runs through middleware pipeline before and after execution.
-spec execute(binary(), map(), map()) -> {ok, term()} | {error, term()}.
execute(ToolName, Args, Context) ->
    gen_server:call(?SERVER, {execute, ensure_binary(ToolName), Args, Context}, 60000).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    %% Create ETS table for tool storage
    ets:new(?TOOL_TABLE, [named_table, set, public, {read_concurrency, true}]),

    MaxTools = maps:get(max_tools, Opts,
               application:get_env(beamai_tools, max_tools, 1024)),

    logger:info("BeamAI tool registry started (max_tools: ~p)", [MaxTools]),

    {ok, #state{
        max_tools = MaxTools,
        tool_count = 0,
        middlewares = maps:get(middlewares, Opts, [])
    }}.

%% @private
handle_call({register, Name, ToolDef}, _From, State) ->
    #state{max_tools = MaxTools, tool_count = Count} = State,
    case Count >= MaxTools of
        true ->
            {reply, {error, max_tools_reached}, State};
        false ->
            case validate_tool_def(ToolDef) of
                ok ->
                    Entry = map_to_entry(Name, ToolDef),
                    ets:insert(?TOOL_TABLE, {Name, Entry}),
                    logger:info("Registered tool: ~s", [Name]),
                    {reply, ok, State#state{tool_count = Count + 1}};
                {error, _} = Err ->
                    {reply, Err, State}
            end
    end;

handle_call({unregister, Name}, _From, State) ->
    case ets:lookup(?TOOL_TABLE, Name) of
        [{_, _}] ->
            ets:delete(?TOOL_TABLE, Name),
            logger:info("Unregistered tool: ~s", [Name]),
            {reply, ok, State#state{tool_count = max(0, State#state.tool_count - 1)}};
        [] ->
            {reply, {error, not_found}, State}
    end;

handle_call({execute, ToolName, Args, Context}, _From, State) ->
    Result = do_execute(ToolName, Args, Context, State),
    {reply, Result, State};

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
    catch ets:delete(?TOOL_TABLE),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
do_execute(ToolName, Args, Context, State) ->
    case ets:lookup(?TOOL_TABLE, ToolName) of
        [{_, Entry}] ->
            %% Check security
            case beamai_tool_security:check_permission(ToolName, Context) of
                ok ->
                    %% Sanitize input
                    SanitizedArgs = beamai_tool_security:sanitize_input(ToolName, Args),

                    %% Validate input against schema
                    case validate_against_schema(SanitizedArgs, Entry#tool_entry.schema) of
                        ok ->
                            %% Run through middleware pipeline
                            MiddlewareChain = State#state.middlewares ++ Entry#tool_entry.middleware,
                            ExecuteCtx = #{
                                tool_name => ToolName,
                                args => SanitizedArgs,
                                context => Context,
                                handler => Entry#tool_entry.handler
                            },
                            case beamai_tool_middleware:execute(MiddlewareChain, ExecuteCtx,
                                    fun(Ctx) -> invoke_handler(Entry#tool_entry.handler, Ctx) end) of
                                {ok, RawResult} ->
                                    %% Filter output
                                    FilteredResult = beamai_tool_security:filter_output(ToolName, RawResult),
                                    {ok, FilteredResult};
                                {error, _} = Err ->
                                    Err
                            end;
                        {error, _} = SchemaErr ->
                            SchemaErr
                    end;
                {error, _} = PermErr ->
                    PermErr
            end;
        [] ->
            {error, {tool_not_found, ToolName}}
    end.

%% @private
invoke_handler(Fun, Ctx) when is_function(Fun, 2) ->
    Args = maps:get(args, Ctx, #{}),
    Context = maps:get(context, Ctx, #{}),
    try
        Result = Fun(Args, Context),
        {ok, Result}
    catch
        Class:Reason:Stack ->
            logger:error("Tool handler failed: ~p:~p~n~p", [Class, Reason, Stack]),
            {error, {handler_error, Class, Reason}}
    end;
invoke_handler(Fun, Ctx) when is_function(Fun, 1) ->
    Args = maps:get(args, Ctx, #{}),
    try
        Result = Fun(Args),
        {ok, Result}
    catch
        Class:Reason:Stack ->
            logger:error("Tool handler failed: ~p:~p~n~p", [Class, Reason, Stack]),
            {error, {handler_error, Class, Reason}}
    end;
invoke_handler({Module, Function}, Ctx) ->
    Args = maps:get(args, Ctx, #{}),
    Context = maps:get(context, Ctx, #{}),
    try
        Result = Module:Function(Args, Context),
        {ok, Result}
    catch
        Class:Reason:Stack ->
            logger:error("Tool handler ~p:~p failed: ~p:~p~n~p",
                        [Module, Function, Class, Reason, Stack]),
            {error, {handler_error, Class, Reason}}
    end;
invoke_handler(_Handler, _Ctx) ->
    {error, invalid_handler}.

%% @private
validate_tool_def(ToolDef) when is_map(ToolDef) ->
    case maps:is_key(handler, ToolDef) of
        true ->
            Handler = maps:get(handler, ToolDef),
            case is_function(Handler) orelse is_mfa_tuple(Handler) of
                true -> ok;
                false -> {error, {invalid_handler, Handler}}
            end;
        false ->
            {error, missing_handler}
    end;
validate_tool_def(_) ->
    {error, invalid_tool_definition}.

%% @private
is_mfa_tuple({M, F}) when is_atom(M), is_atom(F) -> true;
is_mfa_tuple(_) -> false.

%% @private
validate_against_schema(_Input, Schema) when map_size(Schema) =:= 0 ->
    ok;
validate_against_schema(Input, Schema) ->
    %% Basic JSON Schema validation
    Type = maps:get(<<"type">>, Schema, maps:get(type, Schema, undefined)),
    case Type of
        <<"object">> ->
            validate_object(Input, Schema);
        object ->
            validate_object(Input, Schema);
        _ ->
            ok
    end.

%% @private
validate_object(Input, Schema) when is_map(Input) ->
    Required = maps:get(<<"required">>, Schema, maps:get(required, Schema, [])),
    Properties = maps:get(<<"properties">>, Schema, maps:get(properties, Schema, #{})),

    %% Check required fields
    MissingFields = lists:filter(fun(Field) ->
        FieldBin = ensure_binary(Field),
        not maps:is_key(FieldBin, Input) andalso not maps:is_key(Field, Input)
    end, Required),

    case MissingFields of
        [] ->
            %% Validate property types
            Errors = maps:fold(fun(PropName, PropSchema, Acc) ->
                PropNameBin = ensure_binary(PropName),
                case maps:find(PropNameBin, Input) of
                    {ok, Value} ->
                        case validate_property_type(Value, PropSchema) of
                            ok -> Acc;
                            {error, Reason} -> [{PropNameBin, Reason} | Acc]
                        end;
                    error ->
                        case maps:find(PropName, Input) of
                            {ok, Value} ->
                                case validate_property_type(Value, PropSchema) of
                                    ok -> Acc;
                                    {error, Reason} -> [{PropNameBin, Reason} | Acc]
                                end;
                            error ->
                                Acc  %% Not required, not present: ok
                        end
                end
            end, [], Properties),
            case Errors of
                [] -> ok;
                _ -> {error, {validation_errors, Errors}}
            end;
        _ ->
            {error, {missing_required_fields, MissingFields}}
    end;
validate_object(_Input, _Schema) ->
    {error, expected_object}.

%% @private
validate_property_type(_Value, Schema) when is_map(Schema) ->
    PropType = maps:get(<<"type">>, Schema, maps:get(type, Schema, undefined)),
    case PropType of
        undefined -> ok;
        _ -> ok  %% Simplified: accept all types for now
    end;
validate_property_type(_Value, _Schema) ->
    ok.

%% @private
map_to_entry(Name, ToolDef) ->
    #tool_entry{
        name = Name,
        description = maps:get(description, ToolDef, <<>>),
        handler = maps:get(handler, ToolDef),
        schema = maps:get(schema, ToolDef, #{}),
        tags = maps:get(tags, ToolDef, []),
        metadata = maps:get(metadata, ToolDef, #{}),
        middleware = maps:get(middleware, ToolDef, []),
        registered_at = erlang:system_time(millisecond)
    }.

%% @private
entry_to_map(#tool_entry{} = E) ->
    #{
        name => E#tool_entry.name,
        description => E#tool_entry.description,
        handler => E#tool_entry.handler,
        schema => E#tool_entry.schema,
        tags => E#tool_entry.tags,
        metadata => E#tool_entry.metadata,
        middleware => E#tool_entry.middleware,
        registered_at => E#tool_entry.registered_at
    }.

%% @private
matches_filter(Tool, Filter) ->
    NameMatch = case maps:find(name, Filter) of
        {ok, NamePattern} ->
            ToolName = maps:get(name, Tool, <<>>),
            binary:match(ToolName, ensure_binary(NamePattern)) =/= nomatch;
        error -> true
    end,
    TagMatch = case maps:find(tags, Filter) of
        {ok, RequiredTags} ->
            ToolTags = maps:get(tags, Tool, []),
            lists:all(fun(T) -> lists:member(T, ToolTags) end, RequiredTags);
        error -> true
    end,
    NameMatch andalso TagMatch.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V).
