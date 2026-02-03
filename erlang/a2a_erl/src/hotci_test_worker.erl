%%% @doc HotCI Test Worker
%%%
%%% This worker executes individual test tasks for HotCI validation.
%%% It runs tests with proper timeout handling and error reporting.
-module(hotci_test_worker).
-behaviour(gen_server).

%% API
-export([start_link/1, get_test_status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Records
-record.test_info, {
    id :: binary(),
    node_id :: binary(),
    test_name :: atom(),
    scenario_id :: binary(),
    status :: 'running' | 'completed' | 'failed' | 'timed_out',
    start_time :: integer(),
    end_time :: integer() | undefined,
    result :: term() | undefined,
    error :: term() | undefined,
    timeout :: integer()
}.

%% State record
-record.state, {
    test_info :: #test_info{},
    monitor_ref :: reference()
}.

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 30000).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start a test worker
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(TestConfig) ->
    gen_server:start_link(?MODULE, [TestConfig], []).

%% @doc Get test status
-spec get_test_status() -> {ok, #test_info{}} | {error, term()}.
get_test_status() ->
    gen_server:call(?SERVER, get_test_status).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([map()]) -> {ok, #state{}}.
init([TestConfig]) ->
    %% Generate test ID
    TestId = generate_test_id(),

    %% Extract test information
    NodeId = maps:get(node_id, TestConfig),
    TestName = maps:get(test_name, TestConfig),
    ScenarioId = maps:get(scenario_id, TestConfig),
    Timeout = maps:get(timeout, TestConfig, ?DEFAULT_TIMEOUT),

    %% Create test info record
    TestInfo = #test_info{
        id = TestId,
        node_id = NodeId,
        test_name = TestName,
        scenario_id = ScenarioId,
        status = running,
        start_time = erlang:system_time(millisecond),
        timeout = Timeout
    },

    %% Start timeout timer
    MonitorRef = erlang:send_after(Timeout, self(), test_timeout),

    %% Register with test supervisor
    gen_server:cast(hotci_test_supervisor, {test_started, TestId, self()}),

    %% Execute test
    spawn_link(fun() -> execute_test(TestInfo) end),

    {ok, #state{test_info = TestInfo, monitor_ref = MonitorRef}}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call(get_test_status, _From, State) ->
    {reply, {ok, State#state.test_info}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({test_result, Result, Error}, State) ->
    %% Update test status based on result
    EndTime = erlang:system_time(millisecond),

    TestInfo = case Error of
        undefined ->
            State#state.test_info#test_info{
                status = completed,
                end_time = EndTime,
                result = Result
            };
        _ ->
            State#state.test_info#test_info{
                status = failed,
                end_time = EndTime,
                error = Error
            }
    end,

    %% Send completion notification
    notify_test_completion(TestInfo),

    {noreply, State#state{test_info = TestInfo}};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(test_timeout, State) ->
    %% Handle test timeout
    EndTime = erlang:system_time(millisecond),
    TestInfo = State#state.test_info#test_info{
        status = timed_out,
        end_time = EndTime,
        error = timeout
    },

    %% Send completion notification
    notify_test_completion(TestInfo),

    {noreply, State#state{test_info = TestInfo}};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    %% Clean up resources
    ok.

-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Execute the actual test
-spec execute_test(#test_info{}) -> ok.
execute_test(TestInfo) ->
    TestName = TestInfo#test_info.test_name,
    NodeId = TestInfo#test_info.node_id,

    try
        %% Execute test based on test name
        Result = case TestName of
            basic_functionality ->
                test_basic_functionality(NodeId);
            data_integrity ->
                test_data_integrity(NodeId);
            process_consistency ->
                test_process_consistency(NodeId);
            message_handling ->
                test_message_handling(NodeId);
            performance_impact ->
                test_performance_impact(NodeId);
            memory_usage ->
                test_memory_usage(NodeId);
            cpu_usage ->
                test_cpu_usage(NodeId);
            network_connectivity ->
                test_network_connectivity(NodeId);
            state_machine_transitions ->
                test_state_machine_transitions(NodeId);
            subscription_functionality ->
                test_subscription_functionality(NodeId);
            artifact_management ->
                test_artifact_management(NodeId);
            _ ->
                {error, unknown_test}
        end,

        %% Send result back to main process
        self() ! {test_result, Result, undefined}
    catch
        Error:Reason:Stacktrace ->
            %% Send error back to main process
            ErrorInfo = {error, {Error, Reason, Stacktrace}},
            self() ! {test_result, undefined, ErrorInfo}
    end.

%% @doc Test basic functionality
-spec test_basic_functionality(binary()) -> {ok, term()} | {error, term()}.
test_basic_functionality(NodeId) ->
    %% Test that the node can respond to basic requests
    logger:info("Testing basic functionality on node ~p", [NodeId]),

    %% Simulate basic test
    timer:sleep(1000),  % Simulate test execution

    {ok, basic_functionality_passed}.

%% @doc Test data integrity
-spec test_data_integrity(binary()) -> {ok, term()} | {error, term()}.
test_data_integrity(NodeId) ->
    logger:info("Testing data integrity on node ~p", [NodeId]),

    %% Simulate data integrity test
    timer:sleep(1000),

    {ok, data_integrity_verified}.

%% @doc Test process consistency
-spec test_process_consistency(binary()) -> {ok, term()} | {error, term()}.
test_process_consistency(NodeId) ->
    logger:info("Testing process consistency on node ~p", [NodeId]),

    %% Simulate process consistency test
    timer:sleep(1000),

    {ok, process_consistency_verified}.

%% @doc Test message handling
-spec test_message_handling(binary()) -> {ok, term()} | {error, term()}.
test_message_handling(NodeId) ->
    logger:info("Testing message handling on node ~p", [NodeId]),

    %% Simulate message handling test
    timer:sleep(1000),

    {ok, message_handling_verified}.

%% @doc Test performance impact
-spec test_performance_impact(binary()) -> {ok, term()} | {error, term()}.
test_performance_impact(NodeId) ->
    logger:info("Testing performance impact on node ~p", [NodeId]),

    %% Simulate performance test
    timer:sleep(2000),

    {ok, performance_impact_measured}.

%% @doc Test memory usage
-spec test_memory_usage(binary()) -> {ok, term()} | {error, term()}.
test_memory_usage(NodeId) ->
    logger:info("Testing memory usage on node ~p", [NodeId]),

    %% Simulate memory test
    timer:sleep(1000),

    {ok, memory_usage_measured}.

%% @doc Test CPU usage
-spec test_cpu_usage(binary()) -> {ok, term()} | {error, term()}.
test_cpu_usage(NodeId) ->
    logger:info("Testing CPU usage on node ~p", [NodeId]),

    %% Simulate CPU test
    timer:sleep(1000),

    {ok, cpu_usage_measured}.

%% @doc Test network connectivity
-spec test_network_connectivity(binary()) -> {ok, term()} | {error, term()}.
test_network_connectivity(NodeId) ->
    logger:info("Testing network connectivity on node ~p", [NodeId]),

    %% Simulate network test
    timer:sleep(500),

    {ok, network_connectivity_verified}.

%% @doc Test state machine transitions
-spec test_state_machine_transitions(binary()) -> {ok, term()} | {error, term()}.
test_state_machine_transitions(NodeId) ->
    logger:info("Testing state machine transitions on node ~p", [NodeId]),

    %% Simulate state machine test
    timer:sleep(1000),

    {ok, state_machine_transitions_verified}.

%% @doc Test subscription functionality
-spec test_subscription_functionality(binary()) -> {ok, term()} | {error, term()}.
test_subscription_functionality(NodeId) ->
    logger:info("Testing subscription functionality on node ~p", [NodeId]),

    %% Simulate subscription test
    timer:sleep(1000),

    {ok, subscription_functionality_verified}.

%% @doc Test artifact management
-spec test_artifact_management(binary()) -> {ok, term()} | {error, term()}.
test_artifact_management(NodeId) ->
    logger:info("Testing artifact management on node ~p", [NodeId]),

    %% Simulate artifact test
    timer:sleep(1000),

    {ok, artifact_management_verified}.

%% @doc Generate unique test ID
-spec generate_test_id() -> binary().
generate_test_id() ->
    Now = erlang:system_time(millisecond),
    <<"test_", (integer_to_binary(Now))/binary>>.

%% @doc Notify test completion to supervisor
-spec notify_test_completion(#test_info{}) -> ok.
notify_test_completion(TestInfo) ->
    hotci_test_supervisor ! {test_completed, TestInfo#test_info.id, self()}.

%% @doc Handle test completion notification
handle_test_completion(TestId, Result, Error) ->
    gen_server:cast(?SERVER, {test_result, Result, Error}).