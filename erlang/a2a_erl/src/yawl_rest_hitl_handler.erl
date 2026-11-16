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
            case validate_required_fields([<<"workflow_id">>, <<"task_id">>, <<"prompt">>], Data) of
                {error, Missing} ->
                    respond_error(<<"missing_required_fields">>, Missing, Req, State);
                ok ->
                    WorkflowId = maps:get(<<"workflow_id">>, Data),
                    TaskId = maps:get(<<"task_id">>, Data),
                    DecisionPrompt = maps:get(<<"prompt">>, Data),
                    Options = maps:get(<<"options">>, Data, #{}),

                    case yawl_human_in_loop:create_approval_gate(
                        WorkflowId,
                        TaskId,
                        DecisionPrompt,
                        Options
                    ) of
                        {ok, ApprovalId} ->
                            Result = #{
                                approval_id => ApprovalId,
                                workflow_id => WorkflowId,
                                task_id => TaskId,
                                status => <<"pending">>
                            },
                            respond(Result, Req, State);
                        {error, Reason} ->
                            respond_error(<<"approval_creation_failed">>, Reason, Req, State)
                    end
            end;

        [<<"hitl">>, <<"approval">>, ApprovalId, <<"submit">>] ->
            %% Submit approval/rejection
            case maps:get(<<"decision">>, Data, undefined) of
                undefined ->
                    respond_error(<<"missing_required_fields">>, [<<"decision">>], Req, State);
                DecisionValue ->
                    Decision = case DecisionValue of
                        <<"approve">> -> approved;
                        <<"reject">> -> rejected;
                        _ -> rejected
                    end,

                    Feedback = maps:get(<<"feedback">>, Data, #{}),

                    case yawl_human_in_loop:submit_approval(ApprovalId, Decision, Feedback) of
                        ok ->
                            Result = #{
                                approval_id => ApprovalId,
                                decision => Decision,
                                status => <<"submitted">>
                            },
                            respond(Result, Req, State);
                        {error, Reason} ->
                            respond_error(<<"approval_submit_failed">>, Reason, Req, State)
                    end
            end;

        [<<"hitl">>, <<"llm">>, <<"decision">>] ->
            %% Request LLM-assisted decision
            case maps:get(<<"prompt">>, Data, undefined) of
                undefined ->
                    respond_error(<<"missing_required_fields">>, [<<"prompt">>], Req, State);
                DecisionPrompt ->
                    Context = maps:get(<<"context">>, Data, #{}),

                    case yawl_human_in_loop:request_decision_with_llm(
                        DecisionPrompt,
                        Context
                    ) of
                        {ok, LLMDecision} ->
                            respond(LLMDecision, Req, State);
                        {error, Reason} ->
                            respond_error(<<"llm_decision_failed">>, Reason, Req, State)
                    end
            end;

        [<<"hitl">>, <<"session">>, <<"start">>] ->
            %% Start collaborative session
            case maps:get(<<"workflow_id">>, Data, undefined) of
                undefined ->
                    respond_error(<<"missing_required_fields">>, [<<"workflow_id">>], Req, State);
                WorkflowId ->
                    Participants = maps:get(<<"participants">>, Data, []),
                    ParticipantsList = [binary_to_existing_atom(P, utf8) || P <- Participants],

                    case yawl_human_in_loop:start_collaborative_session(
                        WorkflowId,
                        ParticipantsList
                    ) of
                        {ok, SessionId} ->
                            Result = #{
                                session_id => SessionId,
                                workflow_id => WorkflowId,
                                participants => Participants,
                                status => <<"active">>
                            },
                            respond(Result, Req, State);
                        {error, Reason} ->
                            respond_error(<<"session_start_failed">>, Reason, Req, State)
                    end
            end;

        [<<"hitl">>, <<"feedback">>] ->
            %% Collect feedback
            case validate_required_fields([<<"workflow_id">>, <<"feedback">>], Data) of
                {error, Missing} ->
                    respond_error(<<"missing_required_fields">>, Missing, Req, State);
                ok ->
                    WorkflowId = maps:get(<<"workflow_id">>, Data),
                    Feedback = maps:get(<<"feedback">>, Data),

                    case yawl_human_in_loop:collect_feedback(WorkflowId, Feedback) of
                        ok ->
                            Result = #{status => <<"collected">>},
                            respond(Result, Req, State);
                        {error, Reason} ->
                            respond_error(<<"feedback_collection_failed">>, Reason, Req, State)
                    end
            end;

        [<<"hitl">>, <<"feedback">>, <<"analyze">>] ->
            %% Analyze feedback with LLM
            case maps:get(<<"workflow_id">>, Data, undefined) of
                undefined ->
                    respond_error(<<"missing_required_fields">>, [<<"workflow_id">>], Req, State);
                WorkflowId ->
                    case yawl_human_in_loop:analyze_feedback_with_llm(WorkflowId) of
                        {ok, Analysis} ->
                            Result = #{
                                workflow_id => WorkflowId,
                                analysis => Analysis
                            },
                            respond(Result, Req, State);
                        {error, Reason} ->
                            respond_error(<<"feedback_analysis_failed">>, Reason, Req, State)
                    end
            end;

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

%% @private
%% @doc Validate that all required fields are present in the data map.
%% Returns ok if all fields are present, {error, MissingFields} otherwise.
validate_required_fields(RequiredFields, Data) ->
    Missing = lists:filter(fun(Field) ->
        not maps:is_key(Field, Data)
    end, RequiredFields),
    case Missing of
        [] -> ok;
        _ -> {error, Missing}
    end.

%% @private
%% @doc Respond with an error in a standardized format.
respond_error(ErrorCode, Details, Req, State) when is_binary(Details) ->
    respond_error(ErrorCode, #{message => Details}, Req, State);
respond_error(ErrorCode, DetailsMap, Req, State) when is_map(DetailsMap) ->
    Response = #{
        status => <<"error">>,
        error_code => ErrorCode,
        details => DetailsMap
    },
    respond_json(Response, 400, Req, State).
