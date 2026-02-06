%%% @doc Task state transition history tracker
%%%
%%% gen_server that records every task state transition in an ETS table.
%%% Allows replaying and exporting the full transition history for a task.
%%% Uses beamai_a2a_types for state validation.
-module(beamai_task_history).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, record/3, get_history/1, replay/1, export/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(HISTORY_TABLE, beamai_task_history_tab).

-record(state, {}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Record a state transition for a task.
-spec record(binary(), atom(), atom()) -> ok.
record(TaskId, OldState, NewState) ->
    gen_server:cast(?MODULE, {record, TaskId, OldState, NewState}).

%% @doc Get the full transition history for a task.
-spec get_history(binary()) -> {ok, [map()]}.
get_history(TaskId) ->
    gen_server:call(?MODULE, {get_history, TaskId}).

%% @doc Replay transitions as a list of {OldState, NewState} tuples.
-spec replay(binary()) -> {ok, [{atom(), atom()}]}.
replay(TaskId) ->
    gen_server:call(?MODULE, {replay, TaskId}).

%% @doc Export the full history for a task as a serializable map.
-spec export(binary()) -> {ok, map()}.
export(TaskId) ->
    gen_server:call(?MODULE, {export, TaskId}).

%%% gen_server callbacks

init([]) ->
    ets:new(?HISTORY_TABLE, [named_table, bag, public,
                             {keypos, 1},
                             {write_concurrency, auto},
                             {read_concurrency, true}]),
    {ok, #state{}}.

handle_call({get_history, TaskId}, _From, State) ->
    Entries = lookup_entries(TaskId),
    Maps = [entry_to_map(E) || E <- Entries],
    {reply, {ok, Maps}, State};

handle_call({replay, TaskId}, _From, State) ->
    Entries = lookup_entries(TaskId),
    Transitions = [{Old, New} || {_, Old, New, _} <- Entries],
    {reply, {ok, Transitions}, State};

handle_call({export, TaskId}, _From, State) ->
    Entries = lookup_entries(TaskId),
    ExportMap = #{
        task_id => TaskId,
        transition_count => length(Entries),
        transitions => [entry_to_map(E) || E <- Entries],
        exported_at => erlang:system_time(millisecond)
    },
    {reply, {ok, ExportMap}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({record, TaskId, OldState, NewState}, State) ->
    Ts = erlang:system_time(millisecond),
    %% Validate states using beamai_a2a_types
    OldBin = beamai_a2a_types:task_state_to_binary(OldState),
    NewBin = beamai_a2a_types:task_state_to_binary(NewState),
    Entry = {TaskId, OldState, NewState, Ts},
    ets:insert(?HISTORY_TABLE, Entry),
    ?LOG_DEBUG("Task ~s: ~s -> ~s", [TaskId, OldBin, NewBin]),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% Internal

lookup_entries(TaskId) ->
    Entries = ets:lookup(?HISTORY_TABLE, TaskId),
    lists:sort(fun({_, _, _, T1}, {_, _, _, T2}) -> T1 =< T2 end, Entries).

entry_to_map({TaskId, OldState, NewState, Timestamp}) ->
    #{task_id => TaskId,
      old_state => OldState,
      new_state => NewState,
      timestamp => Timestamp,
      terminal => beamai_a2a_types:is_terminal_state(NewState)}.
