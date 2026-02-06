%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent Card Bridge
%%%
%%% Bridges the existing a2a_agent_card module with the enhanced
%%% beamai_a2a_card module. Merges agent card data from both sources
%%% to provide a unified card that includes both A2A protocol
%%% capabilities and BeamAI-specific enhancements.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_card_bridge).

-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    get_unified_card/0,
    update/1,
    merge_capabilities/2,
    get_a2a_card/0,
    get_beamai_card/0,
    invalidate_cache/0
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
-define(CACHE_TTL_MS, 60000). %% 1 minute

-record(state, {
    unified_card    :: map() | undefined,
    cache_expires   :: integer(),
    config          :: map(),
    version         :: non_neg_integer()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the agent card bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the agent card bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Get the unified agent card that merges both A2A and BeamAI cards.
-spec get_unified_card() -> {ok, map()} | {error, term()}.
get_unified_card() ->
    gen_server:call(?SERVER, get_unified_card).

%% @doc Update the unified card with new data.
-spec update(map()) -> ok | {error, term()}.
update(Updates) ->
    gen_server:call(?SERVER, {update, Updates}).

%% @doc Merge capabilities from two sources (A2A and BeamAI).
%% This is a pure function that can be called without the server.
-spec merge_capabilities(map(), map()) -> map().
merge_capabilities(A2ACaps, BeamAICaps) ->
    %% Deep merge with BeamAI taking precedence for new fields
    %% but preserving A2A fields
    BaseMerge = maps:merge(A2ACaps, BeamAICaps),

    %% Merge extensions lists
    A2AExtensions = maps:get(<<"extensions">>, A2ACaps,
                       maps:get(extensions, A2ACaps, [])),
    BeamAIExtensions = maps:get(<<"extensions">>, BeamAICaps,
                          maps:get(extensions, BeamAICaps, [])),
    MergedExtensions = merge_extension_lists(A2AExtensions, BeamAIExtensions),

    BaseMerge#{<<"extensions">> => MergedExtensions}.

%% @doc Get the raw A2A agent card (from a2a_agent_card).
-spec get_a2a_card() -> {ok, map()} | {error, term()}.
get_a2a_card() ->
    gen_server:call(?SERVER, get_a2a_card).

%% @doc Get the raw BeamAI agent card (from beamai_a2a_card).
-spec get_beamai_card() -> {ok, map()} | {error, term()}.
get_beamai_card() ->
    gen_server:call(?SERVER, get_beamai_card).

%% @doc Invalidate the cached unified card.
-spec invalidate_cache() -> ok.
invalidate_cache() ->
    gen_server:cast(?SERVER, invalidate_cache).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    State = #state{
        unified_card = undefined,
        cache_expires = 0,
        config = Config,
        version = 0
    },
    logger:info("BeamAI agent card bridge started"),
    {ok, State}.

%% @private
handle_call(get_unified_card, _From, State) ->
    case ensure_cached(State) of
        {ok, Card, NewState} ->
            {reply, {ok, Card}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({update, Updates}, _From, State) ->
    %% Apply updates to both underlying card systems
    _ = try_update_a2a(Updates),
    _ = try_update_beamai(Updates),
    %% Invalidate cache so the next get rebuilds
    NewState = State#state{
        unified_card = undefined,
        cache_expires = 0,
        version = State#state.version + 1
    },
    {reply, ok, NewState};

handle_call(get_a2a_card, _From, State) ->
    Result = fetch_a2a_card(),
    {reply, Result, State};

handle_call(get_beamai_card, _From, State) ->
    Result = fetch_beamai_card(),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(invalidate_cache, State) ->
    {noreply, State#state{unified_card = undefined, cache_expires = 0}};

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

%% @private Ensure the cached unified card is valid.
-spec ensure_cached(#state{}) -> {ok, map(), #state{}} | {error, term()}.
ensure_cached(#state{unified_card = undefined} = State) ->
    rebuild_unified_card(State);
ensure_cached(#state{cache_expires = Expires} = State) ->
    Now = erlang:system_time(millisecond),
    case Now >= Expires of
        true -> rebuild_unified_card(State);
        false -> {ok, State#state.unified_card, State}
    end.

%% @private Rebuild the unified card from both sources.
-spec rebuild_unified_card(#state{}) -> {ok, map(), #state{}} | {error, term()}.
rebuild_unified_card(State) ->
    A2ACard = fetch_a2a_card(),
    BeamAICard = fetch_beamai_card(),

    UnifiedCard = case {A2ACard, BeamAICard} of
        {{ok, A2A}, {ok, BeamAI}} ->
            merge_cards(A2A, BeamAI);
        {{ok, A2A}, {error, _}} ->
            %% Only A2A card available
            enrich_with_beamai_defaults(A2A);
        {{error, _}, {ok, BeamAI}} ->
            %% Only BeamAI card available
            BeamAI;
        {{error, _}, {error, _}} ->
            %% Neither available, build default
            build_default_unified_card()
    end,

    Now = erlang:system_time(millisecond),
    NewState = State#state{
        unified_card = UnifiedCard,
        cache_expires = Now + ?CACHE_TTL_MS
    },
    {ok, UnifiedCard, NewState}.

%% @private Fetch the A2A agent card from the existing module.
-spec fetch_a2a_card() -> {ok, map()} | {error, term()}.
fetch_a2a_card() ->
    try
        case whereis(a2a_agent_card) of
            undefined -> {error, a2a_agent_card_not_running};
            _Pid ->
                Card = a2a_agent_card:get_card(),
                {ok, record_to_map(Card)}
        end
    catch
        _:Reason -> {error, {a2a_card_error, Reason}}
    end.

%% @private Fetch the BeamAI agent card from the enhanced module.
-spec fetch_beamai_card() -> {ok, map()} | {error, term()}.
fetch_beamai_card() ->
    try
        case whereis(beamai_a2a_card) of
            undefined -> {error, beamai_a2a_card_not_running};
            _Pid ->
                Card = beamai_a2a_card:get(map),
                {ok, Card}
        end
    catch
        _:Reason -> {error, {beamai_card_error, Reason}}
    end.

%% @private Merge two agent cards into a unified card.
-spec merge_cards(map(), map()) -> map().
merge_cards(A2ACard, BeamAICard) ->
    %% Start with A2A as base, overlay BeamAI enhancements
    BaseCard = #{
        <<"name">> => maps:get(<<"name">>, BeamAICard,
                        maps:get(name, A2ACard, <<"BeamAI A2A Agent">>)),
        <<"description">> => maps:get(<<"description">>, BeamAICard,
                                maps:get(description, A2ACard, <<>>)),
        <<"version">> => maps:get(<<"version">>, BeamAICard,
                            maps:get(version, A2ACard, <<"0.1.0">>))
    },

    %% Merge interfaces
    A2AInterfaces = maps:get(supported_interfaces, A2ACard, maps:get(<<"supportedInterfaces">>, A2ACard, [])),
    BeamAIInterfaces = maps:get(<<"supportedInterfaces">>, BeamAICard, []),
    MergedInterfaces = merge_interfaces(A2AInterfaces, BeamAIInterfaces),

    %% Merge capabilities
    A2ACaps = maps:get(capabilities, A2ACard, maps:get(<<"capabilities">>, A2ACard, #{})),
    BeamAICaps = maps:get(<<"capabilities">>, BeamAICard, #{}),
    MergedCaps = merge_capabilities(ensure_map(A2ACaps), ensure_map(BeamAICaps)),

    %% Merge skills
    A2ASkills = maps:get(skills, A2ACard, maps:get(<<"skills">>, A2ACard, [])),
    BeamAISkills = maps:get(<<"skills">>, BeamAICard, []),
    MergedSkills = merge_skills(A2ASkills, BeamAISkills),

    %% Merge input/output modes
    A2AInputModes = maps:get(default_input_modes, A2ACard,
                       maps:get(<<"defaultInputModes">>, A2ACard, [])),
    BeamAIInputModes = maps:get(<<"defaultInputModes">>, BeamAICard, []),
    A2AOutputModes = maps:get(default_output_modes, A2ACard,
                        maps:get(<<"defaultOutputModes">>, A2ACard, [])),
    BeamAIOutputModes = maps:get(<<"defaultOutputModes">>, BeamAICard, []),

    %% Provider info
    Provider = maps:get(<<"provider">>, BeamAICard,
                   ensure_map(maps:get(provider, A2ACard, maps:get(<<"provider">>, A2ACard, #{})))),

    BaseCard#{
        <<"supportedInterfaces">> => MergedInterfaces,
        <<"provider">> => Provider,
        <<"capabilities">> => MergedCaps,
        <<"defaultInputModes">> => lists:usort(A2AInputModes ++ BeamAIInputModes),
        <<"defaultOutputModes">> => lists:usort(A2AOutputModes ++ BeamAIOutputModes),
        <<"skills">> => MergedSkills,
        <<"securitySchemes">> => maps:get(<<"securitySchemes">>, BeamAICard,
                                     maps:get(security_schemes, A2ACard, #{})),
        <<"securityRequirements">> => maps:get(<<"securityRequirements">>, BeamAICard,
                                          maps:get(security_requirements, A2ACard, [])),
        <<"framework">> => #{
            <<"type">> => <<"beamai">>,
            <<"bridge">> => true,
            <<"a2a_compatible">> => true
        }
    }.

%% @private Enrich an A2A card with BeamAI default fields.
-spec enrich_with_beamai_defaults(map()) -> map().
enrich_with_beamai_defaults(A2ACard) ->
    A2ACard#{
        <<"framework">> => #{
            <<"type">> => <<"beamai">>,
            <<"bridge">> => true,
            <<"a2a_compatible">> => true
        }
    }.

%% @private Build a default unified card when neither source is available.
-spec build_default_unified_card() -> map().
build_default_unified_card() ->
    #{
        <<"name">> => <<"BeamAI A2A Agent">>,
        <<"description">> => <<"A unified BeamAI/A2A agent">>,
        <<"version">> => <<"0.1.0">>,
        <<"supportedInterfaces">> => [#{
            <<"url">> => build_default_url(),
            <<"protocolBinding">> => <<"JSONRPC">>,
            <<"protocolVersion">> => <<"0.4">>
        }],
        <<"capabilities">> => #{
            <<"streaming">> => true,
            <<"pushNotifications">> => true,
            <<"extendedAgentCard">> => true,
            <<"extensions">> => []
        },
        <<"defaultInputModes">> => [<<"text/plain">>, <<"application/json">>],
        <<"defaultOutputModes">> => [<<"text/plain">>, <<"application/json">>],
        <<"skills">> => [],
        <<"framework">> => #{
            <<"type">> => <<"beamai">>,
            <<"bridge">> => true,
            <<"a2a_compatible">> => true
        }
    }.

%% @private Merge interface lists, deduplicating by URL.
-spec merge_interfaces(list(), list()) -> list().
merge_interfaces(A2AInterfaces, BeamAIInterfaces) when is_list(A2AInterfaces), is_list(BeamAIInterfaces) ->
    %% Convert A2A interfaces to maps if they are records
    A2AMaps = lists:map(fun ensure_interface_map/1, A2AInterfaces),
    %% Merge by URL, preferring BeamAI versions
    AllInterfaces = A2AMaps ++ BeamAIInterfaces,
    deduplicate_by_key(AllInterfaces, <<"url">>);
merge_interfaces(_, BeamAI) when is_list(BeamAI) -> BeamAI;
merge_interfaces(A2A, _) when is_list(A2A) -> lists:map(fun ensure_interface_map/1, A2A);
merge_interfaces(_, _) -> [].

%% @private Merge skill lists, deduplicating by ID.
-spec merge_skills(list(), list()) -> list().
merge_skills(A2ASkills, BeamAISkills) when is_list(A2ASkills), is_list(BeamAISkills) ->
    A2AMaps = lists:map(fun ensure_skill_map/1, A2ASkills),
    AllSkills = A2AMaps ++ BeamAISkills,
    deduplicate_by_key(AllSkills, <<"id">>);
merge_skills(_, BeamAI) when is_list(BeamAI) -> BeamAI;
merge_skills(A2A, _) when is_list(A2A) -> lists:map(fun ensure_skill_map/1, A2A);
merge_skills(_, _) -> [].

%% @private Merge extension lists.
-spec merge_extension_lists(list(), list()) -> list().
merge_extension_lists(A, B) when is_list(A), is_list(B) ->
    lists:usort(A ++ B);
merge_extension_lists(_, B) when is_list(B) -> B;
merge_extension_lists(A, _) when is_list(A) -> A;
merge_extension_lists(_, _) -> [].

%% @private Deduplicate a list of maps by a key.
-spec deduplicate_by_key([map()], binary()) -> [map()].
deduplicate_by_key(List, Key) ->
    {_, Unique} = lists:foldl(fun(Item, {Seen, Acc}) ->
        case maps:find(Key, Item) of
            {ok, Val} ->
                case maps:is_key(Val, Seen) of
                    true -> {Seen, Acc}; %% Already seen, skip
                    false -> {maps:put(Val, true, Seen), Acc ++ [Item]}
                end;
            error ->
                {Seen, Acc ++ [Item]}
        end
    end, {#{}, []}, List),
    Unique.

%% @private Convert an agent_card record to a map.
-spec record_to_map(#agent_card{} | map()) -> map().
record_to_map(Card) when is_record(Card, agent_card) ->
    #{
        name => Card#agent_card.name,
        description => Card#agent_card.description,
        version => Card#agent_card.version,
        supported_interfaces => Card#agent_card.supported_interfaces,
        provider => Card#agent_card.provider,
        capabilities => Card#agent_card.capabilities,
        default_input_modes => Card#agent_card.default_input_modes,
        default_output_modes => Card#agent_card.default_output_modes,
        skills => Card#agent_card.skills,
        security_schemes => Card#agent_card.security_schemes,
        security_requirements => Card#agent_card.security_requirements
    };
record_to_map(Map) when is_map(Map) ->
    Map.

%% @private Ensure a term is a map.
-spec ensure_map(term()) -> map().
ensure_map(M) when is_map(M) -> M;
ensure_map(R) when is_record(R, agent_capabilities) ->
    #{
        <<"streaming">> => R#agent_capabilities.streaming,
        <<"pushNotifications">> => R#agent_capabilities.push_notifications,
        <<"extendedAgentCard">> => R#agent_capabilities.extended_agent_card,
        <<"extensions">> => R#agent_capabilities.extensions
    };
ensure_map(_) -> #{}.

%% @private Ensure an interface (record or map) is a map.
-spec ensure_interface_map(#agent_interface{} | map()) -> map().
ensure_interface_map(I) when is_record(I, agent_interface) ->
    #{
        <<"url">> => I#agent_interface.url,
        <<"protocolBinding">> => I#agent_interface.protocol_binding,
        <<"protocolVersion">> => I#agent_interface.protocol_version
    };
ensure_interface_map(M) when is_map(M) -> M;
ensure_interface_map(_) -> #{}.

%% @private Ensure a skill (record or map) is a map.
-spec ensure_skill_map(#agent_skill{} | map()) -> map().
ensure_skill_map(S) when is_record(S, agent_skill) ->
    #{
        <<"id">> => S#agent_skill.id,
        <<"name">> => S#agent_skill.name,
        <<"description">> => S#agent_skill.description,
        <<"tags">> => S#agent_skill.tags,
        <<"examples">> => S#agent_skill.examples
    };
ensure_skill_map(M) when is_map(M) -> M;
ensure_skill_map(_) -> #{}.

%% @private Try to update the A2A agent card.
-spec try_update_a2a(map()) -> ok | {error, term()}.
try_update_a2a(Updates) ->
    try
        case whereis(a2a_agent_card) of
            undefined -> {error, not_running};
            _Pid ->
                case maps:find(capabilities, Updates) of
                    {ok, Caps} -> a2a_agent_card:update_capabilities(Caps);
                    error -> ok
                end,
                case maps:find(skill, Updates) of
                    {ok, Skill} -> a2a_agent_card:add_skill(Skill);
                    error -> ok
                end,
                ok
        end
    catch
        _:Reason -> {error, Reason}
    end.

%% @private Try to update the BeamAI agent card.
-spec try_update_beamai(map()) -> ok | {error, term()}.
try_update_beamai(Updates) ->
    try
        case whereis(beamai_a2a_card) of
            undefined -> {error, not_running};
            _Pid ->
                maps:foreach(fun(Key, Value) ->
                    beamai_a2a_card:update(Key, Value)
                end, Updates),
                ok
        end
    catch
        _:Reason -> {error, Reason}
    end.

%% @private Build the default URL.
-spec build_default_url() -> binary().
build_default_url() ->
    Host = application:get_env(a2a_erl, host, "localhost"),
    Port = application:get_env(a2a_erl, port, 8080),
    Scheme = application:get_env(a2a_erl, scheme, "http"),
    iolist_to_binary(io_lib:format("~s://~s:~p", [Scheme, Host, Port])).
