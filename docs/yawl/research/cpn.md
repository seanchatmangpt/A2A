# Colored Petri Nets (CPN)

Advanced Petri net analysis with data, time, and hierarchy.

## Overview

Colored Petri Nets extend classical Petri nets with:
- **Data**: Tokens carry complex data values (colors)
- **Time**: Transitions have duration and time constraints
- **Hierarchy**: Nets can be composed of sub-nets

## Key Concepts

### Color Sets

Type definitions for token data:

```erlang
%% Simple color sets
color_set(int, integer).
color_set(bool, boolean).
color_set(string, binary).

%% Compound color sets
color_set(product, record, [{id, int}, {name, string}, {price, real}]).
color_set(order, record, [{customer_id, string}, {items, list(product)}]).
color_set(status, union, [pending, approved, rejected, completed]).
```

### Guards

Boolean expressions controlling transition firing:

```erlang
%% Guards
guard(amount > 0).
guard(status =:= approved).
guard(length(items) > 0 andalso total < 10000).
```

### Timed Transitions

Transitions with duration:

```erlang
%% Immediate transition
transition(validate).

%% Timed transition (duration in milliseconds)
transition(process_payment, duration = 5000).

%% Time-delayed transition
transition(ship_order, delay = @{2024-01-01 10:00:00}).
```

## Data Structures

```erlang
-record(cpn, {
    id :: binary(),
    name :: binary(),
    places :: [cpn_place()],
    transitions :: [cpn_transition()],
    arcs :: [cpn_arc()],
    color_sets :: map(),  %% #{name => color_set_def()}
    time_mode :: discrete | continuous
}).

-record(cpn_place, {
    id :: binary(),
    name :: binary(),
    color_set :: binary(),
    initial_marking :: [term()],
    capacity :: integer() | unlimited
}).

-record(cpn_transition, {
    id :: binary(),
    name :: binary(),
    guard :: fun((term()) -> boolean()) | undefined,
    code :: fun((term()) -> term()) | undefined,
    duration :: integer() | undefined,
    priority :: integer()
}).

-record(cpn_arc, {
    id :: binary(),
    from :: binary(),
    to :: binary(),
    expression :: fun((term()) -> term())
}).
```

## Implementation

### CPN Simulator

```erlang
-module(cpn_simulator).

-export([create/1, fire/2, step/1, simulate/3, get_marking/1]).

%% Create a CPN from specification
-spec create(map()) -> {ok, cpn()} | {error, term()}.
create(Spec) ->
    %% Validate color sets
    ColorSets = maps:get(color_sets, Spec, #{}),
    ok = validate_color_sets(ColorSets),

    %% Create places
    Places = lists:map(fun(P) ->
        #cpn_place{
            id = maps:get(id, P),
            name = maps:get(name, P),
            color_set = maps:get(color_set, P),
            initial_marking = maps:get(initial_marking, P, []),
            capacity = maps:get(capacity, P, unlimited)
        }
    end, maps:get(places, Spec, [])),

    %% Create transitions
    Transitions = lists:map(fun(T) ->
        #cpn_transition{
            id = maps:get(id, T),
            name = maps:get(name, T),
            guard = compile_guard(maps:get(guard, T)),
            code = compile_code(maps:get(code, T)),
            duration = maps:get(duration, T, 0),
            priority = maps:get(priority, T, 0)
        }
    end, maps:get(transitions, Spec, [])),

    %% Create arcs
    Arcs = lists:map(fun(A) ->
        #cpn_arc{
            id = maps:get(id, A),
            from = maps:get(from, A),
            to = maps:get(to, A),
            expression = compile_expression(maps:get(expression, A))
        }
    end, maps:get(arcs, Spec, [])),

    CPN = #cpn{
        id = yawl_utils:generate_id(cpn),
        name = maps:get(name, Spec),
        places = Places,
        transitions = Transitions,
        arcs = Arcs,
        color_sets = ColorSets,
        time_mode = maps:get(time_mode, Spec, discrete)
    },

    %% Initialize marking
    initialize_marking(CPN).

%% Fire a specific transition
-spec fire(cpn(), binary()) -> {ok, cpn()} | {error, not_enabled}.
fire(#cpn{} = CPN, TransitionId) ->
    case is_enabled(CPN, TransitionId) of
        true ->
            execute_transition(CPN, TransitionId);
        false ->
            {error, not_enabled}
    end.

%% Execute one step (fire any enabled transition)
-spec step(cpn()) -> {ok, binary(), cpn()} | {error, no_enabled_transitions}.
step(#cpn{transitions = Transitions} = CPN) ->
    Enabled = [T || T <- Transitions,
                   is_enabled(CPN, T#cpn_transition.id)],
    case Enabled of
        [] ->
            {error, no_enabled_transitions};
        _ ->
            %% Select by priority
            Sorted = lists:sort(fun(A, B) ->
                A#cpn_transition.priority >= B#cpn_transition.priority
            end, Enabled),
            Selected = hd(Sorted),
            execute_transition(CPN, Selected#cpn_transition.id)
    end.

%% Simulate for N steps
-spec simulate(cpn(), integer(), map()) -> {ok, simulation_result()}.
simulate(CPN, Steps, Options) ->
    %% Run simulation
    {ok, Results} = run_simulation(CPN, Steps, Options),

    %% Extract final marking
    FinalMarking = get_marking(element(2, lists:last(Results))),

    %% Statistics
    Statistics = calculate_statistics(Results),

    {ok, #simulation_result{
        cpn_id => CPN#cpn.id,
        steps => length(Results),
        trace => Results,
        final_marking => FinalMarking,
        statistics => Statistics
    }}.

%% Run simulation loop
run_simulation(CPN, MaxSteps, Options) ->
    run_simulation(CPN, MaxSteps, Options, []).

run_simulation(_CPN, 0, _Options, Acc) ->
    {ok, lists:reverse(Acc)};
run_simulation(CPN, Steps, Options, Acc) ->
    case step(CPN) of
        {error, no_enabled_transitions} ->
            {ok, lists:reverse(Acc)};
        {ok, TransitionId, NewCPN} ->
            Record = #{
                step => MaxSteps - Steps + 1,
                fired_transition => TransitionId,
                marking_before => get_marking(CPN),
                marking_after => get_marking(NewCPN)
            },
            run_simulation(NewCPN, Steps - 1, Options, [Record | Acc])
    end.

%% Check if transition is enabled
is_enabled(CPN, TransitionId) ->
    case find_transition(CPN, TransitionId) of
        {ok, Transition} ->
            has_tokens(CPN, Transition) andalso
            guard_true(CPN, Transition);
        error ->
            false
    end.

%% Check if input places have required tokens
has_tokens(CPN, Transition) ->
    InputPlaces = get_input_places(CPN, Transition),
    lists:all(fun(PlaceId) ->
        Marking = get_marking(CPN),
        maps:get(PlaceId, Marking, []) =/= []
    end, InputPlaces).

%% Evaluate guard expression
guard_true(_CPN, #cpn_transition{guard = undefined}) ->
    true;
guard_true(CPN, #cpn_transition{guard = Guard}) ->
    %% Get variable bindings from input places
    Bindings = collect_bindings(CPN, Guard),
    Guard(Bindings).

%% Execute transition
execute_transition(CPN, TransitionId) ->
    {ok, Transition} = find_transition(CPN, TransitionId),

    %% Remove tokens from input places
    CPN1 = remove_input_tokens(CPN, Transition),

    %% Execute transition code
    OutputTokens = case Transition#cpn_transition.code of
        undefined -> InputTokens;
        Code -> Code(InputTokens)
    end,

    %% Add tokens to output places
    CPN2 = add_output_tokens(CPN1, Transition, OutputTokens),

    {ok, TransitionId, CPN2}.

%% Get current marking
-spec get_marking(cpn()) -> map().
get_marking(#cpn{marking = Marking}) ->
    Marking.

%% Calculate simulation statistics
calculate_statistics(Results) ->
    TransitionCounts = lists:foldl(fun(#{fired_transition := T}, Acc) ->
        maps:update_with(T, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Results),

    #{
        transition_counts => TransitionCounts,
        total_steps => length(Results),
        unique_transitions => maps:size(TransitionCounts)
    }.
```

### Color Set Compiler

```erlang
-module(cpn_color_sets).

-export([define/2, check/3, convert/3]).

%% Define a color set
-spec define(binary(), color_set_def()) -> ok.
define(Name, Definition) ->
    %% Store color set definition
    ok = ets:insert(cpn_color_sets, {Name, Definition}),
    ok.

%% Check if value matches color set
-spec check(binary(), term(), binary()) -> boolean() | {error, term()}.
check(Value, ColorSetName, ColorSetDef) ->
    case ColorSetDef of
        {simple, integer} -> is_integer(Value);
        {simple, boolean} -> is_boolean(Value);
        {simple, string} -> is_binary(Value);
        {simple, real} -> is_number(Value);
        {record, Fields} when is_map(Value) ->
            lists:all(fun({Field, Type}) ->
                case maps:get(Field, Value, undefined) of
                    undefined -> false;
                    FieldValue -> check(FieldValue, Field, Type)
                end
            end, Fields);
        {list, ElementType} when is_list(Value) ->
            lists:all(fun(V) -> check(V, ElementType, simple) end, Value);
        {union, Options} ->
            lists:member(Value, Options)
    end.

%% Convert value to color set
-spec convert(term(), binary(), binary()) -> {ok, term()} | {error, term()}.
convert(Value, FromType, ToType) ->
    case {FromType, ToType} of
        {string, int} ->
            case binary_to_integer(Value) of
                {ok, Int} -> {ok, Int};
                error -> {error, invalid_conversion}
            end;
        {int, string} ->
            {ok, integer_to_binary(Value)};
        _ ->
            {error, unsupported_conversion}
    end.
```

## REST API

### Create CPN Model

```bash
curl -X POST http://localhost:8081/api/research/cpn/model \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order_processing",
    "color_sets": {
      "order": {
        "type": "record",
        "fields": [
          {"name": "id", "type": "int"},
          {"name": "customer", "type": "string"},
          {"name": "amount", "type": "real"}
        ]
      }
    },
    "places": [
      {
        "id": "p_input",
        "name": "input",
        "color_set": "order",
        "initial_marking": []
      }
    ],
    "transitions": [
      {
        "id": "t_validate",
        "name": "validate",
        "guard": "amount > 0 andalso amount < 10000",
        "duration": 1000
      }
    ]
  }'
```

### Simulate CPN

```bash
curl -X POST http://localhost:8081/api/research/cpn/simulate \
  -H "Content-Type: application/json" \
  -d '{
    "cpn_id": "cpn_abc123",
    "initial_marking": {
      "p_input": [{"id": 1, "customer": "cust1", "amount": 500}]
    },
    "steps": 10
  }'
```

## Use Cases

### Data Flow Modeling

Model complex data transformations:

```erlang
%% Order with complex data structure
Order = #{
    id => 1,
    items => [#{
        product_id => "P1",
        quantity => 2
    }],
    total => 100.0
},
```

### Time-Critical Processes

Model processes with time constraints:

```erlang
%% Transition with duration
#cpn_transition{
    id => process_payment,
    duration => 5000,  %% 5 seconds
    priority => high
}.
```

---

[Back to Overview](overview.md) | [Back to Index](../index.md)
