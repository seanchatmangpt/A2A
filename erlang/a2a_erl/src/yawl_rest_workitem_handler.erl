%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST Workitem Handler
%%%
%%% This module provides REST API endpoints for YAWL workitem management.
%%% It handles workitem lifecycle operations including listing, claiming,
%%% and retrieving results.
%%%
%%% ## Endpoints
%%%
%%% - `GET /workflows/{id}/workitems` - List workitems for a workflow
%%% - `GET /workitems/{id}` - Get specific workitem
%%% - `POST /workitems/{id}/claim` - Claim a workitem
%%% - `GET /workitems/{id}/result` - Get workitem result
%%% - `POST /workitems/{id}/complete` - Complete a workitem
%%% - `POST /workitems/{id}/release` - Release a claimed workitem
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_workitem_handler).
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
    workflow_id :: binary() | undefined,
    workitem_id :: binary() | undefined,
    action :: binary() | undefined,
    content_type :: {binary(), binary(), binary()} | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, _State) ->
    Method = cowboy_req:method(Req),
    WorkflowId = cowboy_req:binding(workflow_id, Req),
    WorkitemId = cowboy_req:binding(workitem_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        workflow_id = WorkflowId,
        workitem_id = WorkitemId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case {State#state.workflow_id, State#state.workitem_id, State#state.action} of
        {WorkflowId, undefined, undefined} when WorkflowId =/= undefined ->
            %% /workflows/{id}/workitems - GET, POST
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, WorkitemId, undefined} when WorkitemId =/= undefined ->
            %% /workitems/{id} - GET, PUT, DELETE
            [<<"GET">>, <<"PUT">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _WorkitemId, <<"claim">>} ->
            %% /workitems/{id}/claim - POST
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _WorkitemId, <<"result">>} ->
            %% /workitems/{id}/result - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _WorkitemId, <<"complete">>} ->
            %% /workitems/{id}/complete - POST
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _WorkitemId, <<"release">>} ->
            %% /workitems/{id}/release - POST
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _WorkitemId, <<"start">>} ->
            %% /workitems/{id}/start - POST
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            %% Unknown path
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>]
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
    Exists = case {State#state.workflow_id, State#state.workitem_id} of
        {WorkflowId, undefined} when WorkflowId =/= undefined ->
            %% Check workflow exists
            case yawl_persistence:load_workflow(WorkflowId) of
                {ok, _} -> true;
                {error, _} -> false
            end;
        {undefined, WorkitemId} when WorkitemId =/= undefined ->
            %% Check workitem exists
            case yawl_persistence:load_workitem(WorkitemId) of
                {ok, _} -> true;
                {error, _} -> false
            end;
        {undefined, undefined} ->
            %% Collection resource
            true;
        _ ->
            false
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    case State#state.workitem_id of
        undefined ->
            %% Cannot delete collection
            Response = #{error => <<"cannot_delete_collection">>},
            Req2 = response_json(Req, 400, Response),
            {false, Req2, State};
        WorkitemId ->
            case yawl_workitem_processor:cancel_workitem(<<>>, WorkitemId) of
                ok ->
                    Response = #{status => ok, message => <<"Workitem cancelled">>},
                    Req2 = response_json(Req, 200, Response),
                    {true, Req2, State};
                {error, Reason} ->
                    Response = #{error => to_binary(Reason)},
                    Req2 = response_json(Req, 404, Response),
                    {false, Req2, State}
            end
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.workflow_id, State#state.workitem_id, State#state.action} of
        {<<"GET">>, WorkflowId, undefined, undefined} when WorkflowId =/= undefined ->
            %% List workitems for workflow
            handle_list_workflow_workitems(WorkflowId, Req);
        {<<"GET">>, undefined, WorkitemId, undefined} when WorkitemId =/= undefined ->
            %% Get specific workitem
            handle_get_workitem(WorkitemId);
        {<<"GET">>, undefined, WorkitemId, <<"result">>} when WorkitemId =/= undefined ->
            %% Get workitem result
            handle_get_workitem_result(WorkitemId);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
from_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Req3 = try
        Data = jiffy:decode(Body, [return_maps]),

        Response = case {State#state.method, State#state.workflow_id, State#state.workitem_id, State#state.action} of
            {<<"POST">>, WorkflowId, undefined, undefined} when WorkflowId =/= undefined ->
                %% Create workitem for workflow
                handle_create_workitem(WorkflowId, Data);
            {<<"PUT">>, undefined, WorkitemId, undefined} when WorkitemId =/= undefined ->
                %% Update workitem
                handle_update_workitem(WorkitemId, Data);
            {<<"POST">>, undefined, WorkitemId, <<"claim">>} when WorkitemId =/= undefined ->
                %% Claim workitem
                handle_claim_workitem(WorkitemId, Data);
            {<<"POST">>, undefined, WorkitemId, <<"complete">>} when WorkitemId =/= undefined ->
                %% Complete workitem
                handle_complete_workitem(WorkitemId, Data);
            {<<"POST">>, undefined, WorkitemId, <<"release">>} when WorkitemId =/= undefined ->
                %% Release workitem
                handle_release_workitem(WorkitemId, Data);
            {<<"POST">>, undefined, WorkitemId, <<"start">>} when WorkitemId =/= undefined ->
                %% Start workitem
                handle_start_workitem(WorkitemId, Data);
            _ ->
                #{error => <<"unknown_request">>}
        end,

        ResponseBody = jiffy:encode(Response),
        case Response of
            #{error := _} ->
                cowboy_req:reply(400, #{}, ResponseBody, Req2);
            _ ->
                cowboy_req:reply(201, #{}, ResponseBody, Req2)
        end
    catch
        _:_ ->
            ErrorResponse = #{error => <<"invalid_json">>},
            ErrorBody = jiffy:encode(ErrorResponse),
            cowboy_req:reply(400, #{}, ErrorBody, Req2)
    end,
    {true, Req3, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_workflow_workitems(WorkflowId, Req) ->
    %% Parse query parameters
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    {Status, TaskId, Priority, Limit, Offset} = {
        maps_get(<<"status">>, Params, undefined),
        maps_get(<<"task_id">>, Params, undefined),
        maps_get(<<"priority">>, Params, undefined),
        maps_get(<<"limit">>, Params, 50),
        maps_get(<<"offset">>, Params, 0)
    },

    %% Get workitems from persistence
    {ok, AllWorkitems} = case yawl_persistence:list_workitems(WorkflowId) of
        {ok, Items} -> Items;
        {error, _} -> []
    end,

    %% Filter workitems
    Filtered = filter_workitems(
        AllWorkitems,
        WorkflowId,
        Status,
        TaskId,
        Priority
    ),

    %% Apply pagination
    Paginated = case Limit of
        all -> Filtered;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(Filtered, Offset + 1, LimitInt)
    end,

    #{
        workflow_id => WorkflowId,
        workitems => [workitem_to_map(W) || W <- Paginated],
        total => length(Filtered),
        returned => length(Paginated),
        offset => Offset
    }.

%% @private
handle_get_workitem(WorkitemId) ->
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, Workitem} ->
            workitem_to_map(Workitem);
        {error, not_found} ->
            #{error => <<"workitem_not_found">>, workitem_id => WorkitemId}
    end.

%% @private
handle_get_workitem_result(WorkitemId) ->
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, #yawl_workitem_persist{status = completed, data = Data}} ->
            #{
                workitem_id => WorkitemId,
                status => completed,
                result => maps:get(result, Data, #{}),
                completion_time => maps_get(completion_time, Data, undefined)
            };
        {ok, #yawl_workitem_persist{status = Status}} ->
            #{
                error => <<"workitem_not_completed">>,
                workitem_id => WorkitemId,
                current_status => Status
            };
        {error, not_found} ->
            #{error => <<"workitem_not_found">>, workitem_id => WorkitemId}
    end.

%% @private
handle_create_workitem(WorkflowId, Data) ->
    TaskId = binary_to_existing_atom(maps_get(<<"task_id">>, Data, <<"default_task">>), utf8),
    TaskName = maps_get(<<"task_name">>, Data, atom_to_binary(TaskId, utf8)),
    Priority = binary_to_existing_atom(maps_get(<<"priority">>, Data, <<"normal">>), utf8),
    WorkitemData = maps_get(<<"data">>, Data, #{}),

    %% Create workitem
    Workitem = #yawl_workitem_persist{
        workitem_id = generate_workitem_id(),
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = TaskName,
        status = pending,
        data = WorkitemData,
        allocated_to = undefined,
        allocation_time = undefined,
        start_time = undefined,
        completion_time = undefined,
        error = undefined,
        retry_count = 0,
        priority = Priority
    },

    %% Save workitem
    case yawl_persistence:save_workitem(Workitem) of
        ok ->
            #{
                workitem_id => Workitem#yawl_workitem_persist.workitem_id,
                task_id => TaskId,
                status => created,
                message => <<"Workitem created successfully">>
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
handle_update_workitem(WorkitemId, Data) ->
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, Workitem} ->
            %% Update allowed fields
            UpdatedData = maps:merge(Workitem#yawl_workitem_persist.data, maps_get(<<"data">>, Data, #{})),
            UpdatedWorkitem = Workitem#yawl_workitem_persist{data = UpdatedData},

            case yawl_persistence:save_workitem(UpdatedWorkitem) of
                ok ->
                    #{
                        workitem_id => WorkitemId,
                        status => updated,
                        message => <<"Workitem updated successfully">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end;
        {error, not_found} ->
            #{error => <<"workitem_not_found">>, workitem_id => WorkitemId}
    end.

%% @private
handle_claim_workitem(WorkitemId, Data) ->
    UserId = maps_get(<<"user_id">>, Data, undefined),

    case UserId of
        undefined ->
            #{error => <<"missing_user_id">>, required => <<"user_id">>};
        _ ->
            case yawl_human_task:claim_task(UserId, WorkitemId) of
                {ok, Allocation} ->
                    #{
                        workitem_id => WorkitemId,
                        user_id => UserId,
                        status => claimed,
                        allocation => task_queue_to_map(Allocation)
                    };
                {error, already_claimed} ->
                    #{error => <<"workitem_already_claimed">>, workitem_id => WorkitemId};
                {error, task_not_found} ->
                    #{error => <<"workitem_not_found">>, workitem_id => WorkitemId};
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%% @private
handle_complete_workitem(WorkitemId, Data) ->
    UserId = maps_get(<<"user_id">>, Data, undefined),
    Result = maps_get(<<"result">>, Data, #{}),

    case UserId of
        undefined ->
            #{error => <<"missing_user_id">>, required => <<"user_id">>};
        _ ->
            case yawl_human_task:complete_task(UserId, WorkitemId, Result) of
                ok ->
                    %% Update workitem with result
                    case yawl_persistence:load_workitem(WorkitemId) of
                        {ok, Workitem} ->
                            CompletedWorkitem = Workitem#yawl_workitem_persist{
                                status = completed,
                                completion_time = erlang:monotonic_time(millisecond),
                                data = maps:put(result, Result, Workitem#yawl_workitem_persist.data)
                            },
                            case yawl_persistence:save_workitem(CompletedWorkitem) of
                                ok ->
                                    #{
                                        workitem_id => WorkitemId,
                                        user_id => UserId,
                                        status => completed,
                                        result => Result
                                    };
                                {error, Reason} ->
                                    #{error => to_binary(Reason)}
                            end;
                        {error, Reason} ->
                            #{error => to_binary(Reason)}
                    end;
                {error, not_assigned_to_user} ->
                    #{error => <<"workitem_not_assigned_to_user">>, workitem_id => WorkitemId};
                {error, task_not_found} ->
                    #{error => <<"workitem_not_found">>, workitem_id => WorkitemId};
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%% @private
handle_release_workitem(WorkitemId, Data) ->
    UserId = maps_get(<<"user_id">>, Data, undefined),

    case UserId of
        undefined ->
            #{error => <<"missing_user_id">>, required => <<"user_id">>};
        _ ->
            case yawl_human_task:release_task(UserId, WorkitemId) of
                ok ->
                    #{
                        workitem_id => WorkitemId,
                        user_id => UserId,
                        status => released,
                        message => <<"Workitem released successfully">>
                    };
                {error, not_assigned_to_user} ->
                    #{error => <<"workitem_not_assigned_to_user">>, workitem_id => WorkitemId};
                {error, task_not_found} ->
                    #{error => <<"workitem_not_found">>, workitem_id => WorkitemId};
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%% @private
handle_start_workitem(WorkitemId, Data) ->
    UserId = maps_get(<<"user_id">>, Data, undefined),

    case UserId of
        undefined ->
            #{error => <<"missing_user_id">>, required => <<"user_id">>};
        _ ->
            case yawl_human_task:start_task(UserId, WorkitemId) of
                ok ->
                    %% Update workitem status
                    case yawl_persistence:load_workitem(WorkitemId) of
                        {ok, Workitem} ->
                            StartedWorkitem = Workitem#yawl_workitem_persist{
                                status = started,
                                start_time = erlang:monotonic_time(millisecond)
                            },
                            case yawl_persistence:save_workitem(StartedWorkitem) of
                                ok ->
                                    #{
                                        workitem_id => WorkitemId,
                                        user_id => UserId,
                                        status => started,
                                        start_time => StartedWorkitem#yawl_workitem_persist.start_time
                                    };
                                {error, Reason} ->
                                    #{error => to_binary(Reason)}
                            end;
                        {error, Reason} ->
                            #{error => to_binary(Reason)}
                    end;
                {error, not_assigned_to_user} ->
                    #{error => <<"workitem_not_assigned_to_user">>, workitem_id => WorkitemId};
                {error, task_not_found} ->
                    #{error => <<"workitem_not_found">>, workitem_id => WorkitemId};
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
filter_workitems(Workitems, WorkflowId, Status, TaskId, Priority) ->
    lists:filter(fun(W) ->
        W#yawl_workitem_persist.workflow_id =:= WorkflowId andalso
        (Status =:= undefined orelse W#yawl_workitem_persist.status =:= status_binary_to_atom(Status)) andalso
        (TaskId =:= undefined orelse W#yawl_workitem_persist.task_id =:= binary_to_existing_atom(TaskId, utf8)) andalso
        (Priority =:= undefined orelse W#yawl_workitem_persist.priority =:= binary_to_existing_atom(Priority, utf8))
    end, Workitems).

%% @private
status_binary_to_atom(<<"pending">>) -> pending;
status_binary_to_atom(<<"allocated">>) -> allocated;
status_binary_to_atom(<<"started">>) -> started;
status_binary_to_atom(<<"completed">>) -> completed;
status_binary_to_atom(<<"failed">>) -> failed;
status_binary_to_atom(<<"cancelled">>) -> cancelled;
status_binary_to_atom(Other) -> try binary_to_existing_atom(Other, utf8) catch _:_ -> undefined end.

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
            {Pid, Term} when is_pid(Pid) -> #{pid => pid_to_list(Pid), term => Term};
            {ResourceId, _} when is_binary(ResourceId) -> #{resource_id => ResourceId};
            Other -> Other
        end,
        allocation_time => W#yawl_workitem_persist.allocation_time,
        start_time => W#yawl_workitem_persist.start_time,
        completion_time => W#yawl_workitem_persist.completion_time,
        error => W#yawl_workitem_persist.error,
        retry_count => W#yawl_workitem_persist.retry_count,
        priority => W#yawl_workitem_persist.priority
    }.

%% @private
task_queue_to_map(#yawl_task_queue{} = Q) ->
    #{
        queue_id => Q#yawl_task_queue.queue_id,
        task_id => Q#yawl_task_queue.task_id,
        queue_name => Q#yawl_task_queue.queue_name,
        assigned_user => Q#yawl_task_queue.assigned_user,
        assigned_group => Q#yawl_task_queue.assigned_group,
        priority => Q#yawl_task_queue.priority,
        due_date => Q#yawl_task_queue.due_date,
        created_at => Q#yawl_task_queue.created_at,
        claimed_at => Q#yawl_task_queue.claimed_at
    }.

%% @private
generate_workitem_id() ->
    Timestamp = erlang:monotonic_time(millisecond),
    Random = rand:uniform(1000000),
    << <<"workitem">>/binary, (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(Random))/binary >>.

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
