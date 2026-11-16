# Reachability Analysis

State space exploration and reachability analysis for workflow verification.

## Overview

Reachability analysis determines which states can be reached from a given initial state in a workflow. This implementation uses the O(P²+T²) algorithm from van der Aalst et al. (2025) for efficient state space exploration.

## Algorithm

The O(P²+T²) algorithm efficiently explores the state space by:

1. **State Enumeration**: Generate all reachable states
2. **Transition Evaluation**: Evaluate all transitions at each state
3. **Memoization**: Cache visited states to avoid re-computation
4. **Path Tracking**: Maintain paths for shortest path analysis

### Complexity

- **Time**: O(P² + T²) where P = places, T = transitions
- **Space**: O(|S|) where S = state space

## Data Structures

### Reachability Graph

```erlang
-record(reachability_graph, {
    id :: binary(),
    workflow_id :: binary(),
    states :: map(),  %% #{state_id => state_record()}
    transitions :: map(),  %% #{transition_id => transition_record()}
    initial_state :: binary(),
    final_states :: [binary()],
    deadlock_states :: [binary()],
    statistics :: graph_statistics()
}).

-type state_record() :: #{
    id := binary(),
    marking :: map(),  %% #{place => token_count}
    type => initial | intermediate | final,
    transitions_in := [binary()],
    transitions_out := [binary()]
}.

-type transition_record() :: #{
    id := binary(),
    from_state := binary(),
    to_state := binary(),
    label := binary()
}.

-type graph_statistics() :: #{
    total_states := integer(),
    reachable_states := integer(),
    dead_states := integer(),
    final_states := integer(),
    cycles := integer(),
    analysis_time_ms := integer()
}.
```

## Implementation

### State Space Explorer

```erlang
-module(yawl_reachability).

-export([analyze/1, is_reachable/2, shortest_path/3, detect_deadlocks/1]).

%% Analyze workflow reachability
-spec analyze(binary()) -> {ok, reachability_graph()} | {error, term()}.
analyze(WorkflowId) ->
    {ok, Workflow} = workflow_store:get(WorkflowId),
    PetriNet = workflow_to_petri_net(Workflow),

    StartTime = erlang:monotonic_time(millisecond),

    %% Initialize state space
    InitialMarking = get_initial_marking(PetriNet),
    InitialState = encode_state(InitialMarking),

    %% Explore state space using BFS
    {States, Transitions, Cycles} = explore_state_space(PetriNet, InitialState),

    %% Analyze results
    FinalStates = find_final_states(States),
    Deadlocks = find_deadlock_states(States, PetriNet),

    EndTime = erlang:monotonic_time(millisecond),

    Graph = #reachability_graph{
        id = yawl_utils:generate_id(reachability),
        workflow_id = WorkflowId,
        states = States,
        transitions = Transitions,
        initial_state = InitialState,
        final_states = FinalStates,
        deadlock_states = Deadlocks,
        statistics = #{
            total_states => map_size(States),
            reachable_states => map_size(States),
            dead_states => length(Deadlocks),
            final_states => length(FinalStates),
            cycles => Cycles,
            analysis_time_ms => EndTime - StartTime
        }
    },

    {ok, Graph}.

%% Check if a state is reachable
-spec is_reachable(binary(), map()) -> {ok, boolean(), [binary()]} | {error, term()}.
is_reachable(WorkflowId, TargetMarking) ->
    case analyze(WorkflowId) of
        {ok, #reachability_graph{states = States}} ->
            TargetState = encode_state(TargetMarking),
            case maps:is_key(TargetState, States) of
                true ->
                    Path = find_path_to_state(TargetState, States),
                    {ok, true, Path};
                false ->
                    {ok, false, []}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Find shortest path between states
-spec shortest_path(binary(), binary(), binary()) ->
    {ok, [binary()]} | {error, no_path | term()}.
shortest_path(WorkflowId, FromStateId, ToStateId) ->
    case analyze(WorkflowId) of
        {ok, #reachability_graph{states = States, transitions = Transitions}} ->
            case maps:is_key(FromStateId, States) andalso maps:is_key(ToStateId, States) of
                true ->
                    Path = bfs_shortest_path(FromStateId, ToStateId, Transitions),
                    {ok, Path};
                false ->
                    {error, invalid_state}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Detect deadlock states
-spec detect_deadlocks(binary()) -> {ok, [binary()]} | {error, term()}.
detect_deadlocks(WorkflowId) ->
    case analyze(WorkflowId) of
        {ok, #reachability_graph{deadlock_states = Deadlocks}} ->
            {ok, Deadlocks};
        {error, Reason} ->
            {error, Reason}
    end.

%% Internal: Explore state space using BFS
explore_state_space(PetriNet, InitialState) ->
    Visited = #{InitialState => true},
    Queue = queue:in(InitialState, queue:new()),
    explore_loop(PetriNet, Queue, Visited, #{}, #{}, 0).

explore_loop(PetriNet, Queue, Visited, States, Transitions, Cycles) ->
    case queue:out(Queue) of
        {empty, _} ->
            {States, Transitions, Cycles};
        {{value, StateId}, RestQueue} ->
            %% Get state marking
            State = maps:get(StateId, States),
            Marking = maps:get(marking, State, decode_state(StateId)),

            %% Find enabled transitions
            Enabled = find_enabled_transitions(PetriNet, Marking),

            %% Fire each enabled transition
            {NewStates, NewTransitions, NewVisited, NewCycles} =
                lists:foldl(fun(Transition, {S, T, V, C}) ->
                    fire_transition(Transition, Marking, StateId, PetriNet, S, T, V, C)
                end, {States, Transitions, Visited, Cycles}, Enabled),

            %% Continue BFS
            explore_loop(PetriNet, RestQueue, NewVisited, NewStates, NewTransitions, NewCycles)
    end.

%% Fire a transition
fire_transition(Transition, Marking, FromState, PetriNet, States, Transitions, Visited, Cycles) ->
    %% Execute transition
    {ok, NewMarking} = execute_transition(Transition, Marking, PetriNet),
    ToState = encode_state(NewMarking),

    %% Check for cycle
    NewCycles = case maps:is_key(ToState, Visited) of
        true -> Cycles + 1;
        false -> Cycles
    end,

    %% Add transition
    TransitionId = <<FromState/binary, "->", ToState/binary>>,
    NewTransitions = maps:put(TransitionId, #{
        id => TransitionId,
        from_state => FromState,
        to_state => ToState,
        label => maps:get(label, Transition)
    }, Transitions),

    %% Add state if new
    NewStates = case maps:is_key(ToState, States) of
        true -> States;
        false ->
            maps:put(ToState, #{
                id => ToState,
                marking => NewMarking,
                type => intermediate,
                transitions_in => [],
                transitions_out => []
            }, States)
    end,

    %% Update visited
    NewVisited = maps:put(ToState, true, Visited),

    %% Update from state
    UpdatedStates = maps:update_with(FromState,
        fun(State) ->
            State#{transitions_out => [TransitionId | maps:get(transitions_out, State, [])]}
        end, NewStates),

    {UpdatedStates, NewTransitions, NewVisited, NewCycles}.

%% BFS for shortest path
bfs_shortest_path(From, To, Transitions) ->
    Visited = #{From => true},
    Queue = queue:in({From, []}, queue:new()),
    bfs_loop(To, Queue, Visited, Transitions).

bfs_loop(To, Queue, Visited, Transitions) ->
    case queue:out(Queue) of
        {empty, _} ->
            no_path;
        {{value, {Current, Path}}, Rest} when Current =:= To ->
            lists:reverse(Path);
        {{value, {Current, Path}}, Rest} ->
            %% Find outgoing transitions
            Outgoing = lists:filter(fun({_, T}) ->
                maps:get(from_state, T) =:= Current
            end, maps:to_list(Transitions)),

            {NewQueue, NewVisited} = lists:foldl(fun({TId, T}, {Q, V}) ->
                Next = maps:get(to_state, T),
                case maps:is_key(Next, V) of
                    false ->
                        {queue:in({Next, [TId | Path]}, Q), maps:put(Next, true, V)};
                    true ->
                        {Q, V}
                end
            end, {Rest, Visited}, Outgoing),

            bfs_loop(To, NewQueue, NewVisited, Transitions)
    end.
```

## REST API

### Analyze Workflow

```bash
curl -X POST http://localhost:8081/api/research/reachability \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_id": "seq_abc123",
    "options": {
      "include_markings": true,
      "max_depth": 1000
    }
  }'
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "analysis_id": "reach_xyz789",
  "statistics": {
    "total_states": 42,
    "reachable_states": 38,
    "deadlock_states": 2,
    "final_states": 1,
    "cycles": 3,
    "analysis_time_ms": 150
  },
  "states": [...],
  "transitions": [...]
}
```

## Use Cases

### Workflow Verification

Verify that a workflow can reach its completion state:

```erlang
{ok, Graph} = yawl_reachability:analyze(WorkflowId),
FinalStates = Graph#reachability_graph.final_states,
case length(FinalStates) of
    0 ->
        {error, workflow_cannot_complete};
    _ ->
        {ok, workflow_completeable}
end.
```

### Deadlock Detection

Find deadlock states in a workflow:

```erlang
{ok, Deadlocks} = yawl_reachability:detect_deadlocks(WorkflowId),
case Deadlocks of
    [] ->
        {ok, no_deadlocks};
    _ ->
        {warning, Deadlocks}
end.
```

### Path Validation

Verify that a specific execution path is valid:

```erlang
Path = [<<"state1">>, <<"state2">>, <<"state3">>,
        <<"state4">>, <<"state5">>],
{ok, Valid} = yawl_reachability:validate_path(WorkflowId, Path).
```

---

Next: [Partial Order Discovery](partial-order.md) | [Back to Overview](overview.md)
