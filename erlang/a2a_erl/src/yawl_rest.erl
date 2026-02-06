%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST API Module
%%%
%%% This module provides HTTP REST API endpoints for YAWL workflow
%%% management using the Cowboy web server.
%%%
%%% ## Endpoints
%%%
%%% ### Workflow Management
%%% - `POST /workflows` - Create a new workflow
%%% - `GET /workflows` - List all workflows
%%% - `GET /workflows/{id}` - Get workflow status
%%% - `DELETE /workflows/{id}` - Delete a workflow with full cleanup
%%% - `POST /workflows/{id}/start` - Start a workflow
%%% - `POST /workflows/{id}/cancel` - Cancel a workflow
%%% - `POST /workflows/{id}/suspend` - Suspend a workflow
%%% - `POST /workflows/{id}/resume` - Resume a workflow
%%%
%%% ### Pattern Management
%%% - `GET /patterns` - List all available workflow patterns
%%% - `GET /patterns/{type}` - Get detailed information about a pattern
%%% - `GET /patterns/categories` - List pattern categories
%%% - `GET /patterns/validate` - Validate a pattern configuration
%%%
%%% ### Template Management
%%% - `GET /templates` - List all available templates
%%% - `GET /templates/{id}` - Get template details
%%% - `POST /templates/{id}/instantiate` - Instantiate a template
%%%
%%% ### Workflow Definitions
%%% - `GET /definitions` - List workflow definitions
%%% - `POST /definitions` - Save a workflow definition
%%% - `GET /definitions/{id}` - Get a workflow definition
%%% - `DELETE /definitions/{id}` - Delete a workflow definition
%%% - `GET /definitions/search` - Search workflow definitions
%%%
%%% ### XES Log Management
%%% - `GET /xes/logs` - List all XES logs
%%% - `GET /xes/logs/{log_id}` - Get specific XES log metadata
%%% - `GET /xes/logs/{log_id}/export` - Export XES log as XML
%%% - `POST /xes/logs/{log_id}/export` - Export XES log to specific directory
%%% - `DELETE /xes/logs/{log_id}` - Delete an XES log
%%% - `GET /xes/workflows/{workflow_id}/events` - Get XES events for workflow
%%% - `POST /xes/workflows/{workflow_id}/export` - Export workflow as XES
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    delete_resource/2,
    to_json/2
]).

%% API exports for starting/stopping the REST server
-export([
    start_link/1,
    stop/0,
    child_spec/1
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    workflow_id :: binary() | undefined,
    action :: atom() | undefined
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the REST server.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    Port = maps:get(port, Options, 8081),
    _ = maps_get(host, Options, 'localhost'),  %% Reserved for future use
    Dispatch = cowboy_router:compile([
        {'_', [
            %% Health endpoints
            {"/health", yawl_health_handler, []},
            {"/health/[...]", yawl_health_handler, []},
            %% Workflow endpoints
            {"/workflows", yawl_rest_handler, []},
            {"/workflows/:workflow_id", yawl_rest_handler, []},
            {"/workflows/:workflow_id/:action", yawl_rest_handler, []},
            {"/workflows/:workflow_id/workitems", yawl_rest_workitem_handler, []},
            %% Pattern endpoints
            {"/patterns", yawl_rest_pattern_handler, []},
            {"/patterns/:pattern_type", yawl_rest_pattern_handler, []},
            {"/patterns/:action", yawl_rest_pattern_handler, []},
            %% Template endpoints
            {"/templates", yawl_rest_template_handler, []},
            {"/templates/:template_id", yawl_rest_template_handler, []},
            {"/templates/:template_id/:action", yawl_rest_template_handler, []},
            %% Definition endpoints
            {"/definitions", yawl_rest_definition_handler, []},
            {"/definitions/:definition_id", yawl_rest_definition_handler, []},
            {"/definitions/search", yawl_rest_definition_handler, #{action => search}},
            %% Workitem endpoints
            {"/workitems", yawl_rest_workitem_handler, []},
            {"/workitems/:workitem_id", yawl_rest_workitem_handler, []},
            {"/workitems/:workitem_id/:action", yawl_rest_workitem_handler, []},
            %% Resource endpoints
            {"/resources", yawl_rest_resource_handler, []},
            {"/resources/allocate", yawl_rest_resource_handler, #{action => allocate}},
            {"/resources/deallocate", yawl_rest_resource_handler, #{action => deallocate}},
            {"/resources/:resource_id", yawl_rest_resource_handler, []},
            {"/resources/:resource_id/:action", yawl_rest_resource_handler, []},
            %% Task endpoints
            {"/tasks", yawl_rest_task_handler, []},
            {"/tasks/:task_id", yawl_rest_task_handler, []},
            {"/tasks/:task_id/complete", yawl_rest_task_handler, #{action => complete}},
            %% Service endpoints
            {"/services", yawl_rest_service_handler, []},
            {"/services/:service_id", yawl_rest_service_handler, []},
            {"/services/:service_id/:action", yawl_rest_service_handler, []},
            %% Metrics endpoints
            {"/metrics", yawl_rest_metrics_handler, []},
            {"/metrics/:metrics_type", yawl_rest_metrics_handler, []},
            %% XES log management endpoints
            {"/xes/logs", yawl_rest_xes_handler, []},
            {"/xes/logs/:log_id", yawl_rest_xes_handler, []},
            {"/xes/logs/:log_id/:action", yawl_rest_xes_handler, []},
            {"/xes/workflows/:workflow_id/events", yawl_rest_xes_handler, []},
            {"/xes/workflows/:workflow_id/:action", yawl_rest_xes_handler, []},
            %% Research module endpoints (van der Aalst 2025-2026)
            %% Reachability (Paper 2602.02447)
            {"/workflows/:workflow_id/reachable", yawl_rest_reachability_handler, []},
            {"/reachability/diagnostics", yawl_rest_reachability_handler, []},
            {"/reachability/admissibility", yawl_rest_reachability_handler, []},
            {"/reachability/maximum_admissible", yawl_rest_reachability_handler, []},
            {"/concurrency/analysis", yawl_rest_reachability_handler, []},
            %% LLM Validation (Paper 2509.15336)
            {"/llm/validate", yawl_rest_llm_handler, []},
            {"/llm/generate", yawl_rest_llm_handler, []},
            {"/llm/refine", yawl_rest_llm_handler, []},
            {"/llm/fidelity/:model_id", yawl_rest_llm_handler, []},
            {"/llm/hallucination_report", yawl_rest_llm_handler, []},
            {"/llm/scenarios/:type", yawl_rest_llm_handler, []},
            %% OCPM (Paper 2508.00116)
            {"/ocpm/events", yawl_rest_ocpm_handler, []},
            {"/ocpm/logs/:log_id/objects/:object_type", yawl_rest_ocpm_handler, []},
            {"/ocpm/logs/:log_id/export", yawl_rest_ocpm_handler, []},
            {"/ocpm/lifecycle/:object_id", yawl_rest_ocpm_handler, []},
            {"/ocpm/dependencies", yawl_rest_ocpm_handler, []},
            {"/ocpm/ground/:type", yawl_rest_ocpm_handler, []},
            %% CPN (Paper 2506.12238)
            {"/cpn/export", yawl_rest_cpn_handler, []},
            {"/cpn/parse", yawl_rest_cpn_handler, []},
            {"/cpn/llm_format/:workflow", yawl_rest_cpn_handler, []},
            {"/cpn/llm_parse", yawl_rest_cpn_handler, []},
            {"/cpn/validate", yawl_rest_cpn_handler, []},
            {"/cpn/guard/evaluate", yawl_rest_cpn_handler, []},
            {"/cpn/color_set/create", yawl_rest_cpn_handler, []},
            %% Human-in-the-Loop & Claude Headless
            {"/hitl/approval", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/status", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/submit", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/stream", yawl_rest_hitl_handler, []},
            {"/hitl/approvals", yawl_rest_hitl_handler, []},
            {"/hitl/llm/decision", yawl_rest_hitl_handler, []},
            {"/hitl/session/start", yawl_rest_hitl_handler, []},
            {"/hitl/session/:session_id/continue", yawl_rest_hitl_handler, []},
            {"/hitl/feedback", yawl_rest_hitl_handler, []},
            {"/hitl/feedback/analyze", yawl_rest_hitl_handler, []},
            {"/hitl/history/:workflow_id", yawl_rest_hitl_handler, []}
        ]}
    ]),

    case cowboy:start_clear(yawl_http_listener, [{port, Port}], #{
        env => #{dispatch => Dispatch}
    }) of
        {ok, _Pid} -> {ok, self()};
        {error, Reason} -> {error, Reason}
    end.

%% @doc Stop the REST server.
-spec stop() -> ok.
stop() ->
    cowboy:stop_listener(yawl_http_listener).

%% @doc Get child spec for supervision tree.
-spec child_spec(map()) -> supervisor:child_spec().
child_spec(Options) ->
    Port = maps:get(port, Options, 8081),
    _ = maps_get(host, Options, 'localhost'),  %% Reserved for future use
    Dispatch = cowboy_router:compile([
        {'_', [
            %% Health endpoints
            {"/health", yawl_health_handler, []},
            {"/health/[...]", yawl_health_handler, []},
            %% Workflow endpoints
            {"/workflows", yawl_rest_handler, []},
            {"/workflows/:workflow_id", yawl_rest_handler, []},
            {"/workflows/:workflow_id/:action", yawl_rest_handler, []},
            {"/workflows/:workflow_id/workitems", yawl_rest_workitem_handler, []},
            %% Pattern endpoints
            {"/patterns", yawl_rest_pattern_handler, []},
            {"/patterns/:pattern_type", yawl_rest_pattern_handler, []},
            {"/patterns/:action", yawl_rest_pattern_handler, []},
            %% Template endpoints
            {"/templates", yawl_rest_template_handler, []},
            {"/templates/:template_id", yawl_rest_template_handler, []},
            {"/templates/:template_id/:action", yawl_rest_template_handler, []},
            %% Definition endpoints
            {"/definitions", yawl_rest_definition_handler, []},
            {"/definitions/:definition_id", yawl_rest_definition_handler, []},
            {"/definitions/search", yawl_rest_definition_handler, #{action => search}},
            %% Workitem endpoints
            {"/workitems", yawl_rest_workitem_handler, []},
            {"/workitems/:workitem_id", yawl_rest_workitem_handler, []},
            {"/workitems/:workitem_id/:action", yawl_rest_workitem_handler, []},
            %% Resource endpoints
            {"/resources", yawl_rest_resource_handler, []},
            {"/resources/allocate", yawl_rest_resource_handler, #{action => allocate}},
            {"/resources/deallocate", yawl_rest_resource_handler, #{action => deallocate}},
            {"/resources/:resource_id", yawl_rest_resource_handler, []},
            {"/resources/:resource_id/:action", yawl_rest_resource_handler, []},
            %% Task endpoints
            {"/tasks", yawl_rest_task_handler, []},
            {"/tasks/:task_id", yawl_rest_task_handler, []},
            {"/tasks/:task_id/complete", yawl_rest_task_handler, #{action => complete}},
            %% Service endpoints
            {"/services", yawl_rest_service_handler, []},
            {"/services/:service_id", yawl_rest_service_handler, []},
            {"/services/:service_id/:action", yawl_rest_service_handler, []},
            %% Metrics endpoints
            {"/metrics", yawl_rest_metrics_handler, []},
            {"/metrics/:metrics_type", yawl_rest_metrics_handler, []},
            %% XES log management endpoints
            {"/xes/logs", yawl_rest_xes_handler, []},
            {"/xes/logs/:log_id", yawl_rest_xes_handler, []},
            {"/xes/logs/:log_id/:action", yawl_rest_xes_handler, []},
            {"/xes/workflows/:workflow_id/events", yawl_rest_xes_handler, []},
            {"/xes/workflows/:workflow_id/:action", yawl_rest_xes_handler, []},
            %% Research module endpoints (van der Aalst 2025-2026)
            %% Reachability (Paper 2602.02447)
            {"/workflows/:workflow_id/reachable", yawl_rest_reachability_handler, []},
            {"/reachability/diagnostics", yawl_rest_reachability_handler, []},
            {"/reachability/admissibility", yawl_rest_reachability_handler, []},
            {"/reachability/maximum_admissible", yawl_rest_reachability_handler, []},
            {"/concurrency/analysis", yawl_rest_reachability_handler, []},
            %% LLM Validation (Paper 2509.15336)
            {"/llm/validate", yawl_rest_llm_handler, []},
            {"/llm/generate", yawl_rest_llm_handler, []},
            {"/llm/refine", yawl_rest_llm_handler, []},
            {"/llm/fidelity/:model_id", yawl_rest_llm_handler, []},
            {"/llm/hallucination_report", yawl_rest_llm_handler, []},
            {"/llm/scenarios/:type", yawl_rest_llm_handler, []},
            %% OCPM (Paper 2508.00116)
            {"/ocpm/events", yawl_rest_ocpm_handler, []},
            {"/ocpm/logs/:log_id/objects/:object_type", yawl_rest_ocpm_handler, []},
            {"/ocpm/logs/:log_id/export", yawl_rest_ocpm_handler, []},
            {"/ocpm/lifecycle/:object_id", yawl_rest_ocpm_handler, []},
            {"/ocpm/dependencies", yawl_rest_ocpm_handler, []},
            {"/ocpm/ground/:type", yawl_rest_ocpm_handler, []},
            %% CPN (Paper 2506.12238)
            {"/cpn/export", yawl_rest_cpn_handler, []},
            {"/cpn/parse", yawl_rest_cpn_handler, []},
            {"/cpn/llm_format/:workflow", yawl_rest_cpn_handler, []},
            {"/cpn/llm_parse", yawl_rest_cpn_handler, []},
            {"/cpn/validate", yawl_rest_cpn_handler, []},
            {"/cpn/guard/evaluate", yawl_rest_cpn_handler, []},
            {"/cpn/color_set/create", yawl_rest_cpn_handler, []},
            %% Human-in-the-Loop & Claude Headless
            {"/hitl/approval", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/status", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/submit", yawl_rest_hitl_handler, []},
            {"/hitl/approval/:approval_id/stream", yawl_rest_hitl_handler, []},
            {"/hitl/approvals", yawl_rest_hitl_handler, []},
            {"/hitl/llm/decision", yawl_rest_hitl_handler, []},
            {"/hitl/session/start", yawl_rest_hitl_handler, []},
            {"/hitl/session/:session_id/continue", yawl_rest_hitl_handler, []},
            {"/hitl/feedback", yawl_rest_hitl_handler, []},
            {"/hitl/feedback/analyze", yawl_rest_hitl_handler, []},
            {"/hitl/history/:workflow_id", yawl_rest_hitl_handler, []}
        ]}
    ]),

    #{
        id => yawl_rest,
        start => {cowboy, start_clear, [yawl_http_listener, [{port, Port}], #{
            env => #{dispatch => Dispatch}
        }]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [cowboy_clear, yawl_rest_handler, yawl_rest_workitem_handler,
                   yawl_rest_resource_handler, yawl_rest_task_handler, yawl_health_handler,
                   yawl_rest_service_handler, yawl_rest_metrics_handler,
                   yawl_rest_pattern_handler, yawl_rest_template_handler,
                   yawl_rest_definition_handler, yawl_rest_xes_handler]
    }.

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, _State) ->
    Method = cowboy_req:method(Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        workflow_id = WorkflowId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case State#state.workflow_id of
        undefined when State#state.action =:= undefined ->
            %% /workflows - GET, POST
            [<<"GET">>, <<"POST">>];
        undefined ->
            %% Invalid path
            [<<"GET">>];
        _ when State#state.action =:= undefined ->
            %% /workflows/{id} - GET, DELETE
            [<<"GET">>, <<"DELETE">>];
        _ ->
            %% /workflows/{id}/{action} - POST
            [<<"POST">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, to_json}
    ], Req, State}.

%% @private
content_types_accepted(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, handle_json}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    Exists = case State#state.workflow_id of
        undefined -> true;  %% Collection resource
        WorkflowId ->
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, _} -> true;
                {error, _} -> false
            end
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    WorkflowId = State#state.workflow_id,
    case perform_workflow_cleanup(WorkflowId) of
        {ok, DeletedItems} ->
            Response = #{
                status => ok,
                message => <<"Workflow deleted successfully">>,
                deleted => DeletedItems
            },
            {true, cowboy_req:reply(200, #{}, jiffy:encode(Response), Req), State};
        {error, Reason} ->
            Response = #{error => to_binary(Reason)},
            StatusCode = case Reason of
                workflow_not_found -> 404;
                workflow_running -> 409;
                _ -> 500
            end,
            {false, cowboy_req:reply(StatusCode, #{}, jiffy:encode(Response), Req), State}
    end.

%% @private
%% @doc Perform comprehensive workflow cleanup including:
%% - Workflow instance termination
%% - Persistence cleanup
%% - Workitem deletion
%% - Checkpoint deletion
%% - History deletion
%% - Resource deallocation
perform_workflow_cleanup(WorkflowId) ->
    %% Check if workflow exists first
    case yawl_persistence:load_workflow(WorkflowId) of
        {error, not_found} ->
            {error, workflow_not_found};
        {ok, Workflow} ->
            %% Check if workflow is running
            case Workflow#yawl_workflow_persist.status of
                running ->
                    {error, workflow_running};
                _ ->
                    %% Perform cleanup in stages
                    DeletedItems = cleanup_workflow_stages(WorkflowId, Workflow),

                    {ok, DeletedItems}
            end
    end.

%% @private
cleanup_workflow_stages(WorkflowId, _Workflow) ->
    %% Stage 1: Cancel workflow if still active in orchestrator
    OrchestratorCleanup = case yawl_orchestrator:cancel_workflow(WorkflowId) of
        ok -> orchestrator_cancelled;
        {error, _} -> orchestrator_not_found
    end,

    %% Stage 2: Delete workflow from persistence
    PersistenceCleanup = case yawl_persistence:delete_workflow(WorkflowId) of
        ok -> workflow_deleted;
        {error, _} -> workflow_delete_failed
    end,

    %% Stage 3: Delete all associated workitems
    WorkitemCleanup = case yawl_persistence:list_workitems(WorkflowId) of
        {ok, Workitems} ->
            lists:foreach(fun(W) ->
                yawl_persistence:delete_workitem(W#yawl_workitem_persist.workitem_id)
            end, Workitems),
            {workitems_deleted, length(Workitems)};
        {error, _} -> workitem_cleanup_failed
    end,

    %% Stage 4: Delete all checkpoints
    CheckpointCleanup = case yawl_persistence:list_checkpoints(WorkflowId) of
        {ok, Checkpoints} ->
            lists:foreach(fun(C) ->
                yawl_persistence:delete_checkpoint(C#yawl_checkpoint.checkpoint_id)
            end, Checkpoints),
            {checkpoints_deleted, length(Checkpoints)};
        {error, _} -> checkpoint_cleanup_failed
    end,

    %% Stage 5: Delete execution history
    HistoryCleanup = case yawl_persistence:delete_history(WorkflowId) of
        ok -> history_deleted;
        {error, _} -> history_cleanup_failed
    end,

    %% Stage 6: Deallocate any allocated resources
    ResourceCleanup = cleanup_workflow_resources(WorkflowId),

    %% Return summary of deleted items
    #{
        workflow_id => WorkflowId,
        orchestrator => OrchestratorCleanup,
        persistence => PersistenceCleanup,
        workitems => element(2, WorkitemCleanup),
        checkpoints => element(2, CheckpointCleanup),
        history => HistoryCleanup,
        resources => ResourceCleanup
    }.

%% @private
%% @doc Clean up resources allocated to a workflow
cleanup_workflow_resources(WorkflowId) ->
    case yawl_persistence:list_workitems(WorkflowId) of
        {ok, Workitems} ->
            Deallocated = lists:filter(fun(W) ->
                case W#yawl_workitem_persist.allocated_to of
                    undefined -> false;
                    {ResourcePid, _} ->
                        try
                            yawl_resource_manager:deallocate_resource(ResourcePid),
                            true
                        catch
                            _:_ -> false
                        end
                end
            end, Workitems),
            {resources_deallocated, length(Deallocated)};
        {error, _} ->
            resource_cleanup_failed
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.workflow_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            %% List workflows
            {ok, Workflows} = yawl_orchestrator:list_workflows(),
            #{workflows => Workflows};
        {<<"GET">>, WorkflowId, undefined} ->
            %% Get workflow status
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            #{workflow_id => WorkflowId, status => Status};
        {<<"POST">>, WorkflowId, <<"start">>} ->
            %% Start workflow
            case yawl_orchestrator:execute_workflow(WorkflowId) of
                {ok, Result} ->
                    #{workflow_id => WorkflowId, status => started, result => Result};
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end;
        {<<"POST">>, WorkflowId, <<"cancel">>} ->
            %% Cancel workflow
            case yawl_orchestrator:cancel_workflow(WorkflowId) of
                ok -> #{workflow_id => WorkflowId, status => cancelled};
                {error, Reason} -> #{error => to_binary(Reason)}
            end;
        {<<"POST">>, _WorkflowId, Action} ->
            %% Unknown action
            #{error => <<"unknown_action">>, action => Action};
        _ ->
            #{error => <<"unknown_request">>}
    end,

    Body = jiffy:encode(Response),
    {Body, Req, State}.

%% @private
handle_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jiffy:decode(Body, [return_maps]),

    Response = case {State#state.method, State#state.workflow_id} of
        {<<"POST">>, undefined} ->
            %% Create workflow
            PatternType = maps_get(<<"pattern_type">>, Data, basic_sequential),
            Config = maps_get(<<"config">>, Data, #{}),
            case yawl_orchestrator:create_workflow(PatternType, Config) of
                {ok, WorkflowId} ->
                    #{workflow_id => WorkflowId, status => created};
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end;
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    Req3 = cowboy_req:reply(201, #{}, ResponseBody, Req2),
    {true, Req3, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_list(Term) -> list_to_binary(Term);
to_binary(Term) -> io_lib:format("~p", [Term]).
