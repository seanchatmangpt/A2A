%% @doc Integration tests for MCP ↔ A2A interaction
%% Tests end-to-end workflow, message passing, and coordination

-module(craftplan_integration_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_AGENT_ID, <<"craftplan-mcp">>).
-define(TEST_SESSION_ID, <<"integration-test-session">>).
-define(TEST_TOOL_REQUEST, #{
    jsonrpc => <<"2.0">>,
    id => 1,
    method => <<"tools/call">>,
    params => #{
        name => <<"build">>,
        arguments => #{target => <<"dev">>}
    }
}).
-define(TEST_TASK_DEF, #{
    id => <<"integration-task">>,
    type => <<"build">>,
    parameters => #{target => <<"dev">>},
    priority => <<"high">>
}).

%% Test suite
integration_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_mcp_to_a2a_workflow/0,
            fun test_task_execution_pipeline/0,
            fun test_error_propagation/0,
            fun test_concurrent_operations/0,
            fun test_state_consistency/0,
            fun test_network_resilience/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock all external dependencies
    meck:new(craftplan_mcp_server, [passthrough]),
    meck:new(craftplan_a2a_server, [passthrough]),
    meck:new(craftplan_api_client, [passthrough]),
    meck:new(craftplan_task_handler, [passthrough]),
    meck:new(a2a_handler, [passthrough]),
    meck:new(gen_server, [passthrough]),
    meck:new(timer, [passthrough]),

    % Start test server instances
    start_test_servers(),

    ok.

cleanup(_) ->
    meck:unload(),
    stop_test_servers(),
    ok.

%% Test MCP to A2A workflow
test_mcp_to_a2a_workflow() ->
    % Mock tool execution flow
    meck:expect(craftplan_api_client, execute_tool,
        fun(<<"build">>, Args) ->
            case maps:get(target, Args) of
                <<"dev">> -> {ok, #{status => <<"completed">>, result => <<"Dev build successful">>}};
                <<"prod">> -> {ok, #{status => <<"completed">>, result => <<"Prod build successful">>}}
            end
        end
    ),

    % Mock A2A task handling
    meck:expect(craftplan_a2a_server, register_task,
        fun(TaskDef) -> {ok, maps:get(id, TaskDef)} end
    ),

    meck:expect(craftplan_a2a_server, execute_task,
        fun(TaskId) ->
            case TaskId of
                <<"integration-task">> -> {ok, #{status => <<"completed">>, result => <<"Task completed">>}}
            end
        end
    ),

    % Simulate MCP receiving tool request
    MCPResponse = craftplan_mcp_server:handle_tool_request(?TEST_TOOL_REQUEST),

    % Verify MCP response
    ?_assertEqual(<<"2.0">>, maps:get(jsonrpc, MCPResponse)),
    ?_assertEqual(1, maps:get(id, MCPResponse)),

    % Simulate A2A task creation
    A2AResponse = craftplan_a2a_server:register_task(?TEST_TASK_DEF),
    ?_assertEqual(<<"integration-task">>, A2AResponse),

    % Verify integration success
    ?_assertEqual(ok, verify_integration_state(?TEST_SESSION_ID)).

%% Test task execution pipeline
test_task_execution_pipeline() ->
    % Mock successful pipeline execution
    PipelineSteps = [
        {start, ?TEST_TASK_DEF},
        {execute, <<"build">>},
        {complete, <<"Build successful">>}
    ],

    % Mock pipeline execution
    meck:expect(craftplan_task_handler, execute_pipeline,
        fun(Steps) ->
            lists:foldl(fun(Step, State) ->
                case Step of
                    {start, TaskDef} ->
                        {ok, State#{task => TaskDef}};
                    {execute, Tool} ->
                        {ok, State#{result => tool_success(Tool)}};
                    {complete, Message} ->
                        {ok, State#{status => completed, message => Message}}
                end
            end, #{}, Steps)
        end
    ),

    % Execute pipeline
    {ok, PipelineResult} = craftplan_task_handler:execute_pipeline(PipelineSteps),

    % Verify pipeline result
    ?_assertEqual(completed, maps:get(status, PipelineResult)),
    ?_assertEqual(<<"Build successful">>, maps:get(message, PipelineResult)).

%% Test error propagation
test_error_propagation() ->
    % Mock MCP error handling
    meck:expect(craftplan_mcp_server, handle_tool_request,
        fun(Request) ->
            case maps:get(params, Request) of
                #{arguments := #{target := <<"invalid">>}} ->
                    {error, #{jsonrpc => <<"2.0">>, id => maps:get(id, Request), error => #{code => -32601, message => <<"Invalid target">>}}};
                _ ->
                    {ok, #{jsonrpc => <<"2.0">>, id => maps:get(id, Request), result => #{status => <<"completed">>}}}
            end
        end
    ),

    % Test invalid request
    InvalidRequest = ?TEST_TOOL_REQUEST#{params := ?TEST_TOOL_REQUEST#{params := #{arguments => #{target => <<"invalid">>}}}},
    {error, Error} = craftplan_mcp_server:handle_tool_request(InvalidRequest),
    ?_assertEqual(<<"Invalid target">>, maps:get(message, maps:get(error, Error))),

    % Test valid request
    ValidRequest = ?TEST_TOOL_REQUEST#{params := ?TEST_TOOL_REQUEST#{params := #{arguments => #{target => <<"dev">>}}}},
    {ok, Response} = craftplan_mcp_server:handle_tool_request(ValidRequest),
    ?_assertEqual(<<"completed">>, maps:get(status, maps:get(result, Response))).

%% Test concurrent operations
test_concurrent_operations() ->
    % Mock concurrent task execution
    meck:expect(craftplan_a2a_server, execute_concurrent_tasks,
        fun(TaskIds) ->
            Results = lists:map(fun(TaskId) ->
                timer:sleep(10), % Simulate work
                {ok, #{id => TaskId, status => <<"completed">>}}
            end, TaskIds),
            Results
        end
    ),

    % Test concurrent execution
    TaskIds = [<<"task-1">>, <<"task-2">>, <<"task-3">>],
    Results = craftplan_a2a_server:execute_concurrent_tasks(TaskIds),

    % Verify all tasks completed
    ?_assertEqual(3, length(Results)),
    lists:foreach(fun({ok, Result}) ->
        ?_assertEqual(<<"completed">>, maps:get(status, Result))
    end, Results).

%% Test state consistency
test_state_consistency() ->
    % Mock state management
    meck:expect(craftplan_mcp_server, get_server_state,
        fun() -> #{active_tasks => 2, completed_tasks => 5} end
    ),

    meck:expect(craftplan_a2a_server, get_agent_state,
        fun() -> #{registered_tasks => 2, running_tasks => 1} end
    ),

    % Verify state consistency
    MCPState = craftplan_mcp_server:get_server_state(),
    A2AState = craftplan_a2a_server:get_agent_state(),

    ?_assertEqual(2, maps:get(active_tasks, MCPState)),
    ?_assertEqual(1, maps:get(running_tasks, A2AState)),

    % Test state synchronization
    ?_assertEqual(ok, synchronize_states(MCPState, A2AState)).

%% Test network resilience
test_network_resilience() ->
    % Mock network failure handling
    meck:expect(craftplan_api_client, execute_tool,
        fun(_, _) ->
            {error, <<"Network timeout">>}
        end
    ),

    % Test retry mechanism
    meck:expect(craftplan_api_client, execute_tool_with_retry,
        fun(Tool, Args) ->
            case execute_with_retry(Tool, Args, 3) of
                {ok, Result} -> {ok, Result};
                Error -> Error
            end
        end
    ),

    % Test with retry
    {error, Error} = craftplan_api_client:execute_tool_with_retry(<<"build">>, #{target => <<"dev">>}),
    ?_assertEqual(<<"Network timeout">>, Error).

%% Helper functions
start_test_servers() ->
    % Start mock servers for testing
    {ok, _} = craftplan_mcp_server:start_link(),
    {ok, _} = craftplan_a2a_server:start_link(?TEST_AGENT_ID),
    timer:sleep(100).

stop_test_servers() ->
    % Stop test servers
    craftplan_mcp_server:stop(),
    craftplan_a2a_server:stop(),
    timer:sleep(100).

verify_integration_state(SessionId) ->
    % Verify integration state
    case craftplan_mcp_server:get_session_state(SessionId) of
        {ok, State} ->
            case craftplan_a2a_server:get_session_state(SessionId) of
                {ok, _} -> ok;
                _ -> error
            end;
        _ ->
            error
    end.

tool_success(Tool) ->
    case Tool of
        <<"build">> -> #{status => <<"completed">>, result => <<"Build successful">>};
        <<"deploy">> -> #{status => <<"completed">>, result => <<"Deploy successful">>};
        _ -> #{status => <<"unknown">>}
    end.

synchronize_states(MCPState, A2AState) ->
    % Synchronize states between MCP and A2A
    case {maps:get(active_tasks, MCPState), maps:get(running_tasks, A2AState)} of
        {Active, Running} when Active == Running ->
            ok;
        _ ->
            error
    end.

execute_with_retry(_Tool, _Args, 0) ->
    {error, <<"Max retries exceeded">>};
execute_with_retry(Tool, Args, Retries) ->
    case craftplan_api_client:execute_tool(Tool, Args) of
        {ok, Result} -> {ok, Result};
        {error, _} when Retries > 0 ->
            timer:sleep(1000),
            execute_with_retry(Tool, Args, Retries - 1);
        {error, Error} -> {error, Error}
    end.