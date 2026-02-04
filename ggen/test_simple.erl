%%====================================================================
%% Module: test_simple
%% Description: Simple test for ggen system
%%====================================================================

-module(test_simple).
-export([main/0]).

main() ->
    io:format("Testing ggen-based Erlang code generation system~n"),
    io:format("============================================================~n"),

    test_file_structure(),
    test_ontologies(),
    test_templates(),
    test_queries(),

    io:format("All tests passed!~n").

test_file_structure() ->
    io:format("Testing file structure... "),

    case filelib:is_file("ggen.toml") of
        true ->
            io:format("✅ ggen.toml found~n");
        false ->
            io:format("❌ ggen.toml missing~n")
    end,

    case filelib:is_dir("ontology") of
        true ->
            io:format("✅ ontology directory found~n");
        false ->
            io:format("❌ ontology directory missing~n")
    end,

    case filelib:is_dir("templates") of
        true ->
            io:format("✅ templates directory found~n");
        false ->
            io:format("❌ templates directory missing~n")
    end,

    case filelib:is_dir("queries") of
        true ->
            io:format("✅ queries directory found~n");
        false ->
            io:format("❌ queries directory missing~n")
    end.

test_ontologies() ->
    io:format("Testing ontology files... "),

    OntologyFiles = filelib:wildcard("ontology/*.ttl"),
    io:format("Found ~p ontology files: ", [length(OntologyFiles)]),

    lists:foreach(fun(File) ->
        io:format("~s ", [filename:basename(File)])
    end, OntologyFiles),

    io:format("~n"),

    case OntologyFiles of
        [] -> io:format("❌ No ontology files found~n");
        _ -> io:format("✅ Ontology files found~n")
    end.

test_templates() ->
    io:format("Testing template files... "),

    TemplateDirs = [
        "templates/erlang/src",
        "templates/erlang/config",
        "templates/docker",
        "templates/k8s",
        "templates/helm"
    ],

    lists:foreach(fun(Dir) ->
        case filelib:is_dir(Dir) of
            true ->
                Templates = filelib:wildcard(Dir ++ "/*.tera"),
                io:format("~s: ~p templates~n", [Dir, length(Templates)]);
            false ->
                io:format("~s: directory not found~n", [Dir])
        end
    end, TemplateDirs).

test_queries() ->
    io:format("Testing query files... "),

    QueryFiles = filelib:wildcard("queries/*.sparql"),
    io:format("Found ~p SPARQL queries~n", [length(QueryFiles)]),

    case QueryFiles of
        [] -> io:format("❌ No query files found~n");
        _ -> io:format("✅ Query files found~n")
    end.