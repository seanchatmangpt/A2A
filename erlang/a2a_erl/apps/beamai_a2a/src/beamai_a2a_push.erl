%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Push Notification Manager
%%%
%%% Manages push notification registrations for tasks and sends
%%% notifications on task state changes.  Integrates with the
%%% existing a2a_push_notifier module while providing additional
%%% features:
%%%
%%% - Registration/unregistration of push endpoints per task
%%% - Automatic retry with exponential backoff on failure
%%% - Persistent storage of push configs via a2a_task_store
%%% - Notification payload construction following the A2A spec
%%%
%%% This module is a gen_server that maintains an in-memory index
%%% of push configurations and handles retry scheduling.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_push).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    register/3,
    unregister/2,
    notify/3,
    get_config/1,
    list_configs/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(SERVER, ?MODULE).
-define(MAX_RETRIES, 5).
-define(BASE_BACKOFF_MS, 1000).

-record(state, {
    %% task_id => [push_config_entry()]
    configs = #{} :: #{binary() => [push_config_entry()]}
}).

-record(push_config_entry, {
    id         :: binary(),
    task_id    :: binary(),
    url        :: binary(),
    token      :: binary() | undefined,
    auth       :: {binary(), binary() | undefined} | undefined, %% {Scheme, Creds}
    retries    :: non_neg_integer(),
    created_at :: integer()
}).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Start the push notification manager.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc Register a push notification endpoint for a task.
%%
%% `TaskId' is the task identifier.
%% `ConfigId' is a unique identifier for this push configuration.
%% `PushConfig' is a map with keys:
%%   `url'            - (required) webhook URL
%%   `token'          - (optional) verification token
%%   `authentication' - (optional) #{scheme => ..., credentials => ...}
%% @end
%%--------------------------------------------------------------------
-spec register(binary(), binary(), map()) -> ok | {error, term()}.
register(TaskId, ConfigId, PushConfig) ->
    gen_server:call(?SERVER, {register, TaskId, ConfigId, PushConfig}).

%%--------------------------------------------------------------------
%% @doc Unregister a push notification endpoint.
%% @end
%%--------------------------------------------------------------------
-spec unregister(binary(), binary()) -> ok.
unregister(TaskId, ConfigId) ->
    gen_server:call(?SERVER, {unregister, TaskId, ConfigId}).

%%--------------------------------------------------------------------
%% @doc Send a push notification for a task event.
%%
%% `TaskId' is the task identifier.
%% `EventType' is the type of event (e.g., `status_update',
%%   `artifact_update').
%% `Payload' is the event data to include in the notification.
%%
%% Notifications are sent asynchronously. Failed attempts are
%% retried with exponential backoff.
%% @end
%%--------------------------------------------------------------------
-spec notify(binary(), atom(), map()) -> ok.
notify(TaskId, EventType, Payload) ->
    gen_server:cast(?SERVER, {notify, TaskId, EventType, Payload}).

%%--------------------------------------------------------------------
%% @doc Get the push notification configuration for a task.
%%
%% Returns `{ok, [Config]}' or `{ok, []}' if no configs are
%% registered.
%% @end
%%--------------------------------------------------------------------
-spec get_config(binary()) -> {ok, [map()]}.
get_config(TaskId) ->
    gen_server:call(?SERVER, {get_config, TaskId}).

%%--------------------------------------------------------------------
%% @doc List all push configurations for a task.
%% @end
%%--------------------------------------------------------------------
-spec list_configs(binary()) -> {ok, [map()]}.
list_configs(TaskId) ->
    get_config(TaskId).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    {ok, #state{}}.

handle_call({register, TaskId, ConfigId, PushConfig}, _From, State) ->
    Url = maps:get(<<"url">>, PushConfig, maps:get(url, PushConfig, undefined)),
    case Url of
        undefined ->
            {reply, {error, missing_url}, State};
        _ ->
            Entry = #push_config_entry{
                id = ConfigId,
                task_id = TaskId,
                url = beamai_a2a_utils:to_binary(Url),
                token = maps:get(<<"token">>, PushConfig,
                            maps:get(token, PushConfig, undefined)),
                auth = extract_auth(PushConfig),
                retries = 0,
                created_at = beamai_a2a_utils:now_ms()
            },
            TaskConfigs = maps:get(TaskId, State#state.configs, []),
            %% Replace if same ConfigId exists, otherwise append
            Filtered = [E || E <- TaskConfigs,
                             E#push_config_entry.id =/= ConfigId],
            NewConfigs = maps:put(TaskId, [Entry | Filtered],
                                  State#state.configs),
            %% Also persist to the task store
            persist_push_config(TaskId, ConfigId, PushConfig),
            {reply, ok, State#state{configs = NewConfigs}}
    end;

handle_call({unregister, TaskId, ConfigId}, _From, State) ->
    TaskConfigs = maps:get(TaskId, State#state.configs, []),
    Filtered = [E || E <- TaskConfigs,
                     E#push_config_entry.id =/= ConfigId],
    NewConfigs = case Filtered of
        [] -> maps:remove(TaskId, State#state.configs);
        _  -> maps:put(TaskId, Filtered, State#state.configs)
    end,
    remove_push_config(TaskId, ConfigId),
    {reply, ok, State#state{configs = NewConfigs}};

handle_call({get_config, TaskId}, _From, State) ->
    TaskConfigs = maps:get(TaskId, State#state.configs, []),
    Result = [entry_to_map(E) || E <- TaskConfigs],
    {reply, {ok, Result}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({notify, TaskId, EventType, Payload}, State) ->
    TaskConfigs = maps:get(TaskId, State#state.configs, []),
    lists:foreach(fun(Entry) ->
        send_notification(Entry, EventType, Payload, 0)
    end, TaskConfigs),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({retry_notification, Entry, EventType, Payload, Attempt}, State) ->
    send_notification(Entry, EventType, Payload, Attempt),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Send a push notification to a registered endpoint.
-spec send_notification(#push_config_entry{}, atom(), map(),
                        non_neg_integer()) -> ok.
send_notification(Entry, EventType, Payload, Attempt) ->
    Url = Entry#push_config_entry.url,
    Body = build_notification_body(Entry#push_config_entry.task_id,
                                    EventType, Payload),
    Headers = build_notification_headers(Entry),
    Request = {binary_to_list(Url), Headers, "application/json", Body},

    %% Send asynchronously to avoid blocking
    Self = self(),
    spawn(fun() ->
        case httpc:request(post, Request, [{timeout, 10000}], []) of
            {ok, {{_, StatusCode, _}, _, _}} when StatusCode >= 200,
                                                   StatusCode < 300 ->
                logger:debug("Push notification sent to ~s (status ~p)",
                             [Url, StatusCode]),
                ok;
            {ok, {{_, StatusCode, _}, _, RespBody}} ->
                logger:warning("Push notification to ~s failed: ~p ~s",
                               [Url, StatusCode, RespBody]),
                maybe_retry(Self, Entry, EventType, Payload, Attempt);
            {error, Reason} ->
                logger:error("Push notification to ~s error: ~p",
                             [Url, Reason]),
                maybe_retry(Self, Entry, EventType, Payload, Attempt)
        end
    end),
    ok.

%% @doc Schedule a retry with exponential backoff.
-spec maybe_retry(pid(), #push_config_entry{}, atom(), map(),
                  non_neg_integer()) -> ok.
maybe_retry(Server, Entry, EventType, Payload, Attempt) ->
    NextAttempt = Attempt + 1,
    case NextAttempt >= ?MAX_RETRIES of
        true ->
            logger:error("Push notification to ~s exhausted retries (~p)",
                         [Entry#push_config_entry.url, ?MAX_RETRIES]),
            ok;
        false ->
            BackoffMs = ?BASE_BACKOFF_MS * trunc(math:pow(2, Attempt)),
            %% Add jitter (up to 25% of backoff)
            Jitter = rand:uniform(max(1, BackoffMs div 4)),
            Delay = BackoffMs + Jitter,
            erlang:send_after(Delay, Server,
                              {retry_notification, Entry, EventType,
                               Payload, NextAttempt}),
            ok
    end.

%% @doc Build the JSON notification body.
-spec build_notification_body(binary(), atom(), map()) -> binary().
build_notification_body(TaskId, EventType, Payload) ->
    EventBin = atom_to_binary(EventType, utf8),
    Notification = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">>  => <<"tasks/pushNotification">>,
        <<"params">>  => #{
            <<"taskId">>    => TaskId,
            <<"eventType">> => EventBin,
            <<"data">>      => Payload
        }
    },
    iolist_to_binary(json:encode(Notification)).

%% @doc Build HTTP headers for the push notification request.
-spec build_notification_headers(#push_config_entry{}) ->
    [{string(), string()}].
build_notification_headers(Entry) ->
    BaseHeaders = [{"Content-Type", "application/json"}],
    WithAuth = case Entry#push_config_entry.auth of
        undefined ->
            BaseHeaders;
        {Scheme, undefined} ->
            [{"Authorization", binary_to_list(Scheme)} | BaseHeaders];
        {Scheme, Creds} ->
            AuthVal = binary_to_list(<<Scheme/binary, " ", Creds/binary>>),
            [{"Authorization", AuthVal} | BaseHeaders]
    end,
    case Entry#push_config_entry.token of
        undefined -> WithAuth;
        Token -> [{"X-A2A-Token", binary_to_list(Token)} | WithAuth]
    end.

%% @doc Extract authentication info from a push config map.
-spec extract_auth(map()) -> {binary(), binary() | undefined} | undefined.
extract_auth(Config) ->
    case maps:get(<<"authentication">>, Config,
                  maps:get(authentication, Config, undefined)) of
        undefined -> undefined;
        AuthMap when is_map(AuthMap) ->
            Scheme = maps:get(<<"scheme">>, AuthMap,
                              maps:get(scheme, AuthMap, <<"Bearer">>)),
            Creds = maps:get(<<"credentials">>, AuthMap,
                             maps:get(credentials, AuthMap, undefined)),
            {beamai_a2a_utils:to_binary(Scheme),
             case Creds of
                 undefined -> undefined;
                 _ -> beamai_a2a_utils:to_binary(Creds)
             end};
        _ -> undefined
    end.

%% @doc Convert an entry record to a map for external consumption.
-spec entry_to_map(#push_config_entry{}) -> map().
entry_to_map(Entry) ->
    Base = #{
        <<"id">>        => Entry#push_config_entry.id,
        <<"taskId">>    => Entry#push_config_entry.task_id,
        <<"url">>       => Entry#push_config_entry.url,
        <<"createdAt">> => Entry#push_config_entry.created_at
    },
    M1 = case Entry#push_config_entry.token of
        undefined -> Base;
        Token -> Base#{<<"token">> => Token}
    end,
    case Entry#push_config_entry.auth of
        undefined -> M1;
        {Scheme, Creds} ->
            AuthMap = #{<<"scheme">> => Scheme},
            AuthMap2 = case Creds of
                undefined -> AuthMap;
                _ -> AuthMap#{<<"credentials">> => <<"***">>}  %% redacted
            end,
            M1#{<<"authentication">> => AuthMap2}
    end.

%% @doc Persist push config to the task store (best-effort).
-spec persist_push_config(binary(), binary(), map()) -> ok.
persist_push_config(TaskId, ConfigId, PushConfig) ->
    try
        PNConfig = beamai_a2a_convert:map_to_push_config(PushConfig),
        TaskPNConfig = #task_push_notification_config{
            id = ConfigId,
            task_id = TaskId,
            push_notification_config = PNConfig
        },
        a2a_task_store:add_push_config(TaskId, TaskPNConfig)
    catch
        _:_ -> ok  %% Best effort
    end.

%% @doc Remove push config from the task store (best-effort).
-spec remove_push_config(binary(), binary()) -> ok.
remove_push_config(TaskId, ConfigId) ->
    try
        a2a_task_store:delete_push_config(TaskId, ConfigId)
    catch
        _:_ -> ok  %% Best effort
    end.
