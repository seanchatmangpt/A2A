%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Patterns Unit Tests
%%%
%%% This module contains comprehensive unit tests for YAWL workflow patterns
%%% implementation using gen_pnet Petri net engine.
%%%
%%% Test Coverage:
%%% - Basic control-flow patterns
%%% - Advanced control-flow patterns
%%% - Cancellation patterns
%%% - Multi-instance patterns
%%% - Pattern validation
%%% - Mapping validation
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns_test).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(PATTERN_TIMEOUT, 5000).  % 5 seconds timeout
-define(DEFAULT_CONFIG, #{}).

%%====================================================================
%% Basic Control-Flow Patterns Tests
%%====================================================================

basic_sequential_test_() ->
    [{"Basic sequential pattern validation",
      fun test_basic_sequential_pattern/0},
     {"Basic sequential configuration validation",
      fun test_basic_sequential_config/0},
     {"Basic sequential execution",
      fun test_basic_sequential_execution/0}].

test_basic_sequential_pattern() ->
    Pattern = yawl_patterns:get_pattern_info(basic_sequential),

    ?assertEqual("Basic Sequential", Pattern#{
        name => "Basic Sequential",
        description := "Simple sequential execution of two tasks",
        complexity := low
    }),

    ?assert(lists:member(start, Pattern#{
        places := [start, action1, action2, end]
    })),
    ?assert(listsmember(end, Pattern#{
        places := [start, action1, action2, end]
    })).

test_basic_sequential_config() ->
    ?assert(yawl_patterns:validate_pattern(basic_sequential, ?DEFAULT_CONFIG)),
    ?assert(yawl_patterns:create_workflow(basic_sequential, #{pattern_config => ?DEFAULT_CONFIG})).