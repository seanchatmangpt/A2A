%%% @doc HTTP route bridge between legacy and beamai handlers
%%%
%%% gen_server that manages route configuration, merging legacy
%%% a2a_http_handler routes with beamai_a2a_cowboy_handler routes.
%%% Routes POST requests through beamai_a2a_server:handle_json/2.
-module(beamai_http_bridge).
-behaviour(gen_server).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, configure_routes/1, get_routes/0, add_beamai_routes/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    legacy_routes = [] :: list(),
    beamai_routes = [] :: list(),
    merged_routes = [] :: list()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Replace the full route configuration.
-spec configure_routes(list()) -> ok.
configure_routes(Routes) ->
    gen_server:call(?MODULE, {configure_routes, Routes}).

%% @doc Get the current merged route table.
-spec get_routes() -> {ok, list()}.
get_routes() ->
    gen_server:call(?MODULE, get_routes).

%% @doc Add beamai-specific routes, merging with existing routes.
-spec add_beamai_routes(list()) -> ok.
add_beamai_routes(Routes) ->
    gen_server:call(?MODULE, {add_beamai_routes, Routes}).

%%% gen_server callbacks

init([]) ->
    Legacy = default_legacy_routes(),
    Beamai = default_beamai_routes(),
    Merged = merge_routes(Legacy, Beamai),
    {ok, #state{legacy_routes = Legacy,
                beamai_routes = Beamai,
                merged_routes = Merged}}.

handle_call({configure_routes, Routes}, _From, State) ->
    Merged = merge_routes(Routes, State#state.beamai_routes),
    {reply, ok, State#state{legacy_routes = Routes, merged_routes = Merged}};

handle_call(get_routes, _From, State) ->
    {reply, {ok, State#state.merged_routes}, State};

handle_call({add_beamai_routes, Routes}, _From, State) ->
    AllBeamai = Routes ++ State#state.beamai_routes,
    Merged = merge_routes(State#state.legacy_routes, AllBeamai),
    {reply, ok, State#state{beamai_routes = AllBeamai, merged_routes = Merged}};

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

default_legacy_routes() ->
    [{"/.well-known/agent-card.json", a2a_http_handler, []},
     {"/a2a", a2a_http_handler, []},
     {"/message:send", a2a_http_handler, []},
     {"/message:stream", a2a_sse_handler, []},
     {"/tasks/[...]", a2a_http_handler, []}].

default_beamai_routes() ->
    %% beamai routes use beamai_a2a_cowboy_handler which delegates
    %% POST to beamai_a2a_server:handle_json/2
    [{"/beamai/a2a", beamai_a2a_cowboy_handler, []},
     {"/beamai/agent-card", beamai_a2a_cowboy_handler, []},
     {"/beamai/tasks/[...]", beamai_a2a_cowboy_handler, []}].

merge_routes(Legacy, Beamai) ->
    %% Deduplicate by path (first element), beamai routes take precedence
    BeamaiPaths = sets:from_list([element(1, R) || R <- Beamai]),
    Filtered = [R || R <- Legacy,
                     not sets:is_element(element(1, R), BeamaiPaths)],
    Filtered ++ Beamai.
