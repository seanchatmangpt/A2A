%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Response Serializer
%%%
%%% This module provides response serialization for the YAWL REST API.
%%% It serializes Erlang records to JSON, handles date/time formatting,
%%% and provides consistent response structures for all API endpoints.
%%%
%%% ## Response Format
%%%
%%% All successful responses follow this structure:
%%% ```
%%% {
%%%   "data": {...},
%%%   "meta": {
%%%     "timestamp": "2024-01-01T00:00:00Z",
%%%     "request_id": "uuid"
%%%   },
%%%   "links": {...}
%%% }
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_response_serializer).
-author("A2A Team").

%% API exports
-export([
    serialize/1,
    serialize/2,
    serialize_workflow/1,
    serialize_workflow_list/1,
    serialize_workflow_status/2,
    serialize_resource/1,
    serialize_resource_list/1,
    serialize_task/1,
    serialize_task_list/1,
    serialize_workitem/1,
    serialize_service/1,
    serialize_service_list/1,
    serialize_error/1,
    serialize_validation_errors/1,
    to_json/1,
    format_timestamp/1,
    format_datetime/1,
    format_duration/1,
    create_pagination_meta/4,
    create_response_meta/0,
    create_response_links/2
]).

%% Include files
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Type definitions
-type serializable_data() :: map() | list() | tuple() | #yawl_workflow_persist{} |
                             #yawl_resource_persist{} | #yawl_workitem_persist{} |
                             #yawl_service_registry{} | #yawl_execution_history{}.
-type serialized_response() :: map().
-type meta() :: #{timestamp => binary(), request_id => binary()}.
-type links() :: #{binary() => binary()}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Serialize data to JSON-ready map with default options.
-spec serialize(serializable_data()) -> serialized_response().
serialize(Data) ->
    serialize(Data, #{}).

%% @doc Serialize data to JSON-ready map with options.
-spec serialize(serializable_data(), map()) -> serialized_response().
serialize(Data, Options) when is_map(Data) ->
    %% Already a map, add metadata
    wrap_with_meta(Data, Options);
serialize(Data, Options) when is_list(Data) ->
    %% List of items
    wrap_with_meta(#{data => Data}, Options);
serialize(Record, Options) when is_tuple(Record) ->
    %% Record - determine type and serialize
    case element(1, Record) of
        yawl_workflow_persist -> serialize_workflow(Record, Options);
        yawl_resource_persist -> serialize_resource(Record, Options);
        yawl_workitem_persist -> serialize_workitem(Record, Options);
        yawl_service_registry -> serialize_service(Record, Options);
        yawl_execution_history -> serialize_history(Record, Options);
        _ ->
            %% Unknown record, convert to map as best effort
            wrap_with_meta(Record, Options)
    end.

%% @doc Serialize a workflow record.
-spec serialize_workflow(#yawl_workflow_persist{}) -> serialized_response().
serialize_workflow(Workflow) ->
    serialize_workflow(Workflow, #{}).

%% @private
serialize_workflow(#yawl_workflow_persist{} = W, Options) ->
    Data = #{
        workflow_id => W#yawl_workflow_persist.workflow_id,
        spec_id => W#yawl_workflow_persist.spec_id,
        pattern_type => atom_to_binary(W#yawl_workflow_persist.pattern_type, utf8),
        status => atom_to_binary(W#yawl_workflow_persist.status, utf8),
        marking => serialize_marking(W#yawl_workflow_persist.marking),
        current_place => case W#yawl_workflow_persist.current_place of
            undefined -> null;
            Place -> atom_to_binary(Place, utf8)
        end,
        data => W#yawl_workflow_persist.data,
        parent_workflow_id => W#yawl_workflow_persist.parent_workflow_id,
        created_at => format_timestamp(W#yawl_workflow_persist.created_at),
        updated_at => format_timestamp(W#yawl_workflow_persist.updated_at),
        completed_at => case W#yawl_workflow_persist.completed_at of
            undefined -> null;
            CompletedAt -> format_timestamp(CompletedAt)
        end,
        error => serialize_error(W#yawl_workflow_persist.error)
    },
    wrap_with_meta(Data, Options).

%% @doc Serialize a list of workflows.
-spec serialize_workflow_list([#yawl_workflow_persist{}]) -> serialized_response().
serialize_workflow_list(Workflows) ->
    serialize_workflow_list(Workflows, #{}).

serialize_workflow_list(Workflows, Options) ->
    DataMap = maps:get(data, Options, #{}),
    {Total, Offset, Limit} = {
        maps:get(total, DataMap, length(Workflows)),
        maps:get(offset, DataMap, 0),
        maps:get(limit, DataMap, length(Workflows))
    },
    Serialized = [serialize_workflow(W, #{include_meta => false}) || W <- Workflows],
    Data = #{
        workflows => Serialized,
        total => Total,
        returned => length(Serialized),
        offset => Offset,
        limit => Limit
    },
    Meta = create_pagination_meta(Total, Offset, Limit, Options),
    wrap_with_links(Data, Meta, Options).

%% @doc Serialize workflow status.
-spec serialize_workflow_status(binary(), atom()) -> serialized_response().
serialize_workflow_status(WorkflowId, Status) ->
    Data = #{
        workflow_id => WorkflowId,
        status => atom_to_binary(Status, utf8)
    },
    wrap_with_meta(Data, #{}).

%% @doc Serialize a resource record.
-spec serialize_resource(#yawl_resource_persist{}) -> serialized_response().
serialize_resource(Resource) ->
    serialize_resource(Resource, #{}).

serialize_resource(#yawl_resource_persist{} = R, Options) ->
    Data = #{
        resource_id => R#yawl_resource_persist.resource_id,
        resource_type => atom_to_binary(R#yawl_resource_persist.resource_type, utf8),
        name => R#yawl_resource_persist.name,
        capabilities => [atom_to_binary(C, utf8) || C <- R#yawl_resource_persist.capabilities],
        attributes => R#yawl_resource_persist.attributes,
        status => atom_to_binary(R#yawl_resource_persist.status, utf8),
        current_load => R#yawl_resource_persist.current_load,
        max_capacity => R#yawl_resource_persist.max_capacity,
        available_capacity => max(0, R#yawl_resource_persist.max_capacity - R#yawl_resource_persist.current_load),
        utilization_rate => calculate_utilization(R#yawl_resource_persist.current_load, R#yawl_resource_persist.max_capacity),
        last_heartbeat => case R#yawl_resource_persist.last_heartbeat of
            undefined -> null;
            Heartbeat -> format_timestamp(Heartbeat)
        end,
        metadata => R#yawl_resource_persist.metadata
    },
    wrap_with_meta(Data, Options).

%% @doc Serialize a list of resources.
-spec serialize_resource_list([#yawl_resource_persist{}]) -> serialized_response().
serialize_resource_list(Resources) ->
    serialize_resource_list(Resources, #{}).

serialize_resource_list(Resources, Options) ->
    DataMap = maps:get(data, Options, #{}),
    {Total, Offset, Limit} = {
        maps:get(total, DataMap, length(Resources)),
        maps:get(offset, DataMap, 0),
        maps:get(limit, DataMap, length(Resources))
    },
    Serialized = [serialize_resource(R, #{include_meta => false}) || R <- Resources],
    Data = #{
        resources => Serialized,
        total => Total,
        returned => length(Serialized),
        offset => Offset,
        limit => Limit
    },
    Meta = create_pagination_meta(Total, Offset, Limit, Options),
    wrap_with_links(Data, Meta, Options).

%% @doc Serialize a task/workitem record.
-spec serialize_task(#yawl_workitem_persist{}) -> serialized_response().
serialize_task(Task) ->
    serialize_workitem(Task).

%% @doc Serialize a list of tasks.
-spec serialize_task_list([#yawl_workitem_persist{}]) -> serialized_response().
serialize_task_list(Tasks) ->
    serialize_task_list(Tasks, #{}).

serialize_task_list(Tasks, Options) ->
    DataMap = maps:get(data, Options, #{}),
    {Total, Offset, Limit} = {
        maps:get(total, DataMap, length(Tasks)),
        maps:get(offset, DataMap, 0),
        maps:get(limit, DataMap, length(Tasks))
    },
    Serialized = [serialize_workitem(T, #{include_meta => false}) || T <- Tasks],
    Data = #{
        tasks => Serialized,
        total => Total,
        returned => length(Serialized),
        offset => Offset,
        limit => Limit
    },
    Meta = create_pagination_meta(Total, Offset, Limit, Options),
    wrap_with_links(Data, Meta, Options).

%% @doc Serialize a workitem record.
-spec serialize_workitem(#yawl_workitem_persist{}) -> serialized_response().
serialize_workitem(Workitem) ->
    serialize_workitem(Workitem, #{}).

serialize_workitem(#yawl_workitem_persist{} = W, Options) ->
    Data = #{
        workitem_id => W#yawl_workitem_persist.workitem_id,
        workflow_id => W#yawl_workitem_persist.workflow_id,
        task_id => atom_to_binary(W#yawl_workitem_persist.task_id, utf8),
        task_name => W#yawl_workitem_persist.task_name,
        status => atom_to_binary(W#yawl_workitem_persist.status, utf8),
        data => W#yawl_workitem_persist.data,
        allocated_to => serialize_allocated_to(W#yawl_workitem_persist.allocated_to),
        allocation_time => case W#yawl_workitem_persist.allocation_time of
            undefined -> null;
            Time -> format_timestamp(Time)
        end,
        start_time => case W#yawl_workitem_persist.start_time of
            undefined -> null;
            Time -> format_timestamp(Time)
        end,
        completion_time => case W#yawl_workitem_persist.completion_time of
            undefined -> null;
            Time -> format_timestamp(Time)
        end,
        duration => calculate_duration(W#yawl_workitem_persist.start_time, W#yawl_workitem_persist.completion_time),
        error => serialize_error(W#yawl_workitem_persist.error),
        retry_count => W#yawl_workitem_persist.retry_count,
        priority => atom_to_binary(W#yawl_workitem_persist.priority, utf8)
    },
    wrap_with_meta(Data, Options).

%% @doc Serialize a service record.
-spec serialize_service(#yawl_service_registry{}) -> serialized_response().
serialize_service(Service) ->
    serialize_service(Service, #{}).

serialize_service(#yawl_service_registry{} = S, Options) ->
    Data = #{
        service_id => S#yawl_service_registry.service_id,
        service_name => S#yawl_service_registry.service_name,
        service_type => atom_to_binary(S#yawl_service_registry.service_type, utf8),
        endpoint => S#yawl_service_registry.endpoint,
        health_check_url => S#yawl_service_registry.health_check_url,
        status => atom_to_binary(S#yawl_service_registry.status, utf8),
        last_check => case S#yawl_service_registry.last_check of
            undefined -> null;
            Check -> format_timestamp(Check)
        end,
        response_time => S#yawl_service_registry.response_time,
        success_rate => S#yawl_service_registry.success_rate,
        metadata => S#yawl_service_registry.metadata
    },
    wrap_with_meta(Data, Options).

%% @doc Serialize a list of services.
-spec serialize_service_list([#yawl_service_registry{}]) -> serialized_response().
serialize_service_list(Services) ->
    serialize_service_list(Services, #{}).

serialize_service_list(Services, Options) ->
    DataMap = maps:get(data, Options, #{}),
    {Total, Offset, Limit} = {
        maps:get(total, DataMap, length(Services)),
        maps:get(offset, DataMap, 0),
        maps:get(limit, DataMap, length(Services))
    },
    Serialized = [serialize_service(S, #{include_meta => false}) || S <- Services],
    Data = #{
        services => Serialized,
        total => Total,
        returned => length(Serialized),
        offset => Offset,
        limit => Limit
    },
    Meta = create_pagination_meta(Total, Offset, Limit, Options),
    wrap_with_links(Data, Meta, Options).

%% @doc Serialize an error term.
-spec serialize_error(term()) -> binary() | null.
serialize_error(undefined) -> null;
serialize_error(null) -> null;
serialize_error(Error) when is_binary(Error) -> Error;
serialize_error(Error) when is_atom(Error) -> atom_to_binary(Error, utf8);
serialize_error(Error) -> io_lib:format("~p", [Error]).

%% @doc Serialize validation errors.
-spec serialize_validation_errors([binary()]) -> serialized_response().
serialize_validation_errors(Errors) when is_list(Errors) ->
    #{
        error => true,
        error_code => <<"validation_failed">>,
        message => <<"Request validation failed">>,
        errors => lists:map(fun(Error) ->
            case binary:split(Error, <<": ">>) of
                [Field, Message] ->
                    #{field => Field, message => Message};
                [Field] ->
                    #{field => Field, message => <<>>}
            end
        end, Errors)
    }.

%% @doc Convert response to JSON.
-spec to_json(serialized_response()) -> binary().
to_json(Response) ->
    jiffy:encode(Response).

%% @doc Format a timestamp (milliseconds since epoch) to ISO 8601.
-spec format_timestamp(integer()) -> binary().
format_timestamp(Milliseconds) when is_integer(Milliseconds) ->
    Seconds = Milliseconds div 1000,
    format_datetime(calendar:system_time_to_universal_time(Seconds)).

%% @doc Format a datetime tuple to ISO 8601 string.
-spec format_datetime(calendar:datetime()) -> binary().
format_datetime({{Year, Month, Day}, {Hour, Minute, Second}}) ->
    FormatStr = "~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
    iolist_to_binary(io_lib:format(FormatStr, [Year, Month, Day, Hour, Minute, Second])).

%% @doc Format a duration in milliseconds to human-readable string.
-spec format_duration(integer() | undefined) -> binary() | null.
format_duration(undefined) -> null;
format_duration(0) -> <<"0ms">>;
format_duration(Milliseconds) when is_integer(Milliseconds), Milliseconds < 1000 ->
    <<(integer_to_binary(Milliseconds))/binary, "ms">>;
format_duration(Milliseconds) when is_integer(Milliseconds) ->
    Seconds = Milliseconds / 1000,
    if
        Seconds < 60 ->
            <<(float_to_binary(Seconds, [{decimals, 1}]))/binary, "s">>;
        Seconds < 3600 ->
            Minutes = Seconds / 60,
            <<(float_to_binary(Minutes, [{decimals, 1}]))/binary, "m">>;
        true ->
            Hours = Seconds / 3600,
            <<(float_to_binary(Hours, [{decimals, 1}]))/binary, "h">>
    end.

%% @doc Create pagination metadata.
-spec create_pagination_meta(pos_integer(), non_neg_integer(), pos_integer(), map()) -> meta().
create_pagination_meta(Total, Offset, Limit, Options) ->
    CurrentPage = case Limit of
        0 -> 1;
        _ -> (Offset div Limit) + 1
    end,
    TotalPages = case Limit of
        0 -> 1;
        _ -> (Total + Limit - 1) div Limit
    end,
    _BaseUrl = maps:get(base_url, Options, <<"">>),
    #{
        total => Total,
        offset => Offset,
        limit => Limit,
        current_page => CurrentPage,
        total_pages => TotalPages,
        has_next => CurrentPage < TotalPages,
        has_prev => CurrentPage > 1
    }.

%% @doc Create response metadata.
-spec create_response_meta() -> meta().
create_response_meta() ->
    #{
        timestamp => format_timestamp(erlang:system_time(millisecond)),
        request_id => yawl_error_response:get_request_id()
    }.

%% @doc Create response links (HATEOAS).
-spec create_response_links(binary(), map()) -> links().
create_response_links(BaseUrl, Options) ->
    ResourceId = maps:get(resource_id, Options, undefined),
    ResourceType = maps:get(resource_type, Options, <<"resource">>),

    Links = #{
        self => case ResourceId of
            undefined -> BaseUrl;
            _ -> <<BaseUrl/binary, "/", ResourceId/binary>>
        end
    },

    %% Add collection link
    LinksWithCollection = case ResourceId of
        undefined -> Links;
        _ -> Links#{collection => BaseUrl}
    end,

    %% Add action-specific links based on options
    maybe_add_action_links(LinksWithCollection, BaseUrl, ResourceType, Options).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% @doc Wrap data with response metadata.
-spec wrap_with_meta(map(), map()) -> serialized_response().
wrap_with_meta(Data, Options) ->
    case maps:get(include_meta, Options, true) of
        true ->
            Meta = create_response_meta(),
            Data#{meta => Meta};
        false ->
            Data
    end.

%% @private
%% @doc Wrap data with metadata and links.
-spec wrap_with_links(map(), meta(), map()) -> serialized_response().
wrap_with_links(Data, PaginationMeta, Options) ->
    Response = wrap_with_meta(Data, Options),
    case maps:get(include_links, Options, true) of
        true ->
            BaseUrl = maps:get(base_url, Options, <<"">>),
            Links = create_response_links(BaseUrl, Options),
            Response#{links => Links, pagination => PaginationMeta};
        false ->
            Response#{pagination => PaginationMeta}
    end.

%% @private
%% @doc Serialize marking map to JSON-compatible format.
-spec serialize_marking(map()) -> map().
serialize_marking(Marking) when is_map(Marking) ->
    maps:map(fun(_Key, Value) ->
        case Value of
            Value when is_integer(Value) -> Value;
            Value when is_atom(Value) -> atom_to_binary(Value, utf8);
            Value when is_list(Value) -> [serialize_marking_elem(E) || E <- Value];
            Value when is_map(Value) -> serialize_marking(Value);
            _ -> Value
        end
    end, Marking).

%% @private
serialize_marking_elem(Elem) when is_atom(Elem) -> atom_to_binary(Elem, utf8);
serialize_marking_elem(Elem) when is_integer(Elem) -> Elem;
serialize_marking_elem(Elem) when is_list(Elem) -> [serialize_marking_elem(E) || E <- Elem];
serialize_marking_elem(Elem) -> Elem.

%% @private
%% @doc Serialize allocated_to field.
-spec serialize_allocated_to({pid(), term()} | undefined) -> map() | null.
serialize_allocated_to(undefined) -> null;
serialize_allocated_to({Pid, Term}) ->
    #{
        pid => list_to_binary(pid_to_list(Pid)),
        term => Term
    }.

%% @private
%% @doc Calculate utilization rate.
-spec calculate_utilization(non_neg_integer(), pos_integer()) -> float().
calculate_utilization(Current, Max) when Max > 0 ->
    Current / Max;
calculate_utilization(_Current, _Max) ->
    0.0.

%% @private
%% @doc Calculate duration between start and completion.
-spec calculate_duration(integer() | undefined, integer() | undefined) -> integer() | null.
calculate_duration(undefined, _End) -> null;
calculate_duration(_Start, undefined) -> null;
calculate_duration(Start, End) when is_integer(Start), is_integer(End) ->
    End - Start.

%% @private
%% @doc Maybe add action links based on resource state.
-spec maybe_add_action_links(links(), binary(), binary(), map()) -> links().
maybe_add_action_links(Links, _BaseUrl, _ResourceType, Options) ->
    %% Add standard action links if enabled
    case maps:get(include_actions, Options, false) of
        true ->
            Actions = maps:get(actions, Options, []),
            lists:foldl(fun(Action, Acc) ->
                ActionName = element(1, Action),
                ActionPath = element(2, Action),
                Acc#{ActionName => ActionPath}
            end, Links, Actions);
        false ->
            Links
    end.

%% @private
%% @doc Serialize execution history record.
-spec serialize_history(#yawl_execution_history{}, map()) -> map().
serialize_history(#yawl_execution_history{} = H, _Options) ->
    #{
        history_id => H#yawl_execution_history.history_id,
        workflow_id => H#yawl_execution_history.workflow_id,
        workitem_id => H#yawl_execution_history.workitem_id,
        event_type => atom_to_binary(H#yawl_execution_history.event_type, utf8),
        event_data => H#yawl_execution_history.event_data,
        timestamp => format_timestamp(H#yawl_execution_history.timestamp),
        source => serialize_error(H#yawl_execution_history.source)
    }.
