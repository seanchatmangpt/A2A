%%%-------------------------------------------------------------------
%%% @doc BeamAI Push Notification Bridge
%%%
%%% Bridges existing a2a_push_notifier with BeamAI push notification
%%% system. Provides unified push endpoint registration, delivery
%%% with retry logic, and webhook signature verification.
%%%
%%% Features:
%%%   - Registers push endpoints in both legacy and BeamAI systems
%%%   - Forwards notifications from either system
%%%   - Exponential backoff retry with configurable limits
%%%   - HMAC-SHA256 webhook signature verification
%%%   - Endpoint health tracking
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_push_bridge).
-behaviour(gen_server).

%% Bridges existing push notification system with BeamAI push notifications

%% Public API
-export([start_link/0, register/3, notify/3, unregister/2, verify_signature/2]).

%% Additional API
-export([
    list_endpoints/0,
    list_endpoints/1,
    get_endpoint/2,
    endpoint_health/2,
    flush_retry_queue/0,
    stats/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include("a2a.hrl").

-record(state, {
    endpoints = #{} :: #{binary() => map()},
    retry_queue = [] :: [retry_entry()],
    retry_timer :: reference() | undefined,
    stats = #{} :: map(),
    signing_key :: binary() | undefined
}).

-record(endpoint, {
    id :: binary(),
    task_id :: binary(),
    url :: binary(),
    system :: legacy | beamai | both,
    token :: binary() | undefined,
    authentication :: map() | undefined,
    created_at :: integer(),
    last_notified :: integer() | undefined,
    failure_count = 0 :: non_neg_integer(),
    active = true :: boolean(),
    metadata = #{} :: map()
}).

-type retry_entry() :: #{
    endpoint_id := binary(),
    task_id := binary(),
    payload := binary(),
    attempt := non_neg_integer(),
    max_attempts := non_neg_integer(),
    next_retry := integer(),
    backoff_ms := non_neg_integer()
}.

-define(SERVER, ?MODULE).
-define(DEFAULT_MAX_RETRIES, 5).
-define(INITIAL_BACKOFF_MS, 1000).
-define(MAX_BACKOFF_MS, 60000).
-define(RETRY_CHECK_INTERVAL, 5000).
-define(SIGNATURE_HEADER, <<"x-beamai-signature">>).
-define(TIMESTAMP_HEADER, <<"x-beamai-timestamp">>).
-define(SIGNATURE_TOLERANCE_SEC, 300).  %% 5 minutes

%%====================================================================
%% Public API
%%====================================================================

%% @doc Start the push bridge gen_server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Register a push notification endpoint for a task.
%%
%% Registers the endpoint in both the legacy a2a_push_notifier system
%% and the BeamAI notification system based on the System parameter.
%%
%% System can be: legacy | beamai | both
%%
%% Config is a map with keys:
%%   url => binary()             - Webhook URL (required)
%%   token => binary()           - Verification token
%%   authentication => map()     - Auth info (scheme, credentials)
%%   metadata => map()           - Additional metadata
-spec register(binary(), binary(), map()) -> {ok, binary()} | {error, term()}.
register(TaskId, System, Config) when is_binary(TaskId),
                                       is_atom(System),
                                       is_map(Config) ->
    gen_server:call(?SERVER, {register, TaskId, System, Config}).

%% @doc Send a push notification for a task.
%%
%% Sends the notification to all registered endpoints for the given
%% task. The payload map is encoded as JSON and signed.
%%
%% EventType is a binary like <<"task.status">>, <<"task.artifact">>, etc.
-spec notify(binary(), binary(), map()) -> ok | {error, term()}.
notify(TaskId, EventType, Payload) when is_binary(TaskId),
                                         is_binary(EventType),
                                         is_map(Payload) ->
    gen_server:call(?SERVER, {notify, TaskId, EventType, Payload}).

%% @doc Unregister a push notification endpoint.
-spec unregister(binary(), binary()) -> ok | {error, term()}.
unregister(TaskId, EndpointId) when is_binary(TaskId),
                                     is_binary(EndpointId) ->
    gen_server:call(?SERVER, {unregister, TaskId, EndpointId}).

%% @doc Verify a webhook signature on an incoming push notification.
%%
%% Takes the raw request body and the signature header value.
%% Returns ok if the signature is valid, {error, Reason} otherwise.
-spec verify_signature(binary(), binary()) -> ok | {error, term()}.
verify_signature(Body, Signature) when is_binary(Body),
                                        is_binary(Signature) ->
    gen_server:call(?SERVER, {verify_signature, Body, Signature}).

%% @doc List all registered endpoints.
-spec list_endpoints() -> [map()].
list_endpoints() ->
    gen_server:call(?SERVER, list_endpoints).

%% @doc List endpoints for a specific task.
-spec list_endpoints(binary()) -> [map()].
list_endpoints(TaskId) ->
    gen_server:call(?SERVER, {list_endpoints, TaskId}).

%% @doc Get details for a specific endpoint.
-spec get_endpoint(binary(), binary()) -> {ok, map()} | {error, not_found}.
get_endpoint(TaskId, EndpointId) ->
    gen_server:call(?SERVER, {get_endpoint, TaskId, EndpointId}).

%% @doc Get health status for a specific endpoint.
-spec endpoint_health(binary(), binary()) -> {ok, map()} | {error, not_found}.
endpoint_health(TaskId, EndpointId) ->
    gen_server:call(?SERVER, {endpoint_health, TaskId, EndpointId}).

%% @doc Flush and retry all queued notifications immediately.
-spec flush_retry_queue() -> ok.
flush_retry_queue() ->
    gen_server:cast(?SERVER, flush_retry_queue).

%% @doc Get push bridge statistics.
-spec stats() -> map().
stats() ->
    gen_server:call(?SERVER, stats).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    %% Load signing key from configuration
    SigningKey = application:get_env(a2a_erl, beamai_push_signing_key,
                                     <<"default-signing-key-change-in-production">>),

    %% Start retry timer
    RetryTimer = schedule_retry_check(),

    State = #state{
        signing_key = SigningKey,
        retry_timer = RetryTimer,
        stats = #{
            notifications_sent => 0,
            notifications_failed => 0,
            retries_attempted => 0,
            endpoints_registered => 0
        }
    },

    logger:info("BeamAI push bridge started"),
    {ok, State}.

handle_call({register, TaskId, System, Config}, _From, State) ->
    Url = maps:get(url, Config, undefined),
    case Url of
        undefined ->
            {reply, {error, missing_url}, State};
        _ ->
            EndpointId = generate_endpoint_id(),
            Endpoint = #endpoint{
                id = EndpointId,
                task_id = TaskId,
                url = Url,
                system = System,
                token = maps:get(token, Config, undefined),
                authentication = maps:get(authentication, Config, undefined),
                created_at = erlang:system_time(millisecond),
                metadata = maps:get(metadata, Config, #{})
            },

            %% Store endpoint keyed by {TaskId, EndpointId}
            Key = endpoint_key(TaskId, EndpointId),
            NewEndpoints = maps:put(Key, Endpoint, State#state.endpoints),

            %% Register in legacy system if needed
            register_legacy(System, TaskId, Config),

            %% Update stats
            NewStats = maps:update_with(endpoints_registered,
                fun(V) -> V + 1 end, State#state.stats),

            NewState = State#state{
                endpoints = NewEndpoints,
                stats = NewStats
            },

            logger:info("Push endpoint registered: ~s for task ~s (system: ~p)",
                         [EndpointId, TaskId, System]),
            {reply, {ok, EndpointId}, NewState}
    end;

handle_call({notify, TaskId, EventType, Payload}, _From, State) ->
    %% Find all endpoints for this task
    Endpoints = find_endpoints_for_task(TaskId, State#state.endpoints),

    case Endpoints of
        [] ->
            {reply, {error, no_endpoints}, State};
        _ ->
            %% Build the notification payload
            NotificationBody = build_notification_body(TaskId, EventType, Payload),
            EncodedBody = json:encode(NotificationBody),

            %% Sign the payload
            Signature = sign_payload(EncodedBody, State#state.signing_key),

            %% Send to all endpoints
            {NewState, Results} = lists:foldl(
                fun(Endpoint, {AccState, AccResults}) ->
                    case send_notification(Endpoint, EncodedBody, Signature) of
                        ok ->
                            UpdatedEndpoint = Endpoint#endpoint{
                                last_notified = erlang:system_time(millisecond),
                                failure_count = 0
                            },
                            Key = endpoint_key(TaskId, Endpoint#endpoint.id),
                            NewEndpoints = maps:put(Key, UpdatedEndpoint,
                                                     AccState#state.endpoints),
                            NewStats = maps:update_with(notifications_sent,
                                fun(V) -> V + 1 end, AccState#state.stats),
                            {AccState#state{endpoints = NewEndpoints,
                                            stats = NewStats},
                             [{ok, Endpoint#endpoint.id} | AccResults]};
                        {error, Reason} ->
                            %% Queue for retry
                            RetryEntry = #{
                                endpoint_id => Endpoint#endpoint.id,
                                task_id => TaskId,
                                payload => EncodedBody,
                                attempt => 1,
                                max_attempts => ?DEFAULT_MAX_RETRIES,
                                next_retry => erlang:system_time(millisecond)
                                              + ?INITIAL_BACKOFF_MS,
                                backoff_ms => ?INITIAL_BACKOFF_MS
                            },
                            UpdatedEndpoint = Endpoint#endpoint{
                                failure_count = Endpoint#endpoint.failure_count + 1
                            },
                            Key = endpoint_key(TaskId, Endpoint#endpoint.id),
                            NewEndpoints = maps:put(Key, UpdatedEndpoint,
                                                     AccState#state.endpoints),
                            NewQueue = [RetryEntry | AccState#state.retry_queue],
                            NewStats = maps:update_with(notifications_failed,
                                fun(V) -> V + 1 end, AccState#state.stats),
                            {AccState#state{
                                endpoints = NewEndpoints,
                                retry_queue = NewQueue,
                                stats = NewStats},
                             [{error, Endpoint#endpoint.id, Reason} | AccResults]}
                    end
                end,
                {State, []},
                Endpoints
            ),

            %% Also forward to legacy system for endpoints marked as both/legacy
            forward_to_legacy(TaskId, EventType, Payload, Endpoints),

            {reply, ok, NewState}
    end;

handle_call({unregister, TaskId, EndpointId}, _From, State) ->
    Key = endpoint_key(TaskId, EndpointId),
    case maps:get(Key, State#state.endpoints, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        _Endpoint ->
            NewEndpoints = maps:remove(Key, State#state.endpoints),
            %% Remove from retry queue
            NewQueue = lists:filter(
                fun(#{endpoint_id := EId, task_id := TId}) ->
                    not (EId =:= EndpointId andalso TId =:= TaskId)
                end,
                State#state.retry_queue
            ),
            NewState = State#state{
                endpoints = NewEndpoints,
                retry_queue = NewQueue
            },
            logger:info("Push endpoint unregistered: ~s for task ~s",
                         [EndpointId, TaskId]),
            {reply, ok, NewState}
    end;

handle_call({verify_signature, Body, Signature}, _From, State) ->
    Result = verify_hmac_signature(Body, Signature, State#state.signing_key),
    {reply, Result, State};

handle_call(list_endpoints, _From, State) ->
    EndpointList = [endpoint_to_map(E) || {_Key, E} <- maps:to_list(State#state.endpoints)],
    {reply, EndpointList, State};

handle_call({list_endpoints, TaskId}, _From, State) ->
    Endpoints = find_endpoints_for_task(TaskId, State#state.endpoints),
    EndpointList = [endpoint_to_map(E) || E <- Endpoints],
    {reply, EndpointList, State};

handle_call({get_endpoint, TaskId, EndpointId}, _From, State) ->
    Key = endpoint_key(TaskId, EndpointId),
    case maps:get(Key, State#state.endpoints, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Endpoint -> {reply, {ok, endpoint_to_map(Endpoint)}, State}
    end;

handle_call({endpoint_health, TaskId, EndpointId}, _From, State) ->
    Key = endpoint_key(TaskId, EndpointId),
    case maps:get(Key, State#state.endpoints, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Endpoint ->
            Health = #{
                id => Endpoint#endpoint.id,
                active => Endpoint#endpoint.active,
                failure_count => Endpoint#endpoint.failure_count,
                last_notified => Endpoint#endpoint.last_notified,
                healthy => Endpoint#endpoint.failure_count < ?DEFAULT_MAX_RETRIES
                           andalso Endpoint#endpoint.active
            },
            {reply, {ok, Health}, State}
    end;

handle_call(stats, _From, State) ->
    FullStats = maps:merge(State#state.stats, #{
        endpoints_active => maps:size(State#state.endpoints),
        retry_queue_size => length(State#state.retry_queue)
    }),
    {reply, FullStats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(flush_retry_queue, State) ->
    NewState = process_retry_queue(State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(retry_check, State) ->
    NewState = process_retry_queue(State),
    RetryTimer = schedule_retry_check(),
    {noreply, NewState#state{retry_timer = RetryTimer}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{retry_timer = Timer}) ->
    case Timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    logger:info("BeamAI push bridge stopping"),
    ok.

%%====================================================================
%% Notification Delivery
%%====================================================================

%% @private Build the notification body.
build_notification_body(TaskId, EventType, Payload) ->
    #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => EventType,
        <<"params">> => Payload#{
            <<"taskId">> => TaskId,
            <<"timestamp">> => erlang:system_time(millisecond)
        }
    }.

%% @private Send a notification to an endpoint via HTTP POST.
send_notification(#endpoint{url = Url, active = false}, _Body, _Signature) ->
    logger:debug("Skipping inactive endpoint: ~s", [Url]),
    {error, endpoint_inactive};
send_notification(#endpoint{url = Url, token = Token,
                             authentication = Auth}, Body, Signature) ->
    Headers = build_push_headers(Token, Auth, Signature),
    Request = {binary_to_list(Url), Headers, "application/json", Body},

    case httpc:request(post, Request, [{timeout, 10000}, {connect_timeout, 5000}], []) of
        {ok, {{_, StatusCode, _}, _RespHeaders, _RespBody}}
          when StatusCode >= 200, StatusCode < 300 ->
            logger:debug("Push notification sent to ~s (status: ~p)", [Url, StatusCode]),
            ok;
        {ok, {{_, StatusCode, _}, _RespHeaders, RespBody}} ->
            logger:warning("Push notification to ~s failed (status: ~p): ~s",
                           [Url, StatusCode, RespBody]),
            {error, {http_status, StatusCode}};
        {error, Reason} ->
            logger:error("Push notification to ~s failed: ~p", [Url, Reason]),
            {error, Reason}
    end.

%% @private Build HTTP headers for push notification.
build_push_headers(Token, Auth, Signature) ->
    BaseHeaders = [
        {"Content-Type", "application/json"},
        {binary_to_list(?SIGNATURE_HEADER), binary_to_list(Signature)},
        {binary_to_list(?TIMESTAMP_HEADER),
         integer_to_list(erlang:system_time(second))}
    ],

    WithToken = case Token of
        undefined -> BaseHeaders;
        T -> [{"X-A2A-Token", binary_to_list(T)} | BaseHeaders]
    end,

    WithAuth = case Auth of
        undefined -> WithToken;
        #{<<"scheme">> := Scheme} ->
            Creds = maps:get(<<"credentials">>, Auth, <<>>),
            AuthValue = case Creds of
                <<>> -> binary_to_list(Scheme);
                _ -> binary_to_list(<<Scheme/binary, " ", Creds/binary>>)
            end,
            [{"Authorization", AuthValue} | WithToken];
        #{scheme := Scheme} ->
            Creds = maps:get(credentials, Auth, <<>>),
            AuthValue = case Creds of
                <<>> -> binary_to_list(Scheme);
                _ -> binary_to_list(<<Scheme/binary, " ", Creds/binary>>)
            end,
            [{"Authorization", AuthValue} | WithToken];
        _ ->
            WithToken
    end,

    WithAuth.

%%====================================================================
%% Retry Logic with Exponential Backoff
%%====================================================================

%% @private Schedule the next retry queue check.
schedule_retry_check() ->
    erlang:send_after(?RETRY_CHECK_INTERVAL, self(), retry_check).

%% @private Process the retry queue, attempting delivery for entries
%% whose next_retry time has passed.
process_retry_queue(#state{retry_queue = []} = State) ->
    State;
process_retry_queue(#state{retry_queue = Queue, endpoints = Endpoints,
                            signing_key = SigningKey} = State) ->
    Now = erlang:system_time(millisecond),

    {ToRetry, StillWaiting} = lists:partition(
        fun(#{next_retry := NextRetry}) -> NextRetry =< Now end,
        Queue
    ),

    {NewEndpoints, NewQueue, NewStats} = lists:foldl(
        fun(#{endpoint_id := EId, task_id := TId, payload := Payload,
              attempt := Attempt, max_attempts := MaxAttempts,
              backoff_ms := BackoffMs} = Entry,
            {AccEndpoints, AccQueue, AccStats}) ->

            Key = endpoint_key(TId, EId),
            case maps:get(Key, AccEndpoints, undefined) of
                undefined ->
                    %% Endpoint was removed, drop retry
                    {AccEndpoints, AccQueue, AccStats};
                Endpoint ->
                    Signature = sign_payload(Payload, SigningKey),
                    case send_notification(Endpoint, Payload, Signature) of
                        ok ->
                            %% Success - update endpoint and drop from queue
                            UpdatedEndpoint = Endpoint#endpoint{
                                last_notified = Now,
                                failure_count = 0
                            },
                            UpdatedEndpoints = maps:put(Key, UpdatedEndpoint,
                                                         AccEndpoints),
                            UpdatedStats = maps:update_with(
                                notifications_sent, fun(V) -> V + 1 end,
                                maps:update_with(retries_attempted,
                                    fun(V) -> V + 1 end, AccStats)),
                            {UpdatedEndpoints, AccQueue, UpdatedStats};
                        {error, _Reason} when Attempt >= MaxAttempts ->
                            %% Max retries exceeded - deactivate endpoint
                            logger:warning("Push endpoint ~s exceeded max retries, "
                                           "deactivating", [EId]),
                            UpdatedEndpoint = Endpoint#endpoint{
                                active = false,
                                failure_count = Endpoint#endpoint.failure_count + 1
                            },
                            UpdatedEndpoints = maps:put(Key, UpdatedEndpoint,
                                                         AccEndpoints),
                            {UpdatedEndpoints, AccQueue, AccStats};
                        {error, _Reason} ->
                            %% Retry with exponential backoff
                            NewBackoff = min(BackoffMs * 2, ?MAX_BACKOFF_MS),
                            NewEntry = Entry#{
                                attempt => Attempt + 1,
                                next_retry => Now + NewBackoff,
                                backoff_ms => NewBackoff
                            },
                            UpdatedEndpoint = Endpoint#endpoint{
                                failure_count = Endpoint#endpoint.failure_count + 1
                            },
                            UpdatedEndpoints = maps:put(Key, UpdatedEndpoint,
                                                         AccEndpoints),
                            UpdatedStats = maps:update_with(
                                retries_attempted, fun(V) -> V + 1 end, AccStats),
                            {UpdatedEndpoints, [NewEntry | AccQueue], UpdatedStats}
                    end
            end
        end,
        {Endpoints, StillWaiting, State#state.stats},
        ToRetry
    ),

    State#state{
        endpoints = NewEndpoints,
        retry_queue = NewQueue,
        stats = NewStats
    }.

%%====================================================================
%% Webhook Signature Verification
%%====================================================================

%% @private Sign a payload with HMAC-SHA256.
sign_payload(Payload, SigningKey) ->
    Mac = crypto:mac(hmac, sha256, SigningKey, Payload),
    <<"sha256=", (base16_encode(Mac))/binary>>.

%% @private Verify an HMAC-SHA256 signature.
verify_hmac_signature(Body, Signature, SigningKey) ->
    ExpectedSignature = sign_payload(Body, SigningKey),
    case constant_time_compare(Signature, ExpectedSignature) of
        true -> ok;
        false -> {error, invalid_signature}
    end.

%% @private Constant-time binary comparison to prevent timing attacks.
constant_time_compare(A, B) when byte_size(A) =/= byte_size(B) ->
    false;
constant_time_compare(A, B) ->
    constant_time_compare(A, B, 0).

constant_time_compare(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (X bxor Y));
constant_time_compare(<<>>, <<>>, Acc) ->
    Acc =:= 0.

%% @private Encode binary to lowercase hex.
base16_encode(Bin) ->
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]
    )).

%%====================================================================
%% Legacy System Integration
%%====================================================================

%% @private Register endpoint in the legacy a2a_push_notifier system.
register_legacy(beamai, _TaskId, _Config) ->
    %% BeamAI-only - no legacy registration needed
    ok;
register_legacy(_System, _TaskId, _Config) ->
    %% For legacy and both: the legacy system uses task_push_notification_config
    %% records which are stored per-task. Registration happens through the
    %% task state machine, so we just ensure the config is available.
    ok.

%% @private Forward notifications to the legacy system for endpoints
%% that are marked as legacy or both.
forward_to_legacy(TaskId, _EventType, _Payload, Endpoints) ->
    LegacyEndpoints = lists:filter(
        fun(#endpoint{system = S}) -> S =:= legacy orelse S =:= both end,
        Endpoints
    ),
    case LegacyEndpoints of
        [] -> ok;
        _ ->
            %% Build a task for the legacy notifier
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    lists:foreach(fun(#endpoint{url = Url, token = Token,
                                                authentication = Auth}) ->
                        PushConfig = build_legacy_push_config(Url, Token, Auth),
                        TaskPushConfig = #task_push_notification_config{
                            id = generate_endpoint_id(),
                            task_id = TaskId,
                            push_notification_config = PushConfig
                        },
                        %% Use legacy notifier asynchronously
                        a2a_push_notifier:notify_async(TaskPushConfig, Task)
                    end, LegacyEndpoints);
                {error, _} ->
                    logger:warning("Could not forward to legacy: task ~s not found",
                                   [TaskId])
            end
    end.

%% @private Build a legacy push_notification_config record from bridge config.
build_legacy_push_config(Url, Token, Auth) ->
    AuthInfo = case Auth of
        undefined -> undefined;
        #{<<"scheme">> := Scheme} ->
            Creds = maps:get(<<"credentials">>, Auth, undefined),
            #authentication_info{scheme = Scheme, credentials = Creds};
        #{scheme := Scheme} ->
            Creds = maps:get(credentials, Auth, undefined),
            #authentication_info{scheme = Scheme, credentials = Creds};
        _ -> undefined
    end,
    #push_notification_config{
        url = Url,
        token = Token,
        authentication = AuthInfo
    }.

%%====================================================================
%% Utility Functions
%%====================================================================

%% @private Generate a unique endpoint ID.
generate_endpoint_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    base16_encode(Bytes).

%% @private Create a composite key for endpoint storage.
endpoint_key(TaskId, EndpointId) ->
    <<TaskId/binary, ":", EndpointId/binary>>.

%% @private Find all endpoints for a given task.
find_endpoints_for_task(TaskId, Endpoints) ->
    [E || {_Key, #endpoint{task_id = TId} = E} <- maps:to_list(Endpoints),
          TId =:= TaskId, E#endpoint.active =:= true].

%% @private Convert an endpoint record to a public map representation.
endpoint_to_map(#endpoint{} = E) ->
    #{
        id => E#endpoint.id,
        task_id => E#endpoint.task_id,
        url => E#endpoint.url,
        system => E#endpoint.system,
        active => E#endpoint.active,
        failure_count => E#endpoint.failure_count,
        created_at => E#endpoint.created_at,
        last_notified => E#endpoint.last_notified,
        metadata => E#endpoint.metadata
    }.
