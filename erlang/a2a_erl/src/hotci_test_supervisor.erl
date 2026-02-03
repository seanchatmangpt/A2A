%%% @doc HotCI Test Supervisor
%%%
%%% This supervisor manages test execution for the HotCI framework.
%%% It coordinates test workers and manages test timeouts.
-module(hotci_test_supervisor).
-behaviour(supervisor).

%% API
-export([start_link/0, start_test/1, get_test_status/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(TEST_TIMEOUT, 30000).  % 30 seconds per test
-define(MAX_CONCURRENT_TESTS, 5).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the test supervisor
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a test worker
-spec start_test(map()) -> {ok, pid()} | {error, term()}.
start_test(TestConfig) ->
    supervisor:start_child(?SERVER, [TestConfig]).

%% @doc Get test status
-spec get_test_status(binary()) -> {ok, map()} | {error, term()}.
get_test_status(TestId) ->
    gen_server:call(?SERVER, {get_test_status, TestId}).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    %% Define test worker specification
    ChildSpec = #{
        id => hotci_test_worker,
        start => {hotci_test_worker, start_link, []},
        restart => temporary,
        shutdown => ?TEST_TIMEOUT,
        type => worker,
        modules => [hotci_test_worker]
    },

    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5,
        period => 10,
        max_restart => 50,
        max_shutdown => infinity
    },

    {ok, {SupFlags, [ChildSpec]}}.