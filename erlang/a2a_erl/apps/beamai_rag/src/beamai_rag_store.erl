%%%-------------------------------------------------------------------
%%% @doc BeamAI RAG Vector Store
%%%
%%% Stores document embeddings in ETS and provides cosine similarity
%%% search. Each entry contains an embedding vector, the original
%%% text, and associated metadata.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_rag_store).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    insert/2,
    search/2,
    search/3,
    delete/1,
    count/0,
    clear/0,
    get/1,
    list_ids/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).
-define(TABLE, beamai_rag_vectors).
-define(DEFAULT_SEARCH_LIMIT, 10).

-record(vector_entry, {
    id          :: binary(),
    embedding   :: [float()],
    text        :: binary(),
    metadata    :: map(),
    inserted_at :: integer()
}).

-record(state, {
    table   :: ets:tid(),
    config  :: map(),
    count   :: non_neg_integer()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the vector store with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the vector store with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Insert a vector entry.
%% Data must contain: embedding (list of floats), text (binary),
%% and optionally metadata (map).
-spec insert(binary(), map()) -> ok | {error, term()}.
insert(Id, Data) ->
    gen_server:call(?SERVER, {insert, Id, Data}).

%% @doc Search for the most similar vectors to the query embedding.
%% Returns up to Limit results sorted by descending similarity score.
-spec search([float()], non_neg_integer()) -> {ok, [map()]} | {error, term()}.
search(QueryEmbedding, Limit) ->
    search(QueryEmbedding, Limit, #{}).

%% @doc Search with options.
%% Options:
%%   min_score - Minimum cosine similarity score (default: 0.0)
-spec search([float()], non_neg_integer(), map()) -> {ok, [map()]} | {error, term()}.
search(QueryEmbedding, Limit, Opts) ->
    gen_server:call(?SERVER, {search, QueryEmbedding, Limit, Opts}, 60000).

%% @doc Delete an entry by ID.
-spec delete(binary()) -> ok | {error, not_found}.
delete(Id) ->
    gen_server:call(?SERVER, {delete, Id}).

%% @doc Return the number of entries in the store.
-spec count() -> non_neg_integer().
count() ->
    gen_server:call(?SERVER, count).

%% @doc Clear all entries from the store.
-spec clear() -> ok.
clear() ->
    gen_server:call(?SERVER, clear).

%% @doc Get an entry by ID.
-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Id) ->
    gen_server:call(?SERVER, {get, Id}).

%% @doc List all entry IDs.
-spec list_ids() -> [binary()].
list_ids() ->
    gen_server:call(?SERVER, list_ids).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    Table = ets:new(?TABLE, [
        set, private, {keypos, #vector_entry.id}
    ]),
    State = #state{
        table = Table,
        config = Config,
        count = 0
    },
    logger:info("BeamAI RAG vector store started"),
    {ok, State}.

%% @private
handle_call({insert, Id, Data}, _From, #state{table = Table, count = Count} = State) ->
    Embedding = maps:get(embedding, Data, []),
    Text = maps:get(text, Data, <<>>),
    Metadata = maps:get(metadata, Data, #{}),
    Now = erlang:system_time(millisecond),

    case validate_embedding(Embedding) of
        ok ->
            Entry = #vector_entry{
                id = Id,
                embedding = Embedding,
                text = Text,
                metadata = Metadata,
                inserted_at = Now
            },
            IsNew = not ets:member(Table, Id),
            ets:insert(Table, Entry),
            NewCount = case IsNew of
                true -> Count + 1;
                false -> Count
            end,
            {reply, ok, State#state{count = NewCount}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({search, QueryEmbedding, Limit, Opts}, _From, #state{table = Table} = State) ->
    MinScore = maps:get(min_score, Opts, 0.0),
    try
        %% Compute cosine similarity with all stored vectors
        Results = ets:foldl(fun(#vector_entry{id = Id, embedding = Emb,
                                               text = Text, metadata = Meta}, Acc) ->
            Score = cosine_similarity(QueryEmbedding, Emb),
            case Score >= MinScore of
                true ->
                    [#{id => Id, score => Score, text => Text, metadata => Meta} | Acc];
                false ->
                    Acc
            end
        end, [], Table),

        %% Sort by score descending and take top Limit
        Sorted = lists:sort(fun(#{score := S1}, #{score := S2}) -> S1 >= S2 end, Results),
        TopResults = lists:sublist(Sorted, Limit),
        {reply, {ok, TopResults}, State}
    catch
        Class:Reason:Stack ->
            logger:error("RAG search failed: ~p:~p~n~p", [Class, Reason, Stack]),
            {reply, {error, {search_failed, Reason}}, State}
    end;

handle_call({delete, Id}, _From, #state{table = Table, count = Count} = State) ->
    case ets:member(Table, Id) of
        true ->
            ets:delete(Table, Id),
            {reply, ok, State#state{count = Count - 1}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call(count, _From, #state{count = Count} = State) ->
    {reply, Count, State};

handle_call(clear, _From, #state{table = Table} = State) ->
    ets:delete_all_objects(Table),
    {reply, ok, State#state{count = 0}};

handle_call({get, Id}, _From, #state{table = Table} = State) ->
    case ets:lookup(Table, Id) of
        [#vector_entry{embedding = Emb, text = Text, metadata = Meta, inserted_at = At}] ->
            Result = #{
                id => Id,
                embedding => Emb,
                text => Text,
                metadata => Meta,
                inserted_at => At
            },
            {reply, {ok, Result}, State};
        [] ->
            {reply, {error, not_found}, State}
    end;

handle_call(list_ids, _From, #state{table = Table} = State) ->
    Ids = ets:foldl(fun(#vector_entry{id = Id}, Acc) ->
        [Id | Acc]
    end, [], Table),
    {reply, lists:reverse(Ids), State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{table = Table}) ->
    ets:delete(Table),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Compute the cosine similarity between two vectors.
%% Returns a value between -1.0 and 1.0, where 1.0 means identical.
-spec cosine_similarity([float()], [float()]) -> float().
cosine_similarity([], _) -> 0.0;
cosine_similarity(_, []) -> 0.0;
cosine_similarity(A, B) when length(A) =/= length(B) ->
    %% Pad shorter vector with zeros
    MaxLen = max(length(A), length(B)),
    PadA = pad_vector(A, MaxLen),
    PadB = pad_vector(B, MaxLen),
    cosine_similarity_impl(PadA, PadB);
cosine_similarity(A, B) ->
    cosine_similarity_impl(A, B).

%% @private Implementation of cosine similarity.
-spec cosine_similarity_impl([float()], [float()]) -> float().
cosine_similarity_impl(A, B) ->
    {DotProduct, MagA, MagB} = lists:foldl(
        fun({Ai, Bi}, {Dot, MA, MB}) ->
            {Dot + Ai * Bi, MA + Ai * Ai, MB + Bi * Bi}
        end,
        {0.0, 0.0, 0.0},
        lists:zip(A, B)
    ),
    Denominator = math:sqrt(MagA) * math:sqrt(MagB),
    case Denominator > 0.0 of
        true -> DotProduct / Denominator;
        false -> 0.0
    end.

%% @private Pad a vector with zeros to the given length.
-spec pad_vector([float()], non_neg_integer()) -> [float()].
pad_vector(Vec, TargetLen) when length(Vec) >= TargetLen ->
    Vec;
pad_vector(Vec, TargetLen) ->
    Vec ++ lists:duplicate(TargetLen - length(Vec), 0.0).

%% @private Validate that an embedding is a proper list of numbers.
-spec validate_embedding([float()]) -> ok | {error, term()}.
validate_embedding([]) ->
    {error, empty_embedding};
validate_embedding(Embedding) when is_list(Embedding) ->
    case lists:all(fun(V) -> is_number(V) end, Embedding) of
        true -> ok;
        false -> {error, invalid_embedding_values}
    end;
validate_embedding(_) ->
    {error, embedding_not_list}.
