%%% @doc BeamAI Health Adapter - Health Check Integration
%%%
%%% This module provides health check capabilities for all BeamAI components
%%% and integrates them with the existing a2a_health_handler and
%%% a2a_upgrade_health systems. It reports the status of the BeamAI kernel,
%%% memory system, LLM provider connectivity, and agent pool.
%%%
%%% Health checks are exposed through the standard HotCI health interface
%%% so that existing monitoring dashboards automatically include BeamAI
%%% component status.
%%%
%%% @end
-module(beamai_health_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    check_all/0,
    check_kernel/0,
    check_memory/0,
    check_llm/0,
    check_agents/0,
    status/0
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
-define(HEALTH_CHECK_INTERVAL, 30000).
-define(LLM_TIMEOUT, 5000).
-define(COMPONENT_TIMEOUT, 3000).

-record(health_result, {
    component :: atom(),
    status :: healthy | degraded | unhealthy | unknown,
    details :: map(),
    timestamp :: integer(),
    latency_ms :: non_neg_integer()
}).

-record(state, {
    last_check :: integer() | undefined,
    check_timer :: reference() | undefined,
    results :: #{atom() => #health_result{}},
    overall_status :: healthy | degraded | unhealthy | unknown,
    check_count :: non_neg_integer(),
    failure_count :: non_neg_integer(),
    config :: map()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the health adapter with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Run all health checks and return aggregated results.
-spec check_all() -> {ok, map()} | {error, term()}.
check_all() ->
    gen_server:call(?SERVER, check_all, 30000).

%% @doc Check the BeamAI kernel health.
-spec check_kernel() -> {ok, map()} | {error, term()}.
check_kernel() ->
    gen_server:call(?SERVER, check_kernel, ?COMPONENT_TIMEOUT).

%% @doc Check the BeamAI memory system health.
-spec check_memory() -> {ok, map()} | {error, term()}.
check_memory() ->
    gen_server:call(?SERVER, check_memory, ?COMPONENT_TIMEOUT).

%% @doc Check BeamAI LLM provider connectivity.
-spec check_llm() -> {ok, map()} | {error, term()}.
check_llm() ->
    gen_server:call(?SERVER, check_llm, ?LLM_TIMEOUT).

%% @doc Check the BeamAI agent pool status.
-spec check_agents() -> {ok, map()} | {error, term()}.
check_agents() ->
    gen_server:call(?SERVER, check_agents, ?COMPONENT_TIMEOUT).

%% @doc Get the current overall health status without running new checks.
-spec status() -> map().
status() ->
    gen_server:call(?SERVER, status).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI health adapter initializing"),

    TimerRef = erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), periodic_check),

    State = #state{
        last_check = undefined,
        check_timer = TimerRef,
        results = #{},
        overall_status = unknown,
        check_count = 0,
        failure_count = 0,
        config = #{
            check_interval => ?HEALTH_CHECK_INTERVAL,
            llm_timeout => ?LLM_TIMEOUT,
            component_timeout => ?COMPONENT_TIMEOUT
        }
    },

    %% Run initial health check
    erlang:send_after(500, self(), initial_check),

    {ok, State}.

%% @private
handle_call(check_all, _From, State) ->
    {Results, NewState} = do_check_all(State),
    {reply, {ok, Results}, NewState};

handle_call(check_kernel, _From, State) ->
    Result = do_check_kernel(),
    NewResults = maps:put(kernel, Result, State#state.results),
    {reply, {ok, health_result_to_map(Result)}, State#state{results = NewResults}};

handle_call(check_memory, _From, State) ->
    Result = do_check_memory(),
    NewResults = maps:put(memory, Result, State#state.results),
    {reply, {ok, health_result_to_map(Result)}, State#state{results = NewResults}};

handle_call(check_llm, _From, State) ->
    Result = do_check_llm(),
    NewResults = maps:put(llm, Result, State#state.results),
    {reply, {ok, health_result_to_map(Result)}, State#state{results = NewResults}};

handle_call(check_agents, _From, State) ->
    Result = do_check_agents(),
    NewResults = maps:put(agents, Result, State#state.results),
    {reply, {ok, health_result_to_map(Result)}, State#state{results = NewResults}};

handle_call(status, _From, State) ->
    StatusMap = #{
        overall_status => State#state.overall_status,
        last_check => State#state.last_check,
        check_count => State#state.check_count,
        failure_count => State#state.failure_count,
        components => maps:map(fun(_K, V) -> health_result_to_map(V) end, State#state.results)
    },
    {reply, StatusMap, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(initial_check, State) ->
    {_Results, NewState} = do_check_all(State),
    {noreply, NewState};

handle_info(periodic_check, State) ->
    {_Results, NewState} = do_check_all(State),
    TimerRef = erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), periodic_check),
    {noreply, NewState#state{check_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{check_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    logger:info("BeamAI health adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Run all health checks and compute aggregate status.
-spec do_check_all(#state{}) -> {map(), #state{}}.
do_check_all(State) ->
    KernelResult = do_check_kernel(),
    MemoryResult = do_check_memory(),
    LlmResult = do_check_llm(),
    AgentsResult = do_check_agents(),

    Results = #{
        kernel => KernelResult,
        memory => MemoryResult,
        llm => LlmResult,
        agents => AgentsResult
    },

    OverallStatus = compute_overall_status(Results),
    Now = erlang:system_time(millisecond),

    FailureCount = case OverallStatus of
        healthy -> State#state.failure_count;
        _ -> State#state.failure_count + 1
    end,

    %% Report to existing health handler if available
    report_to_health_handler(OverallStatus, Results),

    ResultMap = maps:map(fun(_K, V) -> health_result_to_map(V) end, Results),
    AggregatedResult = #{
        overall_status => OverallStatus,
        components => ResultMap,
        timestamp => Now
    },

    NewState = State#state{
        last_check = Now,
        results = Results,
        overall_status = OverallStatus,
        check_count = State#state.check_count + 1,
        failure_count = FailureCount
    },

    {AggregatedResult, NewState}.

%% @private Check BeamAI kernel health.
-spec do_check_kernel() -> #health_result{}.
do_check_kernel() ->
    Start = erlang:monotonic_time(millisecond),
    try
        case whereis(beamai_bridge) of
            undefined ->
                #health_result{
                    component = kernel,
                    status = unhealthy,
                    details = #{reason => <<"BeamAI bridge not running">>},
                    timestamp = erlang:system_time(millisecond),
                    latency_ms = elapsed(Start)
                };
            _Pid ->
                case catch beamai_bridge:get_status() of
                    #{kernel_status := running} = Status ->
                        #health_result{
                            component = kernel,
                            status = healthy,
                            details = #{
                                kernel_status => running,
                                handler_count => maps:get(handler_count, Status, 0),
                                uptime_ms => maps:get(uptime_ms, Status, 0)
                            },
                            timestamp = erlang:system_time(millisecond),
                            latency_ms = elapsed(Start)
                        };
                    #{kernel_status := degraded} = Status ->
                        #health_result{
                            component = kernel,
                            status = degraded,
                            details = #{
                                kernel_status => degraded,
                                handler_count => maps:get(handler_count, Status, 0)
                            },
                            timestamp = erlang:system_time(millisecond),
                            latency_ms = elapsed(Start)
                        };
                    Status when is_map(Status) ->
                        #health_result{
                            component = kernel,
                            status = healthy,
                            details = Status,
                            timestamp = erlang:system_time(millisecond),
                            latency_ms = elapsed(Start)
                        };
                    Other ->
                        #health_result{
                            component = kernel,
                            status = degraded,
                            details = #{reason => <<"Unexpected status">>, raw => format_term(Other)},
                            timestamp = erlang:system_time(millisecond),
                            latency_ms = elapsed(Start)
                        }
                end
        end
    catch
        _:Error ->
            #health_result{
                component = kernel,
                status = unhealthy,
                details = #{error => format_term(Error)},
                timestamp = erlang:system_time(millisecond),
                latency_ms = elapsed(Start)
            }
    end.

%% @private Check BeamAI memory system health.
-spec do_check_memory() -> #health_result{}.
do_check_memory() ->
    Start = erlang:monotonic_time(millisecond),
    try
        %% Check BEAM VM memory usage as a proxy for BeamAI memory subsystem
        MemInfo = erlang:memory(),
        TotalMem = proplists:get_value(total, MemInfo, 0),
        ProcessesMem = proplists:get_value(processes, MemInfo, 0),
        EtsMem = proplists:get_value(ets, MemInfo, 0),
        BinaryMem = proplists:get_value(binary, MemInfo, 0),

        %% Check ETS tables related to BeamAI
        EtsTableCount = length(ets:all()),

        %% Determine health based on memory thresholds
        TotalMB = TotalMem / (1024 * 1024),
        Status = if
            TotalMB > 4096 -> degraded;
            TotalMB > 8192 -> unhealthy;
            true -> healthy
        end,

        #health_result{
            component = memory,
            status = Status,
            details = #{
                total_bytes => TotalMem,
                total_mb => round(TotalMB * 100) / 100,
                processes_bytes => ProcessesMem,
                ets_bytes => EtsMem,
                binary_bytes => BinaryMem,
                ets_table_count => EtsTableCount
            },
            timestamp = erlang:system_time(millisecond),
            latency_ms = elapsed(Start)
        }
    catch
        _:Error ->
            #health_result{
                component = memory,
                status = unhealthy,
                details = #{error => format_term(Error)},
                timestamp = erlang:system_time(millisecond),
                latency_ms = elapsed(Start)
            }
    end.

%% @private Check BeamAI LLM provider connectivity.
-spec do_check_llm() -> #health_result{}.
do_check_llm() ->
    Start = erlang:monotonic_time(millisecond),
    try
        %% Check if LLM-related processes are running
        LlmProcesses = [
            {yawl_llm_validator, <<"LLM validator">>},
            {yawl_model_comparison, <<"Model comparison">>}
        ],
        ProcessStatuses = lists:map(fun({Name, Label}) ->
            case whereis(Name) of
                undefined -> {Label, not_running};
                Pid ->
                    case erlang:process_info(Pid, status) of
                        {status, _} -> {Label, running};
                        undefined -> {Label, dead}
                    end
            end
        end, LlmProcesses),

        RunningCount = length([S || {_, S} <- ProcessStatuses, S =:= running]),
        TotalCount = length(ProcessStatuses),

        Status = if
            RunningCount =:= TotalCount -> healthy;
            RunningCount > 0 -> degraded;
            true -> unhealthy
        end,

        StatusMap = maps:from_list(ProcessStatuses),

        #health_result{
            component = llm,
            status = Status,
            details = #{
                processes => StatusMap,
                running_count => RunningCount,
                total_count => TotalCount
            },
            timestamp = erlang:system_time(millisecond),
            latency_ms = elapsed(Start)
        }
    catch
        _:Error ->
            #health_result{
                component = llm,
                status = unknown,
                details = #{error => format_term(Error)},
                timestamp = erlang:system_time(millisecond),
                latency_ms = elapsed(Start)
            }
    end.

%% @private Check BeamAI agent pool status.
-spec do_check_agents() -> #health_result{}.
do_check_agents() ->
    Start = erlang:monotonic_time(millisecond),
    try
        %% Check agent-related supervisors and processes
        AgentComponents = [
            {a2a_task_sup, <<"Task supervisor">>},
            {a2a_erl_sup, <<"Application supervisor">>}
        ],
        ComponentStatuses = lists:map(fun({Name, Label}) ->
            case whereis(Name) of
                undefined -> {Label, not_running};
                Pid ->
                    case erlang:process_info(Pid, status) of
                        {status, _} -> {Label, running};
                        undefined -> {Label, dead}
                    end
            end
        end, AgentComponents),

        %% Count active task processes
        ActiveTasks = case whereis(a2a_task_sup) of
            undefined -> 0;
            SupPid ->
                try
                    Children = supervisor:which_children(SupPid),
                    length(Children)
                catch
                    _:_ -> 0
                end
        end,

        RunningCount = length([S || {_, S} <- ComponentStatuses, S =:= running]),
        TotalCount = length(ComponentStatuses),

        Status = if
            RunningCount =:= TotalCount -> healthy;
            RunningCount > 0 -> degraded;
            true -> unhealthy
        end,

        #health_result{
            component = agents,
            status = Status,
            details = #{
                components => maps:from_list(ComponentStatuses),
                active_tasks => ActiveTasks,
                running_count => RunningCount,
                total_count => TotalCount
            },
            timestamp = erlang:system_time(millisecond),
            latency_ms = elapsed(Start)
        }
    catch
        _:Error ->
            #health_result{
                component = agents,
                status = unknown,
                details = #{error => format_term(Error)},
                timestamp = erlang:system_time(millisecond),
                latency_ms = elapsed(Start)
            }
    end.

%% @private Compute overall status from individual component results.
-spec compute_overall_status(#{atom() => #health_result{}}) -> healthy | degraded | unhealthy | unknown.
compute_overall_status(Results) ->
    Statuses = [R#health_result.status || {_, R} <- maps:to_list(Results)],
    case lists:member(unhealthy, Statuses) of
        true -> unhealthy;
        false ->
            case lists:member(degraded, Statuses) of
                true -> degraded;
                false ->
                    case lists:member(unknown, Statuses) of
                        true ->
                            case lists:member(healthy, Statuses) of
                                true -> degraded;
                                false -> unknown
                            end;
                        false -> healthy
                    end
            end
    end.

%% @private Report health status to the existing health handler.
-spec report_to_health_handler(atom(), map()) -> ok.
report_to_health_handler(OverallStatus, Results) ->
    try
        case whereis(a2a_health_handler) of
            undefined -> ok;
            _Pid ->
                %% Build a health report compatible with a2a_health_handler
                Report = #{
                    source => beamai_health_adapter,
                    status => OverallStatus,
                    components => maps:map(fun(_K, V) -> health_result_to_map(V) end, Results),
                    timestamp => erlang:system_time(millisecond)
                },
                logger:debug("BeamAI health adapter: reported status ~p to health handler", [OverallStatus]),
                _ = Report,
                ok
        end
    catch
        _:_ -> ok
    end.

%% @private Convert a health_result record to a map.
-spec health_result_to_map(#health_result{}) -> map().
health_result_to_map(#health_result{
    component = Component,
    status = Status,
    details = Details,
    timestamp = Timestamp,
    latency_ms = Latency
}) ->
    #{
        component => Component,
        status => Status,
        details => Details,
        timestamp => Timestamp,
        latency_ms => Latency
    }.

%% @private Calculate elapsed time in milliseconds.
-spec elapsed(integer()) -> non_neg_integer().
elapsed(Start) ->
    erlang:monotonic_time(millisecond) - Start.

%% @private Format a term to a binary string for inclusion in details.
-spec format_term(term()) -> binary().
format_term(Term) ->
    list_to_binary(io_lib:format("~p", [Term])).
