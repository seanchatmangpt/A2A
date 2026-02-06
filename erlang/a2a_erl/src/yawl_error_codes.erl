%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Code Registry
%%%
%%% This module defines all error codes used throughout the YAWL REST API.
%%% It provides a centralized registry for error information including
%%% error codes, HTTP status mappings, error categories, and messages.
%%%
%%% ## Error Categories
%%%
%%% - `validation` - Request validation errors (400)
%%% - `authentication` - Authentication failures (401)
%%% - `authorization` - Authorization/permission failures (403)
%%% - `not_found` - Resource not found errors (404)
%%% - `conflict` - Resource conflict errors (409)
%%% - `rate_limit` - Rate limiting errors (429)
%%% - `server_error` - Internal server errors (500)
%%% - `service_unavailable` - Service unavailable errors (503)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_codes).
-author("A2A Team").

%% API exports
-export([
    error_info/1,
    error_code/1,
    http_status/1,
    error_message/1,
    error_category/1,
    format_error/1,
    format_error/2,
    format_error/3,
    all_error_codes/0,
    errors_by_category/1,
    is_client_error/1,
    is_server_error/1
]).

%% Type definitions
-type error_code() :: atom().
-type error_category() :: validation | authentication | authorization | not_found |
                         conflict | rate_limit | server_error | service_unavailable.
-type error_info() :: #{
    code := error_code(),
    category := error_category(),
    http_status := pos_integer(),
    message := binary(),
    description := binary()
}.

%%====================================================================
%% Error Code Registry
%%====================================================================

%% @doc Get error information for a given error code.
-spec error_info(error_code()) -> error_info().
error_info(validation_failed) ->
    #{
        code => validation_failed,
        category => validation,
        http_status => 400,
        message => <<"Request validation failed">>,
        description => <<"The request could not be validated due to invalid data or missing fields">>
    };
error_info(missing_required_field) ->
    #{
        code => missing_required_field,
        category => validation,
        http_status => 400,
        message => <<"Missing required field">>,
        description => <<"A required field is missing from the request">>
    };
error_info(invalid_json) ->
    #{
        code => invalid_json,
        category => validation,
        http_status => 400,
        message => <<"Invalid JSON format">>,
        description => <<"The request body contains malformed JSON">>
    };
error_info(invalid_field_type) ->
    #{
        code => invalid_field_type,
        category => validation,
        http_status => 400,
        message => <<"Invalid field type">>,
        description => <<"A field has an invalid type">>
    };
error_info(invalid_field_value) ->
    #{
        code => invalid_field_value,
        category => validation,
        http_status => 400,
        message => <<"Invalid field value">>,
        description => <<"A field has an invalid value">>
    };
error_info(invalid_pattern_type) ->
    #{
        code => invalid_pattern_type,
        category => validation,
        http_status => 400,
        message => <<"Invalid workflow pattern type">>,
        description => <<"The specified workflow pattern type is not valid">>
    };
error_info(invalid_resource_type) ->
    #{
        code => invalid_resource_type,
        category => validation,
        http_status => 400,
        message => <<"Invalid resource type">>,
        description => <<"The specified resource type is not valid">>
    };
error_info(invalid_status) ->
    #{
        code => invalid_status,
        category => validation,
        http_status => 400,
        message => <<"Invalid status value">>,
        description => <<"The specified status value is not valid">>
    };
error_info(invalid_priority) ->
    #{
        code => invalid_priority,
        category => validation,
        http_status => 400,
        message => <<"Invalid priority value">>,
        description => <<"The specified priority value is not valid">>
    };
error_info(invalid_date_format) ->
    #{
        code => invalid_date_format,
        category => validation,
        http_status => 400,
        message => <<"Invalid date format">>,
        description => <<"The date format is not valid (expected ISO 8601)">>
    };
error_info(request_too_large) ->
    #{
        code => request_too_large,
        category => validation,
        http_status => 413,
        message => <<"Request too large">>,
        description => <<"The request body exceeds the maximum allowed size">>
    };
error_info(unsupported_media_type) ->
    #{
        code => unsupported_media_type,
        category => validation,
        http_status => 415,
        message => <<"Unsupported media type">>,
        description => <<"The request content type is not supported">>
    };
error_info(unprocessable_entity) ->
    #{
        code => unprocessable_entity,
        category => validation,
        http_status => 422,
        message => <<"Unprocessable entity">>,
        description => <<"The request was well-formed but unable to be followed due to semantic errors">>
    };
error_info(authentication_failed) ->
    #{
        code => authentication_failed,
        category => authentication,
        http_status => 401,
        message => <<"Authentication failed">>,
        description => <<"Authentication is required to access this resource">>
    };
error_info(invalid_token) ->
    #{
        code => invalid_token,
        category => authentication,
        http_status => 401,
        message => <<"Invalid authentication token">>,
        description => <<"The provided authentication token is invalid">>
    };
error_info(token_expired) ->
    #{
        code => token_expired,
        category => authentication,
        http_status => 401,
        message => <<"Token expired">>,
        description => <<"The authentication token has expired">>
    };
error_info(missing_token) ->
    #{
        code => missing_token,
        category => authentication,
        http_status => 401,
        message => <<"Missing authentication token">>,
        description => <<"An authentication token is required">>
    };
error_info(insufficient_permissions) ->
    #{
        code => insufficient_permissions,
        category => authorization,
        http_status => 403,
        message => <<"Insufficient permissions">>,
        description => <<"You do not have permission to perform this action">>
    };
error_info(access_denied) ->
    #{
        code => access_denied,
        category => authorization,
        http_status => 403,
        message => <<"Access denied">>,
        description => <<"Access to this resource is denied">>
    };
error_info(workflow_not_found) ->
    #{
        code => workflow_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Workflow not found">>,
        description => <<"The specified workflow does not exist">>
    };
error_info(resource_not_found) ->
    #{
        code => resource_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Resource not found">>,
        description => <<"The specified resource does not exist">>
    };
error_info(task_not_found) ->
    #{
        code => task_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Task not found">>,
        description => <<"The specified task does not exist">>
    };
error_info(workitem_not_found) ->
    #{
        code => workitem_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Workitem not found">>,
        description => <<"The specified workitem does not exist">>
    };
error_info(service_not_found) ->
    #{
        code => service_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Service not found">>,
        description => <<"The specified service does not exist">>
    };
error_info(endpoint_not_found) ->
    #{
        code => endpoint_not_found,
        category => not_found,
        http_status => 404,
        message => <<"Endpoint not found">>,
        description => <<"The requested endpoint does not exist">>
    };
error_info(workflow_already_exists) ->
    #{
        code => workflow_already_exists,
        category => conflict,
        http_status => 409,
        message => <<"Workflow already exists">>,
        description => <<"A workflow with this identifier already exists">>
    };
error_info(resource_already_exists) ->
    #{
        code => resource_already_exists,
        category => conflict,
        http_status => 409,
        message => <<"Resource already exists">>,
        description => <<"A resource with this identifier already exists">>
    };
error_info(workflow_conflict) ->
    #{
        code => workflow_conflict,
        category => conflict,
        http_status => 409,
        message => <<"Workflow conflict">>,
        description => <<"The workflow is in a state that conflicts with this request">>
    };
error_info(resource_conflict) ->
    #{
        code => resource_conflict,
        category => conflict,
        http_status => 409,
        message => <<"Resource conflict">>,
        description => <<"The resource is in a state that conflicts with this request">>
    };
error_info(rate_limit_exceeded) ->
    #{
        code => rate_limit_exceeded,
        category => rate_limit,
        http_status => 429,
        message => <<"Rate limit exceeded">>,
        description => <<"Too many requests have been made">>
    };
error_info(internal_server_error) ->
    #{
        code => internal_server_error,
        category => server_error,
        http_status => 500,
        message => <<"Internal server error">>,
        description => <<"An unexpected error occurred on the server">>
    };
error_info(database_error) ->
    #{
        code => database_error,
        category => server_error,
        http_status => 500,
        message => <<"Database error">>,
        description => <<"An error occurred while accessing the database">>
    };
error_info(persistence_error) ->
    #{
        code => persistence_error,
        category => server_error,
        http_status => 500,
        message => <<"Persistence error">>,
        description => <<"An error occurred while persisting data">>
    };
error_info(orchestration_error) ->
    #{
        code => orchestration_error,
        category => server_error,
        http_status => 500,
        message => <<"Orchestration error">>,
        description => <<"An error occurred during workflow orchestration">>
    };
error_info(allocation_error) ->
    #{
        code => allocation_error,
        category => server_error,
        http_status => 500,
        message => <<"Resource allocation error">>,
        description => <<"An error occurred while allocating resources">>
    };
error_info(service_unavailable) ->
    #{
        code => service_unavailable,
        category => service_unavailable,
        http_status => 503,
        message => <<"Service unavailable">>,
        description => <<"The service is temporarily unavailable">>
    };
error_info(workflow_engine_unavailable) ->
    #{
        code => workflow_engine_unavailable,
        category => service_unavailable,
        http_status => 503,
        message => <<"Workflow engine unavailable">>,
        description => <<"The workflow engine is temporarily unavailable">>
    };
error_info(timeout) ->
    #{
        code => timeout,
        category => server_error,
        http_status => 504,
        message => <<"Request timeout">>,
        description => <<"The request timed out">>
    };
error_info(ErrorCode) when is_atom(ErrorCode) ->
    #{
        code => unknown_error,
        category => server_error,
        http_status => 500,
        message => <<"Unknown error">>,
        description => <<"An unknown error occurred">>
    }.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Get the error code atom.
-spec error_code(error_code()) -> error_code().
error_code(ErrorCode) ->
    Info = error_info(ErrorCode),
    maps:get(code, Info).

%% @doc Get the HTTP status code for an error.
-spec http_status(error_code()) -> pos_integer().
http_status(ErrorCode) ->
    Info = error_info(ErrorCode),
    maps:get(http_status, Info).

%% @doc Get the error message.
-spec error_message(error_code()) -> binary().
error_message(ErrorCode) ->
    Info = error_info(ErrorCode),
    maps:get(message, Info).

%% @doc Get the error category.
-spec error_category(error_code()) -> error_category().
error_category(ErrorCode) ->
    Info = error_info(ErrorCode),
    maps:get(category, Info).

%% @doc Format an error as a map suitable for JSON encoding.
-spec format_error(error_code()) -> map().
format_error(ErrorCode) ->
    format_error(ErrorCode, #{}).

%% @doc Format an error with additional details.
-spec format_error(error_code(), map()) -> map().
format_error(ErrorCode, Details) ->
    Info = error_info(ErrorCode),
    #{
        error_code => atom_to_binary(maps:get(code, Info), utf8),
        error_category => atom_to_binary(maps:get(category, Info), utf8),
        message => maps:get(message, Info),
        http_status => maps:get(http_status, Info)
    } ++ Details.

%% @doc Format an error with a custom message and details.
-spec format_error(error_code(), binary(), map()) -> map().
format_error(ErrorCode, CustomMessage, Details) ->
    Base = format_error(ErrorCode, Details),
    Base#{message => CustomMessage}.

%% @doc Get all defined error codes.
-spec all_error_codes() -> [error_code()].
all_error_codes() ->
    [
        validation_failed,
        missing_required_field,
        invalid_json,
        invalid_field_type,
        invalid_field_value,
        invalid_pattern_type,
        invalid_resource_type,
        invalid_status,
        invalid_priority,
        invalid_date_format,
        request_too_large,
        unsupported_media_type,
        unprocessable_entity,
        authentication_failed,
        invalid_token,
        token_expired,
        missing_token,
        insufficient_permissions,
        access_denied,
        workflow_not_found,
        resource_not_found,
        task_not_found,
        workitem_not_found,
        service_not_found,
        endpoint_not_found,
        workflow_already_exists,
        resource_already_exists,
        workflow_conflict,
        resource_conflict,
        rate_limit_exceeded,
        internal_server_error,
        database_error,
        persistence_error,
        orchestration_error,
        allocation_error,
        service_unavailable,
        workflow_engine_unavailable,
        timeout
    ].

%% @doc Get all error codes for a specific category.
-spec errors_by_category(error_category()) -> [error_code()].
errors_by_category(validation) ->
    [
        validation_failed,
        missing_required_field,
        invalid_json,
        invalid_field_type,
        invalid_field_value,
        invalid_pattern_type,
        invalid_resource_type,
        invalid_status,
        invalid_priority,
        invalid_date_format,
        request_too_large,
        unsupported_media_type,
        unprocessable_entity
    ];
errors_by_category(authentication) ->
    [
        authentication_failed,
        invalid_token,
        token_expired,
        missing_token
    ];
errors_by_category(authorization) ->
    [
        insufficient_permissions,
        access_denied
    ];
errors_by_category(not_found) ->
    [
        workflow_not_found,
        resource_not_found,
        task_not_found,
        workitem_not_found,
        service_not_found,
        endpoint_not_found
    ];
errors_by_category(conflict) ->
    [
        workflow_already_exists,
        resource_already_exists,
        workflow_conflict,
        resource_conflict
    ];
errors_by_category(rate_limit) ->
    [
        rate_limit_exceeded
    ];
errors_by_category(server_error) ->
    [
        internal_server_error,
        database_error,
        persistence_error,
        orchestration_error,
        allocation_error,
        timeout
    ];
errors_by_category(service_unavailable) ->
    [
        service_unavailable,
        workflow_engine_unavailable
    ].

%% @doc Check if an error is a client error (4xx).
-spec is_client_error(error_code()) -> boolean().
is_client_error(ErrorCode) ->
    Status = http_status(ErrorCode),
    Status >= 400 andalso Status < 500.

%% @doc Check if an error is a server error (5xx).
-spec is_server_error(error_code()) -> boolean().
is_server_error(ErrorCode) ->
    Status = http_status(ErrorCode),
    Status >= 500.
