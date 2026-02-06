%%% @doc Performance benchmark adapter for beamai components.
%%% Measures tool invocation latency, memory put/get, and LLM config lookup times.
-module(beamai_benchmark_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

-export([start_link/0, run_all/0, run_tool_benchmark/0,
         run_llm_benchmark/0, run_memory_benchmark/0, get_report/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {results = #{} :: map(), last_run :: integer() | undefined}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
run_all()    -> gen_server:call(?MODULE, run_all, ?DEFAULT_TIMEOUT).
run_tool_benchmark()   -> gen_server:call(?MODULE, run_tool_benchmark, ?DEFAULT_TIMEOUT).
run_llm_benchmark()    -> gen_server:call(?MODULE, run_llm_benchmark, ?DEFAULT_TIMEOUT).
run_memory_benchmark() -> gen_server:call(?MODULE, run_memory_benchmark, ?DEFAULT_TIMEOUT).
get_report() -> gen_server:call(?MODULE, get_report, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_benchmark_adapter starting"),
    {ok, #state{}}.

handle_call(run_all, _From, State) ->
    Now = erlang:system_time(millisecond),
    Results = #{tool => do_tool_benchmark(), memory => do_memory_benchmark(),
                llm => do_llm_benchmark(), timestamp => Now},
    {reply, Results, State#state{results = Results, last_run = Now}};
handle_call(run_tool_benchmark, _From, State) ->
    R = do_tool_benchmark(),
    {reply, R, State#state{results = (State#state.results)#{tool => R}}};
handle_call(run_llm_benchmark, _From, State) ->
    R = do_llm_benchmark(),
    {reply, R, State#state{results = (State#state.results)#{llm => R}}};
handle_call(run_memory_benchmark, _From, State) ->
    R = do_memory_benchmark(),
    {reply, R, State#state{results = (State#state.results)#{memory => R}}};
handle_call(get_report, _From, #state{results = R, last_run = LR} = State) ->
    {reply, #{results => R, last_run => LR}, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

%%% Internal

do_tool_benchmark() ->
    N = 100,
    Kernel = #{name => <<"bench">>, tools => [#{name => <<"echo">>}]},
    try
        {TimeUs, _} = timer:tc(fun() ->
            [beamai_kernel:list_tools(Kernel) || _ <- lists:seq(1, N)]
        end),
        #{iterations => N, total_us => TimeUs, avg_us => TimeUs div N, status => ok}
    catch C:R -> #{iterations => 0, status => {error, {C, R}}}
    end.

do_memory_benchmark() ->
    N = 50,
    try
        Mem = beamai_memory:new(#{}),
        {TimeUs, _} = timer:tc(fun() ->
            [begin
                 beamai_memory:get_latest_snapshot(Mem, #{}),
                 beamai_memory:get_latest_checkpoint(Mem, #{})
             end || _ <- lists:seq(1, N)]
        end),
        #{iterations => N, total_us => TimeUs, avg_us => TimeUs div N, status => ok}
    catch C:R -> #{iterations => 0, status => {error, {C, R}}}
    end.

do_llm_benchmark() ->
    N = 100,
    try
        {TimeUs, _} = timer:tc(fun() ->
            [application:get_env(beamai_core, llm_provider) || _ <- lists:seq(1, N)]
        end),
        #{iterations => N, total_us => TimeUs, avg_us => TimeUs div N,
          status => ok, note => config_lookup_only}
    catch C:R -> #{iterations => 0, status => {error, {C, R}}}
    end.
