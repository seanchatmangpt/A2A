%%%-------------------------------------------------------------------
%%% @doc BeamAI Anthropic Claude LLM Adapter.
%%%
%%% Implements the llm_provider_behaviour for Anthropic's Claude API.
%%% Supports:
%%% - Claude Messages API (v1/messages endpoint)
%%% - Tool use (function calling) in Anthropic format
%%% - Streaming via SSE (Server-Sent Events)
%%% - Multiple Claude model variants
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_anthropic).

-behaviour(llm_provider_behaviour).

%% Behaviour callbacks
-export([
    chat/2,
    stream/2,
    models/0,
    validate_config/1
]).

%% Additional API
-export([
    format_request/2,
    format_tools/1
]).

-define(API_URL, <<"https://api.anthropic.com/v1/messages">>).
-define(API_VERSION, <<"2023-06-01">>).
-define(DEFAULT_MODEL, <<"claude-sonnet-4-20250514">>).
-define(DEFAULT_MAX_TOKENS, 4096).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Send a chat completion request to Anthropic Claude API.
-spec chat(term(), map()) ->
    {ok, map()} | {error, term()}.
chat(Request, Config) ->
    {Url, Headers, Body} = format_request(Request, Config),
    case llm_http_client:request(post, Url, Headers, Body, #{timeout => 120000}) of
        {ok, _StatusCode, _RespHeaders, RespBody} when is_map(RespBody) ->
            Parsed = parse_chat_response(RespBody),
            {ok, Parsed};
        {ok, _StatusCode, _RespHeaders, RespBody} when is_binary(RespBody) ->
            {error, {unparseable_response, RespBody}};
        {error, {http_error, 429, _Body}} ->
            {error, {transient, rate_limited}};
        {error, {http_error, StatusCode, _Body}} when StatusCode >= 500 ->
            {error, {transient, {server_error, StatusCode}}};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Stream a chat completion request from Anthropic Claude API.
%% The callback in StreamOpts receives SSE events as they arrive.
-spec stream(term(), map()) ->
    {ok, map()} | {error, term()}.
stream(Request, StreamOpts) ->
    Config = maps:without([callback, timeout], StreamOpts),
    Callback = maps:get(callback, StreamOpts, fun(_) -> ok end),
    Timeout = maps:get(timeout, StreamOpts, 120000),

    {Url, Headers, Body0} = format_request(Request, Config),
    %% Enable streaming in the request body
    Body = case Body0 of
        B when is_map(B) -> B#{<<"stream">> => true};
        B when is_binary(B) ->
            Decoded = jsx:decode(B, [return_maps]),
            jsx:encode(Decoded#{<<"stream">> => true})
    end,

    StreamHeaders = [{<<"Accept">>, <<"text/event-stream">>} |
                     lists:keydelete(<<"Accept">>, 1, Headers)],

    %% Accumulate the full response from stream events
    AccRef = make_ref(),
    put({stream_acc, AccRef}, #{content_blocks => [], usage => #{}, stop_reason => undefined}),

    WrappedCallback = fun(Event) ->
        case Event of
            #{type := <<"data">>, data := Data} ->
                handle_stream_event(Data, Callback, AccRef);
            #{type := <<"data">>, raw := _Raw} ->
                ok;
            eof ->
                Callback(eof);
            {error, Reason} ->
                Callback({error, Reason});
            _ ->
                ok
        end
    end,

    case llm_http_client:stream_request(post, Url, StreamHeaders, Body,
                                         #{timeout => Timeout, callback => WrappedCallback}) of
        {ok, _StreamRef} ->
            %% Wait for the stream to complete; the callback handles events
            Acc = get({stream_acc, AccRef}),
            erase({stream_acc, AccRef}),
            {ok, finalize_stream_accumulator(Acc)};
        {error, Reason} ->
            erase({stream_acc, AccRef}),
            {error, Reason}
    end.

%% @doc Return list of supported Anthropic Claude models.
-spec models() -> [map()].
models() ->
    [
        #{
            id => <<"claude-opus-4-20250514">>,
            name => <<"Claude Opus 4">>,
            max_tokens => 32768,
            supports_tools => true,
            supports_streaming => true
        },
        #{
            id => <<"claude-sonnet-4-20250514">>,
            name => <<"Claude Sonnet 4">>,
            max_tokens => 8192,
            supports_tools => true,
            supports_streaming => true
        },
        #{
            id => <<"claude-3-5-haiku-20241022">>,
            name => <<"Claude 3.5 Haiku">>,
            max_tokens => 8192,
            supports_tools => true,
            supports_streaming => true
        }
    ].

%% @doc Validate Anthropic provider configuration.
-spec validate_config(map()) -> ok | {error, [term()]}.
validate_config(Config) ->
    Errors = lists:filtermap(fun(Check) -> Check(Config) end, [
        fun(C) ->
            case get_api_key(C) of
                {ok, _} -> false;
                _ -> {true, missing_api_key}
            end
        end,
        fun(C) ->
            case maps:get(model, C, undefined) of
                undefined -> false;
                Model ->
                    ModelIds = [maps:get(id, M) || M <- models()],
                    case lists:member(Model, ModelIds) of
                        true -> false;
                        false -> {true, {unknown_model, Model}}
                    end
            end
        end
    ]),
    case Errors of
        [] -> ok;
        _ -> {error, Errors}
    end.

%%====================================================================
%% Additional API
%%====================================================================

%% @doc Format a completion request into Anthropic API format.
%% Returns {Url, Headers, BodyMap}.
-spec format_request(term(), map()) -> {binary(), list(), map()}.
format_request(Request, Config) ->
    Model = get_model(Request, Config),
    Messages = get_messages(Request),
    MaxTokens = get_max_tokens(Request, Config),
    Temperature = get_temperature(Request),
    Tools = get_tools(Request),

    %% Separate system messages
    {SystemMsgs, UserMsgs} = lists:partition(fun(Msg) ->
        Role = maps:get(role, Msg, maps:get(<<"role">>, Msg, <<>>)),
        Role =:= <<"system">> orelse Role =:= system
    end, Messages),

    SystemText = case SystemMsgs of
        [] -> undefined;
        _ ->
            SystemParts = [maps:get(content, M,
                          maps:get(<<"content">>, M, <<>>)) || M <- SystemMsgs],
            iolist_to_binary(lists:join(<<"\n\n">>, SystemParts))
    end,

    %% Format non-system messages into Anthropic format
    FormattedMsgs = format_anthropic_messages(UserMsgs),

    Body0 = #{
        <<"model">> => Model,
        <<"messages">> => FormattedMsgs,
        <<"max_tokens">> => MaxTokens,
        <<"temperature">> => Temperature
    },

    Body1 = case SystemText of
        undefined -> Body0;
        _ -> Body0#{<<"system">> => SystemText}
    end,

    Body2 = case Tools of
        [] -> Body1;
        _ -> Body1#{<<"tools">> => format_tools(Tools)}
    end,

    Headers = build_headers(Config),
    Url = maps:get(url, Config, ?API_URL),

    {Url, Headers, Body2}.

%% @doc Format tool definitions into Anthropic's tool format.
-spec format_tools(list()) -> list().
format_tools(Tools) ->
    lists:map(fun(Tool) ->
        #{
            <<"name">> => maps:get(name, Tool, maps:get(<<"name">>, Tool, <<>>)),
            <<"description">> => maps:get(description, Tool,
                                 maps:get(<<"description">>, Tool, <<>>)),
            <<"input_schema">> => maps:get(input_schema, Tool,
                                  maps:get(parameters, Tool,
                                  maps:get(<<"input_schema">>, Tool,
                                  maps:get(<<"parameters">>, Tool,
                                  #{<<"type">> => <<"object">>, <<"properties">> => #{}}))))
        }
    end, Tools).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
-spec build_headers(map()) -> list().
build_headers(Config) ->
    {ok, ApiKey} = get_api_key(Config),
    [
        {<<"x-api-key">>, ApiKey},
        {<<"anthropic-version">>, ?API_VERSION},
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Accept">>, <<"application/json">>}
    ].

%% @private
-spec get_api_key(map()) -> {ok, binary()} | {error, not_found}.
get_api_key(Config) ->
    case maps:get(api_key, Config, undefined) of
        undefined ->
            llm_http_client:get_api_key(anthropic);
        Key ->
            {ok, ensure_binary(Key)}
    end.

%% @private
get_model(Request, Config) ->
    case request_field(model, Request) of
        undefined -> maps:get(model, Config, ?DEFAULT_MODEL);
        Model -> Model
    end.

%% @private
get_messages(Request) ->
    case request_field(messages, Request) of
        undefined -> [];
        Msgs -> Msgs
    end.

%% @private
get_max_tokens(Request, Config) ->
    case request_field(max_tokens, Request) of
        undefined -> maps:get(max_tokens, Config, ?DEFAULT_MAX_TOKENS);
        Tokens -> Tokens
    end.

%% @private
get_temperature(Request) ->
    case request_field(temperature, Request) of
        undefined -> 0.7;
        Temp -> Temp
    end.

%% @private
get_tools(Request) ->
    case request_field(tools, Request) of
        undefined -> [];
        Tools -> Tools
    end.

%% @private
%% Extract a field from either a record-like tuple or map.
request_field(Field, Request) when is_map(Request) ->
    maps:get(Field, Request, undefined);
request_field(model, Request) when is_tuple(Request) ->
    element(3, Request);  %% #completion_request.model
request_field(messages, Request) when is_tuple(Request) ->
    element(4, Request);  %% #completion_request.messages
request_field(tools, Request) when is_tuple(Request) ->
    element(5, Request);  %% #completion_request.tools
request_field(temperature, Request) when is_tuple(Request) ->
    element(6, Request);  %% #completion_request.temperature
request_field(max_tokens, Request) when is_tuple(Request) ->
    element(7, Request);  %% #completion_request.max_tokens
request_field(_, _) ->
    undefined.

%% @private
format_anthropic_messages(Messages) ->
    lists:map(fun(Msg) ->
        Role = ensure_binary(maps:get(role, Msg, maps:get(<<"role">>, Msg, <<"user">>))),
        Content = maps:get(content, Msg, maps:get(<<"content">>, Msg, <<>>)),
        FormattedContent = case Content of
            C when is_binary(C) -> C;
            C when is_list(C) -> C;
            _ -> ensure_binary(Content)
        end,
        #{<<"role">> => Role, <<"content">> => FormattedContent}
    end, Messages).

%% @private
-spec parse_chat_response(map()) -> map().
parse_chat_response(Body) ->
    Content = maps:get(<<"content">>, Body, []),
    TextParts = [maps:get(<<"text">>, B, <<>>)
                || B <- Content,
                   maps:get(<<"type">>, B, <<>>) =:= <<"text">>],
    ToolCalls = [#{
        id => maps:get(<<"id">>, B, <<>>),
        name => maps:get(<<"name">>, B, <<>>),
        arguments => maps:get(<<"input">>, B, #{})
    } || B <- Content, maps:get(<<"type">>, B, <<>>) =:= <<"tool_use">>],

    #{
        id => maps:get(<<"id">>, Body, <<>>),
        model => maps:get(<<"model">>, Body, <<>>),
        content => Content,
        text => iolist_to_binary(TextParts),
        tool_calls => ToolCalls,
        stop_reason => maps:get(<<"stop_reason">>, Body, undefined),
        usage => maps:get(<<"usage">>, Body, #{})
    }.

%% @private
handle_stream_event(Data, Callback, AccRef) when is_map(Data) ->
    EventType = maps:get(<<"type">>, Data, <<>>),
    case EventType of
        <<"content_block_delta">> ->
            Delta = maps:get(<<"delta">>, Data, #{}),
            case maps:get(<<"type">>, Delta, <<>>) of
                <<"text_delta">> ->
                    Text = maps:get(<<"text">>, Delta, <<>>),
                    Callback(#{type => text_delta, text => Text});
                <<"input_json_delta">> ->
                    Json = maps:get(<<"partial_json">>, Delta, <<>>),
                    Callback(#{type => input_json_delta, partial_json => Json});
                _ ->
                    ok
            end;
        <<"content_block_start">> ->
            ContentBlock = maps:get(<<"content_block">>, Data, #{}),
            Acc = get({stream_acc, AccRef}),
            Blocks = maps:get(content_blocks, Acc, []),
            put({stream_acc, AccRef}, Acc#{content_blocks => Blocks ++ [ContentBlock]}),
            ok;
        <<"message_delta">> ->
            Delta = maps:get(<<"delta">>, Data, #{}),
            Acc = get({stream_acc, AccRef}),
            StopReason = maps:get(<<"stop_reason">>, Delta, undefined),
            Usage = maps:get(<<"usage">>, Data, #{}),
            put({stream_acc, AccRef}, Acc#{stop_reason => StopReason, usage => Usage}),
            ok;
        <<"message_start">> ->
            ok;
        <<"message_stop">> ->
            ok;
        _ ->
            ok
    end;
handle_stream_event(_Data, _Callback, _AccRef) ->
    ok.

%% @private
finalize_stream_accumulator(Acc) ->
    Blocks = maps:get(content_blocks, Acc, []),
    TextParts = [maps:get(<<"text">>, B, <<>>)
                || B <- Blocks,
                   maps:get(<<"type">>, B, <<>>) =:= <<"text">>],
    #{
        content => Blocks,
        text => iolist_to_binary(TextParts),
        stop_reason => maps:get(stop_reason, Acc, undefined),
        usage => maps:get(usage, Acc, #{})
    }.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> list_to_binary(io_lib:format("~p", [V])).
