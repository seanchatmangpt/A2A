%%%-------------------------------------------------------------------
%%% @doc
%%% Simple test runner to verify XML parser test compilation
%%%-------------------------------------------------------------------

-module(test_runner).
-export([run/0]).

run() ->
    %% Test module compilation
    case compile:file(test/yawl_xml_parser_tests, [debug_info]) of
        {ok, Module} ->
            io:format("✓ Test module ~p compiled successfully~n", [Module]),

            %% Check test export
            Exports = Module:module_info(exports),
            case proplists:get_value(test, Exports) of
                Fun when is_function(Fun) ->
                    io:format("✓ Test function/0 found~n");
                undefined ->
                    io:format("✗ Test function/0 not found~n")
            end;

        {error, Errors, Warnings} ->
            io:format("✗ Compilation errors: ~p~n", [Errors]),
            io:format("Warnings: ~p~n", [Warnings])
    end,

    %% Test case discovery
    case compile:file(test/yawl_xml_parser_tests, [debug_info]) of
        {ok, _} ->
            Tests = discover_tests(),
            io:format("Found ~p test cases~n", [length(Tests)]),
            lists:foreach(fun(T) -> io:format("  - ~p~n", [T]) end, Tests)
    end.

discover_tests() ->
    %% This is a simplified test discovery
    %% In practice, you'd parse the AST or use EUnit's own discovery
    [
        test_parse_valid_xml,
        test_generate_xml,
        test_xml_roundtrip,
        test_schema_validation,
        test_extract_spec
    ].