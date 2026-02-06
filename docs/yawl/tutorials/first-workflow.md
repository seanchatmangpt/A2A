# Creating Your First YAWL Workflow

## Overview

This tutorial walks you through creating your first YAWL workflow from scratch. We'll build a simple order processing workflow step by step, explaining each concept along the way. By the end, you'll have a working workflow that can process orders through different states.

## Prerequisites

- Complete the [Erlang Introduction Tutorial](erlang-intro.md)
- Complete the [Environment Setup Tutorial](setup.md)
- Basic understanding of workflow concepts

## What We'll Build

A simple order processing workflow with the following flow:

```
start → receive_order → process_payment → ship_order → complete
                                      ↓
                                  handle_failure
```

## Step 1: Understanding the Workflow Structure

A YAWL workflow consists of:

- **Places**: Represent states or conditions
- **Transitions**: Represent actions or events
- **Tokens**: Move through the workflow based on transitions
- **Markings**: Show which places currently have tokens

Let's define our workflow components:

```erlang
% Places (states)
start        - Initial state before order is received
order_received - Order has been received and is waiting
payment_pending - Payment processing in progress
shipped      - Order has been shipped
completed    - Order successfully completed
failed       - Order failed at some point

% Transitions (actions)
receive_order  - Receive a new order
process_payment - Process payment for the order
ship_order     - Ship the order
complete       - Mark order as completed
handle_failure  - Handle failure scenarios
```

## Step 2: Create the Module File

Create a new file `my_first_workflow.erl`:

```erlang
%%%-------------------------------------------------------------------
%%% @doc
%%% My First YAWL Workflow - Simple Order Processing
%%%
%%% This is a basic workflow that demonstrates:
%%% - Places and transitions
%%% - Token movement
%%% - State management
%%% - Basic error handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(my_first_workflow).
-author("Your Name").

%% gen_pnet Behaviour Callbacks
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

%% API Functions for testing
-export([
    create_workflow/1,
    get_workflow_spec/0,
    simulate_order_processing/0,
    get_initial_marking/0
]).

%% Include required headers
-include("gen_pnet.hrl").
-include("yawl_types.hrl").
-include("yawl_xes.hrl").
```

## Step 3: Define Places and Transitions

Now let's define the places and transitions:

```erlang
%%====================================================================
%%% Places and Transitions
%%====================================================================

%% @doc Return the list of all places in the workflow
place_lst() ->
    [
        start,
        order_received,
        payment_pending,
        shipped,
        completed,
        failed
    ].

%% @doc Return the list of all transitions in the workflow
trsn_lst() ->
    [
        receive_order,
        process_payment,
        ship_order,
        complete,
        handle_failure
    ].
```

## Step 4: Define Initial Marking

The initial marking determines where tokens start:

```erlang
%% @doc Define initial token placement
init_marking(start, _UsrInfo) ->
    [workflow_token];  % Start with one token at 'start'
init_marking(_Place, _UsrInfo) ->
    [].  % Other places start empty
```

## Step 5: Define Preset and Postset

Preset defines which places feed into a transition, postset defines where tokens go after firing:

```erlang
%% @doc Define input places (preset) for each transition
preset(Transition) ->
    case Transition of
        receive_order -> [start];          % Can only start from 'start'
        process_payment -> [order_received]; % Can only process from 'order_received'
        ship_order -> [payment_pending];    % Can only ship from 'payment_pending'
        complete -> [shipped];             % Can only complete from 'shipped'
        handle_failure -> [failed]         % Handle failure from 'failed'
    end.

%% @doc Define output places (postset) for each transition
postset(Transition) ->
    case Transition of
        receive_order -> [order_received]; % After receiving, order is received
        process_payment -> [payment_pending]; % After payment, payment is pending
        ship_order -> [shipped];           % After shipping, order is shipped
        complete -> [completed];           % After completion, order is completed
        handle_failure -> [failed]         % After handling failure, order is failed
    end.
```

## Step 6: Implement Transition Enablement

The `is_enabled/3` function determines when a transition can fire:

```erlang
%% @doc Check if a transition is enabled (can fire)
is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        receive_order ->
            has_token(start, Mode);  % Can receive order if we're at start
        process_payment ->
            has_token(order_received, Mode) andalso  % Can process payment if order received
            can_process_payment();  % Additional business rule
        ship_order ->
            has_token(payment_pending, Mode);  % Can ship if payment is pending
        complete ->
            has_token(shipped, Mode);  % Can complete if order is shipped
        handle_failure ->
            has_token(failed, Mode)  % Can handle failure if order failed
    end.
```

## Step 7: Implement Transition Firing

The `fire/3` function executes the transition action:

```erlang
%% @doc Execute a transition and produce tokens
fire(Transition, Mode, UsrInfo) ->
    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        receive_order ->
            OrderData = create_order_data(UsrInfo),
            {produce, #{
                order_received => [{order, OrderData}]
            }};

        process_payment ->
            OrderData = get_order_data(Mode, UsrInfo),
            PaymentResult = process_payment(OrderData),
            case PaymentResult of
                {ok, _} ->
                    {produce, #{payment_pending => [payment_token]}};
                {error, Reason} ->
                    {produce, #{failed => [{error, Reason}]}}
            end;

        ship_order ->
            {produce, #{shipped => [shipment_token]}};

        complete ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete, complete),
            {produce, #{completed => [completion_token]}};

        handle_failure ->
            {produce, #{failed => [failure_token]}}
    end.
```

## Step 8: Implement Token Handling

The `trigger/3` function handles what happens to tokens in places:

```erlang
%% @doc Handle tokens in places (cleanup/validation)
trigger(Place, Token, _UsrInfo) ->
    case Place of
        order_received ->
            case Token of
                {order, Data} -> pass;  % Valid order token
                _ -> drop              % Invalid token, drop it
            end;
        payment_pending ->
            case Token of
                payment_token -> pass;  % Valid payment token
                _ -> drop
            end;
        shipped ->
            case Token of
                shipment_token -> pass;  % Valid shipment token
                _ -> drop
            end;
        _ ->
            pass  % Allow all other tokens
    end.
```

## Step 9: Add Helper Functions

Now let's add the helper functions we referenced:

```erlang
%%====================================================================
%%% Helper Functions
%%====================================================================

%% @doc Create initial order data
create_order_data(UsrInfo) ->
    OrderData = case maps:get(order_data, UsrInfo, undefined) of
        undefined ->
            #{
                id => generate_id(<<"order">>),
                items => [#{id => <<"default_item">>, quantity => 1}],
                amount => 100.00,
                customer => <<"system">>
            };
        Data ->
            Data
    end,

    % Log XES workflow start
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    OrderData#{case_id => CaseId}.

%% @doc Get order data from current marking
get_order_data(Mode, _UsrInfo) ->
    case maps:get(order_received, Mode, []) of
        [{order, Data}] -> Data;
        _ -> #{}
    end.

%% @doc Process payment (business logic)
process_payment(OrderData) ->
    Amount = maps:get(amount, OrderData, 0),

    % Simple business rules
    case Amount of
        0 ->
            {error, zero_amount};
        Amount when Amount > 1000 ->
            {error, amount_too_high};
        Amount when Amount < 0 ->
            {error, negative_amount};
        _ ->
            {ok, processed}
    end.

%% @doc Check if payment can be processed
can_process_payment() ->
    true.  % In real implementation, this might check payment methods, etc.

%% @doc Check if a place has tokens
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        [_|_] -> true
    end.

%% @doc Generate unique ID
generate_id(Prefix) ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.
```

## Step 10: Add API Functions

Let's add some API functions to make testing easier:

```erlang
%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create workflow specification
create_workflow(OrderData) ->
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => generate_id(<<"workflow">>),
        order_data => OrderData,
        pattern_type => composite,
        version => <<"1.0.0">>
    },
    {ok, Spec#{config => Config}}.

%% @doc Get workflow specification
get_workflow_spec() ->
    #{
        workflow_id => <<"my_first_workflow">>,
        workflow_name => <<"Simple Order Processing">>,
        version => <<"1.0.0">>,
        description => <<"A simple order processing workflow for demonstration">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [basic_sequential, exclusive_choice]
    }.

%% @doc Get initial marking for simulation
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate order processing workflow
simulate_order_processing() ->
    % Initialize with sample order data
    OrderData = #{
        id => <<"order_test_001">>,
        items => [
            #{id => <<"item_001">>, quantity => 2, price => 25.00},
            #{id => <<"item_002">>, quantity => 1, price => 50.00}
        ],
        amount => 100.00,
        customer => <<"test_customer">>,
        order_data => OrderData
    },

    try
        % Start the workflow
        {ok, InitialState} = create_workflow(OrderData),
        InitialMarking = get_initial_marking(),

        % Execute workflow transitions
        Result = execute_workflow_sequence(InitialMarking, OrderData),

        % Log completion
        CaseId = maps:get(case_id, OrderData, <<>>),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),

        {ok, Result}
    catch
        _:_ ->
            CaseId = maps:get(case_id, OrderData, <<>>),
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {error, workflow_failed}
    end.

%% @doc Execute a sequence of transitions
execute_workflow_sequence(InitialMarking, OrderData) ->
    Transitions = [
        receive_order,
        process_payment,
        ship_order,
        complete
    ],

    UsrInfo = #{order_data => OrderData},

    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        case is_enabled(Transition, CurrentMarking, UsrInfo) of
            true ->
                case fire(Transition, CurrentMarking, UsrInfo) of
                    {produce, ProduceMap} ->
                        NewMarking = apply_produce(CurrentMarking, ProduceMap),
                        {ok, NewMarking};
                    abort ->
                        {ok, CurrentMarking}
                end;
            false ->
                {ok, CurrentMarking}
        end
    end, {ok, InitialMarking}, Transitions).

%% @private Apply produce map to marking
apply_produce(Marking, ProduceMap) ->
    maps:fold(fun(Place, Tokens, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        Acc#{Place => CurrentTokens ++ Tokens}
    end, Marking, ProduceMap).
```

## Step 11: Testing the Workflow

Let's test our workflow in the Erlang shell:

```bash
# Start the Erlang shell
rebar3 shell
```

In the Erlang shell:

```erlang
% Compile the module
c(my_first_workflow).

% Run the simulation
{ok, Result} = my_first_workflow:simulate_order_processing().

% Check the result
io:format("Result: ~p~n", [Result]).
```

Expected output:
```erlang
Result: {ok,#{completed => [completion_token]}}
```

## Step 12: Handling Different Scenarios

Let's add a test for a payment failure scenario:

```erlang
%% @doc Simulate order processing with payment failure
simulate_payment_failure() ->
    OrderData = #{
        id => <<"order_failure_001">>,
        items => [#{id => <<"expensive_item">>, quantity => 1, price => 1500.00}],
        amount => 1500.00,  % This will trigger payment failure
        customer => <<"test_customer">>
    },

    {ok, InitialState} = create_workflow(OrderData),
    InitialMarking = get_initial_marking(),

    % Execute until payment processing
    {ok, AfterPayment} = execute_workflow_sequence(
        InitialMarking#{order_received => [{order, OrderData}]},
        OrderData
    ),

    % Check that we ended up in failed state
    Failed = has_token(failed, AfterPayment),
    io:format("Payment failed: ~p~n", [Failed]),

    {ok, AfterPayment}.
```

Test this:
```erlang
{ok, Result} = my_first_workflow:simulate_payment_failure().
io:format("Result: ~p~n", [Result]).
```

## Step 13: Complete Module File

Here's the complete `my_first_workflow.erl` file for reference:

```erlang
%%%-------------------------------------------------------------------
%%% @doc
%%% My First YAWL Workflow - Simple Order Processing
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(my_first_workflow).
-author("Your Name").

-export([
    place_lst/0,
    trsn_lst/0,
    init_marking/2,
    preset/1,
    postset/1,
    is_enabled/3,
    fire/3,
    trigger/3,
    create_workflow/1,
    get_workflow_spec/0,
    simulate_order_processing/0,
    simulate_payment_failure/0,
    get_initial_marking/0
]).

-include("gen_pnet.hrl").
-include("yawl_types.hrl").
-include("yawl_xes.hrl").

-define(WORKFLOW_ID, <<"my_first_workflow">>).

%%====================================================================
%%% gen_pnet Callbacks
%%====================================================================

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

is_enabled(receive_order, Mode, _UsrInfo) ->
    has_token(start, Mode);
is_enabled(process_payment, Mode, _UsrInfo) ->
    has_token(order_received, Mode) andalso can_process_payment();
is_enabled(ship_order, Mode, _UsrInfo) ->
    has_token(payment_pending, Mode);
is_enabled(complete, Mode, _UsrInfo) ->
    has_token(shipped, Mode);
is_enabled(handle_failure, Mode, _UsrInfo) ->
    has_token(failed, Mode).

fire(receive_order, _Mode, UsrInfo) ->
    OrderData = create_order_data(UsrInfo),
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, receive_order, start),
    {produce, #{order_received => [{order, OrderData}]}};

fire(process_payment, Mode, UsrInfo) ->
    OrderData = get_order_data(Mode, UsrInfo),
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, process_payment, start),
    PaymentResult = process_payment(OrderData),
    case PaymentResult of
        {ok, _} ->
            {produce, #{payment_pending => [payment_token]}};
        {error, Reason} ->
            {produce, #{failed => [{error, Reason}]}}
    end;

fire(ship_order, _Mode, _UsrInfo) ->
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, ship_order, start),
    {produce, #{shipped => [shipment_token]}};

fire(complete, _Mode, _UsrInfo) ->
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete, complete),
    {produce, #{completed => [completion_token]}};

fire(handle_failure, _Mode, _UsrInfo) ->
    {produce, #{failed => [failure_token]}}.

trigger(order_received, {order, _}, _UsrInfo) -> pass;
trigger(_Place, _Token, _UsrInfo) -> pass.

%%====================================================================
%%% API Functions
%%====================================================================

create_workflow(OrderData) ->
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => generate_id(<<"workflow">>),
        order_data => OrderData,
        pattern_type => composite,
        version => <<"1.0.0">>
    },
    {ok, Spec#{config => Config}}.

get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Simple Order Processing">>,
        version => <<"1.0.0">>,
        description => <<"A simple order processing workflow for demonstration">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [basic_sequential, exclusive_choice]
    }.

get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

simulate_order_processing() ->
    OrderData = #{
        id => <<"order_test_001">>,
        items => [
            #{id => <<"item_001">>, quantity => 2, price => 25.00},
            #{id => <<"item_002">>, quantity => 1, price => 50.00}
        ],
        amount => 100.00,
        customer => <<"test_customer">>
    },

    try
        {ok, InitialState} = create_workflow(OrderData),
        InitialMarking = get_initial_marking(),
        Result = execute_workflow_sequence(InitialMarking, OrderData),
        CaseId = maps:get(case_id, OrderData, <<>>),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        {ok, Result}
    catch
        _:_ ->
            CaseId = maps:get(case_id, OrderData, <<>>),
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {error, workflow_failed}
    end.

simulate_payment_failure() ->
    OrderData = #{
        id => <<"order_failure_001">>,
        items => [#{id => <<"expensive_item">>, quantity => 1, price => 1500.00}],
        amount => 1500.00,
        customer => <<"test_customer">>
    },

    {ok, InitialState} = create_workflow(OrderData),
    InitialMarking = get_initial_marking(),
    {ok, AfterPayment} = execute_workflow_sequence(
        InitialMarking#{order_received => [{order, OrderData}]},
        OrderData
    ),

    Failed = has_token(failed, AfterPayment),
    io:format("Payment failed: ~p~n", [Failed]),
    {ok, AfterPayment}.

%%====================================================================
%%% Internal Functions
%%====================================================================

create_order_data(UsrInfo) ->
    OrderData = case maps:get(order_data, UsrInfo, undefined) of
        undefined ->
            #{
                id => generate_id(<<"order">>),
                items => [#{id => <<"default_item">>, quantity => 1}],
                amount => 100.00,
                customer => <<"system">>
            };
        Data ->
            Data
    end,

    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),
    OrderData#{case_id => CaseId}.

get_order_data(Mode, _UsrInfo) ->
    case maps:get(order_received, Mode, []) of
        [{order, Data}] -> Data;
        _ -> #{}
    end.

process_payment(OrderData) ->
    Amount = maps:get(amount, OrderData, 0),
    case Amount of
        0 -> {error, zero_amount};
        Amount when Amount > 1000 -> {error, amount_too_high};
        Amount when Amount < 0 -> {error, negative_amount};
        _ -> {ok, processed}
    end.

can_process_payment() -> true.

has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        [_|_] -> true
    end.

generate_id(Prefix) ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.

execute_workflow_sequence(InitialMarking, OrderData) ->
    Transitions = [receive_order, process_payment, ship_order, complete],
    UsrInfo = #{order_data => OrderData},

    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        case is_enabled(Transition, CurrentMarking, UsrInfo) of
            true ->
                case fire(Transition, CurrentMarking, UsrInfo) of
                    {produce, ProduceMap} ->
                        NewMarking = apply_produce(CurrentMarking, ProduceMap),
                        {ok, NewMarking};
                    abort ->
                        {ok, CurrentMarking}
                end;
            false ->
                {ok, CurrentMarking}
        end
    end, {ok, InitialMarking}, Transitions).

apply_produce(Marking, ProduceMap) ->
    maps:fold(fun(Place, Tokens, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        Acc#{Place => CurrentTokens ++ Tokens}
    end, Marking, ProduceMap).
```

## Step 14: Running the Complete Workflow

Test both scenarios:

```erlang
% Success scenario
{ok, SuccessResult} = my_first_workflow:simulate_order_processing().
io:format("Success: ~p~n", [SuccessResult]).

% Failure scenario
{ok, FailureResult} = my_first_workflow:simulate_payment_failure().
io:format("Failure: ~p~n", [FailureResult]).
```

## What We Learned

1. **Places and Transitions**: The basic building blocks of YAWL workflows
2. **Token Movement**: How tokens flow through the workflow
3. **Transition Enablement**: Business logic for when transitions can fire
4. **Transition Firing**: What happens when a transition executes
5. **Error Handling**: Managing failure scenarios
6. **XES Logging**: Tracking workflow execution for auditing
7. **API Design**: Creating user-friendly interfaces for workflow interaction

## Next Steps

Now that you've created your first workflow, you're ready to:

1. **Explore Patterns**: Learn about different YAWL patterns and how to use them
2. **Business Workflows**: See how real-world business scenarios are implemented
3. **REST API**: Learn to interact with your workflow via HTTP
4. **Testing and Debugging**: Implement comprehensive testing strategies

## Key Concepts to Remember

- **Places** are states, **transitions** are actions
- **Tokens** move from places through transitions
- **Preset/Postset** define workflow connectivity
- **is_enabled/3** contains business logic
- **fire/3** executes transition actions
- **trigger/3** handles token validation
- **XES logging** provides audit trails

Your first YAWL workflow is now complete and functional! You can use this as a foundation for more complex workflows.