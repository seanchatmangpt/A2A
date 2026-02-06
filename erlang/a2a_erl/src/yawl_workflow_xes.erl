%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow XES Logging Module
%%%
%%% This module provides XES (eXtensible Event Stream) logging capabilities
%%% for YAWL workflow execution. XES is the standard format for process mining
%%% event logs, enabling analysis of workflow behavior, performance, and
%%% conformance.
%%%
%%% @end
%%% @author A2A Team
%%% @copyright 2025
%%% @version 1.0.0
%%%-------------------------------------------------------------------

-module(yawl_workflow_xes).
-author("A2A Team").

%%--------------------------------------------------------------------
%% API Exports
%%--------------------------------------------------------------------
-export([
    init/0,
    stop/0,
    log_workflow_start/2,
    log_workflow_complete/2,
    log_workflow_fail/2,
    log_transition/3,
    log_pattern_start/3,
    log_pattern_complete/3,
    log_event/1,
    create_workflow_start_event/2,
    create_workflow_complete_event/2,
    create_workflow_fail_event/2,
    create_transition_event/3,
    create_pattern_event/4,
    export_to_file/1,
    get_workflow_events/1,
    flush_buffer/0
]).

%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------
-include("yawl_xes.hrl").
-include("yawl_types.hrl").
-include_lib("kernel/include/logger.hrl").

%%--------------------------------------------------------------------
%% Macros
%%--------------------------------------------------------------------
-define(XES_STATE, yawl_xes_state).

%%====================================================================
%% API Functions
%%====================================================================

-spec init() -> ok.
init() ->
    Enabled = case application:get_env(a2a_erl, xes_enabled) of
        {ok, Val} -> Val;
        undefined -> true
    end,
    State = #{
        enabled => Enabled,
        buffer => [],
        current_trace => undefined
    },
    put(?XES_STATE, State),
    ?LOG_INFO("XES logging initialized: enabled=~p", [Enabled]),
    ok.

-spec stop() -> ok.
stop() ->
    flush_buffer(),
    erase(?XES_STATE),
    ok.

-spec log_workflow_start(binary(), binary()) -> ok.
log_workflow_start(WorkflowId, CaseId) ->
    Event = create_workflow_start_event(WorkflowId, CaseId),
    log_event(Event),

    State = get(?XES_STATE),
    Trace = #xes_trace{
        trace_id = generate_id(<<"trace">>),
        case_id = CaseId,
        workflow_id = WorkflowId,
        workflow_name = WorkflowId,
        start_time = erlang:system_time(millisecond),
        end_time = undefined,
        events = [Event],
        attributes = #{},
        status = running
    },
    put(?XES_STATE, State#{current_trace => Trace}),
    ok.

-spec log_workflow_complete(binary(), binary()) -> ok.
log_workflow_complete(WorkflowId, CaseId) ->
    Event = create_workflow_complete_event(WorkflowId, CaseId),
    log_event(Event),

    State = get(?XES_STATE),
    CurrentTrace = maps:get(current_trace, State, undefined),
    case CurrentTrace of
        #xes_trace{events = Events} = Trace ->
            _FinalTrace = Trace#xes_trace{
                end_time = erlang:system_time(millisecond),
                events = Events ++ [Event],
                status = completed
            },
            put(?XES_STATE, State#{current_trace => undefined});
        _ -> ok
    end,
    ok.

-spec log_workflow_fail(binary(), binary()) -> ok.
log_workflow_fail(WorkflowId, CaseId) ->
    Event = create_workflow_fail_event(WorkflowId, CaseId),
    log_event(Event),

    State = get(?XES_STATE),
    CurrentTrace = maps:get(current_trace, State, undefined),
    case CurrentTrace of
        #xes_trace{events = Events} = Trace ->
            _FinalTrace = Trace#xes_trace{
                end_time = erlang:system_time(millisecond),
                events = Events ++ [Event],
                status = failed
            },
            put(?XES_STATE, State#{current_trace => undefined});
        _ -> ok
    end,
    ok.

-spec log_transition(binary(), atom(), atom()) -> ok.
log_transition(WorkflowId, Transition, State) ->
    Event = create_transition_event(WorkflowId, Transition, State),
    log_event(Event).

-spec log_pattern_start(binary(), atom(), binary()) -> ok.
log_pattern_start(WorkflowId, PatternType, InstanceId) ->
    Event = create_pattern_event(WorkflowId, PatternType, InstanceId, start),
    log_event(Event).

-spec log_pattern_complete(binary(), atom(), binary()) -> ok.
log_pattern_complete(WorkflowId, PatternType, InstanceId) ->
    Event = create_pattern_event(WorkflowId, PatternType, InstanceId, complete),
    log_event(Event).

-spec log_event(#xes_event{}) -> ok.
log_event(Event) ->
    spawn(fun() ->
        State = get(?XES_STATE),
        Enabled = maps_get(enabled, State, true),
        case Enabled of
            false -> ok;
            true ->
                ?LOG_DEBUG("[XES] ~s ~s ~p",
                    [format_timestamp_ms(Event#xes_event.timestamp),
                     Event#xes_event.activity,
                     Event#xes_event.data_attrs]),
                CurrentTrace = maps_get(current_trace, State, undefined),
                NewTrace = case CurrentTrace of
                    #xes_trace{events = Events} = T ->
                        T#xes_trace{events = Events ++ [Event]};
                    _ -> undefined
                end,
                put(?XES_STATE, (get(?XES_STATE))#{current_trace => NewTrace}),
                Buffer = maps_get(buffer, State, []),
                NewBuffer = Buffer ++ [Event],
                put(?XES_STATE, (get(?XES_STATE))#{buffer => NewBuffer}),
                ok
        end
    end),
    ok.

-spec create_workflow_start_event(binary(), binary()) -> #xes_event{}.
create_workflow_start_event(WorkflowId, CaseId) ->
    #xes_event{
        event_id = generate_id(<<"event">>),
        timestamp = erlang:system_time(millisecond),
        lifecycle = start,
        activity = <<"workflow_start">>,
        transition = undefined,
        resource = undefined,
        data_attrs = #{workflow_id => WorkflowId, case_id => CaseId},
        org_attrs = #{},
        cost_attrs = #{},
        metadata = #{event_type => workflow_start}
    }.

-spec create_workflow_complete_event(binary(), binary()) -> #xes_event{}.
create_workflow_complete_event(WorkflowId, CaseId) ->
    #xes_event{
        event_id = generate_id(<<"event">>),
        timestamp = erlang:system_time(millisecond),
        lifecycle = complete,
        activity = <<"workflow_complete">>,
        transition = undefined,
        resource = undefined,
        data_attrs = #{workflow_id => WorkflowId, case_id => CaseId},
        org_attrs = #{},
        cost_attrs = #{},
        metadata = #{event_type => workflow_complete}
    }.

-spec create_workflow_fail_event(binary(), binary()) -> #xes_event{}.
create_workflow_fail_event(WorkflowId, CaseId) ->
    #xes_event{
        event_id = generate_id(<<"event">>),
        timestamp = erlang:system_time(millisecond),
        lifecycle = pi_abort,
        activity = <<"workflow_fail">>,
        transition = undefined,
        resource = undefined,
        data_attrs = #{workflow_id => WorkflowId, case_id => CaseId},
        org_attrs = #{},
        cost_attrs = #{},
        metadata = #{event_type => workflow_fail}
    }.

-spec create_transition_event(binary(), atom(), atom()) -> #xes_event{}.
create_transition_event(WorkflowId, Transition, TransitionState) ->
    TransitionBin = atom_to_binary(Transition, utf8),
    StateBin = atom_to_binary(TransitionState, utf8),
    #xes_event{
        event_id = generate_id(<<"event">>),
        timestamp = erlang:system_time(millisecond),
        lifecycle = map_lifecycle(TransitionState),
        activity = TransitionBin,
        transition = TransitionBin,
        resource = undefined,
        data_attrs = #{
            workflow_id => WorkflowId,
            transition => TransitionBin,
            state => StateBin
        },
        org_attrs = #{},
        cost_attrs = #{},
        metadata = #{event_type => transition}
    }.

-spec create_pattern_event(binary(), atom(), binary(), atom()) -> #xes_event{}.
create_pattern_event(WorkflowId, PatternType, InstanceId, Status) ->
    PatternBin = atom_to_binary(PatternType, utf8),
    StatusBin = atom_to_binary(Status, utf8),
    #xes_event{
        event_id = generate_id(<<"event">>),
        timestamp = erlang:system_time(millisecond),
        lifecycle = map_lifecycle(Status),
        activity = <<"pattern_", StatusBin/binary>>,
        transition = PatternBin,
        resource = undefined,
        data_attrs = #{
            workflow_id => WorkflowId,
            pattern_type => PatternBin,
            instance_id => InstanceId,
            status => StatusBin
        },
        org_attrs = #{},
        cost_attrs = #{},
        metadata = #{event_type => pattern}
    }.

-spec export_to_file(binary() | string()) -> ok | {error, term()}.
export_to_file(FilePath) ->
    State = get(?XES_STATE),
    CurrentTrace = maps_get(current_trace, State, undefined),
    Traces = case CurrentTrace of
        undefined -> [];
        Trace -> [Trace]
    end,
    XESXml = build_xes_xml(Traces),
    file:write_file(FilePath, XESXml).

-spec get_workflow_events(binary()) -> [#xes_event{}].
get_workflow_events(_WorkflowId) ->
    State = get(?XES_STATE),
    CurrentTrace = maps_get(current_trace, State, undefined),
    case CurrentTrace of
        undefined -> [];
        #xes_trace{events = Events} -> Events
    end.

-spec flush_buffer() -> ok.
flush_buffer() ->
    State = get(?XES_STATE),
    _Buffer = maps_get(buffer, State, []),
    put(?XES_STATE, State#{buffer => []}),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

build_xes_xml(Traces) ->
    TracesXml = lists:map(fun format_trace_xml/1, Traces),
    Header = <<
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<log xes.version=\"1.0\" xes.features=\"nested-attributes\" "
        "xmlns=\"http://www.xes-standard.org/\">\n"
        "  <extension name=\"Concept\" prefix=\"concept\" "
        "uri=\"http://www.xes-standard.org/concept.xesext\"/>\n"
        "  <extension name=\"Time\" prefix=\"time\" "
        "uri=\"http://www.xes-standard.org/time.xesext\"/>\n"
        "  <extension name=\"Organizational\" prefix=\"org\" "
        "uri=\"http://www.xes-standard.org/org.xesext\"/>\n"
        "  <extension name=\"Lifecycle\" prefix=\"lifecycle\" "
        "uri=\"http://www.xes-standard.org/lifecycle.xesext\"/>\n"
        "  <global scope=\"trace\">\n"
        "    <string key=\"concept:name\" value=\"Case ID\"/>\n"
        "  </global>\n"
        "  <global scope=\"event\">\n"
        "    <date key=\"time:timestamp\" value=\"1970-01-01T00:00:00.000+00:00\"/>\n"
        "    <string key=\"concept:name\" value=\"Event Name\"/>\n"
        "    <string key=\"lifecycle:transition\" value=\"complete\"/>\n"
        "  </global>\n"
    >>,
    Footer = <<"</log>\n">>,
    [Header, iolist_to_binary(TracesXml), Footer].

format_trace_xml(#xes_trace{case_id = CaseId, events = Events}) ->
    EventsXml = lists:map(fun format_event_xml/1, Events),
    EventsBin = iolist_to_binary(EventsXml),
    TraceBin = <<
        "  <trace>\n"
        "    <string key=\"concept:name\" value=\"", CaseId/binary, "\"/>\n",
        EventsBin/binary,
        "  </trace>\n"
    >>,
    TraceBin.

format_event_xml(Event) ->
    Timestamp = format_timestamp_iso(Event#xes_event.timestamp),
    Lifecycle = atom_to_binary(Event#xes_event.lifecycle, utf8),
    Activity = Event#xes_event.activity,
    DataAttrs = lists:map(
        fun({K, V}) ->
            KBin = to_binary(K),
            VBin = escape_xml(to_binary(V)),
            <<"        <string key=\"", KBin/binary, "\" value=\"", VBin/binary, "\"/>\n">>
        end,
        maps:to_list(Event#xes_event.data_attrs)
    ),
    DataAttrsBin = case DataAttrs of
        [] -> <<>>;
        _ -> iolist_to_binary(DataAttrs)
    end,
    EventBin = <<
        "    <event>\n"
        "      <date key=\"time:timestamp\" value=\"", Timestamp/binary, "\"/>\n"
        "      <string key=\"concept:name\" value=\"", Activity/binary, "\"/>\n"
        "      <string key=\"lifecycle:transition\" value=\"", Lifecycle/binary, "\"/>\n",
        DataAttrsBin/binary,
        "    </event>\n"
    >>,
    EventBin.

map_lifecycle(start) -> schedule;
map_lifecycle(complete) -> complete;
map_lifecycle(assign) -> assign;
map_lifecycle(reassign) -> reassign;
map_lifecycle(suspend) -> suspend;
map_lifecycle(resume) -> reassign;
map_lifecycle(cancel) -> pi_abort;
map_lifecycle(create) -> pi_schedule;
map_lifecycle(fail) -> pi_abort;
map_lifecycle(_Other) -> complete.

format_timestamp_ms(Ms) ->
    {{Y, M, D}, {H, Min, S}} = calendar:system_time_to_universal_time(Ms div 1000, seconds),
    MsStr = io_lib:format("~3.10.0B", [Ms rem 1000]),
    lists:flatten(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0B ~2.10.0B:~2.10.0B:~2.10.0B.~s",
        [Y, M, D, H, Min, S, MsStr])).

format_timestamp_iso(Ms) ->
    {{Y, M, D}, {H, Min, S}} = calendar:system_time_to_universal_time(Ms div 1000, seconds),
    MsStr = io_lib:format("~3.10.0B", [Ms rem 1000]),
    list_to_binary(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.~sZ",
        [Y, M, D, H, Min, S, MsStr])).

escape_xml(Bin) ->
    Replacements = [
        {<<"&">>, <<"&amp;">>},
        {<<"<">>, <<"&lt;">>},
        {<<">">>, <<"&gt;">>},
        {<<"\"">>, <<"&quot;">>},
        {<<"'">>, <<"&apos;">>}
    ],
    lists:foldl(
        fun({From, To}, Acc) ->
            binary:replace(Acc, From, To, [global])
        end,
        Bin,
        Replacements
    ).

generate_id(Prefix) ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.

maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

to_binary(B) when is_binary(B) -> B;
to_binary(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_binary(I) when is_integer(I) -> integer_to_binary(I);
to_binary(F) when is_float(F) -> float_to_binary(F, [{decimals, 2}]);
to_binary(L) when is_list(L) -> list_to_binary(L);
to_binary(Term) -> list_to_binary(io_lib:format("~p", [Term])).
