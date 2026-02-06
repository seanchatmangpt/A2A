%%%-------------------------------------------------------------------
%%% @doc LLM HTTP Client.
%%%
%%% HTTP client wrapper specialized for LLM API calls. Built on top
%%% of hackney with features for:
%%% - Automatic retry with exponential backoff
%%% - Request/response logging
%%% - API key management via ETS-backed credential store
%%% - Streaming SSE (Server-Sent Events) parsing
%%% - Timeout management
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(llm_http_client).

-export([
    request/4,
    request/5,
    stream_request/4,
    stream_request/5,
    set_api_key/2,
    get_api_key/1,
    delete_api_key/1
]).

-define(CREDENTIAL_TABLE, beamai_llm_credentials).
-define(DEFAULT_TIMEOUT, 60000).
-define(DEFAULT_CONNECT_TIMEOUT, 10000).
-define(MAX_RETRIES, 3).
-define(BASE_RETRY_DELAY, 1000).

-type method() :: get | post | put | delete.
-type url() :: binary() | string().
-type headers() :: [{binary(), binary()}].
-type body() :: binary() | map().

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Perform an HTTP request to an LLM API endpoint.
%% Body can be a binary or a map (which will be JSON-encoded).
-spec request(method(), url(), headers(), body()) ->
    {ok, integer(), headers(), map() | binary()} | {error, term()}.
request(Method, Url, Headers, Body) ->
    request(Method, Url, Headers, Body, #{}).

%% @doc Perform an HTTP request with custom options.
%% Options:
%%   timeout     - Request timeout in ms (default 60000)
%%   retries     - Max retry count (default 3)
%%   retry_delay - Base retry delay in ms (default 1000)
%%   log_request - Whether to log requests (default false)
-spec request(method(), url(), headers(), body(), map()) ->
    {ok, integer(), headers(), map() | binary()} | {error, term()}.
request(Method, Url, Headers, Body, Opts) ->
    EncodedBody = encode_body(Body),
    MergedHeaders = merge_default_headers(Headers),
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    MaxRetries = maps:get(retries, Opts, ?MAX_RETRIES),
    BaseDelay = maps:get(retry_delay, Opts, ?BASE_RETRY_DELAY),
    LogRequest = maps:get(log_request, Opts, false),

    case LogRequest of
        true ->
            logger:debug("LLM HTTP ~p ~s", [Method, Url]);
        false ->
            ok
    end,

    do_request_with_retry(Method, ensure_binary(Url), MergedHeaders,
                          EncodedBody, Timeout, 0, MaxRetries, BaseDelay).

%% @doc Perform a streaming HTTP request for SSE-based LLM responses.
%% The callback function is invoked for each parsed SSE event.
-spec stream_request(method(), url(), headers(), body()) ->
    {ok, reference()} | {error, term()}.
stream_request(Method, Url, Headers, Body) ->
    stream_request(Method, Url, Headers, Body, #{}).

%% @doc Perform a streaming HTTP request with options.
-spec stream_request(method(), url(), headers(), body(), map()) ->
    {ok, reference()} | {error, term()}.
stream_request(Method, Url, Headers, Body, Opts) ->
    EncodedBody = encode_body(Body),
    MergedHeaders = merge_default_headers(Headers),
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    Callback = maps:get(callback, Opts, fun(_Event) -> ok end),

    UrlBin = ensure_binary(Url),
    HackneyOpts = [
        {recv_timeout, Timeout},
        {connect_timeout, ?DEFAULT_CONNECT_TIMEOUT},
        async
    ],

    case hackney:request(Method, UrlBin, MergedHeaders, EncodedBody, HackneyOpts) of
        {ok, ClientRef} ->
            StreamRef = make_ref(),
            spawn_link(fun() ->
                stream_receiver(ClientRef, Callback, StreamRef, <<>>)
            end),
            {ok, StreamRef};
        {error, Reason} ->
            logger:error("LLM stream request failed: ~p", [Reason]),
            {error, Reason}
    end.

%% @doc Store an API key for a provider in the credential store.
-spec set_api_key(atom(), binary()) -> ok.
set_api_key(Provider, ApiKey) ->
    ensure_credential_table(),
    ets:insert(?CREDENTIAL_TABLE, {Provider, ApiKey}),
    ok.

%% @doc Retrieve an API key for a provider.
%% Falls back to environment variables if not in ETS.
-spec get_api_key(atom()) -> {ok, binary()} | {error, not_found}.
get_api_key(Provider) ->
    ensure_credential_table(),
    case ets:lookup(?CREDENTIAL_TABLE, Provider) of
        [{Provider, ApiKey}] ->
            {ok, ApiKey};
        [] ->
            %% Fallback to environment variable
            EnvVar = provider_env_var(Provider),
            case os:getenv(EnvVar) of
                false -> {error, not_found};
                Value -> {ok, list_to_binary(Value)}
            end
    end.

%% @doc Delete a stored API key.
-spec delete_api_key(atom()) -> ok.
delete_api_key(Provider) ->
    ensure_credential_table(),
    ets:delete(?CREDENTIAL_TABLE, Provider),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
do_request_with_retry(Method, Url, Headers, Body, Timeout, Attempt, MaxRetries, BaseDelay) ->
    HackneyOpts = [
        {recv_timeout, Timeout},
        {connect_timeout, ?DEFAULT_CONNECT_TIMEOUT},
        with_body
    ],
    case hackney:request(Method, Url, Headers, Body, HackneyOpts) of
        {ok, StatusCode, RespHeaders, RespBody} when StatusCode >= 200, StatusCode < 300 ->
            DecodedBody = try_decode_json(RespBody),
            {ok, StatusCode, RespHeaders, DecodedBody};
        {ok, StatusCode, RespHeaders, RespBody} when StatusCode =:= 429;
                                                      StatusCode =:= 500;
                                                      StatusCode =:= 502;
                                                      StatusCode =:= 503;
                                                      StatusCode =:= 504 ->
            %% Retryable status codes
            case Attempt < MaxRetries of
                true ->
                    Delay = compute_retry_delay(StatusCode, RespHeaders, Attempt, BaseDelay),
                    logger:warning("LLM API returned ~p, retrying in ~pms (attempt ~p/~p)",
                                   [StatusCode, Delay, Attempt + 1, MaxRetries]),
                    timer:sleep(Delay),
                    do_request_with_retry(Method, Url, Headers, Body, Timeout,
                                          Attempt + 1, MaxRetries, BaseDelay);
                false ->
                    DecodedBody = try_decode_json(RespBody),
                    {error, {http_error, StatusCode, DecodedBody}}
            end;
        {ok, StatusCode, _RespHeaders, RespBody} ->
            DecodedBody = try_decode_json(RespBody),
            {error, {http_error, StatusCode, DecodedBody}};
        {error, Reason} when Attempt < MaxRetries,
                              (Reason =:= timeout orelse
                               Reason =:= closed orelse
                               Reason =:= econnrefused) ->
            Delay = BaseDelay * (1 bsl Attempt) + rand:uniform(BaseDelay),
            logger:warning("LLM HTTP error ~p, retrying in ~pms (attempt ~p/~p)",
                           [Reason, Delay, Attempt + 1, MaxRetries]),
            timer:sleep(Delay),
            do_request_with_retry(Method, Url, Headers, Body, Timeout,
                                  Attempt + 1, MaxRetries, BaseDelay);
        {error, Reason} ->
            logger:error("LLM HTTP request failed permanently: ~p", [Reason]),
            {error, Reason}
    end.

%% @private
%% Compute retry delay, respecting Retry-After header if present.
-spec compute_retry_delay(integer(), list(), non_neg_integer(), non_neg_integer()) ->
    non_neg_integer().
compute_retry_delay(_StatusCode, RespHeaders, Attempt, BaseDelay) ->
    RetryAfter = find_header(<<"retry-after">>, RespHeaders),
    case RetryAfter of
        undefined ->
            %% Exponential backoff with jitter
            BaseDelay * (1 bsl Attempt) + rand:uniform(BaseDelay);
        Value ->
            try
                binary_to_integer(Value) * 1000
            catch _:_ ->
                BaseDelay * (1 bsl Attempt)
            end
    end.

%% @private
-spec find_header(binary(), list()) -> binary() | undefined.
find_header(Name, Headers) ->
    LowerName = string:lowercase(Name),
    case lists:keyfind(LowerName, 1, [{string:lowercase(K), V} || {K, V} <- Headers]) of
        {_, Value} -> Value;
        false -> undefined
    end.

%% @private
%% Receive and parse SSE events from a hackney async stream.
-spec stream_receiver(reference(), fun(), reference(), binary()) -> ok.
stream_receiver(ClientRef, Callback, StreamRef, Buffer) ->
    receive
        {hackney_response, ClientRef, {status, StatusCode, _Reason}} ->
            case StatusCode >= 200 andalso StatusCode < 300 of
                true ->
                    stream_receiver(ClientRef, Callback, StreamRef, Buffer);
                false ->
                    Callback({error, {http_status, StatusCode}}),
                    hackney:close(ClientRef)
            end;
        {hackney_response, ClientRef, {headers, _Headers}} ->
            stream_receiver(ClientRef, Callback, StreamRef, Buffer);
        {hackney_response, ClientRef, done} ->
            %% Process any remaining data in buffer
            process_sse_buffer(Buffer, Callback),
            Callback(eof),
            ok;
        {hackney_response, ClientRef, Chunk} when is_binary(Chunk) ->
            NewBuffer = <<Buffer/binary, Chunk/binary>>,
            Remaining = process_sse_buffer(NewBuffer, Callback),
            stream_receiver(ClientRef, Callback, StreamRef, Remaining);
        {hackney_response, ClientRef, {error, Reason}} ->
            Callback({error, Reason}),
            ok
    after 120000 ->
        Callback({error, stream_timeout}),
        hackney:close(ClientRef),
        ok
    end.

%% @private
%% Parse SSE events from buffer, returning unparsed remainder.
-spec process_sse_buffer(binary(), fun()) -> binary().
process_sse_buffer(Buffer, Callback) ->
    Lines = binary:split(Buffer, <<"\n">>, [global]),
    process_sse_lines(Lines, Callback, <<>>).

process_sse_lines([], _Callback, Acc) ->
    Acc;
process_sse_lines([Last], _Callback, _Acc) ->
    %% Last incomplete line becomes the new buffer
    Last;
process_sse_lines([Line | Rest], Callback, _Acc) ->
    case Line of
        <<"data: ", Data/binary>> ->
            case Data of
                <<"[DONE]">> ->
                    ok;
                _ ->
                    case try_decode_json(Data) of
                        Data when is_binary(Data) ->
                            Callback(#{type => <<"data">>, raw => Data});
                        Decoded ->
                            Callback(#{type => <<"data">>, data => Decoded})
                    end
            end;
        <<"event: ", EventType/binary>> ->
            Callback(#{type => <<"event">>, event => EventType});
        <<>> ->
            ok;
        _ ->
            ok
    end,
    process_sse_lines(Rest, Callback, <<>>).

%% @private
-spec encode_body(body()) -> binary().
encode_body(Body) when is_binary(Body) -> Body;
encode_body(Body) when is_map(Body) -> jsx:encode(Body);
encode_body(Body) when is_list(Body) -> jsx:encode(Body);
encode_body(<<>>) -> <<>>.

%% @private
-spec merge_default_headers(headers()) -> headers().
merge_default_headers(Headers) ->
    Defaults = [
        {<<"Content-Type">>, <<"application/json">>},
        {<<"Accept">>, <<"application/json">>}
    ],
    ExistingKeys = [K || {K, _} <- Headers],
    FilteredDefaults = [{K, V} || {K, V} <- Defaults,
                        not lists:member(K, ExistingKeys)],
    FilteredDefaults ++ Headers.

%% @private
-spec try_decode_json(binary()) -> map() | binary().
try_decode_json(Body) when is_binary(Body), byte_size(Body) > 0 ->
    try
        jsx:decode(Body, [return_maps])
    catch
        _:_ -> Body
    end;
try_decode_json(Body) ->
    Body.

%% @private
-spec ensure_credential_table() -> ok.
ensure_credential_table() ->
    case ets:info(?CREDENTIAL_TABLE) of
        undefined ->
            ets:new(?CREDENTIAL_TABLE, [named_table, public, set]),
            ok;
        _ ->
            ok
    end.

%% @private
-spec provider_env_var(atom()) -> string().
provider_env_var(anthropic) -> "ANTHROPIC_API_KEY";
provider_env_var(openai)    -> "OPENAI_API_KEY";
provider_env_var(Provider)  ->
    string:uppercase(atom_to_list(Provider)) ++ "_API_KEY".

%% @private
-spec ensure_binary(binary() | string()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_list(V) -> list_to_binary(V).
