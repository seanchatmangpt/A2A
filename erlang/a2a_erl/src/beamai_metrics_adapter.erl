%%% @doc Prometheus-compatible metrics collector for beamai components.
%%% Uses ETS counters for tool invocations, LLM calls, and memory operations.
-module(beamai_metrics_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, collect_all/0, increment/2, get_metric/1, to_prometheus/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(METRICS_TAB, beamai_metrics_counters).

-record(state, {
    created_at :: integer()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

collect_all() ->
    gen_server:call(?MODULE, collect_all, ?DEFAULT_TIMEOUT).

increment(Metric, Amount) when is_atom(Metric), is_integer(Amount) ->
    try ets:update_counter(?METRICS_TAB, Metric, Amount)
    catch error:badarg ->
        ets:insert(?METRICS_TAB, {Metric, Amount}),
        Amount
    end.

get_metric(Metric) ->
    try ets:lookup_element(?METRICS_TAB, Metric, 2)
    catch error:badarg -> 0
    end.

to_prometheus() ->
    gen_server:call(?MODULE, to_prometheus, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ets:new(?METRICS_TAB, [named_table, public, set, {write_concurrency, true}]),
    Seeds = [tool_invocations, llm_calls, memory_puts, memory_gets,
             task_creates, agent_messages, kernel_ops, errors],
    [ets:insert(?METRICS_TAB, {K, 0}) || K <- Seeds],
    ?LOG_INFO("beamai_metrics_adapter starting"),
    {ok, #state{created_at = erlang:system_time(millisecond)}}.

handle_call(collect_all, _From, State) ->
    All = ets:tab2list(?METRICS_TAB),
    Map = maps:from_list(All),
    %% Add live system metrics
    Enriched = Map#{
        process_count => erlang:system_info(process_count),
        memory_bytes => erlang:memory(total),
        uptime_ms => erlang:system_time(millisecond) - State#state.created_at
    },
    {reply, Enriched, State};

handle_call(to_prometheus, _From, State) ->
    All = ets:tab2list(?METRICS_TAB),
    Lines = lists:map(fun({Key, Val}) ->
        Name = atom_to_binary(Key),
        ValBin = integer_to_binary(Val),
        <<"# TYPE beamai_", Name/binary, " counter\n",
          "beamai_", Name/binary, " ", ValBin/binary, "\n">>
    end, All),
    %% Append gauges
    ProcCount = integer_to_binary(erlang:system_info(process_count)),
    MemBytes = integer_to_binary(erlang:memory(total)),
    Gauges = [<<"# TYPE beamai_process_count gauge\nbeamai_process_count ",
                ProcCount/binary, "\n">>,
              <<"# TYPE beamai_memory_bytes gauge\nbeamai_memory_bytes ",
                MemBytes/binary, "\n">>],
    {reply, iolist_to_binary(Lines ++ Gauges), State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    catch ets:delete(?METRICS_TAB),
    ok.
