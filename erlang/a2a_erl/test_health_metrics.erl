#!/usr/bin/env escript
%% Simple test script for health handler request metrics

main(_) ->
    %% Add build paths - use local compiled version
    code:add_patha("/tmp/erl_tests2"),
    code:add_pathsa(filelib:wildcard("_build/default/lib/*/ebin")),

    io:format("Testing a2a_health_handler request metrics...~n~n"),

    %% Clean up any existing table
    catch ets:delete(a2a_request_metrics),

    %% Test 1: Initialize
    io:format("Test 1: init_metrics_table/0~n"),
    ok = a2a_health_handler:init_metrics_table(),
    io:format("  PASSED: Table initialized~n~n"),

    %% Test 2: Get initial count (should be 0)
    io:format("Test 2: get_request_count/0 initial~n"),
    0 = a2a_health_handler:get_request_count(),
    io:format("  PASSED: Initial count is 0~n~n"),

    %% Test 3: Increment
    io:format("Test 3: increment_request_count/0~n"),
    1 = a2a_health_handler:increment_request_count(),
    io:format("  PASSED: Increment returns 1~n"),
    1 = a2a_health_handler:get_request_count(),
    io:format("  PASSED: Count after increment is 1~n~n"),

    %% Test 4: Multiple increments
    io:format("Test 4: Multiple increments~n"),
    lists:foreach(fun(_) -> a2a_health_handler:increment_request_count() end, lists:seq(1, 5)),
    6 = a2a_health_handler:get_request_count(),
    io:format("  PASSED: Count after 5 more increments is 6~n~n"),

    %% Test 5: Reset
    io:format("Test 5: reset_request_count/0~n"),
    ok = a2a_health_handler:reset_request_count(),
    0 = a2a_health_handler:get_request_count(),
    io:format("  PASSED: Count after reset is 0~n~n"),

    %% Test 6: get_request_metrics
    io:format("Test 6: get_request_metrics/0~n"),
    a2a_health_handler:increment_request_count(),
    a2a_health_handler:increment_request_count(),
    a2a_health_handler:increment_request_count(),
    Metrics = a2a_health_handler:get_request_metrics(),
    3 = maps:get(<<"total_requests">>, Metrics),
    true = maps:is_key(<<"timestamp">>, Metrics),
    io:format("  PASSED: Metrics map contains correct data~n~n"),

    %% Test 7: Integration with get_metrics
    io:format("Test 7: Integration with get_metrics/0~n"),
    a2a_health_handler:reset_request_count(),
    lists:foreach(fun(_) -> a2a_health_handler:increment_request_count() end, lists:seq(1, 7)),
    AllMetrics = a2a_health_handler:get_metrics(),
    7 = maps:get(<<"requests_total">>, AllMetrics, undefined),
    io:format("  PASSED: get_metrics includes requests_total~n~n"),

    io:format("~n=== All tests passed! ===~n"),
    halt(0).
