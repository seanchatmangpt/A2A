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
    parse_ocel_xes/1,
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
-include_lib("xmerl/include/xmerl.hrl").

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

%% @doc Parse OCEL XES binary into OCEL log structure.
%% Extracts object types, events, and objects from OCEL-XES format.
-spec parse_ocel_xes(binary()) -> {ok, ocel_log()} | {error, term()}.
parse_ocel_xes(XESBinary) when not is_binary(XESBinary) ->
    {error, invalid_input_type};

parse_ocel_xes(<<>>) ->
    {error, empty_input};

parse_ocel_xes(XESBinary) ->
    try
        %% Parse XML using xmerl
        {XmlRoot, _Rest} = xmerl_scan:string(binary_to_list(XESBinary), [{quiet, true}]),

        %% Validate root element is a log
        case XmlRoot#xmlElement.name of
            log ->
                parse_log_element(XmlRoot);
            _ ->
                {error, {missing_log_element, XmlRoot#xmlElement.name}}
        end
    catch
        exit:{fatal, _} = Error ->
            {error, {invalid_xml, Error}};
        _:Error:Stacktrace ->
            {error, {parse_error, Error, Stacktrace}}
    end.

%% @private
%% @doc Parse the log element and extract OCEL data
parse_log_element(LogElement) ->
    %% Extract version
    Version = extract_version(LogElement, <<"1.0">>),

    %% Extract all content
    Content = LogElement#xmlElement.content,

    %% Extract and parse all events first (to collect object types from events)
    Events = parse_events(Content),

    %% Extract object types from both string elements and events
    LogObjectTypes = extract_object_types(Content),
    EventObjectTypes = extract_object_types_from_events(Events),
    AllObjectTypes = lists:usort(LogObjectTypes ++ EventObjectTypes),

    %% Build objects map from events
    Objects = build_objects_map(Events),

    {ok, #{
        version => Version,
        object_types => AllObjectTypes,
        events => Events,
        objects => Objects
    }}.

%% @private
%% @doc Extract OCEL version from log attributes
extract_version(LogElement, DefaultVersion) ->
    Attributes = LogElement#xmlElement.attributes,
    case lists:keyfind(ocel_version, #xmlAttribute.name, Attributes) of
        #xmlAttribute{value = Value} when Value =/= undefined ->
            list_to_binary(Value);
        _ ->
            %% Check for version in string elements
            Content = LogElement#xmlElement.content,
            case find_string_attribute(Content, <<"ocel:version">>) of
                {ok, Version} -> Version;
                error -> DefaultVersion
            end
    end.

%% @private
%% @doc Extract object types from log content
extract_object_types(Content) ->
    %% Extract from string elements with ocel:object-type
    TypeStrings = extract_all_string_values(Content, <<"ocel:object-type">>),
    TypeStrings.

%% @private
%% @doc Extract object types from parsed events
extract_object_types_from_events(Events) ->
    lists:foldl(
        fun(Event, Acc) ->
            Objects = maps:get(objects, Event, #{}),
            maps:fold(
                fun(ObjectType, _ObjectIdList, InnerAcc) ->
                    [ObjectType | InnerAcc]
                end,
                Acc,
                Objects
            )
        end,
        [],
        Events
    ).

%% @private
%% @doc Parse all event elements
parse_events(Content) ->
    Events = lists:filtermap(
        fun(Element) ->
            case Element of
                #xmlElement{name = event} ->
                    {true, parse_event_element(Element)};
                _ ->
                    false
            end
        end,
        Content
    ),
    Events.

%% @private
%% @doc Parse a single event element
parse_event_element(EventElement) ->
    %% Get event ID from xes:id attribute
    %% The attribute may be namespaced ('xes:id') or just ('id')
    XmlAttrs = EventElement#xmlElement.attributes,
    EventId = case lists:keyfind('xes:id', #xmlAttribute.name, XmlAttrs) of
        #xmlAttribute{value = Id} -> list_to_binary(Id);
        false ->
            case lists:keyfind(id, #xmlAttribute.name, XmlAttrs) of
                #xmlAttribute{value = Id} -> list_to_binary(Id);
                false ->
                    %% Try with tuple namespace format
                    case lists:search(
                        fun(#xmlAttribute{name = Name}) ->
                            case Name of
                                {_, id} -> true;
                                id -> true;
                                'xes:id' -> true;
                                _ -> false
                            end
                        end,
                        XmlAttrs
                    ) of
                        {value, #xmlAttribute{value = Id}} -> list_to_binary(Id);
                        false -> <<"unknown">>
                    end
            end
    end,

    %% Parse all event attributes
    Content = EventElement#xmlElement.content,
    Attributes = parse_event_attributes(Content),

    %% Extract activity (concept:name)
    Activity = maps:get(<<"concept:name">>, Attributes, <<"unknown">>),

    %% Extract timestamp
    Timestamp = maps:get(<<"time:timestamp">>, Attributes, erlang:system_time(millisecond)),

    %% Extract lifecycle transition
    Lifecycle = maps:get(<<"ocel:lifecycle-transition">>, Attributes, <<"complete">>),

    %% Build objects map from object-id/object-type pairs
    Objects = extract_event_objects(Content),

    %% Build event map
    Event = #{
        <<"event-id">> => EventId,
        <<"activity">> => Activity,
        <<"timestamp">> => Timestamp,
        <<"lifecycle-transition">> => Lifecycle,
        objects => Objects
    },

    %% Merge with other attributes
    maps:merge(Attributes, Event).

%% @private
%% @doc Parse all attributes from event content
parse_event_attributes(Content) ->
    lists:foldl(
        fun(Element, Acc) ->
            case Element of
                #xmlElement{name = string} ->
                    parse_string_attribute(Element, Acc);
                #xmlElement{name = int} ->
                    parse_int_attribute(Element, Acc);
                #xmlElement{name = float} ->
                    parse_float_attribute(Element, Acc);
                #xmlElement{name = boolean} ->
                    parse_boolean_attribute(Element, Acc);
                #xmlElement{name = date} ->
                    parse_date_attribute(Element, Acc);
                #xmlElement{name = id} ->
                    parse_id_attribute(Element, Acc);
                #xmlElement{name = list} ->
                    parse_list_attribute(Element, Acc);
                _ ->
                    Acc
            end
        end,
        #{},
        Content
    ).

%% @private
%% @doc Parse string attribute
parse_string_attribute(Element, Acc) ->
    Key = extract_key(Element),
    Value = extract_value(Element),
    Acc#{Key => Value}.

%% @private
%% @doc Parse int attribute
parse_int_attribute(Element, Acc) ->
    Key = extract_key(Element),
    ValueStr = extract_value(Element),
    Value = case ValueStr of
        undefined -> 0;
        _ -> list_to_integer(binary_to_list(ValueStr))
    end,
    Acc#{Key => Value}.

%% @private
%% @doc Parse float attribute
parse_float_attribute(Element, Acc) ->
    Key = extract_key(Element),
    ValueStr = extract_value(Element),
    Value = case ValueStr of
        undefined -> 0.0;
        _ -> list_to_float(binary_to_list(ValueStr))
    end,
    Acc#{Key => Value}.

%% @private
%% @doc Parse boolean attribute
parse_boolean_attribute(Element, Acc) ->
    Key = extract_key(Element),
    ValueStr = extract_value(Element),
    Value = case ValueStr of
        <<"true">> -> true;
        <<"false">> -> false;
        _ -> false
    end,
    Acc#{Key => Value}.

%% @private
%% @doc Parse date attribute
parse_date_attribute(Element, Acc) ->
    Key = extract_key(Element),
    ValueStr = extract_value(Element),
    Value = case ValueStr of
        undefined -> erlang:system_time(millisecond);
        _ -> parse_iso8601_timestamp(ValueStr)
    end,
    Acc#{Key => Value}.

%% @private
%% @doc Parse id attribute
parse_id_attribute(Element, Acc) ->
    Key = extract_key(Element),
    Value = extract_value(Element),
    Acc#{Key => Value}.

%% @private
%% @doc Parse list attribute
parse_list_attribute(Element, Acc) ->
    Key = extract_key(Element),
    %% For lists, extract all values
    Values = extract_list_values(Element#xmlElement.content),
    Acc#{Key => Values}.

%% @private
%% @doc Extract key from element attributes
extract_key(Element) ->
    case lists:keyfind(key, #xmlAttribute.name, Element#xmlElement.attributes) of
        #xmlAttribute{value = KeyValue} ->
            list_to_binary(KeyValue);
        false ->
            <<"unknown">>
    end.

%% @private
%% @doc Extract value from element attributes
extract_value(Element) ->
    case lists:keyfind(value, #xmlAttribute.name, Element#xmlElement.attributes) of
        #xmlAttribute{value = Value} ->
            list_to_binary(Value);
        false ->
            %% Try to get text content
            case extract_text_content(Element#xmlElement.content) of
                <<>> -> undefined;
                Text -> Text
            end
    end.

%% @private
%% @doc Extract text content from XML content list
extract_text_content(Content) ->
    Texts = lists:foldl(
        fun(Item, Acc) ->
            case Item of
                #xmlText{value = Value, pos = _Pos} ->
                    [Value | Acc];
                _ ->
                    Acc
            end
        end,
        [],
        Content
    ),
    case Texts of
        [] -> <<>>;
        _ -> list_to_binary(lists:reverse(Texts))
    end.

%% @private
%% @doc Extract objects from event content (object-id/object-type pairs)
extract_event_objects(Content) ->
    %% Find all string elements with ocel:object-id and ocel:object-type
    ObjectPairs = extract_object_pairs(Content),

    %% Group by object type
    lists:foldl(
        fun({ObjectId, ObjectType}, Acc) ->
            case maps:get(ObjectType, Acc, undefined) of
                undefined ->
                    Acc#{ObjectType => [ObjectId]};
                ObjectIdList ->
                    Acc#{ObjectType => lists:usort([ObjectId | ObjectIdList])}
            end
        end,
        #{},
        ObjectPairs
    ).

%% @private
%% @doc Extract object-id/object-type pairs from content
extract_object_pairs(Content) ->
    %% Collect all object IDs and types in order
    %% Each object-id is followed by its object-type
    {Pairs, _PendingId} = lists:foldl(
        fun(Element, {AccPairs, PendingId}) ->
            case Element of
                #xmlElement{name = string} ->
                    Key = extract_key(Element),
                    Value = extract_value(Element),
                    case Key of
                        <<"ocel:object-id">> ->
                            %% Store this ID, waiting for its type
                            {AccPairs, Value};
                        <<"ocel:object-type">> ->
                            %% Pair with the pending object-id
                            case PendingId of
                                undefined ->
                                    %% No pending ID, this is a standalone type declaration
                                    {AccPairs, undefined};
                                _ ->
                                    {[{PendingId, Value} | AccPairs], undefined}
                            end;
                        _ ->
                            {AccPairs, PendingId}
                    end;
                _ ->
                    {AccPairs, PendingId}
            end
        end,
        {[], undefined},
        Content
    ),
    lists:reverse(Pairs).

%% @private
%% @doc Build objects map from all events
build_objects_map(Events) ->
    %% Aggregate objects by type across all events
    lists:foldl(
        fun(Event, Acc) ->
            Objects = maps:get(objects, Event, #{}),
            maps:fold(
                fun(ObjectType, ObjectIdList, InnerAcc) ->
                    case maps:get(ObjectType, InnerAcc, undefined) of
                        undefined ->
                            InnerAcc#{ObjectType => ObjectIdList};
                        ExistingList ->
                            InnerAcc#{ObjectType => lists:usort(ExistingList ++ ObjectIdList)}
                    end
                end,
                Acc,
                Objects
            )
        end,
        #{},
        Events
    ).

%% @private
%% @doc Find string attribute by key in content
find_string_attribute(Content, Key) ->
    case lists:search(
        fun(Element) ->
            case Element of
                #xmlElement{name = string} ->
                    case extract_key(Element) of
                        Key -> true;
                        _ -> false
                    end;
                _ ->
                    false
            end
        end,
        Content
    ) of
        {value, Element} ->
            {ok, extract_value(Element)};
        false ->
            error
    end.

%% @private
%% @doc Extract all string values for a given key
extract_all_string_values(Content, Key) ->
    lists:foldl(
        fun(Element, Acc) ->
            case Element of
                #xmlElement{name = string} ->
                    case extract_key(Element) of
                        Key ->
                            Value = extract_value(Element),
                            [Value | Acc];
                        _ ->
                            Acc
                    end;
                _ ->
                    Acc
            end
        end,
        [],
        Content
    ).

%% @private
%% @doc Extract list values from content
extract_list_values(Content) ->
    lists:foldl(
        fun(Element, Acc) ->
            case Element of
                #xmlElement{name = string} ->
                    [extract_value(Element) | Acc];
                #xmlElement{name = int} ->
                    [extract_value(Element) | Acc];
                #xmlElement{name = float} ->
                    [extract_value(Element) | Acc];
                #xmlElement{name = boolean} ->
                    [extract_value(Element) | Acc];
                _ ->
                    Acc
            end
        end,
        [],
        Content
    ).

%% @private
%% @doc Parse ISO 8601 timestamp to milliseconds since epoch
parse_iso8601_timestamp(TimestampBin) ->
    %% Parse format: 2024-02-05T10:00:00.000Z
    try
        TimestampStr = binary_to_list(TimestampBin),
        %% Parse year, month, day
        {YearStr, Rest1} = lists:split(4, TimestampStr),
        Year = list_to_integer(YearStr),
        [_Dash1 | MonthDayStr] = Rest1,
        {MonthStr, Rest2} = lists:split(2, MonthDayStr),
        Month = list_to_integer(MonthStr),
        [_Dash2 | DayTimeStr] = Rest2,
        {DayStr, Rest3} = lists:split(2, DayTimeStr),
        Day = list_to_integer(DayStr),
        [$T | TimeStr] = Rest3,
        {HourStr, Rest4} = lists:split(2, TimeStr),
        Hour = list_to_integer(HourStr),
        [_Colon1 | MinSecStr] = Rest4,
        {MinStr, Rest5} = lists:split(2, MinSecStr),
        Min = list_to_integer(MinStr),
        [_Colon2 | SecMsStr] = Rest5,
        {SecStr, MsStr} = lists:split(2, SecMsStr),
        Sec = list_to_integer(SecStr),

        %% Parse milliseconds if present
        Millis = case MsStr of
            [$. | MsRest] ->
                {MsStr2, _TZ} = lists:split(3, MsRest),
                list_to_integer(MsStr2);
            _ ->
                0
        end,

        %% Convert to Gregorian seconds
        DateTime = {{Year, Month, Day}, {Hour, Min, Sec}},
        EpochStart = calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
        Seconds = calendar:datetime_to_gregorian_seconds(DateTime) - EpochStart,
        Seconds * 1000 + Millis
    catch
        _:_ -> erlang:system_time(millisecond)
    end.

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
