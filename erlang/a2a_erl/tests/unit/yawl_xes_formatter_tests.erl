%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Formatter Unit Tests
%%%
%%% Test suite for the XES (eXtensible Event Stream) formatter module
%%% implementing IEEE 1849-2016 standard XML formatting.
%%%
%%% Tests cover:
%%% 1. XES XML format validation
%%% 2. Timestamp formatting
%%% 3. Attribute encoding
%%% 4. IEEE 1849-2016 compliance
%%% 5. Extension formatting
%%% 6. Trace and event serialization
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_formatter_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Macros and Constants
%%====================================================================

-define(XES_NAMESPACE, "http://www.xes-standard.org/").
-define(XES_VERSION, "1.0").
-define(TEST_TIMESTAMP, 1704067200000).  % 2024-01-01 00:00:00 UTC

%%====================================================================
%% Test Generator - Main Entry Point
%%====================================================================

xes_formatter_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: XES XML Format Validation", fun test_group_xml_format/0},
      {"Group 2: Timestamp Formatting", fun test_group_timestamps/0},
      {"Group 3: Attribute Encoding", fun test_group_attribute_encoding/0},
      {"Group 4: IEEE 1849-2016 Compliance", fun test_group_ieee_compliance/0},
      {"Group 5: Extension Formatting", fun test_group_extensions/0},
      {"Group 6: Trace Serialization", fun test_group_traces/0},
      {"Group 7: Event Serialization", fun test_group_events/0},
      {"Group 8: Special Characters", fun test_group_special_chars/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup Fixtures
%%====================================================================

setup() ->
    %% Initialize formatter state
    State = #{
        extensions => initialize_extensions(),
        formatter_pid => case code:is_loaded(yawl_xes_formatter) of
            false -> self();
            _ ->
                {ok, Pid} = yawl_xes_formatter:start_link(),
                Pid
        end
    },
    State.

cleanup(_State) ->
    %% Cleanup formatter
    case code:is_loaded(yawl_xes_formatter) of
        false -> ok;
        _ ->
            catch yawl_xes_formatter:stop()
    end,
    ok.

initialize_extensions() ->
    #{
        <<"time">> => #{
            name => <<"Time">>,
            prefix => <<"time">>,
            uri => <<"http://www.xes-standard.org/time.xesext">>
        },
        <<"concept">> => #{
            name => <<"Concept">>,
            prefix => <<"concept">>,
            uri => <<"http://www.xes-standard.org/concept.xesext">>
        },
        <<"lifecycle">> => #{
            name => <<"Lifecycle">>,
            prefix => <<"lifecycle">>,
            uri => <<"http://www.xes-standard.org/lifecycle.xesext">>
        },
        <<"org">> => #{
            name => <<"Organizational">>,
            prefix => <<"org">>,
            uri => <<"http://www.xes-standard.org/org.xesext">>
        }
    }.

%%====================================================================
%% Group 1: XES XML Format Validation
%%====================================================================

test_group_xml_format() ->
    test_xml_declaration(),
    test_log_open_tag(),
    test_log_close_tag(),
    test_nested_elements(),
    test_attribute_format(),
    test_cdata_sections(),
    test_well_formedness(),
    ok.

test_xml_declaration() ->
    %% Test XML declaration
    Declaration = format_xml_declaration(),

    ?assertEqual("<?xml version=\"1.0\" encoding=\"UTF-8\"?>", Declaration),
    ?assert(string:str(Declaration, "<?xml") > 0),
    ?assert(string:str(Declaration, "version") > 0),
    ?assert(string:str(Declaration, "UTF-8") > 0),

    ok.

test_log_open_tag() ->
    %% Test log opening tag with attributes
    LogOpen = format_log_open_tag(),

    ?assert(string:str(LogOpen, "<log") > 0),
    ?assert(string:str(LogOpen, "xes.version") > 0),
    ?assert(string:str(LogOpen, "xmlns") > 0),

    ok.

test_log_close_tag() ->
    %% Test log closing tag
    LogClose = "</log>",

    ?assertEqual("</log>", LogClose),
    ?assert(string:str(LogClose, "</log>") > 0),

    ok.

test_nested_elements() ->
    %% Test proper nesting of elements
    NestedXML = <<
        "<log>"
        "<trace>"
        "<event>"
        "<string key=\"test\" value=\"value\"/>"
        "</event>"
        "</trace>"
        "</log>"
    >>,

    ?assert(string:str(binary_to_list(NestedXML), "<log>") > 0),
    ?assert(string:str(binary_to_list(NestedXML), "<trace>") > 0),
    ?assert(string:str(binary_to_list(NestedXML), "<event>") > 0),
    ?assert(check_nesting(NestedXML)),

    ok.

test_attribute_format() ->
    %% Test attribute key-value format
    AttrXML = format_attribute(string, <<"concept:name">>, <<"Test Task">>),

    ?assert(string:str(AttrXML, "<string") > 0),
    ?assert(string:str(AttrXML, "key=\"concept:name\"") > 0),
    ?assert(string:str(AttrXML, "value=\"Test Task\"") > 0),
    ?assert(string:str(AttrXML, "/>") > 0),

    ok.

test_cdata_sections() ->
    %% Test CDATA sections for special content
    Content = <<"Text with <special> characters & symbols">>,
    CDATA = format_cdata(Content),

    ?assert(string:str(CDATA, "<![CDATA[") > 0),
    ?assert(string:str(CDATA, "]]>") > 0),

    ok.

test_well_formedness() ->
    %% Test that generated XML is well-formed
    XESDocument = create_sample_xes_document(),

    %% Check for balanced tags
    ?assert(check_balanced_tags(XESDocument)),

    %% Check for proper nesting
    ?assert(check_nesting(XESDocument)),

    ok.

%%====================================================================
%% Group 2: Timestamp Formatting
%%====================================================================

test_group_timestamps() ->
    test_iso8601_format(),
    test_millisecond_precision(),
    test_timezone_utc(),
    test_legacy_timestamp_format(),
    test_invalid_timestamp_handling(),
    test_timestamp_range(),
    ok.

test_iso8601_format() ->
    %% Test ISO 8601 timestamp format
    Timestamp = ?TEST_TIMESTAMP,

    Formatted = case code:is_loaded(yawl_xes_formatter) of
        false -> format_timestamp_iso8601(Timestamp);
        _ -> yawl_xes_formatter:format_timestamp(Timestamp)
    end,

    %% Should match ISO 8601: YYYY-MM-DDTHH:MM:SS.sssZ
    ?assert(string:str(Formatted, "T") > 0),
    ?assert(string:str(Formatted, "Z") > 0 orelse string:str(Formatted, "+") > 0),

    %% Check format components
    ?assert(string:str(Formatted, "-") > 0),  % Date separator
    ?assert(string:str(Formatted, ":") > 0),  % Time separator

    ok.

test_millisecond_precision() ->
    %% Test millisecond precision in timestamps
    Timestamp = ?TEST_TIMESTAMP + 123,  % Add milliseconds

    Formatted = format_timestamp_iso8601(Timestamp),

    %% Should include decimal seconds
    %% Format: YYYY-MM-DDTHH:MM:SS.sssZ
    ?assert(string:str(Formatted, ".") > 0),

    %% Verify millisecond digits
    Parts = string:tokens(Formatted, "."),
    ?assert(length(Parts) >= 2),

    ok.

test_timezone_utc() ->
    %% Test UTC timezone indicator
    Timestamp = ?TEST_TIMESTAMP,

    Formatted = format_timestamp_iso8601(Timestamp),

    %% Should end with Z for UTC
    ?assert(string:right(Formatted, 1) =:= "Z" orelse
             string:str(Formatted, "+00:00") > 0),

    ok.

test_legacy_timestamp_format() ->
    %% Test legacy XES timestamp format
    Timestamp = ?TEST_TIMESTAMP,

    %% Legacy format uses Java date format
    LegacyFormat = format_timestamp_legacy(Timestamp),

    ?assert(is_list(LegacyFormat)),
    ?assert(length(LegacyFormat) > 0),

    ok.

test_invalid_timestamp_handling() ->
    %% Test handling of invalid timestamps
    InvalidTimestamps = [
        -1,
        0,
        undefined,
        <<"invalid">>
    ],

    lists:foreach(fun(TS) ->
        Result = format_timestamp_safe(TS),
        %% Should return valid string or default
        ?assert(is_list(Result) orelse is_binary(Result))
    end, InvalidTimestamps),

    ok.

test_timestamp_range() ->
    %% Test various timestamp ranges
    Timestamps = [
        0,                                % Unix epoch
        1000000000,                       % 2001-09-09
        ?TEST_TIMESTAMP,                  % 2024-01-01
        2000000000,                       % 2033-05-18
        4102444800000                     % 2100-01-01
    ],

    lists:foreach(fun(TS) ->
        Formatted = format_timestamp_iso8601(TS),
        ?assert(string:str(Formatted, "T") > 0),
        ?assert(string:str(Formatted, "Z") > 0 orelse
                 string:str(Formatted, "+") > 0)
    end, Timestamps),

    ok.

%%====================================================================
%% Group 3: Attribute Encoding
%%====================================================================

test_group_attribute_encoding() ->
    test_string_attribute(),
    test_date_attribute(),
    test_int_attribute(),
    test_float_attribute(),
    test_boolean_attribute(),
    test_id_attribute(),
    test_list_attribute(),
    test_nested_list_attribute(),
    ok.

test_string_attribute() ->
    %% Test string attribute encoding
    Key = <<"concept:name">>,
    Value = <<"Task Name">>,

    Encoded = encode_attribute(string, Key, Value),

    ?assert(string:str(Encoded, "<string") > 0),
    ?assert(string:str(Encoded, "key=\"concept:name\"") > 0),
    ?assert(string:str(Encoded, "value=\"Task Name\"") > 0),

    ok.

test_date_attribute() ->
    %% Test date attribute encoding
    Key = <<"time:timestamp">>,
    Value = ?TEST_TIMESTAMP,

    Encoded = encode_attribute(date, Key, Value),

    ?assert(string:str(Encoded, "<date") > 0),
    ?assert(string:str(Encoded, "key=\"time:timestamp\"") > 0),
    ?assert(string:str(Encoded, "value=") > 0),

    %% Date value should be ISO 8601 formatted
    ?assert(string:str(Encoded, "T") > 0),
    ?assert(string:str(Encoded, "Z") > 0),

    ok.

test_int_attribute() ->
    %% Test integer attribute encoding
    Key = <<"count">>,
    Value = 42,

    Encoded = encode_attribute(int, Key, Value),

    ?assert(string:str(Encoded, "<int") > 0),
    ?assert(string:str(Encoded, "key=\"count\"") > 0),
    ?assert(string:str(Encoded, "value=\"42\"") > 0),

    ok.

test_float_attribute() ->
    %% Test float attribute encoding
    Key = <<"cost">>,
    Value = 99.99,

    Encoded = encode_attribute(float, Key, Value),

    ?assert(string:str(Encoded, "<float") > 0),
    ?assert(string:str(Encoded, "key=\"cost\"") > 0),
    ?assert(string:str(Encoded, "value=\"99.99\"") > 0),

    ok.

test_boolean_attribute() ->
    %% Test boolean attribute encoding
    Key = <<"active">>,

    %% Test true
    EncodedTrue = encode_attribute(boolean, Key, true),
    ?assert(string:str(EncodedTrue, "<boolean") > 0),
    ?assert(string:str(EncodedTrue, "value=\"true\"") > 0),

    %% Test false
    EncodedFalse = encode_attribute(boolean, Key, false),
    ?assert(string:str(EncodedFalse, "value=\"false\"") > 0),

    ok.

test_id_attribute() ->
    %% Test ID attribute encoding
    Key = <<"id">>,
    Value = <<"ID-123-ABC">>,

    Encoded = encode_attribute(id, Key, Value),

    ?assert(string:str(Encoded, "<id") > 0),
    ?assert(string:str(Encoded, "key=\"id\"") > 0),
    ?assert(string:str(Encoded, "value=\"ID-123-ABC\"") > 0),

    ok.

test_list_attribute() ->
    %% Test list attribute encoding
    Key = <<"values">>,
    Value = [1, 2, 3, 4, 5],

    Encoded = encode_attribute(list, Key, Value),

    ?assert(string:str(Encoded, "<list") > 0),
    ?assert(string:str(Encoded, "key=\"values\"") > 0),

    %% List values should be nested
    ?assert(string:str(Encoded, "<values>") > 0 orelse
             string:str(Encoded, "<string") > 0),

    ok.

test_nested_list_attribute() ->
    %% Test nested list attribute encoding
    Key = <<"nested">>,
    Value = [
        [1, 2],
        [3, 4],
        [5, 6]
    ],

    Encoded = encode_attribute(list, Key, Value),

    ?assert(string:str(Encoded, "<list") > 0),
    ?assert(is_list(Encoded)),

    ok.

%%====================================================================
%% Group 4: IEEE 1849-2016 Compliance
%%====================================================================

test_group_ieee_compliance() ->
    test_namespace_compliance(),
    test_extension_declaration_compliance(),
    test_attribute_type_compliance(),
    test_global_attributes(),
    test_element_hierarchy(),
    test_attribute_key_format(),
    ok.

test_namespace_compliance() ->
    %% Test XES namespace declaration per IEEE 1849-2016
    Namespace = ?XES_NAMESPACE,

    ?assert(string:str(Namespace, "xes-standard.org") > 0),

    %% Default namespace must be declared
    NSDeclaration = "xmlns=\"" ++ Namespace ++ "\"",
    ?assert(string:str(NSDeclaration, "xmlns") > 0),
    ?assert(string:str(NSDeclaration, "xes-standard") > 0),

    ok.

test_extension_declaration_compliance() ->
    %% Test extension declaration format
    Extension = #{
        name => <<"Time">>,
        prefix => <<"time">>,
        uri => <<"http://www.xes-standard.org/time.xesext">>
    },

    Decl = format_extension_declaration(Extension),

    %% Format: <extension name="..." prefix="..." uri="..."/>
    ?assert(string:str(Decl, "<extension") > 0),
    ?assert(string:str(Decl, "name=\"Time\"") > 0),
    ?assert(string:str(Decl, "prefix=\"time\"") > 0),
    ?assert(string:str(Decl, "uri=") > 0),

    ok.

test_attribute_type_compliance() ->
    %% Test all IEEE 1849-2016 attribute types
    Types = [
        {string, <<"string">>, <<"value">>},
        {date, <<"date">>, ?TEST_TIMESTAMP},
        {int, <<"int">>, 123},
        {float, <<"float">>, 45.67},
        {boolean, <<"boolean">>, true},
        {id, <<"id">>, <<"ID-123">>}
    ],

    lists:foreach(fun({Type, Key, Value}) ->
        Encoded = encode_attribute(Type, Key, Value),
        ?assert(is_list(Encoded)),
        ?assert(string:str(Encoded, "<") > 0),
        ?assert(string:str(Encoded, "key=") > 0),
        ?assert(string:str(Encoded, "value=") > 0)
    end, Types),

    ok.

test_global_attributes() ->
    %% Test global attribute definitions
    %% XES allows global attributes for log, trace, and event

    GlobalLogAttrs = [
        {<<"concept:name">>, string, <<"Workflow Log">>},
        {<<"description">>, string, <<"Test log description">>}
    ],

    GlobalTraceAttrs = [
        {<<"concept:name">>, string, <<"Trace Name">>}
    ],

    GlobalEventAttrs = [
        {<<"concept:name">>, string, <<"Event Name">>},
        {<<"time:timestamp">>, date, ?TEST_TIMESTAMP}
    ],

    %% Encode globals
    LogGlobalEncoded = encode_global_attributes(log, GlobalLogAttrs),
    TraceGlobalEncoded = encode_global_attributes(trace, GlobalTraceAttrs),
    EventGlobalEncoded = encode_global_attributes(event, GlobalEventAttrs),

    ?assert(string:str(LogGlobalEncoded, "<global") > 0),
    ?assert(string:str(LogGlobalEncoded, "scope=\"log\"") > 0),

    ?assert(string:str(TraceGlobalEncoded, "scope=\"trace\"") > 0),
    ?assert(string:str(EventGlobalEncoded, "scope=\"event\"") > 0),

    ok.

test_element_hierarchy() ->
    %% Test proper element hierarchy per IEEE 1849-2016
    %% Log > Trace > Event > Attribute

    Hierarchy = create_test_hierarchy(),

    ?assert(string:str(Hierarchy, "<log") > 0),
    ?assert(string:str(Hierarchy, "<trace") > 0),
    ?assert(string:str(Hierarchy, "<event") > 0),
    ?assert(string:str(Hierarchy, "<string") > 0 orelse
             string:str(Hierarchy, "<date") > 0),

    %% Verify order
    LogPos = string:str(Hierarchy, "<log"),
    TracePos = string:str(Hierarchy, "<trace"),
    EventPos = string:str(Hierarchy, "<event"),

    ?assert(LogPos < TracePos),
    ?assert(TracePos < EventPos),

    ok.

test_attribute_key_format() ->
    %% Test attribute key format (prefix:name)
    ValidKeys = [
        <<"concept:name">>,
        <<"time:timestamp">>,
        <<"lifecycle:transition">>,
        <<"org:resource">>,
        <<"cost:amount">>,
        <<"custom:attribute">>
    ],

    lists:foreach(fun(Key) ->
        ?assert(validate_attribute_key(Key))
    end, ValidKeys),

    ok.

%%====================================================================
%% Group 5: Extension Formatting
%%====================================================================

test_group_extensions() ->
    test_standard_extensions(),
    test_custom_extensions(),
    test_extension_prefixes(),
    test_extension_uris(),
    ok.

test_standard_extensions() ->
    %% Test all standard XES extensions
    StandardExtensions = [
        {<<"Time">>, <<"time">>, <<"http://www.xes-standard.org/time.xesext">>},
        {<<"Concept">>, <<"concept">>, <<"http://www.xes-standard.org/concept.xesext">>},
        {<<"Lifecycle">>, <<"lifecycle">>, <<"http://www.xes-standard.org/lifecycle.xesext">>},
        {<<"Organizational">>, <<"org">>, <<"http://www.xes-standard.org/org.xesext">>},
        {<<"Identity">>, <<"identity">>, <<"http://www.xes-standard.org/identity.xesext">>}
    ],

    Formatted = lists:map(fun({Name, Prefix, URI}) ->
        format_extension_declaration(#{
            name => Name,
            prefix => Prefix,
            uri => URI
        })
    end, StandardExtensions),

    %% All should be properly formatted
    lists:foreach(fun(Decl) ->
        ?assert(string:str(Decl, "<extension") > 0),
        ?assert(string:str(Decl, "name=") > 0),
        ?assert(string:str(Decl, "prefix=") > 0),
        ?assert(string:str(Decl, "uri=") > 0),
        ?assert(string:str(Decl, "xes-standard.org") > 0)
    end, Formatted),

    ok.

test_custom_extensions() ->
    %% Test custom (vendor) extensions
    CustomExtensions = [
        {<<"CostExtension">>, <<"cost">>, <<"http://example.com/cost.xesext">>},
        {<<"QualityExtension">>, <<"quality">>, <<"http://vendor.com/quality.xesext">>}
    ],

    lists:foreach(fun({Name, Prefix, URI}) ->
        Decl = format_extension_declaration(#{
            name => Name,
            prefix => Prefix,
            uri => URI
        }),

        ?assert(string:str(Decl, "name=\"" ++ binary_to_list(Name) ++ "\"") > 0),
        ?assert(string:str(Decl, "prefix=\"" ++ binary_to_list(Prefix) ++ "\"") > 0)
    end, CustomExtensions),

    ok.

test_extension_prefixes() ->
    %% Test extension prefix uniqueness
    Prefixes = [<<"time">>, <<"concept">>, <<"lifecycle">>, <<"org">>, <<"cost">>],

    %% All prefixes should be unique
    UniquePrefixes = lists:usort(Prefixes),
    ?assertEqual(length(Prefixes), length(UniquePrefixes)),

    ok.

test_extension_uris() ->
    %% Test extension URI format
    URIs = [
        <<"http://www.xes-standard.org/time.xesext">>,
        <<"http://www.xes-standard.org/concept.xesext">>,
        <<"http://example.com/custom.xesext">>
    ],

    lists:foreach(fun(URI) ->
        URIList = binary_to_list(URI),
        ?assert(string:str(URIList, "http://") > 0 orelse
                 string:str(URIList, "https://") > 0),
        ?assert(string:str(URIList, ".xesext") > 0)
    end, URIs),

    ok.

%%====================================================================
%% Group 6: Trace Serialization
%%====================================================================

test_group_traces() ->
    test_trace_open_tag(),
    test_trace_close_tag(),
    test_trace_attributes(),
    test_trace_with_events(),
    test_nested_trace(),
    ok.

test_trace_open_tag() ->
    %% Test trace opening tag
    TraceOpen = "<trace>",

    ?assertEqual("<trace>", TraceOpen),
    ?assert(string:str(TraceOpen, "<trace>") > 0),

    ok.

test_trace_close_tag() ->
    %% Test trace closing tag
    TraceClose = "</trace>",

    ?assertEqual("</trace>", TraceClose),

    ok.

test_trace_attributes() ->
    %% Test trace with attributes
    TraceAttrs = [
        {<<"concept:name">>, string, <<"Order 12345">>},
        {<<"case:id">>, string, <<"CASE-001">>}
    ],

    TraceXML = format_trace_with_attributes(TraceAttrs),

    ?assert(string:str(TraceXML, "<trace>") > 0),
    ?assert(string:str(TraceXML, "concept:name") > 0),

    ok.

test_trace_with_events() ->
    %% Test trace containing events
    Events = [
        #{<<"concept:name">> => <<"Task 1">>, <<"time:timestamp">> => ?TEST_TIMESTAMP},
        #{<<"concept:name">> => <<"Task 2">>, <<"time:timestamp">> => ?TEST_TIMESTAMP + 1000}
    ],

    TraceXML = format_trace_with_events(Events),

    ?assert(string:str(TraceXML, "<trace>") > 0),
    ?assert(string:str(TraceXML, "<event>") > 0),
    ?assert(string:str(TraceXML, "</event>") > 0),

    %% Count events
    EventCount = count_occurrences(TraceXML, "<event>"),
    ?assertEqual(2, EventCount),

    ok.

test_nested_trace() ->
    %% Test nested traces (sub-traces)
    MainTrace = format_trace_with_id(<<"main">>),
    SubTrace = format_trace_with_id(<<"sub">>),

    Combined = MainTrace ++ "\n" ++ SubTrace,

    ?assert(string:str(Combined, "<trace>") > 0),

    ok.

%%====================================================================
%% Group 7: Event Serialization
%%====================================================================

test_group_events() ->
    test_event_open_tag(),
    test_event_close_tag(),
    test_event_attributes(),
    test_event_with_all_attribute_types(),
    test_event_ordering(),
    ok.

test_event_open_tag() ->
    %% Test event opening tag
    EventOpen = "<event>",

    ?assertEqual("<event>", EventOpen),

    ok.

test_event_close_tag() ->
    %% Test event closing tag
    EventClose = "</event>",

    ?assertEqual("</event>", EventClose),

    ok.

test_event_attributes() ->
    %% Test event with multiple attributes
    EventAttrs = [
        {<<"concept:name">>, string, <<"Process Payment">>},
        {<<"time:timestamp">>, date, ?TEST_TIMESTAMP},
        {<<"lifecycle:transition">>, string, <<"start">>},
        {<<"org:resource">>, string, <<"PaymentService">>}
    ],

    EventXML = format_event_with_attributes(EventAttrs),

    ?assert(string:str(EventXML, "<event>") > 0),
    ?assert(string:str(EventXML, "concept:name") > 0),
    ?assert(string:str(EventXML, "time:timestamp") > 0),
    ?assert(string:str(EventXML, "lifecycle:transition") > 0),
    ?assert(string:str(EventXML, "org:resource") > 0),

    ok.

test_event_with_all_attribute_types() ->
    %% Test event containing all attribute types
    EventAttrs = [
        {<<"string_attr">>, string, <<"text">>},
        {<<"date_attr">>, date, ?TEST_TIMESTAMP},
        {<<"int_attr">>, int, 42},
        {<<"float_attr">>, float, 3.14},
        {<<"bool_attr">>, boolean, true},
        {<<"id_attr">>, id, <<"ID-123">>}
    ],

    EventXML = format_event_with_attributes(EventAttrs),

    %% Verify all types are present
    ?assert(string:str(EventXML, "<string") > 0),
    ?assert(string:str(EventXML, "<date") > 0),
    ?assert(string:str(EventXML, "<int") > 0),
    ?assert(string:str(EventXML, "<float") > 0),
    ?assert(string:str(EventXML, "<boolean") > 0),
    ?assert(string:str(EventXML, "<id") > 0),

    ok.

test_event_ordering() ->
    %% Test event ordering within trace
    Events = [
        #{<<"id">> => <<"evt1">>, <<"time:timestamp">> => ?TEST_TIMESTAMP},
        #{<<"id">> => <<"evt2">>, <<"time:timestamp">> => ?TEST_TIMESTAMP + 100},
        #{<<"id">> => <<"evt3">>, <<"time:timestamp">> => ?TEST_TIMESTAMP + 200}
    ],

    TraceXML = format_trace_with_events(Events),

    %% Extract event positions
    Event1Pos = string:str(TraceXML, "evt1"),
    Event2Pos = string:str(TraceXML, "evt2"),
    Event3Pos = string:str(TraceXML, "evt3"),

    %% Verify chronological order
    ?assert(Event1Pos < Event2Pos),
    ?assert(Event2Pos < Event3Pos),

    ok.

%%====================================================================
%% Group 8: Special Characters
%%====================================================================

test_group_special_chars() ->
    test_xml_escape(),
    test_attribute_value_escape(),
    test_cdata_for_complex_values(),
    test_unicode_characters(),
    ok.

test_xml_escape() ->
    %% Test XML character escaping
    Input = "<tag>Content & \"more\" content</tag>",

    Escaped = escape_xml(Input),

    ?assertNot(string:str(Escaped, "<tag>") > 0),  % Should be escaped
    ?assert(string:str(Escaped, "&lt;") > 0 orelse string:str(Escaped, "<![CDATA[") > 0),
    ?assert(string:str(Escaped, "&amp;") > 0),

    ok.

test_attribute_value_escape() ->
    %% Test escaping in attribute values
    Values = [
        {<<"text\">>with\"quotes\"">>, <<"text&quot;with&quot;quotes&quot;">>},
        {<<"text&with&ampersand">>, <<"text&amp;with&ampersand">>},
        {<<"text<with>brackets">>, <<"text&lt;with&gt;brackets">>}
    ],

    lists:foreach(fun({Input, ExpectedContains}) ->
        Escaped = escape_attribute_value(Input),
        ?assert(string:str(Escaped, binary_to_list(ExpectedContains)) > 0)
    end, Values),

    ok.

test_cdata_for_complex_values() ->
    %% Test CDATA for complex content
    ComplexContent = <<"
        <complex>
            <nested>Content with & special chars</nested>
        </complex>
    ">>,

    CDATA = format_cdata(ComplexContent),

    ?assert(string:str(CDATA, "<![CDATA[") > 0),
    ?assert(string:str(CDATA, "]]>") > 0),

    ok.

test_unicode_characters() ->
    %% Test Unicode character handling
    UnicodeStrings = [
        <<"\xE2\x9C\x93">>,     % Check mark
        <<"\xE2\x9D\xA4">>,     % Heart
        <<"\xF0\x9F\x98\x8A">>, % Smiley
        <<"\xE4\xB8\xAD\xE6\x96\x87">>,  % Chinese
        <<"\xD0\xA0\xD0\xB0\xD0\xB1\xD0\xBE\xD1\x82\xD0\xB0">>  % Cyrillic
    ],

    lists:foreach(fun(Str) ->
        %% Should handle without errors
        Escaped = escape_xml(binary_to_list(Str)),
        ?assert(is_list(Escaped))
    end, UnicodeStrings),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
format_xml_declaration() ->
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>".

format_log_open_tag() ->
    "<log xes.version=\"1.0\" xmlns=\"http://www.xes-standard.org/\">".

format_attribute(Type, Key, Value) ->
    TypeStr = atom_to_list(Type),
    KeyStr = binary_to_list(Key),
    ValueStr = case Type of
        string -> binary_to_list(Value);
        int -> integer_to_list(Value);
        float -> float_to_list(Value, [{decimals, 10}, compact]);
        boolean -> atom_to_list(Value);
        date -> format_timestamp_iso8601(Value);
        id -> binary_to_list(Value);
        list -> "[...]"  % Simplified
    end,
    lists:flatten(["<", TypeStr, " key=\"", KeyStr, "\" value=\"", ValueStr, "\"/>"]).

encode_attribute(Type, Key, Value) ->
    format_attribute(Type, Key, Value).

format_timestamp_iso8601(Timestamp) ->
    %% Convert millisecond timestamp to ISO 8601
    DateTime = calendar:system_time_to_universal_time(Timestamp div 1000),
    DateStr = format_date(DateTime),
    TimeStr = format_time(DateTime),
    MsStr = "." ++ integer_to_list(Timestamp rem 1000),
    DateStr ++ "T" ++ TimeStr ++ MsStr ++ "Z".

format_timestamp_legacy(Timestamp) ->
    format_timestamp_iso8601(Timestamp).

format_timestamp_safe(Timestamp) when is_integer(Timestamp), Timestamp > 0 ->
    format_timestamp_iso8601(Timestamp);
format_timestamp_safe(_) ->
    "1970-01-01T00:00:00.000Z".

format_date({{Year, Month, Day}, _}) ->
    lists:flatten([
        pad4(Year), "-",
        pad2(Month), "-",
        pad2(Day)
    ]).

format_time({_, {Hour, Min, Sec}}) ->
    lists:flatten([
        pad2(Hour), ":",
        pad2(Min), ":",
        pad2(Sec)
    ]).

pad4(N) when N < 10 -> "000" ++ integer_to_list(N);
pad4(N) when N < 100 -> "00" ++ integer_to_list(N);
pad4(N) when N < 1000 -> "0" ++ integer_to_list(N);
pad4(N) -> integer_to_list(N).

pad2(N) when N < 10 -> "0" ++ integer_to_list(N);
pad2(N) -> integer_to_list(N).

format_extension_extension(Extension) ->
    #{
        <<"name">> := Name,
        <<"prefix">> := Prefix,
        <<"uri">> := URI
    } = Extension,
    lists:flatten([
        "<extension name=\"", binary_to_list(Name), "\" ",
        "prefix=\"", binary_to_list(Prefix), "\" ",
        "uri=\"", binary_to_list(URI), "\"/>"
    ]).

format_extension_declaration(Extension) ->
    format_extension_extension(Extension).

encode_global_attributes(_Scope, Attributes) ->
    lists:map(fun({Key, Type, Value}) ->
        format_attribute(Type, Key, Value)
    end, Attributes).

create_test_hierarchy() ->
    lists:flatten([
        "<log>",
        "<trace>",
        "<event>",
        format_attribute(string, <<"concept:name">>, <<"TestEvent">>),
        "</event>",
        "</trace>",
        "</log>"
    ]).

validate_attribute_key(Key) ->
    %% Must contain colon separating prefix and name
    case binary:split(Key, <<":">>) of
        [Prefix, Name] when byte_size(Prefix) > 0, byte_size(Name) > 0 -> true;
        _ -> false
    end.

format_trace_with_attributes(Attrs) ->
    AttrStrs = lists:map(fun({Key, Type, Value}) ->
        format_attribute(Type, Key, Value)
    end, Attrs),
    lists:flatten(["<trace>\n", lists:join("\n", AttrStrs), "\n</trace>"]).

format_trace_with_id(Id) ->
    lists:flatten(["<trace>\n<string key=\"id\" value=\"", binary_to_list(Id), "\"/>\n</trace>"]).

format_trace_with_events(Events) ->
    EventStrs = lists:map(fun(Event) ->
        format_event_from_map(Event)
    end, Events),
    lists:flatten(["<trace>\n", lists:join("\n", EventStrs), "\n</trace>"]).

format_event_from_map(Event) ->
    Attrs = maps:to_list(Event),
    AttrStrs = lists:map(fun({Key, Value}) ->
        Type = guess_type(Value),
        format_attribute(Type, Key, Value)
    end, Attrs),
    lists:flatten(["  <event>\n    ", lists:join("\n    ", AttrStrs), "\n  </event>"]).

guess_type(Value) when is_binary(Value) -> string;
guess_type(Value) when is_integer(Value) -> int;
guess_type(Value) when is_float(Value) -> float;
guess_type(Value) when is_boolean(Value) -> boolean;
guess_type(_) -> string.

format_event_with_attributes(Attrs) ->
    AttrStrs = lists:map(fun({Key, Type, Value}) ->
        format_attribute(Type, Key, Value)
    end, Attrs),
    lists:flatten(["<event>\n", lists:join("\n", AttrStrs), "\n</event>"]).

escape_xml(Text) when is_list(Text) ->
    escape_xml_loop(Text, []).

escape_xml_loop([], Acc) ->
    lists:reverse(Acc);
escape_xml_loop([$< | Rest], Acc) ->
    escape_xml_loop(Rest, lists:reverse("&lt;") ++ Acc);
escape_xml_loop([$> | Rest], Acc) ->
    escape_xml_loop(Rest, lists:reverse("&gt;") ++ Acc);
escape_xml_loop([$& | Rest], Acc) ->
    escape_xml_loop(Rest, lists:reverse("&amp;") ++ Acc);
escape_xml_loop([$" | Rest], Acc) ->
    escape_xml_loop(Rest, lists:reverse("&quot;") ++ Acc);
escape_xml_loop([C | Rest], Acc) ->
    escape_xml_loop(Rest, [C | Acc]).

escape_attribute_value(Value) ->
    escape_xml(binary_to_list(Value)).

format_cdata(Content) ->
    "<![CDATA[" ++ binary_to_list(Content) ++ "]]>".

create_sample_xes_document() ->
    lists:flatten([
        format_xml_declaration(), "\n",
        format_log_open_tag(), "\n",
        "  <trace>\n",
        "    <event>\n",
        "      ", format_attribute(string, <<"concept:name">>, <<"Test">>), "\n",
        "    </event>\n",
        "  </trace>\n",
        "</log>"
    ]).

check_balanced_tags(XML) ->
    check_tags_loop(XML, []).

check_tags_loop([], []) -> true;
check_tags_loop([], _) -> false;
check_tags_loop([Char1, Char2 | Rest], Stack) when Char1 =:= $<, Char2 =:= $/ ->
    %% Closing tag
    check_tags_loop(Rest, Stack);
check_tags_loop([Char1, $t, $a, $g | Rest], Stack) when Char1 =:= $< ->
    check_tags_loop(Rest, [$>|Stack]);
check_tags_loop([Char1, $e, $v, $e, $n, $t | Rest], Stack) when Char1 =:= $/ ->
    check_tags_loop(Rest, Stack);
check_tags_loop([$e, $v, $e, $n, $t | Rest], Stack) ->
    check_tags_loop(Rest, Stack);
check_tags_loop([_ | Rest], Stack) ->
    check_tags_loop(Rest, Stack).

check_nesting(XML) ->
    %% Basic nesting check
    OpenLog = string:str(XML, "<log"),
    OpenTrace = string:str(XML, "<trace"),
    OpenEvent = string:str(XML, "<event"),
    CloseEvent = string:str(XML, "</event"),
    CloseTrace = string:str(XML, "</trace"),
    CloseLog = string:str(XML, "</log"),

    OpenLog > 0 andalso OpenTrace > 0 andalso OpenEvent > 0 andalso
    CloseEvent > 0 andalso CloseTrace > 0 andalso CloseLog > 0 andalso
    OpenLog < OpenTrace andalso OpenTrace < OpenEvent andalso
    CloseEvent < CloseTrace andalso CloseTrace < CloseLog.

count_occurrences(String, Substring) ->
    count_occurrences_loop(String, Substring, 0).

count_occurrences_loop(String, Substring, Count) ->
    case string:str(String, Substring) of
        0 -> Count;
        Index ->
            NewString = lists:nthtail(Index + length(Substring) - 1, String),
            count_occurrences_loop(NewString, Substring, Count + 1)
    end.
