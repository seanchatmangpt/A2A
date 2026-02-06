%%%-------------------------------------------------------------------
%%% @doc BeamAI HTTP client wrapper around hackney.
%%% Provides a simplified interface for making HTTP requests,
%%% with JSON encoding/decoding built in.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_http_client).

-export([
    get/1,
    get/2,
    post/3,
    post_json/3,
    put_json/3,
    delete/1,
    delete/2,
    request/4,
    request/5
]).

-type url() :: binary() | string().
-type headers() :: [{binary(), binary()}].
-type response() :: {ok, integer(), headers(), map() | binary()} | {error, term()}.

-export_type([url/0, headers/0, response/0]).

-define(DEFAULT_TIMEOUT, 30000).
-define(DEFAULT_HEADERS, [
    {<<"Content-Type">>, <<"application/json">>},
    {<<"Accept">>, <<"application/json">>}
]).

%%--------------------------------------------------------------------
%% @doc Perform a GET request.
%% @end
%%--------------------------------------------------------------------
-spec get(url()) -> response().
get(Url) ->
    get(Url, []).

%%--------------------------------------------------------------------
%% @doc Perform a GET request with custom headers.
%% @end
%%--------------------------------------------------------------------
-spec get(url(), headers()) -> response().
get(Url, ExtraHeaders) ->
    request(get, Url, merge_headers(ExtraHeaders), <<>>).

%%--------------------------------------------------------------------
%% @doc Perform a POST request with a raw body.
%% @end
%%--------------------------------------------------------------------
-spec post(url(), headers(), binary()) -> response().
post(Url, ExtraHeaders, Body) ->
    request(post, Url, merge_headers(ExtraHeaders), Body).

%%--------------------------------------------------------------------
%% @doc Perform a POST request with a JSON-encoded body.
%% @end
%%--------------------------------------------------------------------
-spec post_json(url(), map() | list(), headers()) -> response().
post_json(Url, JsonBody, ExtraHeaders) ->
    EncodedBody = jsx:encode(JsonBody),
    request(post, Url, merge_headers(ExtraHeaders), EncodedBody).

%%--------------------------------------------------------------------
%% @doc Perform a PUT request with a JSON-encoded body.
%% @end
%%--------------------------------------------------------------------
-spec put_json(url(), map() | list(), headers()) -> response().
put_json(Url, JsonBody, ExtraHeaders) ->
    EncodedBody = jsx:encode(JsonBody),
    request(put, Url, merge_headers(ExtraHeaders), EncodedBody).

%%--------------------------------------------------------------------
%% @doc Perform a DELETE request.
%% @end
%%--------------------------------------------------------------------
-spec delete(url()) -> response().
delete(Url) ->
    delete(Url, []).

%%--------------------------------------------------------------------
%% @doc Perform a DELETE request with custom headers.
%% @end
%%--------------------------------------------------------------------
-spec delete(url(), headers()) -> response().
delete(Url, ExtraHeaders) ->
    request(delete, Url, merge_headers(ExtraHeaders), <<>>).

%%--------------------------------------------------------------------
%% @doc Perform an HTTP request using hackney.
%% @end
%%--------------------------------------------------------------------
-spec request(atom(), url(), headers(), binary()) -> response().
request(Method, Url, Headers, Body) ->
    request(Method, Url, Headers, Body, []).

%%--------------------------------------------------------------------
%% @doc Perform an HTTP request with custom hackney options.
%% @end
%%--------------------------------------------------------------------
-spec request(atom(), url(), headers(), binary(), list()) -> response().
request(Method, Url, Headers, Body, ExtraOpts) ->
    UrlBin = ensure_binary(Url),
    Opts = [{recv_timeout, ?DEFAULT_TIMEOUT}, with_body | ExtraOpts],
    case hackney:request(Method, UrlBin, Headers, Body, Opts) of
        {ok, StatusCode, RespHeaders, RespBody} ->
            DecodedBody = try_decode_json(RespBody),
            {ok, StatusCode, RespHeaders, DecodedBody};
        {ok, StatusCode, RespHeaders} ->
            {ok, StatusCode, RespHeaders, #{}};
        {error, Reason} ->
            logger:error("HTTP request failed: ~p ~s - ~p", [Method, UrlBin, Reason]),
            {error, Reason}
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
-spec merge_headers(headers()) -> headers().
merge_headers(ExtraHeaders) ->
    %% Extra headers override defaults with the same key
    ExtraKeys = [K || {K, _} <- ExtraHeaders],
    FilteredDefaults = [{K, V} || {K, V} <- ?DEFAULT_HEADERS,
                        not lists:member(K, ExtraKeys)],
    FilteredDefaults ++ ExtraHeaders.

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
-spec ensure_binary(binary() | string()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_list(V) -> list_to_binary(V).
