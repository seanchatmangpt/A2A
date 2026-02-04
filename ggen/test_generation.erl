%%====================================================================
%% Module: test_generation
%% Description: Test script for ggen-based Erlang code generation system
%%====================================================================

-module(test_generation).
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
    io:format("🚀 Testing ggen-based Erlang code generation system~n"),
    io:format("~s~n", [string_times("=", 60)]),

    case parse_args(Args) of
        {help, _} ->
            show_usage();
        {test, Type} ->
            run_test(Type);
        {_, _} ->
            show_usage()
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec parse_args(Args :: list()) -> {test, Type :: string()} | {help, any()} | {error, any()}.
parse_args([]) ->
    {test, "all"};
parse_args(["--help"]) ->
    {help, ok};
parse_args(["help"]) ->
    {help, ok};
parse_args(["test"]) ->
    {test, "all"};
parse_args(["test", Type]) ->
    {test, Type};
parse_args(_) ->
    {error, invalid_args}.

-spec show_usage() -> no_return().
show_usage() ->
    io:format("Usage:~n"),
    io:format("  test_generation                    # Test all components~n"),
    io:format("  test_generation test all           # Test all components~n"),
    io:format("  test_generation test erlang        # Test Erlang generation~n"),
    io:format("  test_generation test docker       # Test Docker generation~n"),
    io:format("  test_generation test k8s           # Test Kubernetes generation~n"),
    io:format("  test_generation test helm          # Test Helm generation~n"),
    io:format("  test_generation help               # Show this help~n"),
    halt(0).

-spec run_test(Type :: string()) -> ok.
run_test("all") ->
    run_all_tests();
run_test("erlang") ->
    test_erlang_generation();
run_test("docker") ->
    test_docker_generation();
run_test("k8s") ->
    test_k8s_generation();
run_test("helm") ->
    test_helm_generation();
run_test(_) ->
    io:format("❌ Unknown test type: ~p~n", [Type]),
    halt(1).

-spec run_all_tests() -> ok.
run_all_tests() ->
    io:format("🎯 Running all tests~n"),
    io:format("~s~n", [string_times("-", 30)]),

    TestResults = [
        test_erlang_generation(),
        test_docker_generation(),
        test_k8s_generation(),
        test_helm_generation()
    ],

    Passed = lists:sum([R || R <- TestResults, R == ok]),
    Total = length(TestResults),

    io:format("~n📊 Test Results: ~p/~p passed~n", [Passed, Total]),

    case Passed of
        Total ->
            io:format("✅ All tests passed!~n");
        _ ->
            io:format("❌ Some tests failed~n"),
            halt(1)
    end.

%%====================================================================
%% Test Functions
%%====================================================================

-spec test_erlang_generation() -> ok | error.
test_erlang_generation() ->
    io:format("🔧 Testing Erlang generation... "),

    case filelib:is_dir("ontology") of
        false ->
            io:format("❌ ontology directory not found~n"),
            error;
        true ->
            case test_ontology_files() of
                ok ->
                    case test_erlang_templates() of
                        ok ->
                            io:format("✅~n"),
                            ok;
                        _ ->
                            io:format("❌ Templates missing~n"),
                            error
                    end;
                _ ->
                    io:format("❌ Ontology files missing~n"),
                    error
            end
    end.

-spec test_ontology_files() -> ok | error.
test_ontology_files() ->
    OntologyFiles = filelib:wildcard("ontology/*.ttl"),
    case OntologyFiles of
        [] ->
            error;
        _ ->
            io:format("Found ~p ontology files: ", [length(OntologyFiles)]),
            lists:foreach(fun(F) ->
                io:format("~s ", [filename:basename(F)])
            end, OntologyFiles),
            io:format("~n"),
            ok
    end.

-spec test_erlang_templates() -> ok | error.
test_erlang_templates() ->
    TemplateDirs = [
        "templates/erlang/src",
        "templates/erlang/config",
        "templates/docker",
        "templates/k8s",
        "templates/helm"
    ],

    HasTemplates = lists:any(fun(Dir) ->
        case filelib:is_dir(Dir) of
            true ->
                case filelib:wildcard(Dir ++ "/*.tera") of
                    [] -> false;
                    _ -> true
                end;
            false -> false
        end
    end, TemplateDirs),

    case HasTemplates of
        true ->
            ok;
        false ->
            error
    end.

-spec test_docker_generation() -> ok | error.
test_docker_generation() ->
    io:format("🐳 Testing Docker generation... "),

    case filelib:is_file("templates/docker/Dockerfile.tera") of
        true ->
            io:format("✅~n"),
            ok;
        false ->
            io:format("❌ Dockerfile template missing~n"),
            error
    end.

-spec test_k8s_generation() -> ok | error.
test_k8s_generation() ->
    io:format("☸️  Testing Kubernetes generation... "),

    K8sTemplates = filelib:wildcard("templates/k8s/*.tera"),
    case K8sTemplates of
        [] ->
            io:format("❌ K8s templates missing~n"),
            error;
        _ ->
            io:format("Found ~p K8s templates~n", [length(K8sTemplates)]),
            ok
    end.

-spec test_helm_generation() -> ok | error.
test_helm_generation() ->
    io:format("📦 Testing Helm generation... "),

    HelmFiles = filelib:wildcard("templates/helm/*.tera"),
    case HelmFiles of
        [] ->
            io:format("❌ Helm templates missing~n"),
            error;
        _ ->
            io:format("Found ~p Helm templates~n", [length(HelmFiles)]),
            ok
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%%====================================================================
%% Helper Functions
%%====================================================================

%% String multiplication helper
-spec string_times(String :: string(), Times :: integer()) -> string().
string_times(_String, 0) -> "";
string_times(String, Times) when Times > 0 ->
    string_times(String, Times - 1) ++ String.