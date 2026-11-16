# Partial Order Discovery

Discover process structure from event logs using advanced mining algorithms.

## Overview

Partial order discovery extracts the process model from event logs, identifying the causal, parallel, and conflict relationships between activities. This implementation supports the Alpha, Heuristic, and Inductive miner algorithms.

## Concepts

### Order Relations

Given a set of activities, three relations can be identified:

1. **Causality (>)**: Activity A always precedes Activity B
2. **Conflict (#)**: Activities A and B never occur together in a case
3. **Concurrency (||)**: Activities A and B can occur in any order

### Alpha Algorithm

The classic process discovery algorithm:

1. **Extract Footprint**: Identify order relations from log
2. **Build Places**: Create places from causal relations
3. **Connect Transitions**: Build the Petri net
4. **Verify Model**: Check fitness against original log

## Data Structures

### Event Log

```erlang
-record(event_log, {
    id :: binary(),
    traces :: [trace()],
    activities :: [binary()],
    start_timestamp :: integer(),
    end_timestamp :: integer()
}).

-type trace() :: #{
    case_id := binary(),
    events := [event()]
}.

-type event() :: #{
    activity := binary(),
    timestamp := integer(),
    attributes := map()
}.
```

### Process Model

```erlang
-record(process_model, {
    id :: binary(),
    places :: [place()],
    transitions :: [transition()],
    arcs :: [arc()],
    relations :: order_relations()
}).

-type place() :: #{
    id := binary(),
    input_transitions := [binary()],
    output_transitions := [binary()]
}.

-type transition() :: #{
    id := binary(),
    label := binary(),
    type => visible | invisible | skip
}.

-type arc() :: #{
    id := binary(),
    source := binary(),
    target := binary()
}.

-type order_relations() :: #{
    causality := [{binary(), binary()}],
    conflict := [{binary(), binary()}],
    concurrency := [{binary(), binary()}]
}.
```

## Implementation

### Alpha Miner

```erlang
-module(alpha_miner).

-export([discover/1, extract_relations/1, build_model/1]).

%% Discover process model using Alpha algorithm
-spec discover(event_log()) -> {ok, process_model()} | {error, term()}.
discover(#event_log{traces = Traces} = Log) ->
    %% Extract all activities
    Activities = extract_activities(Log),

    %% Extract order relations
    Relations = extract_relations(Traces),

    %% Build places from relations
    Places = build_places(Relations, Activities),

    %% Build transitions
    Transitions = build_transitions(Activities),

    %% Build arcs
    Arcs = build_arcs(Places, Transitions),

    Model = #process_model{
        id = yawl_utils:generate_id(model),
        places = Places,
        transitions = Transitions,
        arcs = Arcs,
        relations = Relations
    },

    {ok, Model}.

%% Extract order relations from traces
-spec extract_relations([trace()]) -> order_relations().
extract_relations(Traces) ->
    %% Initialize relation sets
    Causality = sets:new(),
    Conflict = sets:new(),
    Concurrency = sets:new(),

    %% Process each trace
    {FinalCausality, FinalConflict, FinalConcurrency} =
        lists:foldl(fun(Trace, {C, CF, CC) ->
            extract_from_trace(Trace, C, CF, CC)
        end, {Causality, Conflict, Concurrency}, Traces),

    %% Convert to lists
    #{
        causality => sets:to_list(FinalCausality),
        conflict => sets:to_list(FinalConflict),
        concurrency => sets:to_list(FinalConcurrency)
    }.

%% Extract relations from a single trace
extract_from_trace(#{events := Events}, Causality, Conflict, Concurrency) ->
    Activities = [maps:get(activity, E) || E <- Events],

    %% Build direct succession map
    Succession = build_succession_map(Activities),

    %% Update relations
    lists:foldl(fun({A, B}, {C, CF, CC}) ->
        case {relation_exists(B, A, C), relation_exists(A, B, C)} of
            {true, true} ->
                %% Concurrency (A > B and B > A)
                {C, CF, sets:add_element({A, B}, sets:add_element({B, A}, CC))};
            {false, false} ->
                %% Conflict (neither A > B nor B > A)
                {C, sets:add_element({A, B}, sets:add_element({B, A}, CF)), CC};
            {true, false} ->
                %% Causality (A > B only)
                {sets:add_element({A, B}, C), CF, CC};
            {false, true} ->
                %% Causality (B > A only)
                {sets:add_element({B, A}, C), CF, CC}
        end
    end, {Causality, Conflict, Concurrency}, Succession).

%% Build places from causal relations
build_places(#{causality := Causality}, Activities) ->
    %% Find maximal sets of causes
    CauseSets = find_maximal_cause_sets(Causality, Activities),

    %% Find maximal sets of effects
    EffectSets = find_maximal_effect_sets(Causality, Activities),

    %% Create places from combinations
    lists:foldl(fun(CauseSet, Places) ->
        lists:foldl(fun(EffectSet, P) ->
            %% Check if place is valid
            case is_valid_place(CauseSet, EffectSet, Causality) of
                true ->
                    PlaceId = yawl_utils:generate_id(place),
                    [#{
                        id => PlaceId,
                        input_transitions => CauseSet,
                        output_transitions => EffectSet
                    } | P];
                false ->
                    P
            end
        end, Places, EffectSets)
    end, [], CauseSets).

%% Find maximal cause sets
find_maximal_cause_sets(Causality, Activities) ->
    %% Group activities by their effects
    EffectMap = lists:foldl(fun({A, B}, Map) ->
        maps:update_with(B, fun(Set) -> sets:add_element(A, Set) end,
                          sets:new(), Map)
    end, #{}, Causality),

    %% Convert to maximal sets
    lists:map(fun({_, Set}) ->
        lists:sort(sets:to_list(Set))
    end, maps:to_list(EffectMap)).

%% Check if place is valid
is_valid_place(CauseSet, EffectSet, Causality) ->
    %% Every cause must have causality to every effect
    lists:all(fun(Cause) ->
        lists:all(fun(Effect) ->
            lists:member({Cause, Effect}, Causality)
        end, EffectSet)
    end, CauseSet) andalso lists:all(fun(Effect) ->
        lists:all(fun(Cause) ->
            lists:member({Cause, Effect}, Causality)
        end, CauseSet)
    end, EffectSet).
```

### Heuristic Miner

```erlang
-module(heuristic_miner).

-export([discover/2, calculate_dependency/2]).

%% Discover process model using Heuristic miner
-spec discover(event_log(), map()) -> {ok, process_model()} | {error, term()}.
discover(Log, Options) ->
    Threshold = maps:get(threshold, Options, 0.8),

    %% Calculate dependency measures
    Dependencies = calculate_all_dependencies(Log),

    %% Filter by threshold
    Significant = lists:filter(fun({_, _, Dep}) ->
        Dep >= Threshold
    end, Dependencies),

    %% Build model from significant dependencies
    Model = build_from_dependencies(Significant, Log),

    {ok, Model}.

%% Calculate dependency measure between two activities
-spec calculate_dependency(event_log(), {binary(), binary()}) -> float().
calculate_dependency(Log, {A, B}) ->
    %% Count occurrences
    {A_B, A_Total, B_A, B_Total} = count_relation_occurrences(Log, A, B),

    %% Calculate dependency
    case A_B + B_A of
        0 -> 0.0;
        _ ->
            (A_B - B_A) / (A_B + B_A + 1)
    end.

%% Count relation occurrences
count_relation_occurrences(#event_log{traces = Traces}, A, B) ->
    lists:foldl(fun(#{events := Events}, {A_B, A_T, B_A, B_T}) ->
        Activities = [maps:get(activity, E) || E <- Events],
        As = [Act || Act <- Activities, Act =:= A],
        Bs = [Act || Act <- Activities, Act =:= B],

        %% Count A followed by B
        A_Followed_By_B = count_followed_by(Activities, A, B),
        %% Count B followed by A
        B_Followed_By_A = count_followed_by(Activities, B, A),

        {A_B + A_Followed_By_B,
         A_T + length(As),
         B_A + B_Followed_By_A,
         B_T + length(Bs)}
    end, {0, 0, 0, 0}, Traces).

%% Count A followed by B in a list
count_followed_by(Activities, A, B) ->
    count_followed_by(Activities, A, B, 0).

count_followed_by([], _A, _B, Count) -> Count;
count_followed_by([A], A, B, Count) -> Count;
count_followed_by([A, B | _], A, B, Count) -> Count + 1;
count_followed_by([_ | Rest], A, B, Count) ->
    count_followed_by(Rest, A, B, Count).
```

## REST API

### Discover Process Model

```bash
curl -X POST http://localhost:8081/api/research/partial-order/discover \
  -H "Content-Type: application/json" \
  -d '{
    "log_id": "event_log_1",
    "algorithm": "alpha",
    "options": {
      "include_loops": true,
      "merge_short_loops": true
    }
  }'
```

### Response

```json
{
  "log_id": "event_log_1",
  "algorithm": "alpha",
  "model": {
    "places": [
      {
        "id": "p1",
        "input_transitions": ["start"],
        "output_transitions": ["A", "B"]
      }
    ],
    "transitions": [
      {"id": "A", "label": "validate", "type": "visible"},
      {"id": "B", "label": "approve", "type": "visible"}
    ],
    "relations": {
      "causality": [["start", "A"], ["A", "B"]],
      "conflict": [],
      "concurrency": [["A", "B"]]
    }
  },
  "fitness": 0.95
}
```

## Use Cases

### Process Discovery

Discover the underlying process from event logs:

```erlang
{ok, Model} = alpha_miner:discover(EventLog),
#{causality := Causality} = Model#process_model.relations.
```

### Conformance Checking

Check if event log conforms to process model:

```erlang
{ok, Fitness} = yawl_partial_order:fitness(Model, EventLog).
```

### Bottleneck Analysis

Find activities with high concurrency:

```erlang
{ok, Model} = alpha_miner:discover(EventLog),
#{concurrency := Concurrent} = Model#process_model.relations,
%% High concurrency indicates potential bottlenecks
```

---

Next: [LLM Validation](llm-validation.md) | [Back to Overview](overview.md)
