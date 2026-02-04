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
    content_type :: {binary(), binary(), binary()} | undefined
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
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Req3 = try
        Data = jiffy:decode(Body, [return_maps]),

        Response = case {State#state.method, State#state.workflow_id} of
            {<<"POST">>, undefined} ->
                handle_create_workflow(Data);
            {<<"PATCH">>, WorkflowId} ->
                handle_update_workflow(WorkflowId, Data);
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
handle_list_workflows(Req) ->
    %% Parse query parameters
    {QS, _} = cowboy_req:qs(Req),
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
    PatternType = try
        binary_to_existing_atom(maps_get(<<"pattern_type">>, Data, <<"basic_sequential">>), utf8)
    catch
        error:badarg ->
            %% Fallback to default pattern type if atom doesn't exist
            basic_sequential
    end,
    Config = maps_get(<<"config">>, Data, #{}),

    case yawl_orchestrator:create_workflow(PatternType, Config) of
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
            #{error => <<"no_data">>};
        WorkflowData ->
            %% Update workflow data - this would require a workflow instance Pid
            #{error => <<"not_implemented">>}
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
    %% Would need workflow instance Pid
    #{error => <<"not_implemented">>, workflow_id => WorkflowId}.

%% @private
handle_resume_workflow(WorkflowId) ->
    %% Would need workflow instance Pid
    #{error => <<"not_implemented">>, workflow_id => WorkflowId}.

%% @private
handle_checkpoint(WorkflowId) ->
    %% Would need workflow instance Pid
    #{error => <<"not_implemented">>, workflow_id => WorkflowId}.

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
to_binary(Term) -> io_lib:format("~p", [Term]).
