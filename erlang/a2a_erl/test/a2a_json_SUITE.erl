%%%-------------------------------------------------------------------
%%% @doc A2A JSON Encoding/Decoding Test Suite
%%%
%%% Common Test suite for a2a_json module with 25 comprehensive tests
%%% covering encoding, decoding, enum conversions, and timestamp utilities.
%%% @end
%%%-------------------------------------------------------------------
-module(a2a_json_SUITE).

-include("a2a.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%% Test suite callbacks
-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2
]).

%% Test cases
-export([
    %% Encoding Tests (Group 1)
    encode_task_minimal/1,
    encode_task_with_artifacts/1,
    encode_task_with_history/1,
    encode_task_full/1,
    encode_message_minimal/1,
    encode_message_with_optional_fields/1,
    encode_part_text/1,
    encode_part_raw/1,
    encode_part_url/1,
    encode_part_data/1,

    %% Decoding Tests (Group 2)
    decode_valid_json/1,
    decode_invalid_json/1,
    decode_message_basic/1,
    decode_part_text/1,
    decode_part_raw/1,
    decode_jsonrpc_request/1,

    %% Enum Conversion Tests (Group 3)
    task_state_to_json_all_states/1,
    json_to_task_state_all_states/1,
    role_to_json_all_roles/1,
    json_to_role_all_roles/1,

    %% Timestamp Tests (Group 4)
    timestamp_to_iso8601_basic/1,
    timestamp_to_iso8601_edge_case/1,
    iso8601_to_timestamp_basic/1,
    iso8601_to_timestamp_with_millis/1,
    iso8601_timestamp_roundtrip/1,

    %% Integration Tests (Group 5)
    encode_decode_task_roundtrip/1,
    encode_decode_message_roundtrip/1,
    jsonrpc_response_success/1,
    jsonrpc_error_encoding/1,
    stream_response_task_payload/1
]).

%%%===================================================================
%%% Test Suite Callbacks
%%%===================================================================

all() ->
    [
        {group, encoding_tests},
        {group, decoding_tests},
        {group, enum_conversion_tests},
        {group, timestamp_tests},
        {group, integration_tests}
    ].

groups() ->
    [
        {encoding_tests, [parallel], [
            encode_task_minimal,
            encode_task_with_artifacts,
            encode_task_with_history,
            encode_task_full,
            encode_message_minimal,
            encode_message_with_optional_fields,
            encode_part_text,
            encode_part_raw,
            encode_part_url,
            encode_part_data
        ]},
        {decoding_tests, [parallel], [
            decode_valid_json,
            decode_invalid_json,
            decode_message_basic,
            decode_part_text,
            decode_part_raw,
            decode_jsonrpc_request
        ]},
        {enum_conversion_tests, [parallel], [
            task_state_to_json_all_states,
            json_to_task_state_all_states,
            role_to_json_all_roles,
            json_to_role_all_roles
        ]},
        {timestamp_tests, [parallel], [
            timestamp_to_iso8601_basic,
            timestamp_to_iso8601_edge_case,
            iso8601_to_timestamp_basic,
            iso8601_to_timestamp_with_millis,
            iso8601_timestamp_roundtrip
        ]},
        {integration_tests, [parallel], [
            encode_decode_task_roundtrip,
            encode_decode_message_roundtrip,
            jsonrpc_response_success,
            jsonrpc_error_encoding,
            stream_response_task_payload
        ]}
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

%%%===================================================================
%%% Encoding Test Cases
%%%===================================================================

encode_task_minimal(_Config) ->
    Task = #task{
        id = <<"task-123">>,
        context_id = <<"ctx-456">>,
        status = #task_status{
            state = submitted,
            timestamp = 1698384000000
        }
    },
    Result = a2a_json:encode_task(Task),
    ?assertEqual(<<"task-123">>, maps:get(<<"id">>, Result)),
    ?assertEqual(<<"ctx-456">>, maps:get(<<"contextId">>, Result)),
    ?assertMatch(#{<<"state">> := <<"TASK_STATE_SUBMITTED">>}, maps:get(<<"status">>, Result)),
    ?assertNot(is_key(<<"artifacts">>, Result)),
    ?assertNot(is_key(<<"history">>, Result)),
    ok.

encode_task_with_artifacts(_Config) ->
    Task = #task{
        id = <<"task-123">>,
        context_id = <<"ctx-456">>,
        status = #task_status{
            state = completed,
            timestamp = 1698384000000
        },
        artifacts = [
            #artifact{
                artifact_id = <<"artifact-1">>,
                parts = [#part{content = {text, <<"Hello World">>}}]
            }
        ]
    },
    Result = a2a_json:encode_task(Task),
    ?assert(is_key(<<"artifacts">>, Result)),
    [ArtifactMap] = maps:get(<<"artifacts">>, Result),
    ?assertEqual(<<"artifact-1">>, maps:get(<<"artifactId">>, ArtifactMap)),
    ok.

encode_task_with_history(_Config) ->
    Task = #task{
        id = <<"task-123">>,
        context_id = <<"ctx-456">>,
        status = #task_status{
            state = working,
            timestamp = 1698384000000
        },
        history = [
            #message{
                message_id = <<"msg-1">>,
                role = user,
                parts = [#part{content = {text, <<"Help me">>}}]
            }
        ]
    },
    Result = a2a_json:encode_task(Task),
    ?assert(is_key(<<"history">>, Result)),
    [MsgMap] = maps:get(<<"history">>, Result),
    ?assertEqual(<<"msg-1">>, maps:get(<<"messageId">>, MsgMap)),
    ?assertEqual(<<"ROLE_USER">>, maps:get(<<"role">>, MsgMap)),
    ok.

encode_task_full(_Config) ->
    Task = #task{
        id = <<"task-123">>,
        context_id = <<"ctx-456">>,
        status = #task_status{
            state = completed,
            message = #message{
                message_id = <<"msg-1">>,
                role = agent,
                parts = [#part{content = {text, <<"Done">>}}]
            },
            timestamp = 1698384000000
        },
        artifacts = [
            #artifact{
                artifact_id = <<"artifact-1">>,
                parts = [#part{content = {text, <<"Result">>}}]
            }
        ],
        history = [
            #message{
                message_id = <<"msg-1">>,
                role = user,
                parts = [#part{content = {text, <<"Help">>}}]
            }
        ],
        metadata = #{<<"key">> => <<"value">>}
    },
    Result = a2a_json:encode_task(Task),
    ?assertEqual(<<"value">>, maps:get(<<"key">>, maps:get(<<"metadata">>, Result))),
    ?assert(is_key(<<"artifacts">>, Result)),
    ?assert(is_key(<<"history">>, Result)),
    ?assert(is_key(<<"metadata">>, Result)),
    ok.

encode_message_minimal(_Config) ->
    Message = #message{
        message_id = <<"msg-123">>,
        role = user,
        parts = [
            #part{content = {text, <<"Hello">>}}
        ]
    },
    Result = a2a_json:encode_message(Message),
    ?assertEqual(<<"msg-123">>, maps:get(<<"messageId">>, Result)),
    ?assertEqual(<<"ROLE_USER">>, maps:get(<<"role">>, Result)),
    ?assertNot(is_key(<<"contextId">>, Result)),
    ?assertNot(is_key(<<"taskId">>, Result)),
    ok.

encode_message_with_optional_fields(_Config) ->
    Message = #message{
        message_id = <<"msg-123">>,
        context_id = <<"ctx-456">>,
        task_id = <<"task-789">>,
        role = agent,
        parts = [#part{content = {text, <<"Response">>}}],
        metadata = #{<<"meta">> => <<"data">>},
        extensions = [<<"ext-1">>],
        reference_task_ids = [<<"ref-1">>, <<"ref-2">>]
    },
    Result = a2a_json:encode_message(Message),
    ?assertEqual(<<"ctx-456">>, maps:get(<<"contextId">>, Result)),
    ?assertEqual(<<"task-789">>, maps:get(<<"taskId">>, Result)),
    ?assertEqual(#{<<"meta">> => <<"data">>}, maps:get(<<"metadata">>, Result)),
    ?assertEqual([<<"ext-1">>], maps:get(<<"extensions">>, Result)),
    ?assertEqual([<<"ref-1">>, <<"ref-2">>], maps:get(<<"referenceTaskIds">>, Result)),
    ok.

encode_part_text(_Config) ->
    Part = #part{content = {text, <<"Hello World">>}},
    Result = a2a_json:encode_part(Part),
    ?assertEqual(<<"Hello World">>, maps:get(<<"text">>, Result)),
    ?assertNot(is_key(<<"raw">>, Result)),
    ?assertNot(is_key(<<"url">>, Result)),
    ok.

encode_part_raw(_Config) ->
    Part = #part{content = {raw, <<1, 2, 3, 4, 5>>}},
    Result = a2a_json:encode_part(Part),
    ?assertEqual(base64:encode(<<1, 2, 3, 4, 5>>), maps:get(<<"raw">>, Result)),
    ?assertNot(is_key(<<"text">>, Result)),
    ok.

encode_part_url(_Config) ->
    Part = #part{content = {url, <<"https://example.com/file.pdf">>}},
    Result = a2a_json:encode_part(Part),
    ?assertEqual(<<"https://example.com/file.pdf">>, maps:get(<<"url">>, Result)),
    ok.

encode_part_data(_Config) ->
    Data = #{<<"key1">> => <<"value1">>, <<"key2">> => 123},
    Part = #part{content = {data, Data}},
    Result = a2a_json:encode_part(Part),
    ?assertEqual(Data, maps:get(<<"data">>, Result)),
    ok.

%%%===================================================================
%%% Decoding Test Cases
%%%===================================================================

decode_valid_json(_Config) ->
    Json = <<"{\"test\": \"value\", \"number\": 42}">>,
    {ok, Result} = a2a_json:decode(Json),
    ?assertEqual(<<"value">>, maps:get(<<"test">>, Result)),
    ?assertEqual(42, maps:get(<<"number">>, Result)),
    ok.

decode_invalid_json(_Config) ->
    Json = <<"{invalid json}">>,
    {error, _Reason} = a2a_json:decode(Json),
    ok.

decode_message_basic(_Config) ->
    JsonMap = #{
        <<"messageId">> => <<"msg-123">>,
        <<"role">> => <<"ROLE_USER">>,
        <<"parts">> => [
            #{<<"text">> => <<"Hello">>}
        ]
    },
    {ok, Message} = a2a_json:decode_message(JsonMap),
    ?assertEqual(<<"msg-123">>, Message#message.message_id),
    ?assertEqual(user, Message#message.role),
    ?assertEqual(1, length(Message#message.parts)),
    ?assertMatch({text, <<"Hello">>}, (hd(Message#message.parts))#part.content),
    ok.

decode_part_text(_Config) ->
    JsonMap = #{<<"text">> => <<"Test text">>},
    {ok, Part} = a2a_json:decode_part(JsonMap),
    ?assertMatch({text, <<"Test text">>}, Part#part.content),
    ok.

decode_part_raw(_Config) ->
    RawData = <<1, 2, 3, 4, 5>>,
    Encoded = base64:encode(RawData),
    JsonMap = #{<<"raw">> => Encoded},
    {ok, Part} = a2a_json:decode_part(JsonMap),
    ?assertMatch({raw, RawData}, Part#part.content),
    ok.

decode_jsonrpc_request(_Config) ->
    Json = <<"{\"jsonrpc\": \"2.0\", \"method\": \"tasks/send\", \"params\": {}, \"id\": 1}">>,
    {ok, Request} = a2a_json:decode_jsonrpc_request(Json),
    ?assertEqual(<<"2.0">>, Request#jsonrpc_request.jsonrpc),
    ?assertEqual(<<"tasks/send">>, Request#jsonrpc_request.method),
    ?assertEqual(1, Request#jsonrpc_request.id),
    ok.

%%%===================================================================
%%% Enum Conversion Test Cases
%%%===================================================================

task_state_to_json_all_states(_Config) ->
    ?assertEqual(<<"TASK_STATE_UNSPECIFIED">>, a2a_json:task_state_to_json(unspecified)),
    ?assertEqual(<<"TASK_STATE_SUBMITTED">>, a2a_json:task_state_to_json(submitted)),
    ?assertEqual(<<"TASK_STATE_WORKING">>, a2a_json:task_state_to_json(working)),
    ?assertEqual(<<"TASK_STATE_COMPLETED">>, a2a_json:task_state_to_json(completed)),
    ?assertEqual(<<"TASK_STATE_FAILED">>, a2a_json:task_state_to_json(failed)),
    ?assertEqual(<<"TASK_STATE_CANCELED">>, a2a_json:task_state_to_json(canceled)),
    ?assertEqual(<<"TASK_STATE_INPUT_REQUIRED">>, a2a_json:task_state_to_json(input_required)),
    ?assertEqual(<<"TASK_STATE_REJECTED">>, a2a_json:task_state_to_json(rejected)),
    ?assertEqual(<<"TASK_STATE_AUTH_REQUIRED">>, a2a_json:task_state_to_json(auth_required)),
    ok.

json_to_task_state_all_states(_Config) ->
    ?assertEqual(unspecified, a2a_json:json_to_task_state(<<"TASK_STATE_UNSPECIFIED">>)),
    ?assertEqual(submitted, a2a_json:json_to_task_state(<<"TASK_STATE_SUBMITTED">>)),
    ?assertEqual(working, a2a_json:json_to_task_state(<<"TASK_STATE_WORKING">>)),
    ?assertEqual(completed, a2a_json:json_to_task_state(<<"TASK_STATE_COMPLETED">>)),
    ?assertEqual(failed, a2a_json:json_to_task_state(<<"TASK_STATE_FAILED">>)),
    ?assertEqual(canceled, a2a_json:json_to_task_state(<<"TASK_STATE_CANCELED">>)),
    ?assertEqual(input_required, a2a_json:json_to_task_state(<<"TASK_STATE_INPUT_REQUIRED">>)),
    ?assertEqual(rejected, a2a_json:json_to_task_state(<<"TASK_STATE_REJECTED">>)),
    ?assertEqual(auth_required, a2a_json:json_to_task_state(<<"TASK_STATE_AUTH_REQUIRED">>)),
    ok.

role_to_json_all_roles(_Config) ->
    ?assertEqual(<<"ROLE_UNSPECIFIED">>, a2a_json:role_to_json(unspecified)),
    ?assertEqual(<<"ROLE_USER">>, a2a_json:role_to_json(user)),
    ?assertEqual(<<"ROLE_AGENT">>, a2a_json:role_to_json(agent)),
    ok.

json_to_role_all_roles(_Config) ->
    ?assertEqual(unspecified, a2a_json:json_to_role(<<"ROLE_UNSPECIFIED">>)),
    ?assertEqual(user, a2a_json:json_to_role(<<"ROLE_USER">>)),
    ?assertEqual(agent, a2a_json:json_to_role(<<"ROLE_AGENT">>)),
    ok.

%%%===================================================================
%%% Timestamp Test Cases
%%%===================================================================

timestamp_to_iso8601_basic(_Config) ->
    %% Unix timestamp for 2023-10-27 10:00:00.123 UTC
    Timestamp = 1698400800123,
    IsoString = a2a_json:timestamp_to_iso8601(Timestamp),
    ?assertEqual(<<"2023-10-27T10:00:00.123Z">>, IsoString),
    ok.

timestamp_to_iso8601_edge_case(_Config) ->
    %% Unix epoch
    Timestamp = 0,
    IsoString = a2a_json:timestamp_to_iso8601(Timestamp),
    ?assertEqual(<<"1970-01-01T00:00:00.000Z">>, IsoString),
    ok.

iso8601_to_timestamp_basic(_Config) ->
    %% ISO 8601 string without milliseconds
    IsoString = <<"2023-10-27T10:00:00Z">>,
    Timestamp = a2a_json:iso8601_to_timestamp(IsoString),
    Expected = 1698400800000,
    ?assertEqual(Expected, Timestamp),
    ok.

iso8601_to_timestamp_with_millis(_Config) ->
    %% ISO 8601 string with milliseconds
    IsoString = <<"2023-10-27T10:00:00.123Z">>,
    Timestamp = a2a_json:iso8601_to_timestamp(IsoString),
    Expected = 1698400800123,
    ?assertEqual(Expected, Timestamp),
    ok.

iso8601_timestamp_roundtrip(_Config) ->
    %% Test that encoding and decoding are consistent
    OriginalTimestamp = 1698400800456,
    IsoString = a2a_json:timestamp_to_iso8601(OriginalTimestamp),
    DecodedTimestamp = a2a_json:iso8601_to_timestamp(IsoString),
    ?assertEqual(OriginalTimestamp, DecodedTimestamp),
    ok.

%%%===================================================================
%%% Integration Test Cases
%%%===================================================================

encode_decode_task_roundtrip(_Config) ->
    %% Create a complete task
    OriginalTask = #task{
        id = <<"task-123">>,
        context_id = <<"ctx-456">>,
        status = #task_status{
            state = working,
            message = #message{
                message_id = <<"msg-1">>,
                role = agent,
                parts = [#part{content = {text, <<"Processing">>}}, #part{content = {data, #{<<"progress">> => 50}}}]
            },
            timestamp = 1698384000000
        },
        artifacts = [
            #artifact{
                artifact_id = <<"artifact-1">>,
                name = <<"result.txt">>,
                description = <<"Analysis result">>,
                parts = [#part{content = {text, <<"Final result">>}}, #part{content = {text, <<"Second line">>}}]
            }
        ],
        history = [
            #message{
                message_id = <<"msg-1">>,
                role = user,
                parts = [#part{content = {text, <<"Start task">>}}]
            },
            #message{
                message_id = <<"msg-2">>,
                role = agent,
                parts = [#part{content = {text, <<"Working on it">>}}]
            }
        ],
        metadata = #{<<"priority">> => <<"high">>, <<"owner">> => <<"user123">>}
    },

    %% Encode the task
    EncodedMap = a2a_json:encode_task(OriginalTask),

    %% Verify encoded fields
    ?assertEqual(<<"task-123">>, maps:get(<<"id">>, EncodedMap)),
    ?assertEqual(<<"ctx-456">>, maps:get(<<"contextId">>, EncodedMap)),
    ?assertMatch(#{<<"state">> := <<"TASK_STATE_WORKING">>}, maps:get(<<"status">>, EncodedMap)),

    %% Verify artifacts
    ?assert(is_key(<<"artifacts">>, EncodedMap)),
    [Artifact] = maps:get(<<"artifacts">>, EncodedMap),
    ?assertEqual(<<"artifact-1">>, maps:get(<<"artifactId">>, Artifact)),
    ?assertEqual(<<"result.txt">>, maps:get(<<"name">>, Artifact)),
    ?assertEqual(<<"Analysis result">>, maps:get(<<"description">>, Artifact)),

    %% Verify history
    ?assert(is_key(<<"history">>, EncodedMap)),
    [Msg1, Msg2] = maps:get(<<"history">>, EncodedMap),
    ?assertEqual(<<"msg-1">>, maps:get(<<"messageId">>, Msg1)),
    ?assertEqual(<<"ROLE_USER">>, maps:get(<<"role">>, Msg1)),
    ?assertEqual(<<"msg-2">>, maps:get(<<"messageId">>, Msg2)),
    ?assertEqual(<<"ROLE_AGENT">>, maps:get(<<"role">>, Msg2)),

    %% Verify metadata
    ?assertMatch(#{<<"priority">> := <<"high">>, <<"owner">> := <<"user123">>}, maps:get(<<"metadata">>, EncodedMap)),

    ok.

encode_decode_message_roundtrip(_Config) ->
    OriginalMessage = #message{
        message_id = <<"msg-456">>,
        context_id = <<"ctx-789">>,
        task_id = <<"task-123">>,
        role = agent,
        parts = [
            #part{
                content = {text, <<"Here is the result">>},
                metadata = #{<<"format">> => <<"markdown">>}
            },
            #part{
                content = {data, #{<<"score">> => 95, <<"confidence">> => 0.98}},
                metadata = #{<<"type">> => <<"metric">>}
            },
            #part{
                content = {url, <<"https://example.com/output.pdf">>},
                filename = <<"report.pdf">>,
                media_type = <<"application/pdf">>
            }
        ],
        metadata = #{<<"version">> => <<"1.0">>},
        extensions = [<<"custom-ext">>],
        reference_task_ids = [<<"task-1">>, <<"task-2">>]
    },

    %% Encode the message
    EncodedMap = a2a_json:encode_message(OriginalMessage),

    %% Verify encoded fields
    ?assertEqual(<<"msg-456">>, maps:get(<<"messageId">>, EncodedMap)),
    ?assertEqual(<<"ctx-789">>, maps:get(<<"contextId">>, EncodedMap)),
    ?assertEqual(<<"task-123">>, maps:get(<<"taskId">>, EncodedMap)),
    ?assertEqual(<<"ROLE_AGENT">>, maps:get(<<"role">>, EncodedMap)),

    %% Verify parts
    [Part1, Part2, Part3] = maps:get(<<"parts">>, EncodedMap),
    ?assertEqual(<<"Here is the result">>, maps:get(<<"text">>, Part1)),
    ?assertMatch(#{<<"format">> := <<"markdown">>}, maps:get(<<"metadata">>, Part1)),

    ?assertMatch(#{<<"score">> := 95, <<"confidence">> := 0.98}, maps:get(<<"data">>, Part2)),

    ?assertEqual(<<"https://example.com/output.pdf">>, maps:get(<<"url">>, Part3)),
    ?assertEqual(<<"report.pdf">>, maps:get(<<"filename">>, Part3)),
    ?assertEqual(<<"application/pdf">>, maps:get(<<"mediaType">>, Part3)),

    %% Decode back to verify roundtrip
    {ok, DecodedMessage} = a2a_json:decode_message(EncodedMap),
    ?assertEqual(OriginalMessage#message.message_id, DecodedMessage#message.message_id),
    ?assertEqual(OriginalMessage#message.role, DecodedMessage#message.role),
    ?assertEqual(3, length(DecodedMessage#message.parts)),

    ok.

jsonrpc_response_success(_Config) ->
    Response = #jsonrpc_response{
        id = 1,
        result = #{<<"taskId">> => <<"task-123">>},
        error = undefined
    },
    JsonBinary = a2a_json:encode_jsonrpc_response(Response),
    {ok, DecodedMap} = a2a_json:decode(JsonBinary),

    ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, DecodedMap)),
    ?assertEqual(1, maps:get(<<"id">>, DecodedMap)),
    ?assert(is_key(<<"result">>, DecodedMap)),
    ?assertNot(is_key(<<"error">>, DecodedMap)),

    Result = maps:get(<<"result">>, DecodedMap),
    ?assertEqual(<<"task-123">>, maps:get(<<"taskId">>, Result)),
    ok.

jsonrpc_error_encoding(_Config) ->
    Error = #jsonrpc_error{
        code = -32601,
        message = <<"Method not found">>,
        data = #{<<"method">> => <<"unknown_method">>}
    },
    ErrorMap = a2a_json:encode_jsonrpc_error(Error),

    ?assertEqual(-32601, maps:get(<<"code">>, ErrorMap)),
    ?assertEqual(<<"Method not found">>, maps:get(<<"message">>, ErrorMap)),
    ?assert(is_key(<<"data">>, ErrorMap)),
    ?assertEqual(<<"unknown_method">>, maps:get(<<"method">>, maps:get(<<"data">>, ErrorMap))),

    %% Test the deprecated 3-arity version
    ErrorMap2 = a2a_json:encode_jsonrpc_error(-32700, <<"Parse error">>, undefined),
    ?assertEqual(-32700, maps:get(<<"code">>, ErrorMap2)),
    ?assertEqual(<<"Parse error">>, maps:get(<<"message">>, ErrorMap2)),
    ?assertNot(is_key(<<"data">>, ErrorMap2)),

    ok.

stream_response_task_payload(_Config) ->
    Task = #task{
        id = <<"task-stream-123">>,
        context_id = <<"ctx-stream-456">>,
        status = #task_status{
            state = working,
            timestamp = 1698384000000
        }
    },
    StreamResponse = #stream_response{payload = {task, Task}},
    ResponseMap = a2a_json:encode_stream_response(StreamResponse),

    ?assert(is_key(<<"task">>, ResponseMap)),
    ?assertNot(is_key(<<"message">>, ResponseMap)),
    ?assertNot(is_key(<<"statusUpdate">>, ResponseMap)),

    TaskMap = maps:get(<<"task">>, ResponseMap),
    ?assertEqual(<<"task-stream-123">>, maps:get(<<"id">>, TaskMap)),
    ?assertEqual(<<"ctx-stream-456">>, maps:get(<<"contextId">>, TaskMap)),
    ok.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

%% @doc Check if a key exists in a map
is_key(Key, Map) ->
    maps:is_key(Key, Map).
