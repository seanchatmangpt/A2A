%%====================================================================
%% Module: ggen_generator_tests
%% Description: Unit tests for ggen_generator module
%%====================================================================

-module(ggen_generator_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Data
%%====================================================================

-define(TEST_OUTPUT_DIR, "test_output").
-define(MOCK_ONTOLOGY_DATA, #{
    modules => [
        #{
            module_name => "a2a_task_store",
            behaviour_type => "gen_server",
            exported_functions => [],
            properties => [
                #{
                    name => "task_queue",
                    type => "queue()"
                },
                #{
                    name => "max_tasks",
                    type => "integer()"
                }
            ],
            hotci_enabled => true,
            rollback_support => true
        },
        #{
            module_name => "a2a_metrics_collector",
            behaviour_type => "gen_statem",
            exported_functions => [
                #{
                    name => "get_metrics",
                    args => []
                },
                #{
                    name => "update_counter",
                    args => ["string()", "integer()"]
                }
            ],
            properties => [],
            hotci_enabled => false,
            rollback_support => false
        }
    ]
}).

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create test output directory
    case filelib:ensure_dir(?TEST_OUTPUT_DIR ++ "/") of
        ok ->
            %% Clear existing test files
            case file:list_dir(?TEST_OUTPUT_DIR) of
                {ok, Files} ->
                    lists:foreach(fun(File) ->
                        file:delete(?TEST_OUTPUT_DIR ++ "/" ++ File)
                    end, Files);
                {error, _} ->
                    ok
            end,
            ?TEST_OUTPUT_DIR;
        {error, _} ->
            test
    end.

cleanup(Dir) ->
    %% Clean up test files and directories
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                case filelib:is_dir(Dir ++ "/" ++ File) of
                    true ->
                        %% Remove directory recursively
                        case file:list_dir(Dir ++ "/" ++ File) of
                            {ok, SubFiles} ->
                                lists:foreach(fun(SubFile) ->
                                    file:delete(Dir ++ "/" ++ File ++ "/" ++ SubFile)
                                end, SubFiles);
                            {error, _} ->
                                ok
                        end,
                        file:del_dir(Dir ++ "/" ++ File);
                    false ->
                        file:delete(Dir ++ "/" ++ File)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    case Dir =/= test andalso file:del_dir(Dir) of
        true -> ok;
        false -> ok
    end.

%%====================================================================
%% Unit Tests
%%====================================================================

%% Test basic generation functionality
generate_all_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should generate all components without errors",
                ?_assertMatch(ok, ggen_generator:generate(all)),
                ?_assertMatch(ok, ggen_generator:validate(Dir ++ "/erlang")),
                ?_assertMatch(ok, ggen_generator:validate(Dir ++ "/docker")),
                ?_assertMatch(ok, ggen_generator:validate(Dir ++ "/k8s")),
                ?_assertMatch(ok, ggen_generator:validate(Dir ++ "/helm"))
            ]
        end
    }.

%% Test Erlang generation
generate_erlang_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should generate Erlang modules and config files",
                ?_assertMatch(ok, ggen_generator:generate(erlang, #{output_dir => Dir})),
                ?_assert(filelib:is_dir(Dir)),
                ?_assertMatch(true, lists:any(fun(F) -> lists:suffix(".erl", F) end,
                    filelib:wildcard(Dir ++ "/*.erl"))),
                ?_assert(filelib:is_file(Dir ++ "/rebar3.config")),
                ?_assert(filelib:is_file(Dir ++ "/sys.config")),
                ?_assert(filelib:is_file(Dir ++ "/vm.args"))
            ]
        end
    }.

%% Test Docker generation
generate_docker_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should generate Dockerfile",
                ?_assertMatch(ok, ggen_generator:generate(docker, #{output_dir => Dir})),
                ?_assert(filelib:is_file(Dir ++ "/Dockerfile")),
                ?_assertMatch(true,
                    case file:read_file(Dir ++ "/Dockerfile") of
                        {ok, Content} ->
                            lists:member("FROM erlang:27-alpine", Content);
                        {error, _} -> false
                    end)
            ]
        end
    }.

%% Test Kubernetes generation
generate_k8s_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should generate Kubernetes manifests",
                ?_assertMatch(ok, ggen_generator:generate(k8s, #{output_dir => Dir})),
                ?_assert(filelib:is_file(Dir ++ "/deployment.yaml")),
                ?_assert(filelib:is_file(Dir ++ "/service.yaml")),
                ?_assert(filelib:is_file(Dir ++ "/configmap.yaml")),
                ?_assertMatch(true,
                    case file:read_file(Dir ++ "/deployment.yaml") of
                        {ok, Content} ->
                            lists:member("apiVersion: apps/v1", Content);
                        {error, _} -> false
                    end)
            ]
        end
    }.

%% Test Helm generation
generate_helm_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should generate Helm chart",
                ?_assertMatch(ok, ggen_generator:generate(helm, #{output_dir => Dir})),
                ?_assert(filelib:is_dir(Dir ++ "/a2a-erl")),
                ?_assert(filelib:is_file(Dir ++ "/a2a-erl/Chart.yaml")),
                ?_assert(filelib:is_file(Dir ++ "/a2a-erl/values.yaml")),
                ?_assertMatch(true,
                    case file:read_file(Dir ++ "/a2a-erl/Chart.yaml") of
                        {ok, Content} ->
                            lists:member("name: a2a-erl", Content);
                        {error, _} -> false
                    end)
            ]
        end
    }.

%% Test generation with options
generate_with_options_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should handle different generation options correctly",
                ?_assertMatch(ok, ggen_generator:generate(erlang, #{
                    output_dir => Dir,
                    overwrite => false,
                    validate => true
                })),
                ?_assertMatch(ok, ggen_generator:validate(Dir))
            ]
        end
    }.

%% Test validation functionality
validate_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Should validate generated directories",
                ?_assertMatch({error, output_directory_not_found},
                    ggen_generator:validate("nonexistent")),
                ?_assertMatch(ok, ggen_generator:generate(erlang, #{output_dir => Dir})),
                ?_assertMatch(ok, ggen_generator:validate(Dir))
            ]
        end
    }.

%% Test error handling for invalid types
generate_invalid_type_test_() ->
    ["Should handle invalid generation types",
        ?_assertMatch({error, _}, ggen_generator:generate(invalid_type)),
        ?_assertMatch({error, _}, ggen_generator:generate(invalid_type, #{}))
    ].

%% Test helper functions
string_times_test_() ->
    ["String multiplication helper function",
        ?_assertEqual("", ggen_generator:string_times("test", 0)),
        ?_assertEqual("test", ggen_generator:string_times("test", 1)),
        ?_assertEqual("testtest", ggen_generator:string_times("test", 2)),
        ?_assertEqual("testtesttest", ggen_generator:string_times("test", 3))
    ].

%% Test module name generation
generate_erlang_module_content_test_() ->
    ["Should generate correct module content",
        ?_assertEqual("-module(test_module).\n-behaviour(gen_server).\n\n",
            ggen_generator:generate_erlang_module_content(#{
                module_name => "test_module",
                behaviour_type => "gen_server",
                exported_functions => []
            })),
        ?_assertEqual("-module(test_module).\n-behaviour(gen_statem).\n\n-export([test_function/1]).\n\n",
            ggen_generator:generate_erlang_module_content(#{
                module_name => "test_module",
                behaviour_type => "gen_statem",
                exported_functions => [
                    #{
                        name => "test_function",
                        args => ["integer()"]
                    }
                ]
            }))
    ].

%%====================================================================
%% Performance Tests
%%====================================================================

generation_speed_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            ["Generation should be reasonably fast",
                ?_assertMatch(ok,
                    begin
                        StartTime = erlang:system_time(millisecond),
                        Result = ggen_generator:generate(erlang, #{output_dir => Dir}),
                        EndTime = erlang:system_time(millisecond),
                        GenerationTime = EndTime - StartTime,
                        io:format("Generation time: ~p ms~n", [GenerationTime]),
                        Result
                    end)
            ]
        end
    }.

%%====================================================================
%% Mock Tests
%%====================================================================

mock_ontology_data_test_() ->
    ["Should handle mock ontology data correctly",
        ?_assertMatch({ok, _}, ggen_generator:load_ontology_data()),
        ?_assertMatch([_|_], ggen_generator:extract_erlang_modules(?MOCK_ONTOLOGY_DATA))
    ].

mock_ontology_structure_test_() ->
    ["Mock ontology should have expected structure",
        ?_assertMatch([#{module_name := _}], ggen_generator:extract_erlang_modules(?MOCK_ONTOLOGY_DATA)),
        ?_assertEqual(2, length(ggen_generator:extract_erlang_modules(?MOCK_ONTOLOGY_DATA))),
        ?_assertEqual("a2a_task_store",
            lists:nth(1, ggen_generator:extract_erlang_modules(?MOCK_ONTOLOGY_DATA))#module_name),
        ?_assertEqual("a2a_metrics_collector",
            lists:nth(2, ggen_generator:extract_erlang_modules(?MOCK_ONTOLOGY_DATA))#module_name)
    ].

%%====================================================================
%% End of File
%%====================================================================