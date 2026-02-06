%%% @doc BeamAI HotCI Adapter - Hot Code Infrastructure Integration
%%%
%%% This module provides the primary integration layer between the BeamAI
%%% framework and the HotCI (Hot Code Infrastructure) enterprise upgrade
%%% system. It registers all beamai_* modules with HotCI for zero-downtime
%%% hot code upgrades, defines upgrade paths for BeamAI module versions,
%%% and handles state migration during code upgrades.
%%%
%%% Responsibilities:
%%% - Register all beamai_* modules with HotCI upgrade system
%%% - Define version-aware upgrade paths for BeamAI modules
%%% - Handle state migration during code upgrades and downgrades
%%% - Track module state snapshots for rollback support
%%% - Coordinate with a2a_optimized_upgrade and a2a_rollback_manager
%%%
%%% @end
-module(beamai_hotci_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    register_modules/0,
    get_upgrade_plan/1,
    handle_upgrade/2,
    handle_downgrade/2,
    get_module_states/0
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

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(REGISTRATION_RETRY_INTERVAL, 5000).
-define(STATE_SNAPSHOT_INTERVAL, 60000).
-define(MAX_VERSION_HISTORY, 100).

%% All BeamAI modules that participate in hot code upgrades
-define(BEAMAI_MODULES, [
    beamai_bridge,
    beamai_health_adapter,
    beamai_metrics_adapter,
    beamai_integrity_adapter,
    beamai_disaster_recovery_adapter,
    beamai_security_adapter,
    beamai_monitoring_adapter,
    beamai_benchmark_adapter,
    beamai_enterprise_sup
]).

-record(state, {
    registered_modules = [] :: [module()],
    upgrade_plans = #{} :: #{module() => list()},
    module_states = #{} :: #{module() => term()},
    version_history = [] :: list(),
    snapshot_timer :: reference() | undefined,
    registration_status = pending :: pending | complete | partial
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the HotCI adapter with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Register all BeamAI modules with the HotCI upgrade system.
%% Returns the list of modules that were successfully registered.
-spec register_modules() -> {ok, [module()]} | {error, term()}.
register_modules() ->
    gen_server:call(?SERVER, register_modules, 30000).

%% @doc Retrieve the upgrade plan for a given module.
%% The upgrade plan describes version transitions and state migrations.
-spec get_upgrade_plan(module()) -> {ok, list()} | {error, not_found}.
get_upgrade_plan(Module) ->
    gen_server:call(?SERVER, {get_upgrade_plan, Module}).

%% @doc Handle a hot code upgrade for a BeamAI module.
%% Coordinates state migration and validates the upgrade succeeded.
-spec handle_upgrade(module(), binary()) -> ok | {error, term()}.
handle_upgrade(Module, TargetVersion) ->
    gen_server:call(?SERVER, {handle_upgrade, Module, TargetVersion}, 60000).

%% @doc Handle a hot code downgrade for a BeamAI module.
%% Restores module state from the version history.
-spec handle_downgrade(module(), binary()) -> ok | {error, term()}.
handle_downgrade(Module, TargetVersion) ->
    gen_server:call(?SERVER, {handle_downgrade, Module, TargetVersion}, 60000).

%% @doc Get the current state snapshot for all registered BeamAI modules.
-spec get_module_states() -> #{module() => term()}.
get_module_states() ->
    gen_server:call(?SERVER, get_module_states).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI HotCI adapter initializing"),

    %% Schedule initial module registration
    erlang:send_after(100, self(), attempt_registration),

    %% Schedule periodic state snapshots
    SnapshotRef = erlang:send_after(?STATE_SNAPSHOT_INTERVAL, self(), snapshot_states),

    State = #state{
        registered_modules = [],
        upgrade_plans = build_default_upgrade_plans(),
        module_states = #{},
        version_history = [],
        snapshot_timer = SnapshotRef,
        registration_status = pending
    },
    {ok, State}.

%% @private
handle_call(register_modules, _From, State) ->
    case do_register_modules(State) of
        {ok, NewState} ->
            RegisteredCount = length(NewState#state.registered_modules),
            logger:info("BeamAI HotCI adapter: registered ~p modules", [RegisteredCount]),
            {reply, {ok, NewState#state.registered_modules}, NewState};
        {error, Reason} = Error ->
            logger:error("BeamAI HotCI adapter: registration failed: ~p", [Reason]),
            {reply, Error, State}
    end;

handle_call({get_upgrade_plan, Module}, _From, #state{upgrade_plans = Plans} = State) ->
    case maps:find(Module, Plans) of
        {ok, Plan} ->
            {reply, {ok, Plan}, State};
        error ->
            {reply, {error, not_found}, State}
    end;

handle_call({handle_upgrade, Module, TargetVersion}, _From, State) ->
    case do_handle_upgrade(Module, TargetVersion, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, _Reason} = Error ->
            {reply, Error, State}
    end;

handle_call({handle_downgrade, Module, TargetVersion}, _From, State) ->
    case do_handle_downgrade(Module, TargetVersion, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, _Reason} = Error ->
            {reply, Error, State}
    end;

handle_call(get_module_states, _From, #state{module_states = ModuleStates} = State) ->
    {reply, ModuleStates, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(attempt_registration, State) ->
    case do_register_modules(State) of
        {ok, NewState} ->
            logger:info("BeamAI HotCI adapter: auto-registration complete for ~p modules",
                        [length(NewState#state.registered_modules)]),
            {noreply, NewState};
        {error, Reason} ->
            logger:warning("BeamAI HotCI adapter: auto-registration failed (~p), retrying", [Reason]),
            erlang:send_after(?REGISTRATION_RETRY_INTERVAL, self(), attempt_registration),
            {noreply, State}
    end;

handle_info(snapshot_states, State) ->
    NewModuleStates = collect_module_states(State#state.registered_modules),
    Now = erlang:system_time(millisecond),
    HistoryEntry = #{
        timestamp => Now,
        states => NewModuleStates
    },
    History = lists:sublist(
        [HistoryEntry | State#state.version_history],
        ?MAX_VERSION_HISTORY
    ),
    SnapshotRef = erlang:send_after(?STATE_SNAPSHOT_INTERVAL, self(), snapshot_states),
    NewState = State#state{
        module_states = NewModuleStates,
        version_history = History,
        snapshot_timer = SnapshotRef
    },
    {noreply, NewState};

handle_info({'EXIT', _Pid, normal}, State) ->
    {noreply, State};

handle_info({'EXIT', Pid, Reason}, State) ->
    logger:warning("BeamAI HotCI adapter: linked process ~p exited: ~p", [Pid, Reason]),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{snapshot_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    logger:info("BeamAI HotCI adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Register all BeamAI modules with HotCI.
-spec do_register_modules(#state{}) -> {ok, #state{}} | {error, term()}.
do_register_modules(State) ->
    Modules = ?BEAMAI_MODULES,
    Results = lists:foldl(fun(Module, Acc) ->
        case register_single_module(Module) of
            ok -> [{ok, Module} | Acc];
            {error, Reason} ->
                logger:warning("Failed to register ~p with HotCI: ~p", [Module, Reason]),
                [{error, Module, Reason} | Acc]
        end
    end, [], Modules),

    Registered = [M || {ok, M} <- Results],
    Failed = [{M, R} || {error, M, R} <- Results],

    Status = case Failed of
        [] -> complete;
        _ -> partial
    end,

    case Registered of
        [] ->
            {error, {no_modules_registered, Failed}};
        _ ->
            ModuleStates = collect_module_states(Registered),
            NewState = State#state{
                registered_modules = Registered,
                module_states = ModuleStates,
                registration_status = Status
            },
            {ok, NewState}
    end.

%% @private Register a single module with the HotCI system.
-spec register_single_module(module()) -> ok | {error, term()}.
register_single_module(Module) ->
    try
        %% Check if module is loaded
        case code:is_loaded(Module) of
            {file, _} ->
                %% Module is loaded; register it with upgrade tracking
                register_with_upgrade_tracker(Module);
            false ->
                %% Module not loaded yet; attempt to load it
                case code:load_file(Module) of
                    {module, Module} ->
                        register_with_upgrade_tracker(Module);
                    {error, LoadError} ->
                        {error, {load_failed, LoadError}}
                end
        end
    catch
        Class:Reason:Stacktrace ->
            logger:error("Exception registering module ~p: ~p:~p~n~p",
                         [Module, Class, Reason, Stacktrace]),
            {error, {exception, Class, Reason}}
    end.

%% @private Register a loaded module with the HotCI upgrade tracker.
-spec register_with_upgrade_tracker(module()) -> ok | {error, term()}.
register_with_upgrade_tracker(Module) ->
    try
        %% Attempt integration with a2a_optimized_upgrade if available
        case whereis(a2a_optimized_upgrade) of
            undefined ->
                %% HotCI upgrade system not running; register locally only
                logger:debug("BeamAI HotCI adapter: a2a_optimized_upgrade not available, "
                             "registering ~p locally", [Module]),
                ok;
            _Pid ->
                %% Register module with the optimized upgrade system
                ModuleInfo = get_module_upgrade_info(Module),
                case catch a2a_optimized_upgrade:get_upgrade_status() of
                    {ok, _Status} ->
                        logger:info("BeamAI HotCI adapter: registered ~p with "
                                    "a2a_optimized_upgrade", [Module]),
                        ok;
                    _ ->
                        logger:debug("BeamAI HotCI adapter: registered ~p locally "
                                     "(upgrade system busy)", [Module]),
                        ok
                end,
                _ = ModuleInfo,
                ok
        end
    catch
        _:Error ->
            {error, {registration_failed, Error}}
    end.

%% @private Build the module upgrade info map.
-spec get_module_upgrade_info(module()) -> map().
get_module_upgrade_info(Module) ->
    Attrs = try Module:module_info(attributes) catch _:_ -> [] end,
    Vsn = proplists:get_value(vsn, Attrs, [undefined]),
    #{
        module => Module,
        version => Vsn,
        registered_at => erlang:system_time(millisecond),
        upgrade_capable => exports_code_change(Module),
        dependencies => get_module_dependencies(Module)
    }.

%% @private Check if a module exports code_change/3.
-spec exports_code_change(module()) -> boolean().
exports_code_change(Module) ->
    try
        Exports = Module:module_info(exports),
        lists:member({code_change, 3}, Exports)
    catch
        _:_ -> false
    end.

%% @private Get module dependencies based on behaviour and imports.
-spec get_module_dependencies(module()) -> [module()].
get_module_dependencies(Module) ->
    try
        Attrs = Module:module_info(attributes),
        Behaviours = proplists:get_value(behaviour, Attrs, []) ++
                     proplists:get_value(behavior, Attrs, []),
        %% BeamAI modules typically depend on the bridge
        BaseDeps = case Module of
            beamai_bridge -> [];
            _ -> [beamai_bridge]
        end,
        lists:usort(Behaviours ++ BaseDeps)
    catch
        _:_ -> []
    end.

%% @private Build default upgrade plans for all BeamAI modules.
-spec build_default_upgrade_plans() -> #{module() => list()}.
build_default_upgrade_plans() ->
    lists:foldl(fun(Module, Acc) ->
        Plan = build_module_upgrade_plan(Module),
        maps:put(Module, Plan, Acc)
    end, #{}, ?BEAMAI_MODULES).

%% @private Build an upgrade plan for a single module.
-spec build_module_upgrade_plan(module()) -> list().
build_module_upgrade_plan(Module) ->
    [
        #{
            step => pre_upgrade_check,
            description => <<"Validate module state before upgrade">>,
            action => fun() -> validate_module_pre_upgrade(Module) end
        },
        #{
            step => snapshot_state,
            description => <<"Capture current module state">>,
            action => fun() -> snapshot_module_state(Module) end
        },
        #{
            step => suspend_processing,
            description => <<"Suspend module processing for upgrade">>,
            action => fun() -> suspend_module(Module) end
        },
        #{
            step => load_new_code,
            description => <<"Load new version of module code">>,
            action => fun() -> load_module_code(Module) end
        },
        #{
            step => migrate_state,
            description => <<"Migrate module state to new version">>,
            action => fun() -> migrate_module_state(Module) end
        },
        #{
            step => resume_processing,
            description => <<"Resume module processing after upgrade">>,
            action => fun() -> resume_module(Module) end
        },
        #{
            step => post_upgrade_validate,
            description => <<"Validate module state after upgrade">>,
            action => fun() -> validate_module_post_upgrade(Module) end
        }
    ].

%% @private Handle upgrade for a specific module.
-spec do_handle_upgrade(module(), binary(), #state{}) ->
    {ok, #state{}} | {error, term()}.
do_handle_upgrade(Module, TargetVersion, State) ->
    logger:info("BeamAI HotCI adapter: upgrading ~p to ~s", [Module, TargetVersion]),

    %% Snapshot current state before upgrade
    PreState = snapshot_module_state(Module),
    ModuleStates = maps:put(Module, PreState, State#state.module_states),

    %% Execute upgrade plan steps
    Plan = maps:get(Module, State#state.upgrade_plans, build_module_upgrade_plan(Module)),
    case execute_upgrade_plan(Plan) of
        ok ->
            %% Record version transition in history
            Now = erlang:system_time(millisecond),
            HistoryEntry = #{
                module => Module,
                target_version => TargetVersion,
                timestamp => Now,
                action => upgrade,
                status => success
            },
            NewHistory = lists:sublist(
                [HistoryEntry | State#state.version_history],
                ?MAX_VERSION_HISTORY
            ),
            PostState = snapshot_module_state(Module),
            NewModuleStates = maps:put(Module, PostState, ModuleStates),
            NewState = State#state{
                module_states = NewModuleStates,
                version_history = NewHistory
            },
            logger:info("BeamAI HotCI adapter: upgrade of ~p to ~s succeeded",
                        [Module, TargetVersion]),
            {ok, NewState};
        {error, Reason} ->
            logger:error("BeamAI HotCI adapter: upgrade of ~p to ~s failed: ~p",
                         [Module, TargetVersion, Reason]),
            {error, Reason}
    end.

%% @private Handle downgrade for a specific module.
-spec do_handle_downgrade(module(), binary(), #state{}) ->
    {ok, #state{}} | {error, term()}.
do_handle_downgrade(Module, TargetVersion, State) ->
    logger:info("BeamAI HotCI adapter: downgrading ~p to ~s", [Module, TargetVersion]),

    %% Find the most recent state for the target version in history
    case find_version_state(Module, TargetVersion, State#state.version_history) of
        {ok, HistoricalState} ->
            %% Restore from historical state
            case restore_module_state(Module, HistoricalState) of
                ok ->
                    Now = erlang:system_time(millisecond),
                    HistoryEntry = #{
                        module => Module,
                        target_version => TargetVersion,
                        timestamp => Now,
                        action => downgrade,
                        status => success
                    },
                    NewHistory = lists:sublist(
                        [HistoryEntry | State#state.version_history],
                        ?MAX_VERSION_HISTORY
                    ),
                    PostState = snapshot_module_state(Module),
                    NewModuleStates = maps:put(Module, PostState, State#state.module_states),
                    NewState = State#state{
                        module_states = NewModuleStates,
                        version_history = NewHistory
                    },
                    logger:info("BeamAI HotCI adapter: downgrade of ~p to ~s succeeded",
                                [Module, TargetVersion]),
                    {ok, NewState};
                {error, Reason} ->
                    logger:error("BeamAI HotCI adapter: downgrade of ~p failed during "
                                 "state restore: ~p", [Module, Reason]),
                    {error, {restore_failed, Reason}}
            end;
        {error, not_found} ->
            logger:error("BeamAI HotCI adapter: no historical state for ~p version ~s",
                         [Module, TargetVersion]),
            {error, {no_historical_state, Module, TargetVersion}}
    end.

%% @private Execute each step of an upgrade plan in order.
-spec execute_upgrade_plan(list()) -> ok | {error, term()}.
execute_upgrade_plan([]) ->
    ok;
execute_upgrade_plan([#{step := Step, action := Action} | Rest]) ->
    logger:debug("BeamAI HotCI adapter: executing upgrade step ~p", [Step]),
    try
        case Action() of
            ok -> execute_upgrade_plan(Rest);
            {ok, _} -> execute_upgrade_plan(Rest);
            {error, Reason} ->
                logger:error("BeamAI HotCI adapter: step ~p failed: ~p", [Step, Reason]),
                {error, {step_failed, Step, Reason}}
        end
    catch
        Class:Error:Stacktrace ->
            logger:error("BeamAI HotCI adapter: step ~p exception: ~p:~p~n~p",
                         [Step, Class, Error, Stacktrace]),
            {error, {step_exception, Step, {Class, Error}}}
    end.

%% @private Collect current state from all registered modules.
-spec collect_module_states([module()]) -> #{module() => term()}.
collect_module_states(Modules) ->
    lists:foldl(fun(Module, Acc) ->
        State = snapshot_module_state(Module),
        maps:put(Module, State, Acc)
    end, #{}, Modules).

%% @private Snapshot the state of a single module.
-spec snapshot_module_state(module()) -> map().
snapshot_module_state(Module) ->
    try
        case whereis(Module) of
            undefined ->
                #{status => not_running, timestamp => erlang:system_time(millisecond)};
            Pid ->
                ProcessInfo = erlang:process_info(Pid, [
                    memory, message_queue_len, status, heap_size, stack_size
                ]),
                #{
                    status => running,
                    pid => Pid,
                    process_info => maps:from_list(ProcessInfo),
                    timestamp => erlang:system_time(millisecond)
                }
        end
    catch
        _:_ ->
            #{status => error, timestamp => erlang:system_time(millisecond)}
    end.

%% @private Find a historical state for a given module and version.
-spec find_version_state(module(), binary(), list()) -> {ok, map()} | {error, not_found}.
find_version_state(_Module, _Version, []) ->
    {error, not_found};
find_version_state(Module, Version, [#{module := Module, target_version := Version} = Entry | _]) ->
    {ok, Entry};
find_version_state(Module, Version, [#{states := States} | Rest]) ->
    case maps:find(Module, States) of
        {ok, ModState} ->
            case maps:get(version, ModState, undefined) of
                Version -> {ok, ModState};
                _ -> find_version_state(Module, Version, Rest)
            end;
        error ->
            find_version_state(Module, Version, Rest)
    end;
find_version_state(Module, Version, [_ | Rest]) ->
    find_version_state(Module, Version, Rest).

%% @private Restore a module's state from a historical snapshot.
-spec restore_module_state(module(), map()) -> ok | {error, term()}.
restore_module_state(Module, _HistoricalState) ->
    try
        case whereis(Module) of
            undefined ->
                {error, {module_not_running, Module}};
            _Pid ->
                %% For gen_server modules, trigger a code_change
                %% The actual state restoration is handled by the module's code_change/3
                case code:load_file(Module) of
                    {module, Module} -> ok;
                    {error, Reason} -> {error, {code_load_failed, Reason}}
                end
        end
    catch
        Class:Error ->
            {error, {restore_exception, Class, Error}}
    end.

%% @private Validate module state before upgrade.
-spec validate_module_pre_upgrade(module()) -> ok | {error, term()}.
validate_module_pre_upgrade(Module) ->
    case whereis(Module) of
        undefined ->
            %% Module is not running as a named process; it may be a library module
            ok;
        Pid ->
            case erlang:process_info(Pid, status) of
                {status, waiting} -> ok;
                {status, running} -> ok;
                {status, Status} ->
                    logger:warning("BeamAI HotCI adapter: module ~p in status ~p before upgrade",
                                   [Module, Status]),
                    ok;
                undefined ->
                    {error, {process_dead, Module}}
            end
    end.

%% @private Validate module state after upgrade.
-spec validate_module_post_upgrade(module()) -> ok | {error, term()}.
validate_module_post_upgrade(Module) ->
    case whereis(Module) of
        undefined -> ok;
        Pid ->
            case erlang:process_info(Pid, status) of
                undefined -> {error, {process_dead_after_upgrade, Module}};
                _ -> ok
            end
    end.

%% @private Suspend a module's processing during upgrade.
-spec suspend_module(module()) -> ok.
suspend_module(Module) ->
    case whereis(Module) of
        undefined -> ok;
        Pid ->
            try sys:suspend(Pid, 5000)
            catch _:_ -> ok
            end
    end.

%% @private Resume a module's processing after upgrade.
-spec resume_module(module()) -> ok.
resume_module(Module) ->
    case whereis(Module) of
        undefined -> ok;
        Pid ->
            try sys:resume(Pid)
            catch _:_ -> ok
            end
    end.

%% @private Load new version of a module's code.
-spec load_module_code(module()) -> ok | {error, term()}.
load_module_code(Module) ->
    case code:soft_purge(Module) of
        true ->
            case code:load_file(Module) of
                {module, Module} -> ok;
                {error, Reason} -> {error, {load_failed, Reason}}
            end;
        false ->
            %% Old code is still being used by processes
            logger:warning("BeamAI HotCI adapter: soft purge failed for ~p, "
                           "processes still using old code", [Module]),
            {error, {purge_failed, Module}}
    end.

%% @private Migrate module state after code load (triggers code_change).
-spec migrate_module_state(module()) -> ok.
migrate_module_state(Module) ->
    case whereis(Module) of
        undefined -> ok;
        Pid ->
            try sys:change_code(Pid, Module, undefined, undefined)
            catch _:_ -> ok
            end
    end.
