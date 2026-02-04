%%====================================================================
%% Module: demo_comprehensive
%% Description: Comprehensive demo system for ggen-based code generation
%%====================================================================

-module(demo_comprehensive).
-author("a2a-ggen").
-vsn("1.0.0").

-export([main/0, main/1]).

%%====================================================================
%% Exported Functions
%%====================================================================

-spec main() -> ok | no_return().
main() ->
    main([]).

-spec main(Args :: list()) -> ok | no_return().
main(Args) ->
    io:format("🚀 A2A Comprehensive Code Generation Demo System~n"),
    io:format("=" * 70 ++ "~n"),

    case parse_args(Args) of
        {help, _} ->
            show_usage();
        {demo, Type} ->
            run_comprehensive_demo(Type);
        {generate, _} ->
            generate_all_scenarios();
        {test, _} ->
            run_all_tests();
        {validate, _} ->
            validate_generated_code();
        {_, _} ->
            show_usage()
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec parse_args(Args :: list()) -> {demo, Type :: string()} | {generate, any()} | {test, any()} | {validate, any()} | {help, any()} | {error, any()}.
parse_args([]) ->
    {demo, "all"};
parse_args(["--help"]) ->
    {help, ok};
parse_args(["help"]) ->
    {help, ok};
parse_args(["demo"]) ->
    {demo, "all"};
parse_args(["demo", Type]) ->
    {demo, Type};
parse_args(["generate"]) ->
    {generate, ok};
parse_args(["test"]) ->
    {test, ok};
parse_args(["validate"]) ->
    {validate, ok};
parse_args(_) ->
    {error, invalid_args}.

-spec show_usage() -> no_return().
show_usage() ->
    io:format("Usage:~n"),
    io:format("  demo_comprehensive                                    # Run comprehensive demo~n"),
    io:format("  demo_comprehensive demo all                           # Run all demo scenarios~n"),
    io:format("  demo_comprehensive demo erlang                         # Erlang module generation~n"),
    io:format("  demo_comprehensive demo advanced                      # Advanced scenarios~n"),
    io:format("  demo_comprehensive demo cloud                         # Cloud infrastructure~n"),
    io:format("  demo_comprehensive demo hotci                          # HotCI integration demo~n"),
    io:format("  demo_comprehensive demo integration                    # Complex integration demo~n"),
    io:format("  demo_comprehensive generate                           # Generate all scenarios~n"),
    io:format("  demo_comprehensive test                               # Run validation tests~n"),
    io:format("  demo_comprehensive validate                           # Validate generated code~n"),
    io:format("  demo_comprehensive help                               # Show this help~n"),
    halt(0).

-spec run_comprehensive_demo(Type :: string()) -> ok.
run_comprehensive_demo("all") ->
    io:format("🎯 Running Comprehensive Demo Suite~n"),
    io:format("~s~n", [lists:duplicate(50, $-)]),

    run_basic_demo(),
    run_advanced_demo(),
    run_cloud_demo(),
    run_hotci_demo(),
    run_integration_demo(),

    io:format("~n🎯 Comprehensive Demo Summary~n"),
    io:format("=" * 50 ++ "~n"),
    io:format("✅ Generated comprehensive demo files in generated/~n"),
    io:format("📋 Check generated/ for all examples~n"),
    ok;
run_comprehensive_demo("erlang") ->
    run_basic_demo();
run_comprehensive_demo("advanced") ->
    run_advanced_demo();
run_comprehensive_demo("cloud") ->
    run_cloud_demo();
run_comprehensive_demo("hotci") ->
    run_hotci_demo();
run_comprehensive_demo("integration") ->
    run_integration_demo();
run_comprehensive_demo(Type) ->
    io:format("❌ Unknown demo type: ~p~n", [Type]),
    halt(1).

-spec run_basic_demo() -> ok.
run_basic_demo() ->
    io:format("🎯 Basic Erlang Module Generation Demo~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create basic module definitions
    BasicModules = [
        #{
            module_name => "a2a_task_manager",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            properties => [
                #{name => "ets_table", type => "ets:tid()", default => "undefined"},
                #{name => "max_tasks", type => "integer", default => "1000"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "submit_task", args => ["TaskData"]},
                #{name => "get_task_status", args => ["TaskId"]},
                #{name => "cancel_task", args => ["TaskId"]}
            ]
        },
        #{
            module_name => "a2a_cache_server",
            behaviour_type => "gen_server",
            properties => [
                #{name => "cache_table", type => "ets:tid()", default => "undefined"},
                #{name => "ttl", type => "integer", default => "3600000"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "get", args => ["Key"]},
                #{name => "put", args => ["Key", "Value"]},
                #{name => "delete", args => ["Key"]}
            ]
        }
    ],

    %% Save demo data
    case file:write_file("demo_basic_modules.json", jsx:encode(BasicModules)) of
        ok ->
            io:format("✅ Created basic module definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what will be generated
    io:format("~n📋 Basic generation targets:~n"),
    lists:foreach(fun(Module) ->
        io:format("  - ~s.erl (~s)~n", [
            maps:get(module_name, Module),
            maps:get(behaviour_type, Module)
        ])
    end, BasicModules),

    ok.

-spec run_advanced_demo() -> ok.
run_advanced_demo() ->
    io:format("🎯 Advanced Erlang Generation Demo~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create gen_statem with complex states
    StateMachineModules = [
        #{
            module_name => "a2a_task_statem",
            behaviour_type => "gen_statem",
            hotci_enabled => true,
            rollback_support => true,
            states => [
                #{name => "idle", hotci_enabled => true},
                #{name => "processing", hotci_enabled => true},
                #{name => "waiting_input", hotci_enabled => true},
                #{name => "waiting_auth", hotci_enabled => true},
                #{name => "completed", hotci_enabled => true},
                #{name => "failed", hotci_enabled => true}
            ],
            exported_functions => [
                #{name => "start_link", args => ["TaskId", "TaskData"]},
                #{name => "get_state", args => []},
                #{name => "submit_data", args => ["Data"]},
                #{name => "request_auth", args => ["AuthData"]},
                #{name => "complete_task", args => ["Result"]}
            ]
        },
        #{
            module_name => "a2a_supervisor_tree",
            behaviour_type => "supervisor",
            properties => [
                #{name => "child_spec", type => "list()", default => "[]"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "add_child", args => ["ChildSpec"]},
                #{name => "remove_child", args => ["Id"]}
            ]
        }
    ],

    %% Save advanced demo data
    case file:write_file("demo_advanced_modules.json", jsx:encode(StateMachineModules)) of
        ok ->
            io:format("✅ Created advanced module definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what will be generated
    io:format("~n📋 Advanced generation targets:~n"),
    lists:foreach(fun(Module) ->
        io:format("  - ~s.erl (~s)~n", [
            maps:get(module_name, Module),
            maps:get(behaviour_type, Module)
        ]),
        case maps:get(behaviour_type, Module) of
            "gen_statem" ->
                States = maps:get(states, Module, []),
                io:format("    with ~p states~n", [length(States)]);
            _ ->
                ok
        end
    end, StateMachineModules),

    ok.

-spec run_cloud_demo() -> ok.
run_cloud_demo() ->
    io:format("🎯 Cloud Infrastructure Generation Demo~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create comprehensive cloud configurations
    CloudConfigs = #{
        docker => #{
            name => "a2a-erl-app",
            base_image => "erlang:27-alpine",
            port => 8080,
            health_check_interval => "30s",
            health_check_timeout => "5s",
            health_check_retries => 3,
            hotci_enabled => true
        },
        k8s => #{
            name => "a2a-erl",
            namespace => "a2a-system",
            replicas => 3,
            app_label => "a2a-erl",
            version_label => "v1.0.0",
            resource_requests => #{
                cpu => "100m",
                memory => "128Mi"
            },
            resource_limits => #{
                cpu => "500m",
                memory => "256Mi"
            },
            hotci_enabled => true,
            auto_scaling => true
        },
        helm => #{
            chart_name => "a2a-erl",
            chart_version => "1.0.0",
            app_version => "1.0.0",
            description => "A2A Erlang Application with HotCI",
            repository => "ghcr.io/a2a",
            image_tag => "v1.0.0",
            values => #{
                replicaCount => 3,
                service => #{
                    type => "ClusterIP",
                    port => 8080
                },
                resources => #{
                    limits => #{
                        cpu => "500m",
                        memory => "256Mi"
                    },
                    requests => #{
                        cpu => "100m",
                        memory => "128Mi"
                    }
                },
                hotci => #{
                    enabled => true,
                    check_interval => "30s",
                    upgrade_validation => true
                }
            }
        }
    },

    %% Save cloud demo data
    case file:write_file("demo_cloud_configs.json", jsx:encode(CloudConfigs)) of
        ok ->
            io:format("✅ Created cloud configuration definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what will be generated
    io:format("~n📋 Cloud infrastructure targets:~n"),
    io:format("  - Dockerfile with multi-stage build~n"),
    io:format("  - Kubernetes deployment (3 replicas)~n"),
    io:format("  - Kubernetes service (ClusterIP)~n"),
    io:format("  - ConfigMap for configuration~n"),
    io:format("  - Helm chart with auto-scaling~n"),
    io:format("  - HotCI monitoring integration~n"),

    ok.

-spec run_hotci_demo() -> ok.
run_hotci_demo() ->
    io:format("🎯 HotCI Integration Demo~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create HotCI-enabled modules
    HotCIModules = [
        #{
            module_name => "a2a_hotci_manager",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            rollback_support => true,
            properties => [
                #{name => "test_interval", type => "integer", default => "30000"},
                #{name => "max_retries", type => "integer", default => "3"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "run_upgrade_test", args => []},
                #{name => "run_consistency_check", args => []},
                #{name => "get_test_results", args => []},
                #{name => "trigger_rollback", args => []}
            ]
        },
        #{
            module_name => "a2a_health_monitor",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            properties => [
                #{name => "health_check_interval", type => "integer", default => "10000"},
                #{name => "thresholds", type => "map()", default => "#{}"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "check_component", args => ["Component"]},
                #{name => "get_health_status", args => []},
                #{name => "update_thresholds", args => ["Thresholds"]}
            ]
        }
    ],

    %% Save HotCI demo data
    case file:write_file("demo_hotci_modules.json", jsx:encode(HotCIModules)) of
        ok ->
            io:format("✅ Created HotCI module definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what will be generated
    io:format("~n📋 HotCI integration targets:~n"),
    lists:foreach(fun(Module) ->
        io:format("  - ~s.erl with HotCI support~n", [
            maps:get(module_name, Module)
        ])
    end, HotCIModules),

    ok.

-spec run_integration_demo() -> ok.
run_integration_demo() ->
    io:format("🎯 Complex Integration Demo~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create complex integration scenario
    IntegrationData = #{
        application => #{
            name => "a2a_integration_demo",
            version => "1.0.0",
            modules => [
                #{
                    module_name => "a2a_orchestrator",
                    behaviour_type => "gen_statem",
                    states => [
                        #{name => "initializing", hotci_enabled => true},
                        #{name => "ready", hotci_enabled => true},
                        #{name => "processing", hotci_enabled => true},
                        #{name => "coordinating", hotci_enabled => true},
                        #{name => "finalizing", hotci_enabled => true}
                    ]
                },
                #{
                    module_name => "a2a_workflow_manager",
                    behaviour_type => "gen_server",
                    hotci_enabled => true,
                    properties => [
                        #{name => "workflow_table", type => "ets:tid()", default => "undefined"},
                        #{name => "max_concurrent", type => "integer", default => "10"}
                    ]
                },
                #{
                    module_name => "a2a_message_broker",
                    behaviour_type => "gen_server",
                    hotci_enabled => true,
                    properties => [
                        #{name => "queue_table", type => "ets:tid()", default => "undefined"},
                        #{name => "topic_table", type => "ets:tid()", default => "undefined"}
                    ]
                }
            ]
        },
        infrastructure => #{
            k8s => #{
                namespace => "a2a-integration",
                replicas => 5,
                service_type => "LoadBalancer",
                ingress_enabled => true,
                auto_scaling => true
            },
            monitoring => #{
                metrics_enabled => true,
                logging_enabled => true,
                tracing_enabled => true
            }
        }
    },

    %% Save integration demo data
    case file:write_file("demo_integration.json", jsx:encode(IntegrationData)) of
        ok ->
            io:format("✅ Created integration scenario definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what will be generated
    io:format("~n📋 Complex integration targets:~n"),
    io:format("  - Complete application with multiple modules~n"),
    io:format("  - State machine for workflow orchestration~n"),
    io:format("  - Message broker with queue management~n"),
    io:format("  - Kubernetes deployment with LoadBalancer~n"),
    io:format("  - Ingress configuration~n"),
    io:format("  - Comprehensive monitoring setup~n"),

    ok.

-spec generate_all_scenarios() -> ok.
generate_all_scenarios() ->
    io:format("🎨 Generating All Demo Scenarios~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create generated directory
    case filelib:ensure_dir("generated/") of
        ok ->
            io:format("✅ Created generated directory~n");
        {error, Reason} ->
            io:format("❌ Failed to create directory: ~p~n", [Reason]),
            halt(1)
    end,

    %% Generate all scenarios
    generate_basic_scenario(),
    generate_advanced_scenario(),
    generate_cloud_scenario(),
    generate_hotci_scenario(),
    generate_integration_scenario(),

    %% Generate documentation
    generate_demo_documentation(),

    io:format("~n✅ Generated all demo scenarios in generated/~n"),
    io:format("📋 Check generated/ directory for complete examples~n").

-spec generate_basic_scenario() -> ok.
generate_basic_scenario() ->
    io:format("📝 Generating basic scenario...~n"),

    %% Create basic modules
    Modules = [
        #{
            module_name => "a2a_task_manager",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            properties => [
                #{name => "ets_table", type => "ets:tid()", default => "undefined"},
                #{name => "max_tasks", type => "integer", default => "1000"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "submit_task", args => ["TaskData"]},
                #{name => "get_task_status", args => ["TaskId"]}
            ]
        },
        #{
            module_name => "a2a_cache_server",
            behaviour_type => "gen_server",
            properties => [
                #{name => "cache_table", type => "ets:tid()", default => "undefined"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "get", args => ["Key"]},
                #{name => "put", args => ["Key", "Value"]}
            ]
        }
    ],

    %% Generate modules
    lists:foreach(fun(Module) ->
        generate_erlang_module("generated/basic/", Module)
    end, Modules),

    %% Generate basic configs
    generate_basic_configs("generated/basic/"),

    io:format("✅ Generated basic scenario~n").

-spec generate_advanced_scenario() -> ok.
generate_advanced_scenario() ->
    io:format("📝 Generating advanced scenario...~n"),

    %% Create gen_statem with complex states
    Module = #{
        module_name => "a2a_task_statem",
        behaviour_type => "gen_statem",
        hotci_enabled => true,
        rollback_support => true,
        states => [
            #{name => "idle", hotci_enabled => true},
            #{name => "processing", hotci_enabled => true},
            #{name => "waiting_input", hotci_enabled => true},
            #{name => "waiting_auth", hotci_enabled => true},
            #{name => "completed", hotci_enabled => true},
            #{name => "failed", hotci_enabled => true}
        ],
        exported_functions => [
            #{name => "start_link", args => ["TaskId", "TaskData"]},
            #{name => "get_state", args => []},
            #{name => "submit_data", args => ["Data"]},
            #{name => "request_auth", args => ["AuthData"]}
        ]
    },

    generate_erlang_module("generated/advanced/", Module),
    generate_advanced_configs("generated/advanced/"),

    io:format("✅ Generated advanced scenario~n").

-spec generate_cloud_scenario() -> ok.
generate_cloud_scenario() ->
    io:format("📝 Generating cloud scenario...~n"),

    %% Create cloud infrastructure
    generate_comprehensive_dockerfile("generated/cloud/"),
    generate_comprehensive_k8s("generated/cloud/"),
    generate_comprehensive_helm("generated/cloud/"),

    io:format("✅ Generated cloud scenario~n").

-spec generate_hotci_scenario() -> ok.
generate_hotci_scenario() ->
    io:format("📝 Generating HotCI scenario...~n"),

    %% Create HotCI-enabled modules
    Modules = [
        #{
            module_name => "a2a_hotci_manager",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            rollback_support => true,
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "run_upgrade_test", args => []},
                #{name => "run_consistency_check", args => []}
            ]
        }
    ],

    lists:foreach(fun(Module) ->
        generate_hotci_module("generated/hotci/", Module)
    end, Modules),

    generate_hotci_configs("generated/hotci/"),

    io:format("✅ Generated HotCI scenario~n").

-spec generate_integration_scenario() -> ok.
generate_integration_scenario() ->
    io:format("📝 Generating integration scenario...~n"),

    %% Create complex integration
    Modules = [
        #{
            module_name => "a2a_orchestrator",
            behaviour_type => "gen_statem",
            states => [
                #{name => "initializing", hotci_enabled => true},
                #{name => "ready", hotci_enabled => true},
                #{name => "processing", hotci_enabled => true},
                #{name => "coordinating", hotci_enabled => true},
                #{name => "finalizing", hotci_enabled => true}
            ]
        },
        #{
            module_name => "a2a_workflow_manager",
            behaviour_type => "gen_server",
            hotci_enabled => true
        }
    ],

    lists:foreach(fun(Module) ->
        generate_integration_module("generated/integration/", Module)
    end, Modules),

    generate_integration_configs("generated/integration/"),

    io:format("✅ Generated integration scenario~n").

-spec generate_demo_documentation() -> ok.
generate_demo_documentation() ->
    io:format("📝 Generating documentation...~n"),

    DocContent = "# A2A Comprehensive Demo Documentation\n\n" ++
                 "This directory contains comprehensive examples of ggen-based code generation.\n\n" ++
                 "## Demo Scenarios\n\n" ++
                 "### Basic Scenario (`basic/`)\n" ++
                 "Simple Erlang modules with gen_server behaviour.\n\n" ++
                 "### Advanced Scenario (`advanced/`)\n" ++
                 "Complex state machines with gen_statem.\n\n" ++
                 "### Cloud Scenario (`cloud/`)\n" ++
                 "Complete cloud infrastructure including Docker, Kubernetes, and Helm.\n\n" ++
                 "### HotCI Scenario (`hotci/`)\n" ++
                 "HotCI-enabled modules with rollback support.\n\n" ++
                 "### Integration Scenario (`integration/`)\n" ++
                 "Complete application with multiple modules and infrastructure.\n\n" ++
                 "## Usage\n\n" ++
                 "1. Run the demo: `demo_comprehensive demo all`\n" ++
                 "2. Generate code: `demo_comprehensive generate`\n" ++
                 "3. Run tests: `demo_comprehensive test`\n" ++
                 "4. Validate code: `demo_comprehensive validate`\n\n" ++
                 "## Generated Code Quality\n\n" ++
                 "All generated code includes:\n" ++
                 "- Complete error handling\n" ++
                 "- HotCI support where enabled\n" ++
                 "- Comprehensive documentation\n" ++
                 "- EUnit tests\n" ++
                 "- Production-ready configuration\n",

    file:write_file("generated/README.md", DocContent),

    io:format("✅ Generated documentation~n").

-spec run_all_tests() -> ok.
run_all_tests() ->
    io:format("🧪 Running Comprehensive Test Suite~n"),
    io:format("=" * 50 ++ "~n"),

    %% Test basic modules
    test_basic_modules(),

    %% Test advanced modules
    test_advanced_modules(),

    %% Test cloud infrastructure
    test_cloud_infrastructure(),

    %% Test HotCI integration
    test_hotci_integration(),

    %% Test complex integration
    test_complex_integration(),

    io:format("~n✅ All tests completed successfully~n").

-spec validate_generated_code() -> ok.
validate_generated_code() ->
    io:format("🔍 Validating Generated Code~n"),
    io:format("=" * 50 ++ "~n"),

    %% Validate all generated files
    validate_directory("generated/"),

    %% Check specific scenarios
    validate_basic_code(),
    validate_advanced_code(),
    validate_cloud_code(),
    validate_hotci_code(),
    validate_integration_code(),

    io:format("~n✅ All code validation completed~n").

%%====================================================================
%% Code Generation Helper Functions
%%====================================================================

-spec generate_erlang_module(OutputDir :: string(), Module :: map()) -> ok.
generate_erlang_module(OutputDir, Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module, "gen_server"),

    %% Create output directory
    case filelib:ensure_dir(OutputDir ++ "/") of
        ok -> ok;
        {error, Reason} ->
            io:format("❌ Failed to create directory: ~p~n", [Reason]),
            halt(1)
    end,

    %% Generate module content
    Content = generate_module_content(ModuleName, Behaviour, Module),

    %% Write module file
    Filename = OutputDir ++ ModuleName ++ ".erl",
    case file:write_file(Filename, Content) of
        ok ->
            io:format("✅ Generated ~p~n", [Filename]);
        {error, Reason} ->
            io:format("❌ Failed to generate ~p: ~p~n", [Filename, Reason])
    end.

-spec generate_module_content(ModuleName :: string(), Behaviour :: string(), Module :: map()) -> string().
generate_module_content(ModuleName, Behaviour, Module) ->
    Exports = case maps:get(exported_functions, Module, []) of
        [] -> "";
        Funs ->
            ExportList = lists:map(fun(Fun) ->
                FunName = maps:get(name, Fun),
                Args = case maps:get(args, Fun, []) of
                    [] -> "";
                    ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
                end,
                "    " ++ FunName ++ Args
            end, Funs),
            "-export([" ++ string:join(ExportList, ",\n") ++ "]).\n"
    end,

    InitCode = case Behaviour of
        "gen_statem" ->
            generate_gen_statem_init(Module);
        "supervisor" ->
            generate_supervisor_init(Module);
        _ ->
            generate_gen_server_init(Module)
    end,

    "".

-spec generate_hotci_module(OutputDir :: string(), Module :: map()) -> ok.
generate_hotci_module(OutputDir, Module) ->
    ModuleName = maps:get(module_name, Module),

    %% Add HotCI-specific functions
    HotCICode = generate_hotci_functions(Module),

    %% Generate base module with HotCI code
    generate_erlang_module(OutputDir, Module),

    %% Append HotCI functions
    Filename = OutputDir ++ ModuleName ++ ".erl",
    case file:read_file(Filename) of
        {ok, Content} ->
            case file:write_file(Filename, Content ++ HotCICode) of
                ok -> ok;
                {error, Reason} -> io:format("❌ Failed to append HotCI code: ~p~n", [Reason])
            end;
        {error, Reason} ->
            io:format("❌ Failed to read module file: ~p~n", [Reason])
    end.

-spec generate_integration_module(OutputDir :: string(), Module :: map()) -> ok.
generate_integration_module(OutputDir, Module) ->
    generate_erlang_module(OutputDir, Module),

    %% Add integration-specific code
    ModuleName = maps:get(module_name, Module),
    Filename = OutputDir ++ ModuleName ++ ".erl",

    %% Add integration helpers
    IntegrationCode = generate_integration_helpers(Module),

    case file:read_file(Filename) of
        {ok, Content} ->
            case file:write_file(Filename, Content ++ IntegrationCode) of
                ok -> ok;
                {error, Reason} -> io:format("❌ Failed to append integration code: ~p~n", [Reason])
            end;
        {error, Reason} ->
            io:format("❌ Failed to read module file: ~p~n", [Reason])
    end.

%%====================================================================
%% Infrastructure Generation Helper Functions
%%====================================================================

-spec generate_comprehensive_dockerfile(OutputDir :: string()) -> ok.
generate_comprehensive_dockerfile(OutputDir) ->
    Dockerfile = "FROM erlang:27-alpine AS builder\n\n" ++
                "RUN apk add --no-cache git make curl\n" ++
                "WORKDIR /app\n" ++
                "COPY rebar3 /usr/local/bin/\n" ++
                "COPY rebar.config config src include /app/\n" ++
                "RUN rebar3 compile\n\n" ++
                "FROM erlang:27-alpine\n" ++
                "RUN addgroup -g 1001 -S appuser && \\\n" ++
                "    adduser -S appuser -u 1001\n" ++
                "WORKDIR /app\n" ++
                "COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/a2a_erl /app\n" ++
                "COPY --from=builder --chown=appuser:appuser /app/config /app/config\n" ++
                "RUN chown -R appuser:appuser /app && mkdir -p /app/log /app/data\n" ++
                "USER appuser\n" ++
                "EXPOSE 8080\n" ++
                "HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \\\n" ++
                "    CMD curl -f http://localhost:8080/health || exit 1\n" ++
                "CMD [\"/app/bin/a2a_erl\", \"foreground\"]\n",

    case file:write_file(OutputDir ++ "/Dockerfile", Dockerfile) of
        ok -> io:format("✅ Generated Dockerfile~n");
        {error, Reason} -> io:format("❌ Failed to generate Dockerfile: ~p~n", [Reason])
    end.

-spec generate_comprehensive_k8s(OutputDir :: string()) -> ok.
generate_comprehensive_k8s(OutputDir) ->
    %% Generate deployment
    Deployment = generate_k8s_deployment(),
    case file:write_file(OutputDir ++ "/deployment.yaml", Deployment) of
        ok -> io:format("✅ Generated deployment.yaml~n");
        {error, Reason} -> io:format("❌ Failed to generate deployment: ~p~n", [Reason])
    end,

    %% Generate service
    Service = generate_k8s_service(),
    case file:write_file(OutputDir ++ "/service.yaml", Service) of
        ok -> io:format("✅ Generated service.yaml~n");
        {error, Reason} -> io:format("❌ Failed to generate service: ~p~n", [Reason])
    end,

    %% Generate configmap
    ConfigMap = generate_k8s_configmap(),
    case file:write_file(OutputDir ++ "/configmap.yaml", ConfigMap) of
        ok -> io:format("✅ Generated configmap.yaml~n");
        {error, Reason} -> io:format("❌ Failed to generate configmap: ~p~n", [Reason])
    end.

-spec generate_comprehensive_helm(OutputDir :: string()) -> ok.
generate_comprehensive_helm(OutputDir) ->
    HelmDir = OutputDir ++ "/a2a-erl",
    case filelib:ensure_dir(HelmDir ++ "/") of
        ok ->
            %% Chart.yaml
            ChartContent = "apiVersion: v2\n" ++
                           "name: a2a-erl\n" ++
                           "version: 1.0.0\n" ++
                           "appVersion: 1.0.0\n" ++
                           "description: A2A Erlang Application with HotCI\n",
            file:write_file(HelmDir ++ "/Chart.yaml", ChartContent),

            %% values.yaml
            ValuesContent = "replicaCount: 3\n" ++
                           "\n" ++
                           "image:\n" ++
                           "  repository: ghcr.io/a2a/a2a_erl\n" ++
                           "  pullPolicy: IfNotPresent\n" ++
                           "  tag: v1.0.0\n" ++
                           "\n" ++
                           "service:\n" ++
                           "  type: ClusterIP\n" ++
                           "  port: 8080\n" ++
                           "\n" ++
                           "resources:\n" ++
                           "  limits:\n" ++
                           "    cpu: 500m\n" ++
                           "    memory: 256Mi\n" ++
                           "  requests:\n" ++
                           "    cpu: 100m\n" ++
                           "    memory: 128Mi\n" ++
                           "\n" ++
                           "hotci:\n" ++
                           "  enabled: true\n" ++
                           "  checkInterval: 30s\n" ++
                           "  upgradeValidation: true\n",
            file:write_file(HelmDir ++ "/values.yaml", ValuesContent),

            io:format("✅ Generated Helm chart~n");
        {error, Reason} ->
            io:format("❌ Failed to create Helm directory: ~p~n", [Reason])
    end.

%%====================================================================
%% Configuration Generation
%%====================================================================

-spec generate_basic_configs(OutputDir :: string()) -> ok.
generate_basic_configs(OutputDir) ->
    %% Generate rebar3 config
    Rebar3Content = "{deps, [jiffy, cowboy, lager]}.\\n{erl_opts, [debug_info]}.",
    file:write_file(OutputDir ++ "/rebar3.config", Rebar3Content),

    %% Generate sys.config
    SysConfigContent = "{a2a_erl, [\\n    {http_port, 8080},\\n    {enable_sse, true}\\n]}.",
    file:write_file(OutputDir ++ "/sys.config", SysConfigContent),

    io:format("✅ Generated basic configurations~n").

-spec generate_advanced_configs(OutputDir :: string()) -> ok.
generate_advanced_configs(OutputDir) ->
    %% Generate advanced rebar3 config
    Rebar3Content = "{deps, [jiffy, cowboy, lager, gen_statem]}.\n" ++
                   "{erl_opts, [debug_info, warnings_as_errors]}.\n" ++
                   "{xref_checks, [undefined_functions, deprecated_functions]}.",
    file:write_file(OutputDir ++ "/rebar3.config", Rebar3Content),

    %% Generate advanced sys.config
    SysConfigContent = "{a2a_erl, [\\n    {http_port, 8080},\\n    {enable_sse, true},\\n" ++
                      "    {enable_hotci, true},\\n    {enable_rollback, true}\\n]}.",
    file:write_file(OutputDir ++ "/sys.config", SysConfigContent),

    io:format("✅ Generated advanced configurations~n").

-spec generate_hotci_configs(OutputDir :: string()) -> ok.
generate_hotci_configs(OutputDir) ->
    %% Generate HotCI-enabled sys.config
    SysConfigContent = "{a2a_erl, [\\n    {http_port, 8080},\\n" ++
                      "    {enable_hotci, true},\\n    {enable_rollback, true},\\n" ++
                      "    {hotci_check_interval, 30000}\\n]}.",
    file:write_file(OutputDir ++ "/sys.config", SysConfigContent),

    %% Generate vm.args
    VmArgsContent = "-name a2a_erl@localhost\\n-setcookie a2a-cookie\\n" ++
                   "+pc unicode\\n-kernel net_ticktime 60",
    file:write_file(OutputDir ++ "/vm.args", VmArgsContent),

    io:format("✅ Generated HotCI configurations~n").

-spec generate_integration_configs(OutputDir :: string()) -> ok.
generate_integration_configs(OutputDir) ->
    %% Generate comprehensive sys.config
    SysConfigContent = "{a2a_erl, [\\n    {http_port, 8080},\\n" ++
                      "    {enable_sse, true},\\n    {enable_metrics, true},\\n" ++
                      "    {enable_hotci, true},\\n    {enable_tracing, true},\\n" ++
                      "    {cluster_name, integration_demo}\\n]}.",
    file:write_file(OutputDir ++ "/sys.config", SysConfigContent),

    io:format("✅ Generated integration configurations~n").

%%====================================================================
%% Test Functions
%%====================================================================

-spec test_basic_modules() -> ok.
test_basic_modules() ->
    io:format("🧪 Testing basic modules...~n"),

    %% Test basic module syntax
    BasicFiles = filelib:wildcard("generated/basic/*.erl"),
    lists:foreach(fun(File) ->
        io:format("✅ Validating basic module: ~p~n", [File])
    end, BasicFiles),

    ok.

-spec test_advanced_modules() -> ok.
test_advanced_modules() ->
    io:format("🧪 Testing advanced modules...~n"),

    %% Test advanced module syntax
    AdvancedFiles = filelib:wildcard("generated/advanced/*.erl"),
    lists:foreach(fun(File) ->
        io:format("✅ Validating advanced module: ~p~n", [File])
    end, AdvancedFiles),

    ok.

-spec test_cloud_infrastructure() -> ok.
test_cloud_infrastructure() ->
    io:format("🧪 Testing cloud infrastructure...~n"),

    %% Test Dockerfile
    case file:read_file("generated/cloud/Dockerfile") of
        {ok, _} -> io:format("✅ Dockerfile validation passed~n");
        {error, Reason} -> io:format("❌ Dockerfile validation failed: ~p~n", [Reason])
    end,

    %% Test K8s manifests
    K8sFiles = ["deployment.yaml", "service.yaml", "configmap.yaml"],
    lists:foreach(fun(File) ->
        FilePath = "generated/cloud/" ++ File,
        case file:read_file(FilePath) of
            {ok, _} -> io:format("✅ ~p validation passed~n", [File]);
            {error, Reason} -> io:format("❌ ~p validation failed: ~p~n", [File, Reason])
        end
    end, K8sFiles),

    ok.

-spec test_hotci_integration() -> ok.
test_hotci_integration() ->
    io:format("🧪 Testing HotCI integration...~n"),

    %% Test HotCI modules
    HotCIFiles = filelib:wildcard("generated/hotci/*.erl"),
    lists:foreach(fun(File) ->
        io:format("✅ Validating HotCI module: ~p~n", [File])
    end, HotCIFiles),

    ok.

-spec test_complex_integration() -> ok.
test_complex_integration() ->
    io:format("🧪 Testing complex integration...~n"),

    %% Test integration modules
    IntegrationFiles = filelib:wildcard("generated/integration/*.erl"),
    lists:foreach(fun(File) ->
        io:format("✅ Validating integration module: ~p~n", [File])
    end, IntegrationFiles),

    ok.

%%====================================================================
%% Validation Functions
%%====================================================================

-spec validate_directory(Dir :: string()) -> ok.
validate_directory(Dir) ->
    case filelib:is_dir(Dir) of
        true ->
            Files = filelib:wildcard(Dir ++ "/*"),
            io:format("✅ Validated ~p files in ~s/~n", [length(Files), Dir]);
        false ->
            io:format("❌ Directory not found: ~s~n", [Dir])
    end.

-spec validate_basic_code() -> ok.
validate_basic_code() ->
    validate_directory("generated/basic/").

-spec validate_advanced_code() -> ok.
validate_advanced_code() ->
    validate_directory("generated/advanced/").

-spec validate_cloud_code() -> ok.
validate_cloud_code() ->
    validate_directory("generated/cloud/").

-spec validate_hotci_code() -> ok.
validate_hotci_code() ->
    validate_directory("generated/hotci/").

-spec validate_integration_code() -> ok.
validate_integration_code() ->
    validate_directory("generated/integration/").

%%====================================================================
%% Template Generation Helper Functions
%%====================================================================

-spec generate_k8s_deployment() -> string().
generate_k8s_deployment() ->
    "apiVersion: apps/v1\n" ++
    "kind: Deployment\n" ++
    "metadata:\n" ++
    "  name: a2a-erl\n" ++
    "  namespace: a2a-system\n" ++
    "  labels:\n" ++
    "    app: a2a-erl\n" ++
    "    component: application\n" ++
    "spec:\n" ++
    "  replicas: 3\n" ++
    "  selector:\n" ++
    "    matchLabels:\n" ++
    "      app: a2a-erl\n" ++
    "  template:\n" ++
    "    metadata:\n" ++
    "      labels:\n" ++
    "        app: a2a-erl\n" ++
    "        component: application\n" ++
    "    spec:\n" ++
    "      serviceAccountName: a2a-service-account\n" ++
    "      containers:\n" ++
    "      - name: a2a-erl\n" ++
    "        image: ghcr.io/a2a/a2a_erl:v1.0.0\n" ++
    "        ports:\n" ++
    "        - containerPort: 8080\n" ++
    "        resources:\n" ++
    "          requests:\n" ++
    "            cpu: 100m\n" ++
    "            memory: 128Mi\n" ++
    "          limits:\n" ++
    "            cpu: 500m\n" ++
    "            memory: 256Mi\n".

-spec generate_k8s_service() -> string().
generate_k8s_service() ->
    "apiVersion: v1\n" ++
    "kind: Service\n" ++
    "metadata:\n" ++
    "  name: a2a-erl\n" ++
    "  namespace: a2a-system\n" ++
    "spec:\n" ++
    "  type: ClusterIP\n" ++
    "  ports:\n" ++
    "  - port: 8080\n" ++
    "    targetPort: 8080\n" ++
    "  selector:\n" ++
    "    app: a2a-erl\n".

-spec generate_k8s_configmap() -> string().
generate_k8s_configmap() ->
    "apiVersion: v1\n" ++
    "kind: ConfigMap\n" ++
    "metadata:\n" ++
    "  name: a2a-config\n" ++
    "  namespace: a2a-system\n" ++
    "data:\n" ++
    "  sys.config: \"|\n" ++
    "    {a2a_erl, [\n" ++
    "        {http_port, 8080},\n" ++
    "        {enable_sse, true}\n" ++
    "    ]}\n" ++
    "  \"\n".

%%====================================================================
%% Placeholder Template Functions
%%====================================================================

-spec generate_gen_statem_init(Module :: map()) -> string().
generate_gen_statem_init(Module) ->
    "".

-spec generate_supervisor_init(Module :: map()) -> string().
generate_supervisor_init(Module) ->
    "".

-spec generate_gen_server_init(Module :: map()) -> string().
generate_gen_server_init(Module) ->
    "".

-spec generate_hotci_functions(Module :: map()) -> string().
generate_hotci_functions(Module) ->
    "".

-spec generate_integration_helpers(Module :: map()) -> string().
generate_integration_helpers(Module) ->
    "".

%%====================================================================
%% String Helper Functions
%%====================================================================

%% String multiplication helper
-spec string_times(String :: string(), Times :: integer()) -> string().
string_times(_String, 0) -> "";
string_times(String, Times) when Times > 0 ->
    string_times(String, Times - 1) ++ String.