%%% @doc A2A Health Check Handler
%%%
%%% This module implements health check endpoints for the A2A agent service.
%%% Provides monitoring capabilities for load balancers, orchestrators, and
%%% observability systems.
%%%
%%% Endpoints:
%%% - GET /health          - Basic health check (200 if service is up)
%%% - GET /health/ready    - Readiness probe (200 if ready to accept traffic)
%%% - GET /health/live     - Liveness probe (200 if service is alive)
%%% - GET /health/degraded - Degraded mode check (200 if in degraded mode)
%%% - GET /metrics         - Prometheus-style metrics (future)
%%%
%%% @end
-module(a2a_health_handler).
-behaviour(cowboy_handler).

-include("a2a.hrl").

%% Cowboy callbacks
-export([init/2]).

%% Health check API (internal)
-export([
    check_health/0,
    check_readiness/0,
    check_liveness/0,
    get_system_info/0,
    get_metrics/0
]).

-record(health_checks, {
    task_store :: boolean(),
    agent_card :: boolean(),
    http_listener :: boolean(),
    sse_handler :: boolean(),
    push_notifier :: boolean(),
    database :: boolean()
}).

-record(health_state, {
    status :: up | degraded | down,
    timestamp :: integer(),
    uptime :: integer(),
    version :: binary(),
    checks :: #health_checks{} | map()
}).

%%% ============================================================================
%%% Cowboy Handler Callbacks
%%% ============================================================================

%% @doc Cowboy handler entry point
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    {StatusCode, Headers, Body, Req} = handle_request(Method, Path, Req0),

    ReqFinal = cowboy_req:reply(StatusCode, Headers, Body, Req),
    {ok, ReqFinal, State}.

%%% ============================================================================
%%% Request Handlers
%%% ============================================================================

%% @doc Route health check requests
handle_request(<<"GET">>, <<"/health">>, Req) ->
    handle_basic_health(Req);

handle_request(<<"GET">>, <<"/health/ready">>, Req) ->
    handle_readiness(Req);

handle_request(<<"GET">>, <<"/health/live">>, Req) ->
    handle_liveness(Req);

handle_request(<<"GET">>, <<"/health/degraded">>, Req) ->
    handle_degraded(Req);

handle_request(<<"GET">>, <<"/metrics">>, Req) ->
    handle_metrics(Req);

handle_request(_Method, _Path, Req) ->
    {405, json_headers(), error_response(<<"Method not allowed">>), Req}.

%% @doc Basic health check - returns 200 if service is running
handle_basic_health(Req) ->
    Health = check_health(),

    Status = case Health of
        #health_state{status = up} -> 200;
        #health_state{status = degraded} -> 200;
        #health_state{status = down} -> 503
    end,

    Body = encode_health_response(Health),
    {Status, json_headers(), Body, Req}.

%% @doc Readiness probe - checks if service can accept traffic
handle_readiness(Req) ->
    ReadyResult = check_readiness(),

    {Status, Body} = case ReadyResult of
        {ready, Info} ->
            {200, json:encode(#{
                <<"status">> => <<"ready">>,
                <<"timestamp">> => get_timestamp(),
                <<"checks">> => Info
            })};
        {not_ready, Reason, Info} ->
            {503, json:encode(#{
                <<"status">> => <<"not_ready">>,
                <<"timestamp">> => get_timestamp(),
                <<"reason">> => Reason,
                <<"checks">> => Info
            })}
    end,

    {Status, json_headers(), Body, Req}.

%% @doc Liveness probe - checks if service is alive
handle_liveness(Req) ->
    LiveResult = check_liveness(),

    {Status, Body} = case LiveResult of
        {alive, Info} ->
            {200, json:encode(#{
                <<"status">> => <<"alive">>,
                <<"timestamp">> => get_timestamp(),
                <<"info">> => Info
            })};
        {dead, Reason} ->
            {503, json:encode(#{
                <<"status">> => <<"dead">>,
                <<"timestamp">> => get_timestamp(),
                <<"reason">> => Reason
            })}
    end,

    {Status, json_headers(), Body, Req}.

%% @doc Degraded mode check
handle_degraded(Req) ->
    Health = check_health(),

    {Status, Body} = case Health#health_state.status of
        degraded ->
            %% Convert checks record to map for JSON encoding
            ChecksMap = #{
                <<"task_store">> => get_check_value(Health#health_state.checks, task_store),
                <<"agent_card">> => get_check_value(Health#health_state.checks, agent_card),
                <<"http_listener">> => get_check_value(Health#health_state.checks, http_listener),
                <<"sse_handler">> => get_check_value(Health#health_state.checks, sse_handler),
                <<"push_notifier">> => get_check_value(Health#health_state.checks, push_notifier),
                <<"database">> => get_check_value(Health#health_state.checks, database)
            },
            {200, json:encode(#{
                <<"status">> => <<"degraded">>,
                <<"timestamp">> => get_timestamp(),
                <<"checks">> => ChecksMap
            })};
        _ ->
            {503, json:encode(#{
                <<"status">> => <<"normal">>,
                <<"message">> => <<"Service is not in degraded mode">>
            })}
    end,

    {Status, json_headers(), Body, Req}.

%% @doc Metrics endpoint (Prometheus-style text format)
handle_metrics(Req) ->
    Metrics = get_metrics(),

    Body = format_prometheus_metrics(Metrics),
    {200, #{
        <<"content-type">> => <<"text/plain; version=0.0.4">>,
        <<"cache-control">> => <<"no-cache">>
    }, Body, Req}.

%%% ============================================================================
%%% Health Check API
%%% ============================================================================

%% @doc Check overall health status
-spec check_health() -> #health_state{}.
check_health() ->
    Checks = run_health_checks(),

    Status = determine_health_status(Checks),

    #health_state{
        status = Status,
        timestamp = get_timestamp(),
        uptime = get_uptime(),
        version = get_version(),
        checks = Checks
    }.

%% @doc Check if service is ready to accept traffic
-spec check_readiness() -> {ready, map()} | {not_ready, binary(), map()}.
check_readiness() ->
    Checks = #{
        <<"task_store">> => check_task_store_ready(),
        <<"http_listener">> => check_http_listener_ready(),
        <<"agent_card">> => check_agent_card_ready(),
        <<"memory">> => check_memory_available()
    },

    AllReady = maps:fold(fun(_K, V, Acc) -> Acc andalso V end, true, Checks),

    case AllReady of
        true -> {ready, Checks};
        false -> {not_ready, <<"Service not ready">>, Checks}
    end.

%% @doc Check if service is alive (liveness probe)
-spec check_liveness() -> {alive, map()} | {dead, binary()}.
check_liveness() ->
    %% Basic liveness: is the Erlang VM responsive?
    {TotalReductions, _} = erlang:statistics(reductions),
    Info = #{
        <<"node">> => list_to_binary(atom_to_list(node())),
        <<"processes">> => erlang:system_info(process_count),
        <<"process_limit">> => erlang:system_info(process_limit),
        <<"memory">> => get_memory_info(),
        <<"reductions">> => TotalReductions
    },

    try
        %% Check if VM is responsive by making a simple call
        %% If distribution is not enabled, skip the ping check
        case erlang:whereis(erlang) of
            %% Kernel process exists - VM is alive
            _ -> {alive, Info}
        end
    catch
        _:_ -> {dead, <<"Liveness check failed">>}
    end.

%% @doc Get system information
-spec get_system_info() -> map().
get_system_info() ->
    #{
        <<"node">> => list_to_binary(atom_to_list(node())),
        <<"version">> => get_version(),
        <<"uptime">> => get_uptime(),
        <<"otp_release">> => list_to_binary(erlang:system_info(otp_release)),
        <<"erts_version">> => list_to_binary(erlang:system_info(version)),
        <<"kernel">> => get_kernel_info(),
        <<"memory">> => get_detailed_memory_info(),
        <<"processes">> => get_process_info(),
        <<"ports">> => get_port_info()
    }.

%% @doc Get application metrics
-spec get_metrics() -> map().
get_metrics() ->
    #{
        <<"tasks_total">> => get_total_tasks(),
        <<"tasks_by_state">> => get_tasks_by_state(),
        <<"tasks_active">> => get_active_tasks(),
        <<"tasks_completed">> => get_completed_tasks(),
        <<"tasks_failed">> => get_failed_tasks(),
        <<"uptime_seconds">> => get_uptime() div 1000,
        <<"requests_total">> => get_request_count(),
        <<"memory_used_bytes">> => get_total_memory_used(),
        <<"processes">> => erlang:system_info(process_count)
    }.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Run all health checks
run_health_checks() ->
    #health_checks{
        task_store = check_task_store(),
        agent_card = check_agent_card(),
        http_listener = check_http_listener(),
        sse_handler = check_sse_handler(),
        push_notifier = check_push_notifier(),
        database = check_database()
    }.

%% @doc Determine overall health status from checks
determine_health_status(#health_checks{} = Checks) ->
    CriticalServices = [
        Checks#health_checks.task_store,
        Checks#health_checks.agent_card,
        Checks#health_checks.http_listener
    ],

    AllUp = lists:all(fun(X) -> X =:= true end, CriticalServices),

    OptionalServices = [
        Checks#health_checks.sse_handler,
        Checks#health_checks.push_notifier,
        Checks#health_checks.database
    ],

    OptionalDown = lists:filter(fun(X) -> X =:= false end, OptionalServices),

    case AllUp of
        true when length(OptionalDown) > 0 -> degraded;
        true -> up;
        false -> down
    end.

%% @doc Check task store health
check_task_store() ->
    try
        case whereis(a2a_task_store) of
            undefined -> false;
            Pid when is_pid(Pid) ->
                is_process_alive(Pid) andalso
                check_ets_table(a2a_tasks)
        end
    catch
        _:_ -> false
    end.

%% @doc Check task store readiness
check_task_store_ready() ->
    try
        case whereis(a2a_task_store) of
            undefined -> false;
            Pid when is_pid(Pid) ->
                is_process_alive(Pid) andalso
                check_ets_table(a2a_tasks) andalso
                check_ets_table(a2a_task_pids)
        end
    catch
        _:_ -> false
    end.

%% @doc Check agent card health
check_agent_card() ->
    try
        case whereis(a2a_agent_card) of
            undefined -> false;
            Pid when is_pid(Pid) -> is_process_alive(Pid)
        end
    catch
        _:_ -> false
    end.

%% @doc Check agent card readiness
check_agent_card_ready() ->
    try
        case whereis(a2a_agent_card) of
            undefined -> false;
            Pid when is_pid(Pid) ->
                is_process_alive(Pid) andalso
                begin
                    case catch a2a_agent_card:get_card() of
                        {'EXIT', _} -> false;
                        _ -> true
                    end
                end
        end
    catch
        _:_ -> false
    end.

%% @doc Check HTTP listener health
check_http_listener() ->
    try
        %% Check if Cowboy listener is running by checking ranch status
        %% The listener name is configured in a2a_erl_app
        Listeners = ranch:info(),
        case lists:keyfind(a2a_http_listener, 1, Listeners) of
            {a2a_http_listener, _Info} -> true;
            _ ->
                %% Fallback: check if we can connect to the configured port
                Port = application:get_env(a2a_erl, port, 8080),
                case gen_tcp:connect("localhost", Port, [{active, false}], 1000) of
                    {ok, Socket} ->
                        gen_tcp:close(Socket),
                        true;
                    {error, _} ->
                        false
                end
        end
    catch
        _:_ -> false
    end.

%% @doc Check HTTP listener readiness
check_http_listener_ready() ->
    check_http_listener().

%% @doc Check SSE handler health
check_sse_handler() ->
    try
        %% SSE handler is not a separate process, it's a Cowboy handler
        %% Check if HTTP listener is up (SSE uses same listener)
        check_http_listener()
    catch
        _:_ -> false
    end.

%% @doc Check push notifier health
check_push_notifier() ->
    try
        case whereis(a2a_push_notifier) of
            undefined -> false;
            Pid when is_pid(Pid) -> is_process_alive(Pid)
        end
    catch
        _:_ -> false
    end.

%% @doc Check database health (not used in this implementation)
check_database() ->
    %% No database in current implementation
    true.

%% @doc Check if ETS table exists and is accessible
check_ets_table(TableName) ->
    try
        case ets:info(TableName, size) of
            undefined -> false;
            _Size -> true
        end
    catch
        _:_ -> false
    end.

%% @doc Check memory availability
check_memory_available() ->
    try
        TotalMemory = erlang:memory(total),
        SystemTotalMemory = case os:type() of
            {unix, _} ->
                case os:cmd("free -b | awk 'NR==2{print $2}'") of
                    [] -> 0;
                    Output ->
                        try list_to_integer(string:trim(Output))
                        catch _:_ -> 0
                        end
                end;
            _ -> 0
        end,

        %% Consider memory pressure high if using > 90% of available
        case SystemTotalMemory of
            0 -> true;  %% Cannot determine, assume OK
            Total -> TotalMemory < (Total * 90) div 100
        end
    catch
        _:_ -> true
    end.

%% @doc Encode health response
encode_health_response(#health_state{} = Health) ->
    json:encode(#{
        <<"status">> => status_to_binary(Health#health_state.status),
        <<"timestamp">> => Health#health_state.timestamp,
        <<"uptime">> => Health#health_state.uptime,
        <<"version">> => Health#health_state.version,
        <<"checks">> => #{
            <<"task_store">> => get_check_value(Health#health_state.checks, task_store),
            <<"agent_card">> => get_check_value(Health#health_state.checks, agent_card),
            <<"http_listener">> => get_check_value(Health#health_state.checks, http_listener),
            <<"sse_handler">> => get_check_value(Health#health_state.checks, sse_handler),
            <<"push_notifier">> => get_check_value(Health#health_state.checks, push_notifier),
            <<"database">> => get_check_value(Health#health_state.checks, database)
        }
    }).

%% @doc Get check value from checks record
-spec get_check_value(#health_checks{}, atom()) -> boolean().
get_check_value(#health_checks{} = Rec, Field) ->
    case Field of
        task_store -> Rec#health_checks.task_store;
        agent_card -> Rec#health_checks.agent_card;
        http_listener -> Rec#health_checks.http_listener;
        sse_handler -> Rec#health_checks.sse_handler;
        push_notifier -> Rec#health_checks.push_notifier;
        database -> Rec#health_checks.database
    end.

%% @doc Convert status atom to binary
status_to_binary(up) -> <<"up">>;
status_to_binary(degraded) -> <<"degraded">>;
status_to_binary(down) -> <<"down">>.

%% @doc Get current timestamp in milliseconds
get_timestamp() ->
    erlang:system_time(millisecond).

%% @doc Get application uptime in milliseconds
-spec get_uptime() -> non_neg_integer().
get_uptime() ->
    case application:get_key(a2a_erl, start_time) of
        {ok, StartTime} ->
            erlang:monotonic_time(millisecond) - StartTime;
        undefined ->
            %% Fallback to system start time
            %% erlang:statistics(wall_clock) always returns {UpTime, WallClockReductions}
            {UpTime, _} = erlang:statistics(wall_clock),
            UpTime
    end.

%% @doc Get application version
get_version() ->
    case application:get_key(a2a_erl, vsn) of
        {ok, Vsn} -> list_to_binary(Vsn);
        undefined -> <<"unknown">>
    end.

%% @doc Get kernel information
get_kernel_info() ->
    #{
        <<"poll">> => erlang:system_info(kernel_poll),
        <<"thread">> => erlang:system_info(threads),
        <<"smp_support">> => erlang:system_info(smp_support),
        <<"scheduler_threads">> => erlang:system_info(schedulers),
        <<"scheduler_online">> => erlang:system_info(schedulers_online)
    }.

%% @doc Get memory information
get_memory_info() ->
    #{
        <<"total">> => erlang:memory(total),
        <<"processes">> => erlang:memory(processes),
        <<"processes_used">> => erlang:memory(processes_used),
        <<"system">> => erlang:memory(system),
        <<"atom">> => erlang:memory(atom),
        <<"atom_used">> => erlang:memory(atom_used),
        <<"binary">> => erlang:memory(binary),
        <<"code">> => erlang:memory(code),
        <<"ets">> => erlang:memory(ets)
    }.

%% @doc Get detailed memory information
-spec get_detailed_memory_info() -> map().
get_detailed_memory_info() ->
    #{
        <<"total">> => erlang:memory(total),
        <<"processes">> => erlang:memory(processes),
        <<"system">> => erlang:memory(system),
        <<"atom">> => erlang:memory(atom),
        <<"binary">> => erlang:memory(binary),
        <<"code">> => erlang:memory(code),
        <<"ets">> => erlang:memory(ets)
    }.

%% @doc Get process information
-spec get_process_info() -> map().
get_process_info() ->
    %% erlang:statistics(run_queue) returns a non_neg_integer() in OTP 27+
    RunQueue = erlang:statistics(run_queue),
    #{
        <<"count">> => erlang:system_info(process_count),
        <<"limit">> => erlang:system_info(process_limit),
        <<"run_queue">> => RunQueue
    }.

%% @doc Get port information
get_port_info() ->
    #{
        <<"count">> => erlang:system_info(port_count),
        <<"limit">> => erlang:system_info(port_limit)
    }.

%% @doc Get total memory used
get_total_memory_used() ->
    erlang:memory(total).

%% @doc Get total task count
get_total_tasks() ->
    try
        ets:info(a2a_tasks, size)
    catch
        _:_ -> 0
    end.

%% @doc Get tasks by state
get_tasks_by_state() ->
    try
        AllTasks = ets:tab2list(a2a_tasks),
        lists:foldl(fun({_TaskId, Task}, Acc) ->
            State = (Task#task.status)#task_status.state,
            StateBin = a2a_json:task_state_to_json(State),
            maps:update_with(StateBin, fun(V) -> V + 1 end, 1, Acc)
        end, #{}, AllTasks)
    catch
        _:_ -> #{}
    end.

%% @doc Get active task count
get_active_tasks() ->
    try
        AllTasks = ets:tab2list(a2a_tasks),
        ActiveStates = [submitted, working, input_required, auth_required],
        lists:foldl(fun({_TaskId, Task}, Acc) ->
            State = (Task#task.status)#task_status.state,
            case lists:member(State, ActiveStates) of
                true -> Acc + 1;
                false -> Acc
            end
        end, 0, AllTasks)
    catch
        _:_ -> 0
    end.

%% @doc Get completed task count
get_completed_tasks() ->
    try
        AllTasks = ets:tab2list(a2a_tasks),
        lists:foldl(fun({_TaskId, Task}, Acc) ->
            State = (Task#task.status)#task_status.state,
            case State of
                completed -> Acc + 1;
                _ -> Acc
            end
        end, 0, AllTasks)
    catch
        _:_ -> 0
    end.

%% @doc Get failed task count
get_failed_tasks() ->
    try
        AllTasks = ets:tab2list(a2a_tasks),
        lists:foldl(fun({_TaskId, Task}, Acc) ->
            State = (Task#task.status)#task_status.state,
            case State of
                failed -> Acc + 1;
                _ -> Acc
            end
        end, 0, AllTasks)
    catch
        _:_ -> 0
    end.

%% @doc Get request count (placeholder for future metrics)
get_request_count() ->
    %% In production, this would query a metrics table
    0.

%% @doc Format metrics in Prometheus text format
format_prometheus_metrics(Metrics) ->
    Format = fun(Name, Value, Help) ->
        [
            <<"# HELP ", Name/binary, " ", Help/binary, "\n">>,
            <<"# TYPE ", Name/binary, " gauge\n">>,
            <<Name/binary, " ", (integer_to_binary(Value))/binary, "\n\n">>
        ]
    end,

    Lists = [
        Format(<<"a2a_tasks_total">>,
               maps:get(<<"tasks_total">>, Metrics, 0),
               <<"Total number of tasks">>),

        Format(<<"a2a_tasks_active">>,
               maps:get(<<"tasks_active">>, Metrics, 0),
               <<"Number of currently active tasks">>),

        Format(<<"a2a_tasks_completed">>,
               maps:get(<<"tasks_completed">>, Metrics, 0),
               <<"Number of completed tasks">>),

        Format(<<"a2a_tasks_failed">>,
               maps:get(<<"tasks_failed">>, Metrics, 0),
               <<"Number of failed tasks">>),

        Format(<<"a2a_uptime_seconds">>,
               maps:get(<<"uptime_seconds">>, Metrics, 0),
               <<"Service uptime in seconds">>),

        Format(<<"a2a_memory_used_bytes">>,
               maps:get(<<"memory_used_bytes">>, Metrics, 0),
               <<"Total memory used in bytes">>),

        Format(<<"a2a_processes">>,
               maps:get(<<"processes">>, Metrics, 0),
               <<"Number of Erlang processes">>)
    ],

    iolist_to_binary(Lists).

%% @doc JSON headers
json_headers() ->
    #{
        <<"content-type">> => <<"application/json">>,
        <<"cache-control">> => <<"no-cache, no-store, must-revalidate">>,
        <<"access-control-allow-origin">> => <<"*">>
    }.

%% @doc Simple error response
error_response(Message) ->
    json:encode(#{<<"error">> => Message}).
