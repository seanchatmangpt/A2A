%%% @doc State consistency validator for beamai components.
%%% Validates kernel map structure, memory accessibility, and task bridge consistency.
-module(beamai_integrity_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

-export([start_link/0, validate_all/0, validate_kernel/0,
         validate_memory/0, validate_tasks/0, get_report/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {last_report :: map() | undefined, violation_count = 0 :: non_neg_integer()}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
validate_all()    -> gen_server:call(?MODULE, validate_all, ?DEFAULT_TIMEOUT).
validate_kernel() -> gen_server:call(?MODULE, validate_kernel, ?DEFAULT_TIMEOUT).
validate_memory() -> gen_server:call(?MODULE, validate_memory, ?DEFAULT_TIMEOUT).
validate_tasks()  -> gen_server:call(?MODULE, validate_tasks, ?DEFAULT_TIMEOUT).
get_report()      -> gen_server:call(?MODULE, get_report, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_integrity_adapter starting"),
    {ok, #state{}}.

handle_call(validate_all, _From, State) ->
    KR = do_validate_kernel(),
    MR = do_validate_memory(),
    TR = do_validate_tasks(),
    Report = #{kernel => KR, memory => MR, tasks => TR,
               timestamp => erlang:system_time(millisecond)},
    Violations = count_violations(Report),
    NewState = State#state{last_report = Report,
                           violation_count = State#state.violation_count + Violations},
    Overall = case Violations of 0 -> valid; _ -> {invalid, Violations} end,
    {reply, {Overall, Report}, NewState};
handle_call(validate_kernel, _From, State) ->
    {reply, do_validate_kernel(), State};
handle_call(validate_memory, _From, State) ->
    {reply, do_validate_memory(), State};
handle_call(validate_tasks, _From, State) ->
    {reply, do_validate_tasks(), State};
handle_call(get_report, _From, #state{last_report = LR, violation_count = VC} = State) ->
    {reply, #{last_report => LR, total_violations => VC}, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

%%% Internal

do_validate_kernel() ->
    try
        Kernel = #{name => <<"integrity_check">>, tools => []},
        case beamai_kernel:list_tools(Kernel) of
            L when is_list(L) -> ok;
            _ -> {error, tools_not_list}
        end
    catch C:R -> {error, {C, R}}
    end.

do_validate_memory() ->
    try
        Mem = beamai_memory:new(#{}),
        _ = beamai_memory:get_latest_snapshot(Mem, #{}),
        _ = beamai_memory:get_latest_checkpoint(Mem, #{}),
        ok
    catch C:R -> {error, {C, R}}
    end.

do_validate_tasks() ->
    try
        case whereis(beamai_task_bridge) of
            undefined -> {error, bridge_not_running};
            Pid when is_pid(Pid) ->
                case is_process_alive(Pid) of
                    true -> ok;
                    false -> {error, bridge_dead}
                end
        end
    catch C:R -> {error, {C, R}}
    end.

count_violations(Report) ->
    maps:fold(fun
        (timestamp, _V, Acc) -> Acc;
        (_K, ok, Acc) -> Acc;
        (_K, _, Acc) -> Acc + 1
    end, 0, Report).
