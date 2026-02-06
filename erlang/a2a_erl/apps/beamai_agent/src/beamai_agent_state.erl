%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent State Management
%%%
%%% Tracks agent lifecycle states and validates state transitions.
%%% Agent states: idle, thinking, tool_calling, waiting_input, error.
%%%
%%% State transition diagram:
%%%   idle -> thinking
%%%   thinking -> tool_calling | idle | waiting_input | error
%%%   tool_calling -> thinking | idle | error
%%%   waiting_input -> thinking | idle
%%%   error -> idle (reset)
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_state).

%% API
-export([
    new/0,
    transition/2,
    get/1,
    is_terminal/1,
    can_transition/2,
    valid_states/0,
    describe/1
]).

-type agent_state() :: idle | thinking | tool_calling | waiting_input | error.
-type state_record() :: #{
    current := agent_state(),
    previous := agent_state() | undefined,
    entered_at := integer(),
    transition_count := non_neg_integer(),
    history := [{agent_state(), integer()}]
}.

-export_type([agent_state/0, state_record/0]).

%%====================================================================
%% API
%%====================================================================

%% @doc Create a new agent state record, starting in the idle state.
-spec new() -> state_record().
new() ->
    Now = erlang:system_time(millisecond),
    #{
        current => idle,
        previous => undefined,
        entered_at => Now,
        transition_count => 0,
        history => [{idle, Now}]
    }.

%% @doc Attempt a state transition. Returns {ok, NewState} if the
%% transition is valid, or {error, Reason} if not.
-spec transition(state_record(), agent_state()) ->
    {ok, state_record()} | {error, {invalid_transition, agent_state(), agent_state()}}.
transition(#{current := Current} = StateRec, Target) ->
    case can_transition(Current, Target) of
        true ->
            Now = erlang:system_time(millisecond),
            History = maps:get(history, StateRec, []),
            Count = maps:get(transition_count, StateRec, 0),
            NewStateRec = StateRec#{
                current => Target,
                previous => Current,
                entered_at => Now,
                transition_count => Count + 1,
                history => History ++ [{Target, Now}]
            },
            {ok, NewStateRec};
        false ->
            {error, {invalid_transition, Current, Target}}
    end.

%% @doc Get the current agent state.
-spec get(state_record()) -> agent_state().
get(#{current := Current}) ->
    Current.

%% @doc Check if the given state is a terminal state.
%% Only `error' is considered terminal (requires explicit reset).
-spec is_terminal(agent_state()) -> boolean().
is_terminal(error) -> true;
is_terminal(_) -> false.

%% @doc Check whether a transition from From to To is allowed.
-spec can_transition(agent_state(), agent_state()) -> boolean().
%% From idle
can_transition(idle, thinking)          -> true;
%% From thinking
can_transition(thinking, tool_calling)  -> true;
can_transition(thinking, idle)          -> true;
can_transition(thinking, waiting_input) -> true;
can_transition(thinking, error)         -> true;
%% From tool_calling
can_transition(tool_calling, thinking)  -> true;
can_transition(tool_calling, idle)      -> true;
can_transition(tool_calling, error)     -> true;
%% From waiting_input
can_transition(waiting_input, thinking) -> true;
can_transition(waiting_input, idle)     -> true;
%% From error (reset)
can_transition(error, idle)             -> true;
%% All others
can_transition(_, _)                    -> false.

%% @doc Return all valid agent states.
-spec valid_states() -> [agent_state()].
valid_states() ->
    [idle, thinking, tool_calling, waiting_input, error].

%% @doc Return a human-readable description of a state.
-spec describe(agent_state()) -> binary().
describe(idle) ->
    <<"Agent is idle, ready for input">>;
describe(thinking) ->
    <<"Agent is processing/reasoning about input">>;
describe(tool_calling) ->
    <<"Agent is executing tool calls">>;
describe(waiting_input) ->
    <<"Agent is waiting for additional user input">>;
describe(error) ->
    <<"Agent encountered an error">>;
describe(_Unknown) ->
    <<"Unknown agent state">>.
