%%%-------------------------------------------------------------------
%%% @doc
%%% REST Handler for Research Module: Colored Petri Nets
%%%
%%% Paper: arXiv:2506.12238 (Mar 2025)
%%% "CPN-Py: Colored Petri Nets with Python Integration"
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_cpn_handler).
-author("A2A Team").

-behaviour(cowboy_handler).

%% Cowboy handler callbacks
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
%% Cowboy Handler Callbacks
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

%%====================================================================
%% Handlers
%%====================================================================

to_json(Req, State) ->
    Method = cowboy_req:method(Req),
    handle_request(Method, Req, State).

%% @private
%% Handle GET requests
handle_request(<<"GET">>, Req, State) ->
    PathInfo = cowboy_req:path_info(Req),
    case PathInfo of
        [<<"cpn">>, <<"llm_format">>, Workflow] ->
            WorkflowAtom = binary_to_existing_atom(Workflow, utf8),
            LLMJSON = yawl_cpn:llm_format_workflow(WorkflowAtom),
            Result = #{
                workflow => Workflow,
                format => <<"llm-json">>,
                data => jiffy:decode(LLMJSON, [return_maps])
            },
            respond(Result, Req, State);
        _ ->
            not_found(Req, State)
    end;

%% @private
%% Handle POST requests
handle_request(<<"POST">>, Req, State) ->
    PathInfo = cowboy_req:path_info(Req),
    {ok, Body, _} = cowboy_req:read_body(Req),
    Data = jiffy:decode(Body, [return_maps]),

    case PathInfo of
        [<<"cpn">>, <<"export">>] ->
            Workflow = maps:get(<<"workflow">>, Data),
            WorkflowAtom = binary_to_existing_atom(Workflow, utf8),
            CPNJSON = yawl_cpn:workflow_to_cpn_json(WorkflowAtom),
            Result = #{
                workflow => Workflow,
                format => <<"cpn-json">>,
                data => jiffy:decode(CPNJSON, [return_maps])
            },
            respond(Result, Req, State);
        [<<"cpn">>, <<"parse">>] ->
            CPNJSON = jiffy:encode(Data),
            Workflow = yawl_cpn:cpn_json_to_workflow(CPNJSON),
            Result = #{
                status => <<"parsed">>,
                workflow => Workflow
            },
            respond(Result, Req, State);
        [<<"cpn">>, <<"llm_parse">>] ->
            LLMJSON = maps:get(<<"llm_json">>, Data),
            Result = case yawl_cpn:parse_llm_workflow(LLMJSON) of
                {ok, ParsedModel} -> #{
                    status => <<"success">>,
                    model => ParsedModel
                };
                {error, Reason} -> #{
                    status => <<"error">>,
                    reason => Reason
                }
            end,
            respond(Result, Req, State);
        [<<"cpn">>, <<"validate">>] ->
            Result = case yawl_cpn:validate_cpn_json(Data) of
                {ok, Validated} -> #{
                    status => <<"valid">>,
                    data => Validated
                };
                {error, Reason} -> #{
                    status => <<"invalid">>,
                    reason => Reason
                }
            end,
            respond(Result, Req, State);
        [<<"cpn">>, <<"guard">>, <<"evaluate">>] ->
            Guard = maps:get(<<"guard">>, Data),
            Marking = maps:get(<<"marking">>, Data),
            Result = case yawl_cpn:evaluate_guard(Guard, Marking) of
                true -> #{result => true, message => <<"Guard evaluates to true">>};
                false -> #{result => false, message => <<"Guard evaluates to false">>}
            end,
            respond(Result, Req, State);
        [<<"cpn">>, <<"color_set">>, <<"create">>] ->
            Name = binary_to_atom(maps:get(<<"name">>, Data), utf8),
            Type = binary_to_atom(maps:get(<<"type">>, Data), utf8),
            yawl_cpn:create_color_set(Name, Type),
            Result = #{
                status => <<"created">>,
                color_set => #{
                    name => Name,
                    type => Type
                }
            },
            respond(Result, Req, State);
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
        message => <<"CPN endpoint not found">>
    },
    respond_json(Response, 404, Req, State).

%% @private
respond_json(Data, StatusCode, Req, State) ->
    Body = jiffy:encode(Data),
    Req0 = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req),
    {stop, Req0, State}.
