%%%-------------------------------------------------------------------
%%% @doc
%%% REST Handler for Research Module: OCPM
%%%
%%% Paper: arXiv:2508.00116 (Jul 2025)
%%% "Object-Centric Process Mining for AI Grounding"
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_ocpm_handler).
-author("A2A Team").

-behaviour(cowboy_handler).

%% Cowboy handler callbacks
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    content_types_accepted/2,
    resource_exists/2,
    to_json/2,
    delete_resource/2
]).

-include("yawl_types.hrl").

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

init(Req, State) ->
    {cowboy_rest, Req, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>, <<"DELETE">>, <<"OPTIONS">>], Req, State}.

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

delete_resource(Req, State) ->
    to_json(Req, State).

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
        [<<"ocpm">>, <<"logs">>, LogId, <<"objects">>, ObjectType] ->
            OCELLog = yawl_ocpm:get_current_log(),
            Events = yawl_ocpm:extract_object_type(ObjectType, OCELLog),
            Result = #{
                log_id => LogId,
                object_type => ObjectType,
                event_count => length(Events),
                events => Events
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"logs">>, LogId, <<"export">>] ->
            OCELLog = yawl_ocpm:get_current_log(),
            XESLog = yawl_ocpm:ocpm_to_standard_xes(OCELLog),
            Result = #{
                log_id => LogId,
                format => <<"xes">>,
                exported_traces => length(maps:get(traces, XESLog, []))
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"lifecycle">>, ObjectId] ->
            Lifecycle = yawl_ocpm:pi_object_lifecycle(ObjectId),
            Result = #{
                object_id => ObjectId,
                lifecycle => Lifecycle
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"dependencies">>] ->
            Deps = yawl_ocpm:pi_inter_object_dependencies(),
            Result = #{dependencies => Deps},
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
        [<<"ocpm">>, <<"events">>] ->
            Event = #{
                event_id => maps:get(<<"event_id">>, Data),
                timestamp => maps:get(<<"timestamp">>, Data, erlang:monotonic_time(millisecond)),
                activity => maps:get(<<"activity">>, Data),
                objects => maps:get(<<"objects">>, Data)
            },
            ObjectTypes = maps:get(<<"object_types">>, Data, []),
            yawl_ocpm:log_multi_object_event(ObjectTypes, Event),
            Result = #{
                status => <<"logged">>,
                event_id => maps:get(<<"event_id">>, Event)
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"ground">>, <<"generative">>] ->
            OCELLog = maps:get(<<"ocel_log">>, Data, yawl_ocpm:get_current_log()),
            Grounded = yawl_ocpm:ground_generative_ai(OCELLog),
            Result = #{
                type => <<"generative">>,
                grounded_model => Grounded
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"ground">>, <<"predictive">>] ->
            OCELLog = maps:get(<<"ocel_log">>, Data, yawl_ocpm:get_current_log()),
            Predictions = yawl_ocpm:ground_predictive_ai(OCELLog),
            Result = #{
                type => <<"predictive">>,
                predictions => Predictions
            },
            respond(Result, Req, State);
        [<<"ocpm">>, <<"ground">>, <<"prescriptive">>] ->
            OCELLog = maps:get(<<"ocel_log">>, Data, yawl_ocpm:get_current_log()),
            Recommendations = yawl_ocpm:ground_prescriptive_ai(OCELLog),
            Result = #{
                type => <<"prescriptive">>,
                recommendations => Recommendations
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
        message => <<"OCPM endpoint not found">>
    },
    respond_json(Response, 404, Req, State).

%% @private
respond_json(Data, StatusCode, Req, State) ->
    Body = jiffy:encode(Data),
    Req0 = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req),
    {stop, Req0, State}.
