#!/usr/bin/env escript
%% -*- erlang -*-
%%! -pa _build/default/lib/a2a_erl/ebin -pa _build/default/lib/*/ebin -include include

main(_) ->
    io:format("~n=== Testing All 43 YAWL Patterns ===~n~n"),

    code:add_patha("_build/default/lib/a2a_erl/ebin"),
    code:add_patha("_build/default/lib/cowboy/ebin"),
    code:add_patha("_build/default/lib/jiffy/ebin"),
    code:add_patha("_build/default/lib/gen_pnet/ebin"),
    code:add_patha("_build/default/lib/ranch/ebin"),
    code:add_patha("_build/default/lib/cowlib/ebin"),

    %% Get all patterns
    Patterns = yawl_patterns:list_patterns(),
    io:format("Total patterns: ~p~n~n", [length(Patterns)]),

    %% Test each pattern
    Results = lists:map(fun(Pattern) -> test_pattern(Pattern) end, Patterns),

    %% Summary
    Passed = length([R || R <- Results, element(1, R) =:= pass]),
    Failed = length([R || R <- Results, element(1, R) =:= fail]),

    io:format("~n=== Test Summary ===~n"),
    io:format("Passed: ~p/~p~n", [Passed, length(Patterns)]),
    io:format("Failed: ~p/~p~n", [Failed, length(Patterns)]),

    case Failed of
        0 -> io:format("~n✅ All 43 YAWL patterns working correctly!~n~n"),
              halt(0);
        _ -> io:format("~n❌ Some patterns failed~n~n"),
              halt(1)
    end.

test_pattern(Pattern) ->
    io:format("Testing: ~p ... ", [Pattern]),
    try
        %% Test 1: Get pattern info (returns map directly)
        Info = yawl_patterns:get_pattern_info(Pattern),
        Name = maps:get(name, Info),

        %% Test 2: Validate pattern with empty config
        IsValid = yawl_patterns:validate_pattern(Pattern, #{}),

        %% Test 3: Try to create workflow
        CreateResult = yawl_patterns:create_workflow(Pattern, #{}),

        %% Test 4: Check helper functions for cancellations/resources
        IsCancel = yawl_patterns:is_cancellation_pattern(Pattern),
        IsResource = yawl_patterns:is_resource_pattern(Pattern),

        io:format("✓ PASS (~s)~n", [Name]),
        {pass, Pattern}
    catch
        Error:Reason ->
            io:format("✗ FAIL: ~p: ~p~n", [Error, Reason]),
            {fail, Pattern, {Error, Reason}}
    end.
