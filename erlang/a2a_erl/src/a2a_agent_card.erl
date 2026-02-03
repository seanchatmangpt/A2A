%%% @doc A2A Agent Card Management
%%%
%%% This module manages the agent's "business card" - the AgentCard that
%%% describes the agent's capabilities, skills, and how to interact with it.
%%%
%%% The agent card is served at /.well-known/agent-card.json per RFC 8615.
-module(a2a_agent_card).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    get_card/0,
    get_extended_card/0,
    set_card/1,
    add_skill/1,
    remove_skill/1,
    update_capabilities/1
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

-record(state, {
    card :: agent_card(),
    extended_card :: agent_card() | undefined
}).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(default_card()).

-spec start_link(agent_card()) -> {ok, pid()} | {error, term()}.
start_link(Card) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Card, []).

%% @doc Get the public agent card
-spec get_card() -> agent_card().
get_card() ->
    gen_server:call(?MODULE, get_card).

%% @doc Get the extended agent card (for authenticated clients)
-spec get_extended_card() -> agent_card().
get_extended_card() ->
    gen_server:call(?MODULE, get_extended_card).

%% @doc Set the agent card
-spec set_card(agent_card()) -> ok.
set_card(Card) ->
    gen_server:call(?MODULE, {set_card, Card}).

%% @doc Add a skill to the agent
-spec add_skill(agent_skill()) -> ok.
add_skill(Skill) ->
    gen_server:call(?MODULE, {add_skill, Skill}).

%% @doc Remove a skill by ID
-spec remove_skill(binary()) -> ok.
remove_skill(SkillId) ->
    gen_server:call(?MODULE, {remove_skill, SkillId}).

%% @doc Update capabilities
-spec update_capabilities(agent_capabilities()) -> ok.
update_capabilities(Capabilities) ->
    gen_server:call(?MODULE, {update_capabilities, Capabilities}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

init(Card) ->
    {ok, #state{
        card = Card,
        extended_card = Card  % Default: same as public card
    }}.

handle_call(get_card, _From, State) ->
    {reply, State#state.card, State};

handle_call(get_extended_card, _From, State) ->
    Card = case State#state.extended_card of
        undefined -> State#state.card;
        ExtCard -> ExtCard
    end,
    {reply, Card, State};

handle_call({set_card, Card}, _From, State) ->
    {reply, ok, State#state{card = Card}};

handle_call({add_skill, Skill}, _From, State) ->
    Card = State#state.card,
    NewSkills = [Skill | Card#agent_card.skills],
    NewCard = Card#agent_card{skills = NewSkills},
    {reply, ok, State#state{card = NewCard}};

handle_call({remove_skill, SkillId}, _From, State) ->
    Card = State#state.card,
    NewSkills = lists:filter(
        fun(S) -> S#agent_skill.id =/= SkillId end,
        Card#agent_card.skills
    ),
    NewCard = Card#agent_card{skills = NewSkills},
    {reply, ok, State#state{card = NewCard}};

handle_call({update_capabilities, Capabilities}, _From, State) ->
    Card = State#state.card,
    NewCard = Card#agent_card{capabilities = Capabilities},
    {reply, ok, State#state{card = NewCard}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Create a default agent card
-spec default_card() -> agent_card().
default_card() ->
    #agent_card{
        name = <<"A2A Erlang Agent">>,
        description = <<"An A2A protocol agent implemented in Erlang/OTP using gen_statem">>,
        version = <<"0.1.0">>,
        supported_interfaces = [
            #agent_interface{
                url = get_base_url(),
                protocol_binding = <<"JSONRPC">>,
                protocol_version = <<"0.4">>
            }
        ],
        provider = #agent_provider{
            url = <<"https://github.com/a2aproject/a2a-erlang">>,
            organization = <<"A2A Project">>
        },
        capabilities = #agent_capabilities{
            streaming = true,
            push_notifications = true,
            extended_agent_card = true,
            extensions = []
        },
        default_input_modes = [
            <<"text/plain">>,
            <<"application/json">>
        ],
        default_output_modes = [
            <<"text/plain">>,
            <<"application/json">>
        ],
        skills = [
            #agent_skill{
                id = <<"echo">>,
                name = <<"Echo">>,
                description = <<"Echoes back the input message">>,
                tags = [<<"utility">>, <<"test">>],
                examples = [<<"Echo hello world">>]
            }
        ],
        security_schemes = #{},
        security_requirements = []
    }.

%% @doc Get the base URL from configuration
-spec get_base_url() -> binary().
get_base_url() ->
    Host = application:get_env(a2a_erl, host, "localhost"),
    Port = application:get_env(a2a_erl, port, 8080),
    Scheme = application:get_env(a2a_erl, scheme, "http"),
    iolist_to_binary(io_lib:format("~s://~s:~p", [Scheme, Host, Port])).
