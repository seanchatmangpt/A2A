%%% @doc BeamAI Task Store Adapter
%%%
%%% Provides a BeamAI-compatible map-based interface over the existing
%%% a2a_task_store ETS storage. This adapter translates between the
%%% A2A record-based format (#task{}) stored in ETS and the map-based
%%% format expected by BeamAI framework consumers.
%%%
%%% The adapter does NOT create its own storage -- it delegates all
%%% persistence to the existing a2a_task_store module, translating
%%% records to/from maps at the boundary.
%%%
%%% Usage:
%%%   ok = beamai_task_store_adapter:store(#{id => <<"t1">>, ...}).
%%%   {ok, Map} = beamai_task_store_adapter:lookup(<<"t1">>).
%%%   ok = beamai_task_store_adapter:delete(<<"t1">>).
%%% @end
-module(beamai_task_store_adapter).

-include("a2a.hrl").

%% API
-export([
    store/1,
    lookup/1,
    delete/1,
    list/0,
    list/1,
    update/2,
    search/1
]).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Store a task from a BeamAI-format map.
%% Translates the map to an A2A #task{} record and persists it via
%% a2a_task_store:update_task/1.
-spec store(map()) -> ok | {error, term()}.
store(TaskMap) when is_map(TaskMap) ->
    try
        Task = map_to_task_record(TaskMap),
        a2a_task_store:update_task(Task),
        ok
    catch
        Class:Reason:Stack ->
            logger:error("[beamai_task_store_adapter] store failed: ~p:~p~n~p",
                         [Class, Reason, Stack]),
            {error, {store_failed, Reason}}
    end;
store(_) ->
    {error, invalid_task_map}.

%% @doc Look up a task by ID and return it as a BeamAI map.
-spec lookup(binary()) -> {ok, map()} | {error, not_found} | {error, term()}.
lookup(TaskId) when is_binary(TaskId) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            {ok, task_record_to_map(Task)};
        {error, not_found} ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end;
lookup(_) ->
    {error, invalid_task_id}.

%% @doc Delete a task by ID.
-spec delete(binary()) -> ok | {error, term()}.
delete(TaskId) when is_binary(TaskId) ->
    a2a_task_store:delete_task(TaskId);
delete(_) ->
    {error, invalid_task_id}.

%% @doc List all tasks as BeamAI maps (no filtering).
-spec list() -> {ok, [map()]} | {error, term()}.
list() ->
    list(#{}).

%% @doc List tasks with filtering options, returning BeamAI maps.
%%
%% Supported filter keys (matching a2a_task_store:list_tasks/1):
%%   context_id              - filter by context
%%   status                  - filter by task state atom
%%   page_size               - integer page size (default 50)
%%   page_token              - pagination token binary
%%   status_timestamp_after  - minimum status timestamp
%%   include_artifacts       - boolean (default false)
%%   history_length          - integer or undefined
-spec list(map()) -> {ok, [map()], binary()} | {error, term()}.
list(Opts) when is_map(Opts) ->
    try
        {ok, Tasks, NextToken} = a2a_task_store:list_tasks(Opts),
        BeamAIMaps = lists:map(fun task_record_to_map/1, Tasks),
        {ok, BeamAIMaps, NextToken}
    catch
        Class:Reason:Stack ->
            logger:error("[beamai_task_store_adapter] list failed: ~p:~p~n~p",
                         [Class, Reason, Stack]),
            {error, {list_failed, Reason}}
    end;
list(_) ->
    {error, invalid_opts}.

%% @doc Update specific fields of a stored task.
%% Looks up the task, applies the updates, and stores it back.
%%
%% Updates is a map of field names to new values:
%%   status    - new status atom
%%   metadata  - new or merged metadata map
%%   artifacts - new artifact list (replaces existing)
%%   messages  - new message list (replaces existing history)
-spec update(binary(), map()) -> ok | {error, term()}.
update(TaskId, Updates) when is_binary(TaskId), is_map(Updates) ->
    case lookup(TaskId) of
        {ok, CurrentMap} ->
            UpdatedMap = apply_updates(CurrentMap, Updates),
            store(UpdatedMap);
        {error, Reason} ->
            {error, Reason}
    end;
update(_, _) ->
    {error, invalid_arguments}.

%% @doc Search for tasks matching a criteria map.
%%
%% Supported search criteria:
%%   status       - atom() match on task status
%%   context_id   - binary() match on context ID
%%   metadata_key - {Key, Value} match on a metadata entry
%%   has_artifact - boolean() filter tasks that have artifacts
%%   created_after - integer() timestamp filter
-spec search(map()) -> {ok, [map()]} | {error, term()}.
search(Criteria) when is_map(Criteria) ->
    try
        %% Build list_tasks options from search criteria
        ListOpts = build_list_opts(Criteria),
        {ok, Tasks, _NextToken} = a2a_task_store:list_tasks(ListOpts),

        %% Convert to maps
        Maps = lists:map(fun task_record_to_map/1, Tasks),

        %% Apply additional filters that list_tasks doesn't support natively
        Filtered = apply_search_filters(Maps, Criteria),

        {ok, Filtered}
    catch
        Class:Reason:Stack ->
            logger:error("[beamai_task_store_adapter] search failed: ~p:~p~n~p",
                         [Class, Reason, Stack]),
            {error, {search_failed, Reason}}
    end;
search(_) ->
    {error, invalid_criteria}.

%%% ============================================================================
%%% Internal Functions - Record/Map Translation
%%% ============================================================================

%% @doc Convert a BeamAI task map to an A2A #task{} record.
-spec map_to_task_record(map()) -> #task{}.
map_to_task_record(Map) ->
    Id = maps:get(id, Map),
    ContextId = maps:get(context_id, Map, maps:get(context_id,
                    maps:get(metadata, Map, #{}), generate_id())),
    Status = maps:get(status, Map, submitted),
    StatusTimestamp = maps:get(status_timestamp, Map, erlang:system_time(millisecond)),
    Artifacts = maps:get(artifacts, Map, []),
    Messages = maps:get(messages, Map, []),
    Metadata = maps:get(metadata, Map, #{}),

    %% Build the status record
    TaskStatus = #task_status{
        state = Status,
        timestamp = StatusTimestamp
    },

    %% Convert message maps to records
    HistoryRecords = lists:map(fun convert_message_map_to_record/1, Messages),

    %% Convert artifact maps to records
    ArtifactRecords = lists:map(fun convert_artifact_map_to_record/1, Artifacts),

    #task{
        id = Id,
        context_id = ContextId,
        status = TaskStatus,
        artifacts = ArtifactRecords,
        history = HistoryRecords,
        metadata = Metadata
    }.

%% @doc Convert an A2A #task{} record to a BeamAI task map.
-spec task_record_to_map(#task{}) -> map().
task_record_to_map(#task{} = Task) ->
    #task{
        id = Id,
        context_id = ContextId,
        status = #task_status{state = StatusState, timestamp = Timestamp, message = StatusMsg},
        artifacts = Artifacts,
        history = History,
        metadata = Metadata
    } = Task,

    StatusMsgMap = case StatusMsg of
        undefined -> undefined;
        Msg when is_tuple(Msg), element(1, Msg) =:= message ->
            convert_message_record_to_map(Msg);
        Other -> Other
    end,

    #{
        id => Id,
        context_id => ContextId,
        status => StatusState,
        status_timestamp => Timestamp,
        status_message => StatusMsgMap,
        artifacts => lists:map(fun convert_artifact_record_to_map/1, Artifacts),
        messages => lists:map(fun convert_message_record_to_map/1, History),
        metadata => Metadata
    }.

%% @doc Convert a message map to a #message{} record.
-spec convert_message_map_to_record(map() | term()) -> term().
convert_message_map_to_record(Msg) when is_map(Msg) ->
    Parts = lists:map(fun convert_part_map_to_record/1,
                      maps:get(parts, Msg, [])),
    #message{
        message_id = maps:get(message_id, Msg, undefined),
        context_id = maps:get(context_id, Msg, undefined),
        task_id = maps:get(task_id, Msg, undefined),
        role = maps:get(role, Msg, user),
        parts = Parts,
        metadata = maps:get(metadata, Msg, #{})
    };
convert_message_map_to_record(Other) ->
    Other.

%% @doc Convert a #message{} record to a map.
-spec convert_message_record_to_map(term()) -> map().
convert_message_record_to_map(#message{} = Msg) ->
    #message{
        message_id = MsgId,
        context_id = CtxId,
        task_id = TaskId,
        role = Role,
        parts = Parts,
        metadata = Meta
    } = Msg,
    #{
        message_id => MsgId,
        context_id => CtxId,
        task_id => TaskId,
        role => Role,
        parts => lists:map(fun convert_part_record_to_map/1, Parts),
        metadata => Meta
    };
convert_message_record_to_map(Other) ->
    Other.

%% @doc Convert a part map to a #part{} record.
-spec convert_part_map_to_record(map() | term()) -> term().
convert_part_map_to_record(Part) when is_map(Part) ->
    #part{
        content = maps:get(content, Part, {text, <<>>}),
        metadata = maps:get(metadata, Part, #{}),
        filename = maps:get(filename, Part, undefined),
        media_type = maps:get(media_type, Part, undefined)
    };
convert_part_map_to_record(Other) ->
    Other.

%% @doc Convert a #part{} record to a map.
-spec convert_part_record_to_map(term()) -> map().
convert_part_record_to_map(#part{} = P) ->
    Base = #{
        content => P#part.content,
        metadata => P#part.metadata
    },
    B2 = case P#part.filename of
        undefined -> Base;
        Fn -> Base#{filename => Fn}
    end,
    case P#part.media_type of
        undefined -> B2;
        Mt -> B2#{media_type => Mt}
    end;
convert_part_record_to_map(Other) ->
    Other.

%% @doc Convert an artifact map to an #artifact{} record.
-spec convert_artifact_map_to_record(map() | term()) -> term().
convert_artifact_map_to_record(Art) when is_map(Art) ->
    Parts = lists:map(fun convert_part_map_to_record/1,
                      maps:get(parts, Art, [])),
    #artifact{
        artifact_id = maps:get(artifact_id, Art, undefined),
        name = maps:get(name, Art, undefined),
        description = maps:get(description, Art, undefined),
        parts = Parts,
        metadata = maps:get(metadata, Art, #{})
    };
convert_artifact_map_to_record(Other) ->
    Other.

%% @doc Convert an #artifact{} record to a map.
-spec convert_artifact_record_to_map(term()) -> map().
convert_artifact_record_to_map(#artifact{} = Art) ->
    Base = #{
        artifact_id => Art#artifact.artifact_id,
        parts => lists:map(fun convert_part_record_to_map/1, Art#artifact.parts),
        metadata => Art#artifact.metadata
    },
    B2 = case Art#artifact.name of
        undefined -> Base;
        N -> Base#{name => N}
    end,
    case Art#artifact.description of
        undefined -> B2;
        D -> B2#{description => D}
    end;
convert_artifact_record_to_map(Other) ->
    Other.

%%% ============================================================================
%%% Internal Functions - Update and Search
%%% ============================================================================

%% @doc Apply updates to a task map.
-spec apply_updates(map(), map()) -> map().
apply_updates(CurrentMap, Updates) ->
    Now = erlang:system_time(millisecond),

    %% Apply status update
    Map1 = case maps:get(status, Updates, undefined) of
        undefined -> CurrentMap;
        NewStatus -> CurrentMap#{status => NewStatus, status_timestamp => Now}
    end,

    %% Apply metadata update (merge, don't replace)
    Map2 = case maps:get(metadata, Updates, undefined) of
        undefined -> Map1;
        NewMeta when is_map(NewMeta) ->
            OldMeta = maps:get(metadata, Map1, #{}),
            Map1#{metadata => maps:merge(OldMeta, NewMeta)};
        _ -> Map1
    end,

    %% Apply artifacts update (replace)
    Map3 = case maps:get(artifacts, Updates, undefined) of
        undefined -> Map2;
        NewArtifacts when is_list(NewArtifacts) ->
            Map2#{artifacts => NewArtifacts};
        _ -> Map2
    end,

    %% Apply messages update (replace history)
    Map4 = case maps:get(messages, Updates, undefined) of
        undefined -> Map3;
        NewMessages when is_list(NewMessages) ->
            Map3#{messages => NewMessages};
        _ -> Map3
    end,

    Map4.

%% @doc Build list_tasks options from search criteria.
-spec build_list_opts(map()) -> map().
build_list_opts(Criteria) ->
    Opts0 = #{
        page_size => maps:get(page_size, Criteria, 1000),
        include_artifacts => true
    },
    Opts1 = case maps:get(status, Criteria, undefined) of
        undefined -> Opts0;
        Status -> Opts0#{status => Status}
    end,
    Opts2 = case maps:get(context_id, Criteria, undefined) of
        undefined -> Opts1;
        CtxId -> Opts1#{context_id => CtxId}
    end,
    case maps:get(created_after, Criteria, undefined) of
        undefined -> Opts2;
        Timestamp -> Opts2#{status_timestamp_after => Timestamp}
    end.

%% @doc Apply additional search filters that the underlying store doesn't support.
-spec apply_search_filters([map()], map()) -> [map()].
apply_search_filters(Maps, Criteria) ->
    lists:filter(fun(Map) ->
        check_metadata_key(Map, Criteria) andalso
        check_has_artifact(Map, Criteria)
    end, Maps).

%% @doc Check metadata_key filter.
-spec check_metadata_key(map(), map()) -> boolean().
check_metadata_key(Map, Criteria) ->
    case maps:get(metadata_key, Criteria, undefined) of
        undefined ->
            true;
        {Key, Value} ->
            Metadata = maps:get(metadata, Map, #{}),
            maps:get(Key, Metadata, undefined) =:= Value;
        _ ->
            true
    end.

%% @doc Check has_artifact filter.
-spec check_has_artifact(map(), map()) -> boolean().
check_has_artifact(Map, Criteria) ->
    case maps:get(has_artifact, Criteria, undefined) of
        undefined ->
            true;
        true ->
            Artifacts = maps:get(artifacts, Map, []),
            length(Artifacts) > 0;
        false ->
            Artifacts = maps:get(artifacts, Map, []),
            length(Artifacts) =:= 0;
        _ ->
            true
    end.

%% @doc Generate a UUID-like binary identifier.
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    iolist_to_binary([A, $-, B, $-, C, $-, D, $-, E]).
