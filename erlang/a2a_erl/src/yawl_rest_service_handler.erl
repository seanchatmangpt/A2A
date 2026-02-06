%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Service Registry REST Handler
%%%
%%% This module provides HTTP REST API endpoints for service registry
%%% management. It handles service registration, discovery, health checks,
%%% and deregistration.
%%%
%%% ## Endpoints
%%%
%%% - `POST /services` - Register a new service
%%% - `GET /services` - List all services with optional filtering
%%% - `GET /services/{id}` - Get a specific service
%%% - `DELETE /services/{id}` - Deregister a service
%%% - `GET /services/{id}/health` - Check service health
%%% - `PATCH /services/{id}` - Update service configuration
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_service_handler).
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
    service_id :: binary() | undefined,
    action :: binary() | undefined,
    content_type :: {binary(), binary(), binary()} | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ServiceId = cowboy_req:binding(service_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        service_id = ServiceId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case {State#state.service_id, State#state.action} of
        {undefined, undefined} ->
            %% /services - GET, POST
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {ServiceId, undefined} when ServiceId =/= undefined ->
            %% /services/{id} - GET, DELETE, PATCH
            [<<"GET">>, <<"DELETE">>, <<"PATCH">>, <<"HEAD">>, <<"OPTIONS">>];
        {_ServiceId, <<"health">>} ->
            %% /services/{id}/health - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, to_json},
        {{<<"text">>, <<"plain">>, '*'}, to_prometheus}
    ], Req, State}.

%% @private
content_types_accepted(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, from_json}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    Exists = case {State#state.service_id, State#state.action} of
        {undefined, _} -> true;
        {ServiceId, _} when ServiceId =/= undefined ->
            case yawl_service_registry:get_service(ServiceId) of
                {ok, _} -> true;
                {error, _} -> false
            end
    end,
    {Exists, Req, State}.

%% @private
delete_resource(Req, State) ->
    case yawl_service_registry:unregister_service(State#state.service_id) of
        ok ->
            Response = #{
                status => ok,
                message => <<"Service deregistered successfully">>,
                service_id => State#state.service_id
            },
            Req2 = response_json(Req, 200, Response),
            {true, Req2, State};
        {error, Reason} ->
            Response = #{error => to_binary(Reason)},
            Req2 = response_json(Req, 404, Response),
            {false, Req2, State}
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.service_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            handle_list_services(Req);
        {<<"GET">>, ServiceId, undefined} when ServiceId =/= undefined ->
            handle_get_service(ServiceId);
        {<<"GET">>, ServiceId, <<"health">>} when ServiceId =/= undefined ->
            handle_service_health(ServiceId);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
to_prometheus(Req, State) ->
    %% Handle Prometheus format export for metrics
    Response = case {State#state.method, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            %% Check for Prometheus format in query string
            {QS, _} = cowboy_req:qs(Req),
            case string:find(QS, "format=prometheus") of
                nomatch -> handle_list_services(Req);
                _ ->
                    %% Export in Prometheus text format
                    export_services_prometheus()
            end;
        _ ->
            handle_list_services(Req)
    end,

    ResponseBody = case is_binary(Response) of
        true -> Response;
        false -> jiffy:encode(Response)
    end,
    {ResponseBody, Req, State}.

%% @private
from_json(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Req3 = try
        Data = jiffy:decode(Body, [return_maps]),

        Response = case {State#state.method, State#state.service_id} of
            {<<"POST">>, undefined} ->
                handle_register_service(Data);
            {<<"PATCH">>, ServiceId} when ServiceId =/= undefined ->
                handle_update_service(ServiceId, Data);
            _ ->
                #{error => <<"unknown_request">>}
        end,

        ResponseBody = jiffy:encode(Response),
        case Response of
            #{error := _} ->
                cowboy_req:reply(400, #{}, ResponseBody, Req2);
            #{status := created} ->
                cowboy_req:reply(201, #{}, ResponseBody, Req2);
            _ ->
                cowboy_req:reply(200, #{}, ResponseBody, Req2)
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
handle_list_services(Req) ->
    %% Parse query parameters
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    StatusFilter = maps_get(<<"status">>, Params, undefined),
    TypeFilter = maps_get(<<"type">>, Params, undefined),
    Limit = maps_get(<<"limit">>, Params, 100),
    Offset = maps_get(<<"offset">>, Params, 0),

    {ok, AllServices} = yawl_service_registry:list_services(),

    %% Apply filters
    FilteredServices = lists:filter(fun(ServiceMap) ->
        StatusMatch = case StatusFilter of
            undefined -> true;
            StatusBin ->
                ServiceStatus = maps:get(status, ServiceMap, active),
                ServiceStatus =:= binary_to_existing_atom(StatusBin, utf8)
        end,
        TypeMatch = case TypeFilter of
            undefined -> true;
            TypeBin ->
                ServiceType = maps:get(service_type, ServiceMap, unknown),
                ServiceType =:= binary_to_existing_atom(TypeBin, utf8)
        end,
        StatusMatch andalso TypeMatch
    end, AllServices),

    %% Apply pagination
    PaginatedServices = case Limit of
        all -> FilteredServices;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(FilteredServices, Offset + 1, min(LimitInt, length(FilteredServices) - Offset + 1))
    end,

    #{
        services => PaginatedServices,
        total => length(FilteredServices),
        returned => length(PaginatedServices),
        offset => Offset,
        filters => #{
            status => StatusFilter,
            type => TypeFilter
        }
    }.

%% @private
handle_get_service(ServiceId) ->
    case yawl_service_registry:get_service(ServiceId) of
        {ok, Service} ->
            Service;
        {error, not_found} ->
            #{error => <<"service_not_found">>, service_id => ServiceId}
    end.

%% @private
handle_service_health(ServiceId) ->
    case yawl_service_registry:check_health(ServiceId) of
        {ok, Status, ResponseTime} ->
            #{
                service_id => ServiceId,
                status => Status,
                response_time => ResponseTime,
                timestamp => erlang:system_time(millisecond),
                healthy => Status =:= active
            };
        {error, Reason} ->
            #{
                error => to_binary(Reason),
                service_id => ServiceId,
                status => error
            }
    end.

%% @private
handle_register_service(Data) ->
    %% Extract service registration parameters
    ServiceName = maps_get(<<"service_name">>, Data, undefined),
    ServiceTypeBin = maps_get(<<"service_type">>, Data, <<"rest">>),
    Endpoint = maps_get(<<"endpoint">>, Data, undefined),
    HealthCheckUrl = maps_get(<<"health_check_url">>, Data, undefined),
    Metadata = maps_get(<<"metadata">>, Data, #{}),

    %% Validate required fields
    case {ServiceName, Endpoint} of
        {undefined, _} ->
            #{error => <<"missing_service_name">>};
        {_, undefined} ->
            #{error => <<"missing_endpoint">>};
        {ServiceNameVal, EndpointVal} ->
            %% Convert service type binary to atom
            ServiceType = try
                binary_to_existing_atom(ServiceTypeBin, utf8)
            catch
                error:badarg ->
                    %% Default to 'rest' if type doesn't exist
                    rest
            end,

            %% Register service
            Options = #{
                health_check_url => HealthCheckUrl,
                metadata => Metadata
            },

            case yawl_service_registry:register_service(
                ServiceNameVal, ServiceType, EndpointVal, Options) of
                {ok, ServiceId} ->
                    #{
                        status => created,
                        service_id => ServiceId,
                        service_name => ServiceNameVal,
                        service_type => ServiceType,
                        endpoint => EndpointVal,
                        message => <<"Service registered successfully">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end
    end.

%% @private
handle_update_service(ServiceId, Data) ->
    Updates = #{
        endpoint => maps_get(<<"endpoint">>, Data, undefined),
        health_check_url => maps_get(<<"health_check_url">>, Data, undefined),
        metadata => maps_get(<<"metadata">>, Data, #{})
    },

    %% Remove undefined values
    FilteredUpdates = maps:filter(fun(_K, V) -> V =/= undefined end, Updates),

    case maps:size(FilteredUpdates) of
        0 ->
            #{error => <<"no_valid_updates">>};
        _ ->
            %% For update_service, we need to pass metadata separately
            %% Extract endpoint and health_check_url
            UpdateMap = case maps:get(endpoint, FilteredUpdates, undefined) of
                undefined -> #{};
                Endpoint -> #{endpoint => Endpoint}
            end,

            FinalUpdateMap = case maps:get(health_check_url, FilteredUpdates, undefined) of
                undefined -> UpdateMap;
                HcUrl -> UpdateMap#{health_check_url => HcUrl}
            end,

            FinalUpdateMap2 = case maps:get(metadata, FilteredUpdates, undefined) of
                undefined -> FinalUpdateMap;
                Meta -> FinalUpdateMap#{metadata => Meta}
            end,

            case yawl_service_registry:update_service(ServiceId, FinalUpdateMap2) of
                ok ->
                    #{
                        status => ok,
                        service_id => ServiceId,
                        message => <<"Service updated successfully">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end
    end.

%% @private
export_services_prometheus() ->
    {ok, Services} = yawl_service_registry:list_services(),

    Lines = lists:map(fun(Service) ->
        ServiceId = maps:get(service_id, Service, <<"unknown">>),
        ServiceName = maps_get(service_name, Service, <<"unknown">>),
        ServiceType = maps:get(service_type, Service, unknown),
        Status = maps_get(status, Service, active),
        ResponseTime = maps:get(response_time, Service, 0),
        SuccessRate = maps:get(success_rate, Service, 1.0),

        StatusValue = case Status of
            active -> 1;
            _ -> 0
        end,

        [
            <<"yawl_service_up{service=\"", ServiceName/binary,
              "\",id=\"", ServiceId/binary,
              "\",type=\"", (atom_to_binary(ServiceType, utf8))/binary,
              "\"} ", (integer_to_binary(StatusValue))/binary>>,
            <<"yawl_service_response_time{service=\"", ServiceName/binary,
              "\"} ", (integer_to_binary(ResponseTime))/binary>>,
            <<"yawl_service_success_rate{service=\"", ServiceName/binary,
              "\"} ", (float_to_binary(SuccessRate, [{decimals, 3}, compact]))/binary>>
        ]
    end, Services),

    iolist_to_binary(lists:join(<<"\n">>, lists:flatten(Lines))).

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
