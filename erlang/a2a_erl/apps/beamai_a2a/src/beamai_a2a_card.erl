%%%-------------------------------------------------------------------
%%% @doc BeamAI Enhanced Agent Card Module
%%%
%%% Provides enhanced agent card management with caching, dynamic
%%% updates, and RFC 8615 compliance (/.well-known/agent-card.json).
%%% Builds upon the existing a2a_agent_card module with TTL-based
%%% caching and configuration-driven card construction.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_card).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    get/1,
    build/1,
    invalidate/0,
    update/2,
    to_json/1
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
-define(DEFAULT_TTL_MS, 300000). %% 5 minutes
-define(WELL_KNOWN_PATH, <<"/.well-known/agent-card.json">>).

-record(state, {
    card            :: map(),
    config          :: map(),
    cached_json     :: binary() | undefined,
    cache_expires   :: integer(),
    ttl_ms          :: pos_integer(),
    version         :: non_neg_integer()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the agent card server with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the agent card server with the given configuration map.
%% Configuration keys:
%%   name, description, version, url, provider, capabilities,
%%   skills, input_modes, output_modes, ttl_ms, security_schemes
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Get the agent card. If `json' is passed, returns the cached
%% JSON binary. If `map' is passed, returns the card as a map.
%% If `path' is passed, returns the well-known path.
-spec get(json | map | path | config) -> term().
get(json) ->
    gen_server:call(?SERVER, get_json);
get(map) ->
    gen_server:call(?SERVER, get_map);
get(path) ->
    ?WELL_KNOWN_PATH;
get(config) ->
    gen_server:call(?SERVER, get_config).

%% @doc Build an agent card map from the given configuration.
%% This is a pure function that does not require the server to be running.
-spec build(map()) -> map().
build(Config) ->
    Name = maps:get(name, Config, <<"BeamAI Agent">>),
    Description = maps:get(description, Config, <<"A BeamAI-powered agent with A2A protocol support">>),
    Version = maps:get(version, Config, <<"0.1.0">>),
    Url = maps:get(url, Config, build_default_url()),
    Provider = maps:get(provider, Config, #{
        <<"organization">> => <<"BeamAI">>,
        <<"url">> => <<"https://github.com/beamai">>
    }),
    Capabilities = maps:get(capabilities, Config, #{
        <<"streaming">> => true,
        <<"pushNotifications">> => true,
        <<"extendedAgentCard">> => true,
        <<"extensions">> => []
    }),
    Skills = maps:get(skills, Config, [default_skill()]),
    InputModes = maps:get(input_modes, Config, [<<"text/plain">>, <<"application/json">>]),
    OutputModes = maps:get(output_modes, Config, [<<"text/plain">>, <<"application/json">>]),
    SecuritySchemes = maps:get(security_schemes, Config, #{}),
    SecurityReqs = maps:get(security_requirements, Config, []),

    Card = #{
        <<"name">> => ensure_binary(Name),
        <<"description">> => ensure_binary(Description),
        <<"version">> => ensure_binary(Version),
        <<"supportedInterfaces">> => [#{
            <<"url">> => ensure_binary(Url),
            <<"protocolBinding">> => <<"JSONRPC">>,
            <<"protocolVersion">> => <<"0.4">>
        }],
        <<"provider">> => Provider,
        <<"capabilities">> => Capabilities,
        <<"defaultInputModes">> => InputModes,
        <<"defaultOutputModes">> => OutputModes,
        <<"skills">> => Skills,
        <<"securitySchemes">> => SecuritySchemes,
        <<"securityRequirements">> => SecurityReqs
    },

    %% Add optional fields
    Card1 = case maps:find(documentation_url, Config) of
        {ok, DocUrl} -> Card#{<<"documentationUrl">> => ensure_binary(DocUrl)};
        error -> Card
    end,
    case maps:find(icon_url, Config) of
        {ok, IconUrl} -> Card1#{<<"iconUrl">> => ensure_binary(IconUrl)};
        error -> Card1
    end.

%% @doc Invalidate the cached agent card JSON, forcing a rebuild on
%% the next get/1 call.
-spec invalidate() -> ok.
invalidate() ->
    gen_server:cast(?SERVER, invalidate).

%% @doc Update specific fields of the agent card configuration.
%% The Key can be any valid configuration key; the card is rebuilt
%% after the update.
-spec update(atom(), term()) -> ok | {error, term()}.
update(Key, Value) ->
    gen_server:call(?SERVER, {update, Key, Value}).

%% @doc Convert an agent card map to a JSON binary string.
-spec to_json(map()) -> binary().
to_json(Card) when is_map(Card) ->
    jsx:encode(Card).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    TtlMs = maps:get(ttl_ms, Config, ?DEFAULT_TTL_MS),
    Card = build(Config),
    JsonBin = jsx:encode(Card),
    Now = erlang:system_time(millisecond),
    State = #state{
        card = Card,
        config = Config,
        cached_json = JsonBin,
        cache_expires = Now + TtlMs,
        ttl_ms = TtlMs,
        version = 1
    },
    logger:info("BeamAI agent card server started (TTL=~pms)", [TtlMs]),
    {ok, State}.

%% @private
handle_call(get_json, _From, State) ->
    {JsonBin, NewState} = ensure_cache(State),
    {reply, JsonBin, NewState};

handle_call(get_map, _From, State) ->
    {reply, State#state.card, State};

handle_call(get_config, _From, State) ->
    {reply, State#state.config, State};

handle_call({update, Key, Value}, _From, State) ->
    #state{config = Config, ttl_ms = TtlMs} = State,
    NewConfig = maps:put(Key, Value, Config),
    NewCard = build(NewConfig),
    NewJson = jsx:encode(NewCard),
    Now = erlang:system_time(millisecond),
    NewVersion = State#state.version + 1,
    NewState = State#state{
        card = NewCard,
        config = NewConfig,
        cached_json = NewJson,
        cache_expires = Now + TtlMs,
        version = NewVersion
    },
    logger:info("Agent card updated: ~p (version ~p)", [Key, NewVersion]),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(invalidate, State) ->
    NewState = State#state{
        cached_json = undefined,
        cache_expires = 0
    },
    logger:debug("Agent card cache invalidated"),
    {noreply, NewState};

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

%% @private Ensure the JSON cache is valid, rebuilding if expired.
-spec ensure_cache(#state{}) -> {binary(), #state{}}.
ensure_cache(#state{cached_json = undefined} = State) ->
    rebuild_cache(State);
ensure_cache(#state{cache_expires = Expires} = State) ->
    Now = erlang:system_time(millisecond),
    case Now >= Expires of
        true -> rebuild_cache(State);
        false -> {State#state.cached_json, State}
    end.

%% @private Rebuild the JSON cache from the current card.
-spec rebuild_cache(#state{}) -> {binary(), #state{}}.
rebuild_cache(#state{card = Card, ttl_ms = TtlMs} = State) ->
    JsonBin = jsx:encode(Card),
    Now = erlang:system_time(millisecond),
    NewState = State#state{
        cached_json = JsonBin,
        cache_expires = Now + TtlMs
    },
    {JsonBin, NewState}.

%% @private Build the default URL from application configuration.
-spec build_default_url() -> binary().
build_default_url() ->
    Host = application:get_env(a2a_erl, host, "localhost"),
    Port = application:get_env(a2a_erl, port, 8080),
    Scheme = application:get_env(a2a_erl, scheme, "http"),
    iolist_to_binary(io_lib:format("~s://~s:~p", [Scheme, Host, Port])).

%% @private Return the default echo skill definition.
-spec default_skill() -> map().
default_skill() ->
    #{
        <<"id">> => <<"beamai-echo">>,
        <<"name">> => <<"Echo">>,
        <<"description">> => <<"Echoes back the input message with BeamAI enhancements">>,
        <<"tags">> => [<<"utility">>, <<"test">>, <<"beamai">>],
        <<"examples">> => [<<"Echo hello world">>]
    }.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) when is_integer(V) -> integer_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
