%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Bridge - Core Bridge between a2a_erl and BeamAI Kernel
%%%
%%% This module provides the primary integration layer connecting the
%%% existing a2a_erl application to the BeamAI kernel/process framework.
%%% It maintains backward compatibility with all existing A2A handlers
%%% while enabling BeamAI kernel features such as tool registration,
%%% process orchestration, and unified data translation.
%%%
%%% Responsibilities:
%%% - Initialize and manage a BeamAI kernel instance
%%% - Register existing A2A handlers as BeamAI tools
%%% - Translate between A2A and BeamAI data formats
%%% - Provide kernel lifecycle management
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_bridge).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    get_kernel/0,
    register_a2a_handler/2,
    unregister_a2a_handler/1,
    translate_task/1,
    translate_message/1,
    list_handlers/0,
    get_status/0,
    shutdown/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%%%===================================================================
%%% Records
%%%===================================================================

-record(kernel_state, {
    id          :: binary(),
    status      :: initializing | running | degraded | shutting_down,
    started_at  :: integer(),
    config      :: map(),
    capabilities :: [atom()]
}).

-record(registered_handler, {
    name        :: atom(),
    module      :: module(),
    description :: binary(),
    input_schema  :: map(),
    output_schema :: map(),
    registered_at :: integer()
}).

-record(state, {
    kernel        :: #kernel_state{},
    handlers      :: #{atom() => #registered_handler{}},
    handler_pids  :: #{atom() => pid()},
    metrics       :: #{atom() => non_neg_integer()},
    event_sub_ref :: reference() | undefined
}).

-define(SERVER, ?MODULE).
-define(DEFAULT_CONFIG, #{
    max_handlers => 256,
    translation_cache_size => 1024,
    heartbeat_interval => 30000,
    enable_metrics => true
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Retrieve the current BeamAI kernel state.
-spec get_kernel() -> {ok, map()} | {error, not_initialized}.
get_kernel() ->
    gen_server:call(?SERVER, get_kernel).

%% @doc Register an existing A2A handler module as a BeamAI tool.
%% The handler must implement the a2a_handler behaviour.
-spec register_a2a_handler(atom(), module()) -> ok | {error, term()}.
register_a2a_handler(Name, Module) ->
    gen_server:call(?SERVER, {register_handler, Name, Module}).

%% @doc Unregister a previously registered handler.
-spec unregister_a2a_handler(atom()) -> ok | {error, not_found}.
unregister_a2a_handler(Name) ->
    gen_server:call(?SERVER, {unregister_handler, Name}).

%% @doc Translate an A2A task record into a BeamAI-compatible map.
-spec translate_task(task()) -> {ok, map()} | {error, term()}.
translate_task(Task) when is_record(Task, task) ->
    gen_server:call(?SERVER, {translate_task, Task});
translate_task(_) ->
    {error, invalid_task}.

%% @doc Translate an A2A message record into a BeamAI-compatible map.
-spec translate_message(message()) -> {ok, map()} | {error, term()}.
translate_message(Message) when is_record(Message, message) ->
    gen_server:call(?SERVER, {translate_message, Message});
translate_message(_) ->
    {error, invalid_message}.

%% @doc List all registered handlers.
-spec list_handlers() -> [{atom(), module()}].
list_handlers() ->
    gen_server:call(?SERVER, list_handlers).

%% @doc Get the current bridge status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%% @doc Gracefully shut down the bridge and release resources.
-spec shutdown() -> ok.
shutdown() ->
    gen_server:call(?SERVER, shutdown).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init(UserConfig) ->
    process_flag(trap_exit, true),
    Config = maps:merge(?DEFAULT_CONFIG, UserConfig),
    Now = erlang:system_time(millisecond),
    KernelId = generate_kernel_id(),

    Kernel = #kernel_state{
        id = KernelId,
        status = initializing,
        started_at = Now,
        config = Config,
        capabilities = [task_translation, handler_registration,
                        process_bridge, graph_bridge, event_adapter]
    },

    State = #state{
        kernel = Kernel,
        handlers = #{},
        handler_pids = #{},
        metrics = #{
            tasks_translated => 0,
            messages_translated => 0,
            handlers_registered => 0,
            errors => 0
        },
        event_sub_ref = undefined
    },

    %% Subscribe to A2A events if the event system is available
    EventRef = try_subscribe_events(),

    %% Schedule heartbeat
    HeartbeatInterval = maps:get(heartbeat_interval, Config, 30000),
    erlang:send_after(HeartbeatInterval, self(), heartbeat),

    logger:info("BeamAI bridge initialized with kernel ~s", [KernelId]),
    RunningKernel = Kernel#kernel_state{status = running},
    {ok, State#state{kernel = RunningKernel, event_sub_ref = EventRef}}.

%% @private
handle_call(get_kernel, _From, #state{kernel = Kernel} = State) ->
    KernelMap = #{
        id => Kernel#kernel_state.id,
        status => Kernel#kernel_state.status,
        started_at => Kernel#kernel_state.started_at,
        capabilities => Kernel#kernel_state.capabilities,
        config => Kernel#kernel_state.config
    },
    {reply, {ok, KernelMap}, State};

handle_call({register_handler, Name, Module}, _From, State) ->
    #state{handlers = Handlers, metrics = Metrics} = State,
    MaxHandlers = maps:get(max_handlers, (State#state.kernel)#kernel_state.config, 256),
    case map_size(Handlers) >= MaxHandlers of
        true ->
            {reply, {error, max_handlers_reached}, State};
        false ->
            case validate_handler_module(Module) of
                ok ->
                    Now = erlang:system_time(millisecond),
                    Handler = #registered_handler{
                        name = Name,
                        module = Module,
                        description = handler_description(Module),
                        input_schema = #{type => a2a_task, format => record},
                        output_schema = #{type => beamai_result, format => map},
                        registered_at = Now
                    },
                    NewHandlers = maps:put(Name, Handler, Handlers),
                    RegCount = maps:get(handlers_registered, Metrics, 0),
                    NewMetrics = Metrics#{handlers_registered => RegCount + 1},
                    NewState = State#state{handlers = NewHandlers, metrics = NewMetrics},
                    logger:info("Registered A2A handler ~p (~p) as BeamAI tool", [Name, Module]),
                    {reply, ok, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({unregister_handler, Name}, _From, #state{handlers = Handlers} = State) ->
    case maps:is_key(Name, Handlers) of
        true ->
            NewHandlers = maps:remove(Name, Handlers),
            NewPids = maps:remove(Name, State#state.handler_pids),
            logger:info("Unregistered A2A handler ~p from BeamAI", [Name]),
            {reply, ok, State#state{handlers = NewHandlers, handler_pids = NewPids}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call({translate_task, Task}, _From, #state{metrics = Metrics} = State) ->
    try
        Translated = do_translate_task(Task),
        Count = maps:get(tasks_translated, Metrics, 0),
        NewMetrics = Metrics#{tasks_translated => Count + 1},
        {reply, {ok, Translated}, State#state{metrics = NewMetrics}}
    catch
        _:Error ->
            ErrCount = maps:get(errors, Metrics, 0),
            NewMetrics = Metrics#{errors => ErrCount + 1},
            {reply, {error, {translation_failed, Error}}, State#state{metrics = NewMetrics}}
    end;

handle_call({translate_message, Message}, _From, #state{metrics = Metrics} = State) ->
    try
        Translated = do_translate_message(Message),
        Count = maps:get(messages_translated, Metrics, 0),
        NewMetrics = Metrics#{messages_translated => Count + 1},
        {reply, {ok, Translated}, State#state{metrics = NewMetrics}}
    catch
        _:Error ->
            ErrCount = maps:get(errors, Metrics, 0),
            NewMetrics = Metrics#{errors => ErrCount + 1},
            {reply, {error, {translation_failed, Error}}, State#state{metrics = NewMetrics}}
    end;

handle_call(list_handlers, _From, #state{handlers = Handlers} = State) ->
    List = maps:fold(fun(Name, #registered_handler{module = Mod}, Acc) ->
        [{Name, Mod} | Acc]
    end, [], Handlers),
    {reply, lists:reverse(List), State};

handle_call(get_status, _From, State) ->
    #state{kernel = Kernel, handlers = Handlers, metrics = Metrics} = State,
    Status = #{
        kernel_id => Kernel#kernel_state.id,
        kernel_status => Kernel#kernel_state.status,
        uptime_ms => erlang:system_time(millisecond) - Kernel#kernel_state.started_at,
        handler_count => map_size(Handlers),
        metrics => Metrics
    },
    {reply, Status, State};

handle_call(shutdown, _From, State) ->
    logger:info("BeamAI bridge shutting down"),
    Kernel = State#state.kernel,
    NewKernel = Kernel#kernel_state{status = shutting_down},
    {stop, normal, ok, State#state{kernel = NewKernel}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(heartbeat, State) ->
    Kernel = State#state.kernel,
    Config = Kernel#kernel_state.config,
    Interval = maps:get(heartbeat_interval, Config, 30000),
    erlang:send_after(Interval, self(), heartbeat),
    {noreply, State};

handle_info({yawl_a2a_event, EventType, EventData}, State) ->
    %% Forward A2A events into the BeamAI kernel context
    handle_a2a_event(EventType, EventData, State);

handle_info({'EXIT', Pid, Reason}, State) ->
    %% A linked handler process exited
    NewPids = maps:filter(fun(_Name, HPid) -> HPid =/= Pid end, State#state.handler_pids),
    case Reason of
        normal -> ok;
        _ -> logger:warning("BeamAI bridge: linked handler ~p exited: ~p", [Pid, Reason])
    end,
    {noreply, State#state{handler_pids = NewPids}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{event_sub_ref = Ref}) ->
    case Ref of
        undefined -> ok;
        _ ->
            try yawl_a2a_events:unsubscribe(Ref)
            catch _:_ -> ok
            end
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Generate a unique kernel identifier.
-spec generate_kernel_id() -> binary().
generate_kernel_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"beamai-kernel-", Hex/binary>>.

%% @private Validate that a module implements the a2a_handler behaviour.
-spec validate_handler_module(module()) -> ok | {error, term()}.
validate_handler_module(Module) ->
    try
        Attrs = Module:module_info(attributes),
        Behaviours = proplists:get_value(behaviour, Attrs, []) ++
                     proplists:get_value(behavior, Attrs, []),
        case lists:member(a2a_handler, Behaviours) of
            true -> ok;
            false ->
                %% Also accept modules that export the required callbacks
                Exports = Module:module_info(exports),
                RequiredFns = [{init, 2}, {process, 2}, {handle_message, 2}],
                case lists:all(fun(Fn) -> lists:member(Fn, Exports) end, RequiredFns) of
                    true -> ok;
                    false -> {error, {missing_callbacks, Module}}
                end
        end
    catch
        _:_ -> {error, {module_not_loaded, Module}}
    end.

%% @private Extract a handler description from module attributes if available.
-spec handler_description(module()) -> binary().
handler_description(Module) ->
    try
        Attrs = Module:module_info(attributes),
        case proplists:get_value(description, Attrs, undefined) of
            undefined ->
                ModBin = atom_to_binary(Module, utf8),
                <<"A2A handler: ", ModBin/binary>>;
            [Desc] when is_list(Desc) ->
                list_to_binary(Desc);
            _ ->
                ModBin = atom_to_binary(Module, utf8),
                <<"A2A handler: ", ModBin/binary>>
        end
    catch
        _:_ ->
            ModBin = atom_to_binary(Module, utf8),
            <<"A2A handler: ", ModBin/binary>>
    end.

%% @private Translate an A2A #task{} record to a BeamAI-compatible map.
-spec do_translate_task(task()) -> map().
do_translate_task(#task{id = Id, context_id = CtxId, status = Status,
                        artifacts = Artifacts, history = History,
                        metadata = Meta}) ->
    #{
        beamai_type => process,
        id => Id,
        context_id => CtxId,
        state => translate_task_state(Status#task_status.state),
        status => #{
            a2a_state => Status#task_status.state,
            beamai_state => translate_task_state(Status#task_status.state),
            timestamp => Status#task_status.timestamp,
            message => case Status#task_status.message of
                undefined -> null;
                Msg -> do_translate_message(Msg)
            end
        },
        artifacts => [translate_artifact(A) || A <- Artifacts],
        history => [do_translate_message(M) || M <- History],
        metadata => Meta#{source => a2a_erl},
        framework => #{
            origin => a2a,
            bridge_version => <<"1.0.0">>
        }
    }.

%% @private Translate an A2A #message{} record to a BeamAI-compatible map.
-spec do_translate_message(message()) -> map().
do_translate_message(#message{message_id = MsgId, context_id = CtxId,
                              task_id = TaskId, role = Role,
                              parts = Parts, metadata = Meta}) ->
    #{
        beamai_type => message,
        id => MsgId,
        context_id => CtxId,
        task_id => TaskId,
        role => Role,
        content => [translate_part(P) || P <- Parts],
        metadata => Meta#{source => a2a_erl}
    }.

%% @private Translate A2A task states to BeamAI process states.
-spec translate_task_state(atom()) -> atom().
translate_task_state(submitted)      -> pending;
translate_task_state(working)        -> executing;
translate_task_state(completed)      -> completed;
translate_task_state(failed)         -> failed;
translate_task_state(canceled)       -> cancelled;
translate_task_state(input_required) -> waiting_input;
translate_task_state(auth_required)  -> waiting_auth;
translate_task_state(rejected)       -> rejected;
translate_task_state(unspecified)    -> unknown;
translate_task_state(Other)          -> Other.

%% @private Translate an A2A artifact to a BeamAI-compatible map.
-spec translate_artifact(artifact()) -> map().
translate_artifact(#artifact{artifact_id = AId, name = Name,
                             description = Desc, parts = Parts,
                             metadata = Meta}) ->
    #{
        id => AId,
        name => Name,
        description => Desc,
        content => [translate_part(P) || P <- Parts],
        metadata => Meta
    }.

%% @private Translate an A2A part to a BeamAI-compatible map.
-spec translate_part(part()) -> map().
translate_part(#part{content = Content, metadata = Meta,
                     filename = Filename, media_type = MediaType}) ->
    Base = case Content of
        {text, Text}  -> #{type => text, value => Text};
        {raw, Raw}    -> #{type => raw, value => Raw};
        {url, Url}    -> #{type => url, value => Url};
        {data, Data}  -> #{type => data, value => Data}
    end,
    Base#{
        metadata => Meta,
        filename => Filename,
        media_type => MediaType
    }.

%% @private Try to subscribe to A2A events for forwarding into BeamAI.
-spec try_subscribe_events() -> reference() | undefined.
try_subscribe_events() ->
    try
        case whereis(yawl_a2a_events) of
            undefined -> undefined;
            _Pid ->
                {ok, Ref} = yawl_a2a_events:subscribe(self(), all),
                Ref
        end
    catch
        _:_ -> undefined
    end.

%% @private Handle an incoming A2A event within the bridge context.
-spec handle_a2a_event(atom(), map(), #state{}) -> {noreply, #state{}}.
handle_a2a_event(_EventType, _EventData, State) ->
    %% Events are received here for potential forwarding to BeamAI
    %% kernel subsystems. The beamai_event_adapter handles the
    %% detailed translation; this is the raw ingestion point.
    {noreply, State}.
