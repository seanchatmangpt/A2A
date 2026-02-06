%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST XES Handler
%%%
%%% This module provides REST API endpoints for XES (eXtensible Event Stream)
%%% log management. XES is a standard XML-based format for storing event logs
%%% from process mining and workflow execution systems.
%%%
%%% ## Endpoints
%%%
%%% - `GET /xes/logs` - List all XES logs
%%% - `GET /xes/logs/{log_id}` - Get specific XES log metadata
%%% - `GET /xes/logs/{log_id}/export` - Export XES log as XML
%%% - `POST /xes/logs/{log_id}/export` - Export XES log to specific directory
%%% - `DELETE /xes/logs/{log_id}` - Delete an XES log
%%% - `GET /xes/workflows/{workflow_id}/events` - Get XES events for workflow
%%% - `POST /xes/workflows/{workflow_id}/export` - Export workflow as XES
%%%
%%% ## API Usage Examples
%%%
%%% ### List all XES logs
%%% ```
%%% curl -X GET http://localhost:8081/xes/logs
%%% ```
%%%
%%% ### Get specific XES log metadata
%%% ```
%%% curl -X GET http://localhost:8081/xes/logs/log_20240101
%%% ```
%%%
%%% ### Export XES log as XML (download)
%%% ```
%%% curl -X GET http://localhost:8081/xes/logs/log_20240101/export \
%%%      -H "Accept: application/xml" \
%%%      -o workflow_log.xes
%%% ```
%%%
%%% ### Export XES log to specific directory
%%% ```
%%% curl -X POST http://localhost:8081/xes/logs/log_20240101/export \
%%%      -H "Content-Type: application/json" \
%%%      -d '{"directory": "/var/log/xes", "filename": "custom_name.xes"}'
%%% ```
%%%
%%% ### Get XES events for a workflow
%%% ```
%%% curl -X GET "http://localhost:8081/xes/workflows/wf_123/events?format=json"
%%% ```
%%%
%%% ### Export workflow as XES log
%%% ```
%%% curl -X POST http://localhost:8081/xes/workflows/wf_123/export \
%%%      -H "Content-Type: application/json" \
%%%      -d '{"include_trace": true, "format": "xes"}'
%%% ```
%%%
%%% ### Delete an XES log
%%% ```
%%% curl -X DELETE http://localhost:8081/xes/logs/log_20240101
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_xes_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    delete_resource/2,
    to_json/2,
    to_xml/2,
    from_json/2,
    options/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    log_id :: binary() | undefined,
    workflow_id :: binary() | undefined,
    action :: binary() | undefined
}).

%% XES Log record (in-memory storage using ETS)
-record(xes_log, {
    log_id :: binary(),
    workflow_id :: binary(),
    created_at :: integer(),
    event_count :: non_neg_integer(),
    traces :: [map()],
    metadata :: map()
}).

%%====================================================================
%% ETS Table Initialization
%%====================================================================

%% @private
ensure_ets_table() ->
    case ets:info(?MODULE) of
        undefined ->
            ets:new(?MODULE, [named_table, public, set, {keypos, 1}]);
        _ ->
            already_exists
    end.

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, Opts) ->
    Method = cowboy_req:method(Req),
    LogId = cowboy_req:binding(log_id, Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        log_id = LogId,
        workflow_id = WorkflowId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case {State#state.log_id, State#state.workflow_id, State#state.action} of
        {undefined, undefined, undefined} ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {LogId, undefined, undefined} when LogId =/= undefined ->
            [<<"GET">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>];
        {LogId, undefined, <<"export">>} when LogId =/= undefined ->
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, WorkflowId, undefined} when WorkflowId =/= undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, WorkflowId, <<"export">>} when WorkflowId =/= undefined ->
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            [<<"OPTIONS">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    case State#state.action of
        <<"export">> ->
            {[
                {{<<"application">>, <<"json">>, []}, to_json},
                {{<<"application">>, <<"xml">>, []}, to_xml},
                {{<<"text">>, <<"xml">>, []}, to_xml},
                {{<<"application">>, <<"vnd.xes+xml">>, []}, to_xml}
            ], Req, State};
        _ ->
            {[
                {{<<"application">>, <<"json">>, []}, to_json},
                {{<<"application">>, <<"vnd.api+json">>, []}, to_json}
            ], Req, State}
    end.

%% @private
content_types_accepted(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, from_json}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    Exists = case {State#state.log_id, State#state.workflow_id, State#state.action} of
        {undefined, undefined, undefined} ->
            true;
        {LogId, undefined, _} when LogId =/= undefined ->
            case ets:lookup(?MODULE, LogId) of
                [{_, _}] -> true;
                [] -> false
            end;
        {undefined, WorkflowId, _} when WorkflowId =/= undefined ->
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, _} -> true;
                {error, _} -> false
            end;
        _ ->
            false
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    LogId = State#state.log_id,
    case ets:lookup(?MODULE, LogId) of
        [{_, _}] ->
            ets:delete(?MODULE, LogId),
            Response = #{
                status => ok,
                message => <<"XES log deleted successfully">>,
                log_id => LogId
            },
            Req2 = response_json(Req, 200, Response),
            {true, Req2, State};
        [] ->
            Response = #{error => <<"log_not_found">>, log_id => LogId},
            Req2 = response_json(Req, 404, Response),
            {false, Req2, State}
    end.

%% @private
options(Req, State) ->
    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>,
                                     <<"GET, POST, DELETE, OPTIONS">>, Req),
    Req3 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>,
                                     <<"Content-Type, Authorization">>, Req2),
    {true, Req3, State}.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.log_id, State#state.workflow_id, State#state.action} of
        {<<"GET">>, undefined, undefined, undefined} ->
            handle_list_logs(Req);
        {<<"GET">>, LogId, undefined, undefined} when LogId =/= undefined ->
            handle_get_log(LogId);
        {<<"GET">>, LogId, undefined, <<"export">>} when LogId =/= undefined ->
            handle_get_export_info(LogId);
        {<<"GET">>, undefined, WorkflowId, undefined} when WorkflowId =/= undefined ->
            handle_get_workflow_events(WorkflowId, Req);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
to_xml(Req, State) ->
    {Response, Req2} = case {State#state.log_id, State#state.workflow_id, State#state.action} of
        {LogId, undefined, <<"export">>} when LogId =/= undefined ->
            export_log_as_xes(LogId, Req);
        _ ->
            ErrorResponse = #{error => <<"xml_not_available_for_this_endpoint">>},
            {jiffy:encode(ErrorResponse), Req}
    end,

    ResponseBody = case Response of
        Xml when is_binary(Xml) -> Xml;
        Map when is_map(Map) -> jiffy:encode(Map)
    end,

    {ResponseBody, Req2, State}.

%% @private
from_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = try
        jiffy:decode(Body, [return_maps])
    catch
        _:_ -> #{error => <<"invalid_json">>}
    end,

    Response = case Data of
        #{error := _} ->
            Data;
        _ ->
            case {State#state.method, State#state.log_id, State#state.workflow_id, State#state.action} of
                {<<"POST">>, LogId, undefined, <<"export">>} when LogId =/= undefined ->
                    handle_export_to_directory(LogId, Data);
                {<<"POST">>, undefined, WorkflowId, <<"export">>} when WorkflowId =/= undefined ->
                    handle_export_workflow_as_xes(WorkflowId, Data);
                _ ->
                    #{error => <<"unknown_request">>}
            end
    end,

    ResponseBody = jiffy:encode(Response),
    Req3 = cowboy_req:reply(201, #{
        <<"content-type">> => <<"application/json">>
    }, ResponseBody, Req2),
    {true, Req3, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_logs(Req) ->
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    WorkflowIdFilter = maps_get(<<"workflow_id">>, Params, undefined),
    Limit = maps_get(<<"limit">>, Params, 50),
    Offset = maps_get(<<"offset">>, Params, 0),

    AllLogs = case WorkflowIdFilter of
        undefined ->
            list_all_xes_logs();
        WorkflowId ->
            lists:filter(fun(Log) ->
                Log#xes_log.workflow_id =:= WorkflowId
            end, list_all_xes_logs())
    end,

    Total = length(AllLogs),
    Paginated = case Limit of
        all -> AllLogs;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(AllLogs, Offset + 1, LimitInt)
    end,

    #{
        logs => [log_to_map(L) || L <- Paginated],
        total => Total,
        returned => length(Paginated),
        offset => Offset
    }.

%% @private
handle_get_log(LogId) ->
    case ets:lookup(?MODULE, LogId) of
        [{_, Log}] ->
            log_to_map(Log);
        [] ->
            #{error => <<"log_not_found">>, log_id => LogId}
    end.

%% @private
handle_get_export_info(LogId) ->
    case ets:lookup(?MODULE, LogId) of
        [{_, Log}] ->
            #{
                log_id => LogId,
                export_formats => [<<"xes">>, <<"json">>, <<"csv">>],
                event_count => Log#xes_log.event_count,
                estimated_size => estimate_xes_size(Log),
                last_modified => Log#xes_log.created_at,
                export_options => #{
                    include_trace => true,
                    include_metadata => true,
                    compress_output => false
                }
            };
        [] ->
            #{error => <<"log_not_found">>, log_id => LogId}
    end.

%% @private
handle_get_workflow_events(WorkflowId, Req) ->
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    Format = maps_get(<<"format">>, Params, <<"json">>),
    IncludeTrace = maps_get(<<"include_trace">>, Params, true),

    case yawl_persistence:get_workflow_history(WorkflowId) of
        {ok, History} ->
            XesEvents = convert_history_to_xes_events(History, WorkflowId),

            case Format of
                <<"xes">> ->
                    #{
                        workflow_id => WorkflowId,
                        format => <<"xes">>,
                        log => generate_xes_log_xml(XesEvents, WorkflowId, IncludeTrace)
                    };
                <<"csv">> ->
                    #{
                        workflow_id => WorkflowId,
                        format => <<"csv">>,
                        events => convert_events_to_csv(XesEvents)
                    };
                _ ->
                    #{
                        workflow_id => WorkflowId,
                        format => <<"json">>,
                        events => XesEvents,
                        total => length(XesEvents),
                        include_trace => IncludeTrace
                    }
            end;
        {error, not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%% @private
export_log_as_xes(LogId, Req) ->
    case ets:lookup(?MODULE, LogId) of
        [{_, Log}] ->
            XesXml = generate_xes_log_xml_from_record(Log),

            Filename = <<LogId/binary, ".xes">>,
            Req2 = cowboy_req:set_resp_header(<<"content-type">>,
                                             <<"application/xml; charset=utf-8">>, Req),
            Req3 = cowboy_req:set_resp_header(<<"content-disposition">>,
                                             <<"attachment; filename=\"", Filename/binary, "\"">>, Req2),

            {XesXml, Req3};
        [] ->
            ErrorResponse = #{error => <<"log_not_found">>, log_id => LogId},
            {jiffy:encode(ErrorResponse), Req}
    end.

%% @private
handle_export_to_directory(LogId, Data) ->
    Directory = maps_get(<<"directory">>, Data, <<"/tmp/xes">>),
    Filename = maps_get(<<"filename">>, Data, <<LogId/binary, ".xes">>),
    Format = maps_get(<<"format">>, Data, <<"xes">>),

    case ets:lookup(?MODULE, LogId) of
        [{_, Log}] ->
            Content = case Format of
                <<"json">> -> jiffy:encode(log_to_map(Log), [pretty]);
                _ -> generate_xes_log_xml_from_record(Log)
            end,

            FilePath = filename:join([Directory, Filename]),

            try
                ok = filelib:ensure_dir(FilePath),
                ok = file:write_file(FilePath, Content),

                #{
                    status => ok,
                    message => <<"Log exported successfully">>,
                    log_id => LogId,
                    file_path => list_to_binary(FilePath),
                    format => Format,
                    size => byte_size(Content)
                }
            catch
                _:_ ->
                    #{error => <<"export_failed">>, message => <<"Failed to write file">>}
            end;
        [] ->
            #{error => <<"log_not_found">>, log_id => LogId}
    end.

%% @private
handle_export_workflow_as_xes(WorkflowId, Data) ->
    IncludeTrace = maps_get(<<"include_trace">>, Data, true),
    IncludeMetadata = maps_get(<<"include_metadata">>, Data, true),

    case yawl_persistence:get_workflow_history(WorkflowId) of
        {ok, History} ->
            XesEvents = convert_history_to_xes_events(History, WorkflowId),

            LogId = <<WorkflowId/binary, "_xes_",
                     (integer_to_binary(erlang:monotonic_time(millisecond)))/binary>>,

            XesLog = #xes_log{
                log_id = LogId,
                workflow_id = WorkflowId,
                created_at = erlang:monotonic_time(millisecond),
                event_count = length(XesEvents),
                traces = XesEvents,
                metadata = #{
                    include_trace => IncludeTrace,
                    include_metadata => IncludeMetadata
                }
            },

            ets:insert(?MODULE, {LogId, XesLog}),

            #{
                status => ok,
                message => <<"Workflow exported as XES log successfully">>,
                workflow_id => WorkflowId,
                log_id => LogId,
                event_count => length(XesEvents),
                export_url => <<"/xes/logs/", LogId/binary, "/export">>
            };
        {error, not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%%====================================================================
%% XES Storage Functions
%%====================================================================

%% @private
list_all_xes_logs() ->
    case ets:info(?MODULE) of
        undefined -> [];
        _ ->
            Lists = ets:tab2list(?MODULE),
            [Log || {_LogId, Log} <- Lists]
    end.

%%====================================================================
%% XES XML Generation Functions
%%====================================================================

%% @private
generate_xes_log_xml(Events, WorkflowId, IncludeTrace) ->
    Header = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
               "<log xmlns=\"http://www.xes-standard.org/\"\n",
               "     version=\"1.0\">\n">>,

    Extensions = <<"  <extension name=\"Concept\" prefix=\"concept\" uri=\"http://www.xes-standard.org/concept.xesext\"/>\n",
                   "  <extension name=\"Time\" prefix=\"time\" uri=\"http://www.xes-standard.org/time.xesext\"/>\n",
                   "  <extension name=\"Organizational\" prefix=\"org\" uri=\"http://www.xes-standard.org/org.xesext\"/>\n",
                   "  <extension name=\"Lifecycle\" prefix=\"lifecycle\" uri=\"http://www.xes-standard.org/lifecycle.xesext\"/>\n">>,

    GlobalTrace = <<"  <global scope=\"trace\">\n",
                   "    <string key=\"concept:name\" value=\"Workflow Trace\"/>\n",
                   "  </global>\n">>,

    GlobalEvent = <<"  <global scope=\"event\">\n",
                   "    <string key=\"concept:name\" value=\"Event Name\"/>\n",
                   "    <string key=\"lifecycle:transition\" value=\"complete\"/>\n",
                   "  </global>\n">>,

    Trace = case IncludeTrace of
        true -> generate_xes_trace(WorkflowId, Events);
        false -> <<>>
    end,

    Footer = <<"</log>\n">>,

    <<Header/binary, Extensions/binary, GlobalTrace/binary,
      GlobalEvent/binary, Trace/binary, Footer/binary>>.

%% @private
generate_xes_log_xml_from_record(Log) ->
    Events = Log#xes_log.traces,
    WorkflowId = Log#xes_log.workflow_id,
    generate_xes_log_xml(Events, WorkflowId, true).

%% @private
generate_xes_trace(WorkflowId, Events) ->
    TraceStart = <<"  <trace>\n",
                   "    <string key=\"concept:name\" value=\"", WorkflowId/binary, "\"/>\n">>,

    EventsXml = lists:map(fun(Event) ->
        generate_xes_event(Event)
    end, Events),

    EventsBin = iolist_to_binary(EventsXml),

    TraceEnd = <<"  </trace>\n">>,

    <<TraceStart/binary, EventsBin/binary, TraceEnd/binary>>.

%% @private
generate_xes_event(Event) ->
    Name = maps_get(<<"name">>, Event, <<"unknown">>),
    Timestamp = maps_get(<<"timestamp">>, Event, erlang:monotonic_time(millisecond)),
    Source = maps_get(<<"source">>, Event, <<"yawl">>),

    IsoTimestamp = format_timestamp_xes(Timestamp),

    <<"    <event>\n",
      "      <string key=\"concept:name\" value=\"", Name/binary, "\"/>\n",
      "      <date key=\"time:timestamp\" value=\"", IsoTimestamp/binary, "\"/>\n",
      "      <string key=\"org:resource\" value=\"", Source/binary, "\"/>\n",
      "    </event>\n">>.

%%====================================================================
%% Conversion Functions
%%====================================================================

%% @private
convert_history_to_xes_events(History, WorkflowId) ->
    lists:map(fun(H) ->
        #yawl_execution_history{
            history_id = HistoryId,
            workitem_id = WorkitemId,
            event_type = EventType,
            event_data = EventData,
            timestamp = Timestamp,
            source = Source
        } = H,

        WorkitemIdBin = case WorkitemId of
            undefined -> <<>>;
            Id -> Id
        end,

        Name = case EventType of
            complete -> <<"complete">>;
            start -> <<"start">>;
            allocate -> <<"allocate">>;
            _ -> atom_to_binary(EventType, utf8)
        end,

        SourceBin = case Source of
            undefined -> <<"yawl">>;
            S when is_atom(S) -> atom_to_binary(S, utf8);
            S when is_binary(S) -> S;
            _ -> <<"yawl">>
        end,

        #{
            <<"event_id">> => HistoryId,
            <<"workflow_id">> => WorkflowId,
            <<"workitem_id">> => WorkitemIdBin,
            <<"name">> => Name,
            <<"type">> => EventType,
            <<"timestamp">> => Timestamp,
            <<"source">> => SourceBin,
            <<"data">> => EventData
        }
    end, History).

%% @private
convert_events_to_csv(Events) ->
    Header = <<"event_id,workflow_id,workitem_id,name,type,timestamp,source\n">>,

    Rows = lists:map(fun(Event) ->
        Row = [
            maps_get(<<"event_id">>, Event, <<>>),
            maps_get(<<"workflow_id">>, Event, <<>>),
            maps_get(<<"workitem_id">>, Event, <<>>),
            maps_get(<<"name">>, Event, <<>>),
            atom_to_binary(maps_get(<<"type">>, Event, complete), utf8),
            integer_to_binary(maps_get(<<"timestamp">>, Event, 0)),
            maps_get(<<"source">>, Event, <<"yawl">>)
        ],
        binary:list_to_bin(lists:join(<<",">>, Row))
    end, Events),

    RowsBin = iolist_to_binary(lists:join(<<"\n">>, Rows)),
    <<Header/binary, RowsBin/binary, "\n">>.

%% @private
log_to_map(#xes_log{} = Log) ->
    #{
        log_id => Log#xes_log.log_id,
        workflow_id => Log#xes_log.workflow_id,
        created_at => Log#xes_log.created_at,
        event_count => Log#xes_log.event_count,
        metadata => Log#xes_log.metadata,
        export_url => <<"/xes/logs/", (Log#xes_log.log_id)/binary, "/export">>
    }.

%% @private
estimate_xes_size(Log) ->
    EventCount = Log#xes_log.event_count,
    EventCount * 500.

%% @private
format_timestamp_xes(Millis) ->
    Seconds = Millis div 1000,
    {{Year, Month, Day}, {Hour, Minute, Second}} =
        calendar:system_time_to_universal_time(Seconds, second),

    Format = fun(N) when N < 10 -> <<"0", (integer_to_binary(N))/binary>>;
                (N) -> integer_to_binary(N)
             end,

    <<(integer_to_binary(Year))/binary, "-",
      (Format(Month))/binary, "-",
      (Format(Day))/binary, "T",
      (Format(Hour))/binary, ":",
      (Format(Minute))/binary, ":",
      (Format(Second))/binary, ".000+00:00">>.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
parse_query_string(<<>>) ->
    #{};
parse_query_string(QS) ->
    parse_query_params(binary:split(QS, <<"&">>), #{}).

%% @private
parse_query_params([], Acc) ->
    Acc;
parse_query_params([Pair | Rest], Acc) ->
    case binary:split(Pair, <<"=">>) of
        [Key, Value] ->
            DecodedKey = uri_string:unquote(Key),
            DecodedValue = uri_string:unquote(Value),
            parse_query_params(Rest, Acc#{DecodedKey => DecodedValue});
        [Key] ->
            DecodedKey = uri_string:unquote(Key),
            parse_query_params(Rest, Acc#{DecodedKey => true})
    end.

%% @private
response_json(Req, StatusCode, Body) ->
    EncodedBody = jiffy:encode(Body),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, EncodedBody, Req).

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
