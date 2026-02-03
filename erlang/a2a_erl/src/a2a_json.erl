%%% @doc A2A JSON Encoding/Decoding
%%%
%%% This module handles JSON serialization following the ProtoJSON specification.
%%% - Enum values use SCREAMING_SNAKE_CASE
%%% - Field names follow camelCase convention
%%% - Timestamps are ISO 8601 format
%%%
%%% Uses the json module from OTP 27+ (enhanced in OTP 28)
-module(a2a_json).

-include("a2a.hrl").

%% Encoding API
-export([
    encode/1,
    encode_task/1,
    encode_message/1,
    encode_artifact/1,
    encode_part/1,
    encode_task_status/1,
    encode_stream_response/1,
    encode_agent_card/1,
    encode_send_message_request/1,
    encode_jsonrpc_response/1,
    encode_jsonrpc_error/1,
    encode_jsonrpc_error/3
]).

%% Decoding API
-export([
    decode/1,
    decode_send_message_request/1,
    decode_message/1,
    decode_part/1,
    decode_get_task_request/1,
    decode_list_tasks_request/1,
    decode_cancel_task_request/1,
    decode_subscribe_to_task_request/1,
    decode_jsonrpc_request/1
]).

%% Utility
-export([
    task_state_to_json/1,
    json_to_task_state/1,
    role_to_json/1,
    json_to_role/1,
    timestamp_to_iso8601/1,
    iso8601_to_timestamp/1
]).

%%% ============================================================================
%%% Encoding Functions
%%% ============================================================================

%% @doc Generic encode - dispatches based on record type
-spec encode(term()) -> binary().
encode(Term) ->
    jiffy:encode(Term).

%% @doc Encode a Task record to JSON map
-spec encode_task(task()) -> map().
encode_task(#task{} = Task) ->
    Base = #{
        <<"id">> => Task#task.id,
        <<"contextId">> => Task#task.context_id,
        <<"status">> => encode_task_status(Task#task.status)
    },

    %% Add optional fields
    WithArtifacts = case Task#task.artifacts of
        [] -> Base;
        Artifacts -> Base#{<<"artifacts">> => [encode_artifact(A) || A <- Artifacts]}
    end,

    WithHistory = case Task#task.history of
        [] -> WithArtifacts;
        History -> WithArtifacts#{<<"history">> => [encode_message(M) || M <- History]}
    end,

    WithMetadata = case Task#task.metadata of
        M when map_size(M) =:= 0 -> WithHistory;
        M -> WithHistory#{<<"metadata">> => M}
    end,

    WithMetadata.

%% @doc Encode TaskStatus
-spec encode_task_status(task_status()) -> map().
encode_task_status(#task_status{} = Status) ->
    Base = #{
        <<"state">> => task_state_to_json(Status#task_status.state)
    },

    WithMessage = case Status#task_status.message of
        undefined -> Base;
        Msg -> Base#{<<"message">> => encode_message(Msg)}
    end,

    WithTimestamp = WithMessage#{<<"timestamp">> =>
        timestamp_to_iso8601(Status#task_status.timestamp)},

    WithTimestamp.

%% @doc Encode a Message record
-spec encode_message(message()) -> map().
encode_message(#message{} = Msg) ->
    Base = #{
        <<"messageId">> => Msg#message.message_id,
        <<"role">> => role_to_json(Msg#message.role),
        <<"parts">> => [encode_part(P) || P <- Msg#message.parts]
    },

    WithContext = case Msg#message.context_id of
        undefined -> Base;
        CId -> Base#{<<"contextId">> => CId}
    end,

    WithTask = case Msg#message.task_id of
        undefined -> WithContext;
        TId -> WithContext#{<<"taskId">> => TId}
    end,

    WithMetadata = case Msg#message.metadata of
        M when map_size(M) =:= 0 -> WithTask;
        M -> WithTask#{<<"metadata">> => M}
    end,

    WithExtensions = case Msg#message.extensions of
        [] -> WithMetadata;
        Ext -> WithMetadata#{<<"extensions">> => Ext}
    end,

    WithRefs = case Msg#message.reference_task_ids of
        [] -> WithExtensions;
        Refs -> WithExtensions#{<<"referenceTaskIds">> => Refs}
    end,

    WithRefs.

%% @doc Encode a Part record
-spec encode_part(part()) -> map().
encode_part(#part{} = Part) ->
    %% Encode content based on type
    Base = case Part#part.content of
        {text, Text} -> #{<<"text">> => Text};
        {raw, Raw} -> #{<<"raw">> => base64:encode(Raw)};
        {url, Url} -> #{<<"url">> => Url};
        {data, Data} -> #{<<"data">> => Data}
    end,

    WithMetadata = case Part#part.metadata of
        M when map_size(M) =:= 0 -> Base;
        M -> Base#{<<"metadata">> => M}
    end,

    WithFilename = case Part#part.filename of
        undefined -> WithMetadata;
        F -> WithMetadata#{<<"filename">> => F}
    end,

    WithMediaType = case Part#part.media_type of
        undefined -> WithFilename;
        MT -> WithFilename#{<<"mediaType">> => MT}
    end,

    WithMediaType.

%% @doc Encode an Artifact record
-spec encode_artifact(artifact()) -> map().
encode_artifact(#artifact{} = Art) ->
    Base = #{
        <<"artifactId">> => Art#artifact.artifact_id,
        <<"parts">> => [encode_part(P) || P <- Art#artifact.parts]
    },

    WithName = case Art#artifact.name of
        undefined -> Base;
        N -> Base#{<<"name">> => N}
    end,

    WithDesc = case Art#artifact.description of
        undefined -> WithName;
        D -> WithName#{<<"description">> => D}
    end,

    WithMetadata = case Art#artifact.metadata of
        M when map_size(M) =:= 0 -> WithDesc;
        M -> WithDesc#{<<"metadata">> => M}
    end,

    WithExtensions = case Art#artifact.extensions of
        [] -> WithMetadata;
        Ext -> WithMetadata#{<<"extensions">> => Ext}
    end,

    WithExtensions.

%% @doc Encode StreamResponse wrapper
-spec encode_stream_response(stream_response()) -> map().
encode_stream_response(#stream_response{payload = Payload}) ->
    case Payload of
        {task, Task} ->
            #{<<"task">> => encode_task(Task)};
        {message, Message} ->
            #{<<"message">> => encode_message(Message)};
        {status_update, Event} ->
            #{<<"statusUpdate">> => encode_task_status_update_event(Event)};
        {artifact_update, Event} ->
            #{<<"artifactUpdate">> => encode_task_artifact_update_event(Event)}
    end.

%% @doc Encode TaskStatusUpdateEvent
-spec encode_task_status_update_event(task_status_update_event()) -> map().
encode_task_status_update_event(#task_status_update_event{} = Event) ->
    Base = #{
        <<"taskId">> => Event#task_status_update_event.task_id,
        <<"contextId">> => Event#task_status_update_event.context_id,
        <<"status">> => encode_task_status(Event#task_status_update_event.status)
    },

    case Event#task_status_update_event.metadata of
        M when map_size(M) =:= 0 -> Base;
        M -> Base#{<<"metadata">> => M}
    end.

%% @doc Encode TaskArtifactUpdateEvent
-spec encode_task_artifact_update_event(task_artifact_update_event()) -> map().
encode_task_artifact_update_event(#task_artifact_update_event{} = Event) ->
    Base = #{
        <<"taskId">> => Event#task_artifact_update_event.task_id,
        <<"contextId">> => Event#task_artifact_update_event.context_id,
        <<"artifact">> => encode_artifact(Event#task_artifact_update_event.artifact)
    },

    WithAppend = case Event#task_artifact_update_event.append of
        false -> Base;
        true -> Base#{<<"append">> => true}
    end,

    WithLastChunk = case Event#task_artifact_update_event.last_chunk of
        false -> WithAppend;
        true -> WithAppend#{<<"lastChunk">> => true}
    end,

    case Event#task_artifact_update_event.metadata of
        M when map_size(M) =:= 0 -> WithLastChunk;
        M -> WithLastChunk#{<<"metadata">> => M}
    end.

%% @doc Encode AgentCard
-spec encode_agent_card(agent_card()) -> map().
encode_agent_card(#agent_card{} = Card) ->
    Base = #{
        <<"name">> => Card#agent_card.name,
        <<"description">> => Card#agent_card.description,
        <<"version">> => Card#agent_card.version,
        <<"supportedInterfaces">> => [encode_agent_interface(I) || I <- Card#agent_card.supported_interfaces],
        <<"capabilities">> => encode_agent_capabilities(Card#agent_card.capabilities),
        <<"defaultInputModes">> => Card#agent_card.default_input_modes,
        <<"defaultOutputModes">> => Card#agent_card.default_output_modes,
        <<"skills">> => [encode_agent_skill(S) || S <- Card#agent_card.skills]
    },

    WithProvider = case Card#agent_card.provider of
        undefined -> Base;
        P -> Base#{<<"provider">> => encode_agent_provider(P)}
    end,

    WithDocUrl = case Card#agent_card.documentation_url of
        undefined -> WithProvider;
        D -> WithProvider#{<<"documentationUrl">> => D}
    end,

    WithSecSchemes = case Card#agent_card.security_schemes of
        M when map_size(M) =:= 0 -> WithDocUrl;
        M -> WithDocUrl#{<<"securitySchemes">> => M}
    end,

    WithSecReqs = case Card#agent_card.security_requirements of
        [] -> WithSecSchemes;
        Reqs -> WithSecSchemes#{<<"securityRequirements">> => Reqs}
    end,

    WithSignatures = case Card#agent_card.signatures of
        [] -> WithSecReqs;
        Sigs -> WithSecReqs#{<<"signatures">> => Sigs}
    end,

    case Card#agent_card.icon_url of
        undefined -> WithSignatures;
        Icon -> WithSignatures#{<<"iconUrl">> => Icon}
    end.

encode_agent_interface(#agent_interface{} = I) ->
    Base = #{
        <<"url">> => I#agent_interface.url,
        <<"protocolBinding">> => I#agent_interface.protocol_binding,
        <<"protocolVersion">> => I#agent_interface.protocol_version
    },
    case I#agent_interface.tenant of
        undefined -> Base;
        T -> Base#{<<"tenant">> => T}
    end.

encode_agent_capabilities(#agent_capabilities{} = C) ->
    Base = #{},
    W1 = case C#agent_capabilities.streaming of
        undefined -> Base;
        S -> Base#{<<"streaming">> => S}
    end,
    W2 = case C#agent_capabilities.push_notifications of
        undefined -> W1;
        P -> W1#{<<"pushNotifications">> => P}
    end,
    W3 = case C#agent_capabilities.extensions of
        [] -> W2;
        Exts -> W2#{<<"extensions">> => [encode_agent_extension(E) || E <- Exts]}
    end,
    case C#agent_capabilities.extended_agent_card of
        undefined -> W3;
        E -> W3#{<<"extendedAgentCard">> => E}
    end.

encode_agent_extension(#agent_extension{} = E) ->
    Base = #{<<"uri">> => E#agent_extension.uri},
    W1 = case E#agent_extension.description of
        undefined -> Base;
        D -> Base#{<<"description">> => D}
    end,
    W2 = case E#agent_extension.required of
        false -> W1;
        true -> W1#{<<"required">> => true}
    end,
    case E#agent_extension.params of
        M when map_size(M) =:= 0 -> W2;
        M -> W2#{<<"params">> => M}
    end.

encode_agent_skill(#agent_skill{} = S) ->
    Base = #{
        <<"id">> => S#agent_skill.id,
        <<"name">> => S#agent_skill.name,
        <<"description">> => S#agent_skill.description,
        <<"tags">> => S#agent_skill.tags
    },
    W1 = case S#agent_skill.examples of
        [] -> Base;
        Ex -> Base#{<<"examples">> => Ex}
    end,
    W2 = case S#agent_skill.input_modes of
        [] -> W1;
        I -> W1#{<<"inputModes">> => I}
    end,
    W3 = case S#agent_skill.output_modes of
        [] -> W2;
        O -> W2#{<<"outputModes">> => O}
    end,
    case S#agent_skill.security_requirements of
        [] -> W3;
        Sec -> W3#{<<"securityRequirements">> => Sec}
    end.

encode_agent_provider(#agent_provider{} = P) ->
    #{
        <<"url">> => P#agent_provider.url,
        <<"organization">> => P#agent_provider.organization
    }.

%% @doc Encode JSON-RPC response
-spec encode_jsonrpc_response(#jsonrpc_response{}) -> binary().
encode_jsonrpc_response(#jsonrpc_response{} = Resp) ->
    Map = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"id">> => Resp#jsonrpc_response.id
    },
    Final = case Resp#jsonrpc_response.error of
        undefined ->
            Map#{<<"result">> => Resp#jsonrpc_response.result};
        Error ->
            Map#{<<"error">> => Error}
    end,
    json:encode(Final).

%% @doc Encode JSON-RPC error
-spec encode_jsonrpc_error(#jsonrpc_error{}) -> map().
encode_jsonrpc_error(#jsonrpc_error{} = Error) ->
    Base = #{
        <<"code">> => Error#jsonrpc_error.code,
        <<"message">> => Error#jsonrpc_error.message
    },
    case Error#jsonrpc_error.data of
        undefined -> Base;
        D -> Base#{<<"data">> => D}
    end.

%% @doc Encode JSON-RPC error (deprecated - for backward compatibility)
-spec encode_jsonrpc_error(integer(), binary(), term()) -> map().
encode_jsonrpc_error(Code, Message, Data) ->
    Base = #{
        <<"code">> => Code,
        <<"message">> => Message
    },
    case Data of
        undefined -> Base;
        D -> Base#{<<"data">> => D}
    end.

%% @doc Encode SendMessageRequest to map
-spec encode_send_message_request(#send_message_request{}) -> map().
encode_send_message_request(#send_message_request{} = Req) ->
    Base = #{
        <<"message">> => encode_message(Req#send_message_request.message)
    },
    WithConfig = case Req#send_message_request.configuration of
        undefined -> Base;
        Config -> Base#{<<"configuration">> => encode_send_message_configuration(Config)}
    end,
    WithTenant = case Req#send_message_request.tenant of
        undefined -> WithConfig;
        Tenant -> WithConfig#{<<"tenant">> => Tenant}
    end,
    case Req#send_message_request.metadata of
        M when map_size(M) =:= 0 -> WithTenant;
        M -> WithTenant#{<<"metadata">> => M}
    end.

%% @doc Encode SendMessageConfiguration to map
-spec encode_send_message_configuration(#send_message_configuration{}) -> map().
encode_send_message_configuration(#send_message_configuration{} = Config) ->
    Base = #{
        <<"blocking">> => Config#send_message_configuration.blocking
    },
    WithModes = case Config#send_message_configuration.accepted_output_modes of
        [] -> Base;
        Modes -> Base#{<<"acceptedOutputModes">> => Modes}
    end,
    WithHistory = case Config#send_message_configuration.history_length of
        undefined -> WithModes;
        HL -> WithModes#{<<"historyLength">> => HL}
    end,
    case Config#send_message_configuration.push_notification_config of
        undefined -> WithHistory;
        PushConfig -> WithHistory#{<<"pushNotificationConfig">> => encode_push_notification_config(PushConfig)}
    end.

%% @doc Encode PushNotificationConfig to map
-spec encode_push_notification_config(#push_notification_config{}) -> map().
encode_push_notification_config(#push_notification_config{} = Config) ->
    Base = #{
        <<"url">> => Config#push_notification_config.url
    },
    WithId = case Config#push_notification_config.id of
        undefined -> Base;
        Id -> Base#{<<"id">> => Id}
    end,
    WithToken = case Config#push_notification_config.token of
        undefined -> WithId;
        Token -> WithId#{<<"token">> => Token}
    end,
    case Config#push_notification_config.authentication of
        undefined -> WithToken;
        Auth -> WithToken#{<<"authentication">> => encode_authentication_info(Auth)}
    end.

%% @doc Encode AuthenticationInfo to map
-spec encode_authentication_info(#authentication_info{}) -> map().
encode_authentication_info(#authentication_info{} = Auth) ->
    Base = #{
        <<"scheme">> => Auth#authentication_info.scheme
    },
    case Auth#authentication_info.credentials of
        undefined -> Base;
        Creds -> Base#{<<"credentials">> => Creds}
    end.

%%% ============================================================================
%%% Decoding Functions
%%% ============================================================================

%% @doc Generic decode
-spec decode(binary()) -> {ok, map()} | {error, term()}.
decode(Json) ->
    try
        {ok, jiffy:decode(Json, [return_maps])}
    catch
        _:Error -> {error, Error}
    end.

%% @doc Decode JSON-RPC request
-spec decode_jsonrpc_request(binary()) -> {ok, #jsonrpc_request{}} | {error, term()}.
decode_jsonrpc_request(Json) ->
    case decode(Json) of
        {ok, Map} ->
            try
                Req = #jsonrpc_request{
                    jsonrpc = maps:get(<<"jsonrpc">>, Map, <<"2.0">>),
                    method = maps:get(<<"method">>, Map),
                    params = maps:get(<<"params">>, Map, #{}),
                    id = maps:get(<<"id">>, Map, undefined)
                },
                {ok, Req}
            catch
                _:_ -> {error, invalid_request}
            end;
        Error -> Error
    end.

%% @doc Decode SendMessageRequest
-spec decode_send_message_request(map()) -> {ok, send_message_request()} | {error, term()}.
decode_send_message_request(Map) ->
    try
        MessageMap = maps:get(<<"message">>, Map),
        {ok, Message} = decode_message(MessageMap),

        Config = case maps:get(<<"configuration">>, Map, undefined) of
            undefined -> undefined;
            CMap -> decode_send_message_configuration(CMap)
        end,

        Req = #send_message_request{
            tenant = maps:get(<<"tenant">>, Map, undefined),
            message = Message,
            configuration = Config,
            metadata = maps:get(<<"metadata">>, Map, #{})
        },
        {ok, Req}
    catch
        _:Error -> {error, Error}
    end.

decode_send_message_configuration(Map) ->
    #send_message_configuration{
        accepted_output_modes = maps:get(<<"acceptedOutputModes">>, Map, []),
        push_notification_config = case maps:get(<<"pushNotificationConfig">>, Map, undefined) of
            undefined -> undefined;
            PMap -> decode_push_notification_config(PMap)
        end,
        history_length = maps:get(<<"historyLength">>, Map, undefined),
        blocking = maps:get(<<"blocking">>, Map, false)
    }.

decode_push_notification_config(Map) ->
    #push_notification_config{
        id = maps:get(<<"id">>, Map, undefined),
        url = maps:get(<<"url">>, Map),
        token = maps:get(<<"token">>, Map, undefined),
        authentication = case maps:get(<<"authentication">>, Map, undefined) of
            undefined -> undefined;
            AMap ->
                #authentication_info{
                    scheme = maps:get(<<"scheme">>, AMap),
                    credentials = maps:get(<<"credentials">>, AMap, undefined)
                }
        end
    }.

%% @doc Decode Message
-spec decode_message(map()) -> {ok, message()} | {error, term()}.
decode_message(Map) ->
    try
        PartsRaw = maps:get(<<"parts">>, Map, []),
        Parts = [decode_part_internal(P) || P <- PartsRaw],

        Msg = #message{
            message_id = maps:get(<<"messageId">>, Map),
            context_id = maps:get(<<"contextId">>, Map, undefined),
            task_id = maps:get(<<"taskId">>, Map, undefined),
            role = json_to_role(maps:get(<<"role">>, Map)),
            parts = Parts,
            metadata = maps:get(<<"metadata">>, Map, #{}),
            extensions = maps:get(<<"extensions">>, Map, []),
            reference_task_ids = maps:get(<<"referenceTaskIds">>, Map, [])
        },
        {ok, Msg}
    catch
        _:Error -> {error, Error}
    end.

%% @doc Decode Part
-spec decode_part(map()) -> {ok, part()} | {error, term()}.
decode_part(Map) ->
    try
        {ok, decode_part_internal(Map)}
    catch
        _:Error -> {error, Error}
    end.

decode_part_internal(Map) ->
    Content = case Map of
        #{<<"text">> := Text} -> {text, Text};
        #{<<"raw">> := Raw} -> {raw, base64:decode(Raw)};
        #{<<"url">> := Url} -> {url, Url};
        #{<<"data">> := Data} -> {data, Data}
    end,

    #part{
        content = Content,
        metadata = maps:get(<<"metadata">>, Map, #{}),
        filename = maps:get(<<"filename">>, Map, undefined),
        media_type = maps:get(<<"mediaType">>, Map, undefined)
    }.

%% @doc Decode GetTaskRequest
-spec decode_get_task_request(map()) -> {ok, get_task_request()} | {error, term()}.
decode_get_task_request(Map) ->
    try
        Req = #get_task_request{
            tenant = maps:get(<<"tenant">>, Map, undefined),
            id = maps:get(<<"id">>, Map),
            history_length = maps:get(<<"historyLength">>, Map, undefined)
        },
        {ok, Req}
    catch
        _:Error -> {error, Error}
    end.

%% @doc Decode ListTasksRequest
-spec decode_list_tasks_request(map()) -> {ok, list_tasks_request()} | {error, term()}.
decode_list_tasks_request(Map) ->
    try
        Req = #list_tasks_request{
            tenant = maps:get(<<"tenant">>, Map, undefined),
            context_id = maps:get(<<"contextId">>, Map, undefined),
            status = case maps:get(<<"status">>, Map, undefined) of
                undefined -> undefined;
                S -> json_to_task_state(S)
            end,
            page_size = maps:get(<<"pageSize">>, Map, undefined),
            page_token = maps:get(<<"pageToken">>, Map, undefined),
            history_length = maps:get(<<"historyLength">>, Map, undefined),
            status_timestamp_after = case maps:get(<<"statusTimestampAfter">>, Map, undefined) of
                undefined -> undefined;
                T -> iso8601_to_timestamp(T)
            end,
            include_artifacts = maps:get(<<"includeArtifacts">>, Map, undefined)
        },
        {ok, Req}
    catch
        _:Error -> {error, Error}
    end.

%% @doc Decode CancelTaskRequest
-spec decode_cancel_task_request(map()) -> {ok, cancel_task_request()} | {error, term()}.
decode_cancel_task_request(Map) ->
    try
        Req = #cancel_task_request{
            tenant = maps:get(<<"tenant">>, Map, undefined),
            id = maps:get(<<"id">>, Map)
        },
        {ok, Req}
    catch
        _:Error -> {error, Error}
    end.

%% @doc Decode SubscribeToTaskRequest
-spec decode_subscribe_to_task_request(map()) -> {ok, subscribe_to_task_request()} | {error, term()}.
decode_subscribe_to_task_request(Map) ->
    try
        Req = #subscribe_to_task_request{
            tenant = maps:get(<<"tenant">>, Map, undefined),
            id = maps:get(<<"id">>, Map)
        },
        {ok, Req}
    catch
        _:Error -> {error, Error}
    end.

%%% ============================================================================
%%% Enum Conversions (ProtoJSON SCREAMING_SNAKE_CASE)
%%% ============================================================================

%% TaskState enum
-spec task_state_to_json(atom()) -> binary().
task_state_to_json(unspecified) -> <<"TASK_STATE_UNSPECIFIED">>;
task_state_to_json(submitted) -> <<"TASK_STATE_SUBMITTED">>;
task_state_to_json(working) -> <<"TASK_STATE_WORKING">>;
task_state_to_json(completed) -> <<"TASK_STATE_COMPLETED">>;
task_state_to_json(failed) -> <<"TASK_STATE_FAILED">>;
task_state_to_json(canceled) -> <<"TASK_STATE_CANCELED">>;
task_state_to_json(input_required) -> <<"TASK_STATE_INPUT_REQUIRED">>;
task_state_to_json(rejected) -> <<"TASK_STATE_REJECTED">>;
task_state_to_json(auth_required) -> <<"TASK_STATE_AUTH_REQUIRED">>.

-spec json_to_task_state(binary()) -> atom().
json_to_task_state(<<"TASK_STATE_UNSPECIFIED">>) -> unspecified;
json_to_task_state(<<"TASK_STATE_SUBMITTED">>) -> submitted;
json_to_task_state(<<"TASK_STATE_WORKING">>) -> working;
json_to_task_state(<<"TASK_STATE_COMPLETED">>) -> completed;
json_to_task_state(<<"TASK_STATE_FAILED">>) -> failed;
json_to_task_state(<<"TASK_STATE_CANCELED">>) -> canceled;
json_to_task_state(<<"TASK_STATE_INPUT_REQUIRED">>) -> input_required;
json_to_task_state(<<"TASK_STATE_REJECTED">>) -> rejected;
json_to_task_state(<<"TASK_STATE_AUTH_REQUIRED">>) -> auth_required.

%% Role enum
-spec role_to_json(atom()) -> binary().
role_to_json(unspecified) -> <<"ROLE_UNSPECIFIED">>;
role_to_json(user) -> <<"ROLE_USER">>;
role_to_json(agent) -> <<"ROLE_AGENT">>.

-spec json_to_role(binary()) -> atom().
json_to_role(<<"ROLE_UNSPECIFIED">>) -> unspecified;
json_to_role(<<"ROLE_USER">>) -> user;
json_to_role(<<"ROLE_AGENT">>) -> agent.

%%% ============================================================================
%%% Timestamp Utilities
%%% ============================================================================

%% @doc Convert millisecond timestamp to ISO 8601 string
-spec timestamp_to_iso8601(integer()) -> binary().
timestamp_to_iso8601(TimestampMs) ->
    Seconds = TimestampMs div 1000,
    Millis = TimestampMs rem 1000,
    {{Year, Month, Day}, {Hour, Min, Sec}} =
        calendar:system_time_to_universal_time(Seconds, second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
        [Year, Month, Day, Hour, Min, Sec, Millis]
    )).

%% @doc Parse ISO 8601 timestamp string to milliseconds
-spec iso8601_to_timestamp(binary()) -> integer().
iso8601_to_timestamp(IsoStr) ->
    %% Parse ISO 8601 format: "2023-10-27T10:00:00.123Z"
    Str = binary_to_list(IsoStr),
    case re:run(Str,
        "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d{1,3}))?Z?$",
        [{capture, all_but_first, list}]) of
        {match, [YearS, MonthS, DayS, HourS, MinS, SecS]} ->
            parse_timestamp_parts(YearS, MonthS, DayS, HourS, MinS, SecS, "0");
        {match, [YearS, MonthS, DayS, HourS, MinS, SecS, MillisS]} ->
            parse_timestamp_parts(YearS, MonthS, DayS, HourS, MinS, SecS, MillisS);
        _ ->
            0
    end.

parse_timestamp_parts(YearS, MonthS, DayS, HourS, MinS, SecS, MillisS) ->
    Year = list_to_integer(YearS),
    Month = list_to_integer(MonthS),
    Day = list_to_integer(DayS),
    Hour = list_to_integer(HourS),
    Min = list_to_integer(MinS),
    Sec = list_to_integer(SecS),
    %% Pad milliseconds to 3 digits - string:pad may return nested lists
    MillisPadded = case string:pad(MillisS, 3, trailing, $0) of
        Bin when is_binary(Bin) -> binary_to_list(Bin);
        List when is_list(List) ->
            %% string:pad may return nested list like ["123", 48, 48]
            %% Need to flatten it to "12300"
            lists:flatten(List)
    end,
    Millis = list_to_integer(MillisPadded),

    DateTime = {{Year, Month, Day}, {Hour, Min, Sec}},
    Seconds = calendar:datetime_to_gregorian_seconds(DateTime) -
              calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
    Seconds * 1000 + Millis.
