%%%-------------------------------------------------------------------
%%% @doc BeamAI Tool definition and registration.
%%% Handles creation, validation, execution, and serialization
%%% of tool definitions used by the BeamAI kernel.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tool).

-export([
    new/2,
    new/3,
    execute/3,
    to_llm_format/1,
    matches_filter/2,
    validate/1
]).

-type tool_def() :: #{
    name := binary(),
    function := fun(),
    description => binary(),
    parameters => map(),
    tags => [binary()],
    metadata => map()
}.

-export_type([tool_def/0]).

%%--------------------------------------------------------------------
%% @doc Create a new tool definition with name and function.
%% @end
%%--------------------------------------------------------------------
-spec new(binary() | atom(), fun()) -> tool_def().
new(Name, Fun) ->
    new(Name, Fun, #{}).

%%--------------------------------------------------------------------
%% @doc Create a new tool definition with name, function, and options.
%% Options may include: description, parameters, tags, metadata.
%% @end
%%--------------------------------------------------------------------
-spec new(binary() | atom(), fun(), map()) -> tool_def().
new(Name, Fun, Opts) ->
    NameBin = ensure_binary(Name),
    BaseDef = #{
        name => NameBin,
        function => Fun,
        description => maps:get(description, Opts, <<"">>),
        parameters => maps:get(parameters, Opts, #{}),
        tags => maps:get(tags, Opts, []),
        metadata => maps:get(metadata, Opts, #{})
    },
    BaseDef.

%%--------------------------------------------------------------------
%% @doc Execute a tool with the given arguments and context.
%% The tool function is called as Fun(Args, Context).
%% @end
%%--------------------------------------------------------------------
-spec execute(tool_def(), map(), map()) -> {ok, term()} | {error, term()}.
execute(#{function := Fun}, Args, Context) ->
    try
        case erlang:fun_info(Fun, arity) of
            {arity, 2} ->
                Result = Fun(Args, Context),
                {ok, Result};
            {arity, 1} ->
                Result = Fun(Args),
                {ok, Result};
            {arity, 0} ->
                Result = Fun(),
                {ok, Result};
            _ ->
                {error, {invalid_tool_arity, Fun}}
        end
    catch
        Class:Reason:Stacktrace ->
            logger:error("Tool execution failed: ~p:~p~n~p",
                         [Class, Reason, Stacktrace]),
            {error, {tool_execution_failed, Class, Reason}}
    end;
execute(_InvalidTool, _Args, _Context) ->
    {error, invalid_tool_definition}.

%%--------------------------------------------------------------------
%% @doc Convert a tool definition to LLM-compatible format.
%% Returns a map suitable for including in API requests to LLM providers.
%% @end
%%--------------------------------------------------------------------
-spec to_llm_format(tool_def()) -> map().
to_llm_format(#{name := Name, description := Desc, parameters := Params}) ->
    #{
        <<"type">> => <<"function">>,
        <<"function">> => #{
            <<"name">> => Name,
            <<"description">> => Desc,
            <<"parameters">> => params_to_json_schema(Params)
        }
    };
to_llm_format(#{name := Name}) ->
    #{
        <<"type">> => <<"function">>,
        <<"function">> => #{
            <<"name">> => Name,
            <<"description">> => <<"">>,
            <<"parameters">> => #{<<"type">> => <<"object">>, <<"properties">> => #{}}
        }
    }.

%%--------------------------------------------------------------------
%% @doc Check if a tool matches the given filter criteria.
%% Filter is a map with optional keys: name, tags, metadata.
%% @end
%%--------------------------------------------------------------------
-spec matches_filter(tool_def(), map()) -> boolean().
matches_filter(ToolDef, Filter) ->
    NameMatch = case maps:find(name, Filter) of
        {ok, NamePattern} ->
            ToolName = maps:get(name, ToolDef, <<"">>),
            binary:match(ToolName, NamePattern) =/= nomatch;
        error ->
            true
    end,
    TagMatch = case maps:find(tags, Filter) of
        {ok, RequiredTags} ->
            ToolTags = maps:get(tags, ToolDef, []),
            lists:all(fun(T) -> lists:member(T, ToolTags) end, RequiredTags);
        error ->
            true
    end,
    NameMatch andalso TagMatch.

%%--------------------------------------------------------------------
%% @doc Validate a tool definition.
%% @end
%%--------------------------------------------------------------------
-spec validate(tool_def()) -> ok | {error, term()}.
validate(#{name := Name, function := Fun}) when is_binary(Name), is_function(Fun) ->
    ok;
validate(#{name := _Name}) ->
    {error, missing_function};
validate(_) ->
    {error, missing_name}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
-spec params_to_json_schema(map()) -> map().
params_to_json_schema(Params) when map_size(Params) =:= 0 ->
    #{<<"type">> => <<"object">>, <<"properties">> => #{}};
params_to_json_schema(Params) ->
    %% If already in JSON schema format, pass through
    case maps:is_key(<<"type">>, Params) of
        true -> Params;
        false ->
            %% Convert simple param map to JSON schema
            Properties = maps:fold(
                fun(K, V, Acc) ->
                    Acc#{ensure_binary(K) => param_to_schema(V)}
                end,
                #{},
                Params
            ),
            #{<<"type">> => <<"object">>, <<"properties">> => Properties}
    end.

%% @private
-spec param_to_schema(term()) -> map().
param_to_schema(string) ->
    #{<<"type">> => <<"string">>};
param_to_schema(integer) ->
    #{<<"type">> => <<"integer">>};
param_to_schema(number) ->
    #{<<"type">> => <<"number">>};
param_to_schema(boolean) ->
    #{<<"type">> => <<"boolean">>};
param_to_schema(M) when is_map(M) ->
    M;
param_to_schema(_) ->
    #{<<"type">> => <<"string">>}.

%% @private
-spec ensure_binary(atom() | binary() | list()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V).
