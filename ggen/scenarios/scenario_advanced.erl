%%====================================================================
%% Module: scenario_advanced
%% Description: Advanced generation scenario with complex state machines and HotCI
%%====================================================================

-module(scenario_advanced).
-author("a2a-ggen").
-vsn("1.0.0").

-export([generate/0, generate/1, get_config/0]).

%%====================================================================
%% Exported Functions
%%====================================================================

-spec generate() -> ok | {error, term()}.
generate() ->
    generate([]).

-spec generate(Options :: list()) -> ok | {error, term()}.
generate(Options) ->
    io:format("🎯 Running Advanced Generation Scenario~n"),
    io:format("=" * 50 ++ "~n"),

    Config = get_config(),

    case proplists:get_value(output_dir, Options, "generated/advanced/") of
        OutputDir ->
            case filelib:ensure_dir(OutputDir) of
                ok ->
                    generate_advanced_modules(OutputDir, Config),
                    generate_advanced_config(OutputDir, Config),
                    generate_advanced_tests(OutputDir, Config),
                    io:format("✅ Advanced generation completed~n");
                {error, Reason} ->
                    {error, {output_dir_error, Reason}}
            end;
        _ ->
            {error, invalid_options}
    end.

-spec get_config() -> map().
get_config() ->
    #{
        modules => [
            #{
                module_name => "a2a_workflow_orchestrator",
                behaviour_type => "gen_statem",
                hotci_enabled => true,
                rollback_support => true,
                states => [
                    #{name => "idle", hotci_enabled => true},
                    #{name => "initializing", hotci_enabled => true},
                    #{name => "processing", hotci_enabled => true},
                    #{name => "waiting_for_dependencies", hotci_enabled => true},
                    #{name => "coordinating", hotci_enabled => true},
                    #{name => "finalizing", hotci_enabled => true},
                    #{name => "completed", hotci_enabled => true},
                    #{name => "failed", hotci_enabled => true},
                    #{name => "rolled_back", hotci_enabled => true}
                ],
                properties => [
                    #{name => "workflow_id", type => "string()", default => "undefined"},
                    #{name => "workflow_state", type => "map()", default => "#{}"},
                    #{name => "dependency_graph", type => "digraph()", default => "undefined"},
                    #{name => "max_retries", type => "integer", default => "3"},
                    #{name => "timeout", type => "integer", default => "300000"}
                ],
                exported_functions => [
                    #{name => "start_link", args => ["WorkflowId", "WorkflowDef"]},
                    #{name => "get_workflow_status", args => []},
                    #{name => "execute_workflow", args => []},
                    #{name => "add_task", args => ["TaskId", "TaskDef"]},
                    #{name => "pause_workflow", args => []},
                    #{name => "resume_workflow", args => []},
                    #{name => "rollback_workflow", args => []}
                ]
            },
            #{
                module_name => "a2a_hotci_manager",
                behaviour_type => "gen_server",
                hotci_enabled => true,
                rollback_support => true,
                properties => [
                    #{name => "test_suites", type => "map()", default => "#{}"},
                    #{name => "test_results", type => "map()", default => "#{}"},
                    #{name => "upgrade_history", type => "list()", default => "[]"},
                    #{name => "consistency_checks", type => "list()", default => "[]"},
                    #{name => "monitoring_interval", type => "integer", default => "30000"}
                ],
                exported_functions => [
                    #{name => "start_link", args => []},
                    #{name => "run_upgrade_test", args => ["TestSuite"]},
                    #{name => "run_consistency_check", args => []},
                    #{name => "get_test_results", args => ["TestSuite"]},
                    #{name => "trigger_rollback", args => ["Version"]},
                    #{name => "get_upgrade_status", args => []},
                    #{name => "enable_monitoring", args => []},
                    #{name => "disable_monitoring", args => []}
                ]
            },
            #{
                module_name => "a2a_metrics_collector",
                behaviour_type => "gen_server",
                hotci_enabled => false,
                properties => [
                    #{name => "metrics_table", type => "ets:tid()", default => "undefined"},
                    #{name => "prometheus_port", type => "integer", default => "9090"},
                    #{name => "metrics_interval", type => "integer", default => "5000"},
                    #{name => "retention_period", type => "integer", default => "86400000"}
                ],
                exported_functions => [
                    #{name => "start_link", args => []},
                    #{name => "record_metric", args => ["MetricName", "Value", "Tags"]},
                    #{name => "get_metrics", args => []},
                    #{name => "get_metric_history", args => ["MetricName"]},
                    #{name => "export_metrics", args => []},
                    #{name => "cleanup_old_metrics", args => []}
                ]
            }
        ],
        infrastructure => #{
            k8s => #{
                namespace => "a2a-advanced",
                replicas => 5,
                service_type => "LoadBalancer",
                resources => #{
                    requests => #{cpu => "250m", memory => "512Mi"},
                    limits => #{cpu => "1000m", memory => "2Gi"}
                },
                liveness_probe => #{
                    path => "/health",
                    initial_delay => 30,
                    period => 10,
                    timeout => 5
                },
                readiness_probe => #{
                    path => "/ready",
                    initial_delay => 5,
                    period => 5,
                    timeout => 3
                }
            },
            monitoring => #{
                prometheus => true,
                grafana => true,
                alertmanager => true,
                tracing => true
            },
            security => #{
                rbac => true,
                network_policies => true,
                secrets_management => true,
                audit_logging => true
            }
        }
    }.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec generate_advanced_modules(OutputDir :: string(), Config :: map()) -> ok.
generate_advanced_modules(OutputDir, Config) ->
    Modules = maps:get(modules, Config, []),
    lists:foreach(fun(Module) ->
        generate_advanced_module(OutputDir, Module)
    end, Modules).

-spec generate_advanced_module(OutputDir :: string(), Module :: map()) -> ok.
generate_advanced_module(OutputDir, Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module, "gen_server"),
    HotCI = maps:get(hotci_enabled, Module, false),
    Rollback = maps:get(rollback_support, Module, false),
    States = maps:get(states, Module, []),
    Properties = maps:get(properties, Module, []),
    Functions = maps:get(exported_functions, Module, []),

    %% Create module content
    Content = generate_advanced_module_content(ModuleName, Behaviour, HotCI, Rollback, States, Properties, Functions),

    %% Write module file
    Filename = OutputDir ++ ModuleName ++ ".erl",
    case file:write_file(Filename, Content) of
        ok ->
            io:format("✅ Generated ~s~n", [Filename]);
        {error, Reason} ->
            io:format("❌ Failed to generate ~s: ~p~n", [Filename, Reason])
    end.

-spec generate_advanced_module_content(ModuleName :: string(), Behaviour :: string(), HotCI :: boolean(), Rollback :: boolean(), States :: list(), Properties :: list(), Functions :: list()) -> string().
generate_advanced_module_content(ModuleName, Behaviour, HotCI, Rollback, States, Properties, Functions) ->
    %% Module declaration
    Header = "-module(" ++ ModuleName ++ ").\n" ++
             "-behaviour(" ++ Behaviour ++ ").\n\n",

    %% Exports
    Exports = generate_advanced_exports(Behaviour, Functions, HotCI, Rollback),

    %% Records
    Records = generate_advanced_records(Properties, HotCI, Rollback),

    %% API Functions
    ApiFunctions = generate_advanced_api_functions(ModuleName, Functions),

    %% Callback Functions
    CallbackFunctions = generate_advanced_callback_functions(Behaviour, HotCI, Rollback, States),

    %% Internal Functions
    InternalFunctions = generate_advanced_internal_functions(ModuleName, Functions, States),

    %% HotCI Functions
    HotCIFunctions = case HotCI of
        true -> generate_advanced_hotci_functions(ModuleName);
        false -> ""
    end,

    %% Rollback Functions
    RollbackFunctions = case Rollback of
        true -> generate_advanced_rollback_functions(ModuleName);
        false -> ""
    end,

    %% Tests
    Tests = generate_advanced_tests_content(Functions, HotCI, Rollback),

    %% Complete module
    Header ++ Exports ++ Records ++ ApiFunctions ++ CallbackFunctions ++ InternalFunctions ++ HotCIFunctions ++ RollbackFunctions ++ Tests.

-spec generate_advanced_exports(Behaviour :: string(), Functions :: list(), HotCI :: boolean(), Rollback :: boolean()) -> string().
generate_advanced_exports(Behaviour, Functions, HotCI, Rollback) ->
    Exports = case Behaviour of
        "gen_statem" ->
            ["start_link/2,", "callback_mode/0"];
        "gen_server" ->
            ["start_link/0,", "start_link/1"];
        _ ->
            ["start_link/0"]
    end ++ case Functions of
        [] -> [];
        _ -> lists:map(fun(F) ->
            FunName = maps:get(name, F),
            Args = case maps:get(args, F, []) of
                [] -> "/0";
                ArgsList -> "/" ++ integer_to_list(length(ArgsList))
            end,
            ",\n    " ++ FunName ++ Args
        end, Functions)
    end ++ case HotCI of
        true ->
            ",\n    get_metrics/0,\n    get_status/0,\n    is_hotci_enabled/0";
        false -> ""
    end ++ case Rollback of
        true ->
            ",\n    trigger_rollback/1,\n    get_rollback_status/0";
        false -> ""
    end,

    ExportString = "%%====================================================================\n" ++
                   "%% Exports\n" ++
                   "%%====================================================================\n" ++
                   "-export([\n" ++
                   "    " ++ string:strip(lists:flatten(Exports), right, $\n) ++
                   "\n]).\n\n",

    ExportString.

-spec generate_advanced_records(Properties :: list(), HotCI :: boolean(), Rollback :: boolean()) -> string().
generate_advanced_records(Properties, HotCI, Rollback) ->
    Records = "%%====================================================================\n" ++
              "%% Records\n" ++
              "%%====================================================================\n" ++
              "-record(state, {\n",

    RecordFields = case HotCI of
        true ->
            "    hotci_monitor :: pid(),\n" ++
            "    hotci_metrics :: map(),\n" ++
            "    hotci_status :: atom(),\n";
        false -> ""
    end ++ case Rollback of
        true ->
            "    rollback_timer :: reference(),\n" ++
            "    rollback_strategy :: atom(),\n" ++
            "    rollback_data :: term(),\n";
        false -> ""
    end ++ case Properties of
        [] ->
            "    %% Internal state\n" ++
            "    version :: string(),\n" ++
            "    created_at :: integer(),\n" ++
            "    updated_at :: integer(),\n" ++
            "    metadata :: map(),\n" ++
            "    stats :: map()\n";
        _ ->
            lists:map(fun(P) ->
                Name = maps:get(name, P),
                Type = maps:get(type, P, "term()"),
                "    " ++ Name ++ " :: " ++ Type ++ ",\n"
            end, Properties) ++
            "    %% Internal state\n" ++
            "    version :: string(),\n" ++
            "    created_at :: integer(),\n" ++
            "    updated_at :: integer(),\n" ++
            "    metadata :: map(),\n" ++
            "    stats :: map()\n"
    end,

    Records ++ RecordFields ++ "\n}).\n\n".

-spec generate_advanced_api_functions(ModuleName :: string(), Functions :: list()) -> string().
generate_advanced_api_functions(ModuleName, Functions) ->
    Api = "%%====================================================================\n" ++
          "%% API Functions\n" ++
          "%%====================================================================\n",

    FunctionStrings = lists:map(fun(F) ->
        FunName = maps:get(name, F),
        Args = case maps:get(args, F, []) of
            [] -> [];
            ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
        end,

        "%% @doc " ++ FunName ++ " API function\n" ++
        "%% @spec " ++ FunName ++ Args ++ " -> ok | {error, term()}\n" ++
        FunName ++ Args ++ " ->\n" ++
        "    gen_server:call(?MODULE, " ++ atom_to_list(list_to_atom(string:to_lower(FunName))) ++ "_request" ++ case Args of
            [] -> "";
            _ -> " " ++ Args
        end ++ ").\n\n"
    end, Functions),

    Api ++ FunctionStrings.

-spec generate_advanced_callback_functions(Behaviour :: string(), HotCI :: boolean(), Rollback :: boolean(), States :: list()) -> string().
generate_advanced_callback_functions(Behaviour, HotCI, Rollback, States) ->
    Callbacks = "%%====================================================================\n" ++
                "%% Callback Functions\n" ++
                "%%====================================================================\n",

    CaseBehaviour = case Behaviour of
        "gen_statem" ->
            generate_advanced_gen_statem_callbacks(HotCI, Rollback, States);
        "gen_server" ->
            generate_advanced_gen_server_callbacks(HotCI, Rollback);
        _ ->
            ""
    end,

    Callbacks ++ CaseBehaviour.

-spec generate_advanced_gen_statem_callbacks(HotCI :: boolean(), Rollback :: boolean(), States :: list()) -> string().
generate_advanced_gen_statem_callbacks(HotCI, Rollback, States) ->
    Init = "init(Args) ->\n" ++
           "    State = init_state(#state{}, Args),\n" ++
           "    {ok, idle, State}.\n\n",

    CallbackMode = "callback_mode() ->\n" ++
                   "    state_functions.\n\n",

    StateFunctions = lists:map(fun(State) ->
        StateName = maps:get(name, State),
        StateCode = generate_state_function(StateName, HotCI, Rollback, States),
        StateCode
    end, States),

    HandleEvent = "handle_event({timeout, rollback_timer}, rollback_check, State) ->\n" ++
                  "    handle_rollback_check(State);\n\n" ++
                  "handle_event(Event, Content, State) ->\n" ++
                  "    handle_event_generic(Event, Content, State).\n\n",

    HotCIStuff = case HotCI of
        true ->
            "handle_event({hotci_check, Result}, State) ->\n" ++
            "    NewState = handle_hotci_check(Result, State),\n" ++
            "    {next_state, State#state.state, NewState};\n\n";
        false -> ""
    end,

    RollbackStuff = case Rollback of
        true ->
            "handle_event({rollback_request, Version}, State) ->\n" ++
            "    NewState = handle_rollback_request(Version, State),\n" ++
            "    {next_state, rolled_back, NewState};\n\n";
        false -> ""
    end,

    Init ++ CallbackMode ++ StateFunctions ++ HandleEvent ++ HotCIStuff ++ RollbackStuff.

-spec generate_state_function(StateName :: string(), HotCI :: boolean(), Rollback :: boolean(), States :: list()) -> string().
generate_state_function(StateName, HotCI, Rollback, States) ->
    TransitionCode = case StateName of
        "idle" ->
            "idle(event, Content, State) ->\n" ++
            "    {next_state, initializing, State#state{created_at = erlang:system_time(millisecond)}};\n\n";
        "initializing" ->
            "initializing(event, Content, State) ->\n" ++
            "    case initialize_workflow(Content, State) of\n" ++
            "        {ok, NewState} ->\n" ++
            "            {next_state, processing, NewState};\n" ++
            "        {error, Reason} ->\n" ++
            "            {next_state, failed, State#state{metadata = #{error => Reason}}}\n" ++
            "    end;\n\n";
        "processing" ->
            "processing(event, Content, State) ->\n" ++
            "    case process_workflow_step(Content, State) of\n" ++
            "        {ok, NewState} ->\n" ++
            "            check_completion(NewState);\n" ++
            "        {retry, NewState} ->\n" ++
            "            {next_state, waiting_for_dependencies, NewState};\n" ++
            "        {error, Reason} ->\n" ++
            "            {next_state, failed, State#state{metadata = #{error => Reason}}}\n" ++
            "    end;\n\n";
        "waiting_for_dependencies" ->
            "waiting_for_dependencies(event, Content, State) ->\n" ++
            "    case check_dependencies(Content, State) of\n" ++
            "        ready ->\n" ++
            "            {next_state, processing, State};\n" ++
            "        waiting ->\n" ++
            "            {next_state, waiting_for_dependencies, State}\n" ++
            "    end;\n\n";
        "coordinating" ->
            "coordinating(event, Content, State) ->\n" ++
            "    case coordinate_sub_tasks(Content, State) of\n" ++
            "        {ok, NewState} ->\n" ++
            "            {next_state, finalizing, NewState};\n" ++
            "        {error, Reason} ->\n" ++
            "            {next_state, failed, State#state{metadata = #{error => Reason}}}\n" ++
            "    end;\n\n";
        "finalizing" ->
            "finalizing(event, Content, State) ->\n" ++
            "    case finalize_workflow(Content, State) of\n" ++
            "        {ok, NewState} ->\n" ++
            "            {next_state, completed, NewState};\n" ++
            "        {error, Reason} ->\n" ++
            "            {next_state, failed, State#state{metadata = #{error => Reason}}}\n" ++
            "    end;\n\n";
        _ ->
            StateName ++ "(event, Content, State) ->\n" ++
            "    {next_state, State#state.state, State}.\n\n"
    end,

    TransitionCode.

-spec generate_advanced_gen_server_callbacks(HotCI :: boolean(), Rollback :: boolean()) -> string().
generate_advanced_gen_server_callbacks(HotCI, Rollback) ->
    Init = "init(Args) ->\n" ++
           "    State = init_state(#state{}, Args),\n" ++
           "    {ok, State}.\n\n",

    HandleCall = "handle_call(Request, From, State) ->\n" ++
                 "    case Request of\n" ++
                 "        get_metrics ->\n" ++
                 "            {reply, State#state.metrics, State};\n" ++
                 "        get_status ->\n" ++
                 "            {reply, {ok, running}, State};\n" ++
                 "        is_hotci_enabled ->\n" ++
                 "            {reply, true, State};\n" ++
                 "        trigger_rollback(Version) when Rollback ->\n" ++
                 "            {reply, ok, State#state{rollback_data = Version}};\n" ++
                 "        get_rollback_status when Rollback ->\n" ++
                 "            {reply, ready, State};\n" ++
                 "        _ ->\n" ++
                 "            {reply, {error, unknown_request}, State}\n" ++
                 "    end.\n\n",

    HandleCast = "handle_cast(_Msg, State) ->\n" ++
                 "    {noreply, State}.\n\n",

    HandleInfo = "handle_info(_Info, State) ->\n" ++
                 "    {noreply, State}.\n\n",

    Terminate = "terminate(_Reason, State) ->\n" ++
                "    cleanup_resources(State),\n" ++
                "    ok.\n\n",

    CodeChange = "code_change(_OldVsn, State, _Extra) ->\n" ++
                 "    {ok, State}.\n\n",

    HotCIStuff = case HotCI of
        true ->
            "start_hotci_monitor() ->\n" ++
            "    case whereis(hotci_monitor) of\n" ++
            "        undefined ->\n" ++
            "            {ok, Pid} = a2a_hotci_monitor:start(),\n" ++
            "            Pid;\n" ++
            "        Pid ->\n" ++
            "            Pid\n" ++
            "    end.\n\n" ++
            "init_state(#state{} = State, Args) ->\n" ++
            "    HotciMonitor = case application:get_env(a2a_erl, enable_hotci, false) of\n" ++
            "        true -> start_hotci_monitor();\n" ++
            "        false -> undefined\n" ++
            "    end,\n" ++
            "    State#state{hotci_monitor = HotciMonitor}.\n\n";
        false ->
            "init_state(#state{} = State, Args) ->\n" ++
            "    maps:fold(fun init_arg/3, State, Args).\n\n" ++
            "init_arg(_Key, _Value, State) ->\n" ++
            "    State.\n\n"
    end,

    Cleanup = "cleanup_resources(#state{} = State) ->\n" ++
              "    %% Clean up any resources\n" ++
              "    ok.\n\n",

    Init ++ HandleCall ++ HandleCast ++ HandleInfo ++ Terminate ++ CodeChange ++ HotCIStuff ++ Cleanup.

-spec generate_advanced_internal_functions(ModuleName :: string(), Functions :: list(), States :: list()) -> string().
generate_advanced_internal_functions(ModuleName, Functions, States) ->
    Internal = "%%====================================================================\n" ++
               "%% Internal Functions\n" ++
               "%%====================================================================\n",

    GenericHandlers = "handle_event_generic(_Event, _Content, State) ->\n" ++
                     "    {next_state, State#state.state, State}.\n\n",

    WorkflowFunctions = "check_completion(#state{state = processing} = State) ->\n" ++
                       "    case is_workflow_complete(State) of\n" ++
                       "        true -> {next_state, coordinating, State};\n" ++
                       "        false -> {next_state, processing, State}\n" ++
                       "    end;\n\n" ++
                       "check_completion(State) ->\n" ++
                       "    {next_state, State#state.state, State}.\n\n",

    InitializeFunctions = "initialize_workflow(_Content, State) ->\n" ++
                         "    {ok, State#state{workflow_state = #{status => initializing}}}.\n\n" ++
                         "process_workflow_step(_Content, State) ->\n" ++
                         "    {ok, State#state{workflow_state = #{status => processing}}}.\n\n" ++
                         "check_dependencies(_Content, _State) ->\n" ++
                         "    ready.\n\n" ++
                         "coordinate_sub_tasks(_Content, State) ->\n" ++
                         "    {ok, State#state{workflow_state = #{status => coordinating}}}.\n\n" ++
                         "finalize_workflow(_Content, State) ->\n" ++
                         "    {ok, State#state{workflow_state = #{status => completed}}}.\n\n" ++
                         "is_workflow_complete(_State) ->\n" ++
                         "    true.\n\n",

    Internal ++ GenericHandlers ++ WorkflowFunctions ++ InitializeFunctions.

-spec generate_advanced_hotci_functions(ModuleName :: string()) -> string().
generate_advanced_hotci_functions(ModuleName) ->
    HotCI = "%%====================================================================\n" ++
            "%% HotCI Functions\n" ++
            "%%====================================================================\n" ++
            "%% @doc Start HotCI monitor\n" ++
            "start_hotci_monitor() ->\n" ++
            "    case whereis(hotci_monitor) of\n" ++
            "        undefined ->\n" ++
            "            {ok, Pid} = a2a_hotci_monitor:start(),\n" ++
            "            Pid;\n" ++
            "        Pid ->\n" ++
            "            Pid\n" ++
            "    end.\n\n" ++
            "%% @doc Handle HotCI check results\n" ++
            "handle_hotci_check({ok, Result}, State) ->\n" ++
            "    Metrics = State#state.hotci_metrics#{last_check => Result},\n" ++
            "    State#state{hotci_metrics = Metrics};\n\n" ++
            "handle_hotci_check({error, Reason}, State) ->\n" ++
            "    Metrics = State#state.hotci_metrics#{last_error => Reason},\n" ++
            "    State#state{hotci_metrics = Metrics}.\n\n" ++
            "%% @doc Get HotCI status\n" ++
            "get_hotci_status() ->\n" ++
            "    gen_server:call(?MODULE, get_hotci_status).\n\n" ++
            "%% @doc Run HotCI validation\n" ++
            "run_hotci_validation() ->\n" ++
            "    gen_server:call(?MODULE, run_hotci_validation).\n\n" ++
            "%% @doc Trigger HotCI upgrade test\n" ++
            "trigger_upgrade_test() ->\n" ++
            "    gen_server:call(?MODULE, trigger_upgrade_test).\n\n" ++
            "%% @doc HotCI request handler\n" ++
            "handle_hotci_request(Request, From, State) ->\n" ++
            "    case Request of\n" ++
            "        get_hotci_status ->\n" ++
            "            {reply, State#state.hotci_status, State};\n" ++
            "        run_hotci_validation ->\n" ++
            "            Result = run_validation_tests(),\n" ++
            "            {reply, Result, State};\n" ++
            "        trigger_upgrade_test ->\n" ++
            "            Result = trigger_upgrade_tests(),\n" ++
            "            {reply, Result, State};\n" ++
            "        _ ->\n" ++
            "            {reply, {error, unknown_request}, State}\n" ++
            "    end.\n\n" ++
            "run_validation_tests() ->\n" ++
            "    %% Implement validation tests\n" ++
            "    {ok, validation_passed}.\n\n" ++
            "trigger_upgrade_tests() ->\n" ++
            "    %% Implement upgrade tests\n" ++
            "    {ok, upgrade_test_passed}.\n\n".

-spec generate_advanced_rollback_functions(ModuleName :: string()) -> string().
generate_advanced_rollback_functions(ModuleName) ->
    Rollback = "%%====================================================================\n" ++
               "%% Rollback Functions\n" ++
               "%%====================================================================\n" ++
               "%% @doc Start rollback timer\n" ++
               "start_rollback_timer() ->\n" ++
            "    erlang:start_timer(30000, self(), rollback_check).\n\n" ++
            "%% @doc Handle rollback check\n" ++
            "handle_rollback_check(State) ->\n" ++
            "    %% Implement rollback logic\n" ++
            "    State.\n\n" ++
            "%% @doc Handle rollback request\n" ++
            "handle_rollback_request(Version, State) ->\n" ++
            "    %% Implement rollback logic\n" ++
            "    State#state{rollback_data = Version}.\n\n" ++
            "%% @doc Execute rollback\n" ++
            "execute_rollback(State) ->\n" ++
            "    %% Implement rollback execution\n" ++
            "    {ok, rolled_back}.\n\n" ++
            "%% @doc Get rollback status\n" ++
            "get_rollback_status(State) ->\n" ++
            "    %% Return rollback status\n" ++
            "    ready.\n\n".

-spec generate_advanced_tests_content(Functions :: list(), HotCI :: boolean(), Rollback :: boolean()) -> string().
generate_advanced_tests_content(Functions, HotCI, Rollback) ->
    Tests = "%%====================================================================\n" ++
            "%% EUnit Tests\n" ++
            "%%====================================================================\n" ++
            "-ifdef(TEST).\n" ++
            "-include_lib(\"eunit/include/eunit.hrl\").\n\n",

    TestCases = lists:map(fun(F) ->
        FunName = maps:get(name, F),
        TestName = FunName ++ "_test",

        "%% @doc Test " ++ FunName ++ " function\n" ++
        TestName ++ "() ->\n" ++
        "    {ok, _} = start_link(),\n" ++
        "    ?assertEqual(ok, " ++ FunName ++ "()()),\n" ++
        "    ok.\n\n"
    end, Functions),

    HotCITests = case HotCI of
        true ->
            "get_hotci_status_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual(ok, get_hotci_status()),\n" ++
            "    ok.\n\n" ++
            "run_hotci_validation_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual({ok, validation_passed}, run_hotci_validation()),\n" ++
            "    ok.\n\n" ++
            "trigger_upgrade_test_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual({ok, upgrade_test_passed}, trigger_upgrade_test()),\n" ++
            "    ok.\n\n";
        false -> ""
    end,

    RollbackTests = case Rollback of
        true ->
            "trigger_rollback_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual(ok, trigger_rollback(\"v1.0.0\")),\n" ++
            "    ok.\n\n" ++
            "get_rollback_status_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual(ready, get_rollback_status()),\n" ++
            "    ok.\n\n";
        false -> ""
    end,

    StartStopTest = "start_stop_test() ->\n" ++
                   "    {ok, Pid} = start_link(),\n" ++
                   "    unlink(Pid),\n" ++
                   "    exit(Pid, kill),\n" ++
                   "    ok.\n\n",

    Tests ++ TestCases ++ HotCITests ++ RollbackTests ++ StartStopTest ++ "-endif.\n".

-spec generate_advanced_config(OutputDir :: string(), Config :: map()) -> ok.
generate_advanced_config(OutputDir, Config) ->
    %% Generate advanced rebar3 config
    Rebar3Content = generate_advanced_rebar3_config(Config),
    case file:write_file(OutputDir ++ "rebar3.config", Rebar3Content) of
        ok -> io:format("✅ Generated advanced rebar3.config~n");
        {error, Reason} -> io:format("❌ Failed to generate rebar3.config: ~p~n", [Reason])
    end,

    %% Generate advanced sys.config
    SysConfigContent = generate_advanced_sys_config(Config),
    case file:write_file(OutputDir ++ "sys.config", SysConfigContent) of
        ok -> io:format("✅ Generated advanced sys.config~n");
        {error, Reason} -> io:format("❌ Failed to generate sys.config: ~p~n", [Reason])
    end,

    %% Generate vm.args
    VmArgsContent = generate_advanced_vm_args(Config),
    case file:write_file(OutputDir ++ "vm.args", VmArgsContent) of
        ok -> io:format("✅ Generated vm.args~n");
        {error, Reason} -> io:format("❌ Failed to generate vm.args: ~p~n", [Reason])
    end.

-spec generate_advanced_rebar3_config(Config :: map()) -> string().
generate_advanced_rebar3_config(Config) ->
    "{deps, [\n" ++
    "    jiffy, cowboy, lager, jsx, digraph,\n" ++
    "    prometheus, prometheus_ects, prometheus_process_counter,\n" ++
    "    telemetry, opentelemetry, opentelemetry_exporter,\n" ++
    "    eunit_eqc, proper, meck, cover, recon\n" ++
    "] }.\n" ++
    "{erl_opts, [\n" ++
    "    debug_info, warnings_as_errors, report_warnings,\n" ++
    "    {i, \"include\"}, {platform_define, \"\\{windows\\}\", {platform_define, win32}}\n" ++
    "] }.\n" ++
    "{xref_checks, [\n" ++
    "    undefined_functions, deprecated_functions,\n" ++
    "    failsafe, variables_export_used, unused_variables\n" ++
    "] }.\n" ++
    "{dialyzer_opts, [\n" ++
    "    {warnings, [unmatched_returns, error_handling, race_conditions]},\n" ++
    "    {plt_apps, kernel, stdlib, erts, crypto, inets, mnesia, ssl, tools}\n" ++
    "] }.\n" ++
    "{cover_enabled, true}.\n" ++
    "{cover_export_enabled, true}.\n" ++
    "{eunit_opts, [verbose, {report, {eunit_surefire, [{suite, \"*_test\"}]}}]}.\n" ++
    "{relx, [\n" ++
    "    {release, {a2a_erl, \"1.0.0\"}, [\"erts\", \"a2a_erl\"]},\n" ++
    "    {dev_mode, false},\n" ++
    "    {include_erts, true},\n" ++
    "    {generate_start_script, true},\n" ++
    "    {sys_config, \"sys.config\"},\n" ++
    "    {vm_args, \"vm.args\"},\n" ++
    "    {extended_start_script, true},\n" ++
    "    {overlay, [\n" ++
    "        {mkdir, \"log\"},\n" ++
    "        {mkdir, \"data\"},\n" ++
    "        {mkdir, \"config\"},\n" ++
    "        {copy, \"sys.config\", \"{{sys_config}}\"},\n" ++
    "        {copy, \"vm.args\", \"{{vm_args}}\"}\n" ++
    "    ]}\n" ++
    "] }.\n".

-spec generate_advanced_sys_config(Config :: map()) -> string().
generate_advanced_sys_config(Config) ->
    "{a2a_erl, [\n" ++
    "    %% Application configuration\n" ++
    "    {app_name, a2a_erl},\n" ++
    "    {app_version, \"1.0.0\"},\n" ++
    "    {http_port, 8080},\n" ++
    "    {https_port, 8443},\n" ++
    "    {enable_sse, true},\n" ++
    "    {enable_websocket, true},\n" ++
    "    {enable_metrics, true},\n" ++
    "    {enable_tracing, true},\n" ++
    "    {enable_hotci, true},\n" ++
    "    {enable_rollback, true},\n" ++
    "    {log_level, info},\n" ++
    "    {log_dir, \"/var/log/a2a_erl\"},\n" ++
    "    {log_rotation, daily},\n" ++
    "    {max_connections, 10000},\n" ++
    "    {connection_timeout, 30000},\n" ++
    "    {heartbeat_interval, 30000},\n" ++
    "    {session_timeout, 3600},\n" ++
    "    {max_retries, 3},\n" ++
    "    {retry_delay, 1000},\n" ++
    "    {workflow_timeout, 300000},\n" ++
    "    {metrics_port, 9090},\n" ++
    "    {tracing_port, 4317},\n" ++
    "    {hotci_check_interval, 30000},\n" ++
    "    {rollback_timeout, 30000},\n" ++
    "    {monitoring_interval, 5000},\n" ++
    "    {retention_period, 86400000}\n" ++
    "] }.\n".

-spec generate_advanced_vm_args(Config :: map()) -> string().
generate_advanced_vm_args(Config) ->
    "-name a2a_erl@localhost\n" ++
    "-setcookie a2a_erl\n" ++
    "-pa /opt/a2a_erl/ebin\n" ++
    "-config /opt/a2a_erl/sys.config\n" ++
    "-env ERL_MAX_PORTS 65536\n" ++
    "-env ERL_MAX_PORTS 65536\n" ++
    "-env ERL_FULLSWEEP_AFTER 10\n" ++
    "-env ERL_ZONES_DIR /tmp/erlang\n" ++
    "+pc unicode\n" ++
    "+K true\n" ++
    "+P 1048576\n" ++
    "-kernel net_ticktime 60\n" ++
    "-heart\n" ++
    "-env HEART_BEAT_TIMEOUT 30\n" ++
    "-env HEART_COMMAND \"restart a2a_erl\"\n" ++
    "-env LC_ALL en_US.UTF-8\n" ++
    "-env LANG en_US.UTF-8\n" ++
    "-env ERL_AFLAGS \"+pc unicode -kernel shell_history enabled\"\n".

-spec generate_advanced_tests(OutputDir :: string(), Config :: map()) -> ok.
generate_advanced_tests(OutputDir, Config) ->
    %% Generate test runner
    TestRunner = generate_test_runner(Config),
    case file:write_file(OutputDir ++ "test_runner.erl", TestRunner) of
        ok -> io:format("✅ Generated test runner~n");
        {error, Reason} -> io:format("❌ Failed to generate test runner: ~p~n", [Reason])
    end.

-spec generate_test_runner(Config :: map()) -> string().
generate_test_runner(Config) ->
    "-module(test_runner).\n" ++
    "-export([run_all_tests/0, run_specific_tests/1]).\n\n" ++
    "-include_lib(\"eunit/include/eunit.hrl\").\n\n" ++
    "%%====================================================================\n" ++
    "%% Test Runner\n" ++
    "%%====================================================================\n" ++
    "run_all_tests() ->\n" ++
    "    io:format(\"Running all tests...\\n\"),\n" ++
    "    eunit:test([a2a_workflow_orchestrator, a2a_hotci_manager, a2a_metrics_collector],\n" ++
    "              [verbose, {report, {eunit_surefire, [{dir, \"test_results\"}]}}]).\n\n" ++
    "run_specific_tests(Modules) ->\n" ++
    "    io:format(\"Running specific tests: ~p~n\", [Modules]),\n" ++
    "    eunit:test(Modules,\n" ++
    "              [verbose, {report, {eunit_surefire, [{dir, \"test_results\"}]}}]).\n\n" ++
    "%%====================================================================\n" ++
    "%% Test Setup\n" ++
    "%%====================================================================\n" ++
    "-setup() ->\n" ++
    "    %% Setup test environment\n" ++
    "    ok.\n\n" ++
    "-teardown() ->\n" ++
    "    %% Cleanup test environment\n" ++
    "    ok.\n".