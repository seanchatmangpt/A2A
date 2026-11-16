# Object-Centric Process Mining (OCPM)

Process mining for workflows involving multiple interacting object types.

## Overview

Object-Centric Process Mining extends traditional process mining to handle multiple object types that interact during process execution. This is essential for complex business processes like order-to-cash where orders, items, payments, and shipments interact.

## Key Concepts

### Object Types

Different entity types that participate in a process:

- **Order**: Purchase order entity
- **Item**: Product/order line item
- **Payment**: Financial transaction
- **Shipment**: Logistics entity
- **Customer**: Customer entity

### Object Lifecycle

The sequence of states an object goes through:

```erlang
-order lifecycle: created -> approved -> processing -> shipped -> completed
+payment lifecycle: pending -> processing -> completed -> settled
=item lifecycle: added -> reserved -> picked -> packed -> shipped
```

### Object Interactions

How objects affect each other:

- **Order-Item**: Order contains items
- **Order-Payment**: Payment required for order
- **Order-Shipment**: Shipment delivers order

## Data Structures

### Object-Centric Event Log

```erlang
-record(ocel_log, {
    id :: binary(),
    object_types :: [binary()],
    events :: [ocel_event()],
    objects :: [ocel_object()],
    extensions :: map()
}).

-type ocel_event() :: #{
    id := binary(),
    activity := binary(),
    timestamp := integer(),
    objects :: #{binary() => [binary()]},  %% object type => object ids
    attributes := map()
}.

-type ocel_object() :: #{
    id := binary(),
    type := binary(),
    lifecycle :: [binary()],
    attributes := map()
}.
```

### OCPM Model

```erlang
-record(ocpm_model, {
    id :: binary(),
    object_types :: [ocpm_object_type()],
    activities :: [ocpm_activity()],
    interactions :: [ocpm_interaction()],
    lifecycles :: map()  %% #{object_type => lifecycle()}
}).

-type ocpm_object_type() :: #{
    type := binary(),
    attributes := [binary()]
}.

-type ocpm_activity() :: #{
    name := binary(),
    input_objects :: #{binary() => [binary()]},
    output_objects :: #{binary() => [binary()]}
}.

-type ocpm_interaction() :: #{
    from_type := binary(),
    to_type := binary(),
    relation := one_to_one | one_to_many | many_to_one | many_to_many
}.
```

## Implementation

### OCPM Discoverer

```erlang
-module(yawl_ocpm).

-export([discover/1, discover_object_types/1, discover_lifecycles/2]).

%% Discover OCPM model from event log
-spec discover(ocel_log()) -> {ok, ocpm_model()} | {error, term()}.
discover(#ocel_log{id = LogId, events = Events, objects = Objects} = Log) ->
    %% Discover object types
    ObjectTypes = discover_object_types(Log),

    %% Discover activities
    Activities = discover_activities(Events),

    %% Discover object lifecycles
    Lifecycles = lists:map(fun(OT) ->
        Type = maps:get(type, OT),
        {Type, discover_lifecycles(Type, Log)}
    end, ObjectTypes),

    %% Discover interactions
    Interactions = discover_interactions(Events, ObjectTypes),

    Model = #ocpm_model{
        id = yawl_utils:generate_id(ocpm),
        object_types = ObjectTypes,
        activities = Activities,
        interactions = Interactions,
        lifecycles = maps:from_list(Lifecycles)
    },

    {ok, Model}.

%% Discover object types from log
-spec discover_object_types(ocel_log()) -> [ocpm_object_type()].
discover_object_types(#ocel_log{objects = Objects}) ->
    %% Group objects by type
    TypeMap = lists:foldl(fun(Obj, Map) ->
        Type = maps:get(type, Obj),
        Attrs = maps:keys(maps:get(attributes, Obj, #{})),
        maps:update_with(Type, fun(Existing) ->
            lists:usort(Existing ++ Attrs)
        end, Attrs, Map)
    end, #{}, Objects),

    %% Convert to object type records
    lists:map(fun({Type, Attrs}) ->
        #{
            type => Type,
            attributes => Attrs
        }
    end, maps:to_list(TypeMap)).

%% Discover activities from events
-spec discover_activities([ocel_event()]) -> [ocpm_activity()].
discover_activities(Events) ->
    %% Group events by activity
    ActivitiesMap = lists:foldl(fun(Event, Map) ->
        ActivityName = maps:get(activity, Event),
        Objects = maps:get(objects, Event, #{}),

        %% Accumulate input/output object types
        maps:update_with(ActivityName, fun(Acc) ->
            merge_object_references(Acc, Objects)
        end, Objects, Map)
    end, #{}, Events),

    %% Convert to activity records
    lists:map(fun({Name, ObjectRefs}) ->
        #{
            name => Name,
            input_objects => maps:get(input, ObjectRefs, #{}),
            output_objects => maps:get(output, ObjectRefs, #{})
        }
    end, maps:to_list(ActivitiesMap)).

%% Discover lifecycles for an object type
-spec discover_lifecycles(binary(), ocel_log()) -> [binary()].
discover_lifecycles(ObjectType, #ocel_log{events = Events}) ->
    %% Filter events involving this object type
    RelevantEvents = lists:filter(fun(Event) ->
        Objects = maps:get(objects, Event, #{}),
        maps:is_key(ObjectType, Objects)
    end, Events),

    %% Extract lifecycle states from event attributes
    States = lists:flatmap(fun(Event) ->
        Objects = maps:get(objects, Event, #{}),
        ObjectIds = maps:get(ObjectType, Objects, []),
        lists:map(fun(_ObjId) ->
            %% Extract state from event or attributes
            maps:get(<<"lifecycle:state">>,
                    maps:get(attributes, Event, #{}),
                    maps:get(activity, Event))
        end, ObjectIds)
    end, RelevantEvents),

    %% Return unique, ordered states
    lists:usort(States).

%% Discover interactions between object types
-spec discover_interactions([ocel_event()], [ocpm_object_type()]) -> [ocpm_interaction()].
discover_interactions(Events, ObjectTypes) ->
    Types = [maps:get(type, OT) || OT <- ObjectTypes],

    %% Analyze event object combinations
    InteractionsMap = lists:foldl(fun(Event, Map) ->
        Objects = maps:get(objects, Event, #{}),
        EventTypes = maps:keys(Objects),

        %% Find all pairs of object types in this event
        Pairs = find_pairs(EventTypes),

        %% Update interaction counts
        lists:foldl(fun({Type1, Type2}, AccMap) ->
            Key = {Type1, Type2},
            maps:update_with(Key, fun(Count) -> Count + 1 end, 1, AccMap)
        end, Map, Pairs)
    end, #{}, Events),

    %% Determine relationship types based on cardinality
    lists:map(fun({{Type1, Type2}, Count}) ->
        Relation = determine_relation_type(Events, Type1, Type2, Count),
        #{
            from_type => Type1,
            to_type => Type2,
            relation => Relation
        }
    end, maps:to_list(InteractionsMap)).

%% Determine relation type between object types
determine_relation_type(Events, Type1, Type2, TotalEvents) ->
    %% Count occurrences of each cardinality pattern
    OneToOne = count_pattern(Events, Type1, Type2, one_to_one),
    OneToMany = count_pattern(Events, Type1, Type2, one_to_many),
    ManyToOne = count_pattern(Events, Type1, Type2, many_to_one),

    %% Return dominant pattern
    Max = max(OneToOne, max(OneToMany, ManyToOne)),
    case Max of
        OneToOne -> one_to_one;
        OneToMany -> one_to_many;
        ManyToOne -> many_to_one;
        _ -> many_to_many
    end.

%% Count pattern occurrences
count_pattern(Events, Type1, Type2, Pattern) ->
    lists:foldl(fun(Event, Count) ->
        Objects = maps:get(objects, Event, #{}),
        Obj1 = maps:get(Type1, Objects, []),
        Obj2 = maps:get(Type2, Objects, []),

        case {length(Obj1), length(Obj2)} of
            {1, 1} when Pattern =:= one_to_one -> Count + 1;
            {1, N} when N > 1, Pattern =:= one_to_many -> Count + 1;
            {N, 1} when N > 1, Pattern =:= many_to_one -> Count + 1;
            _ -> Count
        end
    end, 0, Events).

%% Merge object references
merge_object_references(Acc, Objects) ->
    lists:foldl(fun({Type, Ids}, M) ->
        maps:update_with(Type, fun(Existing) ->
            lists:usort(Existing ++ Ids)
        end, Ids, M)
    end, Acc, maps:to_list(Objects)).

%% Find all pairs from a list
find_pairs(List) ->
    [{A, B} || A <- List, B <- List, A < B].
```

### Lifecycle Analyzer

```erlang
-module(ocpm_lifecycle_analyzer).

-export([analyze/2, get_transitions/2, detect_deviations/3]).

%% Analyze lifecycle conformance
-spec analyze(binary(), ocpm_model()) -> {ok, lifecycle_analysis()} | {error, term()}.
analyze(ObjectId, Model) ->
    %% Get actual lifecycle from event log
    {ok, ActualLifecycle} = get_actual_lifecycle(ObjectId),

    %% Get expected lifecycle from model
    ObjectType = get_object_type(ObjectId),
    ExpectedLifecycle = maps:get(ObjectType, Model#ocpm_model.lifecycles),

    %% Compare lifecycles
    Deviations = detect_deviations(ActualLifecycle, ExpectedLifecycle, Model),

    Analysis = #lifecycle_analysis{
        object_id => ObjectId,
        object_type => ObjectType,
        expected_lifecycle => ExpectedLifecycle,
        actual_lifecycle => ActualLifecycle,
        conformance => calculate_conformance(ActualLifecycle, ExpectedLifecycle),
        deviations => Deviations
    },

    {ok, Analysis}.

%% Get lifecycle transitions
-spec get_transitions([binary()], ocpm_model()) -> [{binary(), binary()}].
get_transitions(Lifecycle, Model) ->
    %% Get consecutive state pairs
    States = Lifecycle,
    [{A, B} || {A, B} <- lists:zip(States, tl(States))].

%% Detect deviations from expected lifecycle
-spec detect_deviations([binary()], [binary()], ocpm_model()) -> [lifecycle_deviation()].
detect_deviations(Actual, Expected, _Model) ->
    %% Find states not in expected lifecycle
    InvalidStates = [S || S <- Actual, not lists:member(S, Expected)],

    %% Find out-of-order transitions
    InvalidTransitions = find_invalid_transitions(Actual, Expected),

    [#{
        type => invalid_state,
        details => InvalidStates
    },
    #{
        type => invalid_transition,
        details => InvalidTransitions
    }].

find_invalid_transitions(Actual, Expected) ->
    Transitions = [{A, B} || {A, B} <- lists:zip(Actual, tl(Actual))],
    ValidTransitions = [{A, B} || {A, B} <- lists:zip(Expected, tl(Expected))],

    [T || T <- Transitions, not lists:member(T, ValidTransitions)].

%% Calculate conformance score
calculate_conformance(Actual, Expected) ->
    %% Simple Jaccard similarity
    ActualSet = sets:from_list(Actual),
    ExpectedSet = sets:from_list(Expected),

    Intersection = sets:intersection(ActualSet, ExpectedSet),
    Union = sets:union(ActualSet, ExpectedSet),

    sets:size(Intersection) / sets:size(Union).
```

## REST API

### Discover OCPM Model

```bash
curl -X POST http://localhost:8081/api/research/ocpm/discover \
  -H "Content-Type: application/json" \
  -d '{
    "log_id": "ocpm_log_1",
    "algorithm": "ocpm_inductive",
    "options": {
      "object_type_lifecycle": true
    }
  }'
```

### Get Object Types

```bash
curl http://localhost:8081/api/research/ocpm/object-types/{log_id}
```

## Use Cases

### Order-to-Cash Analysis

Analyze complete order-to-cash process:

```erlang
{ok, Model} = yawl_ocpm:discover(OCELLog),
%% Model contains order, item, payment, shipment interactions
```

### Bottleneck Detection

Find objects stuck in specific states:

```erlang
{ok, StuckObjects} = ocpm_lifecycle_analyzer:find_stuck(ObjectType, State),
```

### Conformance Checking

Check if objects follow expected lifecycles:

```erlang
{ok, Analysis} = ocpm_lifecycle_analyzer:analyze(ObjectId, Model),
Conformance = Analysis#lifecycle_analysis.conformance.
```

---

Next: [CPN](cpn.md) | [Back to Overview](overview.md)
