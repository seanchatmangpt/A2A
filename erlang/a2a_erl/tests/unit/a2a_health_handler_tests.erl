%%%-------------------------------------------------------------------
%%% @doc A2A Health Handler Unit Tests
%%%
%%% Chicago School TDD test suite for the A2A health check handler.
%%% Tests cover request counting metrics with ETS-backed storage.
%%%
%%% Test Strategy:
%%% 1. RED: Write failing tests first
%%% 2. GREEN: Implement minimal code to pass
%%% 3. REFACTOR: Clean up while keeping tests passing
%%% @end
%%%-------------------------------------------------------------------

-module(a2a_health_handler_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%%====================================================================
%%% Test Fixtures
%%%====================================================================

request_count_test_() ->
    {foreach,
     fun setup_request_metrics/0,
     fun cleanup_request_metrics/1,
     [
         {"get_request_count/0 returns 0 when no requests counted", fun test_get_request_count_zero/0},
         {"increment_request_count/0 increases count by 1", fun test_increment_request_count/0},
         {"increment_request_count/0 increments multiple times", fun test_increment_request_count_multiple/0},
         {"get_request_count/0 returns accumulated count", fun test_get_request_count_accumulated/0},
         {"reset_request_count/0 resets counter to 0", fun test_reset_request_count/0},
         {"get_request_metrics/0 returns full metrics map", fun test_get_request_metrics/0},
         {"metrics table survives multiple calls", fun test_metrics_persistence/0}
     ]
    }.

%%%====================================================================
%%% Setup and Teardown
%%%====================================================================

setup_request_metrics() ->
    %% Clean up any existing table
    case catch ets:whereis(a2a_request_metrics) of
        Pid when is_pid(Pid) -> ets:delete(a2a_request_metrics);
        _ -> ok
    end,
    %% Create the metrics table for testing
    ets:new(a2a_request_metrics, [named_table, public, set]),
    %% Initialize with zero count
    ets:insert(a2a_request_metrics, {total_requests, 0}),
    ok.

cleanup_request_metrics(_State) ->
    %% Clean up the test table
    catch ets:delete(a2a_request_metrics),
    ok.

%%%====================================================================
%%% RED Phase: Failing Tests (written first)
%%%====================================================================

%% @doc Test: get_request_count returns 0 when no requests counted
test_get_request_count_zero() ->
    %% Ensure counter is at 0
    ets:insert(a2a_request_metrics, {total_requests, 0}),
    %% This should return 0
    Count = a2a_health_handler:get_request_count(),
    ?assertEqual(0, Count).

%% @doc Test: increment_request_count increases count by 1
test_increment_request_count() ->
    %% Start at 0
    ets:insert(a2a_request_metrics, {total_requests, 0}),
    %% Increment
    a2a_health_handler:increment_request_count(),
    %% Check result
    Count = a2a_health_handler:get_request_count(),
    ?assertEqual(1, Count).

%% @doc Test: increment_request_count increments multiple times
test_increment_request_count_multiple() ->
    %% Start at 0
    ets:insert(a2a_request_metrics, {total_requests, 0}),
    %% Increment 5 times
    lists:foreach(fun(_) -> a2a_health_handler:increment_request_count() end, lists:seq(1, 5)),
    %% Check result
    Count = a2a_health_handler:get_request_count(),
    ?assertEqual(5, Count).

%% @doc Test: get_request_count returns accumulated count
test_get_request_count_accumulated() ->
    %% Start at 10
    ets:insert(a2a_request_metrics, {total_requests, 10}),
    %% Increment twice
    a2a_health_handler:increment_request_count(),
    a2a_health_handler:increment_request_count(),
    %% Check result
    Count = a2a_health_handler:get_request_count(),
    ?assertEqual(12, Count).

%% @doc Test: reset_request_count resets counter to 0
test_reset_request_count() ->
    %% Start at 100
    ets:insert(a2a_request_metrics, {total_requests, 100}),
    %% Reset
    a2a_health_handler:reset_request_count(),
    %% Check result
    Count = a2a_health_handler:get_request_count(),
    ?assertEqual(0, Count).

%% @doc Test: get_request_metrics returns full metrics map
test_get_request_metrics() ->
    %% Set up known state
    ets:insert(a2a_request_metrics, {total_requests, 42}),
    %% Get metrics
    Metrics = a2a_health_handler:get_request_metrics(),
    ?assertMatch(#{<<"total_requests">> := 42}, Metrics),
    ?assert(maps:is_key(<<"total_requests">>, Metrics)),
    ?assertEqual(42, maps:get(<<"total_requests">>, Metrics)).

%% @doc Test: metrics table survives multiple calls
test_metrics_persistence() ->
    %% Start at 0
    ets:insert(a2a_request_metrics, {total_requests, 0}),
    %% Increment and check multiple times
    lists:foreach(fun(N) ->
        a2a_health_handler:increment_request_count(),
        Count = a2a_health_handler:get_request_count(),
        ?assertEqual(N, Count)
    end, lists:seq(1, 10)).

%%%====================================================================
%%% Initialization Tests
%%%====================================================================

init_test_() ->
    {foreach,
     fun setup_init/0,
     fun cleanup_init/1,
     [
         {"init_metrics_table/0 creates ETS table if not exists", fun test_init_metrics_table_creates/0},
         {"init_metrics_table/0 does not recreate existing table", fun test_init_metrics_table_existing/0}
     ]
    }.

setup_init() ->
    %% Clean up any existing table
    catch ets:delete(a2a_request_metrics),
    ok.

cleanup_init(_State) ->
    catch ets:delete(a2a_request_metrics),
    ok.

test_init_metrics_table_creates() ->
    %% Table should not exist
    ?assertEqual(undefined, ets:whereis(a2a_request_metrics)),
    %% Initialize
    a2a_health_handler:init_metrics_table(),
    %% Table should now exist
    ?assertNotEqual(undefined, ets:whereis(a2a_request_metrics)),
    %% Should have initial count
    [{total_requests, 0}] = ets:lookup(a2a_request_metrics, total_requests).

test_init_metrics_table_existing() ->
    %% Create table manually
    ets:new(a2a_request_metrics, [named_table, public, set]),
    ets:insert(a2a_request_metrics, {total_requests, 5}),
    %% Initialize (should not recreate)
    a2a_health_handler:init_metrics_table(),
    %% Original count should be preserved
    [{total_requests, 5}] = ets:lookup(a2a_request_metrics, total_requests).

%%%====================================================================
%%% Integration Tests
%%%====================================================================

integration_test_() ->
    {foreach,
     fun setup_integration/0,
     fun cleanup_integration/1,
     [
         {"get_metrics/0 includes request count", fun test_get_metrics_integration/0},
         {"full workflow: init, increment, get, reset", fun test_full_workflow/0}
     ]
    }.

setup_integration() ->
    catch ets:delete(a2a_request_metrics),
    a2a_health_handler:init_metrics_table(),
    ok.

cleanup_integration(_State) ->
    catch ets:delete(a2a_request_metrics),
    ok.

test_get_metrics_integration() ->
    %% Simulate some requests
    lists:foreach(fun(_) -> a2a_health_handler:increment_request_count() end, lists:seq(1, 7)),
    %% Get full metrics
    Metrics = a2a_health_handler:get_metrics(),
    %% Verify request count is included
    ?assert(maps:is_key(<<"requests_total">>, Metrics)),
    ?assertEqual(7, maps:get(<<"requests_total">>, Metrics)).

test_full_workflow() ->
    %% Start clean
    a2a_health_handler:reset_request_count(),
    ?assertEqual(0, a2a_health_handler:get_request_count()),
    %% Add some requests
    a2a_health_handler:increment_request_count(),
    a2a_health_handler:increment_request_count(),
    a2a_health_handler:increment_request_count(),
    ?assertEqual(3, a2a_health_handler:get_request_count()),
    %% Reset
    a2a_health_handler:reset_request_count(),
    ?assertEqual(0, a2a_health_handler:get_request_count()).
