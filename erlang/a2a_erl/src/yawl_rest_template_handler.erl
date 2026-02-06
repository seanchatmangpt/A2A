%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Template REST API Handler
%%%
%%% This module provides HTTP REST API endpoints for YAWL workflow
%%% template management including listing, instantiation, and
%%% template details.
%%%
%%% ## Endpoints
%%%
%%% - `GET /templates` - List all available workflow templates
%%% - `GET /templates/{id}` - Get detailed template information
%%% - `POST /templates/{id}/instantiate` - Instantiate a template with parameters
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_template_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
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
    template_id :: binary() | undefined,
    action :: binary() | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    TemplateId = cowboy_req:binding(template_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        template_id = TemplateId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case State#state.template_id of
        undefined when State#state.action =:= undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        undefined ->
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        _ when State#state.action =:= undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
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
    Exists = case State#state.template_id of
        undefined -> true;  %% Collection resource
        TemplateId ->
            case yawl_workflow_templates:get_template(TemplateId) of
                {error, not_found} -> false;
                {ok, _} -> true
            end
    end,
    {Exists, Req, State}.

%% @private
to_json(Req, State) ->
    Response = case {State#state.template_id, State#state.action} of
        {undefined, undefined} ->
            handle_list_templates();
        {TemplateId, undefined} ->
            handle_get_template(TemplateId);
        {undefined, Action} ->
            #{error => <<"unknown_action">>, action => Action};
        {_, _} ->
            #{error => <<"invalid_request">>}
    end,

    Body = jiffy:encode(Response),
    {Body, Req, State}.

%% @private
from_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jiffy:decode(Body, [return_maps]),

    Response = case {State#state.method, State#state.template_id, State#state.action} of
        {<<"POST">>, TemplateId, <<"instantiate">>} ->
            handle_instantiate_template(TemplateId, Data);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    Req3 = cowboy_req:reply(201, #{}, ResponseBody, Req2),
    {true, Req3, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_templates() ->
    {ok, Templates} = yawl_workflow_templates:list_templates(),
    #{
        templates => Templates,
        total => length(Templates)
    }.

%% @private
handle_get_template(TemplateId) ->
    case yawl_workflow_templates:get_template(TemplateId) of
        {error, not_found} ->
            #{error => <<"template_not_found">>, template_id => TemplateId};
        {ok, Template} ->
            Template
    end.

%% @private
handle_instantiate_template(TemplateId, Parameters) ->
    case yawl_workflow_templates:instantiate_template(TemplateId, Parameters) of
        {ok, WorkflowDef} ->
            #{
                template_id => TemplateId,
                status => instantiated,
                workflow_definition => WorkflowDef
            };
        {error, {parameter_errors, Errors}} ->
            #{
                error => <<"invalid_parameters">>,
                details => Errors
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_list(Term) -> list_to_binary(Term);
to_binary(Term) -> io_lib:format("~p", [Term]).
