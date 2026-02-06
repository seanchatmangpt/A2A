%%%-------------------------------------------------------------------
%%% @doc
%%% REST Handler for Research Module: LLM Validation
%%%
%%% Paper: arXiv:2509.15336 (Sep 2025)
%%% "LLM Hallucination Detection in Process Modeling"
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_llm_handler).
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
        [<<"llm">>, <<"fidelity">>, ModelId] ->
            Fidelity = yawl_llm_validator:fidelity_score(
                #{id => ModelId},
                #{}
            ),
            Result = #{
                model_id => ModelId,
                fidelity => Fidelity
            },
            respond(Result, Req, State);
        [<<"llm">>, <<"scenarios">>, <<"atypical">>] ->
            Scenario = yawl_llm_validator:create_atypical_process(),
            respond(Scenario, Req, State);
        [<<"llm">>, <<"scenarios">>, <<"standard">>] ->
            Scenario = yawl_llm_validator:create_standard_process(),
            respond(Scenario, Req, State);
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
        [<<"llm">>, <<"validate">>] ->
            LLMModel = maps:get(<<"model">>, Data),
            XESLog = maps:get(<<"xes_log">>, Data),
            Result = yawl_llm_validator:validate_against_xes(LLMModel, XESLog),
            respond(Result, Req, State);
        [<<"llm">>, <<"generate">>] ->
            Description = maps:get(<<"description">>, Data),
            Result = case yawl_llm_validator:llm_generate_model(Description) of
                {ok, Model} -> #{
                    status => <<"success">>,
                    model => Model
                };
                {error, Reason} -> #{
                    status => <<"error">>,
                    reason => Reason
                }
            end,
            respond(Result, Req, State);
        [<<"llm">>, <<"refine">>] ->
            Model = maps:get(<<"model">>, Data),
            Feedback = maps:get(<<"feedback">>, Data),
            Result = case yawl_llm_validator:llm_refine_model(Model, Feedback) of
                {ok, RefinedModel} -> #{
                    status => <<"success">>,
                    model => RefinedModel
                };
                {error, Reason} -> #{
                    status => <<"error">>,
                    reason => Reason
                }
            end,
            respond(Result, Req, State);
        [<<"llm">>, <<"hallucination_report">>] ->
            ValidationResult = maps:get(<<"validation_result">>, Data),
            Report = yawl_llm_validator:hallucination_report(ValidationResult),
            respond(Report, Req, State);
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
        message => <<"LLM endpoint not found">>
    },
    respond_json(Response, 404, Req, State).

%% @private
respond_json(Data, StatusCode, Req, State) ->
    Body = jiffy:encode(Data),
    Req0 = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req),
    {stop, Req0, State}.
