-module(demo_a2a_task_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1, get_task/1, put_task/2, delete_task/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    ets_table = undefined :: ets:tid() | undefined,
    max_size = 10000 :: integer(),
    metrics = #{}
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

get_task(TaskId) ->
    gen_server:call(?MODULE, {get_task, TaskId}).

put_task(Task, Ttl) ->
    gen_server:call(?MODULE, {put_task, Task, Ttl}).

delete_task(TaskId) ->
    gen_server:call(?MODULE, {delete_task, TaskId}).

init(Args) ->
    State = init_state(#state{}, Args),
    {ok, State}.

handle_call({get_task, TaskId}, _From, State) ->
    case ets:lookup(State#state.ets_table, TaskId) of
        [Task] -> {reply, Task, State};
        [] -> {reply, undefined, State}
    end;

handle_call({put_task, Task, Ttl}, _From, State) ->
    TaskId = Task#task.id,
    ets:insert(State#state.ets_table, {TaskId, Task, Ttl}),
    {reply, ok, State};

handle_call({delete_task, TaskId}, _From, State) ->
    ets:delete(State#state.ets_table, TaskId),
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    ets:delete(State#state.ets_table),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

init_state(#state{} = State, Args) ->
    maps:fold(fun init_arg/3, State, Args).

init_arg(ets_table, Tid, State) ->
    State#state{ets_table = Tid};

init_arg(max_size, Max, State) ->
    State#state{max_size = Max};

init_arg(_Key, _Value, State) ->
    State.
