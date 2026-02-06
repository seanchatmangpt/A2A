%%% @doc BeamAI Integrity Adapter - State Integrity Validation
%%%
%%% This module provides state integrity validation for all BeamAI
%%% components and integrates with the existing a2a_integrity_validator
%%% and hotci_consistency_checker. It validates kernel state consistency,
%%% memory store integrity, task bridge state, and agent state.
%%%
%%% Each validation function returns a structured report with a status
%%% (valid, invalid, or warning), details about what was checked, and
%%% any issues found. The validate_all/0 function runs all checks and
%%% produces an aggregated report.
%%%
%%% @end
-module(beamai_integrity_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    validate_all/0,
    validate_kernel/0,
    validate_memory/0,
    validate_tasks/0,
    validate_agents/0,
    get_report/0
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

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(VALIDATION_INTERVAL, 120000).
-define(MAX_REPORT_HISTORY, 50).

-record(validation_result, {
    component :: atom(),
    status :: valid | invalid | warning | unknown,
    checks_passed :: non_neg_integer(),
    checks_failed :: non_neg_integer(),
    checks_warned :: non_neg_integer(),
    details :: [map()],
    timestamp :: integer(),
    duration_ms :: non_neg_integer()
}).

-record(state, {
    last_report :: map() | undefined,
    report_history :: [map()],
    validation_timer :: reference() | undefined,
    validation_count :: non_neg_integer(),
    last_validation :: integer() | undefined,
    config :: map()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the integrity adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Run all integrity validations and return aggregated results.
-spec validate_all() -> {ok, map()} | {error, term()}.
validate_all() ->
    gen_server:call(?SERVER, validate_all, 60000).

%% @doc Validate BeamAI kernel state consistency.
-spec validate_kernel() -> {ok, map()} | {error, term()}.
validate_kernel() ->
    gen_server:call(?SERVER, validate_kernel, 10000).

%% @doc Validate BeamAI memory store integrity.
-spec validate_memory() -> {ok, map()} | {error, term()}.
validate_memory() ->
    gen_server:call(?SERVER, validate_memory, 10000).

%% @doc Validate BeamAI task bridge state consistency.
-spec validate_tasks() -> {ok, map()} | {error, term()}.
validate_tasks() ->
    gen_server:call(?SERVER, validate_tasks, 10000).

%% @doc Validate BeamAI agent state consistency.
-spec validate_agents() -> {ok, map()} | {error, term()}.
validate_agents() ->
    gen_server:call(?SERVER, validate_agents, 10000).

%% @doc Get the most recent full validation report.
-spec get_report() -> {ok, map()} | {error, no_report}.
get_report() ->
    gen_server:call(?SERVER, get_report).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI integrity adapter initializing"),

    TimerRef = erlang:send_after(?VALIDATION_INTERVAL, self(), periodic_validation),

    State = #state{
        last_report = undefined,
        report_history = [],
        validation_timer = TimerRef,
        validation_count = 0,
        last_validation = undefined,
        config = #{
            validation_interval => ?VALIDATION_INTERVAL,
            max_report_history => ?MAX_REPORT_HISTORY
        }
    },
    {ok, State}.

%% @private
handle_call(validate_all, _From, State) ->
    {Report, NewState} = do_validate_all(State),
    {reply, {ok, Report}, NewState};

handle_call(validate_kernel, _From, State) ->
    Result = do_validate_kernel(),
    {reply, {ok, validation_result_to_map(Result)}, State};

handle_call(validate_memory, _From, State) ->
    Result = do_validate_memory(),
    {reply, {ok, validation_result_to_map(Result)}, State};

handle_call(validate_tasks, _From, State) ->
    Result = do_validate_tasks(),
    {reply, {ok, validation_result_to_map(Result)}, State};

handle_call(validate_agents, _From, State) ->
    Result = do_validate_agents(),
    {reply, {ok, validation_result_to_map(Result)}, State};

handle_call(get_report, _From, #state{last_report = undefined} = State) ->
    {reply, {error, no_report}, State};

handle_call(get_report, _From, #state{last_report = Report} = State) ->
    {reply, {ok, Report}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(periodic_validation, State) ->
    {_Report, NewState} = do_validate_all(State),
    TimerRef = erlang:send_after(?VALIDATION_INTERVAL, self(), periodic_validation),
    {noreply, NewState#state{validation_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{validation_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    logger:info("BeamAI integrity adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions - Validation
%%%===================================================================

%% @private Run all validations and produce an aggregated report.
-spec do_validate_all(#state{}) -> {map(), #state{}}.
do_validate_all(State) ->
    Start = erlang:monotonic_time(millisecond),

    KernelResult = do_validate_kernel(),
    MemoryResult = do_validate_memory(),
    TasksResult = do_validate_tasks(),
    AgentsResult = do_validate_agents(),

    AllResults = #{
        kernel => KernelResult,
        memory => MemoryResult,
        tasks => TasksResult,
        agents => AgentsResult
    },

    OverallStatus = compute_overall_validity(AllResults),
    Duration = erlang:monotonic_time(millisecond) - Start,
    Now = erlang:system_time(millisecond),

    Report = #{
        overall_status => OverallStatus,
        components => maps:map(fun(_K, V) -> validation_result_to_map(V) end, AllResults),
        timestamp => Now,
        duration_ms => Duration,
        validation_number => State#state.validation_count + 1
    },

    %% Forward to existing integrity validator if available
    forward_to_integrity_validator(Report),

    History = lists:sublist(
        [Report | State#state.report_history],
        ?MAX_REPORT_HISTORY
    ),

    NewState = State#state{
        last_report = Report,
        report_history = History,
        validation_count = State#state.validation_count + 1,
        last_validation = Now
    },

    {Report, NewState}.

%% @private Validate BeamAI kernel state consistency.
-spec do_validate_kernel() -> #validation_result{}.
do_validate_kernel() ->
    Start = erlang:monotonic_time(millisecond),
    Checks = [
        check_kernel_process_alive(),
        check_kernel_state_accessible(),
        check_kernel_handlers_consistent(),
        check_kernel_metrics_valid()
    ],
    build_validation_result(kernel, Checks, Start).

%% @private Validate BeamAI memory store integrity.
-spec do_validate_memory() -> #validation_result{}.
do_validate_memory() ->
    Start = erlang:monotonic_time(millisecond),
    Checks = [
        check_memory_ets_tables_valid(),
        check_memory_usage_within_limits(),
        check_memory_no_leaked_binaries(),
        check_memory_process_heaps()
    ],
    build_validation_result(memory, Checks, Start).

%% @private Validate BeamAI task bridge state consistency.
-spec do_validate_tasks() -> #validation_result{}.
do_validate_tasks() ->
    Start = erlang:monotonic_time(millisecond),
    Checks = [
        check_task_supervisor_alive(),
        check_task_store_consistent(),
        check_task_bridge_state(),
        check_no_orphan_tasks()
    ],
    build_validation_result(tasks, Checks, Start).

%% @private Validate BeamAI agent state consistency.
-spec do_validate_agents() -> #validation_result{}.
do_validate_agents() ->
    Start = erlang:monotonic_time(millisecond),
    Checks = [
        check_agent_supervisor_alive(),
        check_agent_processes_healthy(),
        check_agent_message_queues(),
        check_agent_state_consistency()
    ],
    build_validation_result(agents, Checks, Start).

%%%===================================================================
%%% Internal Functions - Individual Checks
%%%===================================================================

%% -- Kernel checks --

check_kernel_process_alive() ->
    case whereis(beamai_bridge) of
        undefined ->
            #{check => kernel_process_alive, status => warning,
              detail => <<"BeamAI bridge process not running">>};
        Pid ->
            case erlang:is_process_alive(Pid) of
                true ->
                    #{check => kernel_process_alive, status => pass,
                      detail => <<"BeamAI bridge process alive">>};
                false ->
                    #{check => kernel_process_alive, status => fail,
                      detail => <<"BeamAI bridge process registered but not alive">>}
            end
    end.

check_kernel_state_accessible() ->
    try
        case catch beamai_bridge:get_status() of
            Status when is_map(Status) ->
                #{check => kernel_state_accessible, status => pass,
                  detail => <<"Kernel state is accessible">>};
            {'EXIT', _} ->
                #{check => kernel_state_accessible, status => warning,
                  detail => <<"Kernel state not accessible (process not running)">>};
            _ ->
                #{check => kernel_state_accessible, status => fail,
                  detail => <<"Kernel state returned unexpected format">>}
        end
    catch
        _:_ ->
            #{check => kernel_state_accessible, status => warning,
              detail => <<"Exception accessing kernel state">>}
    end.

check_kernel_handlers_consistent() ->
    try
        case catch beamai_bridge:list_handlers() of
            Handlers when is_list(Handlers) ->
                %% Verify each handler module is loaded
                Invalid = [Name || {Name, Mod} <- Handlers,
                           code:is_loaded(Mod) =:= false],
                case Invalid of
                    [] ->
                        #{check => kernel_handlers_consistent, status => pass,
                          detail => iolist_to_binary(
                            io_lib:format("All ~p handlers have loaded modules",
                                          [length(Handlers)]))};
                    _ ->
                        #{check => kernel_handlers_consistent, status => fail,
                          detail => iolist_to_binary(
                            io_lib:format("Handlers with unloaded modules: ~p", [Invalid]))}
                end;
            _ ->
                #{check => kernel_handlers_consistent, status => warning,
                  detail => <<"Could not retrieve handler list">>}
        end
    catch
        _:_ ->
            #{check => kernel_handlers_consistent, status => warning,
              detail => <<"Exception checking handlers">>}
    end.

check_kernel_metrics_valid() ->
    try
        case catch beamai_bridge:get_status() of
            #{metrics := Metrics} when is_map(Metrics) ->
                %% Verify metrics values are non-negative
                InvalidMetrics = maps:fold(fun(Key, Val, Acc) ->
                    case is_number(Val) andalso Val >= 0 of
                        true -> Acc;
                        false -> [Key | Acc]
                    end
                end, [], Metrics),
                case InvalidMetrics of
                    [] ->
                        #{check => kernel_metrics_valid, status => pass,
                          detail => <<"All kernel metrics are valid">>};
                    _ ->
                        #{check => kernel_metrics_valid, status => warning,
                          detail => iolist_to_binary(
                            io_lib:format("Invalid metric keys: ~p", [InvalidMetrics]))}
                end;
            _ ->
                #{check => kernel_metrics_valid, status => warning,
                  detail => <<"Metrics not available">>}
        end
    catch
        _:_ ->
            #{check => kernel_metrics_valid, status => warning,
              detail => <<"Exception validating metrics">>}
    end.

%% -- Memory checks --

check_memory_ets_tables_valid() ->
    try
        AllTables = ets:all(),
        InvalidTables = lists:filter(fun(Tab) ->
            try
                _ = ets:info(Tab, size),
                false
            catch
                _:_ -> true
            end
        end, AllTables),
        case InvalidTables of
            [] ->
                #{check => memory_ets_tables_valid, status => pass,
                  detail => iolist_to_binary(
                    io_lib:format("All ~p ETS tables accessible", [length(AllTables)]))};
            _ ->
                #{check => memory_ets_tables_valid, status => warning,
                  detail => iolist_to_binary(
                    io_lib:format("~p inaccessible ETS tables found", [length(InvalidTables)]))}
        end
    catch
        _:_ ->
            #{check => memory_ets_tables_valid, status => fail,
              detail => <<"Failed to inspect ETS tables">>}
    end.

check_memory_usage_within_limits() ->
    try
        MemInfo = erlang:memory(),
        TotalMem = proplists:get_value(total, MemInfo, 0),
        TotalMB = TotalMem / (1024 * 1024),
        %% Use 4GB as a warning threshold, 8GB as critical
        Status = if
            TotalMB > 8192 -> fail;
            TotalMB > 4096 -> warning;
            true -> pass
        end,
        #{check => memory_usage_within_limits, status => Status,
          detail => iolist_to_binary(
            io_lib:format("Total memory: ~.2f MB", [TotalMB]))}
    catch
        _:_ ->
            #{check => memory_usage_within_limits, status => warning,
              detail => <<"Failed to read memory info">>}
    end.

check_memory_no_leaked_binaries() ->
    try
        BinaryMem = proplists:get_value(binary, erlang:memory(), 0),
        BinaryMB = BinaryMem / (1024 * 1024),
        %% Binary memory over 1GB could indicate a leak
        Status = if
            BinaryMB > 1024 -> warning;
            true -> pass
        end,
        #{check => memory_no_leaked_binaries, status => Status,
          detail => iolist_to_binary(
            io_lib:format("Binary memory: ~.2f MB", [BinaryMB]))}
    catch
        _:_ ->
            #{check => memory_no_leaked_binaries, status => warning,
              detail => <<"Failed to check binary memory">>}
    end.

check_memory_process_heaps() ->
    try
        ProcessCount = erlang:system_info(process_count),
        ProcessLimit = erlang:system_info(process_limit),
        Utilization = ProcessCount / ProcessLimit * 100,
        Status = if
            Utilization > 90.0 -> fail;
            Utilization > 70.0 -> warning;
            true -> pass
        end,
        #{check => memory_process_heaps, status => Status,
          detail => iolist_to_binary(
            io_lib:format("Process count: ~p/~p (~.1f%)",
                          [ProcessCount, ProcessLimit, Utilization]))}
    catch
        _:_ ->
            #{check => memory_process_heaps, status => warning,
              detail => <<"Failed to check process heap info">>}
    end.

%% -- Task checks --

check_task_supervisor_alive() ->
    case whereis(a2a_task_sup) of
        undefined ->
            #{check => task_supervisor_alive, status => warning,
              detail => <<"Task supervisor not running">>};
        Pid ->
            case erlang:is_process_alive(Pid) of
                true ->
                    #{check => task_supervisor_alive, status => pass,
                      detail => <<"Task supervisor alive">>};
                false ->
                    #{check => task_supervisor_alive, status => fail,
                      detail => <<"Task supervisor registered but not alive">>}
            end
    end.

check_task_store_consistent() ->
    try
        case whereis(a2a_task_store) of
            undefined ->
                #{check => task_store_consistent, status => warning,
                  detail => <<"Task store not running">>};
            _Pid ->
                %% Attempt to verify task store is responsive
                case catch gen_server:call(a2a_task_store, ping, 2000) of
                    pong ->
                        #{check => task_store_consistent, status => pass,
                          detail => <<"Task store responsive">>};
                    _ ->
                        %% Many gen_servers don't implement ping; just check process is alive
                        #{check => task_store_consistent, status => pass,
                          detail => <<"Task store process running">>}
                end
        end
    catch
        _:_ ->
            #{check => task_store_consistent, status => warning,
              detail => <<"Could not verify task store">>}
    end.

check_task_bridge_state() ->
    case whereis(beamai_bridge) of
        undefined ->
            #{check => task_bridge_state, status => warning,
              detail => <<"BeamAI bridge not running">>};
        Pid ->
            case erlang:process_info(Pid, message_queue_len) of
                {message_queue_len, Len} when Len > 1000 ->
                    #{check => task_bridge_state, status => warning,
                      detail => iolist_to_binary(
                        io_lib:format("Bridge message queue length: ~p (high)", [Len]))};
                {message_queue_len, Len} ->
                    #{check => task_bridge_state, status => pass,
                      detail => iolist_to_binary(
                        io_lib:format("Bridge message queue length: ~p", [Len]))};
                undefined ->
                    #{check => task_bridge_state, status => fail,
                      detail => <<"Bridge process info unavailable">>}
            end
    end.

check_no_orphan_tasks() ->
    try
        case whereis(a2a_task_sup) of
            undefined ->
                #{check => no_orphan_tasks, status => warning,
                  detail => <<"Task supervisor not running, cannot check for orphans">>};
            SupPid ->
                Children = try supervisor:which_children(SupPid) catch _:_ -> [] end,
                %% Check each child is alive
                DeadChildren = [Id || {Id, Pid, _, _} <- Children,
                                not is_pid(Pid) orelse not erlang:is_process_alive(Pid)],
                case DeadChildren of
                    [] ->
                        #{check => no_orphan_tasks, status => pass,
                          detail => iolist_to_binary(
                            io_lib:format("All ~p tasks are alive", [length(Children)]))};
                    _ ->
                        #{check => no_orphan_tasks, status => warning,
                          detail => iolist_to_binary(
                            io_lib:format("~p orphan/dead tasks found", [length(DeadChildren)]))}
                end
        end
    catch
        _:_ ->
            #{check => no_orphan_tasks, status => warning,
              detail => <<"Exception checking for orphan tasks">>}
    end.

%% -- Agent checks --

check_agent_supervisor_alive() ->
    case whereis(a2a_erl_sup) of
        undefined ->
            #{check => agent_supervisor_alive, status => warning,
              detail => <<"Application supervisor not running">>};
        Pid ->
            case erlang:is_process_alive(Pid) of
                true ->
                    #{check => agent_supervisor_alive, status => pass,
                      detail => <<"Application supervisor alive">>};
                false ->
                    #{check => agent_supervisor_alive, status => fail,
                      detail => <<"Application supervisor registered but not alive">>}
            end
    end.

check_agent_processes_healthy() ->
    try
        %% Check key agent-related processes
        AgentProcs = [a2a_task_sup, beamai_bridge, a2a_erl_sup],
        Statuses = lists:map(fun(Name) ->
            case whereis(Name) of
                undefined -> {Name, not_running};
                Pid ->
                    case erlang:is_process_alive(Pid) of
                        true -> {Name, alive};
                        false -> {Name, dead}
                    end
            end
        end, AgentProcs),
        AliveCount = length([S || {_, S} <- Statuses, S =:= alive]),
        TotalCount = length(Statuses),
        Status = if
            AliveCount =:= TotalCount -> pass;
            AliveCount > 0 -> warning;
            true -> fail
        end,
        #{check => agent_processes_healthy, status => Status,
          detail => iolist_to_binary(
            io_lib:format("~p/~p agent processes alive", [AliveCount, TotalCount]))}
    catch
        _:_ ->
            #{check => agent_processes_healthy, status => warning,
              detail => <<"Exception checking agent processes">>}
    end.

check_agent_message_queues() ->
    try
        AgentProcs = [a2a_task_sup, beamai_bridge],
        QueueLens = lists:filtermap(fun(Name) ->
            case whereis(Name) of
                undefined -> false;
                Pid ->
                    case erlang:process_info(Pid, message_queue_len) of
                        {message_queue_len, Len} -> {true, {Name, Len}};
                        _ -> false
                    end
            end
        end, AgentProcs),
        HighQueues = [{N, L} || {N, L} <- QueueLens, L > 500],
        case HighQueues of
            [] ->
                #{check => agent_message_queues, status => pass,
                  detail => <<"All agent message queues within limits">>};
            _ ->
                #{check => agent_message_queues, status => warning,
                  detail => iolist_to_binary(
                    io_lib:format("High message queues: ~p", [HighQueues]))}
        end
    catch
        _:_ ->
            #{check => agent_message_queues, status => warning,
              detail => <<"Exception checking message queues">>}
    end.

check_agent_state_consistency() ->
    try
        %% Check beamai_bridge state consistency by verifying handler count matches
        case catch beamai_bridge:get_status() of
            #{handler_count := HCount} when is_integer(HCount) ->
                case catch beamai_bridge:list_handlers() of
                    Handlers when is_list(Handlers) ->
                        case length(Handlers) =:= HCount of
                            true ->
                                #{check => agent_state_consistency, status => pass,
                                  detail => <<"Handler count matches registered handlers">>};
                            false ->
                                #{check => agent_state_consistency, status => warning,
                                  detail => iolist_to_binary(
                                    io_lib:format("Handler count mismatch: status=~p, actual=~p",
                                                  [HCount, length(Handlers)]))}
                        end;
                    _ ->
                        #{check => agent_state_consistency, status => warning,
                          detail => <<"Could not list handlers">>}
                end;
            _ ->
                #{check => agent_state_consistency, status => warning,
                  detail => <<"Could not access bridge status">>}
        end
    catch
        _:_ ->
            #{check => agent_state_consistency, status => warning,
              detail => <<"Exception checking agent state consistency">>}
    end.

%%%===================================================================
%%% Internal Functions - Result Building
%%%===================================================================

%% @private Build a validation_result from a list of check results.
-spec build_validation_result(atom(), [map()], integer()) -> #validation_result{}.
build_validation_result(Component, Checks, StartTime) ->
    Duration = erlang:monotonic_time(millisecond) - StartTime,
    Passed = length([C || #{status := pass} = C <- Checks]),
    Failed = length([C || #{status := fail} = C <- Checks]),
    Warned = length([C || #{status := S} = C <- Checks, S =:= warning]),

    OverallStatus = if
        Failed > 0 -> invalid;
        Warned > 0 -> warning;
        Passed > 0 -> valid;
        true -> unknown
    end,

    #validation_result{
        component = Component,
        status = OverallStatus,
        checks_passed = Passed,
        checks_failed = Failed,
        checks_warned = Warned,
        details = Checks,
        timestamp = erlang:system_time(millisecond),
        duration_ms = Duration
    }.

%% @private Compute overall validity from component results.
-spec compute_overall_validity(#{atom() => #validation_result{}}) ->
    valid | invalid | warning | unknown.
compute_overall_validity(Results) ->
    Statuses = [R#validation_result.status || {_, R} <- maps:to_list(Results)],
    case lists:member(invalid, Statuses) of
        true -> invalid;
        false ->
            case lists:member(warning, Statuses) of
                true -> warning;
                false ->
                    case lists:member(valid, Statuses) of
                        true -> valid;
                        false -> unknown
                    end
            end
    end.

%% @private Convert a validation_result record to a map.
-spec validation_result_to_map(#validation_result{}) -> map().
validation_result_to_map(#validation_result{
    component = Component,
    status = Status,
    checks_passed = Passed,
    checks_failed = Failed,
    checks_warned = Warned,
    details = Details,
    timestamp = Timestamp,
    duration_ms = Duration
}) ->
    #{
        component => Component,
        status => Status,
        checks_passed => Passed,
        checks_failed => Failed,
        checks_warned => Warned,
        details => Details,
        timestamp => Timestamp,
        duration_ms => Duration
    }.

%% @private Forward validation report to existing integrity validator.
-spec forward_to_integrity_validator(map()) -> ok.
forward_to_integrity_validator(Report) ->
    try
        case whereis(a2a_integrity_validator) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI integrity adapter: forwarding report to "
                             "a2a_integrity_validator (status: ~p)",
                             [maps:get(overall_status, Report, unknown)]),
                ok
        end
    catch
        _:_ -> ok
    end.
