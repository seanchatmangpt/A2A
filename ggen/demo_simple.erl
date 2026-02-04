%%====================================================================
%% Module: demo_simple
%% Description: Simple demo for ggen system
%%====================================================================

-module(demo_simple).
-export([main/0]).

main() ->
    io:format("A2A Erlang Code Generation Demo~n"),
    io:format("===============================~n"),

    demo_erlang_generation(),
    demo_docker_generation(),
    demo_k8s_generation(),
    demo_helm_generation(),

    io:format("~nDemo completed! Check generated/ directory~n").

demo_erlang_generation() ->
    io:format("Generating Erlang module...~n"),

    %% Create demo Erlang module
    Content = "-module(demo_a2a_task_store).\n" ++
              "-behaviour(gen_server).\n" ++
              "\n" ++
              "-export([start_link/0, get_task/1, put_task/2]).\n" ++
              "\n" ++
              "-record(state, {\n    ets_table = undefined :: ets:tid() | undefined,\n    metrics = #{}\n}).\n" ++
              "\n" ++
              "start_link() ->\n    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).\n" ++
              "\n" ++
              "get_task(TaskId) ->\n    gen_server:call(?MODULE, {get_task, TaskId}).\n" ++
              "\n" ++
              "put_task(Task, Ttl) ->\n    gen_server:call(?MODULE, {put_task, Task, Ttl}).\n" ++
              "\n" ++
              "init(_Args) ->\n    State = #state{ets_table = ets:new(tasks, [])},\n    {ok, State}.\n" ++
              "\n" ++
              "handle_call({get_task, TaskId}, _From, State) ->\n    case ets:lookup(State#state.ets_table, TaskId) of\n        [Task] -> {reply, Task, State};\n        [] -> {reply, undefined, State}\n    end;\n\n" ++
              "handle_call({put_task, Task, Ttl}, _From, State) ->\n    TaskId = Task#task.id,\n    ets:insert(State#state.ets_table, {TaskId, Task, Ttl}),\n    {reply, ok, State}.\n",

    case filelib:ensure_dir("generated/") of
        ok ->
            case file:write_file("generated/demo_a2a_task_store.erl", Content) of
                ok ->
                    io:format("✅ Generated demo_a2a_task_store.erl~n");
                {error, Reason} ->
                    io:format("❌ Failed to write file: ~p~n", [Reason])
            end;
        {error, Reason} ->
            io:format("❌ Failed to create directory: ~p~n", [Reason])
    end.

demo_docker_generation() ->
    io:format("Generating Dockerfile...~n"),

    Content = "FROM erlang:27-alpine AS builder\n\n" ++
              "RUN apk add --no-cache git make curl\n" ++
              "WORKDIR /app\n" ++
              "COPY rebar3 /usr/local/bin/\n" ++
              "COPY rebar.config config src include /app/\n" ++
              "RUN rebar3 compile\n\n" ++
              "FROM erlang:27-alpine\n" ++
              "RUN addgroup -g 1001 -S appuser && \\\n" ++
              "    adduser -S appuser -u 1001\n" ++
              "WORKDIR /app\n" ++
              "COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/* /app\n" ++
              "RUN chown -R appuser:appuser /app\n" ++
              "USER appuser\n" ++
              "EXPOSE 8080\n" ++
              "CMD [\"/app/bin/a2a_erl\", \"foreground\"]\n",

    case file:write_file("generated/demo_Dockerfile", Content) of
        ok ->
            io:format("✅ Generated demo_Dockerfile~n");
        {error, Reason} ->
            io:format("❌ Failed to write file: ~p~n", [Reason])
    end.

demo_k8s_generation() ->
    io:format("Generating Kubernetes manifests...~n"),

    %% Deployment
    DeploymentContent = "apiVersion: apps/v1\n" ++
                       "kind: Deployment\n" ++
                       "metadata:\n" ++
                       "  name: a2a-erl\n" ++
                       "  namespace: a2a-system\n" ++
                       "spec:\n" ++
                       "  replicas: 2\n" ++
                       "  selector:\n" ++
                       "    matchLabels:\n" ++
                       "      app: a2a-erl\n" ++
                       "  template:\n" ++
                       "    metadata:\n" ++
                       "      labels:\n" ++
                       "        app: a2a-erl\n" ++
                       "    spec:\n" ++
                       "      containers:\n" ++
                       "      - name: a2a-erl\n" ++
                       "        image: ghcr.io/a2a/a2a_erl:v0.2.0\n" ++
                       "        ports:\n" ++
                       "        - containerPort: 8080\n",

    %% Service
    ServiceContent = "apiVersion: v1\n" ++
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
                    "    app: a2a-erl\n",

    case file:write_file("generated/demo_deployment.yaml", DeploymentContent) of
        ok ->
            io:format("✅ Generated demo_deployment.yaml~n");
        {error, Reason} ->
            io:format("❌ Failed to write deployment: ~p~n", [Reason])
    end,

    case file:write_file("generated/demo_service.yaml", ServiceContent) of
        ok ->
            io:format("✅ Generated demo_service.yaml~n");
        {error, Reason} ->
            io:format("❌ Failed to write service: ~p~n", [Reason])
    end.

demo_helm_generation() ->
    io:format("Generating Helm chart...~n"),

    %% Create chart directory
    ChartDir = "generated/demo_helm",
    case filelib:ensure_dir(ChartDir ++ "/") of
        ok ->
            %% Chart.yaml
            ChartContent = "apiVersion: v2\n" ++
                           "name: a2a-erl\n" ++
                           "version: 0.2.0\n" ++
                           "appVersion: 0.2.0\n" ++
                           "description: A2A Erlang Application\n",

            case file:write_file(ChartDir ++ "/Chart.yaml", ChartContent) of
                ok ->
                    io:format("✅ Generated Chart.yaml~n");
                {error, Reason} ->
                    io:format("❌ Failed to write Chart.yaml: ~p~n", [Reason])
            end,

            %% values.yaml
            ValuesContent = "replicaCount: 2\n" ++
                            "\n" ++
                            "image:\n" ++
                            "  repository: ghcr.io/a2a/a2a_erl\n" ++
                            "  pullPolicy: IfNotPresent\n" ++
                            "  tag: v0.2.0\n" ++
                            "\n" ++
                            "service:\n" ++
                            "  type: ClusterIP\n" ++
                            "  port: 8080\n",

            case file:write_file(ChartDir ++ "/values.yaml", ValuesContent) of
                ok ->
                    io:format("✅ Generated values.yaml~n");
                {error, Reason} ->
                    io:format("❌ Failed to write values.yaml: ~p~n", [Reason])
            end;
        {error, Reason} ->
            io:format("❌ Failed to create chart directory: ~p~n", [Reason])
    end.