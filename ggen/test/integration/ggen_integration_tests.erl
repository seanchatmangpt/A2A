%%====================================================================
%% Module: ggen_integration_tests
%% Description: Integration tests for end-to-end generation workflow
%%====================================================================

-module(ggen_integration_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

-define(TEST_WORKSPACE, "integration_test_workspace").
-define(TIMEOUT, 10000).  %% 10 seconds timeout
-define(GEN_TYPES, [erlang, docker, k8s, helm, all]).

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create workspace directory
    case filelib:ensure_dir(?TEST_WORKSPACE ++ "/") of
        ok ->
            %% Clean up any existing workspace
            cleanup_workspace(?TEST_WORKSPACE),

            %% Create test data
            create_test_data(),

            %% Start required applications
            ensure_applications(),

            ?TEST_WORKSPACE;
        {error, Reason} ->
            exit({failed_to_setup_workspace, Reason})
    end.

cleanup(Dir) ->
    %% Clean up workspace
    cleanup_workspace(Dir),
    %% Stop applications
    stop_applications(),
    ok.

cleanup_workspace(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                FilePath = Dir ++ "/" ++ File,
                case filelib:is_dir(FilePath) of
                    true ->
                        case file:list_dir(FilePath) of
                            {ok, SubFiles} ->
                                lists:foreach(fun(SubFile) ->
                                    SubFilePath = FilePath ++ "/" ++ SubFile,
                                    case filelib:is_dir(SubFilePath) of
                                        true ->
                                            cleanup_workspace(SubFilePath);
                                        false ->
                                            file:delete(SubFilePath)
                                    end
                                end, SubFiles);
                            {error, _} ->
                                ok
                        end,
                        file:del_dir(FilePath);
                    false ->
                        file:delete(FilePath)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    case file:del_dir(Dir) of
        ok -> ok;
        {error, _} -> ok
    end.

create_test_data() ->
    %% Create test ontology files
    TestOntology = create_test_ontology(),
    file:write_file(?TEST_WORKSPACE ++ "/test_ontology.ttl", TestOntology),

    %% Create test configuration
    TestConfig = create_test_config(),
    file:write_file(?TEST_WORKSPACE ++ "/generation_config.json", TestConfig),
    ok.

create_test_ontology() ->
    "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix a2a: <http://a2a.io/schema/> .

a2a:TaskStore rdf:type owl:Class ;
    rdfs:subClassOf a2a:Component ;
    rdfs:label \"Task Store Component\" .

a2a:TaskStore rdfs:subClassOf [
    rdf:type owl:Restriction ;
    owl:onProperty a2a:hasBehaviour ;
    owl:hasValue a2a:GenServerBehaviour
] .

a2a:MetricsCollector rdf:type owl:Class ;
    rdfs:subClassOf a2a:Component ;
    rdfs:label \"Metrics Collector Component\" .

a2a:MetricsCollector rdfs:subClassOf [
    rdf:type owl:Restriction ;
    owl:onProperty a2a:hasBehaviour ;
    owl:hasValue a2a:GenStatemBehaviour
] .

a2a:GenServerBehaviour rdf:type owl:Class ;
    rdfs:label \"Gen Server Behaviour\" .

a2a:GenStatemBehaviour rdf:type owl:Class ;
    rdfs:label \"Gen State Machine Behaviour\" .

a2a:hasBehaviour rdf:type owl:ObjectProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range a2a:Behaviour .

a2a:component_name rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range xsd:string .

a2a:hasProperty rdf:type owl:ObjectProperty ;
    rdfs:domain a2a:Component ;
    rdfs:range a2a:Property .

a2a:Property rdf:type owl:Class ;
    rdfs:label \"Component Property\" .

a2a:propertyName rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Property ;
    rdfs:range xsd:string .

a2a:propertyType rdf:type owl:DatatypeProperty ;
    rdfs:domain a2a:Property ;
    rdfs:range xsd:string .".

create_test_config() ->
    "{
    \"project_name\": \"test_a2a_app\",
    \"version\": \"0.1.0\",
    \"modules\": [
        {
            \"name\": \"task_store\",
            \"type\": \"gen_server\",
            \"properties\": [
                {
                    \"name\": \"task_queue\",
                    \"type\": \"queue()\"
                },
                {
                    \"name\": \"max_tasks\",
                    \"type\": \"integer()\"
                }
            ]
        },
        {
            \"name\": \"metrics_collector\",
            \"type\": \"gen_statem\",
            \"properties\": []
        }
    ]
}".

ensure_applications() ->
    %% Ensure required applications are running
    case application:ensure_all_started(ggen) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason} -> exit({failed_to_start_ggen, Reason})
    end,
    ok.

stop_applications() ->
    %% Stop applications in reverse order
    case application:stop(ggen) of
        ok -> ok;
        {error, _} -> ok
    end,
    ok.

%%====================================================================
%% Integration Tests
%%====================================================================

%% Test end-to-end generation workflow
end_to_end_generation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should complete end-to-end generation workflow",
                %% Generate all components
                ?_assertMatch(ok, generate_all_components(Dir)),

                %% Validate all generated files
                ?_assert(validate_all_generated_files(Dir)),

                %% Check file contents
                ?_assert(validate_file_contents(Dir)),

                %% Test compilation of generated Erlang files
                ?_assert(compile_generated_erlang_files(Dir))
            ]
        end
    }.

%% Test individual generation types
individual_generation_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            lists:map(fun(Type) ->
                io:format("Testing generation type: ~p~n", [Type]),
                ["Should generate " ++ atom_to_list(Type) ++ " components correctly",
                    ?_assertMatch(ok, generate_single_type(Dir, Type)),
                    ?_assert(validate_single_type(Dir, Type)),
                    ?_assert(validate_type_contents(Dir, Type))
                ]
            end, ?GEN_TYPES)
        end
    }.

%% Test generation with different configurations
multiple_configs_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should handle different generation configurations",
                %% Test with minimal config
                ?_assertMatch(ok, generate_with_config(Dir, minimal_config())),

                %% Test with full config
                ?_assertMatch(ok, generate_with_config(Dir, full_config())),

                %% Test with custom output directory
                ?_assertMatch(ok, generate_with_config(Dir, custom_output_config(Dir)))
            ]
        end
    }.

%% Test generation error handling
error_handling_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should handle generation errors gracefully",
                %% Test with invalid type
                ?_assertMatch({error, _}, ggen_generator:generate(invalid_type)),

                %% Test with missing output directory permission
                ?_assertMatch({error, _}, generate_invalid_output_dir()),

                %% Test with invalid configuration
                ?_assertMatch({error, _}, generate_with_invalid_config())
            ]
        end
    }.

%% Test metric collection during generation
metrics_during_generation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should collect metrics during generation",
                %% Reset metrics
                reset_metrics(),

                %% Generate all components
                Result = generate_all_components(Dir),

                %% Check metrics were updated
                ?_assert(Result =:= ok),
                ?_assertMetricsWereCollected()
            ]
        end
    }.

%% Test generation speed requirements
generation_speed_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should meet generation speed requirements",
                %% Test single generation speed
                Time1 = measure_generation_time(fun() ->
                    ggen_generator:generate(erlang, #{output_dir => Dir ++ "/single"})
                end),
                io:format("Single generation time: ~p ms~n", [Time1]),
                ?_assert(Time1 < 5000),  %% Should be less than 5 seconds

                %% Test all generation speed
                Time2 = measure_generation_time(fun() ->
                    ggen_generator:generate(all, #{output_dir => Dir ++ "/all"})
                end),
                io:format("All generation time: ~p ms~n", [Time2]),
                ?_assert(Time2 < 15000)  %% Should be less than 15 seconds
            ]
        end
    }.

%% Test template rendering
template_rendering_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should render templates correctly",
                %% Test template-specific generation
                ?_assertMatch(ok, generate_erlang_with_templates(Dir)),

                %% Verify template content
                ?_assert(validate_template_rendering(Dir))
            ]
        end
    }.

%%====================================================================
%% Test Helper Functions
%%====================================================================

generate_all_components(Dir) ->
    ggen_generator:generate(all, #{output_dir => Dir}).

generate_single_type(Dir, Type) ->
    ggen_generator:generate(Type, #{output_dir => Dir ++ "/" ++ atom_to_list(Type)}).

generate_with_config(Dir, Config) ->
    ggen_generator:generate(all, Config#{output_dir => Dir}).

generate_invalid_output_dir() ->
    ggen_generator:generate(erlang, #{output_dir => "/root/unwritable_dir"}).

generate_with_invalid_config() ->
    ggen_generator:generate(erlang, #{invalid_option => true}).

generate_erlang_with_templates(Dir) ->
    ggen_generator:generate(erlang, #{output_dir => Dir}).

minimal_config() ->
    #{output_dir => "test_output/minimal"}.

full_config() ->
    #{output_dir => "test_output/full",
      overwrite => true,
      validate => true}.

custom_output_config(Dir) ->
    #{output_dir => Dir ++ "/custom",
      overwrite => false}.

validate_all_generated_files(Dir) ->
    lists:all(fun(Type) ->
        case Type of
            all -> validate_all_types(Dir);
            _ -> validate_single_type(Dir, Type)
        end
    end, ?GEN_TYPES).

validate_all_types(Dir) ->
    lists:all(fun(Type) -> validate_single_type(Dir, Type) end, [erlang, docker, k8s, helm]).

validate_single_type(Dir, Type) ->
    TypeDir = Dir ++ "/" ++ atom_to_list(Type),
    case Type of
        erlang -> validate_erlang_files(TypeDir);
        docker -> validate_docker_files(TypeDir);
        k8s -> validate_k8s_files(TypeDir);
        helm -> validate_helm_files(TypeDir);
        all -> true
    end.

validate_erlang_files(Dir) ->
    ErlangFiles = filelib:wildcard(Dir ++ "/*.erl"),
    ConfigFiles = filelib:wildcard(Dir ++ "/config/*"),
    length(ErlangFiles) > 0 andalso length(ConfigFiles) > 0.

validate_docker_files(Dir) ->
    filelib:is_file(Dir ++ "/Dockerfile").

validate_k8s_files(Dir) ->
    K8sFiles = filelib:wildcard(Dir ++ "/*.yaml"),
    length(K8sFiles) =:= 3.

validate_helm_files(Dir) ->
    ChartDir = Dir ++ "/a2a-erl",
    filelib:is_dir(ChartDir) andalso
    filelib:is_file(ChartDir ++ "/Chart.yaml") andalso
    filelib:is_file(ChartDir ++ "/values.yaml").

validate_file_contents(Dir) ->
    %% Check generated Erlang file content
    ErlangFiles = filelib:wildcard(Dir ++ "/erlang/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} ->
                lists:member("-module(", Content) andalso lists:member("-behaviour(", Content);
            {error, _} -> false
        end
    end, ErlangFiles),

    %% Check Dockerfile content
    case file:read_file(Dir ++ "/docker/Dockerfile") of
        {ok, Content} -> lists:member("FROM erlang", Content);
        {error, _} -> false
    end,

    %% Check Kubernetes deployment
    case file:read_file(Dir ++ "/k8s/deployment.yaml") of
        {ok, Content} -> lists:member("apiVersion: apps/v1", Content);
        {error, _} -> false
    end,

    %% Check Helm chart
    case file:read_file(Dir ++ "/helm/a2a-erl/Chart.yaml") of
        {ok, Content} -> lists:member("name: a2a-erl", Content);
        {error, _} -> false
    end.

validate_type_contents(Dir, Type) ->
    TypeDir = Dir ++ "/" ++ atom_to_list(Type),
    case Type of
        erlang -> validate_erlang_content(TypeDir);
        docker -> validate_docker_content(TypeDir);
        k8s -> validate_k8s_content(TypeDir);
        helm -> validate_helm_content(TypeDir);
        all -> true
    end.

validate_erlang_content(Dir) ->
    %% Check for proper gen_server template content
    ErlangFiles = filelib:wildcard(Dir ++ "/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} ->
                lists:member("-behaviour(gen_server)", Content) orelse
                lists:member("-behaviour(gen_statem)", Content);
            {error, _} -> false
        end
    end, ErlangFiles).

validate_docker_content(Dir) ->
    case file:read_file(Dir ++ "/Dockerfile") of
        {ok, Content} -> lists:member("EXPOSE 8080", Content);
        {error, _} -> false
    end.

validate_k8s_content(Dir) ->
    case file:read_file(Dir ++ "/deployment.yaml") of
        {ok, Content} -> lists:member("containerPort: 8080", Content);
        {error, _} -> false
    end.

validate_helm_content(Dir) ->
    case file:read_file(Dir ++ "/a2a-erl/values.yaml") of
        {ok, Content} -> lists:member("port: 8080", Content);
        {error, _} -> false
    end.

validate_template_rendering(Dir) ->
    %% Check if template-specific features are present
    ErlangFiles = filelib:wildcard(Dir ++ "/*.erl"),
    lists:any(fun(File) ->
        case file:read_file(File) of
            {ok, Content} ->
                %% Check for gen_server template features
                lists:member("gen_server:start_link", Content) andalso
                lists:member("init/1", Content) andalso
                lists:member("handle_call/3", Content);
            {error, _} -> false
        end
    end, ErlangFiles).

compile_generated_erlang_files(Dir) ->
    ErlangFiles = filelib:wildcard(Dir ++ "/erlang/src/*.erl"),
    compile_files(ErlangFiles).

compile_files([]) -> true;
compile_files([File|Files]) ->
    case compile:file(File, [return_errors, debug_info]) of
        {ok, _} -> compile_files(Files);
        {error, _, _} -> false
    end.

measure_generation_time(Fun) ->
    StartTime = erlang:system_time(millisecond),
    Fun(),
    EndTime = erlang:system_time(millisecond),
    EndTime - StartTime.

reset_metrics() ->
    ggen_metrics_collector:set_metric(files_generated, 0),
    ggen_metrics_collector:set_metric(generation_time, 0),
    ggen_metrics_collector:set_metric(errors, 0),
    ggen_metrics_collector:set_metric(ontologies_processed, 0),
    ggen_metrics_collector:set_metric(templates_rendered, 0),
    ggen_metrics_collector:set_metric(sparql_queries_executed, 0),
    ok.

assertMetricsWereCollected() ->
    Metrics = ggen_metrics_collector:get_metrics(),
    FilesGenerated = maps:get(files_generated, maps:get(metrics, Metrics), 0),
    GenerationTime = maps:get(generation_time, maps:get(metrics, Metrics), 0),
    TemplatesRendered = maps:get(templates_rendered, maps:get(metrics, Metrics), 0),

    io:format("Files generated: ~p, Time: ~p ms, Templates: ~p~n",
        [FilesGenerated, GenerationTime, TemplatesRendered]),

    FilesGenerated > 0 andalso GenerationTime > 0 andalso TemplatesRendered > 0.

%%====================================================================
%% End of File
%%====================================================================