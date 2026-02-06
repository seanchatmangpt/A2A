%%%-------------------------------------------------------------------
%%% @doc Bridge between A2A task processing and beamai process framework.
%%% Maps A2A task states (from a2a_task_statem) to beamai_a2a_types
%%% using beamai_a2a_types:binary_to_task_state/1 and
%%% task_state_to_binary/1. Tracks processes in ETS.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_process_bridge).
-behaviour(gen_server).

-export([start_link/0, start_link/1, start_process/2,
         get_process_state/1, map_a2a_state/1, map_beamai_state/1,
         sync_state/2]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-include_lib("beamai_core/include/beamai_common.hrl").

-define(SERVER, ?MODULE).
-define(PROC_TABLE, beamai_process_bridge_procs).

-record(state, {
    processes :: #{binary() => pid()},
    state_map :: #{binary() => atom()}
}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec start_process(binary(), map()) -> {ok, pid()} | {error, term()}.
start_process(TaskId, ProcessOpts) ->
    gen_server:call(?SERVER, {start_process, TaskId, ProcessOpts}, ?DEFAULT_TIMEOUT).

-spec get_process_state(binary()) -> {ok, atom()} | {error, not_found}.
get_process_state(TaskId) ->
    gen_server:call(?SERVER, {get_state, TaskId}, ?DEFAULT_TIMEOUT).

%% @doc Map A2A task state atom to beamai binary representation.
-spec map_a2a_state(atom()) -> binary().
map_a2a_state(State) -> beamai_a2a_types:task_state_to_binary(State).

%% @doc Map beamai binary task state to A2A atom.
-spec map_beamai_state(binary() | atom()) -> atom().
map_beamai_state(Bin) when is_binary(Bin) -> beamai_a2a_types:binary_to_task_state(Bin);
map_beamai_state(Atom) when is_atom(Atom) -> Atom.

-spec sync_state(binary(), atom()) -> ok.
sync_state(TaskId, NewState) ->
    gen_server:cast(?SERVER, {sync_state, TaskId, NewState}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(_Opts) ->
    ets:new(?PROC_TABLE, [named_table, public, set, {read_concurrency, true}]),
    {ok, #state{processes = #{}, state_map = #{}}}.

handle_call({start_process, TaskId, ProcessOpts}, _From, State) ->
    #state{processes = Procs, state_map = SM} = State,
    case maps:is_key(TaskId, Procs) of
        true ->
            {reply, {error, already_started}, State};
        false ->
            case beamai_process:start(ProcessOpts) of
                {ok, Pid} ->
                    _MonRef = erlang:monitor(process, Pid),
                    ets:insert(?PROC_TABLE, {TaskId, Pid}),
                    {reply, {ok, Pid},
                     State#state{processes = Procs#{TaskId => Pid},
                                 state_map = SM#{TaskId => submitted}}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;
handle_call({get_state, TaskId}, _From, #state{state_map = SM} = S) ->
    case maps:find(TaskId, SM) of
        {ok, PState} -> {reply, {ok, PState}, S};
        error -> {reply, {error, not_found}, S}
    end;
handle_call(_Request, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast({sync_state, TaskId, NewState}, #state{state_map = SM} = S) ->
    {noreply, S#state{state_map = SM#{TaskId => NewState}}};
handle_cast(_Msg, S) -> {noreply, S}.

handle_info({'DOWN', _Ref, process, Pid, Reason}, State) ->
    #state{processes = Procs, state_map = SM} = State,
    case find_task_by_pid(Pid, Procs) of
        {ok, TaskId} ->
            Terminal = case Reason of normal -> completed; _ -> failed end,
            ets:delete(?PROC_TABLE, TaskId),
            {noreply, State#state{processes = maps:remove(TaskId, Procs),
                                  state_map = SM#{TaskId => Terminal}}};
        error -> {noreply, State}
    end;
handle_info(_Info, S) -> {noreply, S}.

terminate(_Reason, _S) -> catch ets:delete(?PROC_TABLE), ok.
code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal
%%====================================================================

find_task_by_pid(Pid, Procs) ->
    maps:fold(fun(K, V, Acc) ->
        case V =:= Pid of true -> {ok, K}; false -> Acc end
    end, error, Procs).
