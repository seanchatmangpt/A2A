%% @doc Unit tests for craftplan_a2a_server module
%% Tests A2A task management, WebSocket connections, and message handling

-module(craftplan_a2a_server_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_AGENT_ID, <<"craftplan-mcp">>).
-define(TEST_TASK_ID, <<"task-123">>).
-define(TEST_TASK_DEF, #{
    id => ?TEST_TASK_ID,
    type => <<"build">>,
    parameters => #{target => <<"dev">>},
    priority => <<"high">>
}).
-define(TEST_TASK_RESULT, #{
    id => ?TEST_TASK_ID,
    status => <<"completed">>,
    result => #{output => <<"Build successful">>},
    timestamp => 1642694400000
}).

%% Test suite
a2a_server_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_server_startstop/0,
            fun test_task_registration/0,
            fun test_task_execution/0,
            fun test_websocket_handling/0,
            fun test_task_status_tracking/0,
            fun test_error_handling/0,
            fun test_concurrent_tasks/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock dependencies
    meck:new(a2a_handler, [passthrough]),
    meck:new(craftplan_task_handler, [passthrough]),
    meck:new(gen_server, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(),
    ok.

%% Test server start/stop
test_server_startstop() ->
    % Mock gen_server:start_link
    meck:expect(gen_server, start_link,
        fun(module, Args, Options) ->
            {ok, self()}
        end
    ),

    % Test server startup
    {ok, Pid} = craftplan_a2a_server:start_link(?TEST_AGENT_ID),
    ?_assert(is_pid(Pid)),

    % Test server stop
    ?_assertEqual(ok, craftplan_a2a_server:stop(Pid)).

%% Test task registration
test_task_registration() ->
    % Mock task handler registration
    meck:expect(craftplan_task_handler, register_task,
        fun(TaskDef) -> {ok, TaskDef} end
    ),

    % Test task registration
    {ok, TaskId} = craftplan_a2a_server:register_task(?TEST_TASK_DEF),

    % Verify task was registered
    ?_assertEqual(?TEST_TASK_ID, TaskId).

%% Test task execution
test_task_execution() ->
    % Mock task handler execution
    meck:expect(craftplan_task_handler, execute_task,
        fun(TaskId) ->
            case TaskId of
                ?TEST_TASK_ID ->
                    {ok, ?TEST_TASK_RESULT};
                _ ->
                    {error, <<"Task not found">>}
            end
        end
    ),

    % Test task execution
    {ok, Result} = craftplan_a2a_server:execute_task(?TEST_TASK_ID),

    % Verify execution result
    ?_assertEqual(<<"completed">>, maps:get(status, Result)).

%% Test WebSocket handling
test_websocket_handling() ->
    % Mock WebSocket connection
    meck:expect(a2a_handler, connect,
        fun(Uri) -> {ok, self()} end
    ),

    % Test WebSocket connection
    {ok, Socket} = craftplan_a2a_server:connect(<<"ws://localhost:8080/a2a">>),

    % Verify WebSocket connection
    ?_assert(is_pid(Socket)),

    % Mock WebSocket message handling
    meck:expect(a2a_handler, send_message,
        fun(_, Message) -> {ok, sent} end
    ),

    % Test message sending
    Message = #{type => <<"task_update">>, data => ?TEST_TASK_RESULT},
    ?_assertEqual(ok, craftplan_a2a_server:send_message(Socket, Message)).

%% Test task status tracking
test_task_status_tracking() ->
    % Mock task status updates
    meck:expect(craftplan_task_handler, update_task_status,
        fun(TaskId, Status) ->
            case TaskId of
                ?TEST_TASK_ID ->
                    ok;
                _ ->
                    {error, <<"Task not found">>}
            end
        end
    ),

    % Test status update
    ?_assertEqual(ok, craftplan_a2a_server:update_task_status(?TEST_TASK_ID, <<"running">>)),

    % Test status retrieval
    Status = craftplan_a2a_server:get_task_status(?TEST_TASK_ID),
    ?_assertEqual(<<"running">>, Status).

%% Test error handling
test_error_handling() ->
    % Mock task handler error
    meck:expect(craftplan_task_handler, execute_task,
        fun(_) -> {error, <<"Task execution failed">>} end
    ),

    % Test error handling
    {error, Error} = craftplan_a2a_server:execute_task(?TEST_TASK_ID),
    ?_assertEqual(<<"Task execution failed">>, Error).

%% Test concurrent tasks
test_concurrent_tasks() ->
    % Mock concurrent task execution
    meck:expect(craftplan_task_handler, execute_task,
        fun(TaskId) ->
            timer:sleep(50), % Simulate work
            {ok, ?TEST_TASK_RESULT#{id => TaskId}}
        end
    ),

    % Start multiple concurrent tasks
    TaskIds = [<<"task-1">>, <<"task-2">>, <<"task-3">>],
    Pids = lists:map(fun(TaskId) ->
        spawn(fun() ->
            {ok, Result} = craftplan_a2a_server:execute_task(TaskId),
            Result
        end)
    end, TaskIds),

    % Wait for all tasks to complete
    Results = lists:map(fun(Pid) ->
        receive {Pid, Result} -> Result end
    end, Pids),

    % Verify all tasks completed
    ?_assertEqual(3, length(Results)),
    lists:foreach(fun(Result) ->
        ?_assertEqual(<<"completed">>, maps:get(status, Result))
    end, Results).

%% Helper functions
simulate_websocket_message(Message) ->
    % Simulate WebSocket message processing
    case maps:get(type, Message) of
        <<"task_update">> ->
            TaskId = maps:get(id, maps:get(data, Message)),
            craftplan_a2a_server:update_task_status(TaskId, maps:get(status, maps:get(data, Message)));
        <<"heartbeat">> ->
            craftplan_a2a_server:heartbeat();
        _ ->
            {error, <<"Unknown message type">>}
    end.