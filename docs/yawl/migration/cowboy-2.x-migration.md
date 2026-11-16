# Cowboy 2.x Migration Guide

This guide helps migrate from Cowboy 1.x to Cowboy 2.x for the YAWL REST API.

## Overview

Cowboy 2.x introduced several breaking changes from 1.x. This guide covers the key changes needed for YAWL's REST API implementation.

## Key Changes

### 1. Handler Return Values

**Cowboy 1.x:**
```erlang
init(_Type, Req, _State) ->
    {ok, Req, no_state}.

handle(Req, State) ->
    {ok, Req2} = cowboy_req:reply(200, [], <<"Hello">>, Req),
    {ok, Req2, State}.
```

**Cowboy 2.x:**
```erlang
init(Req0, State) ->
    {cowboy_rest, Req0, State}.

to_json(Req0, State) ->
    Body = jsx:encode(#{message => <<"Hello">>}),
    {Body, Req0, State}.
```

### 2. Request Methods

**Cowboy 1.x:**
```erlang
{Method, Req} = cowboy_req:method(Req),
{Path, Req2} = cowboy_req:path(Req),
{Body, Req3} = cowboy_req:body(Req2),
```

**Cowboy 2.x:**
```erlang
Method = cowboy_req:method(Req),
Path = cowboy_req:path(Req),
{ok, Body, Req2} = cowboy_req:read_body(Req),
```

### 3. Response Methods

**Cowboy 1.x:**
```erlang
{ok, Req2} = cowboy_req:reply(200, [
    {<<"content-type">>, <<"application/json">>}
], Body, Req).
```

**Cowboy 2.x:**
```erlang
Req2 = cowboy_req:reply(200, #{
    <<"content-type">> => <<"application/json">>
}, Body, Req).
```

## YAWL REST API Migration

### Handler Module Structure

Updated handler structure for Cowboy 2.x:

```erlang
-module(yawl_rest_workflow_handler).
-behavior(cowboy_handler).

-export([init/2]).

%% State record
-record(state, {
    method :: cowboy_http:method(),
    workflow_id :: binary() | undefined,
    req :: cowboy_req:req()
}).

%% Initialize handler
init(Req0, Opts) ->
    Method = cowboy_req:method(Req0),
    WorkflowId = cowboy_req:binding(workflow_id, Req0),

    State = #state{
        method = Method,
        workflow_id = WorkflowId,
        req = Req0
    },

    handle_request(Method, Req0, State).

%% Handle GET requests
handle_request(<<"GET">>, Req0, State) ->
    case State#state.workflow_id of
        undefined ->
            list_workflows(Req0, State);
        Id ->
            get_workflow(Id, Req0, State)
    end;

%% Handle POST requests
handle_request(<<"POST">>, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Data = jsx:decode(Body, [return_maps]),

    case maps:get(<<"action">>, Data, undefined) of
        <<"execute">> -> execute_workflow(Req1, State);
        <<"pause">> -> pause_workflow(Req1, State);
        <<"resume">> -> resume_workflow(Req1, State);
        _ ->
            respond_error(400, <<"invalid_action">>, Req1)
    end;

%% Handle DELETE requests
handle_request(<<"DELETE">>, Req0, State) ->
    cancel_workflow(Req0, State);

%% Unsupported methods
handle_request(_, Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = cowboy_req:reply(405, #{
        <<"allow">> => <<"GET, POST, DELETE">>
    }, Req0),
    {ok, Req1, State}.
```

### Response Helper Functions

```erlang
%% Send JSON success response
respond_json(Data, Req) ->
    Body = jsx:encode(Data),
    cowboy_req:reply(200, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req).

%% Send error response
respond_error(Code, Message, Req) ->
    Body = jsx:encode(#{
        error_code => Code,
        message => Message
    }),
    cowboy_req:reply(400, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req).
```

## Router Configuration

### Dispatch Rules

**Cowboy 1.x:**
```erlang
Dispatch = cowboy_router:compile([
    {'_', [
        {"/", toppage_handler, []},
        {"/api/workflows", workflow_handler, []},
        {"/api/workflows/:id", workflow_handler, []},
        {"/api/workflows/:id/execute", workflow_handler, []}
    ]}
]),
{ok, _} = cowboy:start_http(http, 100, [
    {port, 8080}
], [{env, [{dispatch, Dispatch}]}]).
```

**Cowboy 2.x:**
```erlang
Dispatch = cowboy_router:compile([
    {'_', [
        {"/", toppage_handler, []},
        {"/api/workflows", yawl_rest_workflow_handler, []},
        {"/api/workflows/:workflow_id", yawl_rest_workflow_handler, []},
        {"/api/workflows/:workflow_id/execute", yawl_rest_workflow_handler, []},
        {"/api/workflows/:workflow_id/tasks", yawl_rest_task_handler, []},
        {"/api/workflows/:workflow_id/tasks/:task_id", yawl_rest_task_handler, []},
        {"/api/patterns", yawl_rest_pattern_handler, []},
        {"/api/resources", yawl_rest_resource_handler, []}
    ]}
]),
{ok, _} = cowboy:start_clear(yawl_http_listener, [
    {port, 8081}
], #{env => #{dispatch => Dispatch}}).
```

## Streamed Responses

### Streaming Events

For event streaming with Server-Sent Events:

```erlang
-module(yawl_rest_event_handler).
-behavior(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    Req = cowboy_req:stream_reply(200, #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>
    }, Req0),

    %% Subscribe to workflow events
    WorkflowId = cowboy_req:binding(workflow_id, Req0),
    ok = yawl_event_bus:subscribe(WorkflowId),

    %% Stream events
    stream_loop(WorkflowId, Req),

    {ok, Req, State}.

stream_loop(WorkflowId, Req) ->
    receive
        {workflow_event, Event} ->
            Data = jsx:encode(Event),
            cowboy_req:stream(<<"data: ", Data/binary, "\n\n">>, Req),
            stream_loop(WorkflowId, Req);
        {stop_streaming} ->
            cowboy_req:stream(<<>>, Req);
        _ ->
            stream_loop(WorkflowId, Req)
    after 30000 ->
        cowboy_req:stream(<<>>, Req)
    end.
```

## Common Issues

### Issue 1: Request Not Available in Return Value

**Problem:** In Cowboy 1.x, you returned the updated request. In 2.x, it's handled differently.

**Solution:** Use `cowboy_req:reply/2,3,4` and return the final request.

```erlang
%% Cowboy 2.x
Req2 = cowboy_req:reply(200, #{}, <<"Body">>, Req),
{ok, Req2, State}.
```

### Issue 2: Binding Names Changed

**Problem:** Binding syntax changed from `:id` to `:resource_id`.

**Solution:** Update your route patterns and binding names consistently.

```erlang
%% Route
{"/api/workflows/:workflow_id", handler, []}

%% Handler
WorkflowId = cowboy_req:binding(workflow_id, Req).
```

### Issue 3: Body Reading

**Problem:** `cowboy_req:body/1` no longer exists.

**Solution:** Use `cowboy_req:read_body/1,2` instead.

```erlang
{ok, Body, Req2} = cowboy_req:read_body(Req1),
```

## Testing Migrated Handlers

### Test Module Structure

```erlang
-module(yawl_rest_handler_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test workflow creation
create_workflow_test() ->
    %% Start test server
    {ok, _} = cowboy:start_clear(test_listener, [
        {port, 18081}
    ], #{env => #{dispatch => test_dispatch()}}),

    %% Make request
    {ok, {{_, 200, _}, _, Body}} = httpc:request(
        post,
        {"http://localhost:18081/api/workflows",
         [{"content-type", "application/json"}],
         "application/json",
         jsx:encode(#{
             pattern => sequential,
             name => <<"test">>
         })
        },
        [],
        []
    ),

    Response = jsx:decode(Body, [return_maps]),
    ?assertMatch(#{<<"workflow_id">> := <<"seq_", _/binary>>}, Response),

    %% Cleanup
    ok = cowboy:stop_listener(test_listener).

test_dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/api/workflows", yawl_rest_workflow_handler, []}
        ]}
    ]).
```

## Checklist

- [ ] Update all handler modules to use `init/2` callback
- [ ] Replace `cowboy_req:method/1` with direct access
- [ ] Replace `cowboy_req:body/1` with `cowboy_req:read_body/1`
- [ ] Update response methods to use maps for headers
- [ ] Update router configuration for Cowboy 2.x
- [ ] Update stream handlers for event streaming
- [ ] Update all tests for new API
- [ ] Verify all REST endpoints work correctly

---

Next: [HotCI Adoption](hotci-adoption.md) | [Back to Migration](../migration/)
