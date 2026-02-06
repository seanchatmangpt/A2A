%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL OCEL Parsing Unit Tests
%%%
%%% Chicago-style TDD test suite for OCEL (Object-Centric Event Log)
%%% XES parsing functionality.
%%%
%%% Tests follow the Red-Green-Refactor TDD cycle:
%%% 1. RED: Write failing tests first
%%% 2. GREEN: Implement minimal code to pass tests
%%% 3. REFACTOR: Improve implementation while keeping tests green
%%%
%%% Tests cover:
%%% 1. Full OCEL XML parsing (parse_ocel_xes/1)
%%% 2. Object type extraction
%%% 3. Event log parsing
%%% 4. Multiple object types per event
%%% 5. OCEL schema validation
%%% 6. Error handling for invalid OCEL
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_ocel_parsing_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generator - Main Entry Point
%%====================================================================

ocel_parsing_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Basic OCEL XES Parsing", fun test_group_basic_parsing/0},
      {"Group 2: Object Type Extraction", fun test_group_object_types/0},
      {"Group 3: Event Log Parsing", fun test_group_event_parsing/0},
      {"Group 4: Multiple Object Types Per Event", fun test_group_multiple_objects/0},
      {"Group 5: OCEL Schema Validation", fun test_group_schema_validation/0},
      {"Group 6: Error Handling", fun test_group_error_handling/0},
      {"Group 7: OCEL Attribute Extraction", fun test_group_attribute_extraction/0},
      {"Group 8: Real-world OCEL Scenarios", fun test_group_real_world/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup Fixtures
%%====================================================================

setup() ->
    %% Create unique test directory for isolation
    TestDir = "/tmp/yawl_ocel_test_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_path(TestDir ++ "/"),
    #{test_dir => TestDir}.

cleanup(State) ->
    %% Clean up test directory
    TestDir = maps:get(test_dir, State),
    case file:del_dir_r(TestDir) of
        ok -> ok;
        {error, Reason} ->
            io:format("Warning: Failed to delete test directory ~p: ~p~n",
                      [TestDir, Reason])
    end.

%%====================================================================
%% Group 1: Basic OCEL XES Parsing
%%====================================================================

test_group_basic_parsing() ->
    test_parse_minimal_ocel_xes(),
    test_parse_empty_ocel_log(),
    test_parse_ocel_with_version(),
    ok.

%% Test 1.1: Parse minimal OCEL XES - should extract structure
test_parse_minimal_ocel_xes() ->
    %% Minimal valid OCEL XES with required elements
    MinimalOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Create Order\"/>
    <date key=\"time:timestamp\" value=\"2024-01-01T10:00:00.000Z\"/>
  </event>
</log>">>,

    %% This test will FAIL with current placeholder implementation
    %% because it returns empty object_types and events lists
    Result = yawl_object_centric_xes:parse_ocel_xes(MinimalOCEL),

    ?assertMatch({ok, #{}}, Result),

    {ok, ParsedLog} = Result,

    %% These assertions will FAIL with placeholder
    ?assert(maps:is_key(version, ParsedLog)),
    ?assert(maps:is_key(object_types, ParsedLog)),
    ?assert(maps:is_key(events, ParsedLog)),
    ?assert(maps:is_key(objects, ParsedLog)),

    %% Verify version is extracted
    ?assertEqual(<<"1.0">>, maps:get(version, ParsedLog)),

    %% Verify object types list is NOT empty (will fail with placeholder)
    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assert(length(ObjectTypes) > 0),
    ?assert(lists:member(<<"Order">>, ObjectTypes)),

    %% Verify events are parsed (will fail with placeholder)
    Events = maps:get(events, ParsedLog),
    ?assert(length(Events) > 0),

    ok.

%% Test 1.2: Parse empty OCEL log
test_parse_empty_ocel_log() ->
    %% OCEL XES with no events but valid structure
    EmptyOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
</log>">>,

    Result = yawl_object_centric_xes:parse_ocel_xes(EmptyOCEL),

    ?assertMatch({ok, _}, Result),

    {ok, ParsedLog} = Result,

    %% Empty log should have empty lists
    ?assertEqual([], maps:get(object_types, ParsedLog, [])),
    ?assertEqual([], maps:get(events, ParsedLog, [])),
    ?assertEqual(#{}, maps:get(objects, ParsedLog, #{})),

    ok.

%% Test 1.3: Parse OCEL with explicit version
test_parse_ocel_with_version() ->
    %% OCEL XES with version 2.0
    VersionedOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"2.0\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Item\"/>
  </event>
</log>">>,

    Result = yawl_object_centric_xes:parse_ocel_xes(VersionedOCEL),

    ?assertMatch({ok, #{version := <<"2.0">>}}, Result),

    ok.

%%====================================================================
%% Group 2: Object Type Extraction
%%====================================================================

test_group_object_types() ->
    test_extract_single_object_type(),
    test_extract_multiple_object_types(),
    test_extract_object_type_from_events(),
    test_deduplicate_object_types(),
    ok.

%% Test 2.1: Extract single object type
test_extract_single_object_type() ->
    SingleTypeOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
  <string key=\"ocel:object-type\" value=\"Customer\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"c1\"/>
    <string key=\"ocel:object-type\" value=\"Customer\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(SingleTypeOCEL),

    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assertEqual([<<"Customer">>], ObjectTypes),

    ok.

%% Test 2.2: Extract multiple object types
test_extract_multiple_object_types() ->
    MultipleTypesOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <string key=\"ocel:object-type\" value=\"Item\"/>
  <string key=\"ocel:object-type\" value=\"Customer\"/>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(MultipleTypesOCEL),

    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assertEqual(3, length(ObjectTypes)),
    ?assert(lists:member(<<"Order">>, ObjectTypes)),
    ?assert(lists:member(<<"Item">>, ObjectTypes)),
    ?assert(lists:member(<<"Customer">>, ObjectTypes)),

    ok.

%% Test 2.3: Extract object types from event attributes
test_extract_object_type_from_events() ->
    %% Object types can be declared in events
    EventTypesOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Product\"/>
  </event>
  <event xes:id=\"e2\">
    <string key=\"ocel:object-id\" value=\"o2\"/>
    <string key=\"ocel:object-type\" value=\"Resource\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(EventTypesOCEL),

    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assert(lists:member(<<"Product">>, ObjectTypes)),
    ?assert(lists:member(<<"Resource">>, ObjectTypes)),

    ok.

%% Test 2.4: Deduplicate object types
test_deduplicate_object_types() ->
    %% Same object type declared multiple times
    DuplicateTypesOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-type\" value=\"Order\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(DuplicateTypesOCEL),

    ObjectTypes = maps:get(object_types, ParsedLog),
    %% Should only appear once
    ?assertEqual([<<"Order">>], ObjectTypes),

    ok.

%%====================================================================
%% Group 3: Event Log Parsing
%%====================================================================

test_group_event_parsing() ->
    test_parse_single_event(),
    test_parse_multiple_events(),
    test_extract_event_attributes(),
    test_parse_event_timestamp(),
    test_parse_event_lifecycle(),
    ok.

%% Test 3.1: Parse single event
test_parse_single_event() ->
    SingleEventOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"event_001\">
    <string key=\"ocel:object-id\" value=\"order_123\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Submit Order\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T14:30:00.000Z\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"complete\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(SingleEventOCEL),

    Events = maps:get(events, ParsedLog),
    ?assertEqual(1, length(Events)),

    [Event] = Events,
    ?assertEqual(<<"event_001">>, maps:get(<<"event-id">>, Event)),
    ?assertEqual(<<"Submit Order">>, maps:get(<<"activity">>, Event)),
    ?assertEqual(<<"complete">>, maps:get(<<"lifecycle-transition">>, Event)),

    ok.

%% Test 3.2: Parse multiple events
test_parse_multiple_events() ->
    MultiEventOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Create\"/>
  </event>
  <event xes:id=\"e2\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Pay\"/>
  </event>
  <event xes:id=\"e3\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Ship\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(MultiEventOCEL),

    Events = maps:get(events, ParsedLog),
    ?assertEqual(3, length(Events)),

    %% Verify event order is preserved
    ActivityNames = [maps:get(<<"activity">>, E) || E <- Events],
    ?assertEqual([<<"Create">>, <<"Pay">>, <<"Ship">>], ActivityNames),

    ok.

%% Test 3.3: Extract event attributes
test_extract_event_attributes() ->
    AttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"concept:name\" value=\"Process\"/>
    <string key=\"ocel:priority\" value=\"high\"/>
    <int key=\"ocel:amount\" value=\"1000\"/>
    <float key=\"ocel:discount\" value=\"0.15\"/>
    <boolean key=\"ocel:expedited\" value=\"true\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(AttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    ?assertEqual(<<"high">>, maps:get(<<"ocel:priority">>, Event)),
    ?assertEqual(1000, maps:get(<<"ocel:amount">>, Event)),
    ?assertEqual(0.15, maps:get(<<"ocel:discount">>, Event)),
    ?assertEqual(true, maps:get(<<"ocel:expedited">>, Event)),

    ok.

%% Test 3.4: Parse event timestamp
test_parse_event_timestamp() ->
    TimestampOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T10:15:30.123Z\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(TimestampOCEL),

    [Event] = maps:get(events, ParsedLog),
    Timestamp = maps:get(<<"timestamp">>, Event),
    ?assert(is_integer(Timestamp)),
    ?assert(Timestamp > 0),

    ok.

%% Test 3.5: Parse event lifecycle transition
test_parse_event_lifecycle() ->
    LifecycleOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"start\"/>
  </event>
  <event xes:id=\"e2\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"complete\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(LifecycleOCEL),

    Events = maps:get(events, ParsedLog),
    [E1, E2] = Events,
    ?assertEqual(<<"start">>, maps:get(<<"lifecycle-transition">>, E1)),
    ?assertEqual(<<"complete">>, maps:get(<<"lifecycle-transition">>, E2)),

    ok.

%%====================================================================
%% Group 4: Multiple Object Types Per Event
%%====================================================================

test_group_multiple_objects() ->
    test_single_event_multiple_objects(),
    test_extract_all_object_types_from_event(),
    test_object_count_per_event(),
    ok.

%% Test 4.1: Single event with multiple objects
test_single_event_multiple_objects() ->
    MultiObjectOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"concept:name\" value=\"Order Item\"/>
    <string key=\"ocel:object-id\" value=\"order_123\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:object-id\" value=\"item_456\"/>
    <string key=\"ocel:object-type\" value=\"Item\"/>
    <string key=\"ocel:object-id\" value=\"customer_789\"/>
    <string key=\"ocel:object-type\" value=\"Customer\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(MultiObjectOCEL),

    [Event] = maps:get(events, ParsedLog),

    %% Event should have objects map with multiple types
    Objects = maps:get(objects, Event),
    ?assert(is_map(Objects)),
    ?assert(maps:is_key(<<"Order">>, Objects)),
    ?assert(maps:is_key(<<"Item">>, Objects)),
    ?assert(maps:is_key(<<"Customer">>, Objects)),

    %% Verify object IDs
    ?assertEqual([<<"order_123">>], maps:get(<<"Order">>, Objects)),
    ?assertEqual([<<"item_456">>], maps:get(<<"Item">>, Objects)),
    ?assertEqual([<<"customer_789">>], maps:get(<<"Customer">>, Objects)),

    ok.

%% Test 4.2: Extract all object types from multi-object event
test_extract_all_object_types_from_event() ->
    MultiObjTypeOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"TypeA\"/>
    <string key=\"ocel:object-id\" value=\"o2\"/>
    <string key=\"ocel:object-type\" value=\"TypeB\"/>
    <string key=\"ocel:object-id\" value=\"o3\"/>
    <string key=\"ocel:object-type\" value=\"TypeC\"/>
    <string key=\"ocel:object-id\" value=\"o4\"/>
    <string key=\"ocel:object-type\" value=\"TypeD\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(MultiObjTypeOCEL),

    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assertEqual(4, length(ObjectTypes)),
    ?assert(lists:member(<<"TypeA">>, ObjectTypes)),
    ?assert(lists:member(<<"TypeB">>, ObjectTypes)),
    ?assert(lists:member(<<"TypeC">>, ObjectTypes)),
    ?assert(lists:member(<<"TypeD">>, ObjectTypes)),

    ok.

%% Test 4.3: Object count per event
test_object_count_per_event() ->
    ObjectCountOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:object-id\" value=\"i1\"/>
    <string key=\"ocel:object-type\" value=\"Item\"/>
    <string key=\"ocel:object-id\" value=\"i2\"/>
    <string key=\"ocel:object-type\" value=\"Item\"/>
  </event>
  <event xes:id=\"e2\">
    <string key=\"ocel:object-id\" value=\"c1\"/>
    <string key=\"ocel:object-type\" value=\"Customer\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(ObjectCountOCEL),

    [E1, E2] = maps:get(events, ParsedLog),

    %% E1 should have 3 objects (1 Order + 2 Items)
    Objects1 = maps:get(objects, E1),
    ItemList = maps:get(<<"Item">>, Objects1, []),
    ?assertEqual(2, length(ItemList)),

    %% E2 should have 1 object
    Objects2 = maps:get(objects, E2),
    ?assertEqual([<<"c1">>], maps:get(<<"Customer">>, Objects2)),

    ok.

%%====================================================================
%% Group 5: OCEL Schema Validation
%%====================================================================

test_group_schema_validation() ->
    test_validate_ocel_extension_present(),
    test_validate_required_attributes(),
    test_validate_event_structure(),
    test_validate_object_references(),
    ok.

%% Test 5.1: Validate OCEL extension is present
test_validate_ocel_extension_present() ->
    %% Valid OCEL XES with proper extension
    ValidOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(ValidOCEL),
    ?assertMatch(#{}, ParsedLog),

    ok.

%% Test 5.2: Validate required OCEL attributes
test_validate_required_attributes() ->
    %% Missing required object-type attribute
    MissingRequiredOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
  </event>
</log>">>,

    %% Should handle gracefully (return empty list for object types)
    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(MissingRequiredOCEL),
    ObjectTypes = maps:get(object_types, ParsedLog, []),
    ?assert(is_list(ObjectTypes)),

    ok.

%% Test 5.3: Validate event structure
test_validate_event_structure() ->
    MalformedEventOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event>
  </event>
</log>">>,

    %% Should handle events without ID gracefully
    Result = yawl_object_centric_xes:parse_ocel_xes(MalformedEventOCEL),
    ?assertMatch({ok, _}, Result),

    ok.

%% Test 5.4: Validate object references
test_validate_object_references() ->
    %% Event referencing object ID
    ObjectRefOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"order_abc_123\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(ObjectRefOCEL),

    [Event] = maps:get(events, ParsedLog),
    Objects = maps:get(objects, Event, #{}),
    ?assertEqual([<<"order_abc_123">>], maps:get(<<"Order">>, Objects)),

    ok.

%%====================================================================
%% Group 6: Error Handling
%%====================================================================

test_group_error_handling() ->
    test_invalid_xml(),
    test_empty_input(),
    test_missing_log_element(),
    test_missing_ocel_extension(),
    test_non_binary_input(),
    ok.

%% Test 6.1: Invalid XML
test_invalid_xml() ->
    InvalidXMLOCEL = <<"<not><valid><xml>">>,

    Result = yawl_object_centric_xes:parse_ocel_xes(InvalidXMLOCEL),

    %% Should return error for invalid XML
    ?assertMatch({error, _}, Result),

    ok.

%% Test 6.2: Empty input
test_empty_input() ->
    EmptyOCEL = <<>>,

    Result = yawl_object_centric_xes:parse_ocel_xes(EmptyOCEL),

    %% Should return error for empty input
    ?assertMatch({error, _}, Result),

    ok.

%% Test 6.3: Missing log element
test_missing_log_element() ->
    NoLogOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<notlog>
  <event xes:id=\"e1\"></event>
</notlog>">>,

    Result = yawl_object_centric_xes:parse_ocel_xes(NoLogOCEL),

    %% Should return error when log element is missing
    ?assertMatch({error, _}, Result),

    ok.

%% Test 6.4: Missing OCEL extension
test_missing_ocel_extension() ->
    NoExtensionOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <event xes:id=\"e1\">
    <string key=\"concept:name\" value=\"Task\"/>
  </event>
</log>">>,

    %% Should still parse but note lack of OCEL extension
    Result = yawl_object_centric_xes:parse_ocel_xes(NoExtensionOCEL),
    ?assertMatch({ok, _}, Result),

    ok.

%% Test 6.5: Non-binary input
test_non_binary_input() ->
    %% Test with list input
    Result1 = catch yawl_object_centric_xes:parse_ocel_xes("not a binary"),
    ?assertMatch({error, _}, Result1),

    %% Test with atom input
    Result2 = catch yawl_object_centric_xes:parse_ocel_xes(invalid_type),
    ?assertMatch({error, _}, Result2),

    ok.

%%====================================================================
%% Group 7: OCEL Attribute Extraction
%%====================================================================

test_group_attribute_extraction() ->
    test_extract_ocel_string_attributes(),
    test_extract_ocel_integer_attributes(),
    test_extract_ocel_float_attributes(),
    test_extract_ocel_boolean_attributes(),
    test_extract_ocel_date_attributes(),
    ok.

%% Test 7.1: Extract OCEL string attributes
test_extract_ocel_string_attributes() ->
    StringAttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:status\" value=\"pending\"/>
    <string key=\"ocel:region\" value=\"North America\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(StringAttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    ?assertEqual(<<"pending">>, maps:get(<<"ocel:status">>, Event)),
    ?assertEqual(<<"North America">>, maps:get(<<"ocel:region">>, Event)),

    ok.

%% Test 7.2: Extract OCEL integer attributes
test_extract_ocel_integer_attributes() ->
    IntAttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <int key=\"ocel:quantity\" value=\"5\"/>
    <int key=\"ocel:priority\" value=\"1\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(IntAttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    ?assertEqual(5, maps:get(<<"ocel:quantity">>, Event)),
    ?assertEqual(1, maps:get(<<"ocel:priority">>, Event)),

    ok.

%% Test 7.3: Extract OCEL float attributes
test_extract_ocel_float_attributes() ->
    FloatAttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <float key=\"ocel:total\" value=\"99.99\"/>
    <float key=\"ocel:tax_rate\" value=\"0.0825\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(FloatAttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    ?assertEqual(99.99, maps:get(<<"ocel:total">>, Event)),
    ?assertEqual(0.0825, maps:get(<<"ocel:tax_rate">>, Event)),

    ok.

%% Test 7.4: Extract OCEL boolean attributes
test_extract_ocel_boolean_attributes() ->
    BoolAttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <boolean key=\"ocel:paid\" value=\"true\"/>
    <boolean key=\"ocel:shipped\" value=\"false\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(BoolAttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    ?assertEqual(true, maps:get(<<"ocel:paid">>, Event)),
    ?assertEqual(false, maps:get(<<"ocel:shipped">>, Event)),

    ok.

%% Test 7.5: Extract OCEL date attributes
test_extract_ocel_date_attributes() ->
    DateAttrsOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"e1\">
    <string key=\"ocel:object-id\" value=\"o1\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <date key=\"ocel:order_date\" value=\"2024-02-05T00:00:00.000Z\"/>
    <date key=\"ocel:delivery_date\" value=\"2024-02-10T00:00:00.000Z\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(DateAttrsOCEL),

    [Event] = maps:get(events, ParsedLog),
    OrderDate = maps:get(<<"ocel:order_date">>, Event),
    DeliveryDate = maps:get(<<"ocel:delivery_date">>, Event),
    ?assert(is_integer(OrderDate)),
    ?assert(is_integer(DeliveryDate)),
    ?assert(OrderDate < DeliveryDate),

    ok.

%%====================================================================
%% Group 8: Real-world OCEL Scenarios
%%====================================================================

test_group_real_world() ->
    test_order_fulfillment_scenario(),
    test_p2p_payment_scenario(),
    test_supply_chain_scenario(),
    ok.

%% Test 8.1: Order fulfillment scenario
test_order_fulfillment_scenario() ->
    %% Realistic OCEL for order processing
    OrderFulfillmentOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
  <string key=\"ocel:object-type\" value=\"Order\"/>
  <string key=\"ocel:object-type\" value=\"Item\"/>
  <string key=\"ocel:object-type\" value=\"Customer\"/>
  <string key=\"ocel:object-type\" value=\"Payment\"/>

  <event xes:id=\"e1\">
    <string key=\"concept:name\" value=\"Create Order\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T09:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"order_001\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:object-id\" value=\"customer_001\"/>
    <string key=\"ocel:object-type\" value=\"Customer\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"complete\"/>
  </event>

  <event xes:id=\"e2\">
    <string key=\"concept:name\" value=\"Add Item\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T09:01:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"order_001\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:object-id\" value=\"item_001\"/>
    <string key=\"ocel:object-type\" value=\"Item\"/>
    <int key=\"ocel:quantity\" value=\"2\"/>
  </event>

  <event xes:id=\"e3\">
    <string key=\"concept:name\" value=\"Process Payment\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T09:05:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"order_001\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:object-id\" value=\"payment_001\"/>
    <string key=\"ocel:object-type\" value=\"Payment\"/>
    <float key=\"ocel:amount\" value=\"149.99\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"complete\"/>
  </event>

  <event xes:id=\"e4\">
    <string key=\"concept:name\" value=\"Ship Order\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T14:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"order_001\"/>
    <string key=\"ocel:object-type\" value=\"Order\"/>
    <string key=\"ocel:lifecycle-transition\" value=\"complete\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(OrderFulfillmentOCEL),

    %% Verify object types
    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assertEqual(4, length(ObjectTypes)),

    %% Verify event count
    Events = maps:get(events, ParsedLog),
    ?assertEqual(4, length(Events)),

    %% Verify order lifecycle
    Activities = [maps:get(<<"activity">>, E) || E <- Events],
    ?assertEqual([<<"Create Order">>, <<"Add Item">>, <<"Process Payment">>, <<"Ship Order">>],
                 Activities),

    %% Verify payment amount
    PaymentEvent = find_by_activity(<<"Process Payment">>, Events),
    ?assertEqual(149.99, maps:get(<<"ocel:amount">>, PaymentEvent)),

    ok.

%% Test 8.2: P2P payment scenario
test_p2p_payment_scenario() ->
    P2POCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <event xes:id=\"p2p_001\">
    <string key=\"concept:name\" value=\"Initiate Payment\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T12:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"user_alice\"/>
    <string key=\"ocel:object-type\" value=\"User\"/>
    <string key=\"ocel:object-id\" value=\"user_bob\"/>
    <string key=\"ocel:object-type\" value=\"User\"/>
    <string key=\"ocel:object-id\" value=\"payment_tx_123\"/>
    <string key=\"ocel:object-type\" value=\"Transaction\"/>
    <float key=\"ocel:amount\" value=\"50.00\"/>
    <string key=\"ocel:currency\" value=\"USD\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(P2POCEL),

    [Event] = maps:get(events, ParsedLog),

    %% Verify multi-object event
    Objects = maps:get(objects, Event),
    ?assertEqual(2, length(maps:keys(Objects))),

    %% Verify transaction amount
    ?assertEqual(50.00, maps:get(<<"ocel:amount">>, Event)),
    ?assertEqual(<<"USD">>, maps:get(<<"ocel:currency">>, Event)),

    ok.

%% Test 8.3: Supply chain scenario
test_supply_chain_scenario() ->
    SupplyChainOCEL = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">
  <extension name=\"Object-Centric\" prefix=\"ocel\" uri=\"http://www.xes-standard.org/ocel.xesext\"/>
  <string key=\"ocel:version\" value=\"1.0\"/>
  <string key=\"ocel:object-type\" value=\"Product\"/>
  <string key=\"ocel:object-type\" value=\"Warehouse\"/>
  <string key=\"ocel:object-type\" value=\"Shipment\"/>
  <string key=\"ocel:object-type\" value=\"Carrier\"/>

  <event xes:id=\"sc_001\">
    <string key=\"concept:name\" value=\"Manufacture\"/>
    <date key=\"time:timestamp\" value=\"2024-02-01T08:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"prod_sku_001\"/>
    <string key=\"ocel:object-type\" value=\"Product\"/>
    <string key=\"ocel:object-id\" value=\"warehouse_ny\"/>
    <string key=\"ocel:object-type\" value=\"Warehouse\"/>
    <int key=\"ocel:batch_size\" value=\"1000\"/>
  </event>

  <event xes:id=\"sc_002\">
    <string key=\"concept:name\" value=\"Ship\"/>
    <date key=\"time:timestamp\" value=\"2024-02-02T10:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"shipment_trk_001\"/>
    <string key=\"ocel:object-type\" value=\"Shipment\"/>
    <string key=\"ocel:object-id\" value=\"warehouse_ny\"/>
    <string key=\"ocel:object-type\" value=\"Warehouse\"/>
    <string key=\"ocel:object-id\" value=\"carrier_fedex\"/>
    <string key=\"ocel:object-type\" value=\"Carrier\"/>
  </event>

  <event xes:id=\"sc_003\">
    <string key=\"concept:name\" value=\"Deliver\"/>
    <date key=\"time:timestamp\" value=\"2024-02-05T15:00:00.000Z\"/>
    <string key=\"ocel:object-id\" value=\"shipment_trk_001\"/>
    <string key=\"ocel:object-type\" value=\"Shipment\"/>
    <string key=\"ocel:object-id\" value=\"prod_sku_001\"/>
    <string key=\"ocel:object-type\" value=\"Product\"/>
    <boolean key=\"ocel:delivered\" value=\"true\"/>
  </event>
</log>">>,

    {ok, ParsedLog} = yawl_object_centric_xes:parse_ocel_xes(SupplyChainOCEL),

    %% Verify all object types captured
    ObjectTypes = maps:get(object_types, ParsedLog),
    ?assertEqual(4, length(ObjectTypes)),

    %% Verify event flow
    Events = maps:get(events, ParsedLog),
    ?assertEqual(3, length(Events)),

    %% Verify delivered status
    DeliverEvent = lists:nth(3, Events),
    ?assertEqual(true, maps:get(<<"ocel:delivered">>, DeliverEvent)),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Find event by activity name
find_by_activity(_Activity, []) ->
    undefined;
find_by_activity(Activity, [Event | Rest]) ->
    case maps:get(<<"activity">>, Event, undefined) of
        Activity -> Event;
        _ -> find_by_activity(Activity, Rest)
    end.

%% @private
%% @doc Find element in list of maps by key value
find_by_key(_Key, _Value, []) ->
    undefined;
find_by_key(Key, Value, [Map | Rest]) ->
    case maps:get(Key, Map, undefined) of
        Value -> Map;
        _ -> find_by_key(Key, Value, Rest)
    end.
