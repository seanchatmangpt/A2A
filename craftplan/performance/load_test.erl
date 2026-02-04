%%% @doc Load Testing Tools
%%% Comprehensive load testing for Craftplan MCP + A2A systems

-module(load_test).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([run_test/2, run_stress_test/1, run_sustained_test/2]).
-export([get_test_results/0, clear_results/0]).
-export([generate_report/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TEST_DURATION, 300000). % 5 minutes
-define(DEFAULT_RAMP_UP, 30000). % 30 seconds
-define(DEFAULT_USERS, 10).
-define(DEFAULT_RATE, 10). % requests per second

-record(test_config, {
    name :: binary(),
    type :: stress | performance | endurance,
    duration :: integer(),
    ramp_up :: integer(),
    users :: integer(),
    rate :: integer(),
    targets :: list(binary()),
    scenarios :: list(map())
}).

-record(test_stats, {
    start_time :: integer(),
    end_time :: integer() | undefined,
    requests :: list(map()),
    errors :: list(map()),
    response_times :: list(integer()),
    throughput :: float(),
    users :: list(),
    status :: running | completed | failed
}).

-record(state, {
    config :: #test_config{},
    stats :: #test_stats{},
    active_users :: map(),
    timer :: reference() | undefined
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Run a basic load test
-spec run_test(binary(), integer()) -> ok.
run_test(TestName, Duration) ->
    Config = #test_config{
        name = TestName,
        type = performance,
        duration = Duration,
        ramp_up = ?DEFAULT_RAMP_UP,
        users = ?DEFAULT_USERS,
        rate = ?DEFAULT_RATE,
        targets = [<<"mcp">>, <<"a2a">>],
        scenarios = [
            #{
                name => <<"mcp_tool_calls">>,
                type => mcp,
                operation => <<"tools/call">>,
                tool_name => <<"customer_management">>,
                params => #{<<"operation">> => <<"list">>},
                weight => 0.7
            },
            #{
                name => <<"a2a_task_submission">>,
                type => a2a,
                operation => <<"task.submit">>,
                task_type => <<"inventory_management">>,
                params => #{<<"operation">> => <<"list">>},
                weight => 0.3
            }
        ]
    },

    gen_server:call(?SERVER, {run_test, Config}).

%% @doc Run a stress test
-spec run_stress_test(integer()) -> ok.
run_stress_test(UserCount) ->
    Config = #test_config{
        name = <<"stress_test">>,
        type = stress,
        duration = ?DEFAULT_TEST_DURATION,
        ramp_up = ?DEFAULT_RAMP_UP,
        users = UserCount,
        rate = UserCount * 2,
        targets = [<<"mcp">>, <<"a2a">>],
        scenarios = [
            #{
                name => <<"high_load_mcp">>,
                type => mcp,
                operation => <<"tools/call">>,
                tool_name => <<"customer_management">>,
                params => #{<<"operation">> => <<"list">>},
                weight => 0.8
            },
            #{
                name => <<"high_load_a2a">>,
                type => a2a,
                operation => <<"task.submit">>,
                task_type => <<"production_planning">>,
                params => #{<<"operation">> => <<"create">>},
                weight => 0.2
            }
        ]
    },

    gen_server:call(?SERVER, {run_test, Config}).

%% @doc Run a sustained endurance test
-spec run_sustained_test(binary(), integer()) -> ok.
run_sustained_test(TestName, Duration) ->
    Config = #test_config{
        name = TestName,
        type = endurance,
        duration = Duration,
        ramp_up = 0,
        users = 5,
        rate = 1,
        targets = [<<"mcp">>, <<"a2a">>],
        scenarios = [
            #{
                name => <<"sustained_load">>,
                type => mcp,
                operation => <<"tools/call">>,
                tool_name => <<"analytics">>,
                params => #{<<"report_type">> => <<"sales">>},
                weight => 1.0
            }
        ]
    },

    gen_server:call(?SERVER, {run_test, Config}).

%% @doc Get test results
-spec get_test_results() -> map().
get_test_results() ->
    gen_server:call(?SERVER, get_test_results).

%% @doc Clear test results
-spec clear_results() -> ok.
clear_results() ->
    gen_server:call(?SERVER, clear_results).

%% @doc Generate comprehensive test report
-spec generate_report(binary()) -> {ok, binary()} | {error, term()}.
generate_report(Format) ->
    gen_server:call(?SERVER, {generate_report, Format}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        config = undefined,
        stats = undefined,
        active_users = #{},
        timer = undefined
    },

    io:format("Load Testing System initialized~n"),
    {ok, State}.

handle_call({run_test, Config}, _From, State) ->
    case State#state.stats of
        undefined ->
            %% Start new test
            {ok, NewState} = start_test(Config, State),
            {reply, ok, NewState};
        #test_stats{status = completed} ->
            {reply, {error, test_completed}, State};
        #test_stats{status = running} ->
            {reply, {error, test_in_progress}, State}
    end;

handle_call(get_test_results, _From, State) ->
    case State#state.stats of
        undefined ->
            {reply, {error, no_test_running}, State};
        Stats ->
            Report = generate_test_report(Stats),
            {reply, {ok, Report}, State}
    end;

handle_call(clear_results, _From, State) ->
    NewState = State#state{
        config = undefined,
        stats = undefined,
        active_users = #{},
        timer = undefined
    },
    {reply, ok, NewState};

handle_call({generate_report, Format}, _From, State) ->
    case State#state.stats of
        undefined ->
            {reply, {error, no_test_results}, State};
        Stats ->
            Report = generate_formatted_report(Stats, Format),
            {reply, {ok, Report}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(start_ramp_up, State) ->
    RampUpTime = State#state.config#test_config.ramp_up,
    UserCount = State#state.config#test_config.users,
    RampUpStep = UserCount * 1000 / RampUpTime, % users per millisecond

    case ramp_up_users(State, UserCount, RampUpStep, os:system_time(millisecond)) of
        complete ->
            self() ! start_test_phase;
        {incomplete, UpdatedState} ->
            %% Schedule next ramp up step
            NextStep = erlang:send_after(100, self(), continue_ramp_up),
            {noreply, UpdatedState#state{timer = NextStep}}
    end;

handle_info(continue_ramp_up, State) ->
    RampUpTime = State#state.config#test_config.ramp_up,
    UserCount = State#state.config#test_config.users,
    RampUpStep = UserCount * 1000 / RampUpTime,

    case ramp_up_users(State, UserCount, RampUpStep, os:system_time(millisecond)) of
        complete ->
            self() ! start_test_phase;
        {incomplete, UpdatedState} ->
            NextStep = erlang:send_after(100, self(), continue_ramp_up),
            {noreply, UpdatedState#state{timer = NextStep}}
    end;

handle_info(start_test_phase, State) ->
    Start = os:system_time(millisecond),
    Duration = State#state.config#test_config.duration,

    %% Start test timer
    TestTimer = erlang:send_after(Duration, self(), end_test_phase),

    %% Start all users
    spawn_test_users(State#state.config, State#state.active_users),

    UpdatedStats = State#state.stats#{
        start_time = Start,
        status = running
    },

    {noreply, State#state{stats = UpdatedStats, timer = TestTimer}};

handle_info(end_test_phase, State) ->
    %% End all active users
    EndUsers = maps:map(fun(UserId, Pid) ->
        UserPid = whereis(UserId),
        case UserPid of
            undefined -> undefined;
            _ -> exit(UserPid, normal)
        end
    end, State#state.active_users),

    EndTime = os:system_time(millisecond),
    TestDuration = EndTime - State#state.stats#test_stats.start_time,

    UpdatedStats = State#state.stats#{
        end_time = EndTime,
        status = completed,
        throughput = calculate_throughput(State)
    },

    io:format("Load test completed in ~p ms~n", [TestDuration]),

    {noreply, State#state{stats = UpdatedStats, active_users = #{}, timer = undefined}};

handle_info({user_result, UserId, Result}, State) ->
    UpdatedStats = add_result(State#state.stats, UserId, Result),

    %% Remove user from active list
    NewActiveUsers = maps:remove(UserId, State#state.active_users),

    {noreply, State#state{stats = UpdatedStats, active_users = NewActiveUsers}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

start_test(Config, State) ->
    Now = os:system_time(millisecond),
    Stats = #test_stats{
        start_time = Now,
        requests = [],
        errors = [],
        response_times = [],
        status = running
    },

    io:format("Starting load test: ~s~n", [Config#test_config.name]),

    %% Start ramp up phase
    RampUpTimer = erlang:send_after(100, self(), start_ramp_up),

    NewState = State#state{
        config = Config,
        stats = Stats,
        timer = RampUpTimer
    },

    {ok, NewState}.

ramp_up_users(State, TargetUsers, StepRate, CurrentTime) ->
    ActiveUsers = maps:size(State#state.active_users),

    if
        ActiveUsers >= TargetUsers ->
            complete;
        true ->
            NewUsersToSpawn = min(trunc(StepRate * 100), TargetUsers - ActiveUsers),

            spawn_ramp_users(State, NewUsersToSpawn, CurrentTime),

            if
                ActiveUsers + NewUsersToSpawn >= TargetUsers ->
                    complete;
                true ->
                    {incomplete, State}
            end
    end.

spawn_ramp_users(State, Count, Timestamp) ->
    spawn_users(State#state.config, Count, Timestamp).

spawn_test_users(Config, ActiveUsers) ->
    lists:foreach(fun(UserId) ->
        case maps:is_key(UserId, ActiveUsers) of
            false ->
                spawn_user(Config, UserId);
            true ->
                ok
        end
    end, generate_user_ids(Config#test_config.users)).

spawn_user(Config, UserId) ->
    UserPid = spawn_link(?MODULE, user_loop, [Config, UserId]),
    register(UserId, UserPid),
    ok.

user_loop(Config, UserId) ->
    %% Get scenario based on weight
    Scenario = select_scenario(Config#test_config.scenarios),

    %% Execute scenario
    Result = execute_scenario(Scenario, UserId),

    %% Report result
    load_test ! {user_result, UserId, Result},

    %% Schedule next request
    case should_continue(Config, UserId) of
        true ->
            Delay = calculate_request_delay(Config#test_config.rate),
            timer:sleep(Delay),
            user_loop(Config, UserId);
        false ->
            ok
    end.

select_scenario(Scenarios) ->
    TotalWeight = lists:sum([S#{"weight"} || S <- Scenarios]),
    Random = rand:uniform() * TotalWeight,

    select_scenario_weighted(Scenarios, Random, 0).

select_scenario_weighted([Scenario | Rest], Random, Acc) ->
    Weight = maps:get(<<"weight">>, Scenario, 1.0),
    NewAcc = Acc + Weight,

    if
        Random =< NewAcc ->
            Scenario;
        true ->
            select_scenario_weighted(Rest, Random, NewAcc)
    end;
select_scenario_weighted([], _, _) ->
    undefined.

execute_scenario(Scenario, UserId) ->
    Start = os:system_time(microsecond),
    Type = maps:get(<<"type">>, Scenario),
    Operation = maps:get(<<"operation">>, Scenario),

    try
        Result = case Type of
            mcp ->
                execute_mcp_scenario(Scenario, UserId);
            a2a ->
                execute_a2a_scenario(Scenario, UserId);
            _ ->
                {error, unknown_scenario_type}
        end,

        End = os:system_time(microsecond),
        ResponseTime = End - Start,

        #{
            <<"user_id">> => UserId,
            <<"scenario">> => maps:get(<<"name">>, Scenario),
            <<"type">> => Type,
            <<"response_time">> => ResponseTime,
            <<"success">> => true,
            <<"timestamp">> => Start
        };
    catch
        Error:Reason ->
            End = os:system_time(microsecond),
            ResponseTime = End - Start,

            #{
                <<"user_id">> => UserId,
                <<"scenario">> => maps:get(<<"name">>, Scenario),
                <<"type">> => Type,
                <<"response_time">> => ResponseTime,
                <<"success">> => false,
                <<"error">> => term_to_binary({Error, Reason}),
                <<"timestamp">> => Start
            }
    end.

execute_mcp_scenario(Scenario, _UserId) ->
    ToolName = maps:get(<<"tool_name">>, Scenario),
    Params = maps:get(<<"params">>, Scenario),

    case craftplan_mcp_server_optimized:call_tool(ToolName, Params) of
        {ok, Result} ->
            Result;
        {error, Reason} ->
            erlang:error(Reason)
    end.

execute_a2a_scenario(Scenario, _UserId) ->
    TaskType = maps:get(<<"task_type">>, Scenario),
    Params = maps:get(<<"params">>, Scenario),

    case craftplan_a2a_server_optimized:submit_task(TaskType, Params) of
        {ok, TaskId} ->
            #{<<"task_id">> => TaskId};
        {error, Reason} ->
            erlang:error(Reason)
    end.

calculate_request_delay(Rate) ->
    if
        Rate > 0 ->
            1000 div Rate;
        true ->
            1000
    end.

should_continue(Config, UserId) ->
    case Config#test_config.type of
        endurance ->
            true;
        _ ->
            TestDuration = Config#test_config.duration,
            CurrentTime = os:system_time(millisecond),
            CurrentTime - TestDuration < Config#test_config.ramp_up + Config#test_config.duration
    end.

add_result(Stats, UserId, Result) ->
    #{
        <<"user_id">> := UserId,
        <<"response_time">> := ResponseTime,
        <<"success">> := Success,
        <<"timestamp">> := Timestamp,
        <<"scenario">> := Scenario
    } = Result,

    UpdatedRequests = [Result | Stats#test_stats.requests],
    UpdatedResponseTimes = [ResponseTime | Stats#test_stats.response_times],

    UpdatedErrors = case Success of
        true -> Stats#test_stats.errors;
        false -> [Result | Stats#test_stats.errors]
    end,

    Stats#test_stats{
        requests = UpdatedRequests,
        errors = UpdatedErrors,
        response_times = UpdatedResponseTimes
    }.

calculate_throughput(Stats) ->
    case Stats#test_stats.requests of
        [] -> 0.0;
        Requests ->
            Duration = case Stats#test_stats.end_time of
                undefined -> 0;
                EndTime -> EndTime - Stats#test_stats.start_time
            end,

            if
                Duration > 0 ->
                    length(Requests) / (Duration / 1000.0);
                true ->
                    0.0
            end
    end.

generate_test_report(Stats) ->
    #{
        <<"test_duration">> => case Stats#test_stats.end_time of
            undefined -> 0;
            EndTime -> EndTime - Stats#test_stats.start_time
        end,
        <<"total_requests">> => length(Stats#test_stats.requests),
        <<"total_errors">> => length(Stats#test_stats.errors),
        <<"error_rate">> => calculate_error_rate(Stats),
        <<"avg_response_time">> => calculate_avg_response_time(Stats),
        <<"max_response_time">> => calculate_max_response_time(Stats),
        <<"min_response_time">> => calculate_min_response_time(Stats),
        <<"percentiles">> => calculate_percentiles(Stats),
        <<"throughput">> => Stats#test_stats.throughput,
        <<"requests_per_second">> => calculate_requests_per_second(Stats),
        <<"status">> => Stats#test_stats.status
    }.

generate_formatted_report(Stats, Format) ->
    ReportData = generate_test_report(Stats),

    case Format of
        <<"json">> ->
            jiffy:encode(ReportData);
        <<"text">> ->
            format_text_report(ReportData);
        <<"csv">> ->
            format_csv_report(ReportData);
        _ ->
            jiffy:encode(ReportData)
    end.

calculate_error_rate(Stats) ->
    Total = length(Stats#test_stats.requests),
    Errors = length(Stats#test_stats.errors),

    case Total > 0 of
        true -> Errors / Total;
        false -> 0.0
    end.

calculate_avg_response_time(Stats) ->
    Times = Stats#test_stats.response_times,
    case Times of
        [] -> 0;
        _ -> lists:sum(Times) / length(Times)
    end.

calculate_max_response_time(Stats) ->
    case Stats#test_stats.response_times of
        [] -> 0;
        Times -> lists:max(Times)
    end.

calculate_min_response_time(Stats) ->
    case Stats#test_stats.response_times of
        [] -> 0;
        Times -> lists:min(Times)
    end.

calculate_percentiles(Stats) ->
    Times = lists:sort(Stats#test_stats.response_times),
    Length = length(Times),

    #{
        <<"p50">> => get_percentile(Times, 0.5),
        <<"p90">> => get_percentile(Times, 0.9),
        <<"p95">> => get_percentile(Times, 0.95),
        <<"p99">> => get_percentile(Times, 0.99)
    }.

get_percentile(Times, Percentile) ->
    Length = length(Times),
    Index = trunc(Percentile * Length),

    case Index > 0 andalso Index =< Length of
        true -> lists:nth(Index, Times);
        false -> 0
    end.

calculate_requests_per_second(Stats) ->
    Duration = case Stats#test_stats.end_time of
        undefined -> 0;
        EndTime -> EndTime - Stats#test_stats.start_time
    end,

    case Duration > 0 of
        true -> length(Stats#test_stats.requests) / (Duration / 1000.0);
        false -> 0
    end.

format_text_report(ReportData) ->
    io_lib:format(
        "Load Test Report~n"
        "================~n"
        "Total Requests: ~p~n"
        "Total Errors: ~p~n"
        "Error Rate: ~.2f%~n"
        "Avg Response Time: ~.2f ms~n"
        "Max Response Time: ~.2f ms~n"
        "Min Response Time: ~.2f ms~n"
        "Throughput: ~.2f req/s~n"
        "Status: ~p~n",
        [
            maps:get(<<"total_requests">>, ReportData),
            maps:get(<<"total_errors">>, ReportData),
            maps:get(<<"error_rate">>, ReportData) * 100,
            maps:get(<<"avg_response_time">>, ReportData),
            maps:get(<<"max_response_time">>, ReportData),
            maps:get(<<"min_response_time">>, ReportData),
            maps:get(<<"throughput">>, ReportData),
            maps:get(<<"status">>, ReportData)
        ]
    ).

format_csv_report(ReportData) ->
    io_lib:format(
        "metric,value~n"
        "total_requests,~p~n"
        "total_errors,~p~n"
        "error_rate,~.2f~n"
        "avg_response_time,~.2f~n"
        "max_response_time,~.2f~n"
        "min_response_time,~.2f~n"
        "throughput,~.2f~n",
        [
            maps:get(<<"total_requests">>, ReportData),
            maps:get(<<"total_errors">>, ReportData),
            maps:get(<<"error_rate">>, ReportData),
            maps:get(<<"avg_response_time">>, ReportData),
            maps:get(<<"max_response_time">>, ReportData),
            maps:get(<<"min_response_time">>, ReportData),
            maps:get(<<"throughput">>, ReportData)
        ]
    ).

generate_user_ids(Count) ->
    generate_user_ids(Count, 1, []).

generate_user_ids(Count, Current, Acc) when Current =< Count ->
    UserId = iolist_to_binary(["user_", integer_to_list(Current)]),
    generate_user_ids(Count, Current + 1, [UserId | Acc]);
generate_user_ids(_, _, Acc) ->
    Acc.