%%% @doc Adapter over existing a2a_task_store ETS
%%%
%%% Provides a beamai-compatible map interface on top of the legacy
%%% a2a_task_store ETS tables, translating between record and map formats.
-module(beamai_task_store_adapter).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

-export([store/1, lookup/1, delete/1, list/0, list/1, update/2]).

%% @doc Store a beamai-format task map into the legacy ETS store.
-spec store(map()) -> ok | {error, term()}.
store(#{id := TaskId, context_id := CtxId} = TaskMap) ->
    Task = map_to_record(TaskMap),
    a2a_task_store:update_task(Task).

%% @doc Lookup a task by ID, returning a beamai-compatible map.
-spec lookup(binary()) -> {ok, map()} | {error, not_found}.
lookup(TaskId) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} -> {ok, record_to_map(Task)};
        {error, not_found} -> {error, not_found}
    end.

%% @doc Delete a task from the store.
-spec delete(binary()) -> ok.
delete(TaskId) ->
    a2a_task_store:delete_task(TaskId).

%% @doc List all tasks as beamai-format maps.
-spec list() -> {ok, [map()]}.
list() ->
    list(#{}).

%% @doc List tasks with a filter map. Supported keys: status, context_id.
-spec list(map()) -> {ok, [map()]}.
list(Filter) ->
    Opts = filter_to_opts(Filter),
    case a2a_task_store:list_tasks(Opts) of
        {ok, Tasks, _NextToken} ->
            {ok, [record_to_map(T) || T <- Tasks]};
        _ ->
            {ok, []}
    end.

%% @doc Update specific fields of an existing task.
-spec update(binary(), map()) -> ok | {error, not_found}.
update(TaskId, Fields) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            Updated = apply_updates(Task, Fields),
            a2a_task_store:update_task(Updated);
        {error, not_found} ->
            {error, not_found}
    end.

%%% Internal helpers

record_to_map(#task{id = Id, context_id = Ctx, status = St,
                    artifacts = Arts, history = Hist, metadata = Meta}) ->
    #{id => Id,
      context_id => Ctx,
      status => St#task_status.state,
      status_message => St#task_status.message,
      status_timestamp => St#task_status.timestamp,
      artifacts => [artifact_to_map(A) || A <- Arts],
      history => [message_to_map(M) || M <- Hist],
      metadata => Meta}.

map_to_record(#{id := Id, context_id := Ctx} = M) ->
    State = maps:get(status, M, submitted),
    Now = erlang:system_time(millisecond),
    #task{id = Id, context_id = Ctx,
          status = #task_status{state = State, timestamp = Now},
          artifacts = [],
          history = [],
          metadata = maps:get(metadata, M, #{})}.

artifact_to_map(#artifact{artifact_id = Id, name = N, description = D,
                          parts = Ps, metadata = Meta}) ->
    #{artifact_id => Id, name => N, description => D,
      parts => [part_to_map(P) || P <- Ps], metadata => Meta}.

message_to_map(#message{message_id = Id, role = R, parts = Ps,
                        context_id = Ctx, task_id = Tid}) ->
    #{message_id => Id, role => R, context_id => Ctx,
      task_id => Tid, parts => [part_to_map(P) || P <- Ps]}.

part_to_map(#part{content = C, metadata = M, filename = F, media_type = Mt}) ->
    #{content => C, metadata => M, filename => F, media_type => Mt}.

filter_to_opts(Filter) ->
    Base = #{page_size => 1000, include_artifacts => true},
    F1 = case maps:find(status, Filter) of
             {ok, S} -> Base#{status => S};
             error -> Base
         end,
    case maps:find(context_id, Filter) of
        {ok, C} -> F1#{context_id => C};
        error -> F1
    end.

apply_updates(Task, Fields) ->
    T1 = case maps:find(status, Fields) of
             {ok, NewState} ->
                 Now = erlang:system_time(millisecond),
                 Task#task{status = #task_status{state = NewState,
                                                 timestamp = Now}};
             error -> Task
         end,
    case maps:find(metadata, Fields) of
        {ok, NewMeta} -> T1#task{metadata = NewMeta};
        error -> T1
    end.
