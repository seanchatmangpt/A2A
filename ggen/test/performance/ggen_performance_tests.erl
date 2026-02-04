%%====================================================================
%% Module: ggen_performance_tests
%% Description: Performance tests for ggen generation speed and scalability
%%====================================================================

-module(ggen_performance_tests).
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

-define(TEST_OUTPUT_DIR, "performance_test_output").
-define(TIMEOUT, 60000).  %% 60 seconds timeout
-define(MIN_ACCEPTABLE_TIME_MS, 1000).  %% 1 second
-define(MAX_ACCEPTABLE_TIME_MS, 10000). %% 10 seconds
-define(LARGE_PROJECT_MODULES, 100).
-define(MEDIUM_PROJECT_MODULES, 50).
-define(SMALL_PROJECT_MODULES, 10).
-define(METRICS_INTERVAL, 100).  %% 100ms for metrics collection

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create performance test directory
    case filelib:ensure_dir(?TEST_OUTPUT_DIR ++ "/") of
        ok ->
            %% Clean up existing performance files
            cleanup_performance_files(),
            %% Warm up the system
            warm_up_system(),
            ?TEST_OUTPUT_DIR;
        {error, Reason} ->
            exit({failed_to_setup_performance, Reason})
    end.

cleanup(Dir) ->
    case Dir of
        skip_performance_tests -> ok;
        _ ->
            cleanup_performance_files(),
            %% Clean up any compiled beams
            cleanup_beam_files(),
            %% Collect performance metrics
            collect_performance_metrics()
    end,
    ok.

cleanup_performance_files() ->
    case file:list_dir(?TEST_OUTPUT_DIR) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                case filelib:is_dir(?TEST_OUTPUT_DIR ++ "/" ++ File) of
                    true ->
                        cleanup_directory(?TEST_OUTPUT_DIR ++ "/" ++ File);
                    false ->
                        file:delete(?TEST_OUTPUT_DIR ++ "/" ++ File)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    file:del_dir(?TEST_OUTPUT_DIR),
    ok.

cleanup_directory(Dir) ->
    case file:list_dir(Dir) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                case filelib:is_dir(Dir ++ "/" ++ File) of
                    true ->
                        cleanup_directory(Dir ++ "/" ++ File);
                    false ->
                        file:delete(Dir ++ "/" ++ File)
                end
            end, Files);
        {error, _} ->
            ok
    end,
    file:del_dir(Dir),
    ok.

cleanup_beam_files() ->
    EbinFiles = filelib:wildcard("ebin/*.beam"),
    lists:foreach(fun(File) ->
        file:delete(File)
    end, EbinFiles),
    ok.

warm_up_system() ->
    %% Perform a warm-up generation
    case ggen_generator:generate(erlang, #{output_dir => "warm_up", validate => false}) of
        ok -> cleanup_directory("warm_up");
        {error, _} -> ok
    end,
    %% Reset metrics
    ggen_metrics_collector:set_metric(files_generated, 0),
    ggen_metrics_collector:set_metric(generation_time, 0),
    ggen_metrics_collector:set_metric(errors, 0),
    ok.

collect_performance_metrics() ->
    %% Collect and report performance metrics
    Metrics = ggen_metrics_collector:get_metrics(),
    io:format("Performance Metrics: ~p~n", [Metrics]),
    ok.

%%====================================================================
** Performance Tests
%%====================================================================

%% Test single generation performance
single_generation_performance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Single generation should be fast",
                        ?_assert(test_single_generation_performance(Dir))]
            end
        end
    }.

%% Test generation with different module counts
scalability_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Generation should scale with module count",
                        ?_assert(test_generation_with_module_count(Dir, ?SMALL_PROJECT_MODULES)),
                        ?_assert(test_generation_with_module_count(Dir, ?MEDIUM_PROJECT_MODULES)),
                        ?_assert(test_generation_with_module_count(Dir, ?LARGE_PROJECT_MODULES))
                    ]
            end
        end
    }.

%% Test all generation performance
all_generation_performance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["All generation should be reasonable",
                        ?_assert(test_all_generation_performance(Dir))]
            end
        end
    }.

%% Test template rendering performance
template_rendering_performance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Template rendering should be efficient",
                        ?_assert(test_template_rendering_performance(Dir))]
            end
        end
    }.

%% Test concurrent generation performance
concurrent_generation_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Concurrent generation should be efficient",
                        ?_assert(test_concurrent_generation_performance(Dir))]
            end
        end
    }.

%% Test generation with validation
generation_with_validation_performance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Generation with validation should be acceptable",
                        ?_assert(test_generation_with_validation_performance(Dir))]
            end
        end
    }.

%% Test memory usage during generation
memory_usage_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Memory usage should be controlled during generation",
                        ?_assert(test_memory_usage_during_generation(Dir))]
            end
        end
    }.

%% Test repeated generation performance
repeated_generation_performance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(Dir) ->
            case Dir of
                skip_performance_tests ->
                    ["Skipping performance tests"];
                _ ->
                    ["Repeated generation should be consistent",
                        ?_assert(test_repeated_generation_performance(Dir))]
            end
        end
    }.

%%====================================================================
** Performance Test Helper Functions
%%====================================================================

test_single_generation_performance(Dir) ->
    %% Test generation of a single Erlang project
    StartTime = erlang:system_time(millisecond),
    Result = ggen_generator:generate(erlang, #{output_dir => Dir ++ "/single", validate => true}),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("Single generation time: ~p ms~n", [GenerationTime]),
    io:format("Single generation result: ~p~n", [Result]),

    %% Check performance requirements
    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS andalso
    Result =:= ok andalso
    validate_generation_output(Dir ++ "/single").

test_generation_with_module_count(Dir, ModuleCount) ->
    %% Test generation with varying module counts
    StartTime = erlang:system_time(millisecond),
    ProjectData = create_project_data(ModuleCount),
    Result = generate_project_with_data(Dir, ProjectData),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("Generation with ~p modules time: ~p ms~n", [ModuleCount, GenerationTime]),
    io:format("Generation result: ~p~n", [Result]),

    %% Scale performance expectations with module count
    AcceptableTime = ?MIN_ACCEPTABLE_TIME_MS + (ModuleCount * 50),  /// 50ms per module
    GenerationTime =< AcceptableTime andalso
    Result =:= ok andalso
    validate_generation_output(Dir).

test_all_generation_performance(Dir) ->
    %% Test generation of all components
    StartTime = erlang:system_time(millisecond),
    Result = ggen_generator:generate(all, #{output_dir => Dir ++ "/all", validate => true}),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("All generation time: ~p ms~n", [GenerationTime]),
    io:format("All generation result: ~p~n", [Result]),

    %% All generation should be reasonable but longer than single
    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS * 3 andalso
    Result =:= ok andalso
    validate_all_generation_output(Dir ++ "/all").

test_template_rendering_performance(Dir) ->
    %% Test template rendering specifically
    StartTime = erlang:system_time(millisecond),
    Result = generate_templates_only(Dir),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("Template rendering time: ~p ms~n", [GenerationTime]),
    io:format("Template rendering result: ~p~n", [Result]),

    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS andalso
    Result =:= ok andalso
    validate_template_output(Dir).

test_concurrent_generation_performance(Dir) ->
    %% Test concurrent generation of multiple types
    StartTime = erlang:system_time(millisecond),

    %% Spawn concurrent generation processes
    Pid1 = spawn(fun() -> ggen_generator:generate(erlang, #{output_dir => Dir ++ "/concurrent/erlang"}) end),
    Pid2 = spawn(fun() -> ggen_generator:generate(docker, #{output_dir => Dir ++ "/concurrent/docker"}) end),
    Pid3 = spawn(fun() -> ggen_generator:generate(k8s, #{output_dir => Dir ++ "/concurrent/k8s"}) end),

    %% Wait for all processes to complete
    wait_for_completion([Pid1, Pid2, Pid3]),

    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("Concurrent generation time: ~p ms~n", [GenerationTime]),
    io:format("Concurrent generation result: ~p~n", [check_concurrent_results(Dir)]),

    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS * 2 andalso
    validate_concurrent_output(Dir).

test_generation_with_validation_performance(Dir) ->
    %% Test generation with validation enabled
    StartTime = erlang:system_time(millisecond),
    Result = ggen_generator:generate(erlang, #{output_dir => Dir ++ "/with_validation", validate => true}),
    EndTime = erlang:system_time(millisecond),
    GenerationTime = EndTime - StartTime,

    io:format("Generation with validation time: ~p ms~n", [GenerationTime]),
    io:format("Generation with validation result: ~p~n", [Result]),

    %% Validation should add some time but still be acceptable
    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS * 1.5 andalso
    Result =:= ok andalso
    validate_generation_output(Dir ++ "/with_validation").

test_memory_usage_during_generation(Dir) ->
    %% Measure memory usage during generation
    InitialMemory = erlang:memory(total),

    StartTime = erlang:system_time(millisecond),
    Result = ggen_generator:generate(erlang, #{output_dir => Dir ++ "/memory_test"}),
    EndTime = erlang:system_time(millisecond),
    EndMemory = erlang:memory(total),

    GenerationTime = EndTime - StartTime,
    MemoryIncrease = EndMemory - InitialMemory,

    io:format("Generation time: ~p ms~n", [GenerationTime]),
    io:format("Memory increase: ~p bytes~n", [MemoryIncrease]),
    io:format("Memory usage per ms: ~p bytes/ms~n", [MemoryIncrease / GenerationTime]),

    %% Memory usage should be reasonable
    GenerationTime < ?MAX_ACCEPTABLE_TIME_MS andalso
    Result =:= ok andalso
    MemoryIncrease < 1000000,  %% Less than 1MB increase
    validate_generation_output(Dir ++ "/memory_test").

test_repeated_generation_performance(Dir) ->
    %% Test repeated generation performance
    Results = [],
    for _N <- lists:seq(1, 10),
        StartTime = erlang:system_time(millisecond),
        Result = ggen_generator:generate(erlang, #{output_dir => Dir ++ "/repeat_" ++ integer_to_list(_) ++ "/test"}),
        EndTime = erlang:system_time(millisecond),
        GenerationTime = EndTime - StartTime,
        Results = [{GenerationTime, Result} | Results],
        Result =:= ok andalso
        validate_generation_output(Dir ++ "/repeat_" ++ integer_to_list(_) ++ "/test")
    end,

    io:format("Repeated generation results: ~p~n", [Results]),

    %% All generations should succeed and be consistent
    lists:all(fun({Time, Res}) -> Time < ?MAX_ACCEPTABLE_TIME_MS andalso Res =:= ok end, Results) andalso
    check_consistency(Results).

%%====================================================================
** Test Data Creation
%%====================================================================

create_project_data(ModuleCount) ->
    %% Create mock project data for testing
    lists:map(fun(I) ->
        #{
            module_name => "module_" ++ integer_to_list(I),
            behaviour_type => case I rem 3 of
                0 -> "gen_server";
                1 -> "gen_statem";
                2 -> "supervisor"
            end,
            exported_functions => case I rem 4 of
                0 -> [];
                1 -> [
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_1",
                        args => []
                    }
                ];
                2 -> [
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_1",
                        args => ["string()"]
                    },
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_2",
                        args => ["integer()", "string()"]
                    }
                ];
                3 -> [
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_1",
                        args => ["map()"]
                    },
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_2",
                        args => ["pid()"]
                    },
                    #{
                        name => "function_" ++ integer_to_list(I) ++ "_3",
                        args => ["term()"]
                    }
                ]
            end,
            properties => case I rem 2 of
                0 -> [];
                1 -> [
                    #{
                        name => "property_" ++ integer_to_list(I),
                        type => "term()"
                    }
                ]
            end,
            hotci_enabled => I rem 4 =:= 0,
            rollback_support => I rem 4 =:= 2
        }
    end, lists:seq(1, ModuleCount)).

generate_project_with_data(Dir, ProjectData) ->
    %% Mock the generation with project data
    case filelib:ensure_dir(Dir ++ "/") of
        ok ->
            lists:foreach(fun(Module) ->
                generate_module(Dir, Module)
            end, ProjectData),
            generate_config_files(Dir),
            ok;
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

generate_module(Dir, Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module),
    Content = generate_module_content(Module),
    Filename = Dir ++ "/" ++ ModuleName ++ ".erl",

    case file:write_file(Filename, Content) of
        ok -> ok;
        {error, Reason} -> {error, {file_write_error, Filename, Reason}}
    end.

generate_module_content(Module) ->
    ModuleName = maps:get(module_name, Module),
    Behaviour = maps:get(behaviour_type, Module),

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

    Content ++ Exports ++ "\n%% Module implementation for testing~n".

generate_config_files(Dir) ->
    %% Generate config files
    Rebar3Content = "{deps, [jiffy, cowboy, lager]}.\\n{erl_opts, [debug_info]}.",
    file:write_file(Dir ++ "/rebar3.config", Rebar3Content),

    SysConfigContent = "{test_app, []}.",
    file:write_file(Dir ++ "/sys.config", SysConfigContent),

    VmArgsContent = "-name test@localhost\\n-setcookie test-cookie",
    file:write_file(Dir ++ "/vm.args", VmArgsContent),
    ok.

generate_templates_only(Dir) ->
    %% Generate only template files for performance testing
    case filelib:ensure_dir(Dir ++ "/") of
        ok ->
            %% Generate minimal Erlang project
            generate_minimal_erlang_project(Dir),
            %% Generate Docker file
            generate_minimal_dockerfile(Dir),
            ok;
        {error, Reason} ->
            {error, {output_directory_error, Reason}}
    end.

generate_minimal_erlang_project(Dir) ->
    %% Generate minimal Erlang files
    SimpleModule = "-module(simple).\n" ++
                   "-export([test/0]).\n\n" ++
                   "test() -> ok.\n",
    file:write_file(Dir ++ "/simple.erl", SimpleModule),
    ok.

generate_minimal_dockerfile(Dir) ->
    %% Generate minimal Dockerfile
    DockerfileContent = "FROM erlang:27-alpine\n" ++
                       "WORKDIR /app\n" ++
                       "COPY . .\n" ++
                       "CMD [\"rebar3\", \"shell\"]\n",
    file:write_file(Dir ++ "/Dockerfile", DockerfileContent),
    ok.

%%====================================================================
** Validation Helper Functions
%%====================================================================

validate_generation_output(Dir) ->
    ErlangFiles = filelib:wildcard(Dir ++ "/*.erl"),
    ConfigFiles = filelib:wildcard(Dir ++ "/config/*"),
    length(ErlangFiles) > 0 andalso length(ConfigFiles) > 0.

validate_all_generation_output(Dir) ->
    %% Validate all components were generated
    ErlangDir = Dir ++ "/erlang",
    DockerDir = Dir ++ "/docker",
    K8sDir = Dir ++ "/k8s",
    HelmDir = Dir ++ "/helm",

    filelib:is_dir(ErlangDir) andalso
    filelib:is_dir(DockerDir) andalso
    filelib:is_dir(K8sDir) andalso
    filelib:is_dir(HelmDir) andalso
    validate_generation_output(ErlangDir) andalso
    filelib:is_file(DockerDir ++ "/Dockerfile") andalso
    length(filelib:wildcard(K8sDir ++ "/*.yaml")) > 0 andalso
    filelib:is_dir(HelmDir ++ "/a2a-erl").

validate_template_output(Dir) ->
    ErlangFiles = filelib:wildcard(Dir ++ "/*.erl"),
    DockerFiles = filelib:wildcard(Dir ++ "/Dockerfile"),
    length(ErlangFiles) > 0 andalso length(DockerFiles) > 0.

validate_concurrent_output(Dir) ->
    %% Validate concurrent generation outputs
    ErlangDir = Dir ++ "/erlang",
    DockerDir = Dir ++ "/docker",
    K8sDir = Dir ++ "/k8s",

    filelib:is_dir(ErlangDir) andalso
    filelib:is_dir(DockerDir) andalso
    filelib:is_dir(K8sDir).

check_concurrent_results(Dir) ->
    %% Check concurrent generation results
    Results = [],

    case file:list_dir(Dir ++ "/concurrent/erlang") of
        {ok, _} -> Results = [erlang_ok | Results];
        {error, _} -> Results = [erlang_error | Results]
    end,

    case file:list_dir(Dir ++ "/concurrent/docker") of
        {ok, _} -> Results = [docker_ok | Results];
        {error, _} -> Results = [docker_error | Results]
    end,

    case file:list_dir(Dir ++ "/concurrent/k8s") of
        {ok, _} -> Results = [k8s_ok | Results];
        {error, _} -> Results = [k8s_error | Results]
    end,

    Results.

wait_for_completion([]) -> ok;
wait_for_completion([Pid|Pids]) ->
    receive
        {'EXIT', Pid, _} -> wait_for_completion(Pids)
    after 30000 ->  %% 30 second timeout
        wait_for_completion(Pids)
    end.

check_consistency([]) -> true;
check_consistency([{Time, _}|Results]) ->
    %% Check that all times are within reasonable bounds
    lists:all(fun({T, _}) -> T < ?MAX_ACCEPTABLE_TIME_MS end, Results) andalso
    check_consistency(Results).

%%====================================================================
** Performance Metrics Collection
%%====================================================================

track_performance_metrics(StartTime, ModuleCount, Type) ->
    %% Track performance metrics during generation
    CurrentTime = erlang:system_time(millisecond),
    ElapsedTime = CurrentTime - StartTime,

    %% Update metrics every METRICS_INTERVAL ms
    if ElapsedTime rem ?METRICS_INTERVAL == 0 ->
        ggen_metrics_collector:increment_metric(performance_samples, 1),
        ggen_metrics_collector:track_generation_end(ElapsedTime),
        io:format("Performance checkpoint: ~p ms elapsed for ~p modules~n",
            [ElapsedTime, ModuleCount]);
    true ->
        ok
    end.

%%====================================================================
** End of File
%%====================================================================