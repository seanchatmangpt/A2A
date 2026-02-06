%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST Resource Handler
%%%
%%% This module provides REST API endpoints for YAWL resource management.
%%% It handles CRUD operations for resources including capacity management
%%% and allocation.
%%%
%%% ## Endpoints
%%%
%%% - `GET /resources` - List all resources
%%% - `POST /resources` - Create new resource
%%% - `GET /resources/{id}` - Get specific resource
%%% - `PUT /resources/{id}` - Update resource
%%% - `DELETE /resources/{id}` - Delete resource
%%% - `GET /resources/{id}/capacity` - Get resource capacity
%%% - `POST /resources/allocate` - Allocate a resource to a workitem
%%% - `POST /resources/deallocate` - Deallocate a resource from a workitem
%%% - `POST /resources/{id}/allocate` - Allocate specific resource to workitem
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_resource_handler).
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
    resource_id :: binary() | undefined,
    action :: binary() | undefined,
    content_type :: {binary(), binary(), binary()} | undefined,
    auth_context :: yawl_auth_middleware:request_context() | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ResourceId = cowboy_req:binding(resource_id, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        resource_id = ResourceId,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case {State#state.resource_id, State#state.action} of
        {undefined, undefined} ->
            %% /resources - GET, POST
            [<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, <<"allocate">>} ->
            %% /resources/allocate - POST (global allocation)
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, <<"deallocate">>} ->
            %% /resources/deallocate - POST (global deallocation)
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        {undefined, _} ->
            %% Invalid path
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {ResourceId, undefined} ->
            %% /resources/{id} - GET, PUT, DELETE
            [<<"GET">>, <<"PUT">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>];
        {ResourceId, <<"capacity">>} ->
            %% /resources/{id}/capacity - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        {ResourceId, <<"allocate">>} ->
            %% /resources/{id}/allocate - POST (specific resource allocation)
            [<<"POST">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            %% Unknown action
            [<<"HEAD">>, <<"OPTIONS">>]
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
    Exists = case {State#state.resource_id, State#state.action} of
        {undefined, undefined} ->
            %% Collection resource - always exists
            true;
        {undefined, <<"allocate">>} ->
            %% Global allocation endpoint - always exists
            true;
        {undefined, <<"deallocate">>} ->
            %% Global deallocation endpoint - always exists
            true;
        {undefined, _} ->
            %% Invalid path
            false;
        {ResourceId, _} ->
            %% Check if specific resource exists
            case yawl_resource_manager:get_resource(ResourceId) of
                {ok, _} -> true;
                {error, _} -> false
            end
    end,
    {Exists, Req, State}.

%% @private
is_conflict(Req, State) ->
    IsConflict = case {State#state.method, State#state.resource_id} of
        {<<"POST">>, undefined} -> false;
        {<<"POST">>, ResourceId} ->
            case yawl_resource_manager:get_resource(ResourceId) of
                {ok, _} -> true;
                _ -> false
            end;
        _ -> false
    end,
    {IsConflict, Req, State}.

%% @private
delete_resource(Req, State) ->
    case State#state.resource_id of
        undefined ->
            %% Cannot delete collection
            Response = #{error => <<"cannot_delete_collection">>},
            Req2 = response_json(Req, 400, Response),
            {false, Req2, State};
        ResourceId ->
            case yawl_resource_manager:unregister_resource(ResourceId) of
                ok ->
                    Response = #{status => ok, message => <<"Resource deleted">>},
                    Req2 = response_json(Req, 200, Response),
                    {true, Req2, State};
                {error, not_found} ->
                    Response = #{error => <<"resource_not_found">>},
                    Req2 = response_json(Req, 404, Response),
                    {false, Req2, State};
                {error, Reason} ->
                    Response = #{error => to_binary(Reason)},
                    Req2 = response_json(Req, 400, Response),
                    {false, Req2, State}
            end
    end.

%% @private
to_json(Req, State) ->
    Response = case {State#state.method, State#state.resource_id, State#state.action} of
        {<<"GET">>, undefined, undefined} ->
            %% List all resources
            handle_list_resources(Req);
        {<<"GET">>, ResourceId, undefined} ->
            %% Get specific resource
            handle_get_resource(ResourceId);
        {<<"GET">>, ResourceId, <<"capacity">>} ->
            %% Get resource capacity
            handle_get_resource_capacity(ResourceId);
        {<<"POST">>, ResourceId, <<"allocate">>} ->
            %% Allocate resource (workitem allocation)
            handle_allocate_resource(ResourceId, Req);
        _ ->
            #{error => <<"unknown_request">>}
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
from_json(Req, State) ->
    %% Validate request using the validation middleware
    case validate_resource_request_body(Req, State) of
        {error, ErrorResponse, Req2} ->
            Req3 = send_error_response(Req2, ErrorResponse),
            {true, Req3, State};
        {ok, Data, Req2} ->
            Response = case {State#state.method, State#state.resource_id, State#state.action} of
                {<<"POST">>, undefined, undefined} ->
                    %% Create resource
                    handle_create_resource(Data);
                {<<"POST">>, undefined, <<"allocate">>} ->
                    %% Global allocation endpoint
                    handle_global_allocate_resource(Data);
                {<<"POST">>, undefined, <<"deallocate">>} ->
                    %% Global deallocation endpoint
                    handle_global_deallocate_resource(Data);
                {<<"PUT">>, ResourceId, undefined} ->
                    %% Update resource
                    handle_update_resource(ResourceId, Data);
                {<<"POST">>, ResourceId, <<"allocate">>} ->
                    %% Specific resource allocation
                    handle_specific_resource_allocate(ResourceId, Data);
                _ ->
                    #{error => <<"unknown_request">>}
            end,

            ResponseBody = jiffy:encode(Response),
            Req3 = case Response of
                #{error := _} = ErrorResp ->
                    send_error_response(Req2, ErrorResp);
                _ ->
                    cowboy_req:reply(201, #{
                        <<"content-type">> => <<"application/json">>
                    }, ResponseBody, Req2)
            end,
            {true, Req3, State}
    end.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_resources(Req) ->
    %% Parse query parameters
    {QS, _} = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    {Type, Status, Limit, Offset} = {
        maps_get(<<"type">>, Params, undefined),
        maps_get(<<"status">>, Params, undefined),
        maps_get(<<"limit">>, Params, 50),
        maps_get(<<"offset">>, Params, 0)
    },

    Resources = case Type of
        undefined when Status =:= undefined ->
            {ok, AllResources} = yawl_resource_manager:list_resources(),
            AllResources;
        undefined ->
            {ok, Filtered} = yawl_resource_manager:list_resources_by_status(Status),
            Filtered;
        TypeAtom ->
            {ok, Filtered} = yawl_resource_manager:list_resources_by_type(TypeAtom),
            Filtered
    end,

    %% Apply pagination
    Paginated = case Limit of
        all -> Resources;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(Resources, Offset + 1, LimitInt)
    end,

    #{
        resources => [resource_to_map(R) || R <- Paginated],
        total => length(Resources),
        returned => length(Paginated),
        offset => Offset
    }.

%% @private
handle_get_resource(ResourceId) ->
    case yawl_resource_manager:get_resource(ResourceId) of
        {ok, Resource} ->
            resource_to_map(Resource);
        {error, not_found} ->
            #{error => <<"resource_not_found">>, resource_id => ResourceId}
    end.

%% @private
handle_get_resource_capacity(ResourceId) ->
    case yawl_resource_manager:get_resource(ResourceId) of
        {ok, Resource} ->
            #{
                resource_id => ResourceId,
                current_load => Resource#yawl_resource_persist.current_load,
                max_capacity => Resource#yawl_resource_persist.max_capacity,
                available_capacity => max(0, Resource#yawl_resource_persist.max_capacity - Resource#yawl_resource_persist.current_load),
                utilization_rate => case Resource#yawl_resource_persist.max_capacity of
                    0 -> 0.0;
                    Max -> Resource#yawl_resource_persist.current_load / Max
                end
            };
        {error, not_found} ->
            #{error => <<"resource_not_found">>, resource_id => ResourceId}
    end.

%% @private
handle_allocate_resource(ResourceId, Req) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = try
        jiffy:decode(Body, [return_maps])
    catch
        _:_ ->
            #{error => <<"invalid_json">>}
    end,

    case Data of
        #{error := _} ->
            Data;
        #{<<"workitem_id">> := WorkitemId, <<"capabilities">> := Capabilities} ->
            case yawl_resource_manager:allocate_resource(WorkitemId, Capabilities) of
                {ok, AllocatedId, Resource} ->
                    #{
                        resource_id => ResourceId,
                        workitem_id => WorkitemId,
                        allocated_resource_id => AllocatedId,
                        status => allocated,
                        resource => resource_to_map(Resource)
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason), resource_id => ResourceId}
            end;
        _ ->
            #{error => <<"missing_parameters">>, required => [<<"workitem_id">>, <<"capabilities">>]}
    end.

%% @private
handle_create_resource(Data) ->
    ResourceName = maps:get(<<"name">>, Data),
    ResourceType = binary_to_existing_atom(maps:get(<<"type">>, Data, <<"human">>), utf8),
    Options = case maps:get(<<"options">>, Data, undefined) of
        undefined -> #{};
        Opts -> Opts
    end,

    %% Add required options
    FinalOptions = Options#{
        capabilities => maps:get(<<"capabilities">>, Options, []),
        max_capacity => maps:get(<<"max_capacity">>, Options, 10),
        attributes => maps:get(<<"attributes">>, Options, #{}),
        metadata => maps:get(<<"metadata">>, Options, #{})
    },

    case yawl_resource_manager:register_resource(ResourceName, ResourceType, FinalOptions) of
        {ok, ResourceId} ->
            #{
                resource_id => ResourceId,
                status => created,
                message => <<"Resource created successfully">>
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
handle_update_resource(ResourceId, Data) ->
    case maps:get(<<"data">>, Data, undefined) of
        undefined ->
            #{error => <<"no_data">>};
        UpdateData ->
            %% Handle different update operations
            UpdateResults = lists:foldl(fun({Key, Value}, Acc) ->
                case update_resource_field(ResourceId, Key, Value) of
                    {ok, _} -> Acc#{Key => updated};
                    {error, _} -> Acc#{Key => error}
                end
            end, #{}, maps:to_list(UpdateData)),

            case lists:all(fun({_, Status}) -> Status =/= error end, maps:to_list(UpdateResults)) of
                true ->
                    #{
                        resource_id => ResourceId,
                        status => updated,
                        updated_fields => maps:keys(UpdateResults)
                    };
                false ->
                    #{
                        resource_id => ResourceId,
                        status => partial_update,
                        updated_fields => [K || {K, V} <- maps:to_list(UpdateResults), V =/= error],
                        errors => [K || {K, V} <- maps:to_list(UpdateResults), V =:= error]
                    }
            end
    end.

%% @private
%% Global allocation endpoint - allocates best matching resource for a workitem
handle_global_allocate_resource(Data) ->
    WorkitemId = maps_get(<<"workitem_id">>, Data, undefined),
    Capabilities = maps_get(<<"capabilities">>, Data, []),
    ResourceType = maps_get(<<"resource_type">>, Data, undefined),

    case WorkitemId of
        undefined ->
            #{error => <<"missing_workitem_id">>, required => <<"workitem_id">>};
        _ ->
            %% Convert capabilities list from binary to atom if needed
            CapabilitiesAtoms = convert_capabilities_to_atoms(Capabilities),

            %% Allocate based on whether resource type is specified
            Result = case ResourceType of
                undefined ->
                    %% Auto-select best resource
                    yawl_resource_manager:allocate_resource(WorkitemId, CapabilitiesAtoms);
                _ ->
                    ResourceTypeAtom = binary_to_existing_atom(ResourceType, utf8),
                    yawl_resource_manager:allocate_resource(WorkitemId, ResourceTypeAtom, CapabilitiesAtoms)
            end,

            case Result of
                {ok, AllocatedResourceId, Resource} ->
                    #{
                        workitem_id => WorkitemId,
                        allocated_resource_id => AllocatedResourceId,
                        status => allocated,
                        resource => resource_to_map(Resource),
                        message => <<"Resource allocated successfully">>
                    };
                {error, no_available_resources} ->
                    #{
                        error => <<"no_available_resources">>,
                        workitem_id => WorkitemId,
                        required_capabilities => Capabilities
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%% @private
%% Global deallocation endpoint - deallocates a resource from a workitem
handle_global_deallocate_resource(Data) ->
    WorkitemId = maps_get(<<"workitem_id">>, Data, undefined),
    ResourceId = maps_get(<<"resource_id">>, Data, undefined),

    case WorkitemId of
        undefined ->
            #{error => <<"missing_workitem_id">>, required => <<"workitem_id">>};
        _ ->
            Result = case ResourceId of
                undefined ->
                    %% Release by workitem ID only
                    yawl_resource_manager:release_resource(WorkitemId);
                _ ->
                    %% Release specific resource for workitem
                    yawl_resource_manager:release_resource(WorkitemId, ResourceId)
            end,

            case Result of
                ok ->
                    #{
                        workitem_id => WorkitemId,
                        resource_id => ResourceId,
                        status => deallocated,
                        message => <<"Resource deallocated successfully">>
                    };
                {error, allocation_not_found} ->
                    #{
                        error => <<"allocation_not_found">>,
                        workitem_id => WorkitemId,
                        resource_id => ResourceId
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason), workitem_id => WorkitemId}
            end
    end.

%% @private
%% Specific resource allocation endpoint - allocates a specific resource
handle_specific_resource_allocate(ResourceId, Data) ->
    WorkitemId = maps_get(<<"workitem_id">>, Data, undefined),

    case WorkitemId of
        undefined ->
            #{error => <<"missing_workitem_id">>, required => <<"workitem_id">>};
        _ ->
            %% Get the resource to verify it exists and get its type/capabilities
            case yawl_resource_manager:get_resource(ResourceId) of
                {ok, ResourceMap} ->
                    ResourceType = maps:get(resource_type, ResourceMap),
                    Capabilities = maps_get(<<"capabilities">>, Data, []),

                    %% Allocate the specific resource
                    ResourceTypeAtom = binary_to_existing_atom(erlang:atom_to_binary(ResourceType, utf8), utf8),
                    CapabilitiesAtoms = convert_capabilities_to_atoms(Capabilities),

                    case yawl_resource_manager:allocate_resource(WorkitemId, ResourceTypeAtom, CapabilitiesAtoms) of
                        {ok, AllocatedId, Resource} when AllocatedId =:= ResourceId ->
                            #{
                                workitem_id => WorkitemId,
                                allocated_resource_id => ResourceId,
                                status => allocated,
                                resource => resource_to_map(Resource),
                                message => <<"Specific resource allocated successfully">>
                            };
                        {ok, AllocatedId, Resource} ->
                            %% A different resource was allocated (fallback)
                            #{
                                workitem_id => WorkitemId,
                                requested_resource_id => ResourceId,
                                allocated_resource_id => AllocatedId,
                                status => allocated,
                                resource => resource_to_map(Resource),
                                message => <<"Alternative resource allocated">>
                            };
                        {error, Reason} ->
                            #{error => to_binary(Reason), workitem_id => WorkitemId}
                    end;
                {error, not_found} ->
                    #{error => <<"resource_not_found">>, resource_id => ResourceId}
            end
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% Convert capabilities list from binary to atom if needed
convert_capabilities_to_atoms(Capabilities) when is_list(Capabilities) ->
    lists:map(fun(Cap) ->
        case Cap of
            Bin when is_binary(Bin) ->
                try binary_to_existing_atom(Bin, utf8)
                catch error:badarg -> Bin
                end;
            Atom when is_atom(Atom) -> Atom;
            _ -> Cap
        end
    end, Capabilities);
convert_capabilities_to_atoms(Capabilities) ->
    Capabilities.

%% @private
update_resource_field(ResourceId, <<"status">>, Status) ->
    StatusAtom = binary_to_existing_atom(Status, utf8),
    case yawl_resource_manager:update_resource_status(ResourceId, StatusAtom) of
        ok -> {ok, updated};
        {error, _} -> {error, invalid_status}
    end;
update_resource_field(ResourceId, <<"load">>, Load) when is_integer(Load) ->
    case yawl_resource_manager:update_resource_load(ResourceId, Load) of
        ok -> {ok, updated};
        {error, _} -> {error, invalid_load}
    end;
update_resource_field(ResourceId, <<"add_capability">>, Capability) ->
    CapabilityAtom = binary_to_existing_atom(Capability, utf8),
    case yawl_resource_manager:add_capability(ResourceId, CapabilityAtom) of
        ok -> {ok, updated};
        {error, _} -> {error, invalid_capability}
    end;
update_resource_field(ResourceId, <<"remove_capability">>, Capability) ->
    CapabilityAtom = binary_to_existing_atom(Capability, utf8),
    case yawl_resource_manager:remove_capability(ResourceId, CapabilityAtom) of
        ok -> {ok, updated};
        {error, _} -> {error, invalid_capability}
    end;
update_resource_field(_ResourceId, _Field, _Value) ->
    {error, unsupported_field}.

%% @private
resource_to_map(#yawl_resource_persist{} = R) ->
    #{
        resource_id => R#yawl_resource_persist.resource_id,
        resource_type => R#yawl_resource_persist.resource_type,
        name => R#yawl_resource_persist.name,
        capabilities => R#yawl_resource_persist.capabilities,
        attributes => R#yawl_resource_persist.attributes,
        status => R#yawl_resource_persist.status,
        current_load => R#yawl_resource_persist.current_load,
        max_capacity => R#yawl_resource_persist.max_capacity,
        last_heartbeat => R#yawl_resource_persist.last_heartbeat,
        metadata => R#yawl_resource_persist.metadata,
        available_capacity => max(0, R#yawl_resource_persist.max_capacity - R#yawl_resource_persist.current_load),
        utilization_rate => case R#yawl_resource_persist.max_capacity of
            0 -> 0.0;
            Max -> R#yawl_resource_persist.current_load / Max
        end
    };
%% @private
resource_to_map(Map) when is_map(Map) ->
    %% Return as-is if already a map
    Map.

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

%% @private
%% @doc Validate resource request body using the validation schema module.
validate_resource_request_body(Req, State) ->
    case {State#state.method, State#state.resource_id, State#state.action} of
        {<<"POST">>, undefined, undefined} ->
            case yawl_request_validator:validate_request(Req, resource_create) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end;
        {<<"PUT">>, _ResourceId, undefined} ->
            case yawl_request_validator:validate_request(Req, resource_update) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end;
        _ ->
            %% For allocation/deallocation, we do minimal validation
            case yawl_request_validator:validate_json_body(Req, #{}) of
                {ok, Data, Req2} -> {ok, Data, Req2};
                {error, _, _} = Error -> Error
            end
    end.

%% @private
%% @doc Send error response with proper status code.
send_error_response(Req, ErrorMap) ->
    ErrorCode = case maps_get(error_code, ErrorMap, undefined) of
        undefined ->
            case maps_get(error, ErrorMap, undefined) of
                <<"resource_not_found">> -> resource_not_found;
                <<"not_implemented">> -> internal_server_error;
                ErrorAtom when is_atom(ErrorAtom) -> ErrorAtom;
                _ -> validation_failed
            end;
        Code when is_atom(Code) ->
            Code;
        CodeBin when is_binary(CodeBin) ->
            try binary_to_existing_atom(CodeBin, utf8)
            catch error:badarg -> validation_failed
            end
    end,
    ErrorResponse = yawl_error_response:format_error(
        ErrorCode,
        maps_get(details, ErrorMap, #{}),
        maps_get(message, ErrorMap, undefined)
    ),
    StatusCode = maps_get(http_status, ErrorResponse, 400),
    Body = jiffy:encode(ErrorResponse),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req).
