%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST API Handler
%%%
%%% Extended REST handler with comprehensive workflow management
%%% endpoints.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    delete_resource/2,
    is_conflict/2,
    to_json/2,
    from_json/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    workflow_id :: binary() | undefined,
    action :: binary() | undefined,
    content_type :: {binary(), binary(), binary()} | undefined,
    auth_context :: yawl_auth_middleware:request_context() | undefined,
    validation_errors :: [binary()] | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
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
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        _ when State#state.action =:= undefined ->
            [<<"GET">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>, <<"PATCH">>];
        _ ->
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, to_json},
        {{<<"application">>, <<"vnd.api+json">>, '*'}, to_json}
    ], Req, State}.

%% @private
content_types_accepted(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, from_json}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    Exists = case State#state.workflow_id of
        undefined -> true;
        WorkflowId ->
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, _} -> true;
                {error, _} -> false
            end
    end,
    {Exists, Req, State}.

%% @private
is_conflict(Req, State) ->
    IsConflict = case {State#state.method, State#state.workflow_id} of
        {<<"POST">>, undefined} -> false;
        {<<"POST">>, WorkflowId} ->
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, #yawl_workflow_persist{status = running}} -> true;
                _ -> false
            end;
        _ -> false
    end,
    {IsConflict, Req, State}.

%% @private
delete_resource(Req, State) ->
    case yawl_orchestrator:cleanup_workflow(State#state.workflow_id) of
        ok ->
            Response = #{status => ok, message => <<"Workflow deleted">>},
            Req2 = response_json(Req, 200, Response),
            {true, Req2, State};
        {error, Reason} ->
            Response = #{error => to_binary(Reason)},
            Req2 = response_json(Req, 404, Response),
            {false, Req2, State}
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.workflow_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            handle_list_workflows(Req);
        {<<"GET">>, WorkflowId, undefined} ->
            handle_get_workflow(WorkflowId, Req);
        {<<"GET">>, WorkflowId, <<"marking">>} ->
            handle_get_marking(WorkflowId);
        {<<"GET">>, WorkflowId, <<"result">>} ->
            handle_get_result(WorkflowId);
        {<<"GET">>, WorkflowId, <<"history">>} ->
            handle_get_history(WorkflowId);
        {<<"POST">>, WorkflowId, <<"start">>} ->
            handle_start_workflow(WorkflowId);
        {<<"POST">>, WorkflowId, <<"cancel">>} ->
            handle_cancel_workflow(WorkflowId);
        {<<"POST">>, WorkflowId, <<"suspend">>} ->
            handle_suspend_workflow(WorkflowId);
        {<<"POST">>, WorkflowId, <<"pause">>} ->
            handle_suspend_workflow(WorkflowId);
        {<<"POST">>, WorkflowId, <<"resume">>} ->
            handle_resume_workflow(WorkflowId);
        {<<"POST">>, WorkflowId, <<"checkpoint">>} ->
            handle_checkpoint(WorkflowId);
        {<<"POST">>, WorkflowId, Action} ->
            #{error => <<"unknown_action">>, action => Action}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
from_json(Req, State) ->
    %% Validate request using the validation middleware
    case validate_request_body(Req, State) of
        {error, ErrorResponse, Req2} ->
            Req3 = send_error_response(Req2, ErrorResponse),
            {true, Req3, State};
        {ok, Data, Req2} ->
            Response = case {State#state.method, State#state.workflow_id} of
                {<<"POST">>, undefined} ->
                    handle_create_workflow(Data);
                {<<"PATCH">>, WorkflowId} ->
                    handle_update_workflow(WorkflowId, Data);
                _ ->
                    #{error => <<"unknown_request">>}
            end,

            ResponseBody = jiffy:encode(Response),
            Req3 = case Response of
                #{error := _} = ErrorResp ->
                    send_error_response(Req2, ErrorResp);
                _ ->
                    cowboy_req:reply(201, #{
                        <<"content-type">> => <<"application/json">>
                    }, ResponseBody, Req2)
            end,
            {true, Req3, State}
    end.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_workflows(Req) ->
    %% Parse query parameters
    QS = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    {Status, Limit, Offset} = {
        maps_get(<<"status">>, Params, undefined),
        maps_get(<<"limit">>, Params, 50),
        maps_get(<<"offset">>, Params, 0)
    },

    Workflows = case Status of
        undefined ->
            {ok, AllWorkflows} = yawl_persistence:list_workflows(),
            AllWorkflows;
        StatusAtom ->
            {ok, Filtered} = yawl_persistence:list_workflows_by_status(StatusAtom),
            Filtered
    end,

    %% Apply pagination
    Paginated = case Limit of
        all -> Workflows;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(Workflows, Offset + 1, LimitInt)
    end,

    #{
        workflows => [workflow_to_map(W) || W <- Paginated],
        total => length(Workflows),
        returned => length(Paginated),
        offset => Offset
    }.

%% @private
handle_get_workflow(WorkflowId, _Req) ->
    case yawl_persistence:load_workflow(WorkflowId) of
        {ok, Workflow} ->
            workflow_to_map(Workflow);
        {error, not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%% @private
handle_get_marking(WorkflowId) ->
    case yawl_persistence:load_workflow(WorkflowId) of
        {ok, #yawl_workflow_persist{marking = Marking}} ->
            #{workflow_id => WorkflowId, marking => Marking};
        {error, not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%% @private
handle_get_result(WorkflowId) ->
    case yawl_orchestrator:get_workflow_result(WorkflowId) of
        {ok, Result} ->
            #{workflow_id => WorkflowId, result => Result};
        {error, workflow_not_completed} ->
            #{error => <<"workflow_not_completed">>, workflow_id => WorkflowId};
        {error, workflow_not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%% @private
handle_get_history(WorkflowId) ->
    case yawl_persistence:get_workflow_history(WorkflowId) of
        {ok, History} ->
            #{
                workflow_id => WorkflowId,
                history => [history_to_map(H) || H <- History],
                total => length(History)
            };
        {error, not_found} ->
            #{error => <<"workflow_not_found">>, workflow_id => WorkflowId}
    end.

%% @private
handle_create_workflow(Data) ->
    %% Data has been validated and pattern_type is already an atom
    PatternType = maps_get(<<"pattern_type">>, Data, basic_sequential),
    Config = maps_get(<<"config">>, Data, #{}),
    Timeout = maps_get(<<"timeout">>, Data, undefined),
    RetryPolicy = maps_get(<<"retry_policy">>, Data, undefined),

    %% Build final config with optional parameters
    FinalConfig = case Timeout of
        undefined -> Config;
        _ -> Config#{timeout => Timeout}
    end,
    FinalConfig2 = case RetryPolicy of
        undefined -> FinalConfig;
        _ -> FinalConfig#{retry_policy => RetryPolicy}
    end,

    case yawl_orchestrator:create_workflow(PatternType, FinalConfig2) of
        {ok, WorkflowId} ->
            #{
                workflow_id => WorkflowId,
                status => created,
                message => <<"Workflow created successfully">>
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
handle_update_workflow(WorkflowId, Data) ->
    case maps:get(<<"data">>, Data, undefined) of
        undefined ->
            #{error => <<"no_data">>, message => <<"Missing 'data' field in request">>};
        WorkflowData when is_map(WorkflowData) ->
            %% Get workflow instance from orchestrator
            case yawl_orchestrator:get_workflow_instance(WorkflowId) of
                {ok, InstancePid} ->
                    %% Update workflow data by setting each key-value pair
                    UpdateResults = maps:fold(fun(Key, Value, Acc) ->
                        case yawl_workflow_instance:update_data(InstancePid, Key, Value) of
                            ok -> [ok | Acc];
                            {error, Reason} -> [{error, Reason} | Acc]
                        end
                    end, [], WorkflowData),

                    case lists:all(fun(R) -> R =:= ok end, UpdateResults) of
                        true ->
                            %% Also update persistence layer
                            case yawl_persistence:load_workflow(WorkflowId) of
                                {ok, Workflow} ->
                                    %% Merge new data with existing workflow data
                                    ExistingData = Workflow#yawl_workflow_persist.data,
                                    MergedData = maps:merge(ExistingData, WorkflowData),
                                    UpdatedWorkflow = Workflow#yawl_workflow_persist{
                                        data = MergedData,
                                        updated_at = erlang:monotonic_time(millisecond)
                                    },
                                    case yawl_persistence:save_workflow(UpdatedWorkflow) of
                                        ok ->
                                            #{
                                                workflow_id => WorkflowId,
                                                status => updated,
                                                message => <<"Workflow data updated successfully">>,
                                                updated_keys => maps:keys(WorkflowData)
                                            };
                                        {error, Reason} ->
                                            #{
                                                error => to_binary(Reason),
                                                workflow_id => WorkflowId,
                                                message => <<"Workflow instance updated but persistence failed">>
                                            }
                                    end;
                                {error, _} ->
                                    #{
                                        workflow_id => WorkflowId,
                                        status => updated,
                                        message => <<"Workflow data updated (persistence sync pending)">>
                                    }
                            end;
                        false ->
                            Errors = [R || R <- UpdateResults, R =/= ok],
                            #{error => <<"update_failed">>, reasons => Errors}
                    end;
                {error, workflow_instance_not_found} ->
                    %% Workflow not running, try updating persistence directly
                    case yawl_persistence:load_workflow(WorkflowId) of
                        {ok, Workflow} ->
                            ExistingData = Workflow#yawl_workflow_persist.data,
                            MergedData = maps:merge(ExistingData, WorkflowData),
                            UpdatedWorkflow = Workflow#yawl_workflow_persist{
                                data = MergedData,
                                updated_at = erlang:monotonic_time(millisecond)
                            },
                            case yawl_persistence:save_workflow(UpdatedWorkflow) of
                                ok ->
                                    #{
                                        workflow_id => WorkflowId,
                                        status => updated,
                                        message => <<"Workflow data updated in storage">>,
                                        updated_keys => maps:keys(WorkflowData)
                                    };
                                {error, Reason} ->
                                    #{error => to_binary(Reason), workflow_id => WorkflowId}
                            end;
                        {error, Reason} ->
                            #{error => to_binary(Reason), workflow_id => WorkflowId}
                    end;
                {error, Reason} ->
                    #{error => to_binary(Reason), workflow_id => WorkflowId}
            end
    end.

%% @private
handle_start_workflow(WorkflowId) ->
    case yawl_orchestrator:execute_workflow(WorkflowId) of
        {ok, Result} ->
            #{
                workflow_id => WorkflowId,
                status => running,
                message => <<"Workflow started">>,
                result => Result
            };
        {error, Reason} ->
            #{error => to_binary(Reason), workflow_id => WorkflowId}
    end.

%% @private
handle_cancel_workflow(WorkflowId) ->
    case yawl_orchestrator:cancel_workflow(WorkflowId) of
        ok ->
            #{workflow_id => WorkflowId, status => cancelled, message => <<"Workflow cancelled">>};
        {error, Reason} ->
            #{error => to_binary(Reason), workflow_id => WorkflowId}
    end.

%% @private
handle_suspend_workflow(WorkflowId) ->
    case yawl_orchestrator:pause_workflow(WorkflowId) of
        ok ->
            #{workflow_id => WorkflowId, status => paused, message => <<"Workflow paused">>};
        {error, Reason} ->
            #{error => to_binary(Reason), workflow_id => WorkflowId}
    end.

%% @private
handle_resume_workflow(WorkflowId) ->
    case yawl_orchestrator:resume_workflow(WorkflowId) of
        ok ->
            #{workflow_id => WorkflowId, status => resumed, message => <<"Workflow resumed">>};
        {error, Reason} ->
            #{error => to_binary(Reason), workflow_id => WorkflowId}
    end.

%% @private
handle_checkpoint(WorkflowId) ->
    %% Try to create a checkpoint via workflow instance if running
    case yawl_orchestrator:get_workflow_instance(WorkflowId) of
        {ok, InstancePid} ->
            case yawl_workflow_instance:checkpoint(InstancePid) of
                {ok, CheckpointId} ->
                    Timestamp = erlang:monotonic_time(millisecond),
                    #{
                        workflow_id => WorkflowId,
                        checkpoint_id => CheckpointId,
                        timestamp => Timestamp,
                        message => <<"Checkpoint created successfully">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason), workflow_id => WorkflowId}
            end;
        {error, workflow_instance_not_found} ->
            %% Workflow instance not running, try creating checkpoint from persistence
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, Workflow} ->
                    %% Create a checkpoint from the persisted workflow state
                    CheckpointId = <<WorkflowId/binary, "_cp_",
                                   (integer_to_binary(erlang:monotonic_time(millisecond)))/binary>>,
                    Checkpoint = #yawl_checkpoint{
                        checkpoint_id = CheckpointId,
                        workflow_id = WorkflowId,
                        checkpoint_state = #{
                            workflow_id => WorkflowId,
                            status => Workflow#yawl_workflow_persist.status,
                            current_place => Workflow#yawl_workflow_persist.current_place,
                            pattern_type => Workflow#yawl_workflow_persist.pattern_type
                        },
                        marking = Workflow#yawl_workflow_persist.marking,
                        data = Workflow#yawl_workflow_persist.data,
                        timestamp = erlang:monotonic_time(millisecond),
                        sequence_num = 1
                    },
                    case yawl_persistence:save_checkpoint(WorkflowId, Checkpoint) of
                        ok ->
                            #{
                                workflow_id => WorkflowId,
                                checkpoint_id => CheckpointId,
                                timestamp => Checkpoint#yawl_checkpoint.timestamp,
                                message => <<"Checkpoint created from persisted state">>
                            };
                        {error, Reason} ->
                            #{error => to_binary(Reason), workflow_id => WorkflowId}
                    end;
                {error, Reason} ->
                    #{error => to_binary(Reason), workflow_id => WorkflowId}
            end;
        {error, Reason} ->
            #{error => to_binary(Reason), workflow_id => WorkflowId}
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
workflow_to_map(#yawl_workflow_persist{} = W) ->
    #{
        workflow_id => W#yawl_workflow_persist.workflow_id,
        spec_id => W#yawl_workflow_persist.spec_id,
        pattern_type => W#yawl_workflow_persist.pattern_type,
        status => W#yawl_workflow_persist.status,
        created_at => W#yawl_workflow_persist.created_at,
        updated_at => W#yawl_workflow_persist.updated_at,
        completed_at => W#yawl_workflow_persist.completed_at,
        error => W#yawl_workflow_persist.error,
        metadata => #{
            current_place => W#yawl_workflow_persist.current_place,
            parent_workflow_id => W#yawl_workflow_persist.parent_workflow_id
        }
    }.

%% @private
history_to_map(#yawl_execution_history{} = H) ->
    #{
        history_id => H#yawl_execution_history.history_id,
        workflow_id => H#yawl_execution_history.workflow_id,
        workitem_id => H#yawl_execution_history.workitem_id,
        event_type => H#yawl_execution_history.event_type,
        event_data => H#yawl_execution_history.event_data,
        timestamp => H#yawl_execution_history.timestamp,
        source => H#yawl_execution_history.source
    }.

%% @private
parse_query_string(<<>>) ->
    #{};
parse_query_string(QS) ->
    parse_query_params(binary:split(QS, <<"&">>), #{}).

%% @private
parse_query_params([], Acc) ->
    Acc;
parse_query_params([Pair | Rest], Acc) ->
    case binary:split(Pair, <<"=">>) of
        [Key, Value] ->
            DecodedKey = uri_string:unquote(Key),
            DecodedValue = uri_string:unquote(Value),
            parse_query_params(Rest, Acc#{DecodedKey => DecodedValue});
        [Key] ->
            DecodedKey = uri_string:unquote(Key),
            parse_query_params(Rest, Acc#{DecodedKey => true})
    end.

%% @private
response_json(Req, StatusCode, Body) ->
    EncodedBody = jiffy:encode(Body),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, EncodedBody, Req).

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
to_binary(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).

%% @private
%% @doc Validate request body using the validation schema module.
validate_request_body(Req, State) ->
    case State#state.method of
        <<"POST">> ->
            case yawl_request_validator:validate_request(Req, workflow_create) of
                {ok, Data, Req2} ->
                    {ok, Data, Req2};
                {error, _ErrorResponse, Req2} = Error ->
                    Error
            end;
        <<"PATCH">> ->
            case yawl_request_validator:validate_request(Req, workflow_update) of
                {ok, Data, Req2} ->
                    {ok, Data, Req2};
                {error, _ErrorResponse, Req2} = Error ->
                    Error
            end;
        _ ->
            {ok, #{}, Req}
    end.

%% @private
%% @doc Send error response with proper status code.
send_error_response(Req, ErrorMap) ->
    ErrorCode = case maps_get(error_code, ErrorMap, undefined) of
        undefined ->
            case maps_get(error, ErrorMap, undefined) of
                <<"workflow_not_found">> -> workflow_not_found;
                <<"not_implemented">> -> internal_server_error;
                ErrorAtom when is_atom(ErrorAtom) -> ErrorAtom;
                _ -> validation_failed
            end;
        Code when is_atom(Code) ->
            Code;
        CodeBin when is_binary(CodeBin) ->
            try binary_to_existing_atom(CodeBin, utf8)
            catch error:badarg -> validation_failed
            end
    end,
    ErrorResponse = yawl_error_response:format_error(
        ErrorCode,
        maps:get(details, ErrorMap, #{}),
        maps:get(message, ErrorMap, undefined)
    ),
    StatusCode = maps:get(http_status, ErrorResponse, 400),
    Body = jiffy:encode(ErrorResponse),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req).

%% @private
%% @doc Generate a unique request ID.
generate_request_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Time = erlang:monotonic_time(millisecond),
    NodeId = erlang:phash2(node()),
    IdBin = <<UniqueId:32, Time:32, NodeId:32>>,
    binary:encode_hex(IdBin).
