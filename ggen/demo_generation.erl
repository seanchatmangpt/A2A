%%====================================================================
%% Module: demo_generation
%% Description: Demo script showing ggen-based code generation for A2A
%%====================================================================

-module(demo_generation).
-author("a2a-ggen").
-vsn("0.2.0").

-export([main/0, main/1]).

%%====================================================================
%% Exported Functions
%%====================================================================

-spec main() -> ok | no_return().
main() ->
    main([]).

-spec main(Args :: list()) -> ok | no_return().
main(Args) ->
    io:format("🚀 A2A Erlang Code Generation Demo~n"),
    io:format("=" * 60 ++ "~n"),

    case parse_args(Args) of
        {help, _} ->
            show_usage();
        {demo, Type} ->
            run_demo(Type);
        {generate, _} ->
            generate_demo_files();
        {_, _} ->
            show_usage()
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec parse_args(Args :: list()) -> {demo, Type :: string()} | {generate, any()} | {help, any()} | {error, any()}.
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
parse_args(_) ->
    {error, invalid_args}.

-spec show_usage() -> no_return().
show_usage() ->
    io:format("Usage:~n"),
    io:format("  demo_generation                        # Run all demos~n"),
    io:format("  demo_generation demo all               # Run all demos~n"),
    io:format("  demo_generation demo erlang           # Erlang demo~n"),
    io:format("  demo_generation demo docker          # Docker demo~n"),
    io:format("  demo_generation demo k8s               # Kubernetes demo~n"),
    io:format("  demo_generation demo helm              # Helm demo~n"),
    io:format("  demo_generation generate               # Generate demo files~n"),
    io:format("  demo_generation help                   # Show this help~n"),
    halt(0).

-spec run_demo(Type :: string()) -> ok.
run_demo("all") ->
    run_all_demos();
run_demo("erlang") ->
    demo_erlang_generation();
run_demo("docker") ->
    demo_docker_generation();
run_demo("k8s") ->
    demo_k8s_generation();
run_demo("helm") ->
    demo_helm_generation();
run_demo(_) ->
    io:format("❌ Unknown demo type: ~p~n", [Type]),
    halt(1).

-spec run_all_demos() -> ok.
run_all_demos() ->
    io:format("🎯 Running all demos~n"),
    io:format("~s~n", [lists:duplicate(30, $-)]),

    demo_erlang_generation(),
    demo_docker_generation(),
    demo_k8s_generation(),
    demo_helm_generation(),

    io:format("~n🎯 Demo Summary~n"),
    io:format("=" * 40 ++ "~n"),
    io:format("✅ Generated demo files in generated/~n"),
    io:format("📋 Check generated/ directory for examples~n"),
    ok.

%%====================================================================
%% Demo Functions
%%====================================================================

-spec demo_erlang_generation() -> ok.
demo_erlang_generation() ->
    io:format("🎯 Demonstrating Erlang Code Generation~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create demo module data
    DemoData = [
        #{
            module_name => "a2a_task_store",
            behaviour_type => "gen_server",
            hotci_enabled => true,
            rollback_support => true,
            properties => [
                #{name => "ets_table", type => "ets:tid()", default => "undefined"},
                #{name => "max_size", type => "integer", default => "10000"}
            ],
            exported_functions => [
                #{name => "start_link", args => []},
                #{name => "get_task", args => ["TaskId"]},
                #{name => "put_task", args => ["Task", "Ttl"]},
                #{name => "delete_task", args => ["TaskId"]}
            ]
        },
        #{
            module_name => "a2a_task_statem",
            behaviour_type => "gen_statem",
            hotci_enabled => true,
            properties => [
                #{name => "task_timeout", type => "integer", default => "30000"}
            ],
            states => [
                #{name => "submitted", hotci_enabled => true},
                #{name => "working", hotci_enabled => true},
                #{name => "completed", hotci_enabled => true}
            ],
            exported_functions => [
                #{name => "start_link", args => ["TaskId", "TaskData"]},
                #{name => "get_state", args => []}
            ]
        }
    ],

    %% Save demo data
    case file:write_file("demo_modules.json", jsx:encode(DemoData)) of
        ok ->
            io:format("✅ Created demo module definitions~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what would be generated
    io:format("~n📋 What will be generated:~n"),
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
        end,
        io:format("    HotCI enabled: ~p~n", [maps:get(hotci_enabled, Module)])
    end, DemoData),

    ok.

-spec demo_docker_generation() -> ok.
demo_docker_generation() ->
    io:format("🎯 Demonstrating Docker Generation~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create demo Docker data
    DemoData = #{
        base_image => "erlang:27-alpine",
        port => 8080,
        hotci_enabled => true,
        health_check_interval => "30s",
        health_check_timeout => "5s",
        health_check_start_period => "5s",
        health_check_retries => 3
    },

    %% Save demo data
    case file:write_file("demo_docker.json", jsx:encode(DemoData)) of
        ok ->
            io:format("✅ Created demo Docker configuration~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what would be generated
    io:format("~n📋 What will be generated:~n"),
    io:format("  - Multi-stage Dockerfile~n"),
    io:format("  - HotCI dependencies included~n"),
    io:format("  - Health checks enabled~n"),
    io:format("  - Production-ready build~n"),

    ok.

-spec demo_k8s_generation() -> ok.
demo_k8s_generation() ->
    io:format("🎯 Demonstrating Kubernetes Generation~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create demo K8s data
    DemoData = #{
        name => "a2a-erl",
        namespace => "a2a-system",
        replicas => 3,
        app_label => "a2a-erl",
        component_label => "application",
        version_label => "v0.2.0",
        container_port => 8080,
        service_port => 8080,
        service_type => "ClusterIP",
        resource_request_cpu => "100m",
        resource_request_memory => "128Mi",
        resource_limit_cpu => "500m",
        resource_limit_memory => "256Mi",
        liveness_probe_path => "/health",
        readiness_probe_path => "/ready",
        health_check_port => 8080,
        service_account_name => "a2a-service-account",
        hotci_enabled => true,
        hotci_check_interval => "30s"
    },

    %% Save demo data
    case file:write_file("demo_k8s.json", jsx:encode(DemoData)) of
        ok ->
            io:format("✅ Created demo Kubernetes configuration~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what would be generated
    io:format("~n📋 What will be generated:~n"),
    io:format("  - deployment.yaml (3 replicas)~n"),
    io:format("  - service.yaml (ClusterIP)~n"),
    io:format("  - configmap.yaml (application config)~n"),
    io:format("  - HotCI monitoring enabled~n"),

    ok.

-spec demo_helm_generation() -> ok.
demo_helm_generation() ->
    io:format("🎯 Demonstrating Helm Chart Generation~n"),
    io:format("=" * 50 ++ "~n"),

    %% Create demo Helm data
    DemoData = #{
        chart_name => "a2a-erl",
        chart_version => "0.2.0",
        app_version => "0.2.0",
        description => "A2A Erlang Application",
        repository => "ghcr.io/a2a",
        image_tag => "v0.2.0",
        replica_count => 3,
        service => #{
            type => "ClusterIP",
            port => 8080,
            target_port => 8080
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
    },

    %% Save demo data
    case file:write_file("demo_helm.json", jsx:encode(DemoData)) of
        ok ->
            io:format("✅ Created demo Helm configuration~n");
        {error, Reason} ->
            io:format("❌ Failed to create demo data: ~p~n", [Reason])
    end,

    %% Show what would be generated
    io:format("~n📋 What will be generated:~n"),
    io:format("  - Chart.yaml~n"),
    io:format("  - values.yaml~n"),
    io:format("  - README.md~n"),
    io:format("  - Auto-scaling configuration~n"),
    io:format("  - HotCI integration~n"),

    ok.

-spec generate_demo_files() -> ok.
generate_demo_files() ->
    io:format("🎨 Creating Demo Generated Files~n"),
    io:format("=" * 40 ++ "~n"),

    %% Create generated directory
    case filelib:ensure_dir("generated/") of
        ok ->
            io:format("✅ Created generated directory~n");
        {error, Reason} ->
            io:format("❌ Failed to create directory: ~p~n", [Reason]),
            halt(1)
    end,

    %% Generate demo files
    generate_demo_task_store(),
    generate_demo_deployment(),
    generate_demo_dockerfile(),
    generate_demo_helm(),

    io:format("~n✅ Generated demo files in generated/~n").

-spec generate_demo_task_store() -> ok.
generate_demo_task_store() ->
    Module = generated/demo_a2a_task_store.erl,
    Content = "-module(demo_a2a_task_store).\n-behaviour(gen_server).\n\n"
              "-export([start_link/0, start_link/1, get_task/1, put_task/2, delete_task/1]).\n\n"
              "-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).\n\n"
              "-record(state, {\n    ets_table = undefined :: ets:tid() | undefined,\n    max_size = 10000 :: integer(),\n    metrics = #{}\n}).\n\n"
              "start_link() ->\n    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n\n"
              "start_link(Args) ->\n    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).\n\n"
              "get_task(TaskId) ->\n    gen_server:call(?MODULE, {get_task, TaskId}).\n\n"
              "put_task(Task, Ttl) ->\n    gen_server:call(?MODULE, {put_task, Task, Ttl}).\n\n"
              "delete_task(TaskId) ->\n    gen_server:call(?MODULE, {delete_task, TaskId}).\n\n"
              "init(Args) ->\n    State = init_state(#state{}, Args),\n    {ok, State}.\n\n"
              "handle_call({get_task, TaskId}, _From, State) ->\n    case ets:lookup(State#state.ets_table, TaskId) of\n        [Task] -> {reply, Task, State};\n        [] -> {reply, undefined, State}\n    end;\n\n"
              "handle_call({put_task, Task, Ttl}, _From, State) ->\n    TaskId = Task#task.id,\n    ets:insert(State#state.ets_table, {TaskId, Task, Ttl}),\n    {reply, ok, State};\n\n"
              "handle_call({delete_task, TaskId}, _From, State) ->\n    ets:delete(State#state.ets_table, TaskId),\n    {reply, ok, State};\n\n"
              "handle_call(_Request, _From, State) ->\n    {reply, {error, unknown_request}, State}.\n\n"
              "handle_cast(_Msg, State) ->\n    {noreply, State}.\n\n"
              "handle_info(_Info, State) ->\n    {noreply, State}.\n\n"
              "terminate(_Reason, State) ->\n    ets:delete(State#state.ets_table),\n    ok.\n\n"
              "code_change(_OldVsn, State, _Extra) ->\n    {ok, State}.\n\n"
              "init_state(#state{} = State, Args) ->\n    maps:fold(fun init_arg/3, State, Args).\n\n"
              "init_arg(ets_table, Tid, State) ->\n    State#state{ets_table = Tid};\n\n"
              "init_arg(max_size, Max, State) ->\n    State#state{max_size = Max};\n\n"
              "init_arg(_Key, _Value, State) ->\n    State.\n",

    case file:write_file(Module, Content) of
        ok ->
            io:format("✅ Created demo Erlang module: ~p~n", [Module]);
        {error, Reason} ->
            io:format("❌ Failed to create ~p: ~p~n", [Module, Reason])
    end.

-spec generate_demo_deployment() -> ok.
generate_demo_deployment() ->
    File = generated/demo_deployment.yaml,
    Content = "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: demo-a2a-erl\n  namespace: a2a-system\n  labels:\n    app: a2a-erl\n    component: application\n    version: v0.2.0\nspec:\n  replicas: 3\n  selector:\n    matchLabels:\n      app: a2a-erl\n  template:\n    metadata:\n      labels:\n        app: a2a-erl\n        component: application\n        version: v0.2.0\n    spec:\n      serviceAccountName: a2a-service-account\n      containers:\n      - name: a2a-erl\n        image: ghcr.io/a2a/a2a-erl:v0.2.0\n        ports:\n        - containerPort: 8080\n        resources:\n          requests:\n            cpu: 100m\n            memory: 128Mi\n          limits:\n            cpu: 500m\n            memory: 256Mi\n",

    case file:write_file(File, Content) of
        ok ->
            io:format("✅ Created demo K8s deployment: ~p~n", [File]);
        {error, Reason} ->
            io:format("❌ Failed to create ~p: ~p~n", [File, Reason])
    end.

-spec generate_demo_dockerfile() -> ok.
generate_demo_dockerfile() ->
    File = generated/demo_Dockerfile,
    Content = "FROM erlang:27-alpine AS builder\n\nRUN apk add --no-cache git make curl\nWORKDIR /app\nCOPY rebar3 /usr/local/bin/\nCOPY rebar.config.lock rebar.config config src include /app/\nRUN rebar3 compile\n\nFROM erlang:27-alpine\nRUN addgroup -g 1001 -S appuser && \\\n    adduser -S appuser -u 1001\nWORKDIR /app\nCOPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/a2a_erl /app\nCOPY --from=builder --chown=appuser:appuser /app/config /app/config\nRUN chown -R appuser:appuser /app && mkdir -p /app/log /app/data\nUSER appuser\nEXPOSE 8080\nHEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \\\n    CMD curl -f http://localhost:8080/health || exit 1\nCMD [\"/app/bin/a2a_erl\", \"foreground\"]\n",

    case file:write_file(File, Content) of
        ok ->
            io:format("✅ Created demo Dockerfile: ~p~n", [File]);
        {error, Reason} ->
            io:format("❌ Failed to create ~p: ~p~n", [File, Reason])
    end.

-spec generate_demo_helm() -> ok.
generate_demo_helm() ->
    %% Create Helm directory
    HelmDir = generated/demo_helm,
    case filelib:ensure_dir(HelmDir ++ "/") of
        ok ->
            io:format("✅ Created demo Helm directory~n");
        {error, Reason} ->
            io:format("❌ Failed to create directory: ~p~n", [Reason])
    end,

    %% Chart.yaml
    ChartFile = HelmDir ++ "/Chart.yaml",
    ChartContent = "apiVersion: v2\nname: a2a-erl\nversion: 0.2.0\nappVersion: 0.2.0\ndescription: A2A Erlang Application\n",
    file:write_file(ChartFile, ChartContent),

    %% values.yaml
    ValuesFile = HelmDir ++ "/values.yaml",
    ValuesContent = "replicaCount: 3\n\nimage:\n  repository: ghcr.io/a2a/a2a-erl\n  pullPolicy: IfNotPresent\n  tag: v0.2.0\n\nservice:\n  type: ClusterIP\n  port: 8080\n\nresources:\n  limits:\n    cpu: 500m\n    memory: 256Mi\n  requests:\n    cpu: 100m\n    memory: 128Mi\n\nhotci:\n  enabled: true\n  checkInterval: 30s\n",
    file:write_file(ValuesFile, ValuesContent),

    io:format("✅ Created demo Helm chart in: ~p~n", [HelmDir]).

%%====================================================================
%% String Helper Functions
%%====================================================================

%% String multiplication helper
-spec string_times(String :: string(), Times :: integer()) -> string().
string_times(_String, 0) -> "";
string_times(String, Times) when Times > 0 ->
    string_times(String, Times - 1) ++ String.