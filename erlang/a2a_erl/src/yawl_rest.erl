%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST API Module
%%%
%%% This module provides HTTP REST API endpoints for YAWL workflow
%%% management using the Cowboy web server.
%%%
%%% ## Endpoints
%%%
%%% - `POST /workflows` - Create a new workflow
%%% - `GET /workflows/{id}` - Get workflow status
%%% - `POST /workflows/{id}/start` - Start a workflow
%%% - `POST /workflows/{id}/cancel` - Cancel a workflow
%%% - `GET /workflows` - List all workflows
%%% - `DELETE /workflows/{id}` - Delete a workflow
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
    Host = maps_get(host, Options, 'localhost'),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/workflows", yawl_rest_handler, []},
            {"/workflows/:workflow_id", yawl_rest_handler, []},
            {"/workflows/:workflow_id/:action", yawl_rest_handler, []},
            {"/resources", yawl_rest_resource_handler, []},
            {"/resources/:resource_id", yawl_rest_resource_handler, []},
            {"/tasks", yawl_rest_task_handler, []},
            {"/tasks/:task_id", yawl_rest_task_handler, []}
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
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/workflows", yawl_rest_handler, []},
            {"/workflows/:workflow_id", yawl_rest_handler, []},
            {"/workflows/:workflow_id/:action", yawl_rest_handler, []},
            {"/resources", yawl_rest_resource_handler, []},
            {"/resources/:resource_id", yawl_rest_resource_handler, []},
            {"/tasks", yawl_rest_task_handler, []},
            {"/tasks/:task_id", yawl_rest_task_handler, []}
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
        modules => [cowboy_clear, yawl_rest_handler]
    }.

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
    case yawl_orchestrator:cleanup_workflow(State#state.workflow_id) of
        ok ->
            Response = #{status => ok},
            {true, cowboy_req:reply(200, #{}, jiffy:encode(Response), Req), State};
        {error, Reason} ->
            Response = #{error => to_binary(Reason)},
            {false, cowboy_req:reply(404, #{}, jiffy:encode(Response), Req), State}
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
        {<<"POST">>, WorkflowId, Action} ->
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
