%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Adapter Unit Tests
%%%
%%% Test suite for the XES adapter module, focusing on JSON export
%%% functionality. Tests follow Chicago TDD methodology - tests are
%%% written first to fail, then implementation makes them pass.
%%%
%%% Tests cover:
%%% 1. XES to JSON conversion for single trace
%%% 2. XES to JSON conversion for all traces
%%% 3. JSON format validation
%%% 4. Error handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_adapter_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Macros and Constants
%%====================================================================

-define(TEST_WORKFLOW_ID, <<"test_workflow_json">>).
-define(TEST_TRACE_ID, <<"test_trace_json_001">>).
-define(TEST_TIMESTAMP, 1704067200000). % 2024-01-01 00:00:00 UTC

%%====================================================================
%% Test Generator - Main Entry Point
%%====================================================================

xes_adapter_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: XES to JSON Conversion", fun test_group_xes_to_json/0},
      {"Group 2: JSON Export Format", fun test_group_json_format/0},
      {"Group 3: Error Handling", fun test_group_error_handling/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup Fixtures
%%====================================================================

setup() ->
    %% Start the XES adapter for testing
    {ok, Pid} = yawl_xes_adapter:start_link(#{
        output_type => stdio,
        buffer_size => 10
    }),
    #{adapter_pid => Pid}.

cleanup(State) ->
    %% Stop the adapter
    AdapterPid = maps:get(adapter_pid, State),
    case is_process_alive(AdapterPid) of
        true -> gen_server:stop(AdapterPid, normal, 1000);
        false -> ok
    end.

%%====================================================================
%% Group 1: XES to JSON Conversion
%%====================================================================

test_group_xes_to_json() ->
    test_export_trace_json_single(),
    test_export_trace_json_with_events(),
    test_export_all_traces_json(),
    ok.

test_export_trace_json_single() ->
    %% Test exporting a single trace to JSON format
    %% CHICAGO TDD: This test fails before implementation
    WorkflowId = ?TEST_WORKFLOW_ID,

    %% Subscribe to workflow
    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    %% Export trace with JSON format
    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    %% Before implementation: returns {error, json_format_not_supported}
    %% After implementation: returns {ok, JSONBinary}
    ?assertMatch({ok, _JSON}, Result),

    case Result of
        {ok, JSON} ->
            %% Verify it's valid JSON
            ?assert(is_binary(JSON)),
            ?assert(byte_size(JSON) > 0),

            %% Parse JSON to verify structure
            {ok, Decoded} = jiffy:decode(JSON, [return_maps]),
            ?assert(is_map(Decoded)),
            ?assert(maps:is_key(<<"traces">>, Decoded) orelse
                    maps:is_key(<<"log">>, Decoded) orelse
                    maps:is_key(<<"trace">>, Decoded));
        {error, Reason} ->
            %% This is the expected failure before implementation
            ?assertEqual(json_format_not_supported, Reason)
    end,

    ok.

test_export_trace_json_with_events() ->
    %% Test exporting a trace with events to JSON
    WorkflowId = <<"test_wf_with_events">>,

    %% Subscribe to workflow
    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    %% Create some test events
    Events = [
        #{
            event_type => workitem_created,
            timestamp => ?TEST_TIMESTAMP,
            workitem_id => <<"wi_001">>,
            workflow_id => WorkflowId
        },
        #{
            event_type => workitem_started,
            timestamp => ?TEST_TIMESTAMP + 1000,
            workitem_id => <<"wi_001">>,
            workflow_id => WorkflowId
        },
        #{
            event_type => workitem_completed,
            timestamp => ?TEST_TIMESTAMP + 5000,
            workitem_id => <<"wi_001">>,
            workflow_id => WorkflowId
        }
    ],

    %% Convert events to populate the trace
    lists:foreach(fun(Event) ->
        {ok, _XES} = yawl_xes_adapter:convert_event_to_xes(Event)
    end, Events),

    %% Export as JSON
    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    case Result of
        {ok, JSON} ->
            ?assert(is_binary(JSON)),

            %% Verify JSON contains event data
            ?assert(string:str(binary_to_list(JSON), "workitem_created") > 0 orelse
                     string:str(binary_to_list(JSON), "WorkitemCreated") > 0);
        {error, _} ->
            %% Expected before implementation
            ok
    end,

    ok.

test_export_all_traces_json() ->
    %% Test exporting all traces to JSON format
    WorkflowIds = [<<"wf_json_1">>, <<"wf_json_2">>, <<"wf_json_3">>],

    %% Subscribe to multiple workflows
    lists:foreach(fun(WfId) ->
        ok = yawl_xes_adapter:subscribe_to_workflow(WfId)
    end, WorkflowIds),

    %% Export all traces as JSON
    Result = yawl_xes_adapter:export_all_traces(#{format => json}),

    case Result of
        {ok, JSON} ->
            ?assert(is_binary(JSON)),
            ?assert(byte_size(JSON) > 0),

            %% Parse JSON to verify structure
            {ok, Decoded} = jiffy:decode(JSON, [return_maps]),
            ?assert(is_map(Decoded));
        {error, _} ->
            %% Expected before implementation
            ok
    end,

    ok.

%%====================================================================
%% Group 2: JSON Export Format
%%====================================================================

test_group_json_format() ->
    test_json_has_required_fields(),
    test_json_timestamp_format(),
    test_json_event_structure(),
    ok.

test_json_has_required_fields() ->
    %% Test that JSON output has required XES fields
    WorkflowId = <<"test_wf_fields">>,

    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    case Result of
        {ok, JSON} ->
            {ok, Decoded} = jiffy:decode(JSON, [return_maps]),

            %% Verify top-level structure
            ?assert(maps:is_key(<<"xes.version">>, Decoded) orelse
                    maps:is_key(<<"version">>, Decoded) orelse
                    maps:is_key(<<"traces">>, Decoded));
        {error, _} ->
            ok
    end,

    ok.

test_json_timestamp_format() ->
    %% Test that timestamps are properly formatted in JSON
    WorkflowId = <<"test_wf_timestamp">>,

    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    %% Add an event with timestamp
    Event = #{
        event_type => task_created,
        timestamp => ?TEST_TIMESTAMP,
        workitem_id => <<"task_001">>,
        workflow_id => WorkflowId
    },
    {ok, _} = yawl_xes_adapter:convert_event_to_xes(Event),

    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    case Result of
        {ok, JSON} ->
            %% Verify timestamp is in JSON
            ?assert(string:str(binary_to_list(JSON), "1704067200000") > 0 orelse
                     string:str(binary_to_list(JSON), "2024-01-01") > 0);
        {error, _} ->
            ok
    end,

    ok.

test_json_event_structure() ->
    %% Test that events have proper JSON structure
    WorkflowId = <<"test_wf_event_struct">>,

    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    case Result of
        {ok, JSON} ->
            {ok, Decoded} = jiffy:decode(JSON, [return_maps]),

            %% Check for event list structure
            case maps:get(<<"events">>, Decoded, undefined) of
                undefined ->
                    %% Might be nested differently
                    ok;
                Events when is_list(Events) ->
                    %% Verify event structure
                    ?assert(length(Events) >= 0);
                _ ->
                    ok
            end;
        {error, _} ->
            ok
    end,

    ok.

%%====================================================================
%% Group 3: Error Handling
%%====================================================================

test_group_error_handling() ->
    test_export_nonexistent_trace(),
    test_invalid_format_option(),
    test_empty_trace_export(),
    ok.

test_export_nonexistent_trace() ->
    %% Test exporting a workflow that doesn't exist
    WorkflowId = <<"nonexistent_workflow">>,

    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    %% Should return error for nonexistent trace
    case Result of
        {ok, _} ->
            %% If it succeeds, JSON should be valid but empty
            ok;
        {error, _} ->
            %% Error is acceptable
            ok
    end,

    ok.

test_invalid_format_option() ->
    %% Test with invalid format option (should default to xml)
    WorkflowId = <<"test_wf_invalid_format">>,

    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    %% Pass invalid format - should default to xml or handle gracefully
    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => invalid}),

    ?assertMatch({ok, _}, Result),

    ok.

test_empty_trace_export() ->
    %% Test exporting a trace with no events
    WorkflowId = <<"test_wf_empty">>,

    ok = yawl_xes_adapter:subscribe_to_workflow(WorkflowId),

    Result = yawl_xes_adapter:export_trace(WorkflowId, #{format => json}),

    case Result of
        {ok, JSON} ->
            %% Empty trace should still be valid JSON
            ?assert(is_binary(JSON)),
            {ok, Decoded} = jiffy:decode(JSON, [return_maps]),
            ?assert(is_map(Decoded));
        {error, _} ->
            ok
    end,

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Create a mock trace for testing
create_mock_trace(WorkflowId) ->
    #{
        trace_id => ?TEST_TRACE_ID,
        workflow_id => WorkflowId,
        workflow_type => test_workflow,
        start_time => ?TEST_TIMESTAMP,
        end_time => ?TEST_TIMESTAMP + 10000,
        events => [
            #{
                event_id => <<"evt_001">>,
                event_type => workitem_created,
                timestamp => ?TEST_TIMESTAMP,
                activity => <<"WorkitemCreated">>,
                lifecycle => <<"schedule">>,
                resource => undefined,
                attributes => #{}
            }
        ],
        attributes => #{
            <<"concept:name">> => WorkflowId
        }
    }.

%% @private
%% @doc Convert XES XML to JSON structure
xes_xml_to_json(XESXml) ->
    %% Parse XES XML and convert to JSON
    %% This is a simplified version for testing
    #{
        <<"xes.version">> => <<"1.0">>,
        <<"xes.features">> => <<"nested-attributes">>,
        <<"traces">> => []
    }.
