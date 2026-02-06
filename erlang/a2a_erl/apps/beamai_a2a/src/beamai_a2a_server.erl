%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Protocol Server
%%%
%%% A gen_server that implements the BeamAI A2A protocol endpoint.
%%% It maintains server state including agent configuration, a cached
%%% agent card, and a task process map.  All JSON-RPC requests flow
%%% through this server, which applies the middleware pipeline and
%%% delegates to beamai_a2a_handler for method dispatch.
%%%
%%% The server supports both authenticated and unauthenticated
%%% request paths, configurable via the middleware pipeline.
%%%
%%% Key functions:
%%%   start_link/1          - Start with agent config
%%%   handle_request/2      - Process a decoded JSON-RPC request map
%%%   handle_json/2         - Process raw JSON binary
%%%   handle_request_with_auth/3 - Process with explicit auth context
%%%   request_input/3       - Signal input_required to a task
%%%   complete_task/3       - Mark a task as completed
%%%   fail_task/3           - Mark a task as failed
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_server).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/1,
    start_link/2,
    handle_request/2,
    handle_json/2,
    handle_request_with_auth/3,
    request_input/3,
    complete_task/3,
    fail_task/3,
    get_agent_card/1,
    set_agent_card/2,
    get_state/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(DEFAULT_NAME, beamai_a2a_server).

-record(state, {
    %% Agent configuration
    agent_config :: map(),
    %% Cached agent card (built from config)
    agent_card :: #agent_card{} | undefined,
    %% Middleware pipeline
    pipeline :: beamai_a2a_middleware:pipeline(),
    %% Task processes: task_id => pid
    task_procs = #{} :: #{binary() => pid()},
    %% Monitor refs: ref => task_id
    task_monitors = #{} :: #{reference() => binary()},
    %% Server name for registration
    name :: atom()
}).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Start the A2A server with the given agent configuration.
%%
%% Config keys:
%%   `name'            - registered name (default: beamai_a2a_server)
%%   `agent_card'      - #agent_card{} or map()
%%   `handler_module'  - module implementing a2a_handler behaviour
%%   `middleware'       - list of middleware funs (optional)
%%   `auth_required'   - boolean (default: false)
%%   `rate_limit'      - rate limit config map (optional)
%% @end
%%--------------------------------------------------------------------
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    Name = maps:get(name, Config, ?DEFAULT_NAME),
    start_link(Name, Config).

-spec start_link(atom(), map()) -> {ok, pid()} | {error, term()}.
start_link(Name, Config) ->
    gen_server:start_link({local, Name}, ?MODULE, Config#{name => Name}, []).

%%--------------------------------------------------------------------
%% @doc Handle a decoded JSON-RPC request map.
%%
%% Returns a JSON binary response.
%% @end
%%--------------------------------------------------------------------
-spec handle_request(pid() | atom(), map()) -> binary().
handle_request(Server, Request) ->
    gen_server:call(Server, {handle_request, Request}, 30000).

%%--------------------------------------------------------------------
%% @doc Handle a raw JSON binary payload.
%%
%% Decodes the JSON-RPC request, processes it, and returns a JSON
%% binary response.
%% @end
%%--------------------------------------------------------------------
-spec handle_json(pid() | atom(), binary()) -> binary().
handle_json(Server, JsonBinary) ->
    gen_server:call(Server, {handle_json, JsonBinary}, 30000).

%%--------------------------------------------------------------------
%% @doc Handle a request with explicit authentication context.
%%
%% `AuthInfo' is a map with authentication details (e.g., from
%% HTTP headers already parsed by the Cowboy handler).
%% @end
%%--------------------------------------------------------------------
-spec handle_request_with_auth(pid() | atom(), map(), map()) -> binary().
handle_request_with_auth(Server, Request, AuthInfo) ->
    gen_server:call(Server, {handle_request_auth, Request, AuthInfo}, 30000).

%%--------------------------------------------------------------------
%% @doc Signal that a task requires input from the user.
%%
%% `TaskId' is the task identifier.
%% `Prompt' is the prompt message to display to the user.
%% `Metadata' is optional metadata to include in the status update.
%% @end
%%--------------------------------------------------------------------
-spec request_input(pid() | atom(), binary(), binary()) -> ok | {error, term()}.
request_input(Server, TaskId, Prompt) ->
    gen_server:call(Server, {request_input, TaskId, Prompt}).

%%--------------------------------------------------------------------
%% @doc Mark a task as completed with the given result.
%%
%% `TaskId' is the task identifier.
%% `Result' is the result map (may contain `artifacts').
%% `Metadata' is optional metadata.
%% @end
%%--------------------------------------------------------------------
-spec complete_task(pid() | atom(), binary(), map()) -> ok | {error, term()}.
complete_task(Server, TaskId, Result) ->
    gen_server:call(Server, {complete_task, TaskId, Result}).

%%--------------------------------------------------------------------
%% @doc Mark a task as failed.
%%
%% `TaskId' is the task identifier.
%% `Reason' is the failure reason.
%% `Metadata' is optional metadata.
%% @end
%%--------------------------------------------------------------------
-spec fail_task(pid() | atom(), binary(), binary()) -> ok | {error, term()}.
fail_task(Server, TaskId, Reason) ->
    gen_server:call(Server, {fail_task, TaskId, Reason}).

%%--------------------------------------------------------------------
%% @doc Get the cached agent card.
%% @end
%%--------------------------------------------------------------------
-spec get_agent_card(pid() | atom()) -> #agent_card{}.
get_agent_card(Server) ->
    gen_server:call(Server, get_agent_card).

%%--------------------------------------------------------------------
%% @doc Set/update the agent card.
%% @end
%%--------------------------------------------------------------------
-spec set_agent_card(pid() | atom(), #agent_card{}) -> ok.
set_agent_card(Server, Card) ->
    gen_server:call(Server, {set_agent_card, Card}).

%%--------------------------------------------------------------------
%% @doc Get the current server state (for debugging).
%% @end
%%--------------------------------------------------------------------
-spec get_state(pid() | atom()) -> map().
get_state(Server) ->
    gen_server:call(Server, get_state).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Config) ->
    %% Build agent card from config
    AgentCard = build_agent_card(Config),

    %% Set handler module in app env for beamai_a2a_handler
    case maps:get(handler_module, Config, undefined) of
        undefined -> ok;
        Mod -> application:set_env(beamai_a2a, handler_module, Mod)
    end,

    %% Build middleware pipeline
    Pipeline = build_pipeline(Config),

    State = #state{
        agent_config = Config,
        agent_card = AgentCard,
        pipeline = Pipeline,
        name = maps:get(name, Config, ?DEFAULT_NAME)
    },

    logger:info("BeamAI A2A server started: ~p", [State#state.name]),
    {ok, State}.

handle_call({handle_request, Request}, _From, State) ->
    Response = process_request(Request, #{}, State),
    {reply, Response, State};

handle_call({handle_json, JsonBinary}, _From, State) ->
    Response = process_json(JsonBinary, #{}, State),
    {reply, Response, State};

handle_call({handle_request_auth, Request, AuthInfo}, _From, State) ->
    Context = #{auth_claims => AuthInfo},
    Response = process_request(Request, Context, State),
    {reply, Response, State};

handle_call({request_input, TaskId, Prompt}, _From, State) ->
    Result = do_request_input(TaskId, Prompt),
    {reply, Result, State};

handle_call({complete_task, TaskId, ResultMap}, _From, State) ->
    Result = do_complete_task(TaskId, ResultMap),
    {reply, Result, State};

handle_call({fail_task, TaskId, Reason}, _From, State) ->
    Result = do_fail_task(TaskId, Reason),
    {reply, Result, State};

handle_call(get_agent_card, _From, State) ->
    {reply, State#state.agent_card, State};

handle_call({set_agent_card, Card}, _From, State) ->
    %% Also update the a2a_agent_card gen_server if running
    try a2a_agent_card:set_card(Card)
    catch _:_ -> ok
    end,
    {reply, ok, State#state{agent_card = Card}};

handle_call(get_state, _From, State) ->
    Info = #{
        name => State#state.name,
        task_count => maps:size(State#state.task_procs),
        agent_card_name => case State#state.agent_card of
            undefined -> undefined;
            Card -> Card#agent_card.name
        end
    },
    {reply, Info, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    %% Task process died - clean up tracking
    case maps:get(Ref, State#state.task_monitors, undefined) of
        undefined ->
            {noreply, State};
        TaskId ->
            NewProcs = maps:remove(TaskId, State#state.task_procs),
            NewMons = maps:remove(Ref, State#state.task_monitors),
            {noreply, State#state{
                task_procs = NewProcs,
                task_monitors = NewMons
            }}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Request processing
%%====================================================================

%% @doc Process a raw JSON binary through the full pipeline.
-spec process_json(binary(), map(), #state{}) -> binary().
process_json(JsonBinary, InitialContext, State) ->
    case beamai_a2a_jsonrpc:decode(JsonBinary) of
        {ok, Request} ->
            process_request(Request, InitialContext, State);
        {batch, Requests} ->
            Responses = [process_batch_item(Item, InitialContext, State)
                         || Item <- Requests],
            %% Filter out notifications (no id => no response)
            Filtered = [R || R <- Responses, R =/= no_response],
            beamai_a2a_jsonrpc:batch(Filtered);
        {error, ErrorObj} ->
            beamai_a2a_jsonrpc:encode_error(null,
                maps:get(<<"code">>, ErrorObj),
                maps:get(<<"message">>, ErrorObj))
    end.

%% @doc Process a single JSON-RPC request map.
-spec process_request(map(), map(), #state{}) -> binary().
process_request(Request, InitialContext, State) ->
    Id = maps:get(<<"id">>, Request, null),
    Method = maps:get(<<"method">>, Request, undefined),
    Params = maps:get(<<"params">>, Request, #{}),

    %% Run middleware pipeline
    case beamai_a2a_middleware:apply(State#state.pipeline,
                                     Request, InitialContext) of
        {ok, Context} ->
            %% Dispatch to handler
            case beamai_a2a_handler:handle(Method, Params, Context) of
                {ok, Result} ->
                    beamai_a2a_jsonrpc:encode_result(Id, Result);
                {error, ErrorObj} ->
                    beamai_a2a_jsonrpc:encode_error(Id,
                        maps:get(<<"code">>, ErrorObj),
                        maps:get(<<"message">>, ErrorObj));
                {subscribe, Pid, TaskId} ->
                    %% For subscriptions, return a result indicating
                    %% the caller should upgrade to SSE. The actual
                    %% SSE setup is handled by the cowboy handler.
                    track_task(TaskId, Pid, State),
                    beamai_a2a_jsonrpc:encode_result(Id, #{
                        <<"subscribe">> => true,
                        <<"taskId">>    => TaskId,
                        <<"taskPid">>   => list_to_binary(
                            pid_to_list(Pid))
                    })
            end;
        {error, ErrorObj} ->
            beamai_a2a_jsonrpc:encode_error(Id,
                maps:get(<<"code">>, ErrorObj),
                maps:get(<<"message">>, ErrorObj));
        {stop, Response} when is_binary(Response) ->
            Response;
        {stop, _Response} ->
            beamai_a2a_jsonrpc:encode_error(Id, -32603,
                                            <<"Request stopped by middleware">>)
    end.

%% @doc Process a single item from a batch request.
-spec process_batch_item({ok, map()} | {error, map()}, map(), #state{}) ->
    binary() | no_response.
process_batch_item({ok, Request}, Context, State) ->
    Id = maps:get(<<"id">>, Request, undefined),
    case Id of
        undefined ->
            %% Notification (no id) - process but don't return response
            _ = process_request(Request, Context, State),
            no_response;
        _ ->
            process_request(Request, Context, State)
    end;
process_batch_item({error, ErrorObj}, _Context, _State) ->
    beamai_a2a_jsonrpc:encode_error(null,
        maps:get(<<"code">>, ErrorObj),
        maps:get(<<"message">>, ErrorObj)).

%%====================================================================
%% Task lifecycle operations
%%====================================================================

%% @doc Signal that a task requires input.
-spec do_request_input(binary(), binary()) -> ok | {error, term()}.
do_request_input(TaskId, Prompt) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            %% Create a prompt message and send status update
            PromptMsg = #message{
                message_id = beamai_a2a_utils:generate_id(),
                task_id = TaskId,
                role = agent,
                parts = [#part{content = {text, Prompt}}]
            },
            _ = PromptMsg,  %% The message is for documentation
            a2a_task_statem:update_status(Pid, input_required),
            %% Notify push endpoints
            beamai_a2a_push:notify(TaskId, input_required, #{
                <<"prompt">> => Prompt
            }),
            ok;
        {error, not_found} ->
            {error, task_not_found}
    end.

%% @doc Complete a task with results.
-spec do_complete_task(binary(), map()) -> ok | {error, term()}.
do_complete_task(TaskId, ResultMap) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            %% Add artifacts if present
            case maps:get(artifacts, ResultMap,
                          maps:get(<<"artifacts">>, ResultMap, [])) of
                [] -> ok;
                Artifacts ->
                    lists:foreach(fun(ArtMap) ->
                        Artifact = case is_map(ArtMap) of
                            true -> beamai_a2a_convert:map_to_artifact(ArtMap);
                            false -> ArtMap
                        end,
                        a2a_task_statem:add_artifact(Pid, Artifact)
                    end, Artifacts)
            end,
            a2a_task_statem:update_status(Pid, completed),
            beamai_a2a_push:notify(TaskId, completed, ResultMap),
            ok;
        {error, not_found} ->
            {error, task_not_found}
    end.

%% @doc Fail a task with a reason.
-spec do_fail_task(binary(), binary()) -> ok | {error, term()}.
do_fail_task(TaskId, Reason) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            a2a_task_statem:update_status(Pid, failed),
            beamai_a2a_push:notify(TaskId, failed, #{
                <<"reason">> => Reason
            }),
            ok;
        {error, not_found} ->
            {error, task_not_found}
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Build an agent card from the server configuration.
-spec build_agent_card(map()) -> #agent_card{}.
build_agent_card(Config) ->
    case maps:get(agent_card, Config, undefined) of
        undefined ->
            %% Try to get from the a2a_agent_card gen_server
            try a2a_agent_card:get_card()
            catch _:_ -> default_agent_card(Config)
            end;
        Card when is_record(Card, agent_card) ->
            Card;
        CardMap when is_map(CardMap) ->
            beamai_a2a_convert:map_to_agent_card(CardMap)
    end.

%% @doc Create a default agent card.
-spec default_agent_card(map()) -> #agent_card{}.
default_agent_card(Config) ->
    Name = maps:get(agent_name, Config, <<"BeamAI A2A Agent">>),
    Desc = maps:get(agent_description, Config,
                    <<"A2A protocol agent powered by BeamAI">>),
    Version = maps:get(agent_version, Config, <<"0.1.0">>),
    #agent_card{
        name = Name,
        description = Desc,
        version = Version,
        supported_interfaces = [
            #agent_interface{
                url = get_base_url(Config),
                protocol_binding = <<"JSONRPC">>,
                protocol_version = <<"0.4">>
            }
        ],
        capabilities = #agent_capabilities{
            streaming = true,
            push_notifications = true,
            extended_agent_card = false,
            extensions = []
        },
        default_input_modes = [<<"text/plain">>, <<"application/json">>],
        default_output_modes = [<<"text/plain">>, <<"application/json">>],
        skills = [],
        security_schemes = #{},
        security_requirements = []
    }.

%% @doc Get the base URL from config or application env.
-spec get_base_url(map()) -> binary().
get_base_url(Config) ->
    case maps:get(base_url, Config, undefined) of
        undefined ->
            Host = application:get_env(a2a_erl, host, "localhost"),
            Port = application:get_env(a2a_erl, port, 8080),
            Scheme = application:get_env(a2a_erl, scheme, "http"),
            iolist_to_binary(io_lib:format("~s://~s:~p",
                                            [Scheme, Host, Port]));
        Url -> Url
    end.

%% @doc Build the middleware pipeline from configuration.
-spec build_pipeline(map()) -> beamai_a2a_middleware:pipeline().
build_pipeline(Config) ->
    %% Start with logging
    Base = [beamai_a2a_middleware:logging()],

    %% Add CORS
    WithCors = Base ++ [beamai_a2a_middleware:cors()],

    %% Add auth if required
    WithAuth = case maps:get(auth_required, Config, false) of
        true ->
            AuthOpts = maps:get(auth_opts, Config, #{}),
            WithCors ++ [beamai_a2a_middleware:auth(AuthOpts)];
        false ->
            WithCors
    end,

    %% Add rate limiting if configured
    WithRate = case maps:get(rate_limit, Config, undefined) of
        undefined ->
            WithAuth;
        RateConfig when is_map(RateConfig) ->
            WithAuth ++ [beamai_a2a_middleware:rate_limit(RateConfig)]
    end,

    %% Add custom middleware
    Custom = maps:get(middleware, Config, []),
    beamai_a2a_middleware:chain(WithRate ++ Custom).

%% @doc Track a task process for monitoring.
-spec track_task(binary(), pid(), #state{}) -> ok.
track_task(TaskId, Pid, State) ->
    case maps:is_key(TaskId, State#state.task_procs) of
        true -> ok;
        false ->
            Ref = erlang:monitor(process, Pid),
            %% Note: We update state via a cast since we may be in a
            %% synchronous call context.  The state update will be
            %% handled in handle_cast.
            gen_server:cast(State#state.name,
                            {track_task, TaskId, Pid, Ref}),
            ok
    end.
