%%%-------------------------------------------------------------------
%%% @doc Bridge between YAWL workflow definitions and beamai graph engine.
%%% Uses graph:builder/0, graph:add_node/3, graph:add_edge/3,
%%% graph:add_conditional_edge/3, graph:set_entry/2, graph:compile/1,
%%% graph:run/2, graph:state/1.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_graph_bridge).
-behaviour(gen_server).

-export([start_link/0, start_link/1,
         from_yawl_definition/1, to_beamai_graph/1, execute_graph/2]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-include_lib("beamai_core/include/beamai_common.hrl").

-define(SERVER, ?MODULE).

-record(state, {
    graphs :: #{binary() => term()},
    executions :: #{binary() => pid()}
}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Convert YAWL definition to intermediate representation.
%% Expects #{tasks := [...], flows := [...], entry => binary()}.
-spec from_yawl_definition(map()) -> {ok, map()} | {error, term()}.
from_yawl_definition(#{tasks := Tasks, flows := Flows} = Def) ->
    Entry = maps:get(entry, Def, find_entry(Tasks)),
    Conditions = maps:get(conditions, Def, []),
    {ok, #{
        nodes => [#{id => maps:get(id, T),
                     handler => maps:get(handler, T, fun(S) -> S end)}
                  || T <- Tasks],
        edges => [#{from => maps:get(from, F), to => maps:get(to, F)}
                  || F <- Flows],
        conditional_edges => [#{from => maps:get(from, C),
                                router => maps:get(router, C)}
                              || C <- Conditions],
        entry => Entry
    }};
from_yawl_definition(_) -> {error, invalid_yawl_definition}.

%% @doc Compile intermediate representation into a beamai graph.
-spec to_beamai_graph(map()) -> {ok, term()} | {error, term()}.
to_beamai_graph(#{nodes := Nodes, edges := Edges, entry := Entry} = IR) ->
    CondEdges = maps:get(conditional_edges, IR, []),
    B0 = graph:builder(),
    B1 = lists:foldl(fun(#{id := Id, handler := H}, B) ->
        graph:add_node(B, binary_to_atom(Id, utf8), H)
    end, B0, Nodes),
    B2 = lists:foldl(fun(#{from := From, to := To}, B) ->
        graph:add_edge(B, binary_to_atom(From, utf8), binary_to_atom(To, utf8))
    end, B1, Edges),
    B3 = lists:foldl(fun(#{from := From, router := Router}, B) ->
        graph:add_conditional_edge(B, binary_to_atom(From, utf8), Router)
    end, B2, CondEdges),
    B4 = graph:set_entry(B3, binary_to_atom(Entry, utf8)),
    graph:compile(B4);
to_beamai_graph(_) -> {error, invalid_intermediate_representation}.

%% @doc Execute a compiled graph with given input data.
-spec execute_graph(term(), map()) -> {ok, term()} | {error, term()}.
execute_graph(Graph, InputData) ->
    try {ok, graph:run(Graph, graph:state(InputData))}
    catch Class:Reason -> {error, {Class, Reason}}
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(_Opts) ->
    {ok, #state{graphs = #{}, executions = #{}}}.

handle_call({compile, YawlDef}, _From, #state{graphs = G} = State) ->
    case from_yawl_definition(YawlDef) of
        {ok, IR} ->
            case to_beamai_graph(IR) of
                {ok, Graph} ->
                    Id = gen_id(),
                    {reply, {ok, Id, Graph}, State#state{graphs = G#{Id => Graph}}};
                {error, _} = Err -> {reply, Err, State}
            end;
        {error, _} = Err -> {reply, Err, State}
    end;
handle_call({execute, GraphId, Input}, _From, #state{graphs = G} = State) ->
    case maps:find(GraphId, G) of
        {ok, Graph} -> {reply, execute_graph(Graph, Input), State};
        error -> {reply, {error, graph_not_found}, State}
    end;
handle_call(_Request, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Info, S) -> {noreply, S}.
terminate(_Reason, _S) -> ok.
code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal
%%====================================================================

find_entry([#{id := Id} | _]) -> Id;
find_entry(_) -> <<"start">>.

gen_id() ->
    <<"graph_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>.
