# YAWL Erlang Introduction Tutorial

## Overview

This tutorial introduces the fundamental concepts of Erlang programming as they apply to YAWL (Yet Another Workflow Language) development. You'll learn the essential Erlang features needed to work effectively with the YAWL framework.

## Prerequisites

- Basic understanding of programming concepts
- No prior Erlang experience required (we'll cover the essentials)
- Text editor or IDE with Erlang support

## What is Erlang?

Erlang is a programming language designed for building massively scalable soft real-time systems with high availability. It's particularly well-suited for:

- Concurrency and distributed systems
- Fault-tolerant applications
- High-availability systems
- Real-time applications

### Key Features Relevant to YAWL

1. **Concurrency**: Erlang uses lightweight processes (not OS threads)
2. **Fault Tolerance**: "Let it crash" philosophy with supervisors
3. **Pattern Matching**: Core language feature for data manipulation
4. **Immutable Data**: All data is immutable by default
5. **Functional Programming**: No side effects, pure functions

## Erlang Basics for YAWL Development

### 1. Basic Syntax and Data Types

```erlang
%% Comments start with %%
%% Module declaration
-module(my_workflow).
-author("Your Name").
-export([start/0, process_data/1]).

%% Atoms (constants)
start() ->
    ok,
    error,
    workflow_started.

%% Integers and Floats
process_data(Number) when is_integer(Number) ->
    Number * 2;
process_data(Float) when is_float(Float) ->
    Float * 2.0.

%% Lists (ordered collections)
items = [item1, item2, item3]
numbers = [1, 2, 3, 4, 5]

%% Tuples (fixed-size collections)
point = {x, 100, y, 200}
status = {status, running, progress, 0.75}

%% Maps (key-value pairs)
workflow_data = #{
    id => <<"workflow-001">>,
    name => "Order Processing",
    status => running,
    created_at => 1640995200000
}
```

### 2. Pattern Matching

Pattern matching is a core feature of Erlang:

```erlang
%% Function clauses with pattern matching
handle_transition(start) ->
    io:format("Starting workflow~n"),
    {ok, workflow_started};
handle_transition(approve) ->
    io:format("Approving workflow~n"),
    {ok, workflow_approved};
handle_transition(reject) ->
    io:format("Rejecting workflow~n"),
    {error, workflow_rejected};
handle_transition(Other) ->
    io:format("Unknown transition: ~p~n", [Other]),
    {error, unknown_transition}.

%% Matching on maps
is_workflow_ready(#{status := ready}) -> true;
is_workflow_ready(#{status := running}) -> false;
is_workflow_ready(_) -> false.
```

### 3. Functions and Recursion

```erlang
%% Named functions
double(X) -> X * 2.

%% Function with guard
is_adult(Age) when Age >= 18 -> true;
is_adult(Age) when Age < 18 -> false.

%% Recursive function
sum_list([]) -> 0;
sum_list([Head | Tail]) -> Head + sum_list(Tail).

%% Anonymous functions (lambdas)
Apply = fun(F, X) -> F(X) end.
Result = Apply(fun(X) -> X * 2 end, 5),  % Result = 10
```

### 4. Concurrency with Processes

```erlang
%% Spawn a simple process
spawn(fun() -> io:format("I'm a process!~n") end).

%% Process with messages
Pid = spawn(fun() -> loop() end).

loop() ->
    receive
        {From, Msg} ->
            io:format("Received: ~p~n", [Msg]),
            From ! {self(), "Message received"},
            loop();
        stop ->
            io:format("Stopping process~n")
    end.

%% Send a message to the process
Pid ! {self(), "Hello process"}.

%% Receive a response
receive
    {Pid, Response} ->
        io:format("Response: ~p~n", [Response])
after
    5000 ->
        io:format("No response received~n")
end.
```

### 5. Error Handling

```erlang
%% Using try-catch
calculate(Value) ->
    try
        divide(Value, 2)
    catch
        error:badarith ->
            io:format("Cannot divide by zero~n"),
            {error, division_by_zero};
        Type:Reason ->
            io:format("Error ~p: ~p~n", [Type, Reason]),
            {error, Reason}
    end.

divide(X, Y) when Y =/= 0 -> X / Y;
divide(_, _) -> error(badarith).

%% Using pattern matching with throw/catch
validate_workflow(#{status := running} = Data) ->
    case maps:get(required_field, Data, undefined) of
        undefined ->
            throw({missing_field, required_field});
        Value when is_binary(Value) ->
            {ok, Data};
        _ ->
            throw({invalid_field_type, required_field})
    end.
```

## YAWL-Specific Erlang Concepts

### 1. gen_pnet Behaviour

YAWL workflows implement the `gen_pnet` behaviour, which requires specific callbacks:

```erlang
-include("gen_pnet.hrl").
-include("yawl_types.hrl").

%% Required callbacks
-export([
    place_lst/0,
    trsn_lst/0,
    init_marking/2,
    preset/1,
    postset/1,
    is_enabled/3,
    fire/3,
    trigger/3
]).

%% List all places (states) in the workflow
place_lst() ->
    [
        start,
        order_received,
        processing,
        completed,
        failed
    ].

%% List all transitions (actions) in the workflow
trsn_lst() ->
    [
        start_workflow,
        process_order,
        complete_workflow,
        handle_failure
    ].

%% Initial marking of tokens
init_marking(start, _UsrInfo) ->
    [workflow_token];  % Start with a token at the start place
init_marking(_Place, _UsrInfo) ->
    [].

%% Input places for a transition
preset(Transition) ->
    case Transition of
        start_workflow -> [start];
        process_order -> [order_received];
        complete_workflow -> [processing];
        handle_failure -> [failed]
    end.

%% Output places for a transition
postset(Transition) ->
    case Transition of
        start_workflow -> [order_received];
        process_order -> [processing];
        complete_workflow -> [completed];
        handle_failure -> [failed]
    end.
```

### 2. YAWL Token Handling

```erlang
%% Check if a place has tokens
is_enabled(process_order, Mode, _UsrInfo) ->
    has_token(order_received, Mode).

has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        [_|_] -> true
    end.

%% Fire a transition and produce tokens
fire(process_order, Mode, UsrInfo) ->
    OrderData = get_order_data(UsrInfo),
    {produce, #{
        processing => [{order, OrderData}]
    }}.

%% Handle token triggers
trigger(Place, Token, _UsrInfo) ->
    case Place of
        order_received ->
            case Token of
                {order, Data} -> pass;
                _ -> drop
            end;
        _ ->
            pass
    end.
```

### 3. Working with YAWL Data Types

```erlang
%% Workflow data structures
-type workflow_token() :: {workflow, binary()}.
-type order_token() :: {order, map()}.
-type state_token() :: {state, atom()}.

%% Create workflow data
create_order_data() ->
    #{
        id => generate_id(<<"order">>),
        items => [#{id => <<"item1">>, quantity => 10}],
        status => created,
        created_at => erlang:system_time(millisecond)
    }.

%% Helper function for generating IDs
generate_id(Prefix) ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.
```

## Practical Exercise: Simple Workflow

Let's create a simple workflow that processes orders:

```erlang
-module(simple_order_workflow).
-author("Your Name").
-export([place_lst/0, trsn_lst/0, init_marking/2, preset/1, postset/1, is_enabled/3, fire/3, trigger/3]).

-include("gen_pnet.hrl").

place_lst() ->
    [start, order_received, payment_pending, shipped, completed, failed].

trsn_lst() ->
    [receive_order, process_payment, ship_order, complete, handle_failure].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(receive_order) -> [start];
preset(process_payment) -> [order_received];
preset(ship_order) -> [payment_pending];
preset(complete) -> [shipped];
preset(handle_failure) -> [failed].

postset(receive_order) -> [order_received];
postset(process_payment) -> [payment_pending];
postset(ship_order) -> [shipped];
postset(complete) -> [completed];
postset(handle_failure) -> [failed].

is_enabled(receive_order, _Mode, _UsrInfo) -> true;
is_enabled(process_payment, Mode, _UsrInfo) -> has_token(order_received, Mode);
is_enabled(ship_order, Mode, _UsrInfo) -> has_token(payment_pending, Mode);
is_enabled(complete, Mode, _UsrInfo) -> has_token(shipped, Mode);
is_enabled(handle_failure, Mode, _UsrInfo) -> has_token(failed, Mode).

fire(receive_order, _Mode, UsrInfo) ->
    OrderData = create_order_data(UsrInfo),
    {produce, #{order_received => [{order, OrderData}]}};

fire(process_payment, Mode, UsrInfo) ->
    OrderData = get_order_from_mode(Mode),
    case process_payment(OrderData) of
        {ok, _} ->
            {produce, #{payment_pending => [payment_token]}};
        {error, _} ->
            {produce, #{failed => [failure_token]}}
    end;

fire(ship_order, _Mode, UsrInfo) ->
    {produce, #{shipped => [shipment_token]}};

fire(complete, _Mode, _UsrInfo) ->
    {produce, #{completed => [completion_token]}};

fire(handle_failure, _Mode, _UsrInfo) ->
    {produce, #{failed => [failure_token]}}.

trigger(_Place, _Token, _UsrInfo) -> pass.

%% Helper functions
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        _ -> true
    end.

create_order_data(UsrInfo) ->
    case maps:get(order_data, UsrInfo, undefined) of
        undefined ->
            #{
                id => generate_id(<<"order">>),
                items => [#{id => <<"default">>, quantity => 1}],
                amount => 100.0
            };
        Data ->
            Data
    end.

get_order_from_mode(Mode) ->
    case maps:get(order_received, Mode, []) of
        [{order, Data}] -> Data;
        _ -> #{}
    end.

process_payment(OrderData) ->
    Amount = maps:get(amount, OrderData, 0),
    case Amount > 1000 of
        true -> {error, amount_too_high};
        false -> {ok, processed}
    end.

generate_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.
```

## Next Steps

Now that you understand the basics of Erlang for YAWL development, you're ready to:

1. **Read the Setup Tutorial**: Learn how to set up your development environment
2. **Create Your First Workflow**: Follow the step-by-step first workflow tutorial
3. **Explore Patterns**: Dive deep into YAWL pattern usage
4. **Work with the REST API**: Learn how to interact with YAWL via HTTP

## Key Takeaways

1. Erlang is built for concurrency and fault tolerance
2. Pattern matching is fundamental to Erlang programming
3. All data in Erlang is immutable
4. YAWL workflows implement the `gen_pnet` behaviour
5. Token-based workflow execution is the core concept
6. Error handling is done through pattern matching and `try-catch`

## Common Patterns to Remember

```erlang
%% Process spawning and messaging
Pid = spawn(Module, Function, Args),
Pid ! Message,

%% Pattern matching on messages
receive
    {Pid, Data} -> handle_data(Data);
    Other -> ignore
after
    5000 -> timeout_handling()
end.

%% Map operations
update_map(Map, Key, Value) ->
    Map#{Key => Value}.

%% List processing
process_list(List) ->
    lists:map(fun(X) -> X * 2 end, List).
```

Remember: Erlang's syntax might seem unusual at first, but its consistency and power make it ideal for building robust workflow systems like YAWL!