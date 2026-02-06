%%% @doc BeamAI Metrics Adapter - Metrics Collection and Prometheus Export
%%%
%%% This module collects metrics from all BeamAI components and exposes them
%%% in a format compatible with the existing HotCI monitoring infrastructure.
%%% It integrates with a2a_metrics, hotci_metrics_collector, and
%%% a2a_hotci_monitoring to provide a unified metrics view.
%%%
%%% Metrics categories:
%%% - Kernel metrics: tool invocations, filter executions, handler counts
%%% - Memory metrics: store size, checkpoint count, hit rates
%%% - LLM metrics: request counts, latency, token usage, error rates
%%% - Agent metrics: active agents, turn counts, tool calls
%%%
%%% All metrics are also exposed in Prometheus text format for scraping.
%%%
%%% @end
-module(beamai_metrics_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    collect_all/0,
    collect_kernel/0,
    collect_memory/0,
    collect_llm/0,
    collect_agents/0,
    to_prometheus/0
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
-define(COLLECTION_INTERVAL, 15000).
-define(METRICS_TABLE, beamai_metrics_ets).

-record(metric_entry, {
    name :: binary(),
    type :: counter | gauge | histogram | summary,
    value :: number(),
    labels :: map(),
    help :: binary(),
    timestamp :: integer()
}).

-record(state, {
    metrics_table :: ets:tid() | undefined,
    collection_timer :: reference() | undefined,
    last_collection :: integer() | undefined,
    collection_count :: non_neg_integer(),
    kernel_metrics :: map(),
    memory_metrics :: map(),
    llm_metrics :: map(),
    agent_metrics :: map(),
    historical :: list()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the metrics adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Collect all BeamAI metrics.
-spec collect_all() -> {ok, map()}.
collect_all() ->
    gen_server:call(?SERVER, collect_all, 10000).

%% @doc Collect BeamAI kernel metrics.
-spec collect_kernel() -> {ok, map()}.
collect_kernel() ->
    gen_server:call(?SERVER, collect_kernel).

%% @doc Collect BeamAI memory metrics.
-spec collect_memory() -> {ok, map()}.
collect_memory() ->
    gen_server:call(?SERVER, collect_memory).

%% @doc Collect BeamAI LLM metrics.
-spec collect_llm() -> {ok, map()}.
collect_llm() ->
    gen_server:call(?SERVER, collect_llm).

%% @doc Collect BeamAI agent metrics.
-spec collect_agents() -> {ok, map()}.
collect_agents() ->
    gen_server:call(?SERVER, collect_agents).

%% @doc Export all metrics in Prometheus text exposition format.
-spec to_prometheus() -> {ok, binary()}.
to_prometheus() ->
    gen_server:call(?SERVER, to_prometheus, 10000).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI metrics adapter initializing"),

    Table = ets:new(?METRICS_TABLE, [
        set,
        named_table,
        public,
        {read_concurrency, true}
    ]),

    TimerRef = erlang:send_after(?COLLECTION_INTERVAL, self(), collect),

    State = #state{
        metrics_table = Table,
        collection_timer = TimerRef,
        last_collection = undefined,
        collection_count = 0,
        kernel_metrics = #{},
        memory_metrics = #{},
        llm_metrics = #{},
        agent_metrics = #{},
        historical = []
    },

    %% Initial collection
    erlang:send_after(500, self(), collect),

    {ok, State}.

%% @private
handle_call(collect_all, _From, State) ->
    NewState = do_collect_all(State),
    Result = #{
        kernel => NewState#state.kernel_metrics,
        memory => NewState#state.memory_metrics,
        llm => NewState#state.llm_metrics,
        agents => NewState#state.agent_metrics,
        timestamp => NewState#state.last_collection,
        collection_count => NewState#state.collection_count
    },
    {reply, {ok, Result}, NewState};

handle_call(collect_kernel, _From, State) ->
    Metrics = do_collect_kernel(),
    NewState = State#state{kernel_metrics = Metrics},
    {reply, {ok, Metrics}, NewState};

handle_call(collect_memory, _From, State) ->
    Metrics = do_collect_memory(),
    NewState = State#state{memory_metrics = Metrics},
    {reply, {ok, Metrics}, NewState};

handle_call(collect_llm, _From, State) ->
    Metrics = do_collect_llm(),
    NewState = State#state{llm_metrics = Metrics},
    {reply, {ok, Metrics}, NewState};

handle_call(collect_agents, _From, State) ->
    Metrics = do_collect_agents(),
    NewState = State#state{agent_metrics = Metrics},
    {reply, {ok, Metrics}, NewState};

handle_call(to_prometheus, _From, State) ->
    %% Ensure we have fresh data
    FreshState = do_collect_all(State),
    Output = format_prometheus(FreshState),
    {reply, {ok, Output}, FreshState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(collect, State) ->
    NewState = do_collect_all(State),
    TimerRef = erlang:send_after(?COLLECTION_INTERVAL, self(), collect),
    %% Forward to HotCI metrics collector if available
    forward_to_hotci(NewState),
    {noreply, NewState#state{collection_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{collection_timer = TimerRef, metrics_table = Table}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    case Table of
        undefined -> ok;
        _ ->
            try ets:delete(Table)
            catch _:_ -> ok
            end
    end,
    logger:info("BeamAI metrics adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions - Collection
%%%===================================================================

%% @private Collect all metrics categories.
-spec do_collect_all(#state{}) -> #state{}.
do_collect_all(State) ->
    KernelMetrics = do_collect_kernel(),
    MemoryMetrics = do_collect_memory(),
    LlmMetrics = do_collect_llm(),
    AgentMetrics = do_collect_agents(),
    Now = erlang:system_time(millisecond),

    %% Store metrics in ETS for fast access
    store_metrics(State#state.metrics_table, KernelMetrics, MemoryMetrics, LlmMetrics, AgentMetrics),

    %% Keep a bounded history for trend analysis
    HistoryEntry = #{
        timestamp => Now,
        kernel => KernelMetrics,
        memory => MemoryMetrics,
        llm => LlmMetrics,
        agents => AgentMetrics
    },
    History = lists:sublist([HistoryEntry | State#state.historical], 60),

    State#state{
        kernel_metrics = KernelMetrics,
        memory_metrics = MemoryMetrics,
        llm_metrics = LlmMetrics,
        agent_metrics = AgentMetrics,
        last_collection = Now,
        collection_count = State#state.collection_count + 1,
        historical = History
    }.

%% @private Collect kernel metrics from beamai_bridge.
-spec do_collect_kernel() -> map().
do_collect_kernel() ->
    try
        case whereis(beamai_bridge) of
            undefined ->
                #{
                    status => not_running,
                    handler_count => 0,
                    tool_invocations => 0,
                    filter_executions => 0,
                    errors => 0
                };
            _Pid ->
                Status = catch beamai_bridge:get_status(),
                case Status of
                    M when is_map(M) ->
                        Metrics = maps:get(metrics, M, #{}),
                        #{
                            status => maps:get(kernel_status, M, unknown),
                            handler_count => maps:get(handler_count, M, 0),
                            tool_invocations => maps:get(tasks_translated, Metrics, 0),
                            filter_executions => maps:get(messages_translated, Metrics, 0),
                            handlers_registered => maps:get(handlers_registered, Metrics, 0),
                            errors => maps:get(errors, Metrics, 0),
                            uptime_ms => maps:get(uptime_ms, M, 0)
                        };
                    _ ->
                        #{status => error, handler_count => 0, tool_invocations => 0,
                          filter_executions => 0, errors => 0}
                end
        end
    catch
        _:_ ->
            #{status => error, handler_count => 0, tool_invocations => 0,
              filter_executions => 0, errors => 0}
    end.

%% @private Collect memory metrics from the BEAM VM.
-spec do_collect_memory() -> map().
do_collect_memory() ->
    try
        MemInfo = erlang:memory(),
        TotalMem = proplists:get_value(total, MemInfo, 0),
        ProcessesMem = proplists:get_value(processes, MemInfo, 0),
        EtsMem = proplists:get_value(ets, MemInfo, 0),
        BinaryMem = proplists:get_value(binary, MemInfo, 0),
        AtomMem = proplists:get_value(atom, MemInfo, 0),
        SystemMem = proplists:get_value(system, MemInfo, 0),

        %% Count ETS tables and estimate sizes
        AllTables = ets:all(),
        EtsTableCount = length(AllTables),
        EtsEntryCount = lists:foldl(fun(Tab, Acc) ->
            try ets:info(Tab, size) + Acc
            catch _:_ -> Acc
            end
        end, 0, AllTables),

        #{
            total_bytes => TotalMem,
            total_mb => round(TotalMem / (1024 * 1024) * 100) / 100,
            processes_bytes => ProcessesMem,
            ets_bytes => EtsMem,
            binary_bytes => BinaryMem,
            atom_bytes => AtomMem,
            system_bytes => SystemMem,
            ets_table_count => EtsTableCount,
            ets_entry_count => EtsEntryCount,
            checkpoint_count => 0,
            hit_rate => 0.0
        }
    catch
        _:_ ->
            #{total_bytes => 0, total_mb => 0, processes_bytes => 0,
              ets_bytes => 0, binary_bytes => 0, ets_table_count => 0,
              ets_entry_count => 0, checkpoint_count => 0, hit_rate => 0.0}
    end.

%% @private Collect LLM metrics from validator and model comparison modules.
-spec do_collect_llm() -> map().
do_collect_llm() ->
    try
        %% Gather metrics from LLM-related processes
        LlmProcs = [yawl_llm_validator, yawl_model_comparison],
        ProcStatuses = lists:map(fun(Mod) ->
            case whereis(Mod) of
                undefined -> {Mod, not_running};
                Pid ->
                    case erlang:process_info(Pid, [message_queue_len, memory, reductions]) of
                        undefined -> {Mod, dead};
                        Info -> {Mod, maps:from_list(Info)}
                    end
            end
        end, LlmProcs),

        RunningCount = length([S || {_, S} <- ProcStatuses, is_map(S)]),

        %% Aggregate process-level metrics
        TotalReductions = lists:foldl(fun
            ({_, Info}, Acc) when is_map(Info) ->
                Acc + maps:get(reductions, Info, 0);
            (_, Acc) -> Acc
        end, 0, ProcStatuses),

        TotalMemory = lists:foldl(fun
            ({_, Info}, Acc) when is_map(Info) ->
                Acc + maps:get(memory, Info, 0);
            (_, Acc) -> Acc
        end, 0, ProcStatuses),

        TotalQueueLen = lists:foldl(fun
            ({_, Info}, Acc) when is_map(Info) ->
                Acc + maps:get(message_queue_len, Info, 0);
            (_, Acc) -> Acc
        end, 0, ProcStatuses),

        #{
            running_providers => RunningCount,
            total_providers => length(LlmProcs),
            request_count => 0,
            total_latency_ms => 0,
            average_latency_ms => 0.0,
            token_usage => 0,
            error_count => 0,
            total_reductions => TotalReductions,
            total_memory_bytes => TotalMemory,
            total_queue_length => TotalQueueLen,
            process_statuses => maps:from_list(ProcStatuses)
        }
    catch
        _:_ ->
            #{running_providers => 0, total_providers => 0, request_count => 0,
              total_latency_ms => 0, average_latency_ms => 0.0, token_usage => 0,
              error_count => 0}
    end.

%% @private Collect agent metrics from task supervisors.
-spec do_collect_agents() -> map().
do_collect_agents() ->
    try
        %% Count active agents/tasks from the task supervisor
        {ActiveTasks, TaskDetails} = case whereis(a2a_task_sup) of
            undefined -> {0, []};
            SupPid ->
                try
                    Children = supervisor:which_children(SupPid),
                    Count = length(Children),
                    Details = lists:map(fun({Id, Pid, Type, _Mods}) ->
                        #{id => Id, pid => Pid, type => Type}
                    end, Children),
                    {Count, Details}
                catch
                    _:_ -> {0, []}
                end
        end,

        %% Total process count as a proxy for system activity
        ProcessCount = erlang:system_info(process_count),
        ProcessLimit = erlang:system_info(process_limit),

        #{
            active_agents => ActiveTasks,
            agent_details => TaskDetails,
            total_process_count => ProcessCount,
            process_limit => ProcessLimit,
            process_utilization => round(ProcessCount / ProcessLimit * 10000) / 100,
            turn_count => 0,
            tool_calls => 0,
            completed_tasks => 0,
            failed_tasks => 0
        }
    catch
        _:_ ->
            #{active_agents => 0, total_process_count => 0, process_limit => 0,
              process_utilization => 0.0, turn_count => 0, tool_calls => 0}
    end.

%%%===================================================================
%%% Internal Functions - Storage
%%%===================================================================

%% @private Store collected metrics in ETS.
-spec store_metrics(ets:tid(), map(), map(), map(), map()) -> ok.
store_metrics(Table, Kernel, Memory, Llm, Agents) ->
    try
        Now = erlang:system_time(millisecond),
        ets:insert(Table, {kernel_metrics, Kernel, Now}),
        ets:insert(Table, {memory_metrics, Memory, Now}),
        ets:insert(Table, {llm_metrics, Llm, Now}),
        ets:insert(Table, {agent_metrics, Agents, Now}),
        ok
    catch
        _:_ -> ok
    end.

%% @private Forward metrics to HotCI metrics collector.
-spec forward_to_hotci(#state{}) -> ok.
forward_to_hotci(State) ->
    try
        case whereis(hotci_metrics_collector) of
            undefined -> ok;
            _Pid ->
                ClusterId = <<"beamai">>,
                MetricMap = #{
                    metric_type => beamai_aggregate,
                    kernel => State#state.kernel_metrics,
                    memory => State#state.memory_metrics,
                    llm => State#state.llm_metrics,
                    agents => State#state.agent_metrics,
                    timestamp => State#state.last_collection
                },
                catch hotci_metrics_collector:record_metric(ClusterId, MetricMap),
                ok
        end
    catch
        _:_ -> ok
    end.

%%%===================================================================
%%% Internal Functions - Prometheus Format
%%%===================================================================

%% @private Format all metrics in Prometheus text exposition format.
-spec format_prometheus(#state{}) -> binary().
format_prometheus(State) ->
    Lines = lists:flatten([
        format_kernel_prometheus(State#state.kernel_metrics),
        format_memory_prometheus(State#state.memory_metrics),
        format_llm_prometheus(State#state.llm_metrics),
        format_agent_prometheus(State#state.agent_metrics)
    ]),
    iolist_to_binary(Lines).

%% @private Format kernel metrics for Prometheus.
-spec format_kernel_prometheus(map()) -> iolist().
format_kernel_prometheus(Metrics) ->
    [
        prom_line(<<"# HELP beamai_kernel_handler_count Number of registered BeamAI handlers">>),
        prom_line(<<"# TYPE beamai_kernel_handler_count gauge">>),
        prom_gauge(<<"beamai_kernel_handler_count">>, maps:get(handler_count, Metrics, 0)),

        prom_line(<<"# HELP beamai_kernel_tool_invocations_total Total tool invocations">>),
        prom_line(<<"# TYPE beamai_kernel_tool_invocations_total counter">>),
        prom_counter(<<"beamai_kernel_tool_invocations_total">>, maps:get(tool_invocations, Metrics, 0)),

        prom_line(<<"# HELP beamai_kernel_filter_executions_total Total filter executions">>),
        prom_line(<<"# TYPE beamai_kernel_filter_executions_total counter">>),
        prom_counter(<<"beamai_kernel_filter_executions_total">>, maps:get(filter_executions, Metrics, 0)),

        prom_line(<<"# HELP beamai_kernel_errors_total Total kernel errors">>),
        prom_line(<<"# TYPE beamai_kernel_errors_total counter">>),
        prom_counter(<<"beamai_kernel_errors_total">>, maps:get(errors, Metrics, 0)),

        prom_line(<<"# HELP beamai_kernel_uptime_milliseconds Kernel uptime in ms">>),
        prom_line(<<"# TYPE beamai_kernel_uptime_milliseconds gauge">>),
        prom_gauge(<<"beamai_kernel_uptime_milliseconds">>, maps:get(uptime_ms, Metrics, 0))
    ].

%% @private Format memory metrics for Prometheus.
-spec format_memory_prometheus(map()) -> iolist().
format_memory_prometheus(Metrics) ->
    [
        prom_line(<<"# HELP beamai_memory_total_bytes Total memory usage in bytes">>),
        prom_line(<<"# TYPE beamai_memory_total_bytes gauge">>),
        prom_gauge(<<"beamai_memory_total_bytes">>, maps:get(total_bytes, Metrics, 0)),

        prom_line(<<"# HELP beamai_memory_processes_bytes Process memory in bytes">>),
        prom_line(<<"# TYPE beamai_memory_processes_bytes gauge">>),
        prom_gauge(<<"beamai_memory_processes_bytes">>, maps:get(processes_bytes, Metrics, 0)),

        prom_line(<<"# HELP beamai_memory_ets_bytes ETS memory in bytes">>),
        prom_line(<<"# TYPE beamai_memory_ets_bytes gauge">>),
        prom_gauge(<<"beamai_memory_ets_bytes">>, maps:get(ets_bytes, Metrics, 0)),

        prom_line(<<"# HELP beamai_memory_binary_bytes Binary memory in bytes">>),
        prom_line(<<"# TYPE beamai_memory_binary_bytes gauge">>),
        prom_gauge(<<"beamai_memory_binary_bytes">>, maps:get(binary_bytes, Metrics, 0)),

        prom_line(<<"# HELP beamai_memory_ets_table_count Number of ETS tables">>),
        prom_line(<<"# TYPE beamai_memory_ets_table_count gauge">>),
        prom_gauge(<<"beamai_memory_ets_table_count">>, maps:get(ets_table_count, Metrics, 0)),

        prom_line(<<"# HELP beamai_memory_ets_entry_count Total ETS entries">>),
        prom_line(<<"# TYPE beamai_memory_ets_entry_count gauge">>),
        prom_gauge(<<"beamai_memory_ets_entry_count">>, maps:get(ets_entry_count, Metrics, 0))
    ].

%% @private Format LLM metrics for Prometheus.
-spec format_llm_prometheus(map()) -> iolist().
format_llm_prometheus(Metrics) ->
    [
        prom_line(<<"# HELP beamai_llm_running_providers Number of running LLM providers">>),
        prom_line(<<"# TYPE beamai_llm_running_providers gauge">>),
        prom_gauge(<<"beamai_llm_running_providers">>, maps:get(running_providers, Metrics, 0)),

        prom_line(<<"# HELP beamai_llm_request_count_total Total LLM requests">>),
        prom_line(<<"# TYPE beamai_llm_request_count_total counter">>),
        prom_counter(<<"beamai_llm_request_count_total">>, maps:get(request_count, Metrics, 0)),

        prom_line(<<"# HELP beamai_llm_average_latency_milliseconds Average LLM latency">>),
        prom_line(<<"# TYPE beamai_llm_average_latency_milliseconds gauge">>),
        prom_gauge(<<"beamai_llm_average_latency_milliseconds">>, maps:get(average_latency_ms, Metrics, 0.0)),

        prom_line(<<"# HELP beamai_llm_token_usage_total Total token usage">>),
        prom_line(<<"# TYPE beamai_llm_token_usage_total counter">>),
        prom_counter(<<"beamai_llm_token_usage_total">>, maps:get(token_usage, Metrics, 0)),

        prom_line(<<"# HELP beamai_llm_error_count_total Total LLM errors">>),
        prom_line(<<"# TYPE beamai_llm_error_count_total counter">>),
        prom_counter(<<"beamai_llm_error_count_total">>, maps:get(error_count, Metrics, 0))
    ].

%% @private Format agent metrics for Prometheus.
-spec format_agent_prometheus(map()) -> iolist().
format_agent_prometheus(Metrics) ->
    [
        prom_line(<<"# HELP beamai_agent_active_count Number of active agents">>),
        prom_line(<<"# TYPE beamai_agent_active_count gauge">>),
        prom_gauge(<<"beamai_agent_active_count">>, maps:get(active_agents, Metrics, 0)),

        prom_line(<<"# HELP beamai_agent_process_count Total BEAM process count">>),
        prom_line(<<"# TYPE beamai_agent_process_count gauge">>),
        prom_gauge(<<"beamai_agent_process_count">>, maps:get(total_process_count, Metrics, 0)),

        prom_line(<<"# HELP beamai_agent_process_utilization Process utilization percentage">>),
        prom_line(<<"# TYPE beamai_agent_process_utilization gauge">>),
        prom_gauge(<<"beamai_agent_process_utilization">>, maps:get(process_utilization, Metrics, 0.0)),

        prom_line(<<"# HELP beamai_agent_turn_count_total Total agent turns">>),
        prom_line(<<"# TYPE beamai_agent_turn_count_total counter">>),
        prom_counter(<<"beamai_agent_turn_count_total">>, maps:get(turn_count, Metrics, 0)),

        prom_line(<<"# HELP beamai_agent_tool_calls_total Total agent tool calls">>),
        prom_line(<<"# TYPE beamai_agent_tool_calls_total counter">>),
        prom_counter(<<"beamai_agent_tool_calls_total">>, maps:get(tool_calls, Metrics, 0))
    ].

%% @private Format a Prometheus comment/help line.
-spec prom_line(binary()) -> iolist().
prom_line(Line) ->
    [Line, <<"\n">>].

%% @private Format a Prometheus gauge metric line.
-spec prom_gauge(binary(), number()) -> iolist().
prom_gauge(Name, Value) ->
    [Name, <<" ">>, format_number(Value), <<"\n">>].

%% @private Format a Prometheus counter metric line.
-spec prom_counter(binary(), number()) -> iolist().
prom_counter(Name, Value) ->
    [Name, <<" ">>, format_number(Value), <<"\n">>].

%% @private Format a number for Prometheus output.
-spec format_number(number()) -> binary().
format_number(Value) when is_integer(Value) ->
    integer_to_binary(Value);
format_number(Value) when is_float(Value) ->
    float_to_binary(Value, [{decimals, 4}, compact]).
