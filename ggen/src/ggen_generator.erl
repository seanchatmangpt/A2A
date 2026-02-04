%%====================================================================
%% Module: ggen_generator
%% Description: Main code generation logic for A2A Erlang applications
%%====================================================================

-module(ggen_generator).
-author("a2a-ggen").
-vsn("0.2.0").

-export([generate/1, generate/2, validate/1]).

%%====================================================================
%% Types
%%====================================================================

-type generation_type() :: all | erlang | docker | k8s | helm.
-type generation_options() :: #{
    type => generation_type(),
    output_dir => string(),
    overwrite => boolean(),
    validate => boolean()
}.

%%====================================================================
%% Exported Functions
%%====================================================================

-spec generate(Type :: generation_type() | all) -> ok | {error, term()}.
generate(Type) when Type =:= all; Type =:= erlang; Type =:= docker; Type =:= k8s; Type =:= helm ->
    generate(Type, #{}).

-spec generate(Type :: generation_type() | all, Options :: generation_options()) -> ok | {error, term()}.
generate(Type, Options) ->
    ggen_metrics_collector:track_generation_start(),

    StartTime = erlang:system_time(millisecond),

    Result = case Type of
        all ->
            generate_all(Options);
        erlang ->
            generate_erlang(Options);
        docker ->
            generate_docker(Options);
        k8s ->
            generate_k8s(Options);
        helm ->
            generate_helm(Options)
    end,

    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    ggen_metrics_collector:track_generation_end(GenerationTime),

    case Result of
        ok ->
            io:format("✅ Generation completed in ~p ms~n", [GenerationTime]),
            ok;
        {error, Reason} ->
            ggen_metrics_collector:track_error(Reason),
            {error, Reason}
    end.

-spec validate(Output :: string()) -> ok | {error, term()}.
validate(Output) ->
    case filelib:is_dir(Output) of
        false ->
            {error, output_directory_not_found};
        true ->
            validate_generated_files(Output)
    end.

%%====================================================================
%% Internal Generation Functions
%%====================================================================

-spec generate_all(Options :: generation_options()) -> ok | {error, term()}.
generate_all(Options) ->
    io:format("🚀 Generating all components~n"),
    io:format("~s~n", [lists:duplicate(40, $-)]),

    Steps = [
        {erlang, "Erlang modules"},
        {docker, "Docker configuration"},
        {k8s, "Kubernetes manifests"},
        {helm, "Helm charts"}
    ],

    lists:foldl(fun({Type, Desc}, Result) ->
        case Result of
            ok ->
                io:format("📋 Generating ~s...~n", [Desc]),
                case generate(Type, Options#{validate => true}) of
                    ok ->
                        ggen_metrics_collector:track_template_rendered(),
                        ok;
                    {error, _} = Error ->
                        Error
                end;
            {error, _} = Error ->
                Error
        end
    end, ok, Steps).

-spec generate_erlang(Options :: generation_options()) -> ok | {error, term()}.
generate_erlang(Options) ->
    OutputDir = maps:get(output_dir, Options, "generated/erlang"),

    %% Ensure output directory exists
    case filelib:ensure_dir(OutputDir ++ "/") of
        ok ->
            generate_erlang_modules(OutputDir),
            generate_erlang_config(OutputDir),
            validate_erlang_generation(OutputDir);
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

-spec generate_docker(Options :: generation_options()) -> ok | {error, term()}.
generate_docker(Options) ->
    OutputDir = maps:get(output_dir, Options, "generated/docker"),

    case filelib:ensure_dir(OutputDir ++ "/") of
        ok ->
            generate_dockerfile(OutputDir),
            validate_docker_generation(OutputDir);
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

-spec generate_k8s(Options :: generation_options()) -> ok | {error, term()}.
generate_k8s(Options) ->
    OutputDir = maps:get(output_dir, Options, "generated/k8s"),

    case filelib:ensure_dir(OutputDir ++ "/") of
        ok ->
            generate_k8s_manifests(OutputDir),
            validate_k8s_generation(OutputDir);
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

-spec generate_helm(Options :: generation_options()) -> ok | {error, term()}.
generate_helm(Options) ->
    OutputDir = maps:get(output_dir, Options, "generated/helm"),

    case filelib:ensure_dir(OutputDir ++ "/") of
        ok ->
            generate_helm_chart(OutputDir),
            validate_helm_generation(OutputDir);
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

%%====================================================================
%% Erlang Generation
%%====================================================================

-spec generate_erlang_modules(OutputDir :: string()) -> ok.
generate_erlang_modules(OutputDir) ->
    %% Parse ontologies to extract modules
    case load_ontology_data() of
        {ok, OntologyData} ->
            Modules = extract_erlang_modules(OntologyData),
            lists:foreach(fun(Module) ->
                generate_erlang_module(OutputDir, Module)
            end, Modules);
        {error, Reason} ->
            {error, {ontology_parse_error, Reason}}
    end.

-spec generate_erlang_module(OutputDir :: string(), Module :: map()) -> ok.
generate_erlang_module(OutputDir, Module) ->
    ModuleName = maps:get(module_name, Module),
    Content = generate_erlang_module_content(Module),
    Filename = OutputDir ++ "/" ++ ModuleName ++ ".erl",

    case file:write_file(Filename, Content) of
        ok ->
            io:format("✅ Generated ~s~n", [Filename]),
            ok;
        {error, Reason} ->
            {error, {file_write_error, Filename, Reason}}
    end.

-spec generate_erlang_module_content(Module :: map()) -> string().
generate_erlang_module_content(Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module, "gen_server"),

    Content = "-module(" ++ ModuleName ++ ").\n" ++
              "-behaviour(" ++ Behaviour ++ ").\n\n",

    %% Add exports
    Exports = case maps:get(exported_functions, Module, []) of
        [] -> [];
        Funs ->
            ExportsStr = lists:map(fun(Fun) ->
                FunName = maps:get(name, Fun),
                Args = case maps:get(args, Fun, []) of
                    [] -> "";
                    ArgsList -> "(" ++ string:join(ArgsList, ", ") ++ ")"
                end,
                "    " ++ FunName ++ Args
            end, Funs),
            "-export([" ++ string:join(ExportsStr, ",\n") ++ "]).\n"
    end,

    Content ++ Exports ++ "\n%% Module implementation will be generated based on ontology~n".

-spec generate_erlang_config(OutputDir :: string()) -> ok.
generate_erlang_config(OutputDir) ->
    %% Generate rebar3 config
    Rebar3Content = generate_rebar3_config(),
    file:write_file(OutputDir ++ "/rebar3.config", Rebar3Content),

    %% Generate sys.config
    SysConfigContent = generate_sys_config(),
    file:write_file(OutputDir ++ "/sys.config", SysConfigContent),

    %% Generate vm.args
    VmArgsContent = generate_vm_args(),
    file:write_file(OutputDir ++ "/vm.args", VmArgsContent).

%%====================================================================
%% Docker Generation
%%====================================================================

-spec generate_dockerfile(OutputDir :: string()) -> ok.
generate_dockerfile(OutputDir) ->
    Content = "FROM erlang:27-alpine AS builder\n\n" ++
              "RUN apk add --no-cache git make curl\n" ++
              "WORKDIR /app\n" ++
              "COPY rebar3 /usr/local/bin/\n" ++
              "COPY rebar.config.rebar.config config src include /app/\n" ++
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

    file:write_file(OutputDir ++ "/Dockerfile", Content).

%%====================================================================
%% Kubernetes Generation
%%====================================================================

-spec generate_k8s_manifests(OutputDir :: string()) -> ok.
generate_k8s_manifests(OutputDir) ->
    %% Generate deployment
    DeploymentContent = generate_k8s_deployment(),
    file:write_file(OutputDir ++ "/deployment.yaml", DeploymentContent),

    %% Generate service
    ServiceContent = generate_k8s_service(),
    file:write_file(OutputDir ++ "/service.yaml", ServiceContent),

    %% Generate configmap
    ConfigMapContent = generate_k8s_configmap(),
    file:write_file(OutputDir ++ "/configmap.yaml", ConfigMapContent).

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
    "  replicas: 2\n" ++
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
    "        image: ghcr.io/a2a/a2a_erl:v0.2.0\n" ++
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
    "        {enable_sse, true},\n" ++
    "        {enable_metrics, true}\n" ++
    "    ]}\n" ++
    "  \"\n".

%%====================================================================
%% Helm Generation
%%====================================================================

-spec generate_helm_chart(OutputDir :: string()) -> ok.
generate_helm_chart(OutputDir) ->
    %% Create chart directory
    ChartDir = OutputDir ++ "/a2a-erl",
    filelib:ensure_dir(ChartDir ++ "/"),

    %% Generate Chart.yaml
    ChartContent = "apiVersion: v2\n" ++
                   "name: a2a-erl\n" ++
                   "version: 0.2.0\n" ++
                   "appVersion: 0.2.0\n" ++
                   "description: A2A Erlang Application\n",
    file:write_file(ChartDir ++ "/Chart.yaml", ChartContent),

    %% Generate values.yaml
    ValuesContent = "replicaCount: 2\n" ++
                    "\n" ++
                    "image:\n" ++
                    "  repository: ghcr.io/a2a/a2a_erl\n" ++
                    "  pullPolicy: IfNotPresent\n" ++
                    "  tag: v0.2.0\n" ++
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
                    "    memory: 128Mi\n",
    file:write_file(ChartDir ++ "/values.yaml", ValuesContent).

%%====================================================================
%% Validation Functions
%%====================================================================

-spec validate_erlang_generation(OutputDir :: string()) -> ok | {error, term()}.
validate_erlang_generation(OutputDir) ->
    ErlangFiles = filelib:wildcard(OutputDir ++ "/*.erl"),
    case ErlangFiles of
        [] ->
            {error, no_erlang_files_generated};
        _ ->
            io:format("✅ Generated ~p Erlang files~n", [length(ErlangFiles)]),
            ok
    end.

-spec validate_docker_generation(OutputDir :: string()) -> ok | {error, term()}.
validate_docker_generation(OutputDir) ->
    case filelib:is_file(OutputDir ++ "/Dockerfile") of
        true ->
            io:format("✅ Generated Dockerfile~n"),
            ok;
        false ->
            {error, dockerfile_not_generated}
    end.

-spec validate_k8s_generation(OutputDir :: string()) -> ok | {error, term()}.
validate_k8s_generation(OutputDir) ->
    K8sFiles = filelib:wildcard(OutputDir ++ "/*.yaml"),
    case K8sFiles of
        [] ->
            {error, no_k8s_files_generated};
        _ ->
            io:format("✅ Generated ~p Kubernetes manifest files~n", [length(K8sFiles)]),
            ok
    end.

-spec validate_helm_generation(OutputDir :: string()) -> ok | {error, term()}.
validate_helm_generation(OutputDir) ->
    ChartDir = OutputDir ++ "/a2a-erl",
    case filelib:is_dir(ChartDir) of
        true ->
            ChartFiles = filelib:wildcard(ChartDir ++ "/*"),
            io:format("✅ Generated Helm chart with ~p files~n", [length(ChartFiles)]),
            ok;
        false ->
            {error, helm_chart_not_generated}
    end.

-spec validate_generated_files(Output :: string()) -> ok | {error, term()}.
validate_generated_files(Output) ->
    io:format("🔍 Validating generated files in ~s/~n", [Output]),

    SubDirs = ["erlang", "docker", "k8s", "helm"],
    lists:foldl(fun(Dir, Result) ->
        case Result of
            ok ->
                DirPath = Output ++ "/" ++ Dir,
                case filelib:is_dir(DirPath) of
                    true ->
                        validate_directory(DirPath);
                    false ->
                        {error, {directory_missing, Dir}}
                end;
            {error, _} = Error ->
                Error
        end
    end, ok, SubDirs).

-spec validate_directory(Dir :: string()) -> ok | {error, term()}.
validate_directory(Dir) ->
    Files = filelib:wildcard(Dir ++ "/*"),
    case Files of
        [] ->
            {error, {empty_directory, Dir}};
        _ ->
            io:format("✅ Validated ~p files in ~s/~n", [length(Files), Dir]),
            ok
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

-spec load_ontology_data() -> {ok, map()} | {error, term()}.
load_ontology_data() ->
    %% TODO: Implement ontology parsing
    %% For now, return mock data
    {ok, #{
        modules => [
            #{
                module_name => "a2a_task_store",
                behaviour_type => "gen_server",
                exported_functions => []
            }
        ]
    }}.

-spec extract_erlang_modules(OntologyData :: map()) -> list().
extract_erlang_modules(OntologyData) ->
    maps:get(modules, OntologyData, []).

-spec generate_rebar3_config() -> string().
generate_rebar3_config() ->
    "{deps, [jiffy, cowboy, lager]}.\\n{erl_opts, [debug_info]}.".

-spec generate_sys_config() -> string().
generate_sys_config() ->
    "{a2a_erl, [\n    {http_port, 8080},\n    {enable_sse, true}\n]}.".

-spec generate_vm_args() -> string().
generate_vm_args() ->
    "-name a2a_erl@localhost\\n-setcookie a2a-cookie".

