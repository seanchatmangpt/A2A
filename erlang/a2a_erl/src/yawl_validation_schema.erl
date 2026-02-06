%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Validation Schema Definitions
%%%
%%% This module defines JSON validation schemas for all YAWL REST API
%%% endpoints using jiffy for JSON parsing and validation. It provides
%%% validation functions for workflow, resource, task, and service requests.
%%%
%%% ## Schema Structure
%%%
%%% Each schema defines:
%%% - Required fields
%%% - Optional fields with default values
%%% - Field types and constraints
%%% - Custom validation rules
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_validation_schema).
-author("A2A Team").

%% API exports
-export([
    validate/2,
    validate_workflow_create/1,
    validate_workflow_update/1,
    validate_resource_create/1,
    validate_resource_update/1,
    validate_task_create/1,
    validate_task_complete/1,
    validate_service_register/1,
    validate_service_update/1,
    validate_query_params/2,
    validate_field_type/3,
    validate_enum/3,
    validate_range/4,
    validate_pattern/3,
    validate_schema/2
]).

%% Include files
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Type definitions
-type schema_validation_result() :: {ok, map()} | {error, [binary()]}.
-type schema() :: #{
    required => [binary()],
    optional => [{binary(), term()}],
    types => #{binary() => atom()},
    constraints => #{binary() => fun((term()) -> boolean())}
}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Validate data against a named schema.
-spec validate(atom(), map()) -> schema_validation_result().
validate(workflow_create, Data) ->
    validate_workflow_create(Data);
validate(workflow_update, Data) ->
    validate_workflow_update(Data);
validate(resource_create, Data) ->
    validate_resource_create(Data);
validate(resource_update, Data) ->
    validate_resource_update(Data);
validate(task_create, Data) ->
    validate_task_create(Data);
validate(task_complete, Data) ->
    validate_task_complete(Data);
validate(service_register, Data) ->
    validate_service_register(Data);
validate(service_update, Data) ->
    validate_service_update(Data);
validate({query_params, SchemaName}, Params) ->
    validate_query_params(SchemaName, Params);
validate(_SchemaName, _Data) ->
    {error, [<<"unknown_schema">>]}.

%% @doc Validate workflow creation request.
-spec validate_workflow_create(map()) -> schema_validation_result().
validate_workflow_create(Data) when is_map(Data) ->
    Schema = #{
        required => [<<"pattern_type">>],
        optional => [
            {<<"config">>, #{}},
            {<<"timeout">>, 30000},
            {<<"retry_policy">>, undefined},
            {<<"metadata">>, #{}}
        ],
        types => #{
            <<"pattern_type">> => {atom, [
                basic_sequential,
                parallel_split,
                parallel_join,
                exclusive_choice,
                simple_merge,
                iterative_loop,
                multi_instance,
                interleaved_parallelism,
                implicit_merge,
                multiple_merge,
                deferred_choice,
                interleaved_routing,
                milestone
            ]},
            <<"config">> => map,
            <<"timeout">> => integer,
            <<"retry_policy">> => map,
            <<"metadata">> => map
        },
        constraints => #{
            <<"timeout">> => fun(Val) -> Val > 0 andalso Val =< 3600000 end,
            <<"pattern_type">> => fun(Val) -> is_atom(Val) end
        }
    },
    validate_schema(Schema, Data);
validate_workflow_create(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate workflow update request.
-spec validate_workflow_update(map()) -> schema_validation_result().
validate_workflow_update(Data) when is_map(Data) ->
    Schema = #{
        required => [],
        optional => [
            {<<"status">>, undefined},
            {<<"data">>, #{}},
            {<<"metadata">>, #{}}
        ],
        types => #{
            <<"status">> => {atom, [pending, running, completed, failed, cancelled]},
            <<"data">> => map,
            <<"metadata">> => map
        },
        constraints => #{}
    },
    validate_schema(Schema, Data);
validate_workflow_update(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate resource creation request.
-spec validate_resource_create(map()) -> schema_validation_result().
validate_resource_create(Data) when is_map(Data) ->
    Schema = #{
        required => [<<"name">>, <<"type">>],
        optional => [
            {<<"capabilities">>, []},
            {<<"max_capacity">>, 10},
            {<<"attributes">>, #{}},
            {<<"metadata">>, #{}}
        ],
        types => #{
            <<"name">> => binary,
            <<"type">> => {atom, [human, service, system]},
            <<"capabilities">> => {list, atom},
            <<"max_capacity">> => integer,
            <<"attributes">> => map,
            <<"metadata">> => map
        },
        constraints => #{
            <<"name">> => fun(Val) -> byte_size(Val) > 0 andalso byte_size(Val) =< 256 end,
            <<"max_capacity">> => fun(Val) -> Val > 0 andalso Val =< 1000 end,
            <<"capabilities">> => fun(Val) -> is_list(Val) end
        }
    },
    validate_schema(Schema, Data);
validate_resource_create(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate resource update request.
-spec validate_resource_update(map()) -> schema_validation_result().
validate_resource_update(Data) when is_map(Data) ->
    Schema = #{
        required => [],
        optional => [
            {<<"status">>, undefined},
            {<<"load">>, undefined},
            {<<"add_capability">>, undefined},
            {<<"remove_capability">>, undefined},
            {<<"max_capacity">>, undefined},
            {<<"attributes">>, undefined}
        ],
        types => #{
            <<"status">> => {atom, [available, busy, unavailable, offline]},
            <<"load">> => integer,
            <<"add_capability">> => atom,
            <<"remove_capability">> => atom,
            <<"max_capacity">> => integer,
            <<"attributes">> => map
        },
        constraints => #{
            <<"load">> => fun(Val) -> Val >= 0 end,
            <<"max_capacity">> => fun(Val) -> Val > 0 end
        }
    },
    validate_schema(Schema, Data);
validate_resource_update(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate task creation request.
-spec validate_task_create(map()) -> schema_validation_result().
validate_task_create(Data) when is_map(Data) ->
    Schema = #{
        required => [<<"workflow_id">>, <<"task_name">>],
        optional => [
            {<<"task_id">>, <<"default_task">>},
            {<<"priority">>, <<"normal">>},
            {<<"data">>, #{}},
            {<<"due_date">>, undefined},
            {<<"metadata">>, #{}}
        ],
        types => #{
            <<"workflow_id">> => binary,
            <<"task_name">> => binary,
            <<"task_id">> => atom,
            <<"priority">> => {atom, [low, normal, high, urgent]},
            <<"data">> => map,
            <<"due_date">> => integer,
            <<"metadata">> => map
        },
        constraints => #{
            <<"workflow_id">> => fun(Val) -> byte_size(Val) > 0 end,
            <<"task_name">> => fun(Val) -> byte_size(Val) > 0 andalso byte_size(Val) =< 256 end,
            <<"due_date">> => fun(Val) -> Val > 0 end
        }
    },
    validate_schema(Schema, Data);
validate_task_create(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate task completion request.
-spec validate_task_complete(map()) -> schema_validation_result().
validate_task_complete(Data) when is_map(Data) ->
    Schema = #{
        required => [<<"workitem_id">>],
        optional => [
            {<<"result">>, #{}},
            {<<"comments">>, undefined},
            {<<"status">>, <<"completed">>}
        ],
        types => #{
            <<"workitem_id">> => binary,
            <<"result">> => map,
            <<"comments">> => binary,
            <<"status">> => {atom, [completed, failed, cancelled]}
        },
        constraints => #{
            <<"workitem_id">> => fun(Val) -> byte_size(Val) > 0 end,
            <<"comments">> => fun(Val) -> Val =:= undefined orelse byte_size(Val) =< 4096 end
        }
    },
    validate_schema(Schema, Data);
validate_task_complete(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate service registration request.
-spec validate_service_register(map()) -> schema_validation_result().
validate_service_register(Data) when is_map(Data) ->
    Schema = #{
        required => [<<"service_name">>, <<"service_type">>, <<"endpoint">>],
        optional => [
            {<<"health_check_url">>, undefined},
            {<<"metadata">>, #{}}
        ],
        types => #{
            <<"service_name">> => binary,
            <<"service_type">> => atom,
            <<"endpoint">> => binary,
            <<"health_check_url">> => binary,
            <<"metadata">> => map
        },
        constraints => #{
            <<"service_name">> => fun(Val) -> byte_size(Val) > 0 andalso byte_size(Val) =< 256 end,
            <<"endpoint">> => fun(Val) -> is_valid_url(Val) end,
            <<"health_check_url">> => fun(Val) -> Val =:= undefined orelse is_valid_url(Val) end
        }
    },
    validate_schema(Schema, Data);
validate_service_register(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate service update request.
-spec validate_service_update(map()) -> schema_validation_result().
validate_service_update(Data) when is_map(Data) ->
    Schema = #{
        required => [],
        optional => [
            {<<"endpoint">>, undefined},
            {<<"status">>, undefined},
            {<<"health_check_url">>, undefined},
            {<<"metadata">>, undefined}
        ],
        types => #{
            <<"endpoint">> => binary,
            <<"status">> => {atom, [active, inactive, degraded]},
            <<"health_check_url">> => binary,
            <<"metadata">> => map
        },
        constraints => #{
            <<"endpoint">> => fun(Val) -> Val =:= undefined orelse is_valid_url(Val) end,
            <<"health_check_url">> => fun(Val) -> Val =:= undefined orelse is_valid_url(Val) end
        }
    },
    validate_schema(Schema, Data);
validate_service_update(_Data) ->
    {error, [<<"invalid_data_type">>]}.

%% @doc Validate query parameters.
-spec validate_query_params(atom(), map()) -> schema_validation_result().
validate_query_params(workflow_list, Params) when is_map(Params) ->
    Schema = #{
        required => [],
        optional => [
            {<<"status">>, undefined},
            {<<"limit">>, 50},
            {<<"offset">>, 0}
        ],
        types => #{
            <<"status">> => {atom, [pending, running, completed, failed, cancelled]},
            <<"limit">> => integer,
            <<"offset">> => integer
        },
        constraints => #{
            <<"limit">> => fun(Val) -> Val > 0 andalso Val =< 1000 end,
            <<"offset">> => fun(Val) -> Val >= 0 end
        }
    },
    validate_schema(Schema, Params);
validate_query_params(resource_list, Params) when is_map(Params) ->
    Schema = #{
        required => [],
        optional => [
            {<<"type">>, undefined},
            {<<"status">>, undefined},
            {<<"limit">>, 50},
            {<<"offset">>, 0}
        ],
        types => #{
            <<"type">> => {atom, [human, service, system]},
            <<"status">> => {atom, [available, busy, unavailable, offline]},
            <<"limit">> => integer,
            <<"offset">> => integer
        },
        constraints => #{
            <<"limit">> => fun(Val) -> Val > 0 andalso Val =< 1000 end,
            <<"offset">> => fun(Val) -> Val >= 0 end
        }
    },
    validate_schema(Schema, Params);
validate_query_params(task_list, Params) when is_map(Params) ->
    Schema = #{
        required => [],
        optional => [
            {<<"status">>, undefined},
            {<<"workflow_id">>, undefined},
            {<<"limit">>, 50},
            {<<"offset">>, 0}
        ],
        types => #{
            <<"status">> => {atom, [pending, allocated, started, completed, failed, cancelled]},
            <<"workflow_id">> => binary,
            <<"limit">> => integer,
            <<"offset">> => integer
        },
        constraints => #{
            <<"limit">> => fun(Val) -> Val > 0 andalso Val =< 1000 end,
            <<"offset">> => fun(Val) -> Val >= 0 end
        }
    },
    validate_schema(Schema, Params);
validate_query_params(_SchemaName, _Params) ->
    {error, [<<"unknown_query_schema">>]}.

%% @doc Validate a field's type.
-spec validate_field_type(binary(), term(), atom() | {atom, [atom()]}) ->
    {ok, term()} | {error, binary()}.
validate_field_type(_Field, Value, binary) when is_binary(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, atom) when is_atom(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, integer) when is_integer(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, float) when is_float(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, boolean) when is_boolean(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, map) when is_map(Value) ->
    {ok, Value};
validate_field_type(_Field, Value, list) when is_list(Value) ->
    {ok, Value};
validate_field_type(Field, Value, {atom, AllowedValues}) when is_atom(Value) ->
    case lists:member(Value, AllowedValues) of
        true -> {ok, Value};
        false -> {error, <<Field/binary, ": invalid value, expected one of: ",
                          (list_to_binary([atom_to_binary(A, utf8) || A <- AllowedValues]))/binary>>}
    end;
validate_field_type(Field, Value, {list, ElementType}) when is_list(Value) ->
    case validate_list_elements(Field, Value, ElementType) of
        {ok, Converted} -> {ok, Converted};
        {error, _} = Error -> Error
    end;
validate_field_type(Field, Value, binary) when is_integer(Value) orelse is_atom(Value) ->
    {ok, convert_to_binary(Value)};
validate_field_type(Field, Value, atom) when is_binary(Value) ->
    try {ok, binary_to_existing_atom(Value, utf8)}
    catch error:badarg ->
        {error, <<Field/binary, ": cannot convert to atom">>}
    end;
validate_field_type(Field, Value, integer) when is_binary(Value) ->
    try {ok, binary_to_integer(Value)}
    catch error:badarg ->
        {error, <<Field/binary, ": cannot convert to integer">>}
    end;
validate_field_type(Field, _Value, Type) when is_atom(Type) ->
    {error, <<Field/binary, ": expected type ", (atom_to_binary(Type, utf8))/binary>>};
validate_field_type(Field, _Value, Type) ->
    TypeBin = iolist_to_binary(io_lib:format("~p", [Type])),
    {error, <<Field/binary, ": expected type ", TypeBin/binary>>}.

%% @doc Validate an enum value.
-spec validate_enum(binary(), term(), [atom()]) -> {ok, term()} | {error, binary()}.
validate_enum(_Field, Value, Allowed) when is_atom(Value) ->
    case lists:member(Value, Allowed) of
        true -> {ok, Value};
        false -> {error, <<"Invalid enum value">>}
    end;
validate_enum(Field, Value, Allowed) when is_binary(Value) ->
    case binary_to_existing_atom(Value, utf8) of
        Atom when is_atom(Atom) ->
            case lists:member(Atom, Allowed) of
                true -> {ok, Atom};
                false -> {error, <<Field/binary, ": invalid enum value">>}
            end;
        _ ->
            {error, <<Field/binary, ": invalid enum value">>}
    end.

%% @doc Validate a numeric range.
-spec validate_range(binary(), term(), number() | undefined, number() | undefined) ->
    {ok, term()} | {error, binary()}.
validate_range(_Field, Value, Min, Max) when is_number(Value) ->
    TooLow = case Min of
        undefined -> false;
        _ -> Value < Min
    end,
    TooHigh = case Max of
        undefined -> false;
        _ -> Value > Max
    end,
    case {TooLow, TooHigh} of
        {true, _} -> {error, <<"Value below minimum">>};
        {_, true} -> {error, <<"Value above maximum">>};
        _ -> {ok, Value}
    end;
validate_range(Field, _Value, _Min, _Max) ->
    {error, <<Field/binary, ": not a number">>}.

%% @doc Validate a value against a pattern.
-spec validate_pattern(binary(), binary(), binary() | atom()) ->
    {ok, term()} | {error, binary()}.
validate_pattern(_Field, Value, Pattern) when is_atom(Pattern) ->
    case Pattern of
        uuid -> validate_uuid(Value);
        email -> validate_email(Value);
        url -> validate_url(Value);
        timestamp -> validate_timestamp(Value);
        _ -> {ok, Value}
    end;
validate_pattern(Field, Value, PatternRegex) when is_binary(PatternRegex) ->
    case re:run(Value, PatternRegex) of
        {match, _} -> {ok, Value};
        nomatch -> {error, <<Field/binary, ": does not match pattern">>}
    end.

%% @doc Validate data against a schema.
-spec validate_schema(schema(), map()) -> schema_validation_result().
validate_schema(Schema, Data) ->
    Required = maps:get(required, Schema, []),
    Optional = maps:get(optional, Schema, []),
    Types = maps:get(types, Schema, #{}),
    Constraints = maps:get(constraints, Schema, #{}),

    %% Check required fields
    RequiredErrors = check_required_fields(Required, Data),

    %% Add default values for optional fields
    DataWithDefaults = add_defaults(Optional, Data),

    %% Validate types
    TypeErrors = validate_types(Types, DataWithDefaults),

    %% Validate constraints
    ConstraintErrors = validate_constraints(Constraints, DataWithDefaults),

    AllErrors = RequiredErrors ++ TypeErrors ++ ConstraintErrors,

    case AllErrors of
        [] -> {ok, DataWithDefaults};
        _ -> {error, AllErrors}
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% @doc Check if all required fields are present.
-spec check_required_fields([binary()], map()) -> [binary()].
check_required_fields(Required, Data) ->
    lists:filtermap(fun(Field) ->
        case maps:find(Field, Data) of
            {ok, _} -> false;
            error -> {true, <<Field/binary, ": is required">>}
        end
    end, Required).

%% @private
%% @doc Add default values for optional fields.
-spec add_defaults([{binary(), term()}], map()) -> map().
add_defaults(Optional, Data) ->
    lists:foldl(fun({Field, Default}, Acc) ->
        case maps:find(Field, Acc) of
            {ok, _} -> Acc;
            error when Default =/= undefined -> Acc#{Field => Default};
            error -> Acc
        end
    end, Data, Optional).

%% @private
%% @doc Validate field types.
-spec validate_types(#{binary() => atom() | tuple()}, map()) -> [binary()].
validate_types(Types, Data) ->
    maps:fold(fun(Field, TypeSpec, Errors) ->
        case maps:find(Field, Data) of
            {ok, Value} ->
                case validate_field_type(Field, Value, TypeSpec) of
                    {ok, _} -> Errors;
                    {error, Msg} -> [Msg | Errors]
                end;
            error ->
                Errors
        end
    end, [], Types).

%% @private
%% @doc Validate field constraints.
-spec validate_constraints(#{binary() => fun()}, map()) -> [binary()].
validate_constraints(Constraints, Data) ->
    maps:fold(fun(Field, ConstraintFun, Errors) ->
        case maps:find(Field, Data) of
            {ok, Value} ->
                try
                    case ConstraintFun(Value) of
                        true -> Errors;
                        false -> [<<Field/binary, ": constraint validation failed">> | Errors]
                    end
                catch
                    _:_ -> [<<Field/binary, ": constraint error">> | Errors]
                end;
            error ->
                Errors
        end
    end, [], Constraints).

%% @private
%% @doc Validate list elements against a type.
-spec validate_list_elements(binary(), list(), atom()) -> {ok, list()} | {error, binary()}.
validate_list_elements(Field, List, ElementType) ->
    validate_list_elements(Field, List, ElementType, 1, []).

validate_list_elements(_Field, [], _ElementType, _Index, Acc) ->
    {ok, lists:reverse(Acc)};
validate_list_elements(Field, [Head | Rest], ElementType, Index, Acc) ->
    ElementField = <<Field/binary, "[", (integer_to_binary(Index))/binary, "]">>,
    case validate_field_type(ElementField, Head, ElementType) of
        {ok, Converted} ->
            validate_list_elements(Field, Rest, ElementType, Index + 1, [Converted | Acc]);
        {error, _} = Error ->
            Error
    end.

%% @private
%% @doc Convert a value to binary.
-spec convert_to_binary(term()) -> binary().
convert_to_binary(Value) when is_binary(Value) -> Value;
convert_to_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
convert_to_binary(Value) when is_integer(Value) -> integer_to_binary(Value);
convert_to_binary(Value) when is_list(Value) -> list_to_binary(Value);
convert_to_binary(Value) -> iolist_to_binary(io_lib:format("~p", [Value])).

%% @private
%% @doc Validate UUID format.
-spec validate_uuid(binary()) -> {ok, binary()} | {error, binary()}.
validate_uuid(Value) ->
    Pattern = <<"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$">>,
    case re:run(Value, Pattern) of
        {match, _} -> {ok, Value};
        nomatch -> {error, <<"Invalid UUID format">>}
    end.

%% @private
%% @doc Validate email format.
-spec validate_email(binary()) -> {ok, binary()} | {error, binary()}.
validate_email(Value) ->
    Pattern = <<"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$">>,
    case re:run(Value, Pattern) of
        {match, _} -> {ok, Value};
        nomatch -> {error, <<"Invalid email format">>}
    end.

%% @private
%% @doc Validate URL format.
-spec validate_url(binary()) -> {ok, binary()} | {error, binary()}.
validate_url(Value) ->
    is_valid_url(Value).

%% @private
%% @doc Check if value is a valid URL.
-spec is_valid_url(binary()) -> boolean().
is_valid_url(<<>>) ->
    false;
is_valid_url(Value) ->
    case uri_string:parse(Value) of
        #{scheme := Scheme, host := Host} when Scheme =/= undefined, Host =/= undefined ->
            case lists:member(Scheme, [<<"http">>, <<"https">>]) of
                true -> true;
                false -> false
            end;
        _ ->
            false
    end.

%% @private
%% @doc Validate timestamp format (ISO 8601).
-spec validate_timestamp(binary()) -> {ok, binary()} | {error, binary()}.
validate_timestamp(Value) ->
    Pattern = <<"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?$">>,
    case re:run(Value, Pattern) of
        {match, _} -> {ok, Value};
        nomatch -> {error, <<"Invalid timestamp format (expected ISO 8601)">>}
    end.
