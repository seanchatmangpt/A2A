%%%-------------------------------------------------------------------
%%% @doc BeamAI OpenAI LLM Adapter.
%%%
%%% Implements the llm_provider_behaviour for OpenAI's Chat Completions
%%% API. Supports:
%%% - GPT-4 and GPT-3.5 model families
%%% - Function calling / tool use in OpenAI format
%%% - Streaming via SSE
%%% - Compatible with OpenAI API-compatible services
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_openai).

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

-define(API_URL, <<"https://api.openai.com/v1/chat/completions">>).
-define(DEFAULT_MODEL, <<"gpt-4">>).
-define(DEFAULT_MAX_TOKENS, 4096).

%%====================================================================
%% Behaviour Callbacks
%%====================================================================

%% @doc Send a chat completion request to OpenAI API.
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

%% @doc Stream a chat completion request from OpenAI API.
-spec stream(term(), map()) ->
    {ok, map()} | {error, term()}.
stream(Request, StreamOpts) ->
    Config = maps:without([callback, timeout], StreamOpts),
    Callback = maps:get(callback, StreamOpts, fun(_) -> ok end),
    Timeout = maps:get(timeout, StreamOpts, 120000),

    {Url, Headers, Body0} = format_request(Request, Config),
    Body = case Body0 of
        B when is_map(B) -> B#{<<"stream">> => true};
        B when is_binary(B) ->
            Decoded = jsx:decode(B, [return_maps]),
            jsx:encode(Decoded#{<<"stream">> => true})
    end,

    StreamHeaders = [{<<"Accept">>, <<"text/event-stream">>} |
                     lists:keydelete(<<"Accept">>, 1, Headers)],

    %% Accumulate streamed content
    AccRef = make_ref(),
    put({stream_acc, AccRef}, #{chunks => [], finish_reason => undefined}),

    WrappedCallback = fun(Event) ->
        case Event of
            #{type := <<"data">>, data := Data} ->
                handle_stream_event(Data, Callback, AccRef);
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
            Acc = get({stream_acc, AccRef}),
            erase({stream_acc, AccRef}),
            {ok, finalize_stream_accumulator(Acc)};
        {error, Reason} ->
            erase({stream_acc, AccRef}),
            {error, Reason}
    end.

%% @doc Return list of supported OpenAI models.
-spec models() -> [map()].
models() ->
    [
        #{
            id => <<"gpt-4">>,
            name => <<"GPT-4">>,
            max_tokens => 8192,
            supports_tools => true,
            supports_streaming => true
        },
        #{
            id => <<"gpt-4-turbo">>,
            name => <<"GPT-4 Turbo">>,
            max_tokens => 128000,
            supports_tools => true,
            supports_streaming => true
        },
        #{
            id => <<"gpt-4o">>,
            name => <<"GPT-4o">>,
            max_tokens => 128000,
            supports_tools => true,
            supports_streaming => true
        },
        #{
            id => <<"gpt-3.5-turbo">>,
            name => <<"GPT-3.5 Turbo">>,
            max_tokens => 16384,
            supports_tools => true,
            supports_streaming => true
        }
    ].

%% @doc Validate OpenAI provider configuration.
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

%% @doc Format a completion request into OpenAI API format.
-spec format_request(term(), map()) -> {binary(), list(), map()}.
format_request(Request, Config) ->
    Model = get_model(Request, Config),
    Messages = get_messages(Request),
    MaxTokens = get_max_tokens(Request, Config),
    Temperature = get_temperature(Request),
    Tools = get_tools(Request),

    FormattedMsgs = format_openai_messages(Messages),

    Body0 = #{
        <<"model">> => Model,
        <<"messages">> => FormattedMsgs,
        <<"max_tokens">> => MaxTokens,
        <<"temperature">> => Temperature
    },

    Body1 = case Tools of
        [] -> Body0;
        _ -> Body0#{<<"tools">> => format_tools(Tools)}
    end,

    Headers = build_headers(Config),
    Url = maps:get(url, Config, ?API_URL),

    {Url, Headers, Body1}.

%% @doc Format tool definitions into OpenAI function calling format.
-spec format_tools(list()) -> list().
format_tools(Tools) ->
    lists:map(fun(Tool) ->
        Name = maps:get(name, Tool, maps:get(<<"name">>, Tool, <<>>)),
        Desc = maps:get(description, Tool, maps:get(<<"description">>, Tool, <<>>)),
        Params = maps:get(parameters, Tool,
                 maps:get(input_schema, Tool,
                 maps:get(<<"parameters">>, Tool,
                 maps:get(<<"input_schema">>, Tool,
                 #{<<"type">> => <<"object">>, <<"properties">> => #{}})))),
        #{
            <<"type">> => <<"function">>,
            <<"function">> => #{
                <<"name">> => Name,
                <<"description">> => Desc,
                <<"parameters">> => Params
            }
        }
    end, Tools).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
-spec build_headers(map()) -> list().
build_headers(Config) ->
    {ok, ApiKey} = get_api_key(Config),
    BaseHeaders = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Accept">>, <<"application/json">>}
    ],
    %% Add organization header if configured
    case maps:get(organization, Config, undefined) of
        undefined -> BaseHeaders;
        Org -> [{<<"OpenAI-Organization">>, ensure_binary(Org)} | BaseHeaders]
    end.

%% @private
-spec get_api_key(map()) -> {ok, binary()} | {error, not_found}.
get_api_key(Config) ->
    case maps:get(api_key, Config, undefined) of
        undefined ->
            llm_http_client:get_api_key(openai);
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
request_field(Field, Request) when is_map(Request) ->
    maps:get(Field, Request, undefined);
request_field(model, Request) when is_tuple(Request) ->
    element(3, Request);
request_field(messages, Request) when is_tuple(Request) ->
    element(4, Request);
request_field(tools, Request) when is_tuple(Request) ->
    element(5, Request);
request_field(temperature, Request) when is_tuple(Request) ->
    element(6, Request);
request_field(max_tokens, Request) when is_tuple(Request) ->
    element(7, Request);
request_field(_, _) ->
    undefined.

%% @private
format_openai_messages(Messages) ->
    lists:map(fun(Msg) ->
        Role = ensure_binary(maps:get(role, Msg, maps:get(<<"role">>, Msg, <<"user">>))),
        Content = maps:get(content, Msg, maps:get(<<"content">>, Msg, <<>>)),
        ContentBin = case Content of
            C when is_binary(C) -> C;
            C when is_list(C) ->
                %% Flatten content blocks for OpenAI
                Parts = lists:filtermap(fun(Block) when is_map(Block) ->
                    case maps:get(<<"type">>, Block, maps:get(type, Block, <<>>)) of
                        <<"text">> ->
                            {true, maps:get(<<"text">>, Block, maps:get(text, Block, <<>>))};
                        _ -> false
                    end;
                (Text) when is_binary(Text) ->
                    {true, Text};
                (_) -> false
                end, C),
                iolist_to_binary(Parts);
            _ -> ensure_binary(Content)
        end,
        Base = #{<<"role">> => Role, <<"content">> => ContentBin},
        %% Include name if present
        case maps:get(name, Msg, maps:get(<<"name">>, Msg, undefined)) of
            undefined -> Base;
            Name -> Base#{<<"name">> => ensure_binary(Name)}
        end
    end, Messages).

%% @private
-spec parse_chat_response(map()) -> map().
parse_chat_response(Body) ->
    Choices = maps:get(<<"choices">>, Body, []),
    case Choices of
        [FirstChoice | _] ->
            Message = maps:get(<<"message">>, FirstChoice, #{}),
            Content = maps:get(<<"content">>, Message, <<>>),
            FinishReason = maps:get(<<"finish_reason">>, FirstChoice, undefined),

            %% Extract tool calls if present
            ToolCalls = case maps:get(<<"tool_calls">>, Message, []) of
                [] -> [];
                RawCalls ->
                    lists:map(fun(Call) ->
                        Function = maps:get(<<"function">>, Call, #{}),
                        ArgsStr = maps:get(<<"arguments">>, Function, <<"{}">>),
                        Args = try jsx:decode(ArgsStr, [return_maps])
                               catch _:_ -> #{} end,
                        #{
                            id => maps:get(<<"id">>, Call, <<>>),
                            name => maps:get(<<"name">>, Function, <<>>),
                            arguments => Args
                        }
                    end, RawCalls)
            end,

            #{
                id => maps:get(<<"id">>, Body, <<>>),
                model => maps:get(<<"model">>, Body, <<>>),
                content => ensure_binary_or_empty(Content),
                text => ensure_binary_or_empty(Content),
                tool_calls => ToolCalls,
                stop_reason => FinishReason,
                usage => maps:get(<<"usage">>, Body, #{})
            };
        [] ->
            #{
                id => maps:get(<<"id">>, Body, <<>>),
                model => maps:get(<<"model">>, Body, <<>>),
                content => <<>>,
                text => <<>>,
                tool_calls => [],
                stop_reason => undefined,
                usage => maps:get(<<"usage">>, Body, #{})
            }
    end.

%% @private
handle_stream_event(Data, Callback, AccRef) when is_map(Data) ->
    Choices = maps:get(<<"choices">>, Data, []),
    case Choices of
        [Choice | _] ->
            Delta = maps:get(<<"delta">>, Choice, #{}),
            Content = maps:get(<<"content">>, Delta, undefined),
            FinishReason = maps:get(<<"finish_reason">>, Choice, undefined),

            case Content of
                undefined -> ok;
                null -> ok;
                Text when is_binary(Text) ->
                    Callback(#{type => text_delta, text => Text}),
                    Acc = get({stream_acc, AccRef}),
                    Chunks = maps:get(chunks, Acc, []),
                    put({stream_acc, AccRef}, Acc#{chunks => Chunks ++ [Text]})
            end,

            case FinishReason of
                undefined -> ok;
                null -> ok;
                Reason ->
                    Acc2 = get({stream_acc, AccRef}),
                    put({stream_acc, AccRef}, Acc2#{finish_reason => Reason})
            end;
        [] ->
            ok
    end;
handle_stream_event(_Data, _Callback, _AccRef) ->
    ok.

%% @private
finalize_stream_accumulator(Acc) ->
    Chunks = maps:get(chunks, Acc, []),
    FullText = iolist_to_binary(Chunks),
    #{
        content => FullText,
        text => FullText,
        tool_calls => [],
        stop_reason => maps:get(finish_reason, Acc, undefined),
        usage => #{}
    }.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> list_to_binary(io_lib:format("~p", [V])).

%% @private
ensure_binary_or_empty(null) -> <<>>;
ensure_binary_or_empty(undefined) -> <<>>;
ensure_binary_or_empty(V) -> ensure_binary(V).
