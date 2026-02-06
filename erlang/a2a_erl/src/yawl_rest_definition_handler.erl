%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Definition REST API Handler
%%%
%%% This module provides HTTP REST API endpoints for YAWL workflow
%%% definition management including saving, loading, listing, and
%%% searching workflow definitions.
%%%
%%% ## Endpoints
%%%
%%% - `GET /definitions` - List all workflow definitions
%%% - `POST /definitions` - Save a workflow definition
%%% - `GET /definitions/{id}` - Get a workflow definition
%%% - `DELETE /definitions/{id}` - Delete a workflow definition
%%% - `GET /definitions/search` - Search workflow definitions
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_definition_handler).
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
    definition_id :: binary() | undefined,
    action :: binary() | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    DefinitionId = cowboy_req:binding(definition_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        definition_id = DefinitionId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case State#state.definition_id of
        undefined ->
            %% /definitions - GET, POST
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            %% /definitions/{id} - GET, DELETE
            [<<"GET">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>]
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
    Exists = case State#state.definition_id of
        undefined -> true;  %% Collection resource
        DefinitionId ->
            case yawl_workflow_definition_storage:load_definition(DefinitionId) of
                {error, not_found} -> false;
                {ok, _} -> true
            end
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    case yawl_workflow_definition_storage:delete_definition(State#state.definition_id) of
        ok ->
            Response = #{status => ok, message => <<"Definition deleted">>},
            Req2 = response_json(Req, 200, Response),
            {true, Req2, State};
        {error, not_found} ->
            Response = #{error => <<"definition_not_found">>},
            Req2 = response_json(Req, 404, Response),
            {false, Req2, State};
        {error, Reason} ->
            Response = #{error => to_binary(Reason)},
            Req2 = response_json(Req, 500, Response),
            {false, Req2, State}
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.definition_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            handle_list_definitions(Req);
        {<<"GET">>, DefinitionId, undefined} ->
            handle_get_definition(DefinitionId);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    Body = jiffy:encode(Response),
    {Body, Req, State}.

%% @private
from_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jiffy:decode(Body, [return_maps]),

    Response = case {State#state.method, State#state.definition_id} of
        {<<"POST">>, undefined} ->
            handle_save_definition(Data);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    Req3 = case Response of
        #{error := _} -> cowboy_req:reply(400, #{}, ResponseBody, Req2);
        _ -> cowboy_req:reply(201, #{}, ResponseBody, Req2)
    end,
    {true, Req3, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_definitions(Req) ->
    %% Parse query parameters
    QS = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    PatternType = maps_get(<<"pattern_type">>, Params, undefined),

    Definitions = case PatternType of
        undefined ->
            {ok, AllDefs} = yawl_workflow_definition_storage:list_definitions(),
            AllDefs;
        _ ->
            PatternAtom = try binary_to_existing_atom(PatternType, utf8)
            catch error:badarg -> undefined
            end,
            case PatternAtom of
                undefined -> [];
                _ ->
                    {ok, FilteredDefs} = yawl_workflow_definition_storage:list_definitions_by_pattern(PatternAtom),
                    FilteredDefs
            end
    end,

    #{
        definitions => Definitions,
        total => length(Definitions)
    }.

%% @private
handle_get_definition(DefinitionId) ->
    case yawl_workflow_definition_storage:load_definition(DefinitionId) of
        {error, not_found} ->
            #{error => <<"definition_not_found">>, definition_id => DefinitionId};
        {ok, Definition} ->
            Definition
    end.

%% @private
handle_save_definition(Data) ->
    %% Validate required fields
    case {maps:get(<<"pattern_type">>, Data, undefined), maps:get(<<"name">>, Data, undefined)} of
        {undefined, _} ->
            #{error => <<"missing_pattern_type">>};
        {_, undefined} ->
            #{error => <<"missing_name">>};
        {PatternTypeBin, _} ->
            PatternType = try binary_to_existing_atom(PatternTypeBin, utf8)
            catch error:badarg -> undefined
            end,

            DefinitionId = maps_get(<<"id">>, Data, generate_definition_id()),

            case yawl_workflow_definition_storage:save_definition(DefinitionId, Data) of
                {ok, SavedId} ->
                    #{
                        definition_id => SavedId,
                        status => created,
                        message => <<"Definition saved successfully">>
                    };
                {error, {validation_failed, Errors}} ->
                    #{
                        error => <<"validation_failed">>,
                        details => Errors
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

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
response_json(Req, StatusCode, Body) ->
    EncodedBody = jiffy:encode(Body),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, EncodedBody, Req).

%% @private
generate_definition_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Time = erlang:monotonic_time(millisecond),
    TimeBin = integer_to_binary(Time),
    IdBin = integer_to_binary(UniqueId),
    <<"def_", TimeBin/binary, "_", IdBin/binary>>.
