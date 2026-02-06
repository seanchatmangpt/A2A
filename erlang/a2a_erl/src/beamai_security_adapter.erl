%%% @doc BeamAI Security Adapter - Security Validation and Audit
%%%
%%% This module provides security features for BeamAI components and
%%% integrates with the existing a2a_hotci_security system. It validates
%%% BeamAI module integrity during upgrades, audits tool execution,
%%% checks API key security, and enforces security policies.
%%%
%%% The adapter maintains an audit trail of all security-relevant events
%%% and can generate security reports for compliance purposes.
%%%
%%% @end
-module(beamai_security_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    validate_modules/0,
    audit_tool_call/2,
    check_api_keys/0,
    get_security_report/0,
    set_policy/1
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
-define(AUDIT_LOG_MAX, 10000).
-define(INTEGRITY_CHECK_INTERVAL, 300000).
-define(MAX_REPORT_ENTRIES, 100).

-record(audit_entry, {
    id :: binary(),
    timestamp :: integer(),
    event_type :: atom(),
    module :: module() | undefined,
    tool_name :: binary() | undefined,
    details :: map(),
    risk_level :: low | medium | high | critical,
    source :: atom()
}).

-record(security_policy, {
    require_module_integrity :: boolean(),
    require_api_key_validation :: boolean(),
    audit_tool_calls :: boolean(),
    max_tool_call_rate :: non_neg_integer(),
    allowed_modules :: [module()] | all,
    blocked_modules :: [module()],
    require_signed_upgrades :: boolean(),
    integrity_check_interval_ms :: non_neg_integer()
}).

-record(state, {
    policy :: #security_policy{},
    audit_log :: [#audit_entry{}],
    audit_count :: non_neg_integer(),
    module_hashes :: #{module() => binary()},
    last_integrity_check :: integer() | undefined,
    integrity_timer :: reference() | undefined,
    tool_call_rates :: #{binary() => {non_neg_integer(), integer()}},
    security_events :: [map()],
    api_key_status :: map()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the security adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Validate integrity of all registered BeamAI modules.
-spec validate_modules() -> {ok, map()} | {error, term()}.
validate_modules() ->
    gen_server:call(?SERVER, validate_modules, 30000).

%% @doc Audit a tool call execution.
-spec audit_tool_call(binary(), map()) -> ok.
audit_tool_call(ToolName, Details) ->
    gen_server:cast(?SERVER, {audit_tool_call, ToolName, Details}).

%% @doc Check the security status of API keys.
-spec check_api_keys() -> {ok, map()} | {error, term()}.
check_api_keys() ->
    gen_server:call(?SERVER, check_api_keys).

%% @doc Generate a comprehensive security report.
-spec get_security_report() -> {ok, map()}.
get_security_report() ->
    gen_server:call(?SERVER, get_security_report, 10000).

%% @doc Set the security policy.
-spec set_policy(map()) -> ok | {error, term()}.
set_policy(PolicyMap) ->
    gen_server:call(?SERVER, {set_policy, PolicyMap}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI security adapter initializing"),

    DefaultPolicy = #security_policy{
        require_module_integrity = true,
        require_api_key_validation = true,
        audit_tool_calls = true,
        max_tool_call_rate = 1000,
        allowed_modules = all,
        blocked_modules = [],
        require_signed_upgrades = false,
        integrity_check_interval_ms = ?INTEGRITY_CHECK_INTERVAL
    },

    %% Compute initial module hashes
    ModuleHashes = compute_all_module_hashes(),

    TimerRef = erlang:send_after(
        DefaultPolicy#security_policy.integrity_check_interval_ms,
        self(), integrity_check
    ),

    State = #state{
        policy = DefaultPolicy,
        audit_log = [],
        audit_count = 0,
        module_hashes = ModuleHashes,
        last_integrity_check = erlang:system_time(millisecond),
        integrity_timer = TimerRef,
        tool_call_rates = #{},
        security_events = [],
        api_key_status = #{status => unchecked}
    },

    %% Log security adapter startup as an audit event
    StartEntry = #audit_entry{
        id = generate_audit_id(),
        timestamp = erlang:system_time(millisecond),
        event_type = system_start,
        module = ?MODULE,
        tool_name = undefined,
        details = #{message => <<"Security adapter started">>},
        risk_level = low,
        source = system
    },
    {ok, State#state{audit_log = [StartEntry]}}.

%% @private
handle_call(validate_modules, _From, State) ->
    {Result, NewState} = do_validate_modules(State),
    {reply, {ok, Result}, NewState};

handle_call(check_api_keys, _From, State) ->
    {Result, NewState} = do_check_api_keys(State),
    {reply, {ok, Result}, NewState};

handle_call(get_security_report, _From, State) ->
    Report = build_security_report(State),
    {reply, {ok, Report}, State};

handle_call({set_policy, PolicyMap}, _From, State) ->
    case update_security_policy(PolicyMap, State) of
        {ok, NewState} ->
            %% Audit the policy change
            Entry = #audit_entry{
                id = generate_audit_id(),
                timestamp = erlang:system_time(millisecond),
                event_type = policy_change,
                module = ?MODULE,
                tool_name = undefined,
                details = #{new_policy => PolicyMap},
                risk_level = medium,
                source = api
            },
            AuditLog = bounded_prepend(Entry, NewState#state.audit_log, ?AUDIT_LOG_MAX),
            {reply, ok, NewState#state{audit_log = AuditLog}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({audit_tool_call, ToolName, Details}, State) ->
    NewState = do_audit_tool_call(ToolName, Details, State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(integrity_check, State) ->
    {_Result, NewState} = do_validate_modules(State),
    TimerRef = erlang:send_after(
        NewState#state.policy#security_policy.integrity_check_interval_ms,
        self(), integrity_check
    ),
    {noreply, NewState#state{integrity_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{integrity_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    logger:info("BeamAI security adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions - Module Validation
%%%===================================================================

%% @private Validate all BeamAI module integrity.
-spec do_validate_modules(#state{}) -> {map(), #state{}}.
do_validate_modules(State) ->
    BeamaiModules = get_beamai_modules(),
    Now = erlang:system_time(millisecond),

    Results = lists:map(fun(Module) ->
        validate_single_module(Module, State#state.module_hashes)
    end, BeamaiModules),

    ValidCount = length([R || #{status := valid} = R <- Results]),
    InvalidCount = length([R || #{status := invalid} = R <- Results]),
    WarningCount = length([R || #{status := warning} = R <- Results]),

    OverallStatus = if
        InvalidCount > 0 -> invalid;
        WarningCount > 0 -> warning;
        ValidCount > 0 -> valid;
        true -> unknown
    end,

    %% Update module hashes with current values
    NewHashes = compute_all_module_hashes(),

    %% Create audit entry for the validation
    Entry = #audit_entry{
        id = generate_audit_id(),
        timestamp = Now,
        event_type = module_validation,
        module = ?MODULE,
        tool_name = undefined,
        details = #{
            overall_status => OverallStatus,
            valid_count => ValidCount,
            invalid_count => InvalidCount,
            warning_count => WarningCount
        },
        risk_level = case OverallStatus of
            invalid -> high;
            warning -> medium;
            _ -> low
        end,
        source = system
    },
    AuditLog = bounded_prepend(Entry, State#state.audit_log, ?AUDIT_LOG_MAX),

    %% Forward to a2a_hotci_security if available
    forward_to_hotci_security(OverallStatus, Results),

    Result = #{
        overall_status => OverallStatus,
        valid_count => ValidCount,
        invalid_count => InvalidCount,
        warning_count => WarningCount,
        module_results => Results,
        timestamp => Now
    },

    NewState = State#state{
        module_hashes = NewHashes,
        last_integrity_check = Now,
        audit_log = AuditLog,
        audit_count = State#state.audit_count + 1
    },

    {Result, NewState}.

%% @private Validate a single module's integrity.
-spec validate_single_module(module(), #{module() => binary()}) -> map().
validate_single_module(Module, StoredHashes) ->
    try
        case code:is_loaded(Module) of
            {file, BeamFile} ->
                %% Compute current hash of the module
                CurrentHash = compute_module_hash(Module),
                StoredHash = maps:get(Module, StoredHashes, undefined),

                %% Check if hash has changed since last check
                HashChanged = (StoredHash =/= undefined) andalso (StoredHash =/= CurrentHash),

                %% Verify the beam file exists
                FileExists = filelib:is_regular(BeamFile),

                %% Check module exports code_change for upgrade safety
                HasCodeChange = lists:member({code_change, 3},
                    try Module:module_info(exports) catch _:_ -> [] end),

                Status = if
                    HashChanged -> warning;
                    not FileExists -> warning;
                    true -> valid
                end,

                #{
                    module => Module,
                    status => Status,
                    beam_file => list_to_binary(BeamFile),
                    file_exists => FileExists,
                    has_code_change => HasCodeChange,
                    hash_changed => HashChanged,
                    current_hash => base64:encode(CurrentHash)
                };
            false ->
                #{
                    module => Module,
                    status => warning,
                    reason => not_loaded
                }
        end
    catch
        _:Error ->
            #{
                module => Module,
                status => invalid,
                error => list_to_binary(io_lib:format("~p", [Error]))
            }
    end.

%%%===================================================================
%%% Internal Functions - API Key Check
%%%===================================================================

%% @private Check API key security.
-spec do_check_api_keys(#state{}) -> {map(), #state{}}.
do_check_api_keys(State) ->
    Now = erlang:system_time(millisecond),

    %% Check environment variables for API keys
    EnvChecks = check_env_api_keys(),

    %% Check application config for API keys
    AppConfigChecks = check_app_config_keys(),

    OverallStatus = case lists:any(fun(#{status := S}) -> S =:= exposed end,
                                   EnvChecks ++ AppConfigChecks) of
        true -> insecure;
        false -> secure
    end,

    Result = #{
        overall_status => OverallStatus,
        environment_checks => EnvChecks,
        app_config_checks => AppConfigChecks,
        timestamp => Now
    },

    %% Audit the key check
    Entry = #audit_entry{
        id = generate_audit_id(),
        timestamp = Now,
        event_type = api_key_check,
        module = ?MODULE,
        tool_name = undefined,
        details = #{status => OverallStatus},
        risk_level = case OverallStatus of
            insecure -> critical;
            _ -> low
        end,
        source = api
    },
    AuditLog = bounded_prepend(Entry, State#state.audit_log, ?AUDIT_LOG_MAX),

    {Result, State#state{
        api_key_status = Result,
        audit_log = AuditLog
    }}.

%% @private Check environment variables for exposed API keys.
-spec check_env_api_keys() -> [map()].
check_env_api_keys() ->
    KeyPatterns = [
        {"BEAMAI_API_KEY", <<"BeamAI API key">>},
        {"OPENAI_API_KEY", <<"OpenAI API key">>},
        {"ANTHROPIC_API_KEY", <<"Anthropic API key">>},
        {"LLM_API_KEY", <<"LLM API key">>}
    ],
    lists:map(fun({EnvVar, Label}) ->
        case os:getenv(EnvVar) of
            false ->
                #{name => Label, env_var => list_to_binary(EnvVar),
                  status => not_set};
            "" ->
                #{name => Label, env_var => list_to_binary(EnvVar),
                  status => empty};
            Value when length(Value) < 10 ->
                #{name => Label, env_var => list_to_binary(EnvVar),
                  status => suspicious, reason => <<"Key too short">>};
            _Value ->
                #{name => Label, env_var => list_to_binary(EnvVar),
                  status => present, key_length => masked}
        end
    end, KeyPatterns).

%% @private Check application configuration for exposed keys.
-spec check_app_config_keys() -> [map()].
check_app_config_keys() ->
    Apps = [a2a_erl, beamai],
    lists:flatmap(fun(App) ->
        try
            Env = application:get_all_env(App),
            SensitiveKeys = lists:filter(fun({Key, _}) ->
                KeyStr = atom_to_list(Key),
                lists:any(fun(Pattern) ->
                    string:find(KeyStr, Pattern) =/= nomatch
                end, ["api_key", "secret", "password", "token"])
            end, Env),
            lists:map(fun({Key, _Value}) ->
                #{app => App, key => Key, status => present_in_config,
                  recommendation => <<"Use environment variables instead">>}
            end, SensitiveKeys)
        catch
            _:_ -> []
        end
    end, Apps).

%%%===================================================================
%%% Internal Functions - Tool Call Audit
%%%===================================================================

%% @private Record a tool call in the audit log.
-spec do_audit_tool_call(binary(), map(), #state{}) -> #state{}.
do_audit_tool_call(ToolName, Details, State) ->
    Now = erlang:system_time(millisecond),
    Policy = State#state.policy,

    case Policy#security_policy.audit_tool_calls of
        false -> State;
        true ->
            %% Check rate limiting
            RateStatus = check_tool_call_rate(ToolName, State#state.tool_call_rates, Policy),

            RiskLevel = case RateStatus of
                ok -> low;
                rate_limited -> high
            end,

            Entry = #audit_entry{
                id = generate_audit_id(),
                timestamp = Now,
                event_type = tool_call,
                module = undefined,
                tool_name = ToolName,
                details = Details#{rate_status => RateStatus},
                risk_level = RiskLevel,
                source = tool
            },

            AuditLog = bounded_prepend(Entry, State#state.audit_log, ?AUDIT_LOG_MAX),

            %% Update rate tracking
            CurrentRate = maps:get(ToolName, State#state.tool_call_rates, {0, Now}),
            {Count, WindowStart} = CurrentRate,
            NewRate = case Now - WindowStart > 60000 of
                true -> {1, Now};
                false -> {Count + 1, WindowStart}
            end,
            NewRates = maps:put(ToolName, NewRate, State#state.tool_call_rates),

            %% Forward to a2a_hotci_security if high risk
            case RiskLevel of
                high ->
                    forward_security_event(tool_call_rate_limit, #{
                        tool => ToolName,
                        rate => Count + 1
                    });
                _ -> ok
            end,

            State#state{
                audit_log = AuditLog,
                audit_count = State#state.audit_count + 1,
                tool_call_rates = NewRates
            }
    end.

%% @private Check if a tool call exceeds the rate limit.
-spec check_tool_call_rate(binary(), map(), #security_policy{}) -> ok | rate_limited.
check_tool_call_rate(ToolName, Rates, Policy) ->
    Now = erlang:system_time(millisecond),
    case maps:find(ToolName, Rates) of
        {ok, {Count, WindowStart}} ->
            case Now - WindowStart > 60000 of
                true -> ok;
                false ->
                    case Count >= Policy#security_policy.max_tool_call_rate of
                        true -> rate_limited;
                        false -> ok
                    end
            end;
        error ->
            ok
    end.

%%%===================================================================
%%% Internal Functions - Security Report
%%%===================================================================

%% @private Build a comprehensive security report.
-spec build_security_report(#state{}) -> map().
build_security_report(State) ->
    Now = erlang:system_time(millisecond),

    %% Analyze audit log for recent events
    RecentEvents = lists:sublist(State#state.audit_log, ?MAX_REPORT_ENTRIES),
    EventsByType = group_events_by_type(RecentEvents),

    %% Count by risk level
    RiskCounts = lists:foldl(fun(#audit_entry{risk_level = Level}, Acc) ->
        Current = maps:get(Level, Acc, 0),
        maps:put(Level, Current + 1, Acc)
    end, #{}, RecentEvents),

    %% High risk events
    HighRiskEvents = [audit_entry_to_map(E) || E <- RecentEvents,
                      E#audit_entry.risk_level =:= high orelse
                      E#audit_entry.risk_level =:= critical],

    #{
        timestamp => Now,
        total_audit_entries => State#state.audit_count,
        policy => security_policy_to_map(State#state.policy),
        last_integrity_check => State#state.last_integrity_check,
        module_hash_count => maps:size(State#state.module_hashes),
        api_key_status => State#state.api_key_status,
        risk_summary => RiskCounts,
        high_risk_events => lists:sublist(HighRiskEvents, 20),
        events_by_type => EventsByType,
        active_rate_limits => maps:size(State#state.tool_call_rates)
    }.

%% @private Group events by type.
-spec group_events_by_type([#audit_entry{}]) -> map().
group_events_by_type(Entries) ->
    lists:foldl(fun(#audit_entry{event_type = Type}, Acc) ->
        Current = maps:get(Type, Acc, 0),
        maps:put(Type, Current + 1, Acc)
    end, #{}, Entries).

%%%===================================================================
%%% Internal Functions - Utilities
%%%===================================================================

%% @private Get the list of BeamAI modules to validate.
-spec get_beamai_modules() -> [module()].
get_beamai_modules() ->
    [
        beamai_bridge,
        beamai_hotci_adapter,
        beamai_health_adapter,
        beamai_metrics_adapter,
        beamai_integrity_adapter,
        beamai_disaster_recovery_adapter,
        beamai_security_adapter,
        beamai_monitoring_adapter,
        beamai_benchmark_adapter,
        beamai_enterprise_sup
    ].

%% @private Compute hashes for all BeamAI modules.
-spec compute_all_module_hashes() -> #{module() => binary()}.
compute_all_module_hashes() ->
    Modules = get_beamai_modules(),
    lists:foldl(fun(Module, Acc) ->
        Hash = compute_module_hash(Module),
        maps:put(Module, Hash, Acc)
    end, #{}, Modules).

%% @private Compute the hash of a module's BEAM bytecode.
-spec compute_module_hash(module()) -> binary().
compute_module_hash(Module) ->
    try
        case code:get_object_code(Module) of
            {Module, Binary, _Filename} ->
                crypto:hash(sha256, Binary);
            error ->
                <<>>
        end
    catch
        _:_ -> <<>>
    end.

%% @private Generate a unique audit entry ID.
-spec generate_audit_id() -> binary().
generate_audit_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"audit-", Hex/binary>>.

%% @private Prepend to a list with a maximum size bound.
-spec bounded_prepend(term(), list(), non_neg_integer()) -> list().
bounded_prepend(Item, List, MaxSize) ->
    lists:sublist([Item | List], MaxSize).

%% @private Convert an audit entry record to a map.
-spec audit_entry_to_map(#audit_entry{}) -> map().
audit_entry_to_map(#audit_entry{
    id = Id,
    timestamp = Timestamp,
    event_type = EventType,
    module = Module,
    tool_name = ToolName,
    details = Details,
    risk_level = RiskLevel,
    source = Source
}) ->
    #{
        id => Id,
        timestamp => Timestamp,
        event_type => EventType,
        module => Module,
        tool_name => ToolName,
        details => Details,
        risk_level => RiskLevel,
        source => Source
    }.

%% @private Convert security policy to a map.
-spec security_policy_to_map(#security_policy{}) -> map().
security_policy_to_map(#security_policy{
    require_module_integrity = ReqIntegrity,
    require_api_key_validation = ReqApiKey,
    audit_tool_calls = AuditCalls,
    max_tool_call_rate = MaxRate,
    allowed_modules = Allowed,
    blocked_modules = Blocked,
    require_signed_upgrades = ReqSigned,
    integrity_check_interval_ms = Interval
}) ->
    #{
        require_module_integrity => ReqIntegrity,
        require_api_key_validation => ReqApiKey,
        audit_tool_calls => AuditCalls,
        max_tool_call_rate => MaxRate,
        allowed_modules => Allowed,
        blocked_modules => Blocked,
        require_signed_upgrades => ReqSigned,
        integrity_check_interval_ms => Interval
    }.

%% @private Update security policy from a map.
-spec update_security_policy(map(), #state{}) -> {ok, #state{}} | {error, term()}.
update_security_policy(PolicyMap, State) ->
    try
        Old = State#state.policy,
        New = Old#security_policy{
            require_module_integrity = maps:get(require_module_integrity, PolicyMap,
                                                Old#security_policy.require_module_integrity),
            require_api_key_validation = maps:get(require_api_key_validation, PolicyMap,
                                                  Old#security_policy.require_api_key_validation),
            audit_tool_calls = maps:get(audit_tool_calls, PolicyMap,
                                        Old#security_policy.audit_tool_calls),
            max_tool_call_rate = maps:get(max_tool_call_rate, PolicyMap,
                                          Old#security_policy.max_tool_call_rate),
            allowed_modules = maps:get(allowed_modules, PolicyMap,
                                       Old#security_policy.allowed_modules),
            blocked_modules = maps:get(blocked_modules, PolicyMap,
                                       Old#security_policy.blocked_modules),
            require_signed_upgrades = maps:get(require_signed_upgrades, PolicyMap,
                                               Old#security_policy.require_signed_upgrades),
            integrity_check_interval_ms = maps:get(integrity_check_interval_ms, PolicyMap,
                                                   Old#security_policy.integrity_check_interval_ms)
        },

        %% Reschedule integrity check timer if interval changed
        NewTimer = case New#security_policy.integrity_check_interval_ms =/=
                        Old#security_policy.integrity_check_interval_ms of
            true ->
                case State#state.integrity_timer of
                    undefined -> ok;
                    OldRef -> erlang:cancel_timer(OldRef)
                end,
                erlang:send_after(New#security_policy.integrity_check_interval_ms,
                                  self(), integrity_check);
            false ->
                State#state.integrity_timer
        end,

        {ok, State#state{policy = New, integrity_timer = NewTimer}}
    catch
        _:Error ->
            {error, {invalid_policy, Error}}
    end.

%% @private Forward a security event to a2a_hotci_security.
-spec forward_security_event(atom(), map()) -> ok.
forward_security_event(EventType, Details) ->
    try
        case whereis(a2a_hotci_security) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI security adapter: forwarding ~p event to "
                             "a2a_hotci_security", [EventType]),
                catch a2a_hotci_security:audit_security_event(
                    atom_to_binary(EventType),
                    <<"BeamAI security event">>,
                    Details
                ),
                ok
        end
    catch
        _:_ -> ok
    end.

%% @private Forward module validation results to a2a_hotci_security.
-spec forward_to_hotci_security(atom(), [map()]) -> ok.
forward_to_hotci_security(OverallStatus, _Results) ->
    try
        case whereis(a2a_hotci_security) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI security adapter: forwarding module validation "
                             "(~p) to a2a_hotci_security", [OverallStatus]),
                ok
        end
    catch
        _:_ -> ok
    end.
