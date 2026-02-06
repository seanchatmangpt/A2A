%%% @doc BeamAI A2A Task - gen_server implementing BeamAI-style task lifecycle
%%%
%%% This module provides a gen_server-based task management process that
%%% follows the BeamAI framework conventions. It manages task state transitions,
%%% messages, artifacts, and metadata using a map-based interface.
%%%
%%% State Machine:
%%%   submitted -> working -> completed (terminal)
%%%                        -> failed (terminal)
%%%                        -> canceled (terminal)
%%%                        -> rejected (terminal)
%%%                        -> input_required -> working
%%%                        -> auth_required -> working
%%%   Any non-terminal state -> canceled
%%%
%%% Terminal states (completed, failed, canceled, rejected) cannot transition
%%% further.
%%% @end
-module(beamai_a2a_task).
-behaviour(gen_server).

%% API
-export([
    start_link/1,
    start/1,
    get/1,
    update_status/2,
    add_message/2,
    add_artifact/2,
    cancel/1,
    to_map/1,
    can_transition/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-record(task_state, {
    id :: binary(),
    status :: atom(),
    messages = [] :: list(),
    artifacts = [] :: list(),
    metadata = #{} :: map(),
    history = [] :: list(),
    created_at :: binary(),
    updated_at :: binary()
}).

%% Terminal states that cannot transition further
-define(TERMINAL_STATES, [completed, failed, canceled, rejected]).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start a linked BeamAI task process.
%% Opts is a map that may contain:
%%   id        - binary task ID (generated if not provided)
%%   status    - initial status atom (defaults to submitted)
%%   messages  - initial message list
%%   artifacts - initial artifact list
%%   metadata  - metadata map
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

%% @doc Start a non-linked BeamAI task process.
-spec start(map()) -> {ok, pid()} | {error, term()}.
start(Opts) when is_map(Opts) ->
    gen_server:start(?MODULE, Opts, []).

%% @doc Get the current task state as a map.
-spec get(pid()) -> {ok, map()} | {error, term()}.
get(Pid) ->
    gen_server:call(Pid, get_task).

%% @doc Update the task status. Validates state transitions.
-spec update_status(pid(), atom()) -> ok | {error, term()}.
update_status(Pid, NewStatus) ->
    gen_server:call(Pid, {update_status, NewStatus}).

%% @doc Add a message to the task's message list.
-spec add_message(pid(), map()) -> ok | {error, term()}.
add_message(Pid, Message) when is_map(Message) ->
    gen_server:call(Pid, {add_message, Message}).

%% @doc Add an artifact to the task's artifact list.
-spec add_artifact(pid(), map()) -> ok | {error, term()}.
add_artifact(Pid, Artifact) when is_map(Artifact) ->
    gen_server:call(Pid, {add_artifact, Artifact}).

%% @doc Cancel the task. Fails if the task is in a terminal state.
-spec cancel(pid()) -> ok | {error, term()}.
cancel(Pid) ->
    gen_server:call(Pid, cancel).

%% @doc Convert the task state to a plain map representation.
-spec to_map(pid()) -> {ok, map()} | {error, term()}.
to_map(Pid) ->
    gen_server:call(Pid, to_map).

%% @doc Check whether a transition from CurrentStatus to NewStatus is valid.
%% This is a pure function that does not require a running process.
-spec can_transition(atom(), atom()) -> boolean().
can_transition(CurrentStatus, NewStatus) ->
    valid_transition(CurrentStatus, NewStatus).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, #task_state{}}.
init(Opts) ->
    Now = iso8601_now(),
    Id = maps:get(id, Opts, generate_id()),
    InitialStatus = maps:get(status, Opts, submitted),
    Messages = maps:get(messages, Opts, []),
    Artifacts = maps:get(artifacts, Opts, []),
    Metadata = maps:get(metadata, Opts, #{}),

    State = #task_state{
        id = Id,
        status = InitialStatus,
        messages = Messages,
        artifacts = Artifacts,
        metadata = Metadata,
        history = [{InitialStatus, Now, <<"Task created">>}],
        created_at = Now,
        updated_at = Now
    },

    logger:info("[beamai_a2a_task] Task ~s created with status ~p", [Id, InitialStatus]),
    {ok, State}.

handle_call(get_task, _From, State) ->
    Map = state_to_map(State),
    {reply, {ok, Map}, State};

handle_call({update_status, NewStatus}, _From, #task_state{status = CurrentStatus} = State) ->
    case valid_transition(CurrentStatus, NewStatus) of
        true ->
            Now = iso8601_now(),
            HistoryEntry = {NewStatus, Now, iolist_to_binary(
                io_lib:format("Status changed from ~p to ~p", [CurrentStatus, NewStatus]))},
            NewState = State#task_state{
                status = NewStatus,
                history = State#task_state.history ++ [HistoryEntry],
                updated_at = Now
            },
            logger:info("[beamai_a2a_task] Task ~s: ~p -> ~p",
                        [State#task_state.id, CurrentStatus, NewStatus]),
            {reply, ok, NewState};
        false ->
            logger:warning("[beamai_a2a_task] Task ~s: invalid transition ~p -> ~p",
                           [State#task_state.id, CurrentStatus, NewStatus]),
            {reply, {error, {invalid_transition, CurrentStatus, NewStatus}}, State}
    end;

handle_call({add_message, Message}, _From, #task_state{status = CurrentStatus} = State) ->
    case is_terminal(CurrentStatus) of
        true ->
            {reply, {error, {task_terminal, CurrentStatus}}, State};
        false ->
            Now = iso8601_now(),
            TimestampedMsg = Message#{added_at => Now},
            HistoryEntry = {message_added, Now, <<"Message added">>},
            NewState = State#task_state{
                messages = State#task_state.messages ++ [TimestampedMsg],
                history = State#task_state.history ++ [HistoryEntry],
                updated_at = Now
            },
            {reply, ok, NewState}
    end;

handle_call({add_artifact, Artifact}, _From, #task_state{status = CurrentStatus} = State) ->
    case is_terminal(CurrentStatus) andalso CurrentStatus =/= completed of
        true ->
            {reply, {error, {task_terminal, CurrentStatus}}, State};
        false ->
            Now = iso8601_now(),
            TimestampedArt = Artifact#{added_at => Now},
            HistoryEntry = {artifact_added, Now,
                           iolist_to_binary(io_lib:format("Artifact added: ~s",
                               [maps:get(name, Artifact, <<"unnamed">>)]))},
            NewState = State#task_state{
                artifacts = State#task_state.artifacts ++ [TimestampedArt],
                history = State#task_state.history ++ [HistoryEntry],
                updated_at = Now
            },
            {reply, ok, NewState}
    end;

handle_call(cancel, _From, #task_state{status = CurrentStatus} = State) ->
    case is_terminal(CurrentStatus) of
        true ->
            {reply, {error, {task_terminal, CurrentStatus}}, State};
        false ->
            Now = iso8601_now(),
            HistoryEntry = {canceled, Now,
                           iolist_to_binary(io_lib:format("Task canceled from ~p state",
                                                          [CurrentStatus]))},
            NewState = State#task_state{
                status = canceled,
                history = State#task_state.history ++ [HistoryEntry],
                updated_at = Now
            },
            logger:info("[beamai_a2a_task] Task ~s canceled from ~p",
                        [State#task_state.id, CurrentStatus]),
            {reply, ok, NewState}
    end;

handle_call(to_map, _From, State) ->
    Map = state_to_map(State),
    {reply, {ok, Map}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #task_state{id = Id, status = Status}) ->
    logger:info("[beamai_a2a_task] Task ~s (status=~p) terminating: ~p",
                [Id, Status, Reason]),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Valid state transition rules.
%% Terminal states (completed, failed, canceled, rejected) cannot transition.
%% submitted can go to working or canceled.
%% working can go to completed, failed, canceled, rejected, input_required, auth_required.
%% input_required and auth_required can go back to working or to canceled.
-spec valid_transition(atom(), atom()) -> boolean().
valid_transition(submitted, working) -> true;
valid_transition(submitted, canceled) -> true;
valid_transition(working, completed) -> true;
valid_transition(working, failed) -> true;
valid_transition(working, canceled) -> true;
valid_transition(working, rejected) -> true;
valid_transition(working, input_required) -> true;
valid_transition(working, auth_required) -> true;
valid_transition(input_required, working) -> true;
valid_transition(input_required, canceled) -> true;
valid_transition(auth_required, working) -> true;
valid_transition(auth_required, canceled) -> true;
valid_transition(_From, _To) -> false.

%% @doc Check if a state is terminal.
-spec is_terminal(atom()) -> boolean().
is_terminal(Status) ->
    lists:member(Status, ?TERMINAL_STATES).

%% @doc Convert internal state record to a plain map.
-spec state_to_map(#task_state{}) -> map().
state_to_map(#task_state{} = S) ->
    #{
        id => S#task_state.id,
        status => S#task_state.status,
        messages => S#task_state.messages,
        artifacts => S#task_state.artifacts,
        metadata => S#task_state.metadata,
        history => format_history(S#task_state.history),
        created_at => S#task_state.created_at,
        updated_at => S#task_state.updated_at
    }.

%% @doc Format history entries into maps.
-spec format_history(list()) -> list().
format_history(History) ->
    lists:map(fun({Event, Timestamp, Description}) ->
        #{event => Event, timestamp => Timestamp, description => Description}
    end, History).

%% @doc Generate a UUID-like binary identifier.
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    iolist_to_binary([A, $-, B, $-, C, $-, D, $-, E]).

%% @doc Get the current time as an ISO 8601 binary string.
-spec iso8601_now() -> binary().
iso8601_now() ->
    Now = erlang:system_time(second),
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(Now, second),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                   [Y, Mo, D, H, Mi, S])).
