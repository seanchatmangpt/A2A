%%%-------------------------------------------------------------------
%%% @doc BeamAI Tool Security and Sandboxing.
%%%
%%% Provides security controls for tool execution:
%%% - Permission checking before tool execution
%%% - Input sanitization to prevent injection
%%% - Output filtering to remove sensitive data
%%% - Rate limiting per tool to prevent abuse
%%% - Role-based access control (RBAC)
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tool_security).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    check_permission/2,
    sanitize_input/2,
    filter_output/2,
    rate_check/2,
    set_policy/2,
    get_policy/1,
    grant_role/3,
    revoke_role/3,
    add_sensitive_pattern/1,
    reset_rate_limits/0
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

-define(SERVER, ?MODULE).
-define(RATE_TABLE, beamai_tool_rate_limits).
-define(POLICY_TABLE, beamai_tool_policies).
-define(ROLE_TABLE, beamai_tool_roles).

%%====================================================================
%% Records
%%====================================================================

-record(rate_entry, {
    key        :: {binary(), term()},
    count      :: non_neg_integer(),
    window_start :: integer()
}).

-record(policy, {
    tool_name      :: binary(),
    allowed_roles  :: [binary()],
    rate_limit     :: non_neg_integer(),
    rate_window_ms :: non_neg_integer(),
    input_rules    :: [map()],
    output_rules   :: [map()],
    sandbox        :: boolean()
}).

-record(state, {
    enable_security :: boolean(),
    default_rate_limit :: non_neg_integer(),
    rate_window_ms :: non_neg_integer(),
    sensitive_patterns :: [binary()],
    cleanup_timer :: reference() | undefined
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the security server with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the security server with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Check if the current context has permission to execute a tool.
%% Context should contain at minimum a 'caller' or 'role' key.
-spec check_permission(binary(), map()) -> ok | {error, term()}.
check_permission(ToolName, Context) ->
    gen_server:call(?SERVER, {check_permission, ensure_binary(ToolName), Context}).

%% @doc Sanitize input for a tool, removing potentially dangerous content.
%% Returns sanitized input map.
-spec sanitize_input(binary(), map()) -> map().
sanitize_input(ToolName, Input) ->
    case catch gen_server:call(?SERVER, {sanitize_input, ensure_binary(ToolName), Input}) of
        {'EXIT', _} -> Input;
        Sanitized -> Sanitized
    end.

%% @doc Filter output from a tool, removing sensitive data.
-spec filter_output(binary(), term()) -> term().
filter_output(ToolName, Output) ->
    case catch gen_server:call(?SERVER, {filter_output, ensure_binary(ToolName), Output}) of
        {'EXIT', _} -> Output;
        Filtered -> Filtered
    end.

%% @doc Check rate limit for a tool invocation.
-spec rate_check(binary(), map()) -> ok | {error, rate_limited}.
rate_check(ToolName, Context) ->
    gen_server:call(?SERVER, {rate_check, ensure_binary(ToolName), Context}).

%% @doc Set a security policy for a tool.
-spec set_policy(binary(), map()) -> ok.
set_policy(ToolName, Policy) ->
    gen_server:call(?SERVER, {set_policy, ensure_binary(ToolName), Policy}).

%% @doc Get the security policy for a tool.
-spec get_policy(binary()) -> {ok, map()} | {error, not_found}.
get_policy(ToolName) ->
    gen_server:call(?SERVER, {get_policy, ensure_binary(ToolName)}).

%% @doc Grant a role permission to use a tool.
-spec grant_role(binary(), binary(), binary()) -> ok.
grant_role(ToolName, Role, _GrantedBy) ->
    gen_server:call(?SERVER, {grant_role, ensure_binary(ToolName), ensure_binary(Role)}).

%% @doc Revoke a role's permission to use a tool.
-spec revoke_role(binary(), binary(), binary()) -> ok.
revoke_role(ToolName, Role, _RevokedBy) ->
    gen_server:call(?SERVER, {revoke_role, ensure_binary(ToolName), ensure_binary(Role)}).

%% @doc Add a sensitive pattern to be redacted from outputs.
-spec add_sensitive_pattern(binary()) -> ok.
add_sensitive_pattern(Pattern) ->
    gen_server:cast(?SERVER, {add_sensitive_pattern, Pattern}).

%% @doc Reset all rate limit counters.
-spec reset_rate_limits() -> ok.
reset_rate_limits() ->
    gen_server:cast(?SERVER, reset_rate_limits).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    %% Create ETS tables
    ets:new(?RATE_TABLE, [named_table, set, public]),
    ets:new(?POLICY_TABLE, [named_table, set, public, {read_concurrency, true}]),
    ets:new(?ROLE_TABLE, [named_table, bag, public, {read_concurrency, true}]),

    EnableSecurity = maps:get(enable_security, Opts,
                    application:get_env(beamai_tools, enable_security, true)),
    DefaultRateLimit = maps:get(default_rate_limit, Opts,
                      application:get_env(beamai_tools, default_rate_limit, 100)),
    RateWindow = maps:get(rate_window_ms, Opts,
                 application:get_env(beamai_tools, rate_limit_window_ms, 60000)),

    %% Default sensitive patterns (API keys, tokens, etc.)
    DefaultPatterns = [
        <<"sk-[a-zA-Z0-9]{20,}">>,
        <<"Bearer [a-zA-Z0-9._-]+">>,
        <<"password\\s*[=:]\\s*\\S+">>,
        <<"secret\\s*[=:]\\s*\\S+">>
    ],

    %% Schedule periodic cleanup of expired rate limit entries
    {ok, TimerRef} = timer:send_interval(RateWindow, cleanup_rate_limits),

    logger:info("BeamAI tool security started (enabled: ~p, rate_limit: ~p/~pms)",
                [EnableSecurity, DefaultRateLimit, RateWindow]),

    {ok, #state{
        enable_security = EnableSecurity,
        default_rate_limit = DefaultRateLimit,
        rate_window_ms = RateWindow,
        sensitive_patterns = maps:get(sensitive_patterns, Opts, DefaultPatterns),
        cleanup_timer = TimerRef
    }}.

%% @private
handle_call({check_permission, ToolName, Context}, _From, State) ->
    Result = case State#state.enable_security of
        false -> ok;
        true -> do_check_permission(ToolName, Context)
    end,
    {reply, Result, State};

handle_call({sanitize_input, ToolName, Input}, _From, State) ->
    Result = case State#state.enable_security of
        false -> Input;
        true -> do_sanitize_input(ToolName, Input, State)
    end,
    {reply, Result, State};

handle_call({filter_output, ToolName, Output}, _From, State) ->
    Result = case State#state.enable_security of
        false -> Output;
        true -> do_filter_output(ToolName, Output, State)
    end,
    {reply, Result, State};

handle_call({rate_check, ToolName, Context}, _From, State) ->
    Result = do_rate_check(ToolName, Context, State),
    {reply, Result, State};

handle_call({set_policy, ToolName, PolicyMap}, _From, State) ->
    Policy = #policy{
        tool_name = ToolName,
        allowed_roles = maps:get(allowed_roles, PolicyMap, [<<"admin">>, <<"agent">>]),
        rate_limit = maps:get(rate_limit, PolicyMap, State#state.default_rate_limit),
        rate_window_ms = maps:get(rate_window_ms, PolicyMap, State#state.rate_window_ms),
        input_rules = maps:get(input_rules, PolicyMap, []),
        output_rules = maps:get(output_rules, PolicyMap, []),
        sandbox = maps:get(sandbox, PolicyMap, false)
    },
    ets:insert(?POLICY_TABLE, {ToolName, Policy}),
    {reply, ok, State};

handle_call({get_policy, ToolName}, _From, State) ->
    Result = case ets:lookup(?POLICY_TABLE, ToolName) of
        [{_, Policy}] -> {ok, policy_to_map(Policy)};
        [] -> {error, not_found}
    end,
    {reply, Result, State};

handle_call({grant_role, ToolName, Role}, _From, State) ->
    ets:insert(?ROLE_TABLE, {{ToolName, Role}}),
    {reply, ok, State};

handle_call({revoke_role, ToolName, Role}, _From, State) ->
    ets:delete_object(?ROLE_TABLE, {{ToolName, Role}}),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({add_sensitive_pattern, Pattern}, State) ->
    Patterns = State#state.sensitive_patterns,
    {noreply, State#state{sensitive_patterns = [Pattern | Patterns]}};

handle_cast(reset_rate_limits, State) ->
    ets:delete_all_objects(?RATE_TABLE),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(cleanup_rate_limits, State) ->
    Now = erlang:monotonic_time(millisecond),
    Window = State#state.rate_window_ms,
    %% Delete expired entries
    ets:foldl(fun({Key, Entry}, Acc) ->
        case Now - Entry#rate_entry.window_start > Window of
            true -> ets:delete(?RATE_TABLE, Key);
            false -> ok
        end,
        Acc
    end, ok, ?RATE_TABLE),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.cleanup_timer of
        undefined -> ok;
        Ref -> timer:cancel(Ref)
    end,
    catch ets:delete(?RATE_TABLE),
    catch ets:delete(?POLICY_TABLE),
    catch ets:delete(?ROLE_TABLE),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Permission Checking
%%====================================================================

%% @private
do_check_permission(ToolName, Context) ->
    CallerRole = maps:get(role, Context, maps:get(<<"role">>, Context, <<"anonymous">>)),
    CallerRoleBin = ensure_binary(CallerRole),

    %% Check tool-specific policy first
    case ets:lookup(?POLICY_TABLE, ToolName) of
        [{_, #policy{allowed_roles = AllowedRoles}}] ->
            case AllowedRoles of
                [] -> ok;  %% No role restriction
                _ ->
                    case lists:member(CallerRoleBin, AllowedRoles) of
                        true -> ok;
                        false ->
                            %% Check explicit grants
                            case ets:match(?ROLE_TABLE, {{ToolName, CallerRoleBin}}) of
                                [_|_] -> ok;
                                [] -> {error, {permission_denied, ToolName, CallerRoleBin}}
                            end
                    end
            end;
        [] ->
            %% No policy defined: allow by default (admin and agent roles)
            case lists:member(CallerRoleBin, [<<"admin">>, <<"agent">>, <<"system">>]) of
                true -> ok;
                false -> ok  %% Default permissive
            end
    end.

%%====================================================================
%% Internal Functions - Input Sanitization
%%====================================================================

%% @private
do_sanitize_input(ToolName, Input, State) when is_map(Input) ->
    %% Get tool-specific input rules
    InputRules = case ets:lookup(?POLICY_TABLE, ToolName) of
        [{_, #policy{input_rules = Rules}}] -> Rules;
        [] -> []
    end,

    %% Apply default sanitization
    Sanitized1 = sanitize_map_values(Input, State#state.sensitive_patterns),

    %% Apply tool-specific rules
    lists:foldl(fun(Rule, Acc) ->
        apply_input_rule(Rule, Acc)
    end, Sanitized1, InputRules);
do_sanitize_input(_ToolName, Input, _State) ->
    Input.

%% @private
sanitize_map_values(Map, _Patterns) when is_map(Map) ->
    maps:map(fun(_Key, Value) ->
        sanitize_value(Value)
    end, Map);
sanitize_map_values(Other, _Patterns) ->
    Other.

%% @private
sanitize_value(Value) when is_binary(Value) ->
    %% Trim excessive whitespace, limit length
    Trimmed = string:trim(Value),
    case byte_size(Trimmed) > 100000 of
        true -> binary:part(Trimmed, 0, 100000);
        false -> Trimmed
    end;
sanitize_value(Value) when is_map(Value) ->
    maps:map(fun(_K, V) -> sanitize_value(V) end, Value);
sanitize_value(Value) when is_list(Value) ->
    [sanitize_value(V) || V <- Value];
sanitize_value(Value) ->
    Value.

%% @private
apply_input_rule(#{type := max_length, field := Field, max := Max}, Input) ->
    case maps:find(Field, Input) of
        {ok, Value} when is_binary(Value), byte_size(Value) > Max ->
            Input#{Field => binary:part(Value, 0, Max)};
        _ ->
            Input
    end;
apply_input_rule(#{type := strip_field, field := Field}, Input) ->
    maps:remove(Field, Input);
apply_input_rule(#{type := required, field := Field}, Input) ->
    case maps:is_key(Field, Input) of
        true -> Input;
        false -> Input  %% Validation is handled elsewhere
    end;
apply_input_rule(_, Input) ->
    Input.

%%====================================================================
%% Internal Functions - Output Filtering
%%====================================================================

%% @private
do_filter_output(ToolName, Output, State) ->
    %% Get tool-specific output rules
    OutputRules = case ets:lookup(?POLICY_TABLE, ToolName) of
        [{_, #policy{output_rules = Rules}}] -> Rules;
        [] -> []
    end,

    %% Apply sensitive pattern redaction
    Filtered1 = redact_sensitive(Output, State#state.sensitive_patterns),

    %% Apply tool-specific rules
    lists:foldl(fun(Rule, Acc) ->
        apply_output_rule(Rule, Acc)
    end, Filtered1, OutputRules).

%% @private
redact_sensitive(Output, Patterns) when is_binary(Output) ->
    lists:foldl(fun(Pattern, Acc) ->
        try
            re:replace(Acc, Pattern, <<"[REDACTED]">>, [global, {return, binary}])
        catch
            _:_ -> Acc
        end
    end, Output, Patterns);
redact_sensitive(Output, Patterns) when is_map(Output) ->
    maps:map(fun(_K, V) -> redact_sensitive(V, Patterns) end, Output);
redact_sensitive(Output, Patterns) when is_list(Output) ->
    [redact_sensitive(V, Patterns) || V <- Output];
redact_sensitive(Output, _Patterns) ->
    Output.

%% @private
apply_output_rule(#{type := strip_field, field := Field}, Output) when is_map(Output) ->
    maps:remove(Field, Output);
apply_output_rule(#{type := max_length, field := Field, max := Max}, Output) when is_map(Output) ->
    case maps:find(Field, Output) of
        {ok, Value} when is_binary(Value), byte_size(Value) > Max ->
            Output#{Field => binary:part(Value, 0, Max)};
        _ ->
            Output
    end;
apply_output_rule(_, Output) ->
    Output.

%%====================================================================
%% Internal Functions - Rate Limiting
%%====================================================================

%% @private
do_rate_check(ToolName, Context, State) ->
    Caller = maps:get(caller, Context, maps:get(<<"caller">>, Context, <<"default">>)),
    Key = {ToolName, Caller},
    Now = erlang:monotonic_time(millisecond),

    %% Get rate limit for this tool
    {RateLimit, WindowMs} = case ets:lookup(?POLICY_TABLE, ToolName) of
        [{_, #policy{rate_limit = RL, rate_window_ms = W}}] -> {RL, W};
        [] -> {State#state.default_rate_limit, State#state.rate_window_ms}
    end,

    case ets:lookup(?RATE_TABLE, Key) of
        [{_, #rate_entry{count = Count, window_start = Start}}] ->
            case Now - Start > WindowMs of
                true ->
                    %% Window expired, reset
                    NewEntry = #rate_entry{key = Key, count = 1, window_start = Now},
                    ets:insert(?RATE_TABLE, {Key, NewEntry}),
                    ok;
                false when Count < RateLimit ->
                    %% Within window and under limit
                    NewEntry = #rate_entry{key = Key, count = Count + 1, window_start = Start},
                    ets:insert(?RATE_TABLE, {Key, NewEntry}),
                    ok;
                false ->
                    %% Rate limited
                    {error, rate_limited}
            end;
        [] ->
            %% First request
            NewEntry = #rate_entry{key = Key, count = 1, window_start = Now},
            ets:insert(?RATE_TABLE, {Key, NewEntry}),
            ok
    end.

%%====================================================================
%% Internal Functions - Utility
%%====================================================================

%% @private
policy_to_map(#policy{} = P) ->
    #{
        tool_name => P#policy.tool_name,
        allowed_roles => P#policy.allowed_roles,
        rate_limit => P#policy.rate_limit,
        rate_window_ms => P#policy.rate_window_ms,
        input_rules => P#policy.input_rules,
        output_rules => P#policy.output_rules,
        sandbox => P#policy.sandbox
    }.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V).
