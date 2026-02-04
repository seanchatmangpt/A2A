%%% @doc Craftplan Agent Card Module
%%% Manages agent discovery and capability metadata

-module(craftplan_agent_card).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([get_card/0, get_skills/0, get_endpoints/0]).
-export([update_card/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(AGENT_CARD_FILE, filename:join([
    code:priv_dir(craftplan_a2a), "agent-card.json"
])).

-record(state, {
    card :: map(),
    file_path :: string()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Get the agent card
-spec get_card() -> {ok, map()}.
get_card() ->
    gen_server:call(?SERVER, get_card).

%% @doc Get agent skills
-spec get_skills() -> {ok, [map()]}.
get_skills() ->
    gen_server:call(?SERVER, get_skills).

%% @doc Get agent endpoints
-spec get_endpoints() -> {ok, map()}.
get_endpoints() ->
    gen_server:call(?SERVER, get_endpoints).

%% @doc Update the agent card
-spec update_card(map()) -> ok | {error, term()}.
update_card(Updates) ->
    gen_server:call(?SERVER, {update_card, Updates}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    %% Load agent card from file or use default
    CardPath = application:get_env(craftplan_a2a, agent_card_file, ?AGENT_CARD_FILE),

    Card = case file:read_file(CardPath) of
        {ok, Content} ->
            jiffy:decode(Content, [return_maps]);
        {error, enoent} ->
            io:format("Agent card file not found, using default~n"),
            default_agent_card();
        {error, Reason} ->
            io:format("Error reading agent card: ~p, using default~n", [Reason]),
            default_agent_card()
    end,

    State = #state{
        card = Card,
        file_path = CardPath
    },

    io:format("Craftplan Agent Card initialized~n"),
    io:format("Agent: ~s~n", [maps:get(<<"name">>, Card)]),
    io:format("Capabilities: ~p~n", [length(maps:get(<<"skills">>, maps_get([<<"capabilities">>], Card, #{})))]),

    {ok, State}.

handle_call(get_card, _From, State) ->
    {reply, {ok, State#state.card}, State};

handle_call(get_skills, _From, State) ->
    Skills = maps_get([<<"capabilities">>, <<"skills">>], State#state.card, []),
    {reply, {ok, Skills}, State};

handle_call(get_endpoints, _From, State) ->
    Endpoints = maps_get([<<"endpoints">>], State#state.card, #{}),
    {reply, {ok, Endpoints}, State};

handle_call({update_card, Updates}, _From, State) ->
    NewCard = maps:merge(State#state.card, Updates),

    %% Persist to file
    case file:write_file(State#state.file_path, jiffy:encode(NewCard, [pretty])) of
        ok ->
            io:format("Agent card updated: ~p~n", [State#state.file_path]),
            {reply, ok, State#state{card = NewCard}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% Default agent card
default_agent_card() -> #{
    <<"agent_id">> => <<"craftplan-erp-agent">>,
    <<"name">> => <<"Craftplan ERP Agent">>,
    <<"version">> => <<"1.0.0">>,
    <<"description">> => <<"Self-hosted ERP agent for artisanal D2C micro-businesses">>,
    <<"capabilities">> => #{
        <<"skills">> => [
            #{
                <<"id">> => <<"customer_management">>,
                <<"name">> => <<"Customer Management">>,
                <<"description">> => <<"Create, read, update, and delete customer records">>
            },
            #{
                <<"id">> => <<"order_management">>,
                <<"name">> => <<"Order Management">>,
                <<"description">> => <<"Create, update, process, and manage orders">>
            },
            #{
                <<"id">> => <<"inventory_management">>,
                <<"name">> => <<"Inventory Management">>,
                <<"description">> => <<"Manage products, inventory levels, and stock movements">>
            },
            #{
                <<"id">> => <<"production_planning">>,
                <<"name">> => <<"Production Planning">>,
                <<"description">> => <<"Plan and track production orders, schedules, and work orders">>
            },
            #{
                <<"id">> => <<"analytics">>,
                <<"name">> => <<"Business Analytics">>,
                <<"description">> => <<"Generate sales, inventory, and production reports">>
            },
            #{
                <<"id">> => <<"shipping">>,
                <<"name">> => <<"Shipping & Fulfillment">>,
                <<"description">> => <<"Process shipments, track packages, manage carriers">>
            }
        ]
    },
    <<"endpoints">> => #{
        <<"a2a">> => #{
            <<"url">> => <<"http://craftplan-a2a-agent:8080/a2a">>,
            <<"protocol">> => <<"jsonrpc">>,
            <<"version">> => <<"1.0.0">>
        },
        <<"mcp">> => #{
            <<"url">> => <<"http://craftplan-mcp-server:8090/mcp">>,
            <<"protocol">> => <<"jsonrpc">>,
            <<"version">> => <<"2024-11-05">>
        },
        <<"sse">> => #{
            <<"url">> => <<"http://craftplan-a2a-agent:8080/sse">>,
            <<"events">> => [<<"task_update">>, <<"message">>, <<"notification">>]
        },
        <<"health">> => #{
            <<"url">> => <<"http://craftplan-a2a-agent:8080/health">>
        }
    },
    <<"authentication">> => #{
        <<"type">> => <<"bearer">>,
        <<"token_endpoint">> => <<"http://craftplan-a2a-agent:8080/auth/token">>
    },
    <<"orchestrator">> => #{
        <<"supported">> => true,
        <<"delegation">> => true,
        <<"long_running">> => true,
        <<"streaming">> => true
    },
    <<"metadata">> => #{
        <<"category">> => <<"erp">>,
        <<"tags">> => [<<"erp">>, <<"ecommerce">>, <<"manufacturing">>, <<"inventory">>],
        <<"website">> => <<"https://github.com/puemos/craftplan">>,
        <<"pricing">> => <<"open_source">>
    }
}.

%% Safe nested map get
maps_get([], _Map, Default) -> Default;
maps_get([Key | Rest], Map, Default) ->
    case maps:get(Key, Map, undefined) of
        undefined -> Default;
        Value -> maps_get(Rest, Value, Default)
    end.
