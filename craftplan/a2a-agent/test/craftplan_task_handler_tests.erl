%% @doc Unit tests for craftplan_task_handler module
%% Tests individual task processing, state management, and execution logic

-module(craftplan_task_handler_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_TASK_DEF, #{
    id => <<"task-123">>,
    type => <<"build">>,
    parameters => #{target => <<"dev">>},
    priority => <<"high">>,
    timeout => 300000 % 5 minutes
}).
-define(TEST_TASK_CONTEXT, #{
    agent_id => <<"craftplan-mcp">>,
    session_id => <<"session-456">>,
    user_id => <<"user-789">>
}).

%% Test suite
task_handler_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_task_creation/0,
            fun test_task_execution/0,
            fun test_task_cancellation/0,
            fun test_task_timeout/0,
            fun test_task_state_management/0,
            fun test_task_prioritization/0,
            fun test_task_retry/0,
            fun test_task_validation/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock dependencies
    meck:new(craftplan_agent_card, [passthrough]),
    meck:new(a2a_handler, [passthrough]),
    meck:new(gen_server, [passthrough]),
    meck:new(timer, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(),
    ok.

%% Test task creation
test_task_creation() ->
    % Mock task validation
    meck:expect(craftplan_agent_card, validate_task,
        fun(TaskDef) -> {ok, TaskDef} end
    ),

    % Test task creation
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(?TEST_TASK_DEF, ?TEST_TASK_CONTEXT),

    % Verify task creation
    ?_assertEqual(?TEST_TASK_DEF#{id := TaskId}, TaskState),

    % Verify task state
    ?_assertEqual(<<"created">>, maps:get(status, TaskState)),
    ?_assertEqual(?TEST_TASK_CONTEXT, maps:get(context, TaskState)).

%% Test task execution
test_task_execution() ->
    % Mock successful execution
    meck:expect(a2a_handler, execute_tool,
        fun(<<"build">>, Args) ->
            case maps:get(target, Args) of
                <<"dev">> -> {ok, #{result => <<"Dev build successful">>}};
                <<"prod">> -> {ok, #{result => <<"Prod build successful">>}}
            end
        end
    ),

    % Create and execute task
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(?TEST_TASK_DEF, ?TEST_TASK_CONTEXT),
    {ok, Result} = craftplan_task_handler:execute_task(TaskId),

    % Verify execution result
    ?_assertEqual(<<"completed">>, maps:get(status, Result)),
    ?_assertEqual(<<"Dev build successful">>, maps:get(result, Result)).

%% Test task cancellation
test_task_cancellation() ->
    % Create a running task
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(
        ?TEST_TASK_DEF#{status := <<"running">>}, ?TEST_TASK_CONTEXT
    ),

    % Mock cancellation
    meck:expect(a2a_handler, cancel_tool,
        fun(TaskId) -> ok end
    ),

    % Test task cancellation
    ?_assertEqual(ok, craftplan_task_handler:cancel_task(TaskId)),

    % Verify cancellation
    {ok, CancelledState} = craftplan_task_handler:get_task_state(TaskId),
    ?_assertEqual(<<"cancelled">>, maps:get(status, CancelledState)).

%% Test task timeout
test_task_timeout() ->
    % Mock timer setup
    meck:expect(timer, send_after,
        fun(Timeout, Pid, {timeout, TaskId}) ->
            ok
        end
    ),

    % Create task with timeout
    TimeoutTask = ?TEST_TASK_DEF#{timeout := 1000}, % 1 second
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(TimeoutTask, ?TEST_TASK_CONTEXT),

    % Test timeout handling
    % This would normally be triggered by the timer
    ?_assertEqual({timeout, TaskId}, simulate_timeout(TaskId)).

%% Test task state management
test_task_state_management() ->
    % Create task
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(?TEST_TASK_DEF, ?TEST_TASK_CONTEXT),

    % Test state transitions
    UpdatedState1 = craftplan_task_handler:update_task_state(TaskId, <<"running">>),
    ?_assertEqual(<<"running">>, maps:get(status, UpdatedState1)),

    UpdatedState2 = craftplan_task_handler:update_task_state(TaskId, <<"completed">>),
    ?_assertEqual(<<"completed">>, maps:get(status, UpdatedState2)),

    % Test state retrieval
    RetrievedState = craftplan_task_handler:get_task_state(TaskId),
    ?_assertEqual(UpdatedState2, RetrievedState).

%% Test task prioritization
test_task_prioritization() ->
    % Create tasks with different priorities
    HighPriorityTask = ?TEST_TASK_DEF#{priority := <<"high">>, id := <<"task-high">>},
    MediumPriorityTask = ?TEST_TASK_DEF#{priority := <<"medium">>, id := <<"task-medium">>},
    LowPriorityTask = ?TEST_TASK_DEF#{priority := <<"low">>, id := <<"task-low">>},

    {ok, _, _} = craftplan_task_handler:create_task(HighPriorityTask, ?TEST_TASK_CONTEXT),
    {ok, _, _} = craftplan_task_handler:create_task(MediumPriorityTask, ?TEST_TASK_CONTEXT),
    {ok, _, _} = craftplan_task_handler:create_task(LowPriorityTask, ?TEST_TASK_CONTEXT),

    % Test task ordering
    Tasks = craftplan_task_handler:get_all_tasks(),
    TaskIds = [maps:get(id, Task) || Task <- Tasks],
    ?_assertEqual([<<"task-high">>, <<"task-medium">>, <<"task-low">>], TaskIds).

%% Test task retry
test_task_retry() ->
    % Mock retryable failure
    RetryCount = 0,
    meck:expect(a2a_handler, execute_tool,
        fun(<<"build">>, _) ->
            if RetryCount < 2 ->
                {error, <<"Temporary failure">>};
            true ->
                {ok, #{result => <<"Build successful">>}}
            end
        end
    ),

    % Test task with retry
    {ok, TaskId, TaskState} = craftplan_task_handler:create_task(
        ?TEST_TASK_DEF#{max_retries := 2}, ?TEST_TASK_CONTEXT
    ),

    % Execute with retry
    Result = craftplan_task_handler:execute_task_with_retry(TaskId),

    % Verify success after retry
    ?_assertEqual(<<"completed">>, maps:get(status, Result)).

%% Test task validation
test_task_validation() ->
    % Valid task
    ?_assertEqual({ok, ?TEST_TASK_DEF}, craftplan_task_handler:validate_task(?TEST_TASK_DEF)),

    % Invalid tasks
    InvalidTask1 = ?TEST_TASK_DEF#{id := undefined},
    ?_assertEqual({error, <<"Missing task ID">>}, craftplan_task_handler:validate_task(InvalidTask1)),

    InvalidTask2 = ?TEST_TASK_DEF#{type := undefined},
    ?_assertEqual({error, <<"Missing task type">>}, craftplan_task_handler:validate_task(InvalidTask2)),

    InvalidTask3 = ?TEST_TASK_DEF#{parameters := undefined},
    ?_assertEqual({error, <<"Missing task parameters">>}, craftplan_task_handler:validate_task(InvalidTask3)).

%% Helper functions
simulate_timeout(TaskId) ->
    % Simulate timeout event
    case craftplan_task_handler:get_task_state(TaskId) of
        {ok, TaskState} ->
            if maps:get(status, TaskState) =:= <<"running">> ->
                {timeout, TaskId};
            true ->
                no_timeout
            end;
        {error, _} ->
            no_timeout
    end.

execute_with_retry(TaskId, MaxRetries) ->
    craftplan_task_handler:execute_task_with_retry(TaskId, MaxRetries).