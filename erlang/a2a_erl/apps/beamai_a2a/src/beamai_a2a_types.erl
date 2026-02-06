%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Type Definitions and Validation
%%%
%%% Defines canonical type helpers for the A2A protocol within the
%%% BeamAI framework.  Provides state-transition validation, terminal
%%% state checks, message-role validation, and part-kind classification.
%%%
%%% Task states: submitted, working, input_required, auth_required,
%%%              completed, failed, canceled, rejected
%%%
%%% Message roles: user, agent
%%%
%%% Part types: text, file, data
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_types).

%% API - Task states
-export([
    task_state/1,
    is_terminal/1,
    is_interrupted/1,
    can_transition/2,
    terminal_states/0,
    interrupted_states/0,
    all_states/0
]).

%% API - Message roles
-export([
    message_role/1,
    valid_role/1
]).

%% API - Part kinds
-export([
    part_kind/1,
    valid_part_kind/1
]).

%% API - Validation
-export([
    validate_task_state/1,
    validate_message_role/1,
    validate_part/1
]).

%%====================================================================
%% Type definitions
%%====================================================================

-type task_state() :: submitted | working | input_required |
                      auth_required | completed | failed |
                      canceled | rejected.

-type message_role() :: user | agent.

-type part_kind() :: text | file | data.

-export_type([task_state/0, message_role/0, part_kind/0]).

%%====================================================================
%% Task state functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Normalise a task-state representation to a canonical atom.
%%
%% Accepts atoms, binaries (in either camelCase JSON form or lowercase
%% atom form), and returns the corresponding atom.
%% @end
%%--------------------------------------------------------------------
-spec task_state(atom() | binary()) -> task_state() | {error, invalid_state}.
task_state(submitted)         -> submitted;
task_state(working)           -> working;
task_state(input_required)    -> input_required;
task_state(auth_required)     -> auth_required;
task_state(completed)         -> completed;
task_state(failed)            -> failed;
task_state(canceled)          -> canceled;
task_state(rejected)          -> rejected;
%% Binary representations (JSON wire format)
task_state(<<"submitted">>)      -> submitted;
task_state(<<"working">>)        -> working;
task_state(<<"input-required">>) -> input_required;
task_state(<<"input_required">>) -> input_required;
task_state(<<"auth-required">>)  -> auth_required;
task_state(<<"auth_required">>)  -> auth_required;
task_state(<<"completed">>)      -> completed;
task_state(<<"failed">>)         -> failed;
task_state(<<"canceled">>)       -> canceled;
task_state(<<"rejected">>)       -> rejected;
%% ProtoJSON SCREAMING_SNAKE_CASE format (matches existing a2a_json)
task_state(<<"TASK_STATE_SUBMITTED">>)      -> submitted;
task_state(<<"TASK_STATE_WORKING">>)        -> working;
task_state(<<"TASK_STATE_COMPLETED">>)      -> completed;
task_state(<<"TASK_STATE_FAILED">>)         -> failed;
task_state(<<"TASK_STATE_CANCELED">>)       -> canceled;
task_state(<<"TASK_STATE_INPUT_REQUIRED">>) -> input_required;
task_state(<<"TASK_STATE_REJECTED">>)       -> rejected;
task_state(<<"TASK_STATE_AUTH_REQUIRED">>)  -> auth_required;
task_state(_Other)            -> {error, invalid_state}.

%%--------------------------------------------------------------------
%% @doc Return true if the given state is terminal (no further
%% transitions allowed).
%% @end
%%--------------------------------------------------------------------
-spec is_terminal(task_state()) -> boolean().
is_terminal(completed) -> true;
is_terminal(failed)    -> true;
is_terminal(canceled)  -> true;
is_terminal(rejected)  -> true;
is_terminal(_)         -> false.

%%--------------------------------------------------------------------
%% @doc Return true if the given state is an interrupted/waiting state.
%% @end
%%--------------------------------------------------------------------
-spec is_interrupted(task_state()) -> boolean().
is_interrupted(input_required) -> true;
is_interrupted(auth_required)  -> true;
is_interrupted(_)              -> false.

%%--------------------------------------------------------------------
%% @doc Check whether a transition from `From' to `To' is valid
%% according to the A2A protocol specification.
%%
%% Returns `true' if the transition is allowed, `false' otherwise.
%%
%% Valid transitions:
%%   submitted      -> working
%%   working        -> completed | failed | canceled | rejected |
%%                     input_required | auth_required
%%   input_required -> working | canceled
%%   auth_required  -> working | canceled
%%   terminal       -> (none)
%% @end
%%--------------------------------------------------------------------
-spec can_transition(task_state(), task_state()) -> boolean().
can_transition(submitted, working)              -> true;
can_transition(working, completed)              -> true;
can_transition(working, failed)                 -> true;
can_transition(working, canceled)               -> true;
can_transition(working, rejected)               -> true;
can_transition(working, input_required)         -> true;
can_transition(working, auth_required)          -> true;
can_transition(input_required, working)         -> true;
can_transition(input_required, canceled)        -> true;
can_transition(auth_required, working)          -> true;
can_transition(auth_required, canceled)         -> true;
can_transition(_From, _To)                      -> false.

%%--------------------------------------------------------------------
%% @doc Return the list of all terminal states.
%% @end
%%--------------------------------------------------------------------
-spec terminal_states() -> [task_state()].
terminal_states() ->
    [completed, failed, canceled, rejected].

%%--------------------------------------------------------------------
%% @doc Return the list of all interrupted states.
%% @end
%%--------------------------------------------------------------------
-spec interrupted_states() -> [task_state()].
interrupted_states() ->
    [input_required, auth_required].

%%--------------------------------------------------------------------
%% @doc Return the list of all valid task states.
%% @end
%%--------------------------------------------------------------------
-spec all_states() -> [task_state()].
all_states() ->
    [submitted, working, input_required, auth_required,
     completed, failed, canceled, rejected].

%%====================================================================
%% Message role functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Normalise a message role to its canonical atom form.
%% @end
%%--------------------------------------------------------------------
-spec message_role(atom() | binary()) -> message_role() | {error, invalid_role}.
message_role(user)           -> user;
message_role(agent)          -> agent;
message_role(<<"user">>)     -> user;
message_role(<<"agent">>)    -> agent;
message_role(<<"ROLE_USER">>)  -> user;
message_role(<<"ROLE_AGENT">>) -> agent;
message_role(_)              -> {error, invalid_role}.

%%--------------------------------------------------------------------
%% @doc Return true if the argument is a valid message role atom.
%% @end
%%--------------------------------------------------------------------
-spec valid_role(term()) -> boolean().
valid_role(user)  -> true;
valid_role(agent) -> true;
valid_role(_)     -> false.

%%====================================================================
%% Part kind functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Classify a part representation and return its kind atom.
%%
%% Accepts both the tuple form used in a2a.hrl records and the map
%% form used in BeamAI JSON payloads.
%% @end
%%--------------------------------------------------------------------
-spec part_kind(tuple() | map()) -> part_kind() | {error, unknown_part}.
%% Tuple form from #part.content
part_kind({text, _})    -> text;
part_kind({raw, _})     -> file;
part_kind({url, _})     -> file;
part_kind({data, _})    -> data;
%% Map form from JSON
part_kind(#{<<"text">> := _})  -> text;
part_kind(#{<<"raw">> := _})   -> file;
part_kind(#{<<"url">> := _})   -> file;
part_kind(#{<<"data">> := _})  -> data;
part_kind(_)                   -> {error, unknown_part}.

%%--------------------------------------------------------------------
%% @doc Return true if the argument is a valid part kind atom.
%% @end
%%--------------------------------------------------------------------
-spec valid_part_kind(term()) -> boolean().
valid_part_kind(text) -> true;
valid_part_kind(file) -> true;
valid_part_kind(data) -> true;
valid_part_kind(_)    -> false.

%%====================================================================
%% Validation helpers
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Validate that a value is a valid task state.
%% Returns `ok' or `{error, {invalid_task_state, Value}}'.
%% @end
%%--------------------------------------------------------------------
-spec validate_task_state(term()) -> ok | {error, {invalid_task_state, term()}}.
validate_task_state(State) ->
    case task_state(State) of
        {error, _} -> {error, {invalid_task_state, State}};
        _Valid     -> ok
    end.

%%--------------------------------------------------------------------
%% @doc Validate that a value is a valid message role.
%% Returns `ok' or `{error, {invalid_message_role, Value}}'.
%% @end
%%--------------------------------------------------------------------
-spec validate_message_role(term()) -> ok | {error, {invalid_message_role, term()}}.
validate_message_role(Role) ->
    case message_role(Role) of
        {error, _} -> {error, {invalid_message_role, Role}};
        _Valid     -> ok
    end.

%%--------------------------------------------------------------------
%% @doc Validate that a map or tuple represents a valid part.
%% Returns `ok' or `{error, {invalid_part, Value}}'.
%% @end
%%--------------------------------------------------------------------
-spec validate_part(term()) -> ok | {error, {invalid_part, term()}}.
validate_part(Part) ->
    case part_kind(Part) of
        {error, _} -> {error, {invalid_part, Part}};
        _Valid     -> ok
    end.
