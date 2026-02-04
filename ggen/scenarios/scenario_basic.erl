%%====================================================================
%% Module: scenario_basic
%% Description: Basic generation scenario for simple Erlang modules
%%====================================================================

-module(scenario_basic).
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
    io:format("🎯 Running Basic Generation Scenario~n"),
    io:format("=" * 50 ++ "~n"),

    Config = get_config(),

    case proplists:get_value(output_dir, Options, "generated/basic/") of
        OutputDir ->
            case filelib:ensure_dir(OutputDir) of
                ok ->
                    generate_basic_modules(OutputDir, Config),
                    generate_basic_config(OutputDir, Config),
                    io:format("✅ Basic generation completed~n");
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
                module_name => "a2a_task_worker",
                behaviour_type => "gen_server",
                hotci_enabled => true,
                properties => [
                    #{name => "worker_pool", type => "pid()", default => "undefined"},
                    #{name => "max_retries", type => "integer", default => "3"},
                    #{name => "timeout", type => "integer", default => "30000"}
                ],
                exported_functions => [
                    #{name => "start_link", args => []},
                    #{name => "execute_task", args => ["TaskData"]},
                    #{name => "get_status", args => []},
                    #{name => "stop_worker", args => []}
                ]
            },
            #{
                module_name => "a2a_event_bus",
                behaviour_type => "gen_server",
                hotci_enabled => false,
                properties => [
                    #{name => "event_queue", type => "queue:queue()", default => "queue:new()"},
                    #{name => "subscribers", type => "map()", default => "#{}"}
                ],
                exported_functions => [
                    #{name => "start_link", args => []},
                    #{name => "subscribe", args => ["EventType", "Pid"]},
                    #{name => "unsubscribe", args => ["EventType", "Pid"]},
                    #{name => "publish", args => ["EventType", "Event"]}
                ]
            }
        ],
        config => #{
            app_name => "a2a_basic",
            app_version => "1.0.0",
            erlang_version => "27.0",
            otp_features => ["hot_code_loading", "distributed"]
        }
    }.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec generate_basic_modules(OutputDir :: string(), Config :: map()) -> ok.
generate_basic_modules(OutputDir, Config) ->
    Modules = maps:get(modules, Config, []),
    lists:foreach(fun(Module) ->
        generate_basic_module(OutputDir, Module)
    end, Modules).

-spec generate_basic_module(OutputDir :: string(), Module :: map()) -> ok.
generate_basic_module(OutputDir, Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module, "gen_server"),
    HotCI = maps:get(hotci_enabled, Module, false),
    Properties = maps:get(properties, Module, []),
    Functions = maps:get(exported_functions, Module, []),

    %% Create module content
    Content = generate_basic_module_content(ModuleName, Behaviour, HotCI, Properties, Functions),

    %% Write module file
    Filename = OutputDir ++ ModuleName ++ ".erl",
    case file:write_file(Filename, Content) of
        ok ->
            io:format("✅ Generated ~s~n", [Filename]);
        {error, Reason} ->
            io:format("❌ Failed to generate ~s: ~p~n", [Filename, Reason])
    end.

-spec generate_basic_module_content(ModuleName :: string(), Behaviour :: string(), HotCI :: boolean(), Properties :: list(), Functions :: list()) -> string().
generate_basic_module_content(ModuleName, Behaviour, HotCI, Properties, Functions) ->
    %% Module declaration
    Header = "-module(" ++ ModuleName ++ ").\n" ++
             "-behaviour(" ++ Behaviour ++ ").\n\n",

    %% Exports
    Exports = generate_exports(Behaviour, Functions, HotCI),

    %% Records
    Records = generate_records(Properties, HotCI),

    %% API Functions
    ApiFunctions = generate_api_functions(ModuleName, Functions),

    %% Callback Functions
    CallbackFunctions = generate_callback_functions(Behaviour, HotCI),

    %% Internal Functions
    InternalFunctions = generate_internal_functions(ModuleName, Functions),

    %% Tests
    Tests = generate_tests(Functions, HotCI),

    %% Complete module
    Header ++ Exports ++ Records ++ ApiFunctions ++ CallbackFunctions ++ InternalFunctions ++ Tests.

-spec generate_exports(Behaviour :: string(), Functions :: list(), HotCI :: boolean()) -> string().
generate_exports(Behaviour, Functions, HotCI) ->
    Exports = case Behaviour of
        "gen_server" ->
            ["start_link/0,", "start_link/1"];
        "gen_statem" ->
            ["start_link/0,", "start_link/1,", "callback_mode/0"];
        "supervisor" ->
            ["start_link/0"];
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
    end,

    ExportString = "%%====================================================================\n" ++
                   "%% Exports\n" ++
                   "%%====================================================================\n" ++
                   "-export([\n" ++
                   "    " ++ string:strip(lists:flatten(Exports), right, $\n) ++
                   "\n]).\n\n",

    ExportString ++ case HotCI of
        true ->
            "-export([\n" ++
            "    get_metrics/0,\n" ++
            "    get_status/0\n" ++
            "]).\n\n";
        false -> ""
    end.

-spec generate_records(Properties :: list(), HotCI :: boolean()) -> string().
generate_records(Properties, HotCI) ->
    Records = "%%====================================================================\n" ++
              "%% Records\n" ++
              "%%====================================================================\n" ++
              "-record(state, {\n",

    RecordFields = case HotCI of
        true ->
            "    hotci_monitor :: pid(),\n" ++
            "    hotci_metrics :: map(),\n";
        false -> ""
    end ++ case Properties of
        [] ->
            "    %% Internal state\n" ++
            "    metrics :: map(),\n" ++
            "    stats :: map()\n";
        _ ->
            lists:map(fun(P) ->
                Name = maps:get(name, P),
                Type = maps:get(type, P, "term()"),
                "    " ++ Name ++ " :: " ++ Type ++ ",\n"
            end, Properties) ++
            "    %% Internal state\n" ++
            "    metrics :: map(),\n" ++
            "    stats :: map()\n"
    end,

    Records ++ RecordFields ++ "\n}).\n\n".

-spec generate_api_functions(ModuleName :: string(), Functions :: list()) -> string().
generate_api_functions(ModuleName, Functions) ->
    Api = "%%====================================================================\n" ++
          "%% API Functions\n" ++
          "%%====================================================================\n",

    FunctionStrings = lists:map(fun(F) ->
        FunName = maps:get(name, F),
        Args = case maps:get(args, F, []) of
            [] -> [];
            ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
        end,

        FunName ++ Args ++ " ->\n" ++
        "    gen_server:call(?MODULE, " ++ atom_to_list(list_to_atom(string:to_lower(FunName))) ++ "_request" ++ case Args of
            [] -> "";
            _ -> Args
        end ++ ").\n\n"
    end, Functions),

    Api ++ FunctionStrings.

-spec generate_callback_functions(Behaviour :: string(), HotCI :: boolean()) -> string().
generate_callback_functions(Behaviour, HotCI) ->
    Callbacks = "%%====================================================================\n" ++
                "%% Callback Functions\n" ++
                "%%====================================================================\n",

    CaseBehaviour = case Behaviour of
        "gen_server" ->
            generate_gen_server_callbacks(HotCI);
        "gen_statem" ->
            generate_gen_statem_callbacks(HotCI);
        "supervisor" ->
            generate_supervisor_callbacks();
        _ ->
            ""
    end,

    Callbacks ++ CaseBehaviour.

-spec generate_gen_server_callbacks(HotCI :: boolean()) -> string().
generate_gen_server_callbacks(HotCI) ->
    Init = "init(Args) ->\n" ++
           "    State = init_state(#state{}, Args),\n" ++
           "    {ok, State}.\n\n",

    HandleCall = "handle_call(Request, From, State) ->\n" ++
                 "    case Request of\n" ++
                 "        get_metrics ->\n" ++
                 "            {reply, State#state.metrics, State};\n" ++
                 "        get_status ->\n" ++
                 "            {reply, {ok, running}, State};\n" ++
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

-spec generate_gen_statem_callbacks(HotCI :: boolean()) -> string().
generate_gen_statem_callbacks(HotCI) ->
    Init = "init(Args) ->\n" ++
           "    State = init_state(#state{}, Args),\n" ++
           "    {ok, idle, State}.\n\n",

    CallbackMode = "callback_mode() ->\n" ++
                   "    state_functions.\n\n",

    StateFunctions = "idle(event, Content, State) ->\n" ++
                    "    {next_state, processing, State}.\n\n" ++
                    "processing(event, Content, State) ->\n" ++
                    "    {next_state, idle, State}.\n\n",

    HandleEvent = "handle_event(_Event, Content, State) ->\n" ++
                  "    {next_state, idle, State}.\n\n",

    Init ++ CallbackMode ++ StateFunctions ++ HandleEvent.

-spec generate_supervisor_callbacks() -> string().
generate_supervisor_callbacks() ->
    Init = "init([]) ->\n" ++
           "    ChildSpecs = [],\n" ++
           "    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.\n\n" ++
           "init(Args) ->\n" ++
           "    ChildSpecs = process_args(Args),\n" ++
           "    {ok, {{one_for_one, 5, 10}, ChildSpecs}}.\n\n" ++
           "process_args(Args) ->\n" ++
           "    %% Process arguments to create child specifications\n" ++
           "    [].\n\n".

-spec generate_internal_functions(ModuleName :: string(), Functions :: list()) -> string().
generate_internal_functions(ModuleName, Functions) ->
    Internal = "%%====================================================================\n" ++
               "%% Internal Functions\n" ++
               "%%====================================================================\n",

    FunctionStrings = lists:map(fun(F) ->
        FunName = maps:get(name, F),
        LowerName = string:to_lower(FunName),

        LowerName ++ "_request(Request, From, State) ->\n" ++
        "    Reply = {error, not_implemented},\n" ++
        "    {reply, Reply, State}.\n\n" ++

        LowerName ++ "_cast(Request, State) ->\n" ++
        "    {noreply, State}.\n\n" ++

        LowerName ++ "_info(Request, State) ->\n" ++
        "    {noreply, State}.\n\n"
    end, Functions),

    Internal ++ FunctionStrings.

-spec generate_tests(Functions :: list(), HotCI :: boolean()) -> string().
generate_tests(Functions, HotCI) ->
    Tests = "%%====================================================================\n" ++
            "%% EUnit Tests\n" ++
            "%%====================================================================\n" ++
            "-ifdef(TEST).\n" ++
            "-include_lib(\"eunit/include/eunit.hrl\").\n\n",

    TestCases = lists:map(fun(F) ->
        FunName = maps:get(name, F),
        TestName = FunName ++ "_test",

        TestName ++ "() ->\n" ++
        "    {ok, _} = start_link(),\n" ++
        "    ?assertEqual(ok, " ++ FunName ++ "()),\n" ++
        "    ok.\n\n"
    end, Functions),

    HotCITests = case HotCI of
        true ->
            "get_metrics_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual(#{}, get_metrics()),\n" ++
            "    ok.\n\n" ++
            "get_status_test() ->\n" ++
            "    {ok, _} = start_link(),\n" ++
            "    ?assertEqual({ok, running}, get_status()),\n" ++
            "    ok.\n\n";
        false -> ""
    end,

    StartStopTest = "start_stop_test() ->\n" ++
                   "    {ok, Pid} = start_link(),\n" ++
                   "    unlink(Pid),\n" ++
                   "    exit(Pid, kill),\n" ++
                   "    ok.\n\n",

    Tests ++ TestCases ++ HotCITests ++ StartStopTest ++ "-endif.\n".

-spec generate_basic_config(OutputDir :: string(), Config :: map()) -> ok.
generate_basic_config(OutputDir, Config) ->
    %% Generate rebar3 config
    Rebar3Content = generate_rebar3_config(Config),
    case file:write_file(OutputDir ++ "rebar3.config", Rebar3Content) of
        ok -> io:format("✅ Generated rebar3.config~n");
        {error, Reason} -> io:format("❌ Failed to generate rebar3.config: ~p~n", [Reason])
    end,

    %% Generate sys.config
    SysConfigContent = generate_sys_config(Config),
    case file:write_file(OutputDir ++ "sys.config", SysConfigContent) of
        ok -> io:format("✅ Generated sys.config~n");
        {error, Reason} -> io:format("❌ Failed to generate sys.config: ~p~n", [Reason])
    end,

    %% Generate vm.args
    VmArgsContent = generate_vm_args(Config),
    case file:write_file(OutputDir ++ "vm.args", VmArgsContent) of
        ok -> io:format("✅ Generated vm.args~n");
        {error, Reason} -> io:format("❌ Failed to generate vm.args: ~p~n", [Reason])
    end.

-spec generate_rebar3_config(Config :: map()) -> string().
generate_rebar3_config(Config) ->
    AppName = maps:get(app_name, Config, "a2a_erl"),
    ErlangVersion = maps:get(erlang_version, Config, "27.0"),

    "{deps, [jiffy, cowboy, lager, jsx]}.\n" ++
    "{erl_opts, [debug_info, warnings_as_errors]}.\n" ++
    "{xref_checks, [undefined_functions, deprecated_functions]}.\n" ++
    "{dialyzer_opts, [{warnings, [unmatched_returns, error_handling]}]}.\n" ++
    "{relx, [{release, {\"" ++ AppName ++ "\", \"" ++ ErlangVersion ++ "\"}, [\"erts\", \"" ++ AppName ++ "\"]},\n" ++
    "       {dev_mode, false},\n" ++
    "       {include_erts, true},\n" ++
    "       {generate_start_script, true},\n" ++
    "       {sys_config, \"sys.config\"},\n" ++
    "       {vm_args, \"vm.args\"}]}.\n".

-spec generate_sys_config(Config :: map()) -> string().
generate_sys_config(Config) ->
    AppName = maps:get(app_name, Config, "a2a_erl"),

    "{" ++ AppName ++ ", [\n" ++
    "    {http_port, 8080},\n" ++
    "    {enable_sse, true},\n" ++
    "    {enable_metrics, true},\n" ++
    "    {log_level, info},\n" ++
    "    {log_dir, \"/var/log/" ++ AppName ++ "\"},\n" ++
    "    {max_connections, 1000},\n" ++
    "    {connection_timeout, 30000},\n" ++
    "    {heartbeat_interval, 30000}\n" ++
    "] }.\n".

-spec generate_vm_args(Config :: map()) -> string().
generate_vm_args(Config) ->
    AppName = maps:get(app_name, Config, "a2a_erl"),

    "-name " ++ AppName ++ "@localhost\n" ++
    "-setcookie " ++ AppName ++ "\n" ++
    "-pa /opt/" ++ AppName ++ "/ebin\n" ++
    "-config /opt/" ++ AppName ++ "/sys.config\n" ++
    "-env ERL_MAX_PORTS 65536\n" ++
    "-env ERL_FULLSWEEP_AFTER 10\n" ++
    "+pc unicode\n" ++
    "-kernel net_ticktime 60\n" ++
    "-heart\n" ++
    "-env HEART_BEAT_TIMEOUT 30\n" ++
    "-env HEART_COMMAND \"restart " ++ AppName ++ "\"\n".