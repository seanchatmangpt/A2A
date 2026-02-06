%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST Task Handler
%%%
%%% This module provides REST API endpoints for YAWL task management.
%%% It handles task lifecycle operations, workitem management, and
%%% task completion tracking.
%%%
%%% ## Endpoints
%%%
%%% - `GET /tasks` - List all tasks
%%% - `POST /tasks` - Create new task
%%% - `GET /tasks/{id}` - Get specific task
%%% - `PUT /tasks/{id}/complete` - Mark task as complete
%%% - `GET /tasks/{id}/workitems` - Get workitems for task
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_task_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    delete_resource/2,
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
    task_id :: binary() | undefined,
    action :: binary() | undefined,
    content_type :: {binary(), binary(), binary()} | undefined,
    auth_context :: yawl_auth_middleware:request_context() | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, HandlerState) ->
    Method = cowboy_req:method(Req),
    TaskId = cowboy_req:binding(task_id, Req),
    Action = cowboy_req:binding(action, Req),

    %% Check if action was provided in handler state (from route config)
    RouteAction = case cowboy_req:binding(action, Req) of
        undefined ->
            case HandlerState of
                #{action := RouteAction0} -> RouteAction0;
                _ -> undefined
            end;
        BoundAction -> BoundAction
    end,

    NewState = #state{
        method = Method,
        task_id = TaskId,
        action = RouteAction
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case {State#state.task_id, State#state.action} of
        {undefined, undefined} ->
            %% /tasks or /workitems - GET, POST
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _} ->
            %% Invalid path
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {TaskId, undefined} ->
            %% /tasks/{id} or /workitems/{id} - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {TaskId, <<"complete">>} ->
            %% /tasks/{id}/complete or /workitems/{id}/complete - PUT, POST
            [<<"PUT">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {TaskId, <<"workitems">>} ->
            %% /tasks/{id}/workitems - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            %% Unknown action
            [<<"HEAD">>, <<"OPTIONS">>]
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
    Exists = case State#state.task_id of
        undefined -> true;  %% Collection resource
        TaskId ->
            %% For tasks, we'll check if the task exists in any workflow
            %% This is a simplified check - in practice, you'd query workitem storage
            case task_exists(TaskId) of
                true -> true;
                false -> false
            end
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    %% Task deletion typically means cancelling the workitem
    case State#state.task_id of
        undefined ->
            %% Cannot delete collection
            Response = #{error => <<"cannot_delete_collection">>},
            Req2 = response_json(Req, 400, Response),
            {false, Req2, State};
        TaskId ->
            case cancel_task(TaskId) of
                ok ->
                    Response = #{status => ok, message => <<"Task cancelled">>},
                    Req2 = response_json(Req, 200, Response),
                    {true, Req2, State};
                {error, not_found} ->
                    Response = #{error => <<"task_not_found">>},
                    Req2 = response_json(Req, 404, Response),
                    {false, Req2, State};
                {error, Reason} ->
                    Response = #{error => to_binary(Reason)},
                    Req2 = response_json(Req, 400, Response),
                    {false, Req2, State}
            end
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.task_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            %% List all tasks
            handle_list_tasks(Req);
        {<<"GET">>, TaskId, undefined} ->
            %% Get specific task
            handle_get_task(TaskId);
        {<<"GET">>, TaskId, <<"workitems">>} ->
            %% Get workitems for task
            handle_get_task_workitems(TaskId);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
from_json(Req, State) ->
    %% Validate request using the validation middleware
    case validate_task_request_body(Req, State) of
        {error, ErrorResponse, Req2} ->
            Req3 = send_error_response(Req2, ErrorResponse),
            {true, Req3, State};
        {ok, Data, Req2} ->
            Response = case {State#state.method, State#state.task_id} of
                {<<"POST">>, undefined} ->
                    %% Create task (workitem)
                    handle_create_task(Data);
                {<<"PUT">>, TaskId} ->
                    %% Complete task (PUT method)
                    handle_complete_task(TaskId, Data);
                {<<"POST">>, TaskId} when State#state.action =:= <<"complete">> ->
                    %% Complete task (POST method to /complete endpoint)
                    handle_complete_task(TaskId, Data);
                _ ->
                    #{error => <<"unknown_request">>}
            end,

            ResponseBody = jiffy:encode(Response),
            Req3 = case Response of
                #{error := _} = ErrorResp ->
                    send_error_response(Req2, ErrorResp);
                _ ->
                    cowboy_req:reply(200, #{
                        <<"content-type">> => <<"application/json">>
                    }, ResponseBody, Req2)
            end,
            {true, Req3, State}
    end.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_tasks(Req) ->
    %% Parse query parameters
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    {Status, WorkflowId, Limit, Offset} = {
        maps_get(<<"status">>, Params, undefined),
        maps_get(<<"workflow_id">>, Params, undefined),
        maps_get(<<"limit">>, Params, 50),
        maps_get(<<"offset">>, Params, 0)
    },

    %% Get all workitems and filter
    {ok, AllWorkitems} = get_all_workitems(),
    Filtered = filter_workitems(AllWorkitems, Status, WorkflowId),

    %% Apply pagination
    Paginated = case Limit of
        all -> Filtered;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(Filtered, Offset + 1, LimitInt)
    end,

    #{
        tasks => [workitem_to_map(W) || W <- Paginated],
        total => length(Filtered),
        returned => length(Paginated),
        offset => Offset
    }.

%% @private
handle_get_task(TaskId) ->
    case get_workitem_by_id(TaskId) of
        {ok, Workitem} ->
            workitem_to_map(Workitem);
        {error, not_found} ->
            #{error => <<"task_not_found">>, task_id => TaskId}
    end.

%% @private
handle_get_task_workitems(TaskId) ->
    case get_workitem_by_id(TaskId) of
        {ok, Workitem} ->
            %% Find all workitems for the same task in the workflow
            {ok, AllWorkitems} = get_all_workitems(),
            RelatedWorkitems = lists:filter(fun(W) ->
                W#yawl_workitem_persist.task_id =:= Workitem#yawl_workitem_persist.task_id
            end, AllWorkitems),
            #{
                task_id => TaskId,
                workitems => [workitem_to_map(W) || W <- RelatedWorkitems],
                total => length(RelatedWorkitems)
            };
        {error, not_found} ->
            #{error => <<"task_not_found">>, task_id => TaskId}
    end.

%% @private
handle_create_task(Data) ->
    WorkflowId = maps:get(<<"workflow_id">>, Data),
    TaskName = maps:get(<<"task_name">>, Data),
    Priority = binary_to_existing_atom(maps:get(<<"priority">>, Data, <<"normal">>), utf8),
    TaskId = binary_to_existing_atom(maps:get(<<"task_id">>, Data, <<"default_task">>), utf8),
    DataMap = maps:get(<<"data">>, Data, #{}),

    %% Create workitem
    Workitem = #yawl_workitem_persist{
        workitem_id = generate_workitem_id(),
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = TaskName,
        status = pending,
        data = DataMap,
        allocated_to = undefined,
        allocation_time = undefined,
        start_time = undefined,
        completion_time = undefined,
        error = undefined,
        retry_count = 0,
        priority = Priority
    },

    %% Save workitem and queue for processing
    case save_workitem(Workitem) of
        ok ->
            case yawl_human_task:allocate_task(Workitem, #{}) of
                {ok, _} ->
                    #{
                        workitem_id => Workitem#yawl_workitem_persist.workitem_id,
                        task_id => TaskId,
                        status => created,
                        message => <<"Task created and queued">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end;
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
handle_complete_task(TaskId, Data) ->
    WorkitemId = maps:get(<<"workitem_id">>, Data),
    ResultData = maps:get(<<"result">>, Data, #{}),
    WorkflowId = maps:get(<<"workflow_id">>, Data),

    %% First update the workitem in persistence
    case get_workitem_by_id(WorkitemId) of
        {ok, Workitem} ->
            %% Update workitem status
            CompletedWorkitem = Workitem#yawl_workitem_persist{
                status = completed,
                completion_time = erlang:monotonic_time(millisecond),
                data = maps:put(<<"completion_result">>, ResultData, Workitem#yawl_workitem_persist.data)
            },

            case save_workitem(CompletedWorkitem) of
                ok ->
                    %% Notify the workflow instance that the task is complete
                    TaskIdAtom = try
                        binary_to_existing_atom(TaskId, utf8)
                    catch
                        error:badarg ->
                            %% TaskId might be a binary that's not an atom
                            %% Try to use the task_id from the workitem
                            Workitem#yawl_workitem_persist.task_id
                    end,

                    CompleteResult = case WorkflowId of
                        undefined ->
                            %% Try to get workflow_id from workitem
                            case Workitem#yawl_workitem_persist.workflow_id of
                                undefined -> {error, no_workflow_id};
                                WfId -> complete_workflow_task(WfId, TaskIdAtom, ResultData)
                            end;
                        _ ->
                            complete_workflow_task(WorkflowId, TaskIdAtom, ResultData)
                    end,

                    case CompleteResult of
                        ok ->
                            %% Release any allocated resources
                            case yawl_resource_manager:release_resource(WorkitemId) of
                                ok ->
                                    #{
                                        task_id => TaskId,
                                        workitem_id => WorkitemId,
                                        status => completed,
                                        completion_time => CompletedWorkitem#yawl_workitem_persist.completion_time,
                                        result => ResultData
                                    };
                                {error, Reason} ->
                                    #{
                                        task_id => TaskId,
                                        workitem_id => WorkitemId,
                                        status => completed,
                                        warnings => [<<"Resource release failed">>],
                                        error => to_binary(Reason)
                                    }
                            end;
                        {error, Reason} ->
                            #{
                                error => to_binary(Reason),
                                task_id => TaskId,
                                workitem_id => WorkitemId
                            }
                    end;
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end;
        {error, not_found} ->
            #{error => <<"workitem_not_found">>, workitem_id => WorkitemId}
    end.

%% @private
complete_workflow_task(WorkflowId, TaskId, ResultData) ->
    case yawl_orchestrator:get_workflow_instance(WorkflowId) of
        {ok, InstancePid} ->
            yawl_workflow_instance:complete_task(InstancePid, TaskId, ResultData);
        {error, _} ->
            %% Workflow instance not found, try completing via orchestrator
            yawl_orchestrator:complete_workitem(WorkflowId, TaskId, ResultData)
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
task_exists(TaskId) ->
    %% Check if any workitem has this task_id
    {ok, Workitems} = get_all_workitems(),
    lists:any(fun(W) -> W#yawl_workitem_persist.task_id =:= TaskId end, Workitems).

%% @private
cancel_task(TaskId) ->
    %% Find and cancel workitems for this task
    {ok, Workitems} = get_all_workitems(),
    TaskWorkitems = lists:filter(fun(W) -> W#yawl_workitem_persist.task_id =:= TaskId end, Workitems),

    Results = lists:map(fun(Workitem) ->
        case update_workitem_status(Workitem#yawl_workitem_persist.workitem_id, cancelled) of
            ok -> ok;
            {error, _} -> error
        end
    end, TaskWorkitems),

    case lists:member(error, Results) of
        false -> ok;
        true -> {error, cancellation_failed}
    end.

%% @private
get_all_workitems() ->
    %% This would typically query the persistence layer
    %% For now, return empty list - implement based on your storage
    {ok, []}.

%% @private
get_workitem_by_id(WorkitemId) ->
    %% This would typically query the persistence layer
    %% For now, return error - implement based on your storage
    {error, not_found}.

%% @private
save_workitem(Workitem) ->
    %% This would typically save to persistence layer
    %% For now, return ok - implement based on your storage
    ok.

%% @private
update_workitem_status(WorkitemId, Status) ->
    %% This would typically update workitem in persistence layer
    %% For now, return ok - implement based on your storage
    ok.

%% @private
filter_workitems(Workitems, Status, WorkflowId) ->
    lists:filter(fun(W) ->
        (Status =:= undefined orelse W#yawl_workitem_persist.status =:= Status) andalso
        (WorkflowId =:= undefined orelse W#yawl_workitem_persist.workflow_id =:= WorkflowId)
    end, Workitems).

%% @private
generate_workitem_id() ->
    %% Generate unique workitem ID
    Timestamp = erlang:monotonic_time(millisecond),
    Random = rand:uniform(1000000),
    << <<"workitem">>/binary, (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(Random))/binary >>.

%% @private
workitem_to_map(#yawl_workitem_persist{} = W) ->
    #{
        workitem_id => W#yawl_workitem_persist.workitem_id,
        workflow_id => W#yawl_workitem_persist.workflow_id,
        task_id => W#yawl_workitem_persist.task_id,
        task_name => W#yawl_workitem_persist.task_name,
        status => W#yawl_workitem_persist.status,
        data => W#yawl_workitem_persist.data,
        allocated_to => case W#yawl_workitem_persist.allocated_to of
            undefined -> undefined;
            {Pid, Term} -> #{pid => pid_to_list(Pid), term => Term}
        end,
        allocation_time => W#yawl_workitem_persist.allocation_time,
        start_time => W#yawl_workitem_persist.start_time,
        completion_time => W#yawl_workitem_persist.completion_time,
        error => W#yawl_workitem_persist.error,
        retry_count => W#yawl_workitem_persist.retry_count,
        priority => W#yawl_workitem_persist.priority
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
to_binary(Term) -> io_lib:format("~p", [Term]).

%% @private
%% @doc Validate task request body using the validation schema module.
validate_task_request_body(Req, State) ->
    case State#state.method of
        <<"POST">> ->
            case yawl_request_validator:validate_request(Req, task_create) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end;
        <<"PUT">> ->
            case yawl_request_validator:validate_request(Req, task_complete) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end;
        _ ->
            %% Default validation
            case yawl_request_validator:validate_json_body(Req, #{}) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end
    end.

%% @private
%% @doc Send error response with proper status code.
send_error_response(Req, ErrorMap) ->
    ErrorCode = case maps_get(error_code, ErrorMap, undefined) of
        undefined ->
            case maps_get(error, ErrorMap, undefined) of
                <<"task_not_found">> -> task_not_found;
                <<"workitem_not_found">> -> workitem_not_found;
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
        maps_get(details, ErrorMap, #{}),
        maps_get(message, ErrorMap, undefined)
    ),
    StatusCode = maps_get(http_status, ErrorResponse, 400),
    Body = jiffy:encode(ErrorResponse),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req).
