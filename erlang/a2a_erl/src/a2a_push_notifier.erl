%%% @doc A2A Push Notification Handler
%%%
%%% This module handles sending push notifications to configured webhooks
%%% when task state changes occur. Uses OTP 28's httpc client.
%%%
%%% Push notifications are sent as HTTP POST requests with JSON body
%%% containing the task status update.
-module(a2a_push_notifier).

-include("a2a.hrl").

%% API
-export([
    notify/2,
    notify_async/2
]).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Send push notification synchronously
-spec notify(task_push_notification_config(), task()) -> ok | {error, term()}.
notify(Config, Task) ->
    PushConfig = Config#task_push_notification_config.push_notification_config,
    Url = PushConfig#push_notification_config.url,

    %% Build notification payload
    Payload = build_payload(Task),

    %% Build headers
    Headers = build_headers(PushConfig),

    %% Send HTTP POST request
    Request = {binary_to_list(Url), Headers, "application/json", Payload},

    case httpc:request(post, Request, [{timeout, 10000}], []) of
        {ok, {{_, StatusCode, _}, _, _Body}} when StatusCode >= 200, StatusCode < 300 ->
            logger:debug("Push notification sent successfully to ~s", [Url]),
            ok;
        {ok, {{_, StatusCode, _}, _, Body}} ->
            logger:warning("Push notification failed with status ~p: ~s", [StatusCode, Body]),
            {error, {http_status, StatusCode}};
        {error, Reason} ->
            logger:error("Push notification request failed: ~p", [Reason]),
            {error, Reason}
    end.

%% @doc Send push notification asynchronously
-spec notify_async(task_push_notification_config(), task()) -> ok.
notify_async(Config, Task) ->
    spawn(fun() ->
        case notify(Config, Task) of
            ok -> ok;
            {error, Reason} ->
                %% Could implement retry logic here
                logger:warning("Async push notification failed: ~p", [Reason])
        end
    end),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Build the notification payload
-spec build_payload(task()) -> binary().
build_payload(Task) ->
    %% Create a task status update event
    StatusEvent = #task_status_update_event{
        task_id = Task#task.id,
        context_id = Task#task.context_id,
        status = Task#task.status,
        metadata = Task#task.metadata
    },

    %% Wrap in JSON-RPC notification format
    Notification = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"task/statusUpdate">>,
        <<"params">> => #{
            <<"taskId">> => StatusEvent#task_status_update_event.task_id,
            <<"contextId">> => StatusEvent#task_status_update_event.context_id,
            <<"status">> => a2a_json:encode_task_status(Task#task.status),
            <<"metadata">> => StatusEvent#task_status_update_event.metadata
        }
    },

    json:encode(Notification).

%% @doc Build HTTP headers including authentication
-spec build_headers(push_notification_config()) -> [{string(), string()}].
build_headers(Config) ->
    BaseHeaders = [{"Content-Type", "application/json"}],

    %% Add authentication header if configured
    case Config#push_notification_config.authentication of
        undefined ->
            BaseHeaders;
        #authentication_info{scheme = Scheme, credentials = Credentials} ->
            AuthValue = case Credentials of
                undefined -> binary_to_list(Scheme);
                Creds -> binary_to_list(<<Scheme/binary, " ", Creds/binary>>)
            end,
            [{"Authorization", AuthValue} | BaseHeaders]
    end ++
    %% Add token header if configured
    case Config#push_notification_config.token of
        undefined -> [];
        Token -> [{"X-A2A-Token", binary_to_list(Token)}]
    end.
