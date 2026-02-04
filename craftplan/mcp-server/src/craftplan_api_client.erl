%%% @doc Craftplan API Client
%%% Handles communication with the Craftplan Phoenix backend

-module(craftplan_api_client).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([request/3, request/4]).
-export([get/2, post/2, put/2, delete/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 30000).
-define(BASE_URL, application:get_env(craftplan_mcp, api_url, "http://localhost:4000/api")).

-record(state, {
    base_url :: binary(),
    api_token :: binary() | undefined,
    pool :: pid(),
    metrics :: map()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Make a generic API request
-spec request(binary(), binary(), map()) -> {ok, map()} | {error, term()}.
request(Resource, Operation, Params) ->
    request(Resource, Operation, Params, ?DEFAULT_TIMEOUT).

-spec request(binary(), binary(), map(), timeout()) -> {ok, map()} | {error, term()}.
request(Resource, Operation, Params, Timeout) ->
    gen_server:call(?SERVER, {request, Resource, Operation, Params}, Timeout).

%% @doc GET request
-spec get(binary(), map()) -> {ok, map()} | {error, term()}.
get(Path, QueryParams) ->
    gen_server:call(?SERVER, {get, Path, QueryParams}).

%% @doc POST request
-spec post(binary(), map()) -> {ok, map()} | {error, term()}.
post(Path, Body) ->
    gen_server:call(?SERVER, {post, Path, Body}).

%% @doc PUT request
-spec put(binary(), map()) -> {ok, map()} | {error, term()}.
put(Path, Body) ->
    gen_server:call(?SERVER, {put, Path, Body}).

%% @doc DELETE request
-spec delete(binary()) -> {ok, map()} | {error, term()}.
delete(Path) ->
    gen_server:call(?SERVER, {delete, Path}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    BaseUrl = ?BASE_URL,
    {ok, Pool} = start_http_pool(),

    State = #state{
        base_url = BaseUrl,
        api_token = get_api_token(),
        pool = Pool,
        metrics = #{}
    },

    {ok, State}.

handle_call({request, Resource, Operation, Params}, _From, State) ->
    URL = build_url(Resource, Params, State),
    Method = http_method(Operation),
    Headers = build_headers(State),
    Body = build_body(Operation, Params),

    case do_request(Method, URL, Headers, Body, State) of
        {ok, Response} ->
            {reply, {ok, Response}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get, Path, QueryParams}, _From, State) ->
    URL = build_full_url(Path, QueryParams, State),
    Headers = build_headers(State),

    case do_request(get, URL, Headers, <<>>, State) of
        {ok, Response} ->
            {reply, {ok, Response}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({post, Path, Body}, _From, State) ->
    URL = build_full_url(Path, #{}, State),
    Headers = build_headers(State),

    case do_request(post, URL, Headers, Body, State) of
        {ok, Response} ->
            {reply, {ok, Response}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({put, Path, Body}, _From, State) ->
    URL = build_full_url(Path, #{}, State),
    Headers = build_headers(State),

    case do_request(put, URL, Headers, Body, State) of
        {ok, Response} ->
            {reply, {ok, Response}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({delete, Path}, _From, State) ->
    URL = build_full_url(Path, #{}, State),
    Headers = build_headers(State),

    case do_request(delete, URL, Headers, <<>>, State) of
        {ok, Response} ->
            {reply, {ok, Response}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

start_http_pool() ->
    % Simple implementation - in production use hackney or similar
    {ok, self()}.

get_api_token() ->
    case application:get_env(craftplan_mcp, api_token) of
        {ok, Token} -> Token;
        undefined -> undefined
    end.

build_url(_Resource, _Params, _State) ->
    <<"/api/test">>.

build_full_url(Path, QueryParams, _State) ->
    case map_size(QueryParams) of
        0 -> Path;
        _ -> Path
    end.

join_binary([], _Separator) ->
    <<>>;
join_binary([H], _Separator) ->
    H;
join_binary([H|T], Separator) ->
    <<H/binary, Separator/binary, (join_binary(T, Separator))/binary>>.

http_method(<<"list">>) -> get;
http_method(<<"get">>) -> get;
http_method(<<"create">>) -> post;
http_method(<<"update">>) -> put;
http_method(<<"delete">>) -> delete;
http_method(_) -> get.

build_headers(_State) ->
    #{<<"content-type">> => <<"application/json">>}.

build_body(Operation, Params) ->
    case Operation of
        <<"list">> -> <<>>;
        <<"get">> -> <<>>;
        _ -> jiffy:encode(Params)
    end.

do_request(Method, URL, Headers, Body, State) ->
    % Mock implementation for testing
    case Method of
        get ->
            {ok, #{
                <<"data">> => [],
                <<"meta">> => #{}
            }};
        post ->
            {ok, #{
                <<"data">> => #{<<"id">> => <<"new_id">>},
                <<"meta">> => #{}
            }};
        put ->
            {ok, #{
                <<"data">> => #{<<"id">> => <<"updated_id">>},
                <<"meta">> => #{}
            }};
        delete ->
            {ok, #{
                <<"data">> => #{},
                <<"meta">> => #{}
            }}
    end.