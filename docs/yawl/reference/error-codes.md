# YAWL Error Codes Reference

## Overview

The YAWL system provides a comprehensive error handling framework with standardized error codes and detailed error information. This reference documents all error codes, their categories, HTTP status mappings, and provides guidance for error handling and recovery.

## Error Categories

YAWL errors are organized into the following categories:

### 1. Validation Errors (400 Bad Request)
Errors related to request validation, data validation, and parameter validation.

### 2. Authentication Errors (401 Unauthorized)
Errors related to authentication, authorization, and security.

### 3. Not Found Errors (404 Not Found)
Errors related to missing resources, workflows, or data.

### 4. Conflict Errors (409 Conflict)
Errors related to resource conflicts, state conflicts, and operation conflicts.

### 5. Rate Limit Errors (429 Too Many Requests)
Errors related to rate limiting and request throttling.

### 6. Server Errors (500 Internal Server Error)
Errors related to internal server problems, database errors, and system failures.

### 7. Service Unavailable (503 Service Unavailable)
Errors related to service availability and resource constraints.

## Error Code Reference

### Validation Errors

#### `validation_failed`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Request validation failed"
- **Description**: The request could not be validated due to invalid data or missing fields

**Common Causes:**
- Invalid JSON format
- Missing required parameters
- Invalid parameter types
- Business rule violations

**Example Usage:**
```erlang
case yawl_orchestrator:create_workflow(invalid_pattern, #{}) of
    {error, validation_failed} ->
        %% Handle validation failure
        handle_validation_error();
    ok ->
        %% Proceed with workflow
        ok
end.
```

#### `missing_required_field`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Missing required field"
- **Description**: A required field is missing from the request

**Common Causes:**
- Missing `pattern_type` in workflow creation
- Missing `workflow_id` in status queries
- Missing required parameters for specific patterns

**Example:**
```erlang
case yawl_orchestrator:create_workflow(undefined, #{}) of
    {error, missing_required_field} ->
        %% Pattern type is required
        specify_pattern_type();
    _ -> ok
end.
```

#### `invalid_json`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid JSON format"
- **Description**: The request body contains malformed JSON

**Common Causes:**
- Malformed JSON syntax
- Invalid character encoding
- JSON parsing errors

**Handling:**
```erlang
case parse_json_request(RequestBody) of
    {error, invalid_json} ->
        return_400_error(invalid_json, "Invalid JSON format");
    {ok, Data} ->
        proceed_with_data(Data)
end.
```

#### `invalid_field_type`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid field type"
- **Description**: A field has an invalid type

**Common Causes:**
- String provided where integer is expected
- Boolean provided where string is expected
- Invalid enum value
- Type conversion errors

**Validation Function:**
```erlang
validate_field_type(Field, ExpectedType) ->
    case erlang:is_type(Field, ExpectedType) of
        true -> ok;
        false -> {error, {invalid_field_type, Field, ExpectedType}}
    end.
```

#### `invalid_field_value`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid field value"
- **Description**: A field has an invalid value

**Common Causes:**
- Value out of range
- Value not in allowed set
- Business rule violation
- Format invalid

**Example:**
```erlang
%% Validate timeout value
case Timeout of
    T when T > 0, T =< 300000 -> ok;
    _ -> {error, {invalid_field_value, "timeout", "must be between 1 and 300000"}}
end.
```

#### `invalid_pattern_type`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid workflow pattern type"
- **Description**: The specified workflow pattern type is not valid

**Valid Patterns:**
- `basic_sequential`
- `parallel_split`
- `parallel_join`
- `exclusive_choice`
- `simple_merge`
- And all other supported YAWL patterns

**Validation:**
```erlang
is_valid_pattern_type(PatternType) ->
    lists:member(PatternType, ?YAWL_PATTERNS).
```

#### `invalid_resource_type`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid resource type"
- **Description**: The specified resource type is not valid

**Valid Resource Types:**
- `cpu`
- `memory`
- `io`
- `network`
- `custom`

#### `invalid_status`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid status value"
- **Description**: The specified status value is not valid

**Valid Status Values:**
- `pending`
- `running`
- `paused`
- `completed`
- `cancelled`
- `failed`

#### `invalid_priority`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid priority value"
- **Description**: The specified priority value is not valid

**Valid Priority Values:**
- `low`
- `normal`
- `high`
- `urgent`

#### `invalid_date_format`
- **HTTP Status**: 400
- **Category**: validation
- **Message**: "Invalid date format"
- **Description**: The date format is not valid (expected ISO 8601)

**Expected Format:** `YYYY-MM-DDTHH:MM:SSZ`

#### `request_too_large`
- **HTTP Status**: 413
- **Category**: validation
- **Message**: "Request too large"
- **Description**: The request body exceeds the maximum allowed size

**Size Limits:**
- Default: 10MB
- Configurable via `max_request_size`

#### `unsupported_media_type`
- **HTTP Status**: 415
- **Category**: validation
- **Message**: "Unsupported media type"
- **Description**: The request content type is not supported

**Supported Types:**
- `application/json`
- `text/plain`

#### `unprocessable_entity`
- **HTTP Status**: 422
- **Category**: validation
- **Message**: "Unprocessable entity"
- **Description**: The request was well-formed but unable to be followed due to semantic errors

### Authentication Errors

#### `authentication_failed`
- **HTTP Status**: 401
- **Category**: authentication
- **Message**: "Authentication failed"
- **Description**: Authentication is required to access this resource

**Common Causes:**
- Invalid credentials
- Expired credentials
- Invalid token format
- Authentication service unavailable

**Handling:**
```erlang
case authenticate(Request) of
    {ok, User} -> handle_authenticated_request(User);
    {error, authentication_failed} -> return_401_error()
end.
```

#### `invalid_token`
- **HTTP Status**: 401
- **Category**: authentication
- **Message**: "Invalid authentication token"
- **Description**: The provided authentication token is invalid

**Common Causes:**
- Malformed token
- Token signature verification failed
- Token corrupted during transmission

#### `token_expired`
- **HTTP Status**: 401
- **Category**: authentication
- **Message**: "Token expired"
- **Description**: The authentication token has expired

**Handling:**
```erlang
case verify_token(Token) of
    {ok, User} -> ok;
    {error, token_expired} -> return_401_with_refresh_prompt();
    {error, invalid_token} -> return_401_error()
end.
```

#### `missing_token`
- **HTTP Status**: 401
- **Category**: authentication
- **Message**: "Missing authentication token"
- **Description**: An authentication token is required

**Common Causes:**
- No Authorization header
- Empty Authorization header
- Missing token in query parameter

### Authorization Errors

#### `insufficient_permissions`
- **HTTP Status**: 403
- **Category**: authorization
- **Message**: "Insufficient permissions"
- **Description**: You do not have permission to perform this action

**Common Causes:**
- User lacks required role
- User lacks required permission
- Resource access denied
- Operation not allowed for user

**Permission Checking:**
```erlang
check_permission(User, Operation, Resource) ->
    case has_permission(User, Operation, Resource) of
        true -> ok;
        false -> {error, insufficient_permissions}
    end.
```

#### `access_denied`
- **HTTP Status**: 403
- **Category**: authorization
- **Message**: "Access denied"
- **Description**: Access to this resource is denied

**Common Causes:**
- Resource access denied
- Operation not allowed
- Administrative restrictions

### Not Found Errors

#### `workflow_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Workflow not found"
- **Description**: The specified workflow does not exist

**Common Causes:**
- Invalid workflow ID
- Workflow was deleted
- Workflow not created yet

**Handling:**
```erlang
case yawl_orchestrator:get_status(WorkflowId) of
    {error, workflow_not_found} ->
        return_404_error("Workflow not found", WorkflowId);
    {ok, Status} ->
        return_status(Status)
end.
```

#### `resource_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Resource not found"
- **Description**: The specified resource does not exist

**Common Causes:**
- Invalid resource ID
- Resource not provisioned
- Resource deleted

#### `task_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Task not found"
- **Description**: The specified task does not exist

**Common Causes:**
- Invalid task ID
- Task completed and removed
- Task not yet created

#### `workitem_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Workitem not found"
- **Description**: The specified workitem does not exist

**Common Causes:**
- Invalid workitem ID
- Workitem completed and removed
- Workitem not yet created

#### `service_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Service not found"
- **Description**: The specified service does not exist

#### `endpoint_not_found`
- **HTTP Status**: 404
- **Category**: not_found
- **Message**: "Endpoint not found"
- **Description**: The requested endpoint does not exist

### Conflict Errors

#### `workflow_already_exists`
- **HTTP Status**: 409
- **Category**: conflict
- **Message**: "Workflow already exists"
- **Description**: A workflow with this identifier already exists

**Common Causes:**
- Duplicate workflow ID
- Workflow creation race condition
- Workflow not properly cleaned up

**Prevention:**
```erlang
case yawl_orchestrator:create_workflow(PatternType, Config) of
    {error, workflow_already_exists} ->
        %% Generate unique ID or handle existing workflow
        handle_duplicate_workflow();
    {ok, WorkflowId} ->
        proceed_with_workflow(WorkflowId)
end.
```

#### `resource_already_exists`
- **HTTP Status**: 409
- **Category**: conflict
- **Message**: "Resource already exists"
- **Description**: A resource with this identifier already exists

#### `workflow_conflict`
- **HTTP Status**: 409
- **Category**: conflict
- **Message**: "Workflow conflict"
- **Description**: The workflow is in a state that conflicts with this request

**Common Causes:**
- Cannot start completed workflow
- Cannot cancel completed workflow
- State transition conflicts

#### `resource_conflict`
- **HTTP Status**: 409
- **Category**: conflict
- **Message**: "Resource conflict"
- **Description**: The resource is in a state that conflicts with this request

### Rate Limit Errors

#### `rate_limit_exceeded`
- **HTTP Status**: 429
- **Category**: rate_limit
- **Message**: "Rate limit exceeded"
- **Description**: Too many requests have been made

**Common Causes:**
- Exceeded requests per minute
- Exceeded requests per hour
- Exceeded burst limits

**Handling:**
```erlang
case check_rate_limit(User, Endpoint) of
    {ok, Allowed} -> proceed_with_request();
    {error, rate_limit_exceeded} ->
        %% Return with retry-after header
        return_429_with_retry_after()
end.
```

### Server Errors

#### `internal_server_error`
- **HTTP Status**: 500
- **Category**: server_error
- **Message**: "Internal server error"
- **Description**: An unexpected error occurred on the server

**Common Causes:**
- Unhandled exceptions
- Runtime errors
- System failures

**Handling:**
```erlang
try
    %% Operation that might fail
    perform_operation()
catch
    Error:Reason ->
        %% Log the error
        log_error(Error, Reason),
        %% Return generic error to client
        {error, internal_server_error}
end.
```

#### `database_error`
- **HTTP Status**: 500
- **Category**: server_error
- **Message**: "Database error"
- **Description**: An error occurred while accessing the database

**Common Causes:**
- Database connection issues
- Database timeout
- Data integrity violations
- Database unavailable

**Recovery:**
```erlang
case yawl_persistence:save_workflow(Workflow) of
    {error, database_error} ->
        %% Retry with exponential backoff
        retry_operation_with_backoff();
    ok ->
        %% Success
        ok
end.
```

#### `persistence_error`
- **HTTP Status**: 500
- **Category**: server_error
- **Message**: "Persistence error"
- **Description**: An error occurred while persisting data

**Common Causes:**
- Disk full
- Permission denied
- Network issues
- Storage subsystem failure

#### `orchestration_error`
- **HTTP Status**: 500
- **Category**: server_error
- **Message**: "Orchestration error"
- **Description**: An error occurred during workflow orchestration

**Common Causes:**
- Workflow engine failure
- State corruption
- Deadlock detected
- Timeout occurred

#### `allocation_error`
- **HTTP Status**: 500
- **Category**: server_error
- **Message**: "Resource allocation error"
- **Description**: An error occurred while allocating resources

**Common Causes:**
- Resource exhaustion
- Invalid resource request
- Resource pool exhausted
- Resource deadlock

### Service Unavailable Errors

#### `service_unavailable`
- **HTTP Status**: 503
- **Category**: service_unavailable
- **Message**: "Service unavailable"
- **Description**: The service is temporarily unavailable

**Common Causes:**
- Service maintenance
- Resource exhaustion
- System overload
- Network issues

**Handling:**
```erlang
case yawl_orchestrator:create_workflow(PatternType, Config) of
    {error, service_unavailable} ->
        %% Implement retry logic
        implement_retry_logic();
    {ok, WorkflowId} ->
        proceed_with_workflow(WorkflowId)
end.
```

#### `workflow_engine_unavailable`
- **HTTP Status**: 503
- **Category**: service_unavailable
- **Message**: "Workflow engine unavailable"
- **Description**: The workflow engine is temporarily unavailable

**Common Causes:**
- Workflow service restart
- Configuration update
- Maintenance activities

#### `timeout`
- **HTTP Status**: 504
- **Category**: server_error
- **Message**: "Request timeout"
- **Description**: The request timed out

**Common Causes:**
- Operation took too long
- Network timeout
- Resource wait timeout

## Error Handling Patterns

### Error Response Format

All YAWL errors are returned in a consistent JSON format:

```json
{
    "error_code": "workflow_not_found",
    "error_category": "not_found",
    "message": "Workflow not found",
    "http_status": 404,
    "timestamp": "2024-01-15T10:30:00Z",
    "details": {
        "workflow_id": "invalid_workflow_id",
        "suggestion": "Check the workflow ID or create a new workflow"
    }
}
```

### Error Recovery Strategies

#### Retry with Exponential Backoff

```erlang
retry_with_backoff(Operation, MaxRetries, BaseDelay) ->
    retry_with_backoff(Operation, MaxRetries, BaseDelay, 1).

retry_with_backoff(Operation, MaxRetries, BaseDelay, Attempt) when Attempt =< MaxRetries ->
    case Operation() of
        {ok, Result} -> {ok, Result};
        {error, Reason} when Attempt < MaxRetries ->
            Delay = BaseDelay * (2 * (Attempt - 1)),
            timer:sleep(Delay),
            retry_with_backoff(Operation, MaxRetries, BaseDelay, Attempt + 1);
        {error, Reason} ->
            {error, Reason}
    end.
```

#### Circuit Breaker Pattern

```erlang
-record(circuit_breaker, {
    state :: closed | open | half_open,
    failure_count :: integer(),
    failure_threshold :: integer(),
    timeout :: integer()
}).

execute_with_circuit_breaker(Operation, CB) ->
    case CB#circuit_breaker.state of
        closed ->
            case Operation() of
                {ok, Result} ->
                    reset_circuit_breaker(CB),
                    {ok, Result};
                {error, Reason} ->
                    increment_failure_count(CB),
                    {error, Reason}
            end;
        open ->
            check_if_circuit_can_reset(CB);
        half_open ->
            case Operation() of
                {ok, Result} ->
                    close_circuit_breaker(CB),
                    {ok, Result};
                {error, Reason} ->
                    open_circuit_breaker(CB),
                    {error, Reason}
            end
    end.
```

#### Fallback Strategy

```erlang
execute_with_fallback(Operation, Fallback) ->
    try
        case Operation() of
            {ok, Result} -> {ok, Result};
            {error, _Reason} -> Fallback()
        end
    catch
        _:_ -> Fallback()
    end.
```

### Error Logging and Monitoring

#### Error Logging

```erlang
log_error(Error, Context) ->
    ErrorInfo = yawl_error_codes:error_info(Error),
    LogEntry = #{
        timestamp => erlang:system_time(millisecond),
        error_code => Error,
        error_category => maps:get(category, ErrorInfo),
        message => maps:get(message, ErrorInfo),
        context => Context,
        stacktrace => erlang:get_stacktrace(),
        node => node(),
        pid => self()
    },
    %% Log to error tracking system
    error_tracking:log_error(LogEntry).
```

#### Error Metrics

```erlang
track_error(Error, Category) ->
    ErrorMetrics = #{
        error_code => Error,
        error_category => Category,
        timestamp => erlang:system_time(millisecond),
        node => node()
    },
    metrics:increment(error_count, ErrorMetrics).
```

### Error Testing

#### Unit Testing Error Handling

```erlang
error_handling_test_() ->
    [
        { "workflow_not_found error",
          fun() ->
              case yawl_orchestrator:get_status(<<"invalid_id">>) of
                  {error, workflow_not_found} ->
                      ok;
                  _ ->
                      error(expected_workflow_not_found_error)
              end
          end
        },
        { "invalid_pattern_type validation",
          fun() ->
              case yawl_orchestrator:create_workflow(invalid_pattern, #{}) of
                  {error, invalid_pattern_type} ->
                      ok;
                  _ ->
                      error(expected_invalid_pattern_type_error)
              end
          end
        }
    ].
```

#### Integration Testing Error Scenarios

```erlang
integration_error_test() ->
    %% Test database connection failure
    application:set_env(a2a_erl, database_url, "invalid://connection"),

    %% Test error handling
    case yawl_persistence:save_workflow(test_workflow) of
        {error, database_error} ->
            %% Verify proper error handling
            verify_error_handling();
        ok ->
            error(should_have_failed_with_database_error)
    end.
```

## Best Practices

### Error Handling Guidelines

1. **Consistent Error Responses**
   - Use the standard error format
   - Include appropriate HTTP status codes
   - Provide clear error messages

2. **Error Recovery**
   - Implement retry logic for transient errors
   - Use circuit breakers for service dependencies
   - Provide fallback mechanisms

3. **Error Logging**
   - Log errors with appropriate level
   - Include context and stack traces
   - Monitor error rates and patterns

4. **Error Testing**
   - Unit test error handling paths
   - Integration test error scenarios
   - Performance test error recovery

5. **User Communication**
   - Provide user-friendly error messages
   - Include suggestions for resolution
   - Maintain appropriate error visibility

### Error Monitoring

#### Error Rate Monitoring

```erlang
monitor_error_rates() ->
    %% Track error rates by category
    ErrorRates = metrics:get_error_rates(),

    %% Set alerts for high error rates
    maps:foreach(fun(Category, Count) ->
        if Count > 100 ->
                send_alert(Category, Count);
           true -> ok
        end
    end, ErrorRates).
```

#### Error Pattern Analysis

```erlang
analyze_error_patterns() ->
    %% Get recent errors
    RecentErrors = error_tracking:get_recent_errors(3600000),  % 1 hour

    %% Analyze patterns
    Patterns = analyze_patterns(RecentErrors),

    %% Generate recommendations
    generate_recommendations(Patterns).
```

### Performance Considerations

1. **Error Overhead**
   - Minimize error logging overhead
   - Use asynchronous error logging
   - Cache error information

2. **Memory Management**
   - Limit error history size
   - Implement error log rotation
   - Clean up temporary error data

3. **Network Impact**
   - Compress error messages when needed
   - Batch error reporting
   - Optimize error transmission

4. **CPU Impact**
   - Use efficient error handling
   - Avoid excessive error processing
   - Implement throttling for error storms