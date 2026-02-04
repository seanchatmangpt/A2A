%%====================================================================
%% Module: ggen_metrics_collector
%% Description: Collect and report metrics for code generation
%%====================================================================

-module(ggen_metrics_collector).
-behaviour(gen_server).

-export([
    start_link/0, get_metrics/0,
    increment_metric/2, set_metric/2,
    track_generation_start/0, track_generation_end/1,
    track_ontology_processed/0, track_template_rendered/0,
    track_sparql_executed/0, track_error/1
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    metrics :: map(),
    start_time :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_metrics() -> map().
get_metrics() ->
    gen_server:call(?MODULE, get_metrics).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

-spec init(Args :: term()) -> {ok, term()} | {stop, term()}.
init(_Args) ->
    State = #state{
        metrics = #{
            files_generated => 0,
            generation_time => 0,
            errors => 0,
            ontologies_processed => 0,
            templates_rendered => 0,
            sparql_queries_executed => 0
        },
        start_time = erlang:system_time(millisecond)
    },

    {ok, State}.

-spec handle_call(Request :: term(), From :: term(), State :: term()) ->
    {reply, term(), term()} | {noreply, term()} | {stop, term(), term()}.
handle_call(get_metrics, _From, State) ->
    Metrics = State#state.metrics,
    Reply = #{
        metrics => Metrics,
        uptime => erlang:system_time(millisecond) - State#state.start_time,
        timestamp => erlang:system_time(millisecond)
    },
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(Msg :: term(), State :: term()) -> {noreply, term()} | {stop, term(), term()}.
handle_cast({increment_metric, Metric, Value}, #state{metrics = Metrics} = State) ->
    NewMetrics = maps:update(Metric, maps:get(Metric, Metrics, 0) + Value, Metrics),
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({set_metric, Metric, Value}, #state{metrics = Metrics} = State) ->
    NewMetrics = maps:put(Metric, Value, Metrics),
    {noreply, State#state{metrics = NewMetrics}};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(Info :: term(), State :: term()) -> {noreply, term()} | {stop, term(), term()}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(Reason :: term(), State :: term()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(OldVsn :: term(), State :: term(), Extra :: term()) -> {ok, term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Metric Helper Functions
%%====================================================================

-spec increment_metric(Metric :: atom(), Value :: integer()) -> ok.
increment_metric(Metric, Value) ->
    gen_server:cast(?MODULE, {increment_metric, Metric, Value}).

-spec set_metric(Metric :: atom(), Value :: integer()) -> ok.
set_metric(Metric, Value) ->
    gen_server:cast(?MODULE, {set_metric, Metric, Value}).

%%====================================================================
%% Event Tracking
%%====================================================================

-spec track_generation_start() -> ok.
track_generation_start() ->
    increment_metric(files_generated, 1).

-spec track_generation_end(Time :: integer()) -> ok.
track_generation_end(Time) ->
    increment_metric(generation_time, Time).

-spec track_ontology_processed() -> ok.
track_ontology_processed() ->
    increment_metric(ontologies_processed, 1).

-spec track_template_rendered() -> ok.
track_template_rendered() ->
    increment_metric(templates_rendered, 1).

-spec track_sparql_executed() -> ok.
track_sparql_executed() ->
    increment_metric(sparql_queries_executed, 1).

-spec track_error(Error :: term()) -> ok.
track_error(Error) ->
    increment_metric(errors, 1),
    io:format("❌ Generation error: ~p~n", [Error]).