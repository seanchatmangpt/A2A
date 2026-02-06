%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Response Formatter
%%%
%%% This module provides consistent error response formatting for the YAWL
%%% REST API. It ensures all error responses follow a standard structure
%%% with proper HTTP status codes, error codes, messages, and detailed
%%% information.
%%%
%%% ## Error Response Format
%%%
%%% All error responses follow this structure:
%%% ```
%%% {
%%%   "error": true,
%%%   "error_code": "validation_failed",
%%%   "error_category": "validation",
%%%   "message": "Request validation failed",
%%%   "details": {...},
%%%   "timestamp": "2024-01-01T00:00:00Z",
%%%   "request_id": "uuid"
%%% }
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_response).
-author("A2A Team").

%% API exports
-export([
    format_error/1,
    format_error/2,
    format_error/3,
    format_error/4,
    format_validation_error/2,
    format_validation_error/3,
    format_auth_error/2,
    format_auth_error/3,
    format_not_found_error/2,
    format_not_found_error/3,
    format_conflict_error/2,
    format_conflict_error/3,
    format_rate_limit_error/2,
    format_rate_limit_error/3,
    format_server_error/2,
    format_server_error/3,
    to_json/1,
    to_cowboy_response/3,
    to_cowboy_response/4,
    set_request_id/1,
    get_request_id/0
]).

%% Include files
-include("yawl_types.hrl").

%% Type definitions
-type error_code() :: yawl_error_codes:error_code().
-type error_response() :: map().
-type cowboy_request() :: term().
-type http_status() :: pos_integer().

%%====================================================================
%% Process Dictionary for Request ID
%%====================================================================

-define(REQUEST_ID_KEY, '$yawl_request_id').

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Format an error response using the error code registry.
-spec format_error(error_code()) -> error_response().
format_error(ErrorCode) ->
    format_error(ErrorCode, #{}).

%% @doc Format an error response with additional details.
-spec format_error(error_code(), map()) -> error_response().
format_error(ErrorCode, Details) ->
    format_error(ErrorCode, Details, undefined).

%% @doc Format an error response with details and a custom message.
-spec format_error(error_code(), map(), binary() | undefined) -> error_response().
format_error(ErrorCode, Details, CustomMessage) ->
    BaseInfo = yawl_error_codes:error_info(ErrorCode),
    BaseResponse = #{
        error => true,
        error_code => atom_to_binary(maps:get(code, BaseInfo), utf8),
        error_category => atom_to_binary(maps:get(category, BaseInfo), utf8),
        message => case CustomMessage of
            undefined -> maps:get(message, BaseInfo);
            _ -> CustomMessage
        end,
        http_status => maps:get(http_status, BaseInfo),
        timestamp => format_timestamp(),
        request_id => get_request_id()
    },
    case maps:size(Details) of
        0 -> BaseResponse;
        _ -> BaseResponse#{details => Details}
    end.

%% @doc Format an error response with full customization.
-spec format_error(error_code(), map(), binary() | undefined, http_status()) -> error_response().
format_error(ErrorCode, Details, CustomMessage, OverrideStatus) ->
    BaseResponse = format_error(ErrorCode, Details, CustomMessage),
    BaseResponse#{http_status => OverrideStatus}.

%% @doc Format a validation error with field-specific details.
-spec format_validation_error(binary() | [binary()], map() | [map()]) -> error_response().
format_validation_error(FieldOrFields, Errors) ->
    format_validation_error(FieldOrFields, Errors, undefined).

%% @doc Format a validation error with custom message.
-spec format_validation_error(binary() | [binary()], map() | [map()], binary() | undefined) -> error_response().
format_validation_error(FieldOrFields, Errors, CustomMessage) ->
    Details = case is_list(FieldOrFields) of
        true ->
            #{
                fields => FieldOrFields,
                errors => Errors
            };
        false ->
            #{
                field => FieldOrFields,
                errors => Errors
            }
    end,
    format_error(validation_failed, Details, CustomMessage).

%% @doc Format an authentication error.
-spec format_auth_error(error_code(), map()) -> error_response().
format_auth_error(ErrorCode, Details) ->
    format_auth_error(ErrorCode, Details, undefined).

%% @doc Format an authentication error with custom message.
-spec format_auth_error(error_code(), map(), binary() | undefined) -> error_response().
format_auth_error(ErrorCode, Details, CustomMessage) ->
    format_error(ErrorCode, Details, CustomMessage).

%% @doc Format a not found error.
-spec format_not_found_error(binary(), map()) -> error_response().
format_not_found_error(ResourceType, Details) ->
    format_not_found_error(ResourceType, Details, undefined).

%% @doc Format a not found error with custom message.
-spec format_not_found_error(binary(), map(), binary() | undefined) -> error_response().
format_not_found_error(ResourceType, Details, CustomMessage) ->
    DefaultMessage = <<ResourceType/binary, " not found">>,
    Message = case CustomMessage of
        undefined -> DefaultMessage;
        _ -> CustomMessage
    end,
    BaseDetails = Details#{resource_type => ResourceType},
    ErrorCode = case ResourceType of
        <<"workflow">> -> workflow_not_found;
        <<"resource">> -> resource_not_found;
        <<"task">> -> task_not_found;
        <<"workitem">> -> workitem_not_found;
        <<"service">> -> service_not_found;
        _ -> endpoint_not_found
    end,
    format_error(ErrorCode, BaseDetails, Message).

%% @doc Format a conflict error.
-spec format_conflict_error(binary(), map()) -> error_response().
format_conflict_error(ConflictType, Details) ->
    format_conflict_error(ConflictType, Details, undefined).

%% @doc Format a conflict error with custom message.
-spec format_conflict_error(binary(), map(), binary() | undefined) -> error_response().
format_conflict_error(ConflictType, Details, CustomMessage) ->
    DefaultMessage = <<ConflictType/binary, " conflict">>,
    Message = case CustomMessage of
        undefined -> DefaultMessage;
        _ -> CustomMessage
    end,
    BaseDetails = Details#{conflict_type => ConflictType},
    ErrorCode = case ConflictType of
        <<"workflow">> -> workflow_conflict;
        <<"resource">> -> resource_conflict;
        _ -> workflow_conflict
    end,
    format_error(ErrorCode, BaseDetails, Message).

%% @doc Format a rate limit error.
-spec format_rate_limit_error(pos_integer(), map()) -> error_response().
format_rate_limit_error(RetryAfter, Details) ->
    format_rate_limit_error(RetryAfter, Details, undefined).

%% @doc Format a rate limit error with custom message.
-spec format_rate_limit_error(pos_integer(), map(), binary() | undefined) -> error_response().
format_error_rate_limit_error(RetryAfter, Details, CustomMessage) ->
    DefaultDetails = Details#{retry_after => RetryAfter},
    format_error(rate_limit_exceeded, DefaultDetails, CustomMessage).

%% @doc Internal wrapper for rate limit error formatting
format_rate_limit_error(RetryAfter, Details, CustomMessage) ->
    BaseDetails = Details#{retry_after => RetryAfter},
    format_error(rate_limit_exceeded, BaseDetails, CustomMessage).

%% @doc Format a server error.
-spec format_server_error(error_code(), map()) -> error_response().
format_server_error(ErrorCode, Details) ->
    format_server_error(ErrorCode, Details, undefined).

%% @doc Format a server error with custom message.
-spec format_server_error(error_code(), map(), binary() | undefined) -> error_response().
format_server_error(ErrorCode, Details, CustomMessage) ->
    format_error(ErrorCode, Details, CustomMessage).

%% @doc Convert error response to JSON.
-spec to_json(error_response()) -> binary().
to_json(ErrorResponse) ->
    jiffy:encode(ErrorResponse).

%% @doc Create a Cowboy HTTP response from an error response.
-spec to_cowboy_response(cowboy_request(), error_code(), map()) -> cowboy_request().
to_cowboy_response(Req, ErrorCode, Details) ->
    to_cowboy_response(Req, ErrorCode, Details, undefined).

%% @doc Create a Cowboy HTTP response with custom message.
-spec to_cowboy_response(cowboy_request(), error_code(), map(), binary() | undefined) -> cowboy_request().
to_cowboy_response(Req, ErrorCode, Details, CustomMessage) ->
    ErrorResponse = format_error(ErrorCode, Details, CustomMessage),
    JsonBody = to_json(ErrorResponse),
    StatusCode = maps:get(http_status, ErrorResponse),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, JsonBody, Req).

%% @doc Set the request ID for the current request context.
-spec set_request_id(binary()) -> ok.
set_request_id(RequestId) ->
    put(?REQUEST_ID_KEY, RequestId),
    ok.

%% @doc Get the request ID for the current request context.
-spec get_request_id() -> binary().
get_request_id() ->
    case get(?REQUEST_ID_KEY) of
        undefined -> generate_request_id();
        RequestId when is_binary(RequestId) -> RequestId
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% @doc Format current timestamp as ISO 8601 string.
-spec format_timestamp() -> binary().
format_timestamp() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    FormatStr = "~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
    io_lib:format(FormatStr, [Year, Month, Day, Hour, Minute, Second]).

%% @private
%% @doc Generate a new request ID.
-spec generate_request_id() -> binary().
generate_request_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Time = erlang:monotonic_time(millisecond),
    NodeId = erlang:phash2(node()),
    <<UniqueId:32, Time:32, NodeId:32>>.
