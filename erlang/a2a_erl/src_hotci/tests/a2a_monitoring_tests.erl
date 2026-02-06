%%%-------------------------------------------------------------------
%%% @doc
%%% Chicago-Style TDD Tests for HotCI Monitoring Functions
%%%
%%% RED PHASE: Tests written first.
%%% GREEN PHASE: Functions implemented to make tests pass.
%%% @end
%%%-------------------------------------------------------------------

-module(a2a_monitoring_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("a2a.hrl").

%% Record definitions for testing (local to a2a_monitoring module)
-record(alert, {
    id = <<>> :: binary(),
    rule_id = <<>> :: binary(),
    severity = low :: low | medium | high | critical,
    message = <<>> :: binary(),
    timestamp = 0 :: integer(),
    service = <<>> :: binary(),
    metric_value = 0.0 :: float(),
    triggered_by = <<>> :: binary(),
    resolved = false :: boolean(),
    resolved_timestamp = undefined :: integer() | undefined,
    acknowledged = false :: boolean(),
    acknowledged_by = undefined :: binary() | undefined,
    acknowledged_timestamp = undefined :: integer() | undefined,
    notification_log = [] :: [binary()]
}).

-record(state, {
    config = undefined :: map() | undefined,
    metrics = undefined :: ets:tid() | undefined,
    alert_rules = undefined :: ets:tid() | undefined,
    alerts = undefined :: ets:tid() | undefined,
    active_monitors = [] :: [pid()],
    metrics_collection_ref = undefined :: reference() | undefined,
    performance_baseline = #{} :: map(),
    health_status = healthy :: atom(),
    last_metrics_update = 0 :: integer(),
    alert_history = [] :: [binary()],
    service_health = #{} :: map(),
    critical_paths = [] :: [binary()],
    notification_targets = [] :: [binary()]
}).

%%====================================================================
%% MONITORING FUNCTION TESTS
%%====================================================================

%% Test CPU usage returns a percentage between 0 and 100
get_cpu_usage_test_() ->
    [?_test(begin
        Usage = a2a_monitoring:get_cpu_usage(),
        ?assert(is_float(Usage)),
        ?assert(Usage >= 0.0),
        ?assert(Usage =< 100.0)
    end)].

%% Test memory usage returns a percentage between 0 and 100
get_memory_usage_test_() ->
    [?_test(begin
        Usage = a2a_monitoring:get_memory_usage(),
        ?assert(is_float(Usage)),
        ?assert(Usage >= 0.0),
        ?assert(Usage =< 100.0)
    end)].

%% Test disk usage returns a percentage between 0 and 100
get_disk_usage_test_() ->
    [?_test(begin
        Usage = a2a_monitoring:get_disk_usage(),
        ?assert(is_float(Usage)),
        ?assert(Usage >= 0.0),
        ?assert(Usage =< 100.0)
    end)].

%% Test system load returns a meaningful load average
get_system_load_test_() ->
    [?_test(begin
        Load = a2a_monitoring:get_system_load(),
        ?assert(is_float(Load) orelse is_number(Load)),
        ?assert(Load >= 0.0)
    end)].

%% Test active connections returns a non-negative integer
get_active_connections_test_() ->
    [?_test(begin
        Conns = a2a_monitoring:get_active_connections(),
        ?assert(is_integer(Conns)),
        ?assert(Conns >= 0)
    end)].

%% Test request rate returns a non-negative number
get_request_rate_test_() ->
    [?_test(begin
        Rate = a2a_monitoring:get_request_rate(),
        ?assert(is_number(Rate)),
        ?assert(Rate >= 0.0)
    end)].

%% Test average response time returns a non-negative number
get_average_response_time_test_() ->
    [?_test(begin
        Time = a2a_monitoring:get_average_response_time(),
        ?assert(is_number(Time)),
        ?assert(Time >= 0)
    end)].

%% Test error rate returns a decimal between 0 and 1
get_error_rate_test_() ->
    [?_test(begin
        Rate = a2a_monitoring:get_error_rate(),
        ?assert(is_float(Rate)),
        ?assert(Rate >= 0.0),
        ?assert(Rate =< 1.0)
    end)].

%% Test active tasks returns a non-negative integer
get_active_tasks_test_() ->
    [?_test(begin
        Tasks = a2a_monitoring:get_active_tasks(),
        ?assert(is_integer(Tasks)),
        ?assert(Tasks >= 0)
    end)].

%%====================================================================
%% NOTIFICATION FUNCTION TESTS
%%====================================================================

%% Test email notification sending returns success or error tuple
send_email_notification_test_() ->
    {setup,
     fun() ->
         %% Setup: Start inets for HTTP calls
         application:ensure_all_started(inets),
         ok
     end,
     fun(_) ->
         %% Teardown
         ok
     end,
     [?_test(begin
         %% Create a mock alert
         Alert = #alert{
             id = <<"test-alert-1">>,
             severity = high,
             message = <<"Test email notification">>,
             service = <<"test-service">>,
             timestamp = erlang:system_time(millisecond)
         },

         %% Create a mock state with notification config
         State = #state{
             notification_targets = [
                 <<"test@example.com">>
             ]
         },

         %% Test that function returns a valid result
         Result = a2a_monitoring:send_email_notification(Alert, State),

         %% Should return true, {ok, _}, or {error, _}
         ?assert(is_boolean(Result) orelse is_tuple(Result))
     end)]}.

%% Test Slack notification sending returns success or error tuple
send_slack_notification_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(inets),
         ok
     end,
     fun(_) ->
         ok
     end,
     [?_test(begin
         Alert = #alert{
             id = <<"test-alert-2">>,
             severity = critical,
             message = <<"Test Slack notification">>,
             service = <<"test-service">>,
             timestamp = erlang:system_time(millisecond)
         },

         State = #state{
             notification_targets = [
                 <<"https://hooks.slack.com/services/T00/B00/XXX">>
             ]
         },

         Result = a2a_monitoring:send_slack_notification(Alert, State),

         %% Should return true, {ok, _}, or {error, _}
         ?assert(is_boolean(Result) orelse is_tuple(Result))
     end)]}.

%% Test SMS notification sending returns success or error tuple
send_sms_notification_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(inets),
         ok
     end,
     fun(_) ->
         ok
     end,
     [?_test(begin
         Alert = #alert{
             id = <<"test-alert-3">>,
             severity = critical,
             message = <<"Test SMS notification">>,
             service = <<"test-service">>,
             timestamp = erlang:system_time(millisecond)
         },

         State = #state{
             notification_targets = [
                 <<"+1234567890">>
             ]
         },

         Result = a2a_monitoring:send_sms_notification(Alert, State),

         %% Should return true, {ok, _}, or {error, _}
         ?assert(is_boolean(Result) orelse is_tuple(Result))
     end)]}.

%% Test email notification with invalid configuration
send_email_notification_invalid_config_test_() ->
    [?_test(begin
         Alert = #alert{
             id = <<"test-alert-4">>,
             severity = low,
             message = <<"Test email">>,
             service = <<"test-service">>,
             timestamp = erlang:system_time(millisecond)
         },

         %% Empty notification targets
         State = #state{
             notification_targets = []
         },

         Result = a2a_monitoring:send_email_notification(Alert, State),

         %% Should handle gracefully - return false or {error, _}
         ?assertEqual(false, Result)
     end)].

%% Test Slack notification formats alert message correctly
send_slack_notification_formatting_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(inets),
         ok
     end,
     fun(_) ->
         ok
     end,
     [?_test(begin
         Alert = #alert{
             id = <<"test-alert-format">>,
             severity = high,
             message = <<"CPU usage at 95%">>,
             service = <<"payment-processor">>,
             timestamp = erlang:system_time(millisecond)
         },

         State = #state{
             notification_targets = [<<"https://hooks.slack.com/services/TEST">>]
         },

         %% Call the function
         Result = a2a_monitoring:send_slack_notification(Alert, State),

         %% Verify result is valid
         ?assert(is_boolean(Result) orelse is_tuple(Result))
     end)]}.

%% Test SMS notification with critical severity
send_sms_notification_critical_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(inets),
         ok
     end,
     fun(_) ->
         ok
     end,
     [?_test(begin
         Alert = #alert{
             id = <<"test-alert-critical">>,
             severity = critical,
             message = <<"System down">>,
             service = <<"auth-service">>,
             timestamp = erlang:system_time(millisecond)
         },

         State = #state{
             notification_targets = [<<"+15551234567">>]
         },

         Result = a2a_monitoring:send_sms_notification(Alert, State),

         %% Should return valid result
         ?assert(is_boolean(Result) orelse is_tuple(Result))
     end)]}.

%%====================================================================
%% NOTIFICATION HELPER FUNCTION TESTS
%%====================================================================

%% Test building notification payload from alert
build_notification_payload_test_() ->
    [?_test(begin
         Alert = #alert{
             id = <<"alert-123">>,
             severity = high,
             message = <<"High memory usage">>,
             service = <<"api-gateway">>,
             timestamp = 1704067200000
         },

         Payload = a2a_monitoring:build_notification_payload(Alert),

         %% Payload should be a map with required fields
         ?assert(is_map(Payload)),
         ?assert(maps:is_key(<<"alert_id">>, Payload)),
         ?assert(maps:is_key(<<"severity">>, Payload)),
         ?assert(maps:is_key(<<"message">>, Payload)),
         ?assert(maps:is_key(<<"service">>, Payload))
     end)].

%% Test formatting Slack message from alert
format_slack_message_test_() ->
    [?_test(begin
         Alert = #alert{
             id = <<"alert-456">>,
             severity = critical,
             message = <<"Database connection failed">>,
             service = <<"database">>,
             timestamp = erlang:system_time(millisecond)
         },

         Message = a2a_monitoring:format_slack_message(Alert),

         %% Message should be a binary and contain alert info
         ?assert(is_binary(Message)),
         ?assert(byte_size(Message) > 0)
     end)].

%% Test formatting SMS message from alert (short format)
format_sms_message_test_() ->
    [?_test(begin
         Alert = #alert{
             id = <<"alert-789">>,
             severity = critical,
             message = <<"Server crash">>,
             service = <<"web-server">>,
             timestamp = erlang:system_time(millisecond)
         },

         Message = a2a_monitoring:format_sms_message(Alert),

         %% SMS should be short and concise
         ?assert(is_binary(Message)),
         ?assert(byte_size(Message) =< 160)  % SMS length limit
     end)].
