%%% @doc HTTP Client
%%% Enhanced HTTP client with connection pooling and caching

-module(http_client).
-behaviour(gen_server).

%% API
-export([start_link/1, stop/1]).
-export([get/2, post/2, put/2, delete/1, head/1]).
-export([ping/1, get_stats/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 30000).
-define(MAX_RETRIES, 3).
-define(CACHE_SIZE, 1000).
-define(CACHE_TTL, 300000). % 5 minutes

-record(request, {
    id :: binary(),
    method :: binary(),
    url :: binary(),
    headers :: map(),
    body :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    status :: integer() | undefined,
    retry_count :: integer()
}).

-record(state, {
    pool_name :: binary(),
    base_url :: binary(),
    headers :: map(),
    timeout :: integer(),
    cache :: map(), #{binary() => {term(), integer()}},
    stats :: map(),
    active_requests :: map()
}).

%%====================================================================
%% API
%%====================================================================

start_link(PoolName) ->
    gen_server:start_link({via, gproc, {pool_name, PoolName}}, ?MODULE, [PoolName], []).

stop(PoolName) ->
    gen_server:stop({via, gproc, {pool_name, PoolName}}).

%% @doc HTTP GET request
-spec get(binary(), map()) -> {ok, map()} | {error, term()}.
get(PoolName, Path) ->
    do_request(PoolName, <<"GET">>, Path, <<>>, #{}).

%% @doc HTTP POST request
-spec post(binary(), binary()) -> {ok, map()} | {error, term()}.
post(PoolName, Body) ->
    do_request(PoolName, <<"POST">>, <<>>, Body, #{}).

%% @doc HTTP PUT request
-spec put(binary(), binary()) -> {ok, map()} | {error, term()}.
put(PoolName, Body) ->
    do_request(PoolName, <<"PUT">>, <<>>, Body, #{}).

%% @doc HTTP DELETE request
-spec delete(binary()) -> {ok, map()} | {error, term()}.
delete(PoolName) ->
    do_request(PoolName, <<"DELETE">>, <<>>, <<>>, #{}).

%% @doc HTTP HEAD request
-spec head(binary()) -> {ok, map()} | {error, term()}.
head(PoolName) ->
    do_request(PoolName, <<"HEAD">>, <<>>, <<>>, #{}).

%% @doc Ping connection
-spec ping(binary()) -> ok | {error, term()}.
ping(PoolName) ->
    gen_server:call({via, gproc, {pool_name, PoolName}}, ping).

%% @doc Get connection statistics
-spec get_stats(binary()) -> map().
get_stats(PoolName) ->
    gen_server:call({via, gproc, {pool_name, PoolName}}, get_stats).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([PoolName]) ->
    State = #state{
        pool_name = PoolName,
        base_url = get_base_url(PoolName),
        headers = get_default_headers(PoolName),
        timeout = ?DEFAULT_TIMEOUT,
        cache = #{},
        stats = #{
            requests => 0,
            successes => 0,
            failures => 0,
            total_time => 0,
            cache_hits => 0,
            cache_misses => 0
        },
        active_requests = #{}
    },

    %% Start cache cleanup timer
    CleanupTimer = erlang:send_after(60000, self(), cleanup_cache),

    io:format("HTTP Client started for pool ~s~n", [PoolName]),
    {ok, State#state{stats = State#state.stats#{cleanup_timer => CleanupTimer}}}.

handle_call(ping, _From, State) ->
    {reply, ok, State};

handle_call(get_stats, _From, State) ->
    Stats = State#state.stats#{
        cache_size => maps:size(State#state.cache),
        active_requests => maps:size(State#state.active_requests)
    },
    {reply, Stats, State};

handle_call({request, RequestId, Method, Path, Body, Options}, _From, State) ->
    StartTime = os:system_time(millisecond),
    URL = build_url(State#state.base_url, Path),
    Headers = get_request_headers(State#state.headers, Options),

    Req = #request{
        id = RequestId,
        method = Method,
        url = URL,
        headers = Headers,
        body = Body,
        start_time = StartTime,
        retry_count = 0
    },

    %% Add to active requests
    ActiveRequests = maps:put(RequestId, Req, State#state.active_requests),
    UpdatedStats = State#state.stats#{
        requests => State#state.stats.requests + 1,
        active_requests => maps:size(ActiveRequests)
    },

    %% Check cache for GET requests
    case Method of
        <<"GET">> ->
            case get_from_cache(State#state.cache, URL, Body) of
                {ok, CachedData} ->
                    %% Update stats
                    UpdatedStats1 = UpdatedStats#{
                        successes => UpdatedStats.successes + 1,
                        cache_hits => UpdatedStats.cache_hits + 1
                    },

                    %% Remove from active requests
                    FinalActiveRequests = maps:remove(RequestId, ActiveRequests),

                    Response = make_response(CachedData, 200),
                    {reply, Response, State#state{stats = UpdatedStats1, active_requests = FinalActiveRequests}};
                {error, not_found} ->
                    %% Make actual request
                    Response = make_http_request(Method, URL, Headers, Body, State),
                    handle_response(Response, RequestId, State, UpdatedStats)
            end;
        _ ->
            %% For non-GET requests, make actual request
            Response = make_http_request(Method, URL, Headers, Body, State),
            handle_response(Response, RequestId, State, UpdatedStats)
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({response, RequestId, Response}, State) ->
    case maps:get(RequestId, State#state.active_requests, undefined) of
        undefined ->
            {noreply, State};
        Req ->
            %% Remove from active requests
            ActiveRequests = maps:remove(RequestId, State#state.active_requests),

            %% Update request record
            UpdatedReq = Req#request{
                end_time = os:system_time(millisecond),
                status = maps:get(status, Response, undefined)
            },

            %% Update stats
            Duration = UpdatedReq#request.end_time - UpdatedReq#request.start_time,
            UpdatedStats = State#state.stats#{
                total_time => State#state.stats.total_time + Duration,
                active_requests => maps:size(ActiveRequests)
            },

            %% Cache GET responses
            case UpdatedReq#request.method of
                <<"GET">> ->
                    put_to_cache(State#state.cache, UpdatedReq#request.url, Response);
                _ ->
                    ok
            end,

            io:format("Request ~s completed in ~p ms~n", [RequestId, Duration]),

            {noreply, State#state{active_requests = ActiveRequests, stats = UpdatedStats}}
    end;

handle_info(cleanup_cache, State) ->
    Now = os:system_time(millisecond),
    Ttl = ?CACHE_TTL,

    {UpdatedCache, Removed} = cleanup_expired_cache(State#state.cache, Now, Ttl),

    case Removed > 0 of
        true ->
            io:format("Cache cleanup removed ~p expired entries~n", [Removed]),
            %% Restart cleanup timer
            CleanupTimer = erlang:send_after(60000, self(), cleanup_cache),
            {noreply, State#state{cache = UpdatedCache, stats = State#state.stats#{cleanup_timer => CleanupTimer}}};
        false ->
            %% Restart cleanup timer
            CleanupTimer = erlang:send_after(60000, self(), cleanup_cache),
            {noreply, State#state{stats = State#state.stats#{cleanup_timer => CleanupTimer}}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

do_request(PoolName, Method, Path, Body, Options) ->
    RequestId = generate_request_id(),

    case gen_server:call({via, gproc, {pool_name, PoolName}},
                        {request, RequestId, Method, Path, Body, Options},
                        ?DEFAULT_TIMEOUT) of
        {ok, Response} ->
            Response;
        {error, Reason} ->
            {error, Reason}
    end.

handle_response(Response, RequestId, State, Stats) ->
    case Response of
        {ok, ResponseData} ->
            %% Success
            UpdatedStats = Stats#{
                successes => Stats.successes + 1,
                cache_misses => Stats.cache_misses + 1
            };

        {error, Reason} ->
            %% Check if we should retry
            case should_retry(Reason, State) of
                true ->
                    retry_request(RequestId, State, Stats);
                false ->
                    UpdatedStats = Stats#{
                        failures => Stats.failures + 1,
                        cache_misses => Stats.cache_misses + 1
                    }
            end
    end,

    %% Send response to client
    self() ! {response, RequestId, Response},

    {noreply, State#state{stats = UpdatedStats}}.

make_http_request(Method, URL, Headers, Body, State) ->
    %% Build HTTP request
    RequestOptions = [
        {timeout, State#state.timeout},
        {ssl_options, get_ssl_options()},
        {autoredirect, true},
        {proxy_options, get_proxy_options()}
    ],

    case do_http_request(Method, URL, Headers, Body, RequestOptions) of
        {ok, Response} ->
            {ok, Response};
        {error, Reason} ->
            case Reason of
                timeout ->
                    {error, timeout};
                connection_refused ->
                    {error, connection_refused};
                {status, Status} when Status >= 500 ->
                    {error, server_error};
                {status, Status} when Status >= 400 ->
                    {error, client_error};
                _ ->
                    {error, Reason}
            end
    end.

do_http_request(Method, URL, Headers, Body, Options) ->
    %% Mock implementation for testing
    %% In production, would use hackney or ibrowse
    timer:sleep(10), % Simulate network delay

    {ok, #{
        status => 200,
        headers => #{
            <<"content-type">> => <<"application/json">>,
            <<"server">> => <<"craftplan-erl-client">>
        },
        body => jiffy:encode(#{<<"data">> => <<"success">>, <<"timestamp">> => os:system_time(millisecond)})
    }}.

retry_request(RequestId, State, Stats) ->
    case maps:get(RequestId, State#state.active_requests, undefined) of
        undefined ->
            ok;
        Req ->
            case Req#request.retry_count < ?MAX_RETRIES of
                true ->
                    NewRetryCount = Req#request.retry_count + 1,
                    UpdatedReq = Req#request{retry_count = NewRetryCount},
                    ActiveRequests = maps:put(RequestId, UpdatedReq, State#state.active_requests),

                    io:format("Retrying request ~s (~p/~p)~n", [RequestId, NewRetryCount, ?MAX_RETRIES]),

                    %% Retry the request
                    Response = make_http_request(UpdatedReq#request.method, UpdatedReq#request.url,
                                               UpdatedReq#request.headers, UpdatedReq#request.body, State),

                    handle_response(Response, RequestId, State#state{active_requests = ActiveRequests}, Stats);
                false ->
                    ok
            end
    end.

should_retry(Error, State) ->
    case Error of
        timeout -> true;
        connection_refused -> true;
        {status, 429} -> true; % Rate limiting
        {status, 502} -> true; % Bad gateway
        {status, 503} -> true; % Service unavailable
        {status, 504} -> true; % Gateway timeout
        _ -> false
    end.

get_from_cache(Cache, URL, Body) ->
    case maps:get(URL, Cache, undefined) of
        {Data, Timestamp} ->
            Age = os:system_time(millisecond) - Timestamp,
            if
                Age < ?CACHE_TTL ->
                    {ok, Data};
                true ->
                    {error, expired}
            end;
        undefined ->
            {error, not_found}
    end.

put_to_cache(Cache, URL, Response) ->
    %% Only cache successful responses
    case Response of
        {ok, ResponseData} ->
            CacheEntry = {ResponseData, os:system_time(millisecond)},
            maps:put(URL, CacheEntry, Cache);
        _ ->
            Cache
    end.

cleanup_expired_cache(Cache, Now, Ttl) ->
    cleanup_expired_cache(maps:to_list(Cache), Now, Ttl, #{}).

cleanup_expired_cache([], _Now, _Ttl, NewCache) ->
    {NewCache, 0};

cleanup_expired_cache([{URL, {_, Timestamp}} | Rest], Now, Ttl, NewCache) ->
    Age = Now - Timestamp,
    case Age < Ttl of
        true ->
            cleanup_expired_cache(Rest, Now, Ttl, maps:put(URL, {_, Timestamp}, NewCache));
        false ->
            {UpdatedCache, Removed} = cleanup_expired_cache(Rest, Now, Ttl, NewCache),
            {UpdatedCache, Removed + 1}
    end.

build_url(BaseUrl, Path) ->
    case Path of
        <<>> -> BaseUrl;
        _ when is_binary(Path) ->
            case binary:at(Path, 0) of
                $/ -> <<BaseUrl/binary, Path/binary>>;
                _ -> <<BaseUrl/binary, $/, Path/binary>>
            end
    end.

get_base_url(PoolName) ->
    case PoolName of
        <<"craftplan-api">> -> <<"http://localhost:4000/api">>;
        _ -> <<"http://localhost:8080">>
    end.

get_default_headers(PoolName) ->
    DefaultHeaders = #{
        <<"content-type">> => <<"application/json">>,
        <<"user-agent">> => <<"craftplan-erl-client/1.0.0">>,
        <<"accept">> => <<"application/json">>
    },

    case PoolName of
        <<"craftplan-api">> ->
            case application:get_env(craftplan_mcp, api_token) of
                {ok, Token} -> DefaultHeaders#{<<"authorization">> => <<"Bearer ", Token/binary>>};
                undefined -> DefaultHeaders
            end;
        _ -> DefaultHeaders
    end.

get_request_headers(Headers, Options) ->
    case maps:get(headers, Options, undefined) of
        undefined -> Headers;
        CustomHeaders ->
            lists:foldl(fun({K, V}, Acc) -> maps:put(K, V, Acc) end, Headers, CustomHeaders)
    end.

get_ssl_options() ->
    #{
        verify => verify_none,
        server_name_indication => disable,
        secure_renegotiate => false,
        partial_chain => false
    }.

get_proxy_options() ->
    #{}.

make_response(ResponseData, Status) ->
    #{
        status => Status,
        headers => #{<<"content-type">> => <<"application/json">>},
        body => ResponseData
    }.

generate_request_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("req_~p_~p", [Timestamp, Random])).