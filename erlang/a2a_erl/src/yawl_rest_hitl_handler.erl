%%%-------------------------------------------------------------------
%%% @doc
%%% REST Handler for Human-in-the-Loop Workflows
%%%
%%% Integrates Claude Code headless mode for LLM-assisted decision making
%%% and human approval gates in YAWL workflows.
%%%
%%% Endpoints:
%%% - POST /hitl/approval - Create approval gate
%%% - GET  /hitl/approval/{id}/status - Check status
%%% - POST /hitl/approval/{id}/submit - Submit decision
%%% - GET  /hitl/stream/{id} - SSE stream for real-time updates
%%% - POST /hitl/llm/decision - Request LLM-assisted decision
%%% - POST /hitl/session/start - Start collaborative session
%%% - POST /hitl/session/{id}/continue - Continue session
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_hitl_handler).
-author("A2A Team").

%% Cowboy REST handler callbacks
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    to_json/2
]).

-include("yawl_types.hrl").

%%====================================================================
%% REST Handler Callbacks
%%====================================================================

init(Req, State) ->
    {cowboy_rest, Req, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>, <<"OPTIONS">>], Req, State}.

content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, to_json}
    ], Req, State}.

content_types_accepted(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, []}, to_json}
    ], Req, State}.

resource_exists(Req, State) ->
    {true, Req, State}.

%% @private
to_json(Req, State) ->
    Method = cowboy_req:method(Req),
    handle_request(Method, Req, State).

%% @private
handle_request(<<"POST">>, Req, State) ->
    PathInfo = cowboy_req:path_info(Req),
    {ok, Body, _} = cowboy_req:read_body(Req),
    Data = jiffy:decode(Body, [return_maps]),

    case PathInfo of
        [<<"hitl">>, <<"approval">>] ->
            %% Create approval gate
            WorkflowId = maps:get(<<"workflow_id">>, Data),
            TaskId = maps:get(<<"task_id">>, Data),
            DecisionPrompt = maps:get(<<"prompt">>, Data),
            Options = maps:get(<<"options">>, Data, #{}),

            {ok, ApprovalId} = yawl_human_in_loop:create_approval_gate(
                WorkflowId,
                TaskId,
                DecisionPrompt,
                Options
            ),

            Result = #{
                approval_id => ApprovalId,
                workflow_id => WorkflowId,
                task_id => TaskId,
                status => <<"pending">>
            },
            respond(Result, Req, State);

        [<<"hitl">>, <<"approval">>, ApprovalId, <<"submit">>] ->
            %% Submit approval/rejection
            Decision = case maps:get(<<"decision">>, Data) of
                <<"approve">> -> approved;
                <<"reject">> -> rejected;
                _ -> rejected
            end,

            Feedback = maps:get(<<"feedback">>, Data, #{}),

            ok = yawl_human_in_loop:submit_approval(ApprovalId, Decision, Feedback),

            Result = #{
                approval_id => ApprovalId,
                decision => Decision,
                status => <<"submitted">>
            },
            respond(Result, Req, State);

        [<<"hitl">>, <<"llm">>, <<"decision">>] ->
            %% Request LLM-assisted decision
            DecisionPrompt = maps:get(<<"prompt">>, Data),
            Context = maps:get(<<"context">>, Data, #{}),

            {ok, LLMDecision} = yawl_human_in_loop:request_decision_with_llm(
                DecisionPrompt,
                Context
            ),

            respond(LLMDecision, Req, State);

        [<<"hitl">>, <<"session">>, <<"start">>] ->
            %% Start collaborative session
            WorkflowId = maps:get(<<"workflow_id">>, Data),
            Participants = maps:get(<<"participants">>, Data, []),
            ParticipantsList = [binary_to_existing_atom(P, utf8) || P <- Participants],

            {ok, SessionId} = yawl_human_in_loop:start_collaborative_session(
                WorkflowId,
                ParticipantsList
            ),

            Result = #{
                session_id => SessionId,
                workflow_id => WorkflowId,
                participants => Participants,
                status => <<"active">>
            },
            respond(Result, Req, State);

        [<<"hitl">>, <<"feedback">>] ->
            %% Collect feedback
            WorkflowId = maps:get(<<"workflow_id">>, Data),
            Feedback = maps:get(<<"feedback">>, Data),

            ok = yawl_human_in_loop:collect_feedback(WorkflowId, Feedback),

            Result = #{status => <<"collected">>},
            respond(Result, Req, State);

        [<<"hitl">>, <<"feedback">>, <<"analyze">>] ->
            %% Analyze feedback with LLM
            WorkflowId = maps:get(<<"workflow_id">>, Data),

            {ok, Analysis} = yawl_human_in_loop:analyze_feedback_with_llm(WorkflowId),

            Result = #{
                workflow_id => WorkflowId,
                analysis => Analysis
            },
            respond(Result, Req, State);

        _ ->
            not_found(Req, State)
    end;

handle_request(<<"GET">>, Req, State) ->
    PathInfo = cowboy_req:path_info(Req),

    case PathInfo of
        [<<"hitl">>, <<"approval">>, ApprovalId, <<"status">>] ->
            %% Check approval status
            {ok, Status} = yawl_human_in_loop:check_approval_status(ApprovalId),
            respond(Status, Req, State);

        [<<"hitl">>, <<"approvals">>] ->
            %% Get pending approvals
            {ok, Pending} = yawl_human_in_loop:get_pending_approvals(),
            respond(#{pending => Pending}, Req, State);

        [<<"hitl">>, <<"history">>, WorkflowId] ->
            %% Get approval history
            {ok, History} = yawl_human_in_loop:get_approval_history(WorkflowId),
            respond(#{history => History}, Req, State);

        _ ->
            not_found(Req, State)
    end;

handle_request(_Method, Req, State) ->
    not_found(Req, State).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
respond(Result, Req, State) ->
    Response = #{
        status => <<"success">>,
        data => Result
    },
    respond_json(Response, 200, Req, State).

%% @private
not_found(Req, State) ->
    Response = #{
        error => <<"not_found">>,
        message => <<"Human-in-the-loop endpoint not found">>
    },
    respond_json(Response, 404, Req, State).

%% @private
respond_json(Data, StatusCode, Req, State) ->
    Body = jiffy:encode(Data),
    Req0 = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req),
    {stop, Req0, State}.
