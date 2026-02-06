%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Partial Order XML Parsing (XES Format)
%%%
%%% Chicago-style TDD: Tests written FIRST, expected to FAIL.
%%% Implementation follows to make tests pass.
%%%
%%% Tests XES (eXtensible Event Stream) format with partial order extension
%%% based on van der Aalst 2025 - arXiv:2509.15346
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_partial_order_xml_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% Minimal valid XES with partial order extension
minimal_xes_po() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"trace1\">\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"e2\">\n"
      "      <string key=\"concept:name\" value=\"B\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:01:00.000Z\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"e3\">\n"
      "      <string key=\"concept:name\" value=\"C\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:02:00.000Z\"/>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% XES with partial order extension containing precedence relations
xes_with_precedence() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"trace_with_precedence\">\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"Start\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "      <list key=\"po:order-after\">\n"
      "        <string value=\"e0\"/>\n"
      "      </list>\n"
      "    </event>\n"
      "    <event xes:id=\"e2\">\n"
      "      <string key=\"concept:name\" value=\"Process\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:01:00.000Z\"/>\n"
      "      <list key=\"po:order-after\">\n"
      "        <string value=\"e1\"/>\n"
      "      </list>\n"
      "    </event>\n"
      "    <event xes:id=\"e3\">\n"
      "      <string key=\"concept:name\" value=\"End\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:02:00.000Z\"/>\n"
      "      <list key=\"po:order-after\">\n"
      "        <string value=\"e2\"/>\n"
      "      </list>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% XES with concurrent events (both order-after and concurrent-with)
xes_with_concurrent() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"concurrent_trace\">\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"e2\">\n"
      "      <string key=\"concept:name\" value=\"B\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:30.000Z\"/>\n"
      "      <list key=\"po:order-after\">\n"
      "        <string value=\"e1\"/>\n"
      "      </list>\n"
      "    </event>\n"
      "    <event xes:id=\"e3\">\n"
      "      <string key=\"concept:name\" value=\"C\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:30.000Z\"/>\n"
      "      <list key=\"po:order-after\">\n"
      "        <string value=\"e1\"/>\n"
      "      </list>\n"
      "      <list key=\"po:concurrent-with\">\n"
      "        <string value=\"e2\"/>\n"
      "      </list>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% XES with multiple traces
xes_with_multiple_traces() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"trace1\">\n"
      "    <event xes:id=\"t1_e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"t1_e2\">\n"
      "      <string key=\"concept:name\" value=\"B\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:01:00.000Z\"/>\n"
      "    </event>\n"
      "  </trace>\n"
      "  <trace xes:id=\"trace2\">\n"
      "    <event xes:id=\"t2_e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T11:00:00.000Z\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"t2_e2\">\n"
      "      <string key=\"concept:name\" value=\"C\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T11:01:00.000Z\"/>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% Malformed XML - missing closing tag
malformed_xml_unclosed() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\">\n"
      "  <trace>\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "    </event>\n"
      "  <!-- Missing closing tags -->\n"
      "</log>">>.

%% Malformed XML - invalid XML structure
malformed_xml_invalid() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\">\n"
      "  <trace>\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "    </event>>\n"  %% Extra closing bracket
      "  </trace>\n"
      "</log>">>.

%% XES with missing required attributes
xes_missing_activity() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"trace1\">\n"
      "    <event xes:id=\"e1\">\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% XES with custom attributes
xes_with_attributes() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "  <trace xes:id=\"trace_with_attrs\">\n"
      "    <event xes:id=\"e1\">\n"
      "      <string key=\"concept:name\" value=\"A\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
      "      <string key=\"org:resource\" value=\"user1\"/>\n"
      "      <int key=\"cost:total\" value=\"100\"/>\n"
      "    </event>\n"
      "    <event xes:id=\"e2\">\n"
      "      <string key=\"concept:name\" value=\"B\"/>\n"
      "      <date key=\"time:timestamp\" value=\"2025-01-01T10:01:00.000Z\"/>\n"
      "      <string key=\"org:resource\" value=\"user2\"/>\n"
      "    </event>\n"
      "  </trace>\n"
      "</log>">>.

%% Empty XES log
empty_xes() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
      "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>\n"
      "</log>">>.

%%====================================================================
%% Test Cases - ALL EXPECTED TO FAIL INITIALLY
%%====================================================================

%%--------------------------------------------------------------------
%% Basic XES Parsing Tests
%%--------------------------------------------------------------------

import_minimal_xes_test_() ->
    {"Parse minimal XES with partial order extension",
     fun() ->
         XES = minimal_xes_po(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, #{events := _, order := _, concurrent := _, trace_id := _}}, Result),
         {ok, PO} = Result,
         Events = maps:get(events, PO),
         ?assertEqual(3, length(Events)),
         ?assertEqual(<<"trace1">>, maps:get(trace_id, PO))
     end}.

import_xes_with_precedence_test_() ->
    {"Parse XES with precedence relations (po:order-after)",
     fun() ->
         XES = xes_with_precedence(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, #{order := #{}}}, Result),
         {ok, PO} = Result,
         Order = maps:get(order, PO),
         %% Verify precedence: e1 -> e2 -> e3
         ?assertEqual([<<"e1">>], maps:get(<<"e2">>, Order, [])),
         ?assertEqual([<<"e2">>], maps:get(<<"e3">>, Order, []))
     end}.

import_xes_with_concurrent_test_() ->
    {"Parse XES with concurrent events (po:concurrent-with)",
     fun() ->
         XES = xes_with_concurrent(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, #{concurrent := _}}, Result),
         {ok, PO} = Result,
         Concurrent = maps:get(concurrent, PO),
         %% e2 and e3 should be marked as concurrent
         ?assert(sets:is_element({<<"e2">>, <<"e3">>}, Concurrent) orelse
                 sets:is_element({<<"e3">>, <<"e2">>}, Concurrent))
     end}.

import_xes_multiple_traces_test_() ->
    {"Parse XES with multiple traces (should merge or return first)",
     fun() ->
         XES = xes_with_multiple_traces(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, _}, Result),
         {ok, PO} = Result,
         Events = maps:get(events, PO),
         ?assert(length(Events) >= 2)
     end}.

import_xes_with_attributes_test_() ->
    {"Parse XES with custom attributes (org:resource, cost:total)",
     fun() ->
         XES = xes_with_attributes(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, #{events := _}}, Result),
         {ok, PO} = Result,
         Events = maps:get(events, PO),
         Event1 = lists:keyfind(<<"e1">>, 2, Events),
         ?assertMatch(#{attributes := #{<<"org:resource">> := <<"user1">>}}, Event1)
     end}.

%%--------------------------------------------------------------------
%% Error Handling Tests
%%--------------------------------------------------------------------

import_malformed_xml_unclosed_test_() ->
    {"Return error for malformed XML with unclosed tags",
     fun() ->
         XES = malformed_xml_unclosed(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({error, _}, Result),
         {error, Reason} = Result,
         ?assert(is_atom(Reason) orelse is_binary(Reason))
     end}.

import_malformed_xml_invalid_test_() ->
    {"Return error for malformed XML with invalid structure",
     fun() ->
         XES = malformed_xml_invalid(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({error, _}, Result)
     end}.

import_empty_xes_test_() ->
    {"Handle empty XES log gracefully",
     fun() ->
         XES = empty_xes(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         %% Should return PO with empty events list
         ?assertMatch({ok, #{events := []}}, Result)
     end}.

import_xes_missing_activity_test_() ->
    {"Handle events missing required activity name",
     fun() ->
         XES = xes_missing_activity(),
         Result = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, _}, Result),
         {ok, PO} = Result,
         Events = maps:get(events, PO),
         %% Event should have unknown or default activity
         ?assertEqual(1, length(Events))
     end}.

import_invalid_input_test_() ->
    {"Return error for non-binary input",
     fun() ->
         Result = yawl_partial_order:import_partial_order_xes(not_binary),
         ?assertMatch({error, _}, Result)
     end}.

import_empty_binary_test_() ->
    {"Return error for empty binary input",
     fun() ->
         Result = yawl_partial_order:import_partial_order_xes(<<>>),
         ?assertMatch({error, _}, Result)
     end}.

%%--------------------------------------------------------------------
%% Structure Validation Tests
%%--------------------------------------------------------------------

validate_xes_structure_test_() ->
    {"Validate XES partial order structure has required keys",
     fun() ->
         XES = minimal_xes_po(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         %% Must have all required keys
         ?assert(maps:is_key(events, PO)),
         ?assert(maps:is_key(order, PO)),
         ?assert(maps:is_key(concurrent, PO)),
         ?assert(maps:is_key(trace_id, PO))
     end}.

validate_event_structure_test_() ->
    {"Validate parsed events have required fields",
     fun() ->
         XES = minimal_xes_po(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Events = maps:get(events, PO),
         lists:foreach(
             fun(Event) ->
                 ?assert(maps:is_key(id, Event)),
                 ?assert(maps:is_key(timestamp, Event)),
                 ?assert(maps:is_key(activity, Event)),
                 ?assert(maps:is_key(trace_id, Event))
             end,
             Events)
     end}.

validate_order_relation_structure_test_() ->
    {"Validate order relations are properly formed",
     fun() ->
         XES = xes_with_precedence(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Order = maps:get(order, PO),
         maps:foreach(
             fun(_From, ToList) ->
                 ?assert(is_list(ToList)),
                 lists:foreach(
                     fun(To) ->
                         ?assert(is_binary(To))
                     end,
                     ToList)
             end,
             Order)
     end}.

%%--------------------------------------------------------------------
%% XES Standard Compliance Tests
%%--------------------------------------------------------------------

parse_xes_namespace_test_() ->
    {"Correctly parse XES namespace attributes",
     fun() ->
         XES = minimal_xes_po(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         ?assertMatch({ok, _}, {ok, PO})
     end}.

parse_xes_extension_test_() ->
    {"Recognize partial order extension declaration",
     fun() ->
         XES = minimal_xes_po(),
         ?assert(binary:match(XES, <<"po:order-after">>) =/= nomatch orelse
                 binary:match(XES, <<"PartialOrder">>) =/= nomatch),
         {ok, _} = yawl_partial_order:import_partial_order_xes(XES)
     end}.

parse_xes_standard_attributes_test_() ->
    {"Parse standard XES attributes (concept:name, time:timestamp)",
     fun() ->
         XES = minimal_xes_po(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Events = maps:get(events, PO),
         ?assertEqual(3, length(Events)),
         lists:foreach(
             fun(E) ->
                 ?assert(is_binary(maps:get(activity, E))),
                 ?assert(is_integer(maps:get(timestamp, E)))
             end,
             Events)
     end}.

%%--------------------------------------------------------------------
%% Round-trip Tests
%%--------------------------------------------------------------------

roundtrip_export_import_test_() ->
    {"Exported XES can be imported back successfully",
     fun() ->
         %% Create a partial order
         OriginalPO = #{
             events => [
                 #{id => <<"e1">>, timestamp => 1704097200000, activity => <<"A">>,
                   trace_id => <<"trace1">>, attributes => #{}},
                 #{id => <<"e2">>, timestamp => 1704097260000, activity => <<"B">>,
                   trace_id => <<"trace1">>, attributes => #{}}
             ],
             order => #{<<"e1">> => [<<"e2">>]},
             concurrent => sets:new(),
             trace_id => <<"trace1">>
         },
         %% Export
         ExportedXES = yawl_partial_order:export_partial_order_xes(OriginalPO),
         ?assert(is_binary(ExportedXES)),
         %% Import back
         {ok, ImportedPO} = yawl_partial_order:import_partial_order_xes(ExportedXES),
         %% Verify structure preserved
         ?assertEqual(2, length(maps:get(events, ImportedPO))),
         ?assertEqual(<<"trace1">>, maps:get(trace_id, ImportedPO))
     end}.

%%--------------------------------------------------------------------
%% Edge Cases Tests
%%--------------------------------------------------------------------

import_xes_with_whitespace_test_() ->
    {"Handle XES with excessive whitespace",
     fun() ->
         WhitespaceXES = <<"\n\n  ", (minimal_xes_po())/binary, "\n\n  ">>,
         Result = yawl_partial_order:import_partial_order_xes(WhitespaceXES),
         ?assertMatch({ok, _}, Result)
     end}.

import_xes_with_special_characters_test_() ->
    {"Handle activity names with special characters",
     fun() ->
         SpecialXES = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                        "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
                        "  <trace xes:id=\"trace1\">\n"
                        "    <event xes:id=\"e1\">\n"
                        "      <string key=\"concept:name\" value=\"Send Email &amp; Notify\"/>\n"
                        "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
                        "    </event>\n"
                        "  </trace>\n"
                        "</log>">>,
         {ok, PO} = yawl_partial_order:import_partial_order_xes(SpecialXES),
         Events = maps:get(events, PO),
         ?assertEqual(1, length(Events))
     end}.

import_xes_with_unicode_test_() ->
    {"Handle UTF-8 encoded content",
     fun() ->
         UnicodeXES = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                        "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
                        "  <trace xes:id=\"trace1\">\n"
                        "    <event xes:id=\"e1\">\n"
                        "      <string key=\"concept:name\" value=\"Überprüfung\"/>\n"
                        "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
                        "    </event>\n"
                        "  </trace>\n"
                        "</log>">>,
         {ok, PO} = yawl_partial_order:import_partial_order_xes(UnicodeXES),
         Events = maps:get(events, PO),
         ?assertEqual(1, length(Events))
     end}.

%%--------------------------------------------------------------------
%% Concurrent Relations Tests
%%--------------------------------------------------------------------

verify_concurrent_symmetry_test_() ->
    {"Concurrent relations should be symmetric",
     fun() ->
         XES = xes_with_concurrent(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Concurrent = maps:get(concurrent, PO),
         %% If (a,b) is concurrent, (b,a) should also be in the set
         sets:foreach(
             fun({A, B}) ->
                 ?assert(sets:is_element({B, A}, Concurrent))
             end,
             Concurrent)
     end}.

verify_no_self_concurrent_test_() ->
    {"Event should not be concurrent with itself",
     fun() ->
         XES = xes_with_concurrent(),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Concurrent = maps:get(concurrent, PO),
         lists:foreach(
             fun(E) ->
                 Id = maps:get(id, E),
                 ?assertNot(sets:is_element({Id, Id}, Concurrent))
             end,
             maps:get(events, PO))
     end}.

%%--------------------------------------------------------------------
%% Timestamp Parsing Tests
%%--------------------------------------------------------------------

parse_iso8601_timestamp_test_() ->
    {"Parse ISO 8601 timestamps correctly",
     fun() ->
         XES = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                 "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
                 "  <trace xes:id=\"trace1\">\n"
                 "    <event xes:id=\"e1\">\n"
                 "      <string key=\"concept:name\" value=\"A\"/>\n"
                 "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.000Z\"/>\n"
                 "    </event>\n"
                 "  </trace>\n"
                 "</log>">>,
         {ok, PO} = yawl_partial_order:import_partial_order_xes(XES),
         Events = maps:get(events, PO),
         Event = hd(Events),
         Ts = maps:get(timestamp, Event),
         ?assert(is_integer(Ts)),
         ?assert(Ts > 0)
     end}.

parse_multiple_timestamp_formats_test_() ->
    {"Handle various timestamp formats",
     fun() ->
         FormatsXES = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                        "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n"
                        "  <trace xes:id=\"trace1\">\n"
                        "    <event xes:id=\"e1\">\n"
                        "      <string key=\"concept:name\" value=\"A\"/>\n"
                        "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00Z\"/>\n"
                        "    </event>\n"
                        "    <event xes:id=\"e2\">\n"
                        "      <string key=\"concept:name\" value=\"B\"/>\n"
                        "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:00.123Z\"/>\n"
                        "    </event>\n"
                        "  </trace>\n"
                        "</log>">>,
         {ok, PO} = yawl_partial_order:import_partial_order_xes(FormatsXES),
         Events = maps:get(events, PO),
         ?assertEqual(2, length(Events)),
         lists:foreach(
             fun(E) ->
                 ?assert(is_integer(maps:get(timestamp, E)))
             end,
             Events)
     end}.

%%--------------------------------------------------------------------
%% Large XES Handling Tests
%%--------------------------------------------------------------------

import_xes_many_events_test_() ->
    {"Handle XES with many events",
     fun() ->
         %% Generate XES with 100 events
         EventsXML = lists:map(
             fun(I) ->
                 Id = integer_to_binary(I),
                 io_lib:format(
                     "    <event xes:id=\"e~s\">\n"
                     "      <string key=\"concept:name\" value=\"Activity~s\"/>\n"
                     "      <date key=\"time:timestamp\" value=\"2025-01-01T10:00:~2.10.0B.000Z\"/>\n"
                     "    </event>\n",
                     [Id, Id, I])
             end,
             lists:seq(1, 100)),
         LargeXES = iolist_to_binary([
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
             "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">\n",
             "  <trace xes:id=\"large_trace\">\n",
             EventsXML,
             "  </trace>\n",
             "</log>"
         ]),
         {ok, PO} = yawl_partial_order:import_partial_order_xes(LargeXES),
         ?assertEqual(100, length(maps:get(events, PO)))
     end}.
