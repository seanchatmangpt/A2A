%%%-------------------------------------------------------------------
%%% @doc
%%% REST Handler for Research Module: Reachability Analysis
%%%
%%% Paper: arXiv:2602.02447 (Feb 2026) - Thomas M. Prinz
%%% "Reachability Diagnostics with O(P²+T²) Algorithm"
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_reachability_handler).
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
        [<<"workflows">>, WorkflowId, <<"reachable">>] ->
            Marking = get_marking_from_qs(Req),
            Result = yawl_reachability:is_reachable(
                binary_to_existing_atom(WorkflowId, utf8),
                Marking
            ),
            respond(Result, Req, State);
        [<<"concurrency">>, <<"analysis">>] ->
            Workflow = get_workflow_binding(Req, <<"ordering_workflow">>),
            Result = yawl_concurrency_analyzer:analyze_concurrency(Workflow, #{}),
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
        [<<"reachability">>, <<"diagnostics">>] ->
            Workflow = binary_to_existing_atom(maps:get(<<"workflow">>, Data), utf8),
            Marking = maps:get(<<"marking">>, Data),
            Result = yawl_reachability:reachability_diagnostics(Workflow, Marking),
            respond(Result, Req, State);
        [<<"reachability">>, <<"admissibility">>] ->
            Marking = maps:get(<<"marking">>, Data),
            Result = #{is_admissible => yawl_reachability:is_admissible(Marking)},
            respond(Result, Req, State);
        [<<"reachability">>, <<"maximum_admissible">>] ->
            Places = maps:get(<<"places">>, Data),
            Result = #{maximum_admissible => yawl_reachability:maximum_admissible(Places)},
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
get_marking_from_qs(Req) ->
    QS = cowboy_req:parse_qs(Req),
    lists:foldl(fun({Key, Value}, Acc) ->
        BinKey = binary_to_list(Key),
        Place = list_to_existing_atom(BinKey),
        Acc#{Place => [Value]}
    end, #{}, QS).

%% @private
get_workflow_binding(Req, Default) ->
    case cowboy_req:binding(workflow, Req) of
        undefined -> binary_to_existing_atom(Default, utf8);
        Workflow -> binary_to_existing_atom(Workflow, utf8)
    end.

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
        message => <<"Endpoint not found">>
    },
    respond_json(Response, 404, Req, State).

%% @private
respond_json(Data, StatusCode, Req, State) ->
    Body = jiffy:encode(Data),
    Req0 = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req),
    {stop, Req0, State}.
