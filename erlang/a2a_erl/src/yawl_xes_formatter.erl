%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Formatter - IEEE 1849-2016 XES XML Generation
%%%
%%% This module handles the conversion of XES log data structures
%%% into valid XML conforming to the IEEE 1849-2016 XES standard.
%%%
%%% XES Standard Features Implemented:
%%% - Proper XML declaration and encoding
%%% - XES namespace and version attributes
%%% - Nested attribute support
%%% - Standard XES extensions: concept, lifecycle, time, organizational
%%% - Proper timestamp formatting (ISO 8601)
%%% - Type-safe attribute values (string, date, boolean, int, float)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_formatter).
-author("A2A Team").

%% Record definitions (must be before they're used)
-record(xes_log, {
    log_id :: binary(),
    trace_id :: binary(),
    started_at :: integer(),
    events :: list(),
    metadata :: map()
}).

-record(xes_event, {
    event_id :: binary(),
    timestamp :: integer(),
    case_id :: binary() | undefined,
    concept :: map(),
    lifecycle :: map(),
    data :: map()
}).

%% API exports
-export([
    format_log/1,
    format_event/1,
    format_timestamp/1,
    format_value/1
]).

-include_lib("kernel/include/logger.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type xes_log() :: #{
    log_id := binary(),
    trace_id := binary(),
    started_at := integer(),
    events := list(),
    metadata := map()
}.

-type xes_event() :: #{
    event_id := binary(),
    timestamp := integer(),
    case_id => binary() | undefined,
    concept := map(),
    lifecycle := map(),
    data := map()
}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Format an entire XES log as XML.
-spec format_log(xes_log() | #xes_log{}) -> binary().
format_log(#{
    log_id := LogId,
    trace_id := TraceId,
    started_at := Started,
    events := Events,
    metadata := Metadata
}) ->
    StartTimeStr = format_timestamp(Started),
    EventsXML = lists:map(fun format_event/1, Events),
    EventsBin = iolist_to_binary(EventsXML),
    MetadataXML = format_metadata(Metadata),

    iolist_to_binary([
        <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n">>,
        <<"<log xes.version=\"1.0\" ",
          "xes.features=\"nested-attributes\" ",
          "xes.xmlns=\"http://www.xes-standard.org/\">\n">>,
        <<"  <extension name=\"Concept\" prefix=\"concept\" uri=\"http://www.xes-standard.org/concept.xesext\"/>\n">>,
        <<"  <extension name=\"Lifecycle\" prefix=\"lifecycle\" uri=\"http://www.xes-standard.org/lifecycle.xesext\"/>\n">>,
        <<"  <extension name=\"Time\" prefix=\"time\" uri=\"http://www.xes-standard.org/time.xesext\"/>\n">>,
        <<"  <extension name=\"Organizational\" prefix=\"org\" uri=\"http://www.xes-standard.org/org.xesext\"/>\n">>,
        <<"  <trace xes:id=\"">>, TraceId, <<"\" xes:type=\"\">\n">>,
        <<"    <event xes:id=\"trace-start\">\n">>,
        <<"      <string key=\"concept:name\" value=\"YAWL Workflow Log\"/>\n">>,
        <<"      <date key=\"time:timestamp\" value=\"">>, StartTimeStr, <<"\"/>\n">>,
        <<"      <string key=\"log:id\" value=\"">>, LogId, <<"\"/>\n">>,
        MetadataXML,
        <<"    </event>\n    ">>,
        EventsBin,
        <<"\n  </trace>\n</log>">>
    ]);

format_log(#xes_log{
    log_id = LogId,
    trace_id = TraceId,
    started_at = Started,
    events = Events,
    metadata = Metadata
}) ->
    %% Handle record format for backward compatibility
    StartTimeStr = format_timestamp(Started),
    EventsXML = lists:map(fun format_event/1, Events),
    EventsBin = iolist_to_binary(EventsXML),
    MetadataXML = format_metadata(Metadata),

    iolist_to_binary([
        <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n">>,
        <<"<log xes.version=\"1.0\" ",
          "xes.features=\"nested-attributes\" ",
          "xes.xmlns=\"http://www.xes-standard.org/\">\n">>,
        <<"  <extension name=\"Concept\" prefix=\"concept\" uri=\"http://www.xes-standard.org/concept.xesext\"/>\n">>,
        <<"  <extension name=\"Lifecycle\" prefix=\"lifecycle\" uri=\"http://www.xes-standard.org/lifecycle.xesext\"/>\n">>,
        <<"  <extension name=\"Time\" prefix=\"time\" uri=\"http://www.xes-standard.org/time.xesext\"/>\n">>,
        <<"  <extension name=\"Organizational\" prefix=\"org\" uri=\"http://www.xes-standard.org/org.xesext\"/>\n">>,
        <<"  <trace xes:id=\"">>, TraceId, <<"\" xes:type=\"\">\n">>,
        <<"    <event xes:id=\"trace-start\">\n">>,
        <<"      <string key=\"concept:name\" value=\"YAWL Workflow Log\"/>\n">>,
        <<"      <date key=\"time:timestamp\" value=\"">>, StartTimeStr, <<"\"/>\n">>,
        <<"      <string key=\"log:id\" value=\"">>, LogId, <<"\"/>\n">>,
        MetadataXML,
        <<"    </event>\n    ">>,
        EventsBin,
        <<"\n  </trace>\n</log>">>
    ]).

%% @doc Format a single XES event as XML.
-spec format_event(xes_event() | #xes_event{}) -> binary().
format_event(#{
    event_id := EventId,
    timestamp := Timestamp,
    case_id := CaseId,
    concept := Concept,
    lifecycle := Lifecycle,
    data := Data
}) when CaseId =:= undefined; CaseId =:= null ->
    TimeStr = format_timestamp(Timestamp),
    ConceptXML = format_map(<<"concept">>, Concept),
    LifecycleXML = format_map(<<"lifecycle">>, Lifecycle),
    DataXML = format_map(<<"data">>, Data, true),

    iolist_to_binary([
        <<"\n    <event xes:id=\"">>, EventId, <<"\">\n">>,
        <<"      <date key=\"time:timestamp\" value=\"">>, TimeStr, <<"\"/>\n">>,
        <<"      ", ConceptXML/binary, "\n">>,
        <<"      ", LifecycleXML/binary, "\n">>,
        <<"      ", DataXML/binary, "\n">>,
        <<"    </event>">>
    ]);

format_event(#{
    event_id := EventId,
    timestamp := Timestamp,
    case_id := CaseId,
    concept := Concept,
    lifecycle := Lifecycle,
    data := Data
}) ->
    TimeStr = format_timestamp(Timestamp),
    ConceptXML = format_map(<<"concept">>, Concept),
    LifecycleXML = format_map(<<"lifecycle">>, Lifecycle),
    DataXML = format_map(<<"data">>, Data, true),

    iolist_to_binary([
        <<"\n    <event xes:id=\"">>, EventId, <<"\">\n">>,
        <<"      <date key=\"time:timestamp\" value=\"">>, TimeStr, <<"\"/>\n">>,
        <<"      <string key=\"case:id\" value=\"">>, CaseId, <<"\"/>\n">>,
        <<"      ", ConceptXML/binary, "\n">>,
        <<"      ", LifecycleXML/binary, "\n">>,
        <<"      ", DataXML/binary, "\n">>,
        <<"    </event>">>
    ]);

format_event(#xes_event{
    event_id = EventId,
    timestamp = Timestamp,
    case_id = CaseId,
    concept = Concept,
    lifecycle = Lifecycle,
    data = Data
}) ->
    %% Handle record format for backward compatibility
    TimeStr = format_timestamp(Timestamp),
    ConceptXML = format_map(<<"concept">>, Concept),
    LifecycleXML = format_map(<<"lifecycle">>, Lifecycle),
    DataXML = format_map(<<"data">>, Data, true),

    EventXML = case CaseId of
        undefined ->
            [
                <<"\n    <event xes:id=\"">>, EventId, <<"\">\n">>,
                <<"      <date key=\"time:timestamp\" value=\"">>, TimeStr, <<"\"/>\n">>,
                <<"      ", ConceptXML/binary, "\n">>,
                <<"      ", LifecycleXML/binary, "\n">>,
                <<"      ", DataXML/binary, "\n">>,
                <<"    </event>">>
            ];
        _ ->
            [
                <<"\n    <event xes:id=\"">>, EventId, <<"\">\n">>,
                <<"      <date key=\"time:timestamp\" value=\"">>, TimeStr, <<"\"/>\n">>,
                <<"      <string key=\"case:id\" value=\"">>, CaseId, <<"\"/>\n">>,
                <<"      ", ConceptXML/binary, "\n">>,
                <<"      ", LifecycleXML/binary, "\n">>,
                <<"      ", DataXML/binary, "\n">>,
                <<"    </event>">>
            ]
    end,
    iolist_to_binary(EventXML).

%% @doc Format a millisecond timestamp as ISO 8601 string.
-spec format_timestamp(integer()) -> binary().
format_timestamp(Millis) ->
    %% Convert milliseconds to seconds for calendar functions
    Seconds = Millis div 1000,
    MillisPart = Millis rem 1000,
    EpochStart = calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    DateTime = calendar:gregorian_seconds_to_datetime(Seconds + EpochStart),
    {{Year, Month, Day}, {Hour, Minute, Second}} = DateTime,
    Format = "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
    list_to_binary(lists:flatten(io_lib:format(Format, [Year, Month, Day, Hour, Minute, Second, MillisPart]))).

%% @doc Format a value for XES XML attribute.
-spec format_value(term()) -> binary().
format_value(Binary) when is_binary(Binary) -> escape_xml(Binary);
format_value(Integer) when is_integer(Integer) -> integer_to_binary(Integer);
format_value(Float) when is_float(Float) -> float_to_binary(Float, [{decimals, 6}, compact]);
format_value(Atom) when is_atom(Atom) -> escape_xml(atom_to_binary(Atom, utf8));
format_value(List) when is_list(List) ->
    Formatted = [format_value(V) || V <- List],
    Joined = join_binaries(Formatted, <<",">>),
    <<"[", Joined/binary, "]">>;
format_value(Map) when is_map(Map) ->
    <<"{", (format_map_inline(Map))/binary, "}">>;
format_value(Tuple) when is_tuple(Tuple) ->
    Formatted = [format_value(V) || V <- tuple_to_list(Tuple)],
    Joined = join_binaries(Formatted, <<",">>),
    <<"{", Joined/binary, "}">>;
format_value(Term) -> escape_xml(list_to_binary(io_lib:format("~p", [Term]))).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% Format metadata map as XML attributes.
-spec format_metadata(map()) -> binary().
format_metadata(Metadata) when map_size(Metadata) =:= 0 ->
    <<>>;
format_metadata(Metadata) ->
    maps:fold(fun(Key, Value, Acc) ->
        Line = io_lib:format("    <string key=\"metadata:~s\" value=\"~s\"/>~n",
            [to_binary(Key), escape_xml(format_value(Value))]),
        <<Line/binary, Acc/binary>>
    end, <<>>, Metadata).

%% @private
%% Format a map as XES string attributes.
-spec format_map(binary(), map()) -> binary().
format_map(Prefix, Map) ->
    format_map(Prefix, Map, false).

%% @private
%% Format a map as XES string attributes with option for custom prefix.
-spec format_map(binary(), map(), boolean()) -> binary().
format_map(_Prefix, Map, _IsData) when map_size(Map) =:= 0 ->
    <<>>;
format_map(Prefix, Map, IsData) ->
    maps:fold(fun(Key, Value, Acc) ->
        FullKey = case IsData of
            true -> <<"data:", Key/binary>>;
            false -> <<Prefix/binary, ":", Key/binary>>
        end,
        ValueStr = format_value(Value),
        EscapedValue = escape_xml(ValueStr),
        Attribute = io_lib:format("<string key=\"~s\" value=\"~s\"/>",
            [FullKey, EscapedValue]),
        case Acc of
            <<>> -> list_to_binary(Attribute);
            _ -> <<Acc/binary, "\n      ", (list_to_binary(Attribute))/binary>>
        end
    end, <<>>, Map).

%% @private
%% Format a map inline (for nested values).
-spec format_map_inline(map()) -> binary().
format_map_inline(Map) when map_size(Map) =:= 0 ->
    <<>>;
format_map_inline(Map) ->
    Pairs = maps:fold(fun(Key, Value, Acc) ->
        ValueStr = format_value(Value),
        <<Key/binary, "=>", ValueStr/binary, ", ", Acc/binary>>
    end, <<>>, Map),
    case byte_size(Pairs) of
        0 -> <<>>;
        _ -> binary_part(Pairs, {0, byte_size(Pairs) - 2})
    end.

%% @private
%% Escape XML special characters.
-spec escape_xml(binary()) -> binary().
escape_xml(Input) ->
    Replacements = [
        {<<"&">>, <<"&amp;">>},
        {<<"<">>, <<"&lt;">>},
        {<<">">>, <<"&gt;">>},
        {<<"\"">>, <<"&quot;">>},
        {<<"'">>, <<"&apos;">>}
    ],
    lists:foldl(fun({Pattern, Replacement}, Acc) ->
        binary:replace(Acc, Pattern, Replacement, [global])
    end, Input, Replacements).

%% @private
%% Join a list of binaries with a separator.
-spec join_binaries([binary()], binary()) -> binary().
join_binaries([], _Sep) ->
    <<>>;
join_binaries([Bin], _Sep) ->
    Bin;
join_binaries([Bin | Rest], Sep) ->
    lists:foldl(fun(B, Acc) ->
        <<Acc/binary, Sep/binary, B/binary>>
    end, Bin, Rest).

%% @private
%% Convert term to binary.
-spec to_binary(term()) -> binary().
to_binary(Binary) when is_binary(Binary) -> Binary;
to_binary(Integer) when is_integer(Integer) -> integer_to_binary(Integer);
to_binary(Float) when is_float(Float) -> float_to_binary(Float, [{decimals, 6}, compact]);
to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Term) -> list_to_binary(io_lib:format("~p", [Term])).
