%%====================================================================
%% Module: demo
%% Description: Comprehensive demo for A2A GGen system
%%====================================================================

-module(demo).
-export([main/0, main/1]).

%%====================================================================
%% Main Functions
%%====================================================================

main() ->
    main([]).

main(Args) ->
    io:format("🚀 A2A GGen Code Generation Demo~n"),
    io:format("===========================================~n"),
    io:format("~n"),

    case parse_args(Args) of
        {help, _} ->
            show_usage();
        {demo, Type} ->
            run_demo(Type);
        {generate, Type} ->
            run_generation(Type);
        {test, Type} ->
            run_tests(Type);
        {all, _} ->
            run_all_demos();
        {_, _} ->
            show_usage()
    end.

%%====================================================================
%% Argument Parsing
%%====================================================================

parse_args([]) ->
    {all, ok};
parse_args(["--help"]) ->
    {help, ok};
parse_args(["help"]) ->
    {help, ok};
parse_args(["demo"]) ->
    {demo, all};
parse_args(["demo", Type]) ->
    {demo, Type};
parse_args(["generate"]) ->
    {generate, all};
parse_args(["generate", Type]) ->
    {generate, Type};
parse_args(["test"]) ->
    {test, all};
parse_args(["test", Type}) ->
    {test, Type};
parse_args(["all"]) ->
    {all, ok};
parse_args(_) ->
    {error, invalid_args}.

show_usage() ->
    io:format("Usage:~n"),
    io:format("  demo                    # Run all demos and generation~n"),
    io:format("  demo erlang             # Generate Erlang modules~n"),
    io:format("  demo docker            # Generate Docker configurations~n"),
    io:format("  demo k8s                # Generate Kubernetes manifests~n"),
    io:format("  demo helm               # Generate Helm charts~n"),
    io:format("  demo cloud              # Generate all cloud configurations~n"),
    erlang:halt(0).

%%====================================================================
%% Demo Execution
%%====================================================================

run_demo("all") ->
    io:format("🎯 Running comprehensive demos~n"),
    io:format("~s~n", [string_times("=", 50)]),

    run_demo("erlang"),
    run_demo("docker"),
    run_demo("k8s"),
    run_demo("helm"),
    io:format("~n✅ All demos completed!~n");

run_demo("erlang") ->
    io:format("🔧 Erlang Module Generation Demo~n"),
    io:format("~s~n", [string_times("-", 30)]),
    generate_erlang_demo();

run_demo("docker") ->
    io:format("🐳 Docker Configuration Demo~n"),
    io:format("~s~n", [string_times("-", 30)]),
    generate_docker_demo();

run_demo("k8s") ->
    io:format("☸️  Kubernetes Manifest Demo~n"),
    io:format("~s~n", [string_times("-", 30)]),
    generate_k8s_demo();

run_demo("helm") ->
    io:format("📦 Helm Chart Demo~n"),
    io:format("~s~n", [string_times("-", 30)]),
    generate_helm_demo();

run_demo("cloud") ->
    io:format("☁️  Cloud Infrastructure Demo~n"),
    io:format("~s~n", [string_times("-", 30)]),
    generate_docker_demo(),
    generate_k8s_demo(),
    generate_helm_demo();

run_demo(_) ->
    io:format("❌ Unknown demo type~n").

%%====================================================================
%% Generation Execution
%%====================================================================

run_generation("all") ->
    io:format("🎯 Generating all components~n"),
    io:format("~s~n", [string_times("=", 50)]),

    run_generation("erlang"),
    run_generation("docker"),
    run_generation("k8s"),
    run_generation("helm"),
    io:format("~n✅ All generation completed!~n");

run_generation("erlang") ->
    io:format("📝 Generating Erlang modules~n"),
    generate_erlang_demo();

run_generation("docker") ->
    io:format("📝 Generating Docker configurations~n"),
    generate_docker_demo();

run_generation("k8s") ->
    io:format("📝 Generating Kubernetes manifests~n"),
    generate_k8s_demo();

run_generation("helm") ->
    io:format("📝 Generating Helm charts~n"),
    generate_helm_demo();

run_generation(_) ->
    io:format("❌ Unknown generation type~n").

%%====================================================================
%% Test Execution
%%====================================================================

run_tests("all") ->
    io:format("🧪 Running all tests~n"),
    io:format("~s~n", [string_times("=", 40)]),

    run_tests("erlang"),
    run_tests("docker"),
    run_tests("k8s"),
    run_tests("helm"),
    io:format("~n✅ All tests completed!~n");

run_tests("erlang") ->
    io:format("🔬 Testing Erlang generation~n"),
    test_erlang_generation();

run_tests("docker") ->
    io:format("🔬 Testing Docker generation~n"),
    test_docker_generation();

run_tests("k8s") ->
    io:format("🔬 Testing Kubernetes generation~n"),
    test_k8s_generation();

run_tests("helm") ->
    io:format("🔬 Testing Helm generation~n"),
    test_helm_generation();

run_tests(_) ->
    io:format("❌ Unknown test type~n").

run_all_demos() ->
    run_demo("all"),
    io:format("~n"),
    run_generation("all"),
    io:format("~n"),
    run_tests("all"),
    io:format("~n🎉 Comprehensive demo completed!~n").

%%====================================================================
%% Erlang Generation Demo
%%====================================================================

generate_erlang_demo() ->
    io:format("Generating Erlang modules with HotCI support...~n"),

    %% Create demo Erlang module
    Content = "-module(a2a_task_store).\n" ++
              "-behaviour(gen_server).\n" ++
              "\n" ++
              "-export([start_link/0, get_task/1, put_task/2]).\n" ++
              "\n" ++
              "-record(state, {\n    ets_table = undefined :: ets:tid() | undefined,\n    metrics = #{},\n    version = \"0.2.0\"\n}).\n" ++
              "\n" ++
              "-record(task, {\n    id :: binary(),\n    type :: binary(),\n    data :: map(),\n    created_at :: integer()\n}).\n" ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% API Functions\n" ++
              "%%====================================================================\n" ++
              "\n" ++
              "start_link() ->\n    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n" ++
              "\n" ++
              "get_task(TaskId) ->\n    gen_server:call(?MODULE, {get_task, TaskId}).\n" ++
              "\n" ++
              "put_task(Task, Ttl) ->\n    gen_server:call(?MODULE, {put_task, Task, Ttl}).\n" ++
              "\n" ++
              "%%====================================================================\n" ++
              "%% gen_server Callbacks\n" ++
              "%%====================================================================\n" ++
              "\n" ++
              "init(_Args) ->\n    State = #state{ets_table = ets:new(tasks, [])},\n    {ok, State}.\n" ++
              "\n" ++
              "handle_call({get_task, TaskId}, _From, State) ->\n    case ets:lookup(State#state.ets_table, TaskId) of\n        [Task] -> {reply, Task, State};\n        [] -> {reply, {error, not_found}, State}\n    end;\n" ++
              "\n" ++
              "handle_call({put_task, Task, Ttl}, _From, State) ->\n    TaskId = Task#task.id,\n    Expiry = os:system_time(second) + Ttl,\n    ets:insert(State#state.ets_table, {TaskId, Task, Expiry}),\n    {reply, ok, State}.\n",

    write_file_with_content("generated/demo_a2a_task_store.erl", Content),
    io:format("✅ Generated demo_a2a_task_store.erl~n").

%%====================================================================
%% Docker Generation Demo
%%====================================================================

generate_docker_demo() ->
    io:format("Generating Docker configurations...~n"),

    %% Create production Dockerfile
    Content = "FROM erlang:27-alpine AS builder\n\n" ++
              "# Install build dependencies\n" ++
              "RUN apk add --no-cache git make curl\n" ++
              "WORKDIR /app\n" ++
              "\n" ++
              "# Copy rebar and dependencies\n" ++
              "COPY rebar3 /usr/local/bin/\n" ++
              "COPY rebar.config config src include /app/\n" ++
              "\n" ++
              "# Build the release\n" ++
              "RUN rebar3 release\n\n" ++
              "# Final stage\n" ++
              "FROM erlang:27-alpine\n" ++
              "\n" ++
              "# Create non-root user\n" ++
              "RUN addgroup -g 1001 -S appuser && \\\\\n" ++
              "    adduser -S appuser -u 1001\n" ++
              "WORKDIR /app\n" ++
              "\n" ++
              "# Copy from builder\n" ++
              "COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/* /app\n" ++
              "RUN chown -R appuser:appuser /app\n" ++
              "USER appuser\n" ++
              "\n" ++
              "# Expose ports\n" ++
              "EXPOSE 8080 8081\n" ++
              "\n" ++
              "# Health check\n" ++
              "HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \\\n" ++
              "    CMD curl -f http://localhost:8080/health || exit 1\n" ++
              "\n" ++
              "# Start the application\n" ++
              "CMD [\"/app/bin/a2a_erl\", \"foreground\"]\n",

    write_file_with_content("generated/demo_Dockerfile", Content),
    io:format("✅ Generated demo_Dockerfile~n").

%%====================================================================
%% Kubernetes Generation Demo
%%====================================================================

generate_k8s_demo() ->
    io:format("Generating Kubernetes manifests...~n"),

    %% Create Deployment
    DeploymentContent = "apiVersion: apps/v1\n" ++
                       "kind: Deployment\n" ++
                       "metadata:\n" ++
                       "  name: a2a-erl\n" ++
                       "  namespace: a2a-system\n" ++
                       "  labels:\n" ++
                       "    app: a2a-erl\n" ++
                       "    component: application\n" ++
                       "    version: \"0.2.0\"\n" ++
                       "spec:\n" ++
                       "  replicas: 2\n" ++
                       "  selector:\n" ++
                       "    matchLabels:\n" ++
                       "      app: a2a-erl\n" ++
                       "  template:\n" ++
                       "    metadata:\n" ++
                       "      labels:\n" ++
                       "        app: a2a-erl\n" ++
                       "      annotations:\n" ++
                       "        prometheus.io/scrape: \"true\"\n" ++
                       "        prometheus.io/port: \"8081\"\n" ++
                       "        prometheus.io/path: \"/metrics\"\n" ++
                       "    spec:\n" ++
                       "      securityContext:\n" ++
                       "        runAsUser: 1000\n" ++
                       "        runAsGroup: 1000\n" ++
                       "        fsGroup: 1000\n" ++
                       "      containers:\n" ++
                       "      - name: a2a-erl\n" ++
                       "        image: ghcr.io/a2a/a2a_erl:v0.2.0\n" ++
                       "        ports:\n" ++
                       "        - containerPort: 8080\n" ++
                       "        - containerPort: 8081\n" ++
                       "        resources:\n" ++
                       "          requests:\n" ++
                       "            cpu: \"100m\"\n" ++
                       "            memory: \"128Mi\"\n" ++
                       "          limits:\n" ++
                       "            cpu: \"500m\"\n" ++
                       "            memory: \"256Mi\"\n" ++
                       "        livenessProbe:\n" ++
                       "          httpGet:\n" ++
                       "            path: /health\n" ++
                       "            port: 8080\n" ++
                       "          initialDelaySeconds: 30\n" ++
                       "          periodSeconds: 30\n" ++
                       "        readinessProbe:\n" ++
                       "          httpGet:\n" ++
                       "            path: /health\n" ++
                       "            port: 8080\n" ++
                       "          initialDelaySeconds: 5\n" ++
                       "          periodSeconds: 10\n",

    write_file_with_content("generated/demo_deployment.yaml", DeploymentContent),
    io:format("✅ Generated demo_deployment.yaml~n").

%%====================================================================
%% Helm Generation Demo
%%====================================================================

generate_helm_demo() ->
    io:format("Generating Helm chart...~n"),

    %% Create Chart.yaml
    ChartContent = "apiVersion: v2\n" ++
                   "name: a2a-erl\n" ++
                   "version: 0.2.0\n" ++
                   "appVersion: \"0.2.0\"\n" ++
                   "description: A2A Erlang Application Helm Chart\n" ++
                   "type: application\n" ++
                   "keywords:\n" ++
                   "  - erlang\n" ++
                   "  - a2a\n" ++
                   "  - task-queue\n" ++
                   "home: https://github.com/a2a/ggen\n" ++
                   "sources:\n" ++
                   "  - https://github.com/a2a/ggen\n" ++
                   "maintainers:\n" ++
                   "  - name: A2A Team\n" ++
                   "    email: dev@a2a.com\n" ++
                   "annotations:\n" ++
                   "  artifacthub.io/changes: |\n" ++
                   "    - Added support for horizontal pod autoscaling\n" ++
                   "    - Added Prometheus metrics integration\n" ++
                   "  artifacthub.io/images: |\n" ++
                   "    - name: a2a-erl\n" ++
                   "      image: ghcr.io/a2a/a2a_erl:v0.2.0\n" ++
                   "      maintainers:\n" ++
                   "        - name: A2A Team\n" ++
                   "      tags:\n" ++
                   "        - erlang\n" ++
                   "        - a2a\n" ++
                   "        - task-processing\n" ++
                   "      urls:\n" ++
                   "        - https://github.com/a2a/ggen",

    write_file_with_content("generated/demo_helm/Chart.yaml", ChartContent),
    io:format("✅ Generated Chart.yaml~n"),

    %% Create values.yaml
    ValuesContent = "replicaCount: 2\n" ++
                    "\n" ++
                    "image:\n" ++
                    "  repository: ghcr.io/a2a/a2a_erl\n" ++
                    "  pullPolicy: IfNotPresent\n" ++
                    "  tag: \"v0.2.0\"\n" ++
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
                    "autoscaling:\n" ++
                    "  enabled: false\n" ++
                    "  minReplicas: 1\n" ++
                    "  maxReplicas: 5\n" ++
                    "  targetCPUUtilizationPercentage: 80\n" ++
                    "  targetMemoryUtilizationPercentage: 80\n" ++
                    "\n" ++
                    "podAnnotations:\n" ++
                    "  prometheus.io/scrape: \"true\"\n" ++
                    "  prometheus.io/port: \"8081\"\n" ++
                    "  prometheus.io/path: \"/metrics\"\n" ++
                    "\n" ++
                    "podSecurityContext:\n" ++
                    "  runAsUser: 1000\n" ++
                    "  runAsGroup: 1000\n" ++
                    "  fsGroup: 1000\n" ++
                    "\n" ++
                    "securityContext:\n" ++
                    "  runAsUser: 1000\n" ++
                    "  runAsGroup: 1000\n" ++
                    "  fsGroup: 1000\n",

    case file:write_file("generated/demo_helm/values.yaml", ValuesContent) of
        ok ->
            io:format("✅ Generated values.yaml~n");
        {error, Reason} ->
            io:format("❌ Failed to write values.yaml: ~p~n", [Reason])
    end.

%%====================================================================
%% Test Functions
%%====================================================================

test_erlang_generation() ->
    case filelib:is_file("generated/demo_a2a_task_store.erl") of
        true ->
            io:format("✅ Erlang generation test passed~n");
        false ->
            io:format("❌ Erlang generation test failed - file missing~n")
    end.

test_docker_generation() ->
    case filelib:is_file("generated/demo_Dockerfile") of
        true ->
            io:format("✅ Docker generation test passed~n");
        false ->
            io:format("❌ Docker generation test failed - file missing~n")
    end.

test_k8s_generation() ->
    case (filelib:is_file("generated/demo_deployment.yaml") andalso
         filelib:is_file("generated/demo_service.yaml")) of
        true ->
            io:format("✅ Kubernetes generation test passed~n");
        false ->
            io:format("❌ Kubernetes generation test failed - files missing~n")
    end.

test_helm_generation() ->
    case (filelib:is_file("generated/demo_helm/Chart.yaml") andalso
         filelib:is_file("generated/demo_helm/values.yaml")) of
        true ->
            io:format("✅ Helm generation test passed~n");
        false ->
            io:format("❌ Helm generation test failed - files missing~n")
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

write_file_with_content(Filename, Content) ->
    case filelib:ensure_dir(filename:dirname(Filename) ++ "/") of
        ok ->
            case file:write_file(Filename, Content) of
                ok -> ok;
                {error, Reason} -> io:format("❌ Failed to write ~p: ~p~n", [Filename, Reason])
            end;
        {error, Reason} ->
            io:format("❌ Failed to create directory for ~p: ~p~n", [Filename, Reason])
    end.

string_times(_String, 0) -> "";
string_times(String, Times) when Times > 0 ->
    string_times(String, Times - 1) ++ String.