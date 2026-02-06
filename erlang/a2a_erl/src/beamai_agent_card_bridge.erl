%%% @doc Bridge between a2a_agent_card and beamai_a2a_card
%%%
%%% gen_server that merges agent card data from the legacy a2a_agent_card
%%% gen_server and the beamai_a2a_card:generate/1 function. Uses
%%% beamai_a2a_card_cache for caching the generated beamai card.
-module(beamai_agent_card_bridge).
-behaviour(gen_server).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, get_unified_card/0, update/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    agent_config = #{} :: map(),
    cached_card :: map() | undefined
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Get a unified card merging legacy and beamai data.
-spec get_unified_card() -> {ok, map()}.
get_unified_card() ->
    gen_server:call(?MODULE, get_unified_card).

%% @doc Update the agent configuration, invalidating cached cards.
-spec update(map()) -> ok.
update(Config) ->
    gen_server:call(?MODULE, {update, Config}).

%%% gen_server callbacks

init([]) ->
    DefaultConfig = #{
        name => <<"A2A Erlang Agent">>,
        description => <<"Bridged A2A agent with beamai support">>,
        version => <<"0.2.0">>,
        url => get_base_url()
    },
    {ok, #state{agent_config = DefaultConfig}}.

handle_call(get_unified_card, _From, #state{cached_card = Cached} = State)
  when Cached =/= undefined ->
    {reply, {ok, Cached}, State};

handle_call(get_unified_card, _From, State) ->
    Card = build_unified_card(State#state.agent_config),
    {reply, {ok, Card}, State#state{cached_card = Card}};

handle_call({update, Config}, _From, State) ->
    MergedConfig = maps:merge(State#state.agent_config, Config),
    %% Invalidate beamai cache
    ?SAFE_EXEC(beamai_a2a_card_cache:invalidate(unified)),
    {reply, ok, State#state{agent_config = MergedConfig,
                            cached_card = undefined}};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% Internal

build_unified_card(AgentConfig) ->
    %% Fetch legacy card
    LegacyCard = ?SAFE_EXEC_DEFAULT(a2a_agent_card:get_card(), undefined),
    LegacyMap = case LegacyCard of
        undefined -> #{};
        Card -> record_to_map(Card)
    end,
    %% Generate beamai card
    BeamaiMap = case beamai_a2a_card:generate(AgentConfig) of
        {ok, BCard} ->
            ?SAFE_EXEC(beamai_a2a_card_cache:put(unified, BCard)),
            BCard;
        _ -> #{}
    end,
    %% Merge: beamai values override legacy, but keep legacy skills/capabilities
    Base = maps:merge(LegacyMap, BeamaiMap),
    MergedSkills = merge_skills(
        maps:get(skills, LegacyMap, []),
        maps:get(skills, BeamaiMap, [])),
    Base#{skills => MergedSkills}.

record_to_map(#agent_card{name = Name, description = Desc, version = Vsn,
                          capabilities = Caps, skills = Skills,
                          default_input_modes = In, default_output_modes = Out}) ->
    #{name => Name, description => Desc, version => Vsn,
      capabilities => caps_to_map(Caps),
      skills => [skill_to_map(S) || S <- Skills],
      default_input_modes => In, default_output_modes => Out};
record_to_map(_) -> #{}.

caps_to_map(#agent_capabilities{streaming = S, push_notifications = P}) ->
    #{streaming => S, push_notifications => P};
caps_to_map(_) -> #{}.

skill_to_map(#agent_skill{id = Id, name = Name, description = Desc,
                          tags = Tags}) ->
    #{id => Id, name => Name, description => Desc, tags => Tags};
skill_to_map(M) when is_map(M) -> M.

merge_skills(Legacy, Beamai) ->
    BeamaiIds = sets:from_list([maps:get(id, S, <<>>) || S <- Beamai]),
    Filtered = [S || S <- Legacy,
                     not sets:is_element(maps:get(id, S, <<>>), BeamaiIds)],
    Filtered ++ Beamai.

get_base_url() ->
    Host = application:get_env(a2a_erl, host, "localhost"),
    Port = application:get_env(a2a_erl, port, 8080),
    Scheme = application:get_env(a2a_erl, scheme, "http"),
    iolist_to_binary(io_lib:format("~s://~s:~p", [Scheme, Host, Port])).
