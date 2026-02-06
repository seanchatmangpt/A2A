%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Definition Storage Module
%%%
%%% This module provides persistent storage for workflow definitions.
%%% It supports:
%%%
%%% - Saving and loading workflow definitions
%%% - Versioning of workflow definitions
%%% - Definition validation
%%% - Listing and searching definitions
%%% - Import/export of definitions
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_definition_storage).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Definition management
-export([
    save_definition/2,
    load_definition/1,
    delete_definition/1,
    list_definitions/0,
    list_definitions_by_pattern/1,
    search_definitions/1,
    get_definition_versions/1,
    load_definition_version/2
]).

%% API exports - Validation
-export([
    validate_definition/1,
    validate_definition_structure/1
]).

%% API exports - Import/Export
-export([
    export_definition/1,
    import_definition/1,
    export_all_definitions/0
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    definitions :: map(),
    version_index :: map(),
    table_status :: map()
}).

-record(definition, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    pattern_type :: atom(),
    config :: map(),
    version :: integer(),
    created_at :: integer(),
    updated_at :: integer(),
    created_by :: binary() | undefined,
    metadata :: map()
}).

-type definition() :: #definition{}.
-type definition_id() :: binary().

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the definition storage manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Save a workflow definition.
-spec save_definition(binary(), map()) -> {ok, definition_id()} | {error, term()}.
save_definition(Id, DefinitionMap) when is_map(DefinitionMap) ->
    gen_server:call(?MODULE, {save_definition, Id, DefinitionMap}).

%% @doc Load a workflow definition by ID.
-spec load_definition(definition_id()) -> {ok, map()} | {error, not_found}.
load_definition(Id) ->
    gen_server:call(?MODULE, {load_definition, Id}).

%% @doc Delete a workflow definition.
-spec delete_definition(definition_id()) -> ok | {error, term()}.
delete_definition(Id) ->
    gen_server:call(?MODULE, {delete_definition, Id}).

%% @doc List all workflow definitions.
-spec list_definitions() -> {ok, [map()]}.
list_definitions() ->
    gen_server:call(?MODULE, list_definitions).

%% @doc List definitions by pattern type.
-spec list_definitions_by_pattern(atom()) -> {ok, [map()]}.
list_definitions_by_pattern(PatternType) ->
    gen_server:call(?MODULE, {list_definitions_by_pattern, PatternType}).

%% @doc Search definitions by name or description.
-spec search_definitions(binary()) -> {ok, [map()]}.
search_definitions(Query) ->
    gen_server:call(?MODULE, {search_definitions, Query}).

%% @doc Get all versions of a definition.
-spec get_definition_versions(definition_id()) -> {ok, [map()]}.
get_definition_versions(Id) ->
    gen_server:call(?MODULE, {get_definition_versions, Id}).

%% @doc Load a specific version of a definition.
-spec load_definition_version(definition_id(), integer()) -> {ok, map()} | {error, term()}.
load_definition_version(Id, Version) ->
    gen_server:call(?MODULE, {load_definition_version, Id, Version}).

%% @doc Validate a workflow definition.
-spec validate_definition(map()) -> {ok, boolean(), [term()]}.
validate_definition(Definition) ->
    gen_server:call(?MODULE, {validate_definition, Definition}).

%% @doc Validate definition structure only.
-spec validate_definition_structure(map()) -> {ok, boolean(), [term()]}.
validate_definition_structure(Definition) ->
    do_validate_structure(Definition).

%% @doc Export a definition to JSON.
-spec export_definition(definition_id()) -> {ok, binary()} | {error, term()}.
export_definition(Id) ->
    gen_server:call(?MODULE, {export_definition, Id}).

%% @doc Import a definition from JSON.
-spec import_definition(binary()) -> {ok, definition_id()} | {error, term()}.
import_definition(JsonData) ->
    gen_server:call(?MODULE, {import_definition, JsonData}).

%% @doc Export all definitions.
-spec export_all_definitions() -> {ok, binary()}.
export_all_definitions() ->
    gen_server:call(?MODULE, export_all_definitions).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Ensure Mnesia is running
    case mnesia:start() of
        ok -> ok;
        {error, {already_started, _}} -> ok
    end,

    %% Create definition table if needed
    create_definition_tables(),

    %% Load existing definitions from Mnesia
    Definitions = load_definitions_from_storage(),

    State = #state{
        definitions = Definitions,
        version_index = build_version_index(Definitions),
        table_status = #{definitions => initialized}
    },

    {ok, State}.

%% @private
handle_call({save_definition, Id, DefinitionMap}, _From, State) ->
    {Reply, NewState} = do_save_definition(Id, DefinitionMap, State),
    {reply, Reply, NewState};

handle_call({load_definition, Id}, _From, State) ->
    Reply = do_load_definition(Id, State),
    {reply, Reply, State};

handle_call({delete_definition, Id}, _From, State) ->
    {Reply, NewState} = do_delete_definition(Id, State),
    {reply, Reply, NewState};

handle_call(list_definitions, _From, State) ->
    Reply = do_list_definitions(State),
    {reply, Reply, State};

handle_call({list_definitions_by_pattern, PatternType}, _From, State) ->
    Reply = do_list_definitions_by_pattern(PatternType, State),
    {reply, Reply, State};

handle_call({search_definitions, Query}, _From, State) ->
    Reply = do_search_definitions(Query, State),
    {reply, Reply, State};

handle_call({get_definition_versions, Id}, _From, State) ->
    Reply = do_get_definition_versions(Id, State),
    {reply, Reply, State};

handle_call({load_definition_version, Id, Version}, _From, State) ->
    Reply = do_load_definition_version(Id, Version, State),
    {reply, Reply, State};

handle_call({validate_definition, Definition}, _From, State) ->
    Reply = do_validate_definition(Definition, State),
    {reply, Reply, State};

handle_call({export_definition, Id}, _From, State) ->
    Reply = do_export_definition(Id, State),
    {reply, Reply, State};

handle_call({import_definition, JsonData}, _From, State) ->
    {Reply, NewState} = do_import_definition(JsonData, State),
    {reply, Reply, NewState};

handle_call(export_all_definitions, _From, State) ->
    Reply = do_export_all_definitions(State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
create_definition_tables() ->
    Table = yawl_workflow_definition,
    case mnesia:create_table(Table, [
        {attributes, record_info(fields, definition)},
        {index, [#definition.pattern_type, #definition.name]},
        {type, set},
        {disc_copies, [node()]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Table}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @private
load_definitions_from_storage() ->
    Trans = fun() ->
        mnesia:match_object(#definition{_ = '_'})
    end,
    case mnesia:transaction(Trans) of
        {atomic, Definitions} ->
            lists:foldl(fun(D, Acc) ->
                Acc#{D#definition.id => D}
            end, #{}, Definitions);
        {aborted, _} ->
            #{}
    end.

%% @private
build_version_index(Definitions) ->
    lists:foldl(fun({_Id, Definition}, Acc) ->
        PatternType = Definition#definition.pattern_type,
        Existing = maps:get(PatternType, Acc, []),
        Acc#{PatternType => [Definition#definition.id | Existing]}
    end, #{}, maps:to_list(Definitions)).

%% @private
do_save_definition(Id, DefinitionMap, State) ->
    %% Validate the definition first
    case validate_definition_structure(DefinitionMap) of
        {ok, false, Errors} ->
            {{error, {validation_failed, Errors}}, State};
        {ok, true, _} ->
            PatternType = maps_get_to_atom(pattern_type, DefinitionMap, basic_sequential),
            Name = maps_get(<<"name">>, DefinitionMap, <<"unnamed">>),
            Description = maps_get(<<"description">>, DefinitionMap, <<"">>),
            Config = maps_get(<<"config">>, DefinitionMap, #{}),

            %% Check if definition exists and get version
            CurrentVersion = case maps:get(Id, State#state.definitions, undefined) of
                undefined -> 0;
                ExistingDef -> ExistingDef#definition.version
            end,

            Now = erlang:monotonic_time(millisecond),

            Definition = #definition{
                id = Id,
                name = Name,
                description = Description,
                pattern_type = PatternType,
                config = Config,
                version = CurrentVersion + 1,
                created_at = case CurrentVersion of
                    0 -> Now;
                    _ -> (maps:get(Id, State#state.definitions))#definition.created_at
                end,
                updated_at = Now,
                created_by = maps_get(<<"created_by">>, DefinitionMap, undefined),
                metadata = maps_get(<<"metadata">>, DefinitionMap, #{})
            },

            %% Save to Mnesia
            case save_definition_to_mnesia(Definition) of
                ok ->
                    NewDefinitions = maps:put(Id, Definition, State#state.definitions),
                    NewVersionIndex = build_version_index(NewDefinitions),
                    NewState = State#state{
                        definitions = NewDefinitions,
                        version_index = NewVersionIndex
                    },
                    {{ok, Id}, NewState};
                {error, Reason} ->
                    {{error, Reason}, State}
            end
    end.

%% @private
save_definition_to_mnesia(Definition) ->
    Trans = fun() -> mnesia:write(Definition) end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @private
do_load_definition(Id, State) ->
    case maps:get(Id, State#state.definitions, undefined) of
        undefined -> {error, not_found};
        Definition -> {ok, definition_to_map(Definition)}
    end.

%% @private
do_delete_definition(Id, State) ->
    case maps:is_key(Id, State#state.definitions) of
        false ->
            {error, not_found};
        true ->
            %% Delete from Mnesia
            Trans = fun() -> mnesia:delete(yawl_workflow_definition, Id, write) end,
            case mnesia:transaction(Trans) of
                {atomic, ok} ->
                    NewDefinitions = maps:remove(Id, State#state.definitions),
                    NewVersionIndex = build_version_index(NewDefinitions),
                    NewState = State#state{
                        definitions = NewDefinitions,
                        version_index = NewVersionIndex
                    },
                    {ok, NewState};
                {aborted, Reason} ->
                    {{error, Reason}, State}
            end
    end.

%% @private
do_list_definitions(State) ->
    Definitions = maps:map(fun(_Id, Def) ->
        definition_to_summary_map(Def)
    end, State#state.definitions),
    {ok, maps:values(Definitions)}.

%% @private
do_list_definitions_by_pattern(PatternType, State) ->
    Filtered = maps:filter(fun(_Id, Def) ->
        Def#definition.pattern_type =:= PatternType
    end, State#state.definitions),
    Definitions = maps:map(fun(_Id, Def) ->
        definition_to_summary_map(Def)
    end, Filtered),
    {ok, maps:values(Definitions)}.

%% @private
do_search_definitions(Query, State) ->
    LowerQuery = binary:lowercase(Query),
    Filtered = maps:filter(fun(_Id, Def) ->
        NameMatch = binary:part(binary:lowercase(Def#definition.name),
                               0, byte_size(LowerQuery)) =:= LowerQuery,
        DescMatch = binary:part(binary:lowercase(Def#definition.description),
                               0, byte_size(LowerQuery)) =:= LowerQuery,
        NameMatch orelse DescMatch
    end, State#state.definitions),
    Definitions = maps:map(fun(_Id, Def) ->
        definition_to_summary_map(Def)
    end, Filtered),
    {ok, maps:values(Definitions)}.

%% @private
do_get_definition_versions(Id, State) ->
    case maps:get(Id, State#state.definitions, undefined) of
        undefined -> {error, not_found};
        Definition ->
            %% In a full implementation, we'd return all versions
            %% For now, return current version info
            {ok, [#{
                version => Definition#definition.version,
                created_at => Definition#definition.created_at,
                updated_at => Definition#definition.updated_at
            }]}
    end.

%% @private
do_load_definition_version(Id, Version, State) ->
    case maps:get(Id, State#state.definitions, undefined) of
        undefined -> {error, not_found};
        Definition when Definition#definition.version =:= Version ->
            {ok, definition_to_map(Definition)};
        _Definition ->
            {error, version_not_found}
    end.

%% @private
do_validate_definition(DefinitionMap, _State) ->
    case validate_definition_structure(DefinitionMap) of
        {ok, false, Errors} -> {ok, false, Errors};
        {ok, true, _} ->
            PatternType = maps_get_to_atom(pattern_type, DefinitionMap, basic_sequential),
            Config = maps_get(<<"config">>, DefinitionMap, #{}),
            Valid = yawl_patterns:validate_pattern(PatternType, Config),
            {ok, Valid, []}
    end.

%% @private
do_validate_structure(DefinitionMap) ->
    Errors = [],

    %% Check required fields
    Errors1 = case maps:is_key(<<"pattern_type">>, DefinitionMap) of
        true -> Errors;
        false -> [<<"pattern_type is required">> | Errors]
    end,

    Errors2 = case maps:is_key(<<"name">>, DefinitionMap) of
        true -> Errors1;
        false -> [<<"name is required">> | Errors1]
    end,

    %% Validate pattern type
    Errors3 = case maps_get(<<"pattern_type">>, DefinitionMap, undefined) of
        undefined -> Errors2;
        PatternTypeBin ->
            PatternType = try binary_to_existing_atom(PatternTypeBin, utf8)
            catch error:badarg -> undefined
            end,
            case PatternType of
                undefined -> [<<"invalid pattern_type">> | Errors2];
                _ ->
                    %% Check if pattern is valid - cannot use lists:member in guard with macro
                    ValidPatterns = [basic_sequential, parallel_split, parallel_join,
                                   exclusive_choice, simple_merge, iterative_loop,
                                   multi_instance, cancelation, interleaved_parallelism],
                    case lists:member(PatternType, ValidPatterns) of
                        true -> Errors2;
                        false -> [<<"unknown pattern_type">> | Errors2]
                    end
            end
    end,

    IsValid = Errors3 =:= [],
    {ok, IsValid, lists:reverse(Errors3)}.

%% @private
do_export_definition(Id, State) ->
    case maps:get(Id, State#state.definitions, undefined) of
        undefined -> {error, not_found};
        Definition ->
            Json = jiffy:encode(definition_to_map(Definition)),
            {ok, Json}
    end.

%% @private
do_import_definition(JsonData, State) ->
    try jiffy:decode(JsonData, [return_maps]) of
        DefinitionMap ->
            Id = maps_get(<<"id">>, DefinitionMap, generate_definition_id()),
            NewId = case Id of
                <<>> -> generate_definition_id();
                _ -> Id
            end,
            {Reply, NewState} = do_save_definition(NewId, DefinitionMap, State),
            {Reply, NewState}
    catch
        _:_ ->
            {{error, invalid_json}, State}
    end.

%% @private
do_export_all_definitions(State) ->
    Definitions = maps:map(fun(_Id, Def) ->
        definition_to_map(Def)
    end, State#state.definitions),
    Json = jiffyencode(#{definitions => maps:values(Definitions)}),
    {ok, Json}.

%% @private
definition_to_map(#definition{} = Def) ->
    #{
        id => Def#definition.id,
        name => Def#definition.name,
        description => Def#definition.description,
        pattern_type => Def#definition.pattern_type,
        config => Def#definition.config,
        version => Def#definition.version,
        created_at => Def#definition.created_at,
        updated_at => Def#definition.updated_at,
        created_by => Def#definition.created_by,
        metadata => Def#definition.metadata
    }.

%% @private
definition_to_summary_map(#definition{} = Def) ->
    #{
        id => Def#definition.id,
        name => Def#definition.name,
        description => Def#definition.description,
        pattern_type => Def#definition.pattern_type,
        version => Def#definition.version,
        updated_at => Def#definition.updated_at
    }.

%% @private
generate_definition_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Time = erlang:monotonic_time(millisecond),
    <<UniqueId:32, Time:32>>.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

%% @private
maps_get_to_atom(Key, Map, Default) ->
    case maps:get(Key, Map, Default) of
        Default -> Default;
        Bin when is_binary(Bin) ->
            try binary_to_existing_atom(Bin, utf8)
            catch error:badarg -> Default
            end;
        Atom when is_atom(Atom) -> Atom;
        _ -> Default
    end.

%% @private
jiffyencode(Term) ->
    jiffy:encode(Term).
