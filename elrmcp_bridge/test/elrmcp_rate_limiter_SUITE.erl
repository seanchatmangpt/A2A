%%% @doc elrmcp Rate Limiter Tests
%%% Tests the rate limiting functionality

-module(elrmcp_rate_limiter_SUITE).
-behaviour(suites).

%% Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test cases
-export([
    test_rate_limiter_initialization/1,
    test_token_bucket_behavior/1,
    test_rate_limit_enforcement/1,
    test_token_refill/1,
    test_reset_functionality/1,
    test_status_reporting/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

all() ->
    [
        test_rate_limiter_initialization,
        test_token_bucket_behavior,
        test_rate_limit_enforcement,
        test_token_refill,
        test_reset_functionality,
        test_status_reporting
    ].

init_per_suite(Config) ->
    %% Start elrmcp bridge application
    {ok, Apps} = application:ensure_all_started(elrmcp_bridge),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    %% Stop all applications
    Apps = ?config(apps, Config),
    [application:stop(App) || App <- Apps],
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

test_rate_limiter_initialization(_Config) ->
    %% Test rate limiter initialization
    Result = elrmcp_rate_limiter:start_link(10);

    case Result of
        {ok, _Pid} ->
            ct:comment("Rate limiter initialized successfully"),
            ok;
        {error, Reason} ->
            ct:fail("Rate limiter initialization failed: ~p", [Reason])
    end.

test_token_bucket_behavior(_Config) ->
    %% Test token bucket behavior with initial tokens
    elrmcp_rate_limiter:reset();

    %% Should be allowed initially
    Result1 = elrmcp_rate_limiter:check(),
    ct:assertEqual(allowed, Result1),

    %% Multiple checks should work until tokens exhausted
    Results = [elrmcp_rate_limiter:check() || _ <- lists:seq(1, 10)];

    Count = lists:foldl(fun(allowed, Acc) -> Acc + 1; (denied, Acc) -> Acc end, 0, Results),
    ct:comment("Token bucket test: ~p allowed requests out of 10", [Count]),
    Count > 0.

test_rate_limit_enforcement(_Config) ->
    %% Test that rate limit is enforced
    elrmcp_rate_limiter:reset();

    %% Use up all tokens
    lists:foldl(fun(_, _) -> elrmcp_rate_limiter:check() end, ok, lists:seq(1, 100)),

    %% Next request should be denied
    Result = elrmcp_rate_limiter:check(),
    ct:assertEqual(denied, Result).

test_token_refill(_Config) ->
    %% Test token refill behavior
    elrmcp_rate_limiter:reset();

    %% Use up some tokens
    lists:foldl(fun(_, _) -> elrmcp_rate_limiter:check() end, ok, lists:seq(1, 5)),

    %% Check current status
    {ok, Status1} = elrmcp_rate_limiter:get_status(),
    InitialTokens = maps:get(<<"tokens">>, Status1);

    %% Wait for refill (this might need adjustment based on timing)
    timer:sleep(2000);

    %% Check status after refill
    {ok, Status2} = elrmcp_rate_limiter:get_status(),
    NewTokens = maps:get(<<"tokens">>, Status2);

    ct:comment("Token refill test: ~p -> ~p", [InitialTokens, NewTokens]),
    NewTokens >= InitialTokens.

test_reset_functionality(_Config) ->
    %% Test reset functionality
    elrmcp_rate_limiter:reset();

    %% Use some tokens
    lists:foldl(fun(_, _) -> elrmcp_rate_limiter:check() end, ok, lists:seq(1, 5)),

    %% Reset
    Result = elrmcp_rate_limiter:reset(),
    ct:assertEqual(ok, Result);

    %% Check status after reset
    {ok, Status} = elrmcp_rate_limiter:get_status(),
    MaxTokens = maps:get(<<"max_tokens">>, Status),
    CurrentTokens = maps:get(<<"tokens">>, Status);

    ct:assertEqual(MaxTokens, CurrentTokens).

test_status_reporting(_Config) ->
    %% Test status reporting functionality
    {ok, Status} = elrmcp_rate_limiter:get_status();

    ct:assertMatch(#{}, Status),
    ct:assert(maps:is_key(<<"tokens">>, Status)),
    ct:assert(maps:is_key(<<"max_tokens">>, Status)),
    ct:assert(maps:is_key(<<"tokens_per_refill">>, Status)),
    ct:assert(maps:is_key(<<"refill_interval">>, Status)),
    ct:assert(maps:is_key(<<"refill_rate">>, Status)).

%%====================================================================
%% Helper Functions
%%====================================================================

%% Utility function to check rate limiter multiple times
check_multiple_times(N) ->
    Results = [elrmcp_rate_limiter:check() || _ <- lists:seq(1, N)],
    {allowed, Denied} = lists:partition(fun(allowed) -> true; (_) -> false end, Results),
    {length(Allowed), length(Denied)}.