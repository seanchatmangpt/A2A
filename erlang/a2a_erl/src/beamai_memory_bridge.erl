%%%-------------------------------------------------------------------
%%% @doc Memory Bridge: syncs a2a_task_store and yawl_persistence
%%% data into beamai_memory via its Store and Snapshot APIs.
%%%
%%% On init creates a beamai_memory with an ETS backend.
%%% sync_tasks/0  reads a2a_task_store entries and writes them
%%% into beamai_memory:put/5.
%%% sync_workflows/0 reads yawl_persistence workflows and saves
%%% them as beamai_memory snapshots.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, sync_tasks/0, sync_workflows/0,
         query/1, get_memory/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    memory :: beamai_memory:memory(),
    store_name :: atom()
}).

-define(STORE_NAME, beamai_bridge_store).
-define(TASK_NS, [<<"a2a">>, <<"tasks">>]).
-define(WORKFLOW_NS, [<<"yawl">>, <<"workflows">>]).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec sync_tasks() -> {ok, non_neg_integer()} | {error, term()}.
sync_tasks() ->
    gen_server:call(?MODULE, sync_tasks, ?DEFAULT_TIMEOUT).

-spec sync_workflows() -> {ok, non_neg_integer()} | {error, term()}.
sync_workflows() ->
    gen_server:call(?MODULE, sync_workflows, ?DEFAULT_TIMEOUT).

-spec query(map()) -> {ok, [term()]} | {error, term()}.
query(Opts) ->
    gen_server:call(?MODULE, {query, Opts}).

-spec get_memory() -> {ok, beamai_memory:memory()}.
get_memory() ->
    gen_server:call(?MODULE, get_memory).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    {ok, _Pid} = beamai_store_ets:start_link(?STORE_NAME, #{}),
    Backend = {beamai_store_ets, ?STORE_NAME},
    case beamai_memory:new(#{backend => Backend}) of
        {ok, Memory} ->
            ?LOG_INFO("beamai_memory_bridge started with ETS backend"),
            {ok, #state{memory = Memory, store_name = ?STORE_NAME}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(sync_tasks, _From, #state{memory = Memory} = State) ->
    case a2a_task_store:list_tasks(#{}) of
        {ok, Tasks, _Token} ->
            Count = lists:foldl(fun(Task, Acc) ->
                TaskId = task_id(Task),
                Value = task_to_map(Task),
                case beamai_memory:put(Memory, ?TASK_NS, TaskId, Value, #{}) of
                    ok    -> Acc + 1;
                    _Err  -> Acc
                end
            end, 0, Tasks),
            {reply, {ok, Count}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(sync_workflows, _From, #state{memory = Memory0} = State) ->
    case yawl_persistence:list_workflows() of
        {ok, Workflows} ->
            {Count, Memory} = lists:foldl(fun(Wf, {Acc, Mem}) ->
                WfId = workflow_id(Wf),
                WfState = workflow_to_map(Wf),
                case beamai_memory:save_snapshot(Mem, WfId, WfState) of
                    {ok, _Snapshot, NewMem} -> {Acc + 1, NewMem};
                    {error, _}             -> {Acc, Mem}
                end
            end, {0, Memory0}, Workflows),
            {reply, {ok, Count}, State#state{memory = Memory}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({query, Opts}, _From, #state{memory = Memory} = State) ->
    Ns = maps:get(namespace, Opts, ?TASK_NS),
    SearchOpts = maps:without([namespace], Opts),
    Reply = beamai_memory:search(Memory, Ns, SearchOpts),
    {reply, Reply, State};

handle_call(get_memory, _From, #state{memory = Memory} = State) ->
    {reply, {ok, Memory}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

task_id(T) when is_map(T) -> maps:get(id, T, maps:get(<<"id">>, T, <<"unknown">>));
task_id(T) when is_tuple(T) -> to_bin(element(2, T)).

task_to_map(T) when is_map(T) -> T;
task_to_map(T) when is_tuple(T) -> #{record => element(1, T), data => to_bin(T)}.

workflow_id(W) when is_tuple(W) -> to_bin(element(2, W));
workflow_id(W) when is_map(W) -> maps:get(workflow_id, W, <<"unknown">>).

workflow_to_map(W) when is_map(W) -> W;
workflow_to_map(W) when is_tuple(W) -> #{record => element(1, W), data => to_bin(W)}.

to_bin(T) -> iolist_to_binary(io_lib:format("~p", [T])).
