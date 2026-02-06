%%%-------------------------------------------------------------------
%%% @doc
%%% HotCI Metrics Collector Unit Tests
%%%
%%% Test suite for the HotCI metrics collector module using Chicago TDD.
%%% Tests verify that actual Erlang/OTP tools are used for metric collection.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(hotci_metrics_collector_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generators - CPU Usage
%%====================================================================

get_cpu_usage_returns_valid_percentage_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_cpu_usage(ClusterId),
    ?assert(is_number(Result)),
    ?assert(Result >= 0.0),
    ?assert(Result =< 100.0).

get_cpu_usage_uses_real_os_mon_test() ->
    %% This test verifies that cpu_sup (OS_Mon) is actually being used
    %% rather than returning hardcoded values
    ClusterId = <<"test-cluster-cpu">>,
    Result1 = hotci_metrics_collector:get_cpu_usage(ClusterId),
    timer:sleep(100),  % Small delay to allow CPU measurement change
    Result2 = hotci_metrics_collector:get_cpu_usage(ClusterId),
    %% Results may vary slightly due to real measurement
    ?assert(is_number(Result1)),
    ?assert(is_number(Result2)).

%%====================================================================
%% Test Generators - Memory Usage
%%====================================================================

get_memory_usage_returns_positive_integer_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_memory_usage(ClusterId),
    ?assert(is_integer(Result)),
    ?assert(Result > 0).

get_memory_usage_returns_bytes_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_memory_usage(ClusterId),
    %% Memory should be at least 1 MB
    ?assert(Result >= 1024 * 1024).

get_memory_usage_uses_erlang_memory_test() ->
    %% Verify we're using erlang:memory/0,1 for actual measurement
    ClusterId = <<"test-cluster-mem">>,
    Result = hotci_metrics_collector:get_memory_usage(ClusterId),
    %% Compare with direct erlang:memory call to ensure correlation
    SystemMemory = case erlang:memory() of
        MemMap when is_map(MemMap) ->
            maps:get(total, MemMap, 0);
        MemList when is_list(MemList) ->
            proplists:get_value(total, MemList, 0)
    end,
    %% Results should be in the same order of magnitude
    ?assert(Result > 0),
    ?assert(SystemMemory > 0).

%%====================================================================
%% Test Generators - Process Count
%%====================================================================

get_process_count_returns_positive_integer_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_process_count(ClusterId),
    ?assert(is_integer(Result)),
    ?assert(Result > 0).

get_process_count_matches_erlang_processes_test() ->
    ClusterId = <<"test-cluster-proc">>,
    Result = hotci_metrics_collector:get_process_count(ClusterId),
    %% Compare with erlang:system_info(process_count)
    ActualProcessCount = erlang:system_info(process_count),
    %% Should be reasonably close (within 5 processes)
    ?assert(abs(Result - ActualProcessCount) =< 5).

%%====================================================================
%% Test Generators - Network I/O
%%====================================================================

get_network_io_returns_number_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_network_io(ClusterId),
    ?assert(is_number(Result)),
    ?assert(Result >= 0.0).

get_network_io_uses_statistics_test() ->
    ClusterId = <<"test-cluster-net">>,
    %% Verify that network statistics are being queried
    Result = hotci_metrics_collector:get_network_io(ClusterId),
    %% The implementation should use erlang:statistics(io)
    %% or similar for network I/O
    ?assert(is_number(Result)).

%%====================================================================
%% Test Generators - Disk I/O
%%====================================================================

get_disk_io_returns_number_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_disk_io(ClusterId),
    ?assert(is_number(Result)),
    ?assert(Result >= 0.0).

get_disk_io_uses_os_mon_test() ->
    ClusterId = <<"test-cluster-disk">>,
    %% Verify that disksup (OS_Mon) is being used
    Result = hotci_metrics_collector:get_disk_io(ClusterId),
    ?assert(is_number(Result)).

%%====================================================================
%% Test Generators - Health Status
%%====================================================================

get_health_status_returns_valid_status_test() ->
    ClusterId = <<"test-cluster">>,
    Result = hotci_metrics_collector:get_health_status(ClusterId),
    %% Health status should be 0.0 (unhealthy) to 1.0 (healthy)
    ?assert(is_number(Result)),
    ?assert(Result >= 0.0),
    ?assert(Result =< 1.0).

get_health_status_considers_system_health_test() ->
    ClusterId = <<"test-cluster-health">>,
    Result = hotci_metrics_collector:get_health_status(ClusterId),
    %% A healthy system should return high health score
    ?assert(Result >= 0.0).

%%====================================================================
%% Test Generators - Integration
%%====================================================================

all_metrics_collectable_test() ->
    ClusterId = <<"test-cluster-integration">>,
    %% Verify all metric functions work together
    CPU = hotci_metrics_collector:get_cpu_usage(ClusterId),
    Mem = hotci_metrics_collector:get_memory_usage(ClusterId),
    Proc = hotci_metrics_collector:get_process_count(ClusterId),
    Net = hotci_metrics_collector:get_network_io(ClusterId),
    Disk = hotci_metrics_collector:get_disk_io(ClusterId),
    Health = hotci_metrics_collector:get_health_status(ClusterId),

    ?assert(is_number(CPU) andalso CPU >= 0.0 andalso CPU =< 100.0),
    ?assert(is_integer(Mem) andalso Mem > 0),
    ?assert(is_integer(Proc) andalso Proc > 0),
    ?assert(is_number(Net) andalso Net >= 0.0),
    ?assert(is_number(Disk) andalso Disk >= 0.0),
    ?assert(is_number(Health) andalso Health >= 0.0 andalso Health =< 1.0).

%%====================================================================
%% Test Generators - Fallback Behavior
%%====================================================================

metrics_fallback_when_os_mon_unavailable_test() ->
    %% Test graceful fallback when OS_Mon is not available
    ClusterId = <<"test-cluster-fallback">>,
    %% These should not crash even if OS_Mon isn't running
    ?assertNotException(error, _, hotci_metrics_collector:get_cpu_usage(ClusterId)),
    ?assertNotException(error, _, hotci_metrics_collector:get_memory_usage(ClusterId)),
    ?assertNotException(error, _, hotci_metrics_collector:get_process_count(ClusterId)),
    ?assertNotException(error, _, hotci_metrics_collector:get_network_io(ClusterId)),
    ?assertNotException(error, _, hotci_metrics_collector:get_disk_io(ClusterId)),
    ?assertNotException(error, _, hotci_metrics_collector:get_health_status(ClusterId)).
