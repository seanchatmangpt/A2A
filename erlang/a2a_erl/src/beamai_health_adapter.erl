%%% @doc Health checks for beamai components.
%%% Verifies kernel creation, memory subsystem, LLM config, and agent liveness.
-module(beamai_health_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

-export([start_link/0, check_all/0, check_kernel/0, check_memory/0,
         check_llm/0, check_agents/0, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {last_check :: map() | undefined, check_interval = 30000 :: pos_integer()}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
check_all()  -> gen_server:call(?MODULE, check_all, ?DEFAULT_TIMEOUT).
check_kernel() -> gen_server:call(?MODULE, check_kernel, ?DEFAULT_TIMEOUT).
check_memory() -> gen_server:call(?MODULE, check_memory, ?DEFAULT_TIMEOUT).
check_llm()    -> gen_server:call(?MODULE, check_llm, ?DEFAULT_TIMEOUT).
check_agents() -> gen_server:call(?MODULE, check_agents, ?DEFAULT_TIMEOUT).
status()       -> gen_server:call(?MODULE, status, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_health_adapter starting"),
    erlang:send_after(5000, self(), periodic_check),
    {ok, #state{}}.

handle_call(check_all, _From, State) ->
    Result = do_check_all(),
    {reply, Result, State#state{last_check = Result}};
handle_call(check_kernel, _From, State) ->
    {reply, do_check_kernel(), State};
handle_call(check_memory, _From, State) ->
    {reply, do_check_memory(), State};
handle_call(check_llm, _From, State) ->
    {reply, do_check_llm(), State};
handle_call(check_agents, _From, State) ->
    {reply, do_check_agents(), State};
handle_call(status, _From, #state{last_check = Last} = State) ->
    Report = case Last of undefined -> do_check_all(); M -> M end,
    AllOk = maps:fold(fun(_K, V, Acc) ->
        Acc andalso (V =:= ok orelse is_integer(V))
    end, true, maps:remove(timestamp, Report)),
    Status = case AllOk of true -> healthy; false -> degraded end,
    {reply, #{status => Status, checks => Report}, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(periodic_check, #state{check_interval = Interval} = State) ->
    Result = do_check_all(),
    erlang:send_after(Interval, self(), periodic_check),
    {noreply, State#state{last_check = Result}};
handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

%%% Internal

do_check_all() ->
    #{kernel => do_check_kernel(), memory => do_check_memory(),
      llm => do_check_llm(), agents => do_check_agents(),
      timestamp => erlang:system_time(millisecond)}.

do_check_kernel() ->
    try
        Kernel = #{name => <<"health_check">>, tools => []},
        case beamai_kernel:list_tools(Kernel) of
            L when is_list(L) -> ok;
            _ -> {error, unexpected_result}
        end
    catch C:R -> {error, {C, R}}
    end.

do_check_memory() ->
    try _Mem = beamai_memory:new(#{}), ok
    catch C:R -> {error, {C, R}}
    end.

do_check_llm() ->
    case application:get_env(beamai_core, llm_provider) of
        {ok, _} -> ok;
        undefined ->
            case os:getenv("BEAMAI_LLM_API_KEY") of
                false -> {error, no_llm_config};
                _ -> ok
            end
    end.

do_check_agents() ->
    try
        length([P || P <- erlang:processes(),
            case erlang:process_info(P, dictionary) of
                {dictionary, D} ->
                    proplists:get_value('$initial_call', D) =:= {beamai_agent, init, 1};
                _ -> false
            end])
    catch _:_ -> 0
    end.
