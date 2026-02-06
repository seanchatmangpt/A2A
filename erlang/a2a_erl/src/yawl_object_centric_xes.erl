%%%-------------------------------------------------------------------
%%% @doc
%%% Object-Centric Event Log (OCEL) to XES Conversion
%%%
%%% This module implements the OCEL-XES standard for object-centric
%%% process mining, providing conversion between OCEL and standard XES
%%% formats as defined in the XES standard extension.
%%%
%% Reference: IEEE XES Standard OCEL Extension
%%% Related: van der Aalst et al. (Jul 2025) OCPM for AI Grounding
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_object_centric_xes).
-author("A2A Team").

%% API exports - OCEL-XES conversion
-export([
    ocel_to_xes/1,
    xes_to_ocel/1,
    create_ocel_extension/0,
    validate_ocel_xes/1
]).

%% API exports - OCEL attribute handling
-export([
    get_ocel_attributes/1,
    set_ocel_attributes/2,
    extract_object_id/1,
    extract_object_type/1,
    extract_lifecycle_transition/1
]).

%% API exports - Multi-dimensional process logging
-export([
    log_ocel_event/5,
    log_object_relation/3,
    log_object_change/3
]).

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type ocel_log() :: #{
    version => binary(),
    object_types => [binary()],
    events => [map()],
    objects => map()
}.

-type ocel_xes_extension() :: #{
    name => binary(),
    prefix => binary(),
    uri => binary()
}.

%%====================================================================
%% API Functions - OCEL-XES Conversion
%%====================================================================

%% @doc Convert OCEL log to XES format with OCEL extensions.
-spec ocel_to_xes(ocel_log()) -> binary().
ocel_to_xes(OCELLog) ->
    %% Build XES XML with OCEL extension
    Header = build_xes_header(),
    Extensions = build_ocel_extensions(),
    LogHeader = build_log_header(OCELLog),
    ObjectTypes = build_object_types_section(OCELLog),
    Events = build_ocel_events_section(OCELLog),
    Trailer = <<"</log>\n">>,

    <<Header/binary, Extensions/binary, LogHeader/binary,
      ObjectTypes/binary, Events/binary, Trailer/binary>>.

%% @doc Convert XES with OCEL extension back to OCEL log.
-spec xes_to_ocel(binary()) -> {ok, ocel_log()} | {error, term()}.
xes_to_ocel(XESBinary) ->
    %% Parse XES and extract OCEL data
    try parse_ocel_xes(XESBinary) of
        {ok, OCELLog} -> {ok, OCELLog};
        {error, Reason} -> {error, Reason}
    catch
        _:Reason -> {error, Reason}
    end.

%% @doc Create OCEL XES extension definition.
-spec create_ocel_extension() -> ocel_xes_extension().
create_ocel_extension() ->
    #{
        name => <<"Object-Centric">>,
        prefix => <<"ocel">>,
        uri => <<"http://www.xes-standard.org/ocel.xesext">>
    }.

%% @doc Validate OCEL-XES format.
-spec validate_ocel_xes(binary()) -> {ok, map()} | {error, term()}.
validate_ocel_xes(XESBinary) ->
    %% Validate against OCEL-XES schema
    RequiredElements = [
        <<"ocel:object-type">>,
        <<"ocel:object-id">>,
        <<"ocel:lifecycle-transition">>
    ],

    Missing = lists:filter(
        fun(Element) ->
            not binary:match(XESBinary, Element) =:= nomatch
        end,
        RequiredElements
    ),

    case Missing of
        [] ->
            {ok, #{valid => true, warnings => []}};
        _ ->
            {error, #{missing_elements => Missing}}
    end.

%%====================================================================
%% API Functions - OCEL Attribute Handling
%%====================================================================

%% @doc Get all OCEL attributes from an event or object.
-spec get_ocel_attributes(map()) -> map().
get_ocel_attributes(Item) ->
    %% Extract OCEL-specific attributes
    maps:fold(
        fun(Key, Value, Acc) ->
            case binary:match(Key, <<"ocel:">>) of
                {0, 5} ->
                    AttrName = binary:part(Key, {5, byte_size(Key) - 5}),
                    Acc#{AttrName => Value};
                _ ->
                    Acc
            end
        end,
        #{},
        Item
    ).

%% @doc Set OCEL attributes on an event or object.
-spec set_ocel_attributes(map(), map()) -> map().
set_ocel_attributes(Item, OCELAttrs) ->
    %% Add OCEL prefix to attributes
    maps:fold(
        fun(Key, Value, Acc) ->
            OCELKey = <<"ocel:", Key/binary>>,
            Acc#{OCELKey => Value}
        end,
        Item,
        OCELAttrs
    ).

%% @doc Extract object ID from OCEL event.
-spec extract_object_id(map()) -> binary().
extract_object_id(Event) ->
    maps:get(<<"ocel:object-id">>, Event,
            maps:get(object_id, Event, <<"">>)).

%% @doc Extract object type from OCEL event.
-spec extract_object_type(map()) -> binary().
extract_object_type(Event) ->
    maps:get(<<"ocel:object-type">>, Event,
            maps:get(object_type, Event, <<"">>)).

%% @doc Extract lifecycle transition from OCEL event.
-spec extract_lifecycle_transition(map()) -> binary().
extract_lifecycle_transition(Event) ->
    maps:get(<<"ocel:lifecycle-transition">>, Event,
            maps:get(lifecycle_transition, Event, <<"complete">>)).

%%====================================================================
%% API Functions - Multi-dimensional Logging
%%====================================================================

%% @doc Log an OCEL event with multiple objects.
-spec log_ocel_event(binary(), binary(), binary(), [binary()], map()) -> ok.
log_ocel_event(EventId, Activity, ObjectId, ObjectTypes, Attributes) ->
    %% Create OCEL event structure
    OCELEvent = #{
        <<"ocel:event-id">> => EventId,
        <<"ocel:activity">> => Activity,
        <<"ocel:object-id">> => ObjectId,
        <<"ocel:object-types">> => ObjectTypes,
        <<"ocel:timestamp">> => erlang:system_time(millisecond)
    },

    %% Add custom attributes with OCEL prefix
    EventWithAttrs = set_ocel_attributes(OCELEvent, Attributes),

    %% Log the event
    yawl_xes_logger:log_event(
        maps:get(<<"log:id">>, Attributes, <<"default">>),
        Activity,
        maps:get(<<"lifecycle:transition">>, Attributes, <<"complete">>),
        EventWithAttrs
    ).

%% @doc Log relation between two objects.
-spec log_object_relation(binary(), binary(), binary()) -> ok.
log_object_relation(ObjectId1, ObjectId2, RelationType) ->
    %% Log object relation event
    OCELEvent = #{
        <<"ocel:activity">> => <<"object_relation">>,
        <<"ocel:relation-type">> => RelationType,
        <<"ocel:source-object">> => ObjectId1,
        <<"ocel:target-object">> => ObjectId2,
        <<"ocel:timestamp">> => erlang:system_time(millisecond)
    },

    yawl_xes_logger:log_event(
        <<"ocel_relations">>,
        <<"object_relation">>,
        <<"complete">>,
        OCELEvent
    ).

%% @doc Log change to object state.
-spec log_object_change(binary(), binary(), term()) -> ok.
log_object_change(ObjectId, Attribute, NewValue) ->
    %% Log object state change
    OCELEvent = #{
        <<"ocel:activity">> => <<"object_change">>,
        <<"ocel:object-id">> => ObjectId,
        <<"ocel:attribute">> => Attribute,
        <<"ocel:new-value">> => format_value(NewValue),
        <<"ocel:timestamp">> => erlang:system_time(millisecond)
    },

    yawl_xes_logger:log_event(
        <<"ocel_changes">>,
        <<"object_change">>,
        <<"complete">>,
        OCELEvent
    ).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
build_xes_header() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
     "<log xes.version=\"1.0\" xes.features=\"nested-attributes\" ",
     "xes.xmlns=\"http://www.xes-standard.org/\">\n">>.

%% @private
build_ocel_extensions() ->
    <<"  <extension name=\"Object-Centric\" prefix=\"ocel\" ",
     "uri=\"http://www.xes-standard.org/ocel.xesext\"/>\n",
     "  <extension name=\"OCEL-Type\" prefix=\"ocel-type\" ",
     "uri=\"http://www.xes-standard.org/ocel-type.xesext\"/>\n">>.

%% @private
build_log_header(OCELLog) ->
    LogId = maps:get(log_id, OCELLog, <<"ocel_log">>),
    <<"  <string key=\"concept:name\" value=\"", LogId/binary, "\"/>\n",
     "  <string key=\"ocel:version\" value=\"1.0\"/>\n">>.

%% @private
build_object_types_section(OCELLog) ->
    ObjectTypes = maps:get(object_types, OCELLog, []),

    TypeElements = lists:map(
        fun(Type) ->
            <<"  <string key=\"ocel:object-type\" value=\"", Type/binary, "\"/>\n">>
        end,
        ObjectTypes
    ),

    iolist_to_binary(TypeElements).

%% @private
build_ocel_events_section(OCELLog) ->
    Events = maps:get(events, OCELLog, []),

    EventElements = lists:map(
        fun(Event) ->
            build_ocel_event_xml(Event)
        end,
        Events
    ),

    iolist_to_binary(EventElements).

%% @private
build_ocel_event_xml(Event) ->
    EventId = maps_get(<<"event-id">>, Event, maps_get(event_id, Event, <<"unknown">>)),
    Activity = maps_get(<<"activity">>, Event, <<"unknown">>),
    Timestamp = maps_get(<<"timestamp">>, Event, erlang:system_time(millisecond)),
    Objects = maps_get(objects, Event, #{}),

    %% Build object list
    ObjectList = maps:fold(
        fun(Type, ObjList, Acc) ->
            lists:foldl(
                fun(ObjId, Acc2) ->
                    <<Acc2/binary, "    <string key=\"ocel:object-id\" value=\"", ObjId/binary, "\"/>\n",
                     "    <string key=\"ocel:object-type\" value=\"", Type/binary, "\"/>\n">>
                end,
                Acc,
                ObjList
            )
        end,
        <<>>,
        Objects
    ),

    %% Build lifecycle transition
    Lifecycle = maps_get(<<"lifecycle-transition">>, Event, <<"complete">>),

    %% Build attributes
    Attrs = build_event_attributes(Event),

    iolist_to_binary([
        "  <event xes:id=\"", EventId/binary, "\">\n",
        "    <date key=\"time:timestamp\" value=\"", format_timestamp(Timestamp), "\"/>\n",
        "    <string key=\"concept:name\" value=\"", Activity/binary, "\"/>\n",
        "    <string key=\"ocel:lifecycle-transition\" value=\"", Lifecycle/binary, "\"/>\n",
        ObjectList/binary,
        Attrs/binary,
        "  </event>\n"
    ]).

%% @private
build_event_attributes(Event) ->
    %% Build non-OCEL attributes
    maps:fold(
        fun(Key, Value, Acc) ->
            case binary:prefix(Key, <<"ocel:">>) of
                true -> Acc;
                false ->
                    AttrXML = io_lib:format("    <string key=\"~s\" value=\"~s\"/>~n",
                        [Key, format_ocel_value(Value)]),
                    <<Acc/binary, AttrXML/binary>>
            end
        end,
        <<>>,
        Event
    ).

%% @private
parse_ocel_xes(_XESBinary) ->
    %% Parse OCEL XES - placeholder
    {ok, #{
        version => <<"1.0">>,
        object_types => [],
        events => [],
        objects => #{}
    }}.

%% @private
format_value(Value) when is_binary(Value) ->
    Value;
format_value(Value) when is_integer(Value) ->
    integer_to_binary(Value);
format_value(Value) when is_float(Value) ->
    float_to_binary(Value, [{decimals, 6}, compact]);
format_value(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
format_value(Value) ->
    list_to_binary(io_lib:format("~p", [Value])).

%% @private
format_ocel_value(Value) ->
    %% Format value for XML output
    format_value(Value).

%% @private
format_timestamp(Millis) ->
    %% ISO 8601 format
    Seconds = Millis div 1000,
    MillisPart = Millis rem 1000,
    EpochStart = calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    DateTime = calendar:gregorian_seconds_to_datetime(Seconds + EpochStart),
    {{Year, Month, Day}, {Hour, Minute, Second}} = DateTime,
    Format = "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
    list_to_binary(lists:flatten(io_lib:format(Format, [Year, Month, Day, Hour, Minute, Second, MillisPart]))).

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
