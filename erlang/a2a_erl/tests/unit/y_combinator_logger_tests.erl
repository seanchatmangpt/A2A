%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for Y Combinator Logger Module
%%%
%%% Tests the logging and telemetry functionality for the Y Combinator demo.
%%% @end
%%%-------------------------------------------------------------------

-module(y_combinator_logger_tests).
-author("A2A Team").

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

logger_setup() ->
    {ok, Pid} = y_combinator_logger:start_link(),
    Pid.

logger_cleanup(_Pid) ->
    y_combinator_logger:stop(),
    ok.

%%====================================================================
%% Generator Tests
%%====================================================================

logger_test_() ->
    {foreach,
        fun logger_setup/0,
        fun logger_cleanup/1,
        [
            fun test_log_event/1,
            fun test_combination_logging/1,
            fun test_test_lifecycle_logging/1,
            fun test_demo_logging/1,
            fun test_metrics/1,
            fun test_metrics_dashboard/1,
            fun test_export_logs/1,
            fun test_log_summary/1
        ]
    }.

%%====================================================================
%% Individual Test Cases
%%====================================================================

%% @doc Test basic event logging
test_log_event(_Pid) ->
    fun() ->
        ?assertEqual(ok, y_combinator_logger:log_event(info, test, <<"Test message">>, #{})),
        ?assertEqual(ok, y_combinator_logger:log_event(warning, test, <<"Warning message">>, #{})),
        ?assertEqual(ok, y_combinator_logger:log_event(error, test, <<"Error message">>, #{})),
        ?assertEqual(ok, y_combinator_logger:log_event(debug, test, <<"Debug message">>, #{}))
    end.

%% @doc Test combination generation logging
test_combination_logging(_Pid) ->
    fun() ->
        Combination = [basic_sequential, parallel_split],
        ?assertEqual(ok, y_combinator_logger:log_combination_generated(Combination)),
        ?assertEqual(ok, y_combinator_logger:log_combination_generated(Combination, #{test => metadata}))
    end.

%% @doc Test lifecycle logging
test_test_lifecycle_logging(_Pid) ->
    fun() ->
        TestID = <<"test_123">>,
        ?assertEqual(ok, y_combinator_logger:log_test_started(TestID)),
        ?assertEqual(ok, y_combinator_logger:log_test_completed(TestID, #{status => pass})),
        ?assertEqual(ok, y_combinator_logger:log_test_failed(TestID, timeout))
    end.

%% @doc Test demo logging
test_demo_logging(_Pid) ->
    fun() ->
        Patterns = [basic_sequential, parallel_split, exclusive_choice],
        ?assertEqual(ok, y_combinator_logger:log_demo_started(<<"Quick Demo">>, Patterns)),
        ?assertEqual(ok, y_combinator_logger:log_demo_completed(<<"Quick Demo">>, 10, 5000))
    end.

%% @doc Test metrics collection
test_metrics(_Pid) ->
    fun() ->
        {ok, Metrics} = y_combinator_logger:get_metrics(),
        ?assert(is_map(Metrics)),
        ?assert(maps:is_key(total_combinations_generated, Metrics)),
        ?assert(maps:is_key(tests_run, Metrics)),
        ?assert(maps:is_key(tests_passed, Metrics)),
        ?assert(maps:is_key(tests_failed, Metrics)),

        %% Test category-specific metrics
        {ok, TestsMetric} = y_combinator_logger:get_metrics(tests_run),
        ?assert(is_integer(TestsMetric))
    end.

%% @doc Test metrics dashboard
test_metrics_dashboard(_Pid) ->
    fun() ->
        ?assertEqual(ok, y_combinator_logger:metrics_dashboard(console)),

        %% Test return format
        DashboardData = y_combinator_logger:metrics_dashboard(return),
        ?assert(is_map(DashboardData))
    end.

%% @doc Test log export functionality
test_export_logs(_Pid) ->
    fun() ->
        %% JSON export
        {ok, JSONFile} = y_combinator_logger:export_logs(json),
        ?assert(is_list(JSONFile)),
        ?assert(filelib:is_file(JSONFile)),

        %% CSV export
        {ok, CSVFile} = y_combinator_logger:export_logs(csv),
        ?assert(is_list(CSVFile)),
        ?assert(filelib:is_file(CSVFile)),

        %% Prometheus export
        PrometheusOutput = y_combinator_logger:export_prometheus(),
        ?assert(is_binary(PrometheusOutput)),
        ?assert(PrometheusOutput =/= <<>>)
    end.

%% @doc Test log summary
test_log_summary(_Pid) ->
    fun() ->
        %% Add some logs first
        y_combinator_logger:log_event(info, test, <<"Test 1">>, #{}),
        y_combinator_logger:log_event(warning, test, <<"Test 2">>, #{}),
        y_combinator_logger:log_event(error, test, <<"Test 3">>, #{}),

        {ok, Summary} = y_combinator_logger:get_log_summary(),
        ?assert(is_map(Summary)),
        ?assert(maps:is_key(total_entries, Summary)),
        ?assert(maps:is_key(by_level, Summary)),
        ?assert(maps:is_key(by_type, Summary))
    end.

%%====================================================================
%% Integration Tests
%%====================================================================

%% @doc Test full demo workflow with logging
integration_test_() ->
    {setup,
        fun() ->
            {ok, Pid} = y_combinator_logger:start_link(),
            Pid
        end,
        fun(_Pid) ->
            y_combinator_logger:stop()
        end,
        fun(_Pid) ->
            [
                fun() ->
                    %% Simulate a demo run
                    Patterns = [basic_sequential, parallel_split],
                    DemoName = <<"Test Demo">>,

                    %% Log demo start
                    ?assertEqual(ok, y_combinator_logger:log_demo_started(DemoName, Patterns)),

                    %% Simulate combination generation
                    Combinations = [
                        [basic_sequential, basic_sequential],
                        [basic_sequential, parallel_split],
                        [parallel_split, basic_sequential],
                        [parallel_split, parallel_split]
                    ],
                    lists:foreach(fun(C) ->
                        y_combinator_logger:log_combination_generated(C)
                    end, Combinations),

                    %% Simulate tests
                    lists:foreach(fun(N) ->
                        TestID = list_to_binary(io_lib:format("test_~p", [N])),
                        y_combinator_logger:log_test_started(TestID),
                        case N rem 4 of
                            0 -> y_combinator_logger:log_test_failed(TestID, timeout);
                            _ -> y_combinator_logger:log_test_completed(TestID, #{status => pass})
                        end
                    end, lists:seq(1, 10)),

                    %% Log demo completion
                    ?assertEqual(ok, y_combinator_logger:log_demo_completed(DemoName, 4, 2500)),

                    %% Verify metrics
                    {ok, Metrics} = y_combinator_logger:get_metrics(),
                    ?assertEqual(4, maps:get(total_combinations_generated, Metrics)),
                    ?assertEqual(10, maps:get(tests_run, Metrics))
                end
            ]
        end
    }.

%% @doc Test metrics reset
metrics_reset_test_() ->
    {setup,
        fun() ->
            {ok, Pid} = y_combinator_logger:start_link(),
            %% Add some metrics
            y_combinator_logger:log_demo_started(<<"Test">>, [basic_sequential]),
            y_combinator_logger:log_combination_generated([basic_sequential]),
            Pid
        end,
        fun(_Pid) ->
            y_combinator_logger:stop()
        end,
        fun(_Pid) ->
            [
                fun() ->
                    %% Reset metrics
                    ?assertEqual(ok, y_combinator_logger:reset_metrics()),

                    %% Verify reset
                    {ok, Metrics} = y_combinator_logger:get_metrics(),
                    ?assertEqual(0, maps:get(total_combinations_generated, Metrics))
                end
            ]
        end
    }.

%% @doc Test counter and gauge operations
counter_gauge_test_() ->
    {setup,
        fun logger_setup/0,
        fun logger_cleanup/1,
        [
            fun(_Pid) ->
                fun() ->
                    %% Test counter increments
                    ?assertEqual(ok, y_combinator_logger:increment_counter(test_counter)),
                    ?assertEqual(ok, y_combinator_logger:increment_counter(test_counter, 5)),

                    %% Test gauge setting
                    ?assertEqual(ok, y_combinator_logger:set_gauge(test_gauge, 42)),
                    ?assertEqual(ok, y_combinator_logger:set_gauge(test_gauge, 3.14)),

                    %% Test timing recording
                    ?assertEqual(ok, y_combinator_logger:record_timing(test_timing, 100)),
                    ?assertEqual(ok, y_combinator_logger:record_timing(test_timing, 250))
                end
            end
        ]
    }.

%%====================================================================
%% Property-Based Tests
%%====================================================================

prop_log_message_roundtrip() ->
    ?FORALL(Type, oneof([combination, test, demo, system, performance]),
        begin
            ok = y_combinator_logger:start_link(),
            Result = y_combinator_logger:log_event(info, Type, <<"Test">>, #{}),
            y_combinator_logger:stop(),
            Result =:= ok
        end).

prop_metrics_non_negative() ->
    ?FORALL(_Ops, list(oneof([
        {log_combination, [basic_sequential, parallel_split]},
        {log_demo, <<"Demo">>, [basic_sequential]},
        {log_test_start, <<"Test1">>},
        {log_test_pass, <<"Test1">>},
        {log_test_fail, <<"Test1">>, timeout}
    ])),
        begin
            {ok, _Pid} = y_combinator_logger:start_link(),
            lists:foreach(fun
                ({log_combination, Combo}) ->
                    y_combinator_logger:log_combination_generated(Combo);
                ({log_demo, Name, Pats}) ->
                    y_combinator_logger:log_demo_started(Name, Pats),
                    y_combinator_logger:log_demo_completed(Name, 1, 100);
                ({log_test_start, ID}) ->
                    y_combinator_logger:log_test_started(ID);
                ({log_test_pass, ID}) ->
                    y_combinator_logger:log_test_completed(ID, #{status => pass});
                ({log_test_fail, ID, Reason}) ->
                    y_combinator_logger:log_test_failed(ID, Reason)
            end, _Ops),

            {ok, Metrics} = y_combinator_logger:get_metrics(),
            y_combinator_logger:stop(),

            %% All metrics should be non-negative
            maps:get(total_combinations_generated, Metrics, 0) >= 0 andalso
            maps:get(tests_run, Metrics, 0) >= 0 andalso
            maps:get(tests_passed, Metrics, 0) >= 0 andalso
            maps:get(tests_failed, Metrics, 0) >= 0
        end).
