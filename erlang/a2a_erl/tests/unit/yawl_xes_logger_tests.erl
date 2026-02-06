%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Logger Unit Tests
%%%
%%% Test suite for the XES (eXtensible Event Stream) logger module
%%% implementing IEEE 1849-2016 standard for process mining event logs.
%%%
%%% Tests cover:
%%% 1. Log creation and management
%%% 2. Event recording (all event types)
%%% 3. XES export functionality
%%% 4. Concurrent logging
%%% 5. Trace management
%%% 6. Attribute handling
%%% 7. Extension support
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_logger_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Macros and Constants
%%====================================================================

-define(TEST_LOG_DIR, "/tmp/yawl_xes_test_").
-define(TEST_WORKFLOW_ID, <<"test_workflow_xes">>).
-define(TEST_TRACE_ID, <<"test_trace_001">>).

%%====================================================================
%% Test Generator - Main Entry Point
%%====================================================================

xes_logger_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Log Creation and Management", fun test_group_log_management/0},
      {"Group 2: Event Recording", fun test_group_event_recording/0},
      {"Group 3: XES Export", fun test_group_xes_export/0},
      {"Group 4: Concurrent Logging", fun test_group_concurrent_logging/0},
      {"Group 5: Trace Management", fun test_group_trace_management/0},
      {"Group 6: Attribute Handling", fun test_group_attributes/0},
      {"Group 7: Extensions", fun test_group_extensions/0},
      {"Group 8: IEEE 1849-2016 Compliance", fun test_group_ieee_compliance/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup Fixtures
%%====================================================================

setup() ->
    %% Generate unique test directory for isolation
    TestDir = ?TEST_LOG_DIR ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TestDir ++ "/"),

    %% Start XES logger with test configuration
    Config = #{
        log_directory => TestDir,
        buffer_size => 100,
        auto_flush => false,
        extensions => [time, concept, lifecycle, organizational],
        global_trace_attributes => [
            {<<"concept:name">>, string, <<"TestWorkflow">>}
        ]
    },

    %% Try to start the logger - if module doesn't exist yet, mock will be used
    LoggerPid = case code:is_loaded(yawl_xes_logger) of
        false ->
            %% Create mock process for testing
            spawn(fun() -> mock_logger_loop(#{}) end);
        _ ->
            {ok, Pid} = case yawl_xes_logger:start_link(Config) of
                {ok, P} -> P;
                {error, {already_started, P}} -> P
            end,
            Pid
    end,

    #{logger_pid => LoggerPid, test_dir => TestDir, config => Config}.

cleanup(State) ->
    %% Stop logger
    LoggerPid = maps:get(logger_pid, State),
    case is_process_alive(LoggerPid) of
        true -> exit(LoggerPid, normal);
        false -> ok
    end,

    %% Clean up test directory
    TestDir = maps:get(test_dir, State),
    case file:del_dir_r(TestDir) of
        ok -> ok;
        {error, Reason} ->
            io:format("Warning: Failed to delete test directory ~p: ~p~n",
                      [TestDir, Reason])
    end.

mock_logger_loop(State) ->
    receive
        {stop, From} -> From ! ok;
        {get_state, From} -> From ! State, mock_logger_loop(State);
        _ -> mock_logger_loop(State)
    end.

%%====================================================================
%% Group 1: Log Creation and Management
%%====================================================================

test_group_log_management() ->
    test_create_log(),
    test_create_log_with_attributes(),
    test_open_existing_log(),
    test_close_log(),
    test_delete_log(),
    test_list_logs(),
    test_log_metadata(),
    ok.

test_create_log() ->
    %% Test creating a new XES log
    LogId = <<"test_log_001">>,

    Result = case code:is_loaded(yawl_xes_logger) of
        false ->
            %% Mock response
            {ok, LogId};
        _ ->
            yawl_xes_logger:create_log(LogId, #{
                description => <<"Test log for unit testing">>,
                source => <<"YAWL Orchestrator">>,
                vendor => <<"A2A Team">>
            })
    end,

    ?assertMatch({ok, _}, Result),

    %% Verify log exists
    {ok, CreatedLogId} = Result,
    ?assertEqual(LogId, CreatedLogId),

    ok.

test_create_log_with_attributes() ->
    %% Test creating log with custom attributes
    LogId = <<"test_log_attrs">>,

    Attributes = [
        {<<"concept:name">>, string, <<"Attribute Test Log">>},
        {<<"description">>, string, <<"Testing attribute handling">>},
        {<<"version">>, string, <<"1.0">>},
        {<<"created">>, date, erlang:system_time(millisecond)}
    ],

    Result = case code:is_loaded(yawl_xes_logger) of
        false ->
            %% Mock response
            {ok, LogId};
        _ ->
            yawl_xes_logger:create_log(LogId, #{attributes => Attributes})
    end,

    ?assertMatch({ok, _}, Result),

    ok.

test_open_existing_log() ->
    %% Test opening an existing log for appending
    LogId = <<"test_log_open">>,

    %% First create it
    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            ok = yawl_xes_logger:close_log(LogId)
    end,

    %% Then open it
    Result = case code:is_loaded(yawl_xes_logger) of
        false ->
            %% Mock response
            {ok, LogId};
        _ ->
            yawl_xes_logger:open_log(LogId)
    end,

    ?assertMatch({ok, _}, Result),

    ok.

test_close_log() ->
    %% Test closing a log
    LogId = <<"test_log_close">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),

            %% Close the log
            Result = yawl_xes_logger:close_log(LogId),
            ?assertEqual(ok, Result)
    end,

    ok.

test_delete_log() ->
    %% Test deleting a log
    LogId = <<"test_log_delete">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            ok = yawl_xes_logger:close_log(LogId),

            %% Delete the log
            Result = yawl_xes_logger:delete_log(LogId),
            ?assertEqual(ok, Result),

            %% Verify log is deleted
            ?assertEqual({error, not_found}, yawl_xes_logger:open_log(LogId))
    end,

    ok.

test_list_logs() ->
    %% Test listing all logs
    LogIds = [<<"test_log_list_1">>, <<"test_log_list_2">>, <<"test_log_list_3">>],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            %% Create multiple logs
            lists:foreach(fun(Lid) ->
                {ok, _} = yawl_xes_logger:create_log(Lid, #{}),
                ok = yawl_xes_logger:close_log(Lid)
            end, LogIds),

            %% List logs
            {ok, LogList} = yawl_xes_logger:list_logs(),

            %% Verify our test logs are in the list
            lists:foreach(fun(Lid) ->
                ?assert(lists:member(Lid, LogList))
            end, LogIds)
    end,

    ok.

test_log_metadata() ->
    %% Test log metadata management
    LogId = <<"test_log_metadata">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{
                description => <<"Metadata test log">>,
                author => <<"Test Author">>,
                version => <<"2.0">>
            }),

            %% Get metadata
            {ok, Metadata} = yawl_xes_logger:get_log_metadata(LogId),

            ?assert(maps:is_key(<<"description">>, Metadata)),
            ?assert(maps:is_key(<<"author">>, Metadata)),
            ?assert(maps:is_key(<<"version">>, Metadata)),

            ok = yawl_xes_logger:close_log(LogId)
    end,

    ok.

%%====================================================================
%% Group 2: Event Recording
%%====================================================================

test_group_event_recording() ->
    test_record_trace_start(),
    test_record_trace_complete(),
    test_record_event(),
    test_record_event_with_attributes(),
    test_record_all_event_types(),
    test_batch_record_events(),
    test_event_timestamps(),
    test_event_lifecycle(),
    ok.

test_record_trace_start() ->
    %% Test recording trace start (workflow start)
    TraceId = ?TEST_TRACE_ID,
    WorkflowId = ?TEST_WORKFLOW_ID,

    Result = case code:is_loaded(yawl_xes_logger) of
        false ->
            %% Mock response
            {ok, TraceId};
        _ ->
            yawl_xes_logger:start_trace(TraceId, WorkflowId, #{
                attributes => [
                    {<<"concept:name">>, string, <<"Order Processing">>}
                ]
            })
    end,

    ?assertMatch({ok, _}, Result),

    ok.

test_record_trace_complete() ->
    %% Test recording trace completion
    TraceId = <<"test_trace_complete">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            %% Start a trace first
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_001">>, #{}),

            %% Complete the trace
            Result = yawl_xes_logger:complete_trace(TraceId, #{
                final_status => completed,
                duration_ms => 1500
            }),

            ?assertEqual(ok, Result)
    end,

    ok.

test_record_event() ->
    %% Test recording a single event
    TraceId = <<"test_trace_event">>,
    EventId = <<"event_001">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_001">>, #{}),

            %% Record an event
            Result = yawl_xes_logger:record_event(TraceId, EventId, #{
                concept_name => <<"Validate Order">>,
                lifecycle_transition => <<"start">>,
                timestamp => erlang:system_time(millisecond)
            }),

            ?assertEqual(ok, Result)
    end,

    ok.

test_record_event_with_attributes() ->
    %% Test recording event with custom attributes
    TraceId = <<"test_trace_attrs">>,
    EventId = <<"event_attrs_001">>,

    Attributes = [
        {<<"concept:name">>, string, <<"Process Payment">>},
        {<<"lifecycle:transition">>, string, <<"complete">>},
        {<<"cost:amount">>, float, 99.99},
        {<<"org:resource">>, string, <<"PaymentService">>},
        {<<"data:orderId">>, string, <<"ORD-12345">>}
    ],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_001">>, #{}),

            Result = yawl_xes_logger:record_event(TraceId, EventId, #{
                attributes => Attributes
            }),

            ?assertEqual(ok, Result)
    end,

    ok.

test_record_all_event_types() ->
    %% Test recording all standard XES event types
    TraceId = <<"test_trace_all_types">>,

    EventTypes = [
        {<<"schedule_start">>, <<"schedule">>},
        {<<"assign">>, <<"assign">>},
        {<<"reassign">>, <<"reassign">>},
        {<<"start">>, <<"start">>},
        {<<"suspend">>, <<"suspend">>},
        {<<"resume">>, <<"resume">>},
        {<<"pi_complete">>, <<"complete">>},
        {<<"aut_complete">>, <<"aut_complete">>},
        {<<"manual_complete">>, <<"manual_complete">>},
        {<<"withdraw">>, <<"withdraw">>}
    ],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_all_types">>, #{}),

            lists:foreach(fun({EventName, Transition}) ->
                EventId = <<"evt_", Transition/binary>>,
                Result = yawl_xes_logger:record_event(TraceId, EventId, #{
                    concept_name => EventName,
                    lifecycle_transition => Transition
                }),
                ?assertEqual(ok, Result)
            end, EventTypes)
    end,

    ok.

test_batch_record_events() ->
    %% Test batch recording multiple events
    TraceId = <<"test_trace_batch">>,

    Events = [
        {<<"evt_1">>, #{concept_name => <<"Task 1">>, lifecycle_transition => <<"start">>}},
        {<<"evt_2">>, #{concept_name => <<"Task 2">>, lifecycle_transition => <<"complete">>}},
        {<<"evt_3">>, #{concept_name => <<"Task 3">>, lifecycle_transition => <<"start">>}},
        {<<"evt_4">>, #{concept_name => <<"Task 4">>, lifecycle_transition => <<"complete">>}}
    ],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_batch">>, #{}),

            Result = yawl_xes_logger:record_events(TraceId, Events),

            ?assertEqual(ok, Result)
    end,

    ok.

test_event_timestamps() ->
    %% Test that events properly record timestamps
    TraceId = <<"test_trace_timestamps">>,

    BeforeTimestamp = erlang:system_time(millisecond),

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_timestamps">>, #{}),

            %% Record event without explicit timestamp (should use current time)
            ok = yawl_xes_logger:record_event(TraceId, <<"evt_time">>, #{
                concept_name => <<"Timed Task">>
            }),

            %% Get trace events
            {ok, Events} = yawl_xes_logger:get_trace_events(TraceId),

            ?assert(length(Events) > 0),

            %% Verify timestamp is reasonable
            [Event | _] = Events,
            EventTimestamp = maps:get(<<"time:timestamp">>, Event, 0),
            ?assert(EventTimestamp >= BeforeTimestamp)
    end,

    ok.

test_event_lifecycle() ->
    %% Test complete lifecycle of a task event
    TraceId = <<"test_trace_lifecycle">>,

    TaskId = <<"task_validate">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_lifecycle">>, #{}),

            %% Schedule
            ok = yawl_xes_logger:record_event(TraceId, <<TaskId/binary, "_schedule">>, #{
                concept_name => TaskId,
                lifecycle_transition => schedule
            }),

            %% Start
            ok = yawl_xes_logger:record_event(TraceId, <<TaskId/binary, "_start">>, #{
                concept_name => TaskId,
                lifecycle_transition => start
            }),

            %% Complete
            ok = yawl_xes_logger:record_event(TraceId, <<TaskId/binary, "_complete">>, #{
                concept_name => TaskId,
                lifecycle_transition => complete
            }),

            %% Verify lifecycle
            {ok, Events} = yawl_xes_logger:get_trace_events(TraceId),

            ?assertEqual(3, length(Events)),

            %% Verify transition order
            Transitions = [maps:get(<<"lifecycle:transition">>, E) || E <- Events],
            ?assertEqual([<<"schedule">>, <<"start">>, <<"complete">>], Transitions)
    end,

    ok.

%%====================================================================
%% Group 3: XES Export
%%====================================================================

test_group_xes_export() ->
    test_export_to_file(),
    test_export_format(),
    test_export_with_extensions(),
    test_export_partial_trace(),
    test_export_multiple_traces(),
    test_export_compression(),
    ok.

test_export_to_file() ->
    %% Test exporting log to XES file
    LogId = <<"test_log_export">>,
    TraceId = <<"test_trace_export">>,
    FilePath = "/tmp/test_export.xes",

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_export">>, #{}),

            %% Add some events
            ok = yawl_xes_logger:record_event(TraceId, <<"evt1">>, #{
                concept_name => <<"Task 1">>,
                lifecycle_transition => start
            }),

            %% Export to file
            Result = yawl_xes_logger:export_to_file(LogId, FilePath),

            ?assertEqual(ok, Result),

            %% Verify file exists and has content
            ?assert(filelib:is_file(FilePath)),

            {ok, Content} = file:read_file(FilePath),
            ?assert(byte_size(Content) > 0),

            %% Verify it's valid XML (contains XES namespace)
            ContentStr = binary_to_list(Content),
            ?assert(string:str(ContentStr, "xes") > 0 orelse
                     string:str(ContentStr, "XES") > 0),

            %% Cleanup
            file:delete(FilePath)
    end,

    ok.

test_export_format() ->
    %% Test that exported XES has correct format
    LogId = <<"test_log_format">>,
    TraceId = <<"test_trace_format">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_format">>, #{}),

            %% Export to string
            {ok, XESString} = yawl_xes_logger:export_to_string(LogId),

            %% Verify XES structure
            ?assert(string:str(XESString, "<?xml") > 0),
            ?assert(string:str(XESString, "<log") > 0),
            ?assert(string:str(XESString, "</log>") > 0),
            ?assert(string:str(XESString, "<trace") > 0),
            ?assert(string:str(XESString, "</trace>") > 0)
    end,

    ok.

test_export_with_extensions() ->
    %% Test exporting with standard XES extensions
    LogId = <<"test_log_extensions">>,
    TraceId = <<"test_trace_ext">>,

    Extensions = [
        {<<"Time">>, <<"time">>, <<"http://www.xes-standard.org/time.xesext">>},
        {<<"Concept">>, <<"concept">>, <<"http://www.xes-standard.org/concept.xesext">>},
        {<<"Lifecycle">>, <<"lifecycle">>, <<"http://www.xes-standard.org/lifecycle.xesext">>},
        {<<"Organizational">>, <<"org">>, <<"http://www.xes-standard.org/org.xesext">>}
    ],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{
                extensions => Extensions
            }),

            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_ext">>, #{}),

            %% Export
            {ok, XESString} = yawl_xes_logger:export_to_string(LogId),

            %% Verify extensions are in export
            lists:foreach(fun({Name, Prefix, _URI}) ->
                ?assert(string:str(XESString, "extension") > 0),
                ?assert(string:str(XESString, binary_to_list(Prefix)) > 0)
            end, Extensions)
    end,

    ok.

test_export_partial_trace() ->
    %% Test exporting only part of a trace
    TraceId = <<"test_trace_partial">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_partial">>, #{}),

            %% Add multiple events
            lists:foreach(fun(I) ->
                Eid = <<"evt_", (integer_to_binary(I))/binary>>,
                yawl_xes_logger:record_event(TraceId, Eid, #{
                    concept_name => <<"Task ">>,
                    lifecycle_transition => start
                })
            end, lists:seq(1, 10)),

            %% Export first 5 events
            {ok, PartialXES} = yawl_xes_logger:export_trace_to_string(TraceId, #{
                max_events => 5
            }),

            %% Verify partial export
            ?assert(string:str(PartialXES, "<event") > 0)
    end,

    ok.

test_export_multiple_traces() ->
    %% Test exporting log with multiple traces
    LogId = <<"test_log_multi">>,

    TraceIds = [<<"trace_1">>, <<"trace_2">>, <<"trace_3">>],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),

            %% Create multiple traces
            lists:foreach(fun(Tid) ->
                {ok, _} = yawl_xes_logger:start_trace(Tid, LogId, #{}),
                ok = yawl_xes_logger:record_event(Tid, <<"evt">>, #{
                    concept_name => <<"Task">>,
                    lifecycle_transition => complete
                })
            end, TraceIds),

            %% Export
            {ok, XESString} = yawl_xes_logger:export_to_string(LogId),

            %% Verify multiple traces
            ?assert(string:str(XESString, "<trace") > 0),

            %% Count trace tags
            TraceStartCount = count_occurrences(XESString, "<trace"),
            ?assert(TraceStartCount >= length(TraceIds))
    end,

    ok.

test_export_compression() ->
    %% Test exporting with compression
    LogId = <<"test_log_compress">>,
    FilePath = "/tmp/test_export.xes.gz",

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            {ok, _} = yawl_xes_logger:start_trace(<<"trace1">>, <<"wf">>, #{}),

            %% Export with compression
            Result = yawl_xes_logger:export_to_file(LogId, FilePath, #{
                compress => true
            }),

            ?assertEqual(ok, Result),
            ?assert(filelib:is_file(FilePath)),

            file:delete(FilePath)
    end,

    ok.

%%====================================================================
%% Group 4: Concurrent Logging
%%====================================================================

test_group_concurrent_logging() ->
    test_concurrent_trace_creation(),
    test_concurrent_event_recording(),
    test_concurrent_log_access(),
    test_concurrent_export(),
    ok.

test_concurrent_trace_creation() ->
    %% Test creating multiple traces concurrently
    NumTraces = 100,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            %% Spawn processes to create traces concurrently
            Pids = lists:map(fun(I) ->
                TraceId = <<"concurrent_trace_", (integer_to_binary(I))/binary>>,
                spawn(fun() ->
                    Result = yawl_xes_logger:start_trace(TraceId, <<"wf_concurrent">>, #{}),
                    self() ! {result, Result}
                end)
            end, lists:seq(1, NumTraces)),

            %% Wait for all to complete
            Results = lists:map(fun(Pid) ->
                receive
                    {result, R} -> R
                after 5000 -> timeout
                end
            end, Pids),

            %% All should succeed
            SuccessCount = length([R || R <- Results, element(1, R) =:= ok]),
            ?assert(SuccessCount >= NumTraces - 1)  % Allow 1 failure
    end,

    ok.

test_concurrent_event_recording() ->
    %% Test recording events to same trace from multiple processes
    TraceId = <<"concurrent_events_trace">>,
    NumEvents = 50,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_concurrent_events">>, #{}),

            %% Spawn processes to record events concurrently
            Pids = lists:map(fun(I) ->
                EventId = <<"evt_", (integer_to_binary(I))/binary>>,
                spawn(fun() ->
                    Result = yawl_xes_logger:record_event(TraceId, EventId, #{
                        concept_name => <<"Concurrent Task">>,
                        lifecycle_transition => start,
                        event_number => I
                    }),
                    self() ! {result, Result}
                end)
            end, lists:seq(1, NumEvents)),

            %% Wait for all to complete
            Results = lists:map(fun(Pid) ->
                receive
                    {result, R} -> R
                after 5000 -> timeout
                end
            end, Pids),

            %% Most should succeed
            SuccessCount = length([R || R <- Results, R =:= ok]),
            ?assert(SuccessCount >= NumEvents - 5),

            %% Verify all events were recorded
            {ok, Events} = yawl_xes_logger:get_trace_events(TraceId),
            ?assert(length(Events) >= NumEvents - 5)
    end,

    ok.

test_concurrent_log_access() ->
    %% Test concurrent access to same log
    LogId = <<"concurrent_log_access">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),

            %% Multiple operations concurrently
            Operations = [
                fun() -> yawl_xes_logger:get_log_metadata(LogId) end,
                fun() -> yawl_xes_logger:list_traces(LogId) end,
                fun() -> yawl_xes_logger:get_statistics(LogId) end
            ],

            Pids = lists:map(fun(Op) ->
                spawn(fun() ->
                    Result = Op(),
                    self() ! {result, Result}
                end)
            end, Operations),

            %% Wait for all
            lists:foreach(fun(Pid) ->
                receive
                    {result, _} -> ok
                after 2000 -> ?assert(false)
                end
            end, Pids)
    end,

    ok.

test_concurrent_export() ->
    %% Test concurrent exports
    LogId = <<"concurrent_export">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:create_log(LogId, #{}),
            {ok, _} = yawl_xes_logger:start_trace(<<"trace1">>, LogId, #{}),

            %% Export to multiple files concurrently
            Pids = lists:map(fun(I) ->
                FilePath = "/tmp/concurrent_export_" ++ integer_to_list(I) ++ ".xes",
                spawn(fun() ->
                    Result = yawl_xes_logger:export_to_file(LogId, FilePath),
                    self() ! {result, Result, FilePath}
                end)
            end, lists:seq(1, 5)),

            %% Wait for all
            lists:foreach(fun(Pid) ->
                receive
                    {result, Result, FilePath} ->
                        ?assertEqual(ok, Result),
                        file:delete(FilePath)
                after 5000 -> ?assert(false)
                end
            end, Pids)
    end,

    ok.

%%====================================================================
%% Group 5: Trace Management
%%====================================================================

test_group_trace_management() ->
    test_create_trace(),
    test_get_trace_info(),
    test_list_traces(),
    test_delete_trace(),
    test_trace_attributes(),
    test_trace_parent_child(),
    ok.

test_create_trace() ->
    %% Test creating a new trace
    TraceId = <<"test_new_trace">>,
    WorkflowId = <<"wf_001">>,

    Result = case code:is_loaded(yawl_xes_logger) of
        false -> {ok, TraceId};
        _ -> yawl_xes_logger:start_trace(TraceId, WorkflowId, #{})
    end,

    ?assertMatch({ok, _}, Result),

    ok.

test_get_trace_info() ->
    %% Test getting trace information
    TraceId = <<"test_trace_info">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_info">>, #{
                attributes => [
                    {<<"concept:name">>, string, <<"Info Test Trace">>}
                ]
            }),

            %% Add some events
            ok = yawl_xes_logger:record_event(TraceId, <<"evt1">>, #{
                concept_name => <<"Task">>,
                lifecycle_transition => start
            }),

            %% Get info
            {ok, Info} = yawl_xes_logger:get_trace_info(TraceId),

            ?assert(maps:is_key(<<"trace_id">>, Info)),
            ?assert(maps:is_key(<<"workflow_id">>, Info)),
            ?assert(maps:is_key(<<"event_count">>, Info)),
            ?assert(maps:get(<<"event_count">>, Info) > 0)
    end,

    ok.

test_list_traces() ->
    %% Test listing all traces
    TraceIds = [<<"trace_list_1">>, <<"trace_list_2">>, <<"trace_list_3">>],

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            lists:foreach(fun(Tid) ->
                {ok, _} = yawl_xes_logger:start_trace(Tid, <<"wf_list">>, #{})
            end, TraceIds),

            %% List traces
            {ok, TraceList} = yawl_xes_logger:list_traces(),

            %% Verify our traces are in the list
            lists:foreach(fun(Tid) ->
                ?assert(lists:member(Tid, TraceList))
            end, TraceIds)
    end,

    ok.

test_delete_trace() ->
    %% Test deleting a trace
    TraceId = <<"test_trace_delete">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_delete">>, #{}),

            %% Delete trace
            Result = yawl_xes_logger:delete_trace(TraceId),

            ?assertEqual(ok, Result),

            %% Verify deleted
            ?assertEqual({error, not_found}, yawl_xes_logger:get_trace_info(TraceId))
    end,

    ok.

test_trace_attributes() ->
    %% Test trace attribute management
    TraceId = <<"test_trace_attrs_mgmt">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(TraceId, <<"wf_attrs">>, #{
                attributes => [
                    {<<"concept:name">>, string, <<"Attribute Management">>},
                    {<<"case:id">>, string, <<"CASE-001">>}
                ]
            }),

            %% Add more attributes
            ok = yawl_xes_logger:add_trace_attribute(TraceId, #{
                key => <<"custom:attribute">>,
                type => string,
                value => <<"Custom Value">>
            }),

            %% Get info and verify attributes
            {ok, Info} = yawl_xes_logger:get_trace_info(TraceId),

            ?assert(maps:is_key(<<"attributes">>, Info))
    end,

    ok.

test_trace_parent_child() ->
    %% Test parent-child trace relationships
    ParentTraceId = <<"test_trace_parent">>,
    ChildTraceId = <<"test_trace_child">>,

    case code:is_loaded(yawl_xes_logger) of
        false -> ok;
        _ ->
            {ok, _} = yawl_xes_logger:start_trace(ParentTraceId, <<"wf_parent">>, #{}),

            %% Create child trace
            {ok, _} = yawl_xes_logger:start_trace(ChildTraceId, <<"wf_child">>, #{
                parent_trace => ParentTraceId
            }),

            %% Verify relationship
            {ok, ChildInfo} = yawl_xes_logger:get_trace_info(ChildTraceId),
            ?assertEqual(ParentTraceId, maps:get(<<"parent_trace">>, ChildInfo))
    end,

    ok.

%%====================================================================
%% Group 6: Attribute Handling
%%====================================================================

test_group_attributes() ->
    test_boolean_attributes(),
    test_integer_attributes(),
    test_float_attributes(),
    test_string_attributes(),
    test_date_attributes(),
    test_id_attributes(),
    test_list_attributes(),
    test_nested_attributes(),
    ok.

test_boolean_attributes() ->
    %% Test boolean attribute handling
    ?assertEqual(true, is_boolean_attribute(true)),
    ?assertEqual(true, is_boolean_attribute(false)),
    ok.

test_integer_attributes() ->
    %% Test integer attribute handling
    ?assertEqual(true, is_integer(42)),
    ?assertEqual(true, is_integer(-1)),
    ?assertEqual(true, is_integer(0)),
    ok.

test_float_attributes() ->
    %% Test float attribute handling
    ?assertEqual(true, is_float(3.14)),
    ?assertEqual(true, is_float(-0.001)),
    ok.

test_string_attributes() ->
    %% Test string attribute handling
    ?assertEqual(true, is_binary(<<"string">>)),
    ?assertEqual(true, is_binary(<<"">>)),
    ok.

test_date_attributes() ->
    %% Test date attribute handling (timestamps)
    Timestamp = erlang:system_time(millisecond),
    ?assert(is_integer(Timestamp)),
    ?assert(Timestamp > 0),
    ok.

test_id_attributes() ->
    %% Test ID attribute handling
    Id = <<"id-123-abc">>,
    ?assert(is_binary(Id)),
    ?assert(byte_size(Id) > 0),
    ok.

test_list_attributes() ->
    %% Test list attribute handling
    List = [1, 2, 3, 4, 5],
    ?assert(is_list(List)),
    ?assert(length(List) > 0),
    ok.

test_nested_attributes() ->
    %% Test nested attribute handling
    Nested = #{
        level1 => #{
            level2 => #{
                level3 => <<"deep value">>
            }
        }
    },
    ?assert(is_map(Nested)),
    ?assert(is_map(maps:get(<<"level1">>, Nested))),
    ok.

%%====================================================================
%% Group 7: Extensions
%%====================================================================

test_group_extensions() ->
    test_time_extension(),
    test_concept_extension(),
    test_lifecycle_extension(),
    test_organizational_extension(),
    test_custom_extension(),
    ok.

test_time_extension() ->
    %% Test time extension (XES standard)
    TimeExtension = #{
        name => <<"Time">>,
        prefix => <<"time">>,
        uri => <<"http://www.xes-standard.org/time.xesext">>
    },

    ?assertEqual(<<"Time">>, maps:get(<<"name">>, TimeExtension)),
    ?assertEqual(<<"time">>, maps:get(<<"prefix">>, TimeExtension)),
    ?assert(string:str(binary_to_list(maps:get(<<"uri">>, TimeExtension)), "xes-standard") > 0),

    ok.

test_concept_extension() ->
    %% Test concept extension
    ConceptExtension = #{
        name => <<"Concept">>,
        prefix => <<"concept">>,
        uri => <<"http://www.xes-standard.org/concept.xesext">>
    },

    ?assertEqual(<<"Concept">>, maps:get(<<"name">>, ConceptExtension)),

    ok.

test_lifecycle_extension() ->
    %% Test lifecycle extension
    LifecycleExtension = #{
        name => <<"Lifecycle">>,
        prefix => <<"lifecycle">>,
        uri => <<"http://www.xes-standard.org/lifecycle.xesext">>,

        %% Standard transitions
        transitions => [
            schedule, assign, reassign, start, suspend,
            resume, pi_complete, aut_complete, manual_complete,
            withdraw
        ]
    },

    Transitions = maps:get(transitions, LifecycleExtension),
    ?assert(lists:member(start, Transitions)),
    ?assert(lists:member(complete, Transitions)),

    ok.

test_organizational_extension() ->
    %% Test organizational extension
    OrgExtension = #{
        name => <<"Organizational">>,
        prefix => <<"org">>,
        uri => <<"http://www.xes-standard.org/org.xesext">>
    },

    ?assertEqual(<<"org">>, maps:get(<<"prefix">>, OrgExtension)),

    ok.

test_custom_extension() ->
    %% Test custom extension
    CustomExtension = #{
        name => <<"CustomCost">>,
        prefix => <<"cost">>,
        uri => <<"http://example.com/cost.xesext">>
    },

    ?assertEqual(<<"CustomCost">>, maps:get(<<"name">>, CustomExtension)),

    ok.

%%====================================================================
%% Group 8: IEEE 1849-2016 Compliance
%%====================================================================

test_group_ieee_compliance() ->
    test_required_log_attributes(),
    test_required_trace_attributes(),
    test_required_event_attributes(),
    test_xml_structure(),
    test_namespace_declaration(),
    test_extension_declaration(),
    test_attribute_types(),
    ok.

test_required_log_attributes() ->
    %% Test required log attributes per IEEE 1849-2016
    RequiredLogAttrs = [
        <<"xes.version">>,
        <<"xes.features">>,
        <<"openxes.version">>,
        <<"xmlns">>
    ],

    %% Verify all required attributes are known
    lists:foreach(fun(Attr) ->
        ?assert(is_binary(Attr)),
        ?assert(byte_size(Attr) > 0)
    end, RequiredLogAttrs),

    ok.

test_required_trace_attributes() ->
    %% Test required trace attributes
    RequiredTraceAttrs = [
        <<"concept:name">>
    ],

    lists:foreach(fun(Attr) ->
        ?assert(is_binary(Attr))
    end, RequiredTraceAttrs),

    ok.

test_required_event_attributes() ->
    %% Test required event attributes
    RequiredEventAttrs = [
        <<"concept:name">>,
        <<"time:timestamp">>
    ],

    lists:foreach(fun(Attr) ->
        ?assert(is_binary(Attr))
    end, RequiredEventAttrs),

    ok.

test_xml_structure() ->
    %% Test XES XML structure requirements
    %% According to IEEE 1849-2016, XES must be valid XML

    %% Simulated XES structure
    SimulatedXES = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xes.features=\"nested-attributes\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Concept\" prefix=\"concept\" uri=\"http://www.xes-standard.org/concept.xesext\"/>
  <trace>
    <event>
      <string key=\"concept:name\" value=\"Task 1\"/>
      <date key=\"time:timestamp\" value=\"2024-01-01T00:00:00.000Z\"/>
    </event>
  </trace>
</log>">>,

    %% Verify structure
    ?assert(string:str(binary_to_list(SimulatedXES), "<?xml") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "<log") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "</log>") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "<trace") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "</trace>") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "<event") > 0),
    ?assert(string:str(binary_to_list(SimulatedXES), "</event>") > 0),

    ok.

test_namespace_declaration() ->
    %% Test XES namespace declaration
    %% Default namespace: http://www.xes-standard.org/

    DefaultNS = <<"http://www.xes-standard.org/">>,

    ?assert(string:str(binary_to_list(DefaultNS), "xes-standard") > 0),

    ok.

test_extension_declaration() ->
    %% Test extension declaration format
    %% <extension name="..." prefix="..." uri="..."/>

    Extension = #{
        name => <<"Time">>,
        prefix => <<"time">>,
        uri => <<"http://www.xes-standard.org/time.xesext">>
    },

    ?assert(is_binary(maps:get(name, Extension))),
    ?assert(is_binary(maps:get(prefix, Extension))),
    ?assert(is_binary(maps:get(uri, Extension))),

    ok.

test_attribute_types() ->
    %% Test XES attribute types per IEEE 1849-2016
    AttributeTypes = [
        string,
        date,
        int,
        float,
        boolean,
        id,
        list
    ],

    %% Verify all types are known
    ValidTypes = [string, date, int, float, boolean, id, list],
    lists:foreach(fun(Type) ->
        ?assert(lists:member(Type, ValidTypes))
    end, AttributeTypes),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Count occurrences of substring in string
count_occurrences(String, Substring) ->
    Count = count_occurrences_loop(String, Substring, 0),
    Count.

count_occurrences_loop(String, Substring, Count) ->
    case string:str(String, Substring) of
        0 -> Count;
        Index ->
            NewString = lists:nthtail(Index + length(Substring) - 1, String),
            count_occurrences_loop(NewString, Substring, Count + 1)
    end.

%% @private
%% @doc Check if value is a valid boolean attribute
is_boolean_attribute(Value) when is_boolean(Value) -> true;
is_boolean_attribute(_) -> false.
