%%%-------------------------------------------------------------------
%%% @doc BeamAI RAG - Retrieval-Augmented Generation
%%%
%%% Provides document indexing with embeddings, similarity search,
%%% and context augmentation for LLM prompts. Uses a vector store
%%% (beamai_rag_store) for efficient cosine similarity lookups.
%%%
%%% Workflow:
%%%   1. Index documents: split into chunks, generate embeddings
%%%   2. Search: find similar chunks via cosine similarity
%%%   3. Augment: inject retrieved context into LLM prompts
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_rag).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    index/2,
    index/3,
    search/2,
    search/3,
    augment_prompt/2,
    augment_prompt/3,
    clear/0,
    stats/0
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
-define(DEFAULT_CHUNK_SIZE, 512).
-define(DEFAULT_CHUNK_OVERLAP, 64).
-define(DEFAULT_TOP_K, 5).
-define(DEFAULT_MIN_SCORE, 0.3).
-define(EMBEDDING_DIM, 384).  %% Default embedding dimension

-record(state, {
    store_pid   :: pid() | undefined,
    kernel_ref  :: atom() | pid(),
    config      :: map(),
    stats       :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the RAG server with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the RAG server with custom configuration.
%% Options:
%%   kernel_ref - BeamAI kernel for embedding generation
%%   chunk_size - Characters per chunk (default: 512)
%%   chunk_overlap - Overlap between chunks (default: 64)
%%   embedding_dim - Embedding vector dimension (default: 384)
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Index a document for retrieval.
%% DocId is a unique identifier, Content is the document text.
-spec index(binary(), binary()) -> ok | {error, term()}.
index(DocId, Content) ->
    index(DocId, Content, #{}).

%% @doc Index a document with options.
%% Options:
%%   metadata - Additional metadata to store with chunks
%%   chunk_size - Override default chunk size
%%   chunk_overlap - Override default chunk overlap
-spec index(binary(), binary(), map()) -> ok | {error, term()}.
index(DocId, Content, Opts) ->
    gen_server:call(?SERVER, {index, DocId, Content, Opts}, 120000).

%% @doc Search for documents similar to the query.
%% Returns a list of {Score, ChunkText, Metadata} tuples.
-spec search(binary(), non_neg_integer()) -> {ok, [map()]} | {error, term()}.
search(Query, TopK) ->
    search(Query, TopK, #{}).

%% @doc Search with options.
%% Options:
%%   min_score - Minimum similarity score (default: 0.3)
%%   filter - Metadata filter function
-spec search(binary(), non_neg_integer(), map()) -> {ok, [map()]} | {error, term()}.
search(Query, TopK, Opts) ->
    gen_server:call(?SERVER, {search, Query, TopK, Opts}, 60000).

%% @doc Augment a prompt with retrieved context.
%% Searches for relevant documents and prepends them to the prompt.
-spec augment_prompt(binary(), binary()) -> {ok, binary()} | {error, term()}.
augment_prompt(Query, Prompt) ->
    augment_prompt(Query, Prompt, #{}).

%% @doc Augment a prompt with options.
%% Options:
%%   top_k - Number of results to include (default: 5)
%%   min_score - Minimum similarity score
%%   template - Custom template for context injection
-spec augment_prompt(binary(), binary(), map()) -> {ok, binary()} | {error, term()}.
augment_prompt(Query, Prompt, Opts) ->
    gen_server:call(?SERVER, {augment_prompt, Query, Prompt, Opts}, 60000).

%% @doc Clear all indexed documents.
-spec clear() -> ok.
clear() ->
    gen_server:call(?SERVER, clear).

%% @doc Get indexing/search statistics.
-spec stats() -> map().
stats() ->
    gen_server:call(?SERVER, stats).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),

    %% Start the vector store
    StorePid = case beamai_rag_store:start_link() of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid;
        _ -> undefined
    end,

    State = #state{
        store_pid = StorePid,
        kernel_ref = KernelRef,
        config = Config,
        stats = #{
            documents_indexed => 0,
            chunks_indexed => 0,
            searches_performed => 0,
            prompts_augmented => 0
        }
    },
    logger:info("BeamAI RAG server started"),
    {ok, State}.

%% @private
handle_call({index, DocId, Content, Opts}, _From, State) ->
    #state{kernel_ref = KernelRef, config = Config, stats = Stats} = State,
    ChunkSize = maps:get(chunk_size, Opts,
                         maps:get(chunk_size, Config, ?DEFAULT_CHUNK_SIZE)),
    ChunkOverlap = maps:get(chunk_overlap, Opts,
                            maps:get(chunk_overlap, Config, ?DEFAULT_CHUNK_OVERLAP)),
    Metadata = maps:get(metadata, Opts, #{}),

    %% Split content into chunks
    Chunks = chunk_text(Content, ChunkSize, ChunkOverlap),

    %% Generate embeddings and store each chunk
    Results = lists:map(fun({ChunkIdx, ChunkText}) ->
        ChunkId = <<DocId/binary, "-", (integer_to_binary(ChunkIdx))/binary>>,
        Embedding = generate_embedding(KernelRef, ChunkText),
        ChunkMeta = Metadata#{
            doc_id => DocId,
            chunk_index => ChunkIdx,
            chunk_text => ChunkText,
            text_length => byte_size(ChunkText)
        },
        beamai_rag_store:insert(ChunkId, #{
            embedding => Embedding,
            text => ChunkText,
            metadata => ChunkMeta
        })
    end, lists:zip(lists:seq(1, length(Chunks)), Chunks)),

    Errors = [R || R <- Results, R =/= ok],
    case Errors of
        [] ->
            DocsIndexed = maps:get(documents_indexed, Stats, 0),
            ChunksIndexed = maps:get(chunks_indexed, Stats, 0),
            NewStats = Stats#{
                documents_indexed => DocsIndexed + 1,
                chunks_indexed => ChunksIndexed + length(Chunks)
            },
            logger:info("RAG: indexed ~s (~p chunks)", [DocId, length(Chunks)]),
            {reply, ok, State#state{stats = NewStats}};
        _ ->
            {reply, {error, {partial_index_failure, Errors}}, State}
    end;

handle_call({search, Query, TopK, Opts}, _From, State) ->
    #state{kernel_ref = KernelRef, stats = Stats} = State,
    MinScore = maps:get(min_score, Opts, ?DEFAULT_MIN_SCORE),
    FilterFun = maps:get(filter, Opts, undefined),

    %% Generate embedding for the query
    QueryEmbedding = generate_embedding(KernelRef, Query),

    %% Search the vector store
    case beamai_rag_store:search(QueryEmbedding, TopK * 2) of
        {ok, RawResults} ->
            %% Filter by minimum score and optional metadata filter
            Filtered = lists:filtermap(fun(#{score := Score} = Result) ->
                case Score >= MinScore of
                    true ->
                        case FilterFun of
                            undefined -> {true, Result};
                            Fun when is_function(Fun, 1) ->
                                case Fun(Result) of
                                    true -> {true, Result};
                                    false -> false
                                end;
                            _ -> {true, Result}
                        end;
                    false ->
                        false
                end
            end, RawResults),

            %% Take top K
            TopResults = lists:sublist(Filtered, TopK),

            Searches = maps:get(searches_performed, Stats, 0),
            NewStats = Stats#{searches_performed => Searches + 1},
            {reply, {ok, TopResults}, State#state{stats = NewStats}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({augment_prompt, Query, Prompt, Opts}, _From, State) ->
    #state{kernel_ref = KernelRef, stats = Stats} = State,
    TopK = maps:get(top_k, Opts, ?DEFAULT_TOP_K),
    MinScore = maps:get(min_score, Opts, ?DEFAULT_MIN_SCORE),
    Template = maps:get(template, Opts, default_augmentation_template()),

    %% Generate embedding for the query
    QueryEmbedding = generate_embedding(KernelRef, Query),

    %% Search for relevant context
    case beamai_rag_store:search(QueryEmbedding, TopK) of
        {ok, Results} ->
            %% Filter by minimum score
            Relevant = [R || #{score := S} = R <- Results, S >= MinScore],

            %% Build context string from results
            ContextParts = lists:map(fun(#{text := Text, score := Score}) ->
                iolist_to_binary(io_lib:format("[Score: ~.3f] ~s",
                                               [Score, Text]))
            end, Relevant),
            Context = iolist_to_binary(lists:join(<<"\n\n">>, ContextParts)),

            %% Apply template
            AugmentedPrompt = apply_template(Template, Context, Prompt),

            Augmented = maps:get(prompts_augmented, Stats, 0),
            NewStats = Stats#{prompts_augmented => Augmented + 1},
            {reply, {ok, AugmentedPrompt}, State#state{stats = NewStats}};
        {error, Reason} ->
            %% If search fails, return the original prompt
            logger:warning("RAG augmentation search failed: ~p, using original prompt", [Reason]),
            {reply, {ok, Prompt}, State}
    end;

handle_call(clear, _From, State) ->
    beamai_rag_store:clear(),
    NewStats = #{
        documents_indexed => 0,
        chunks_indexed => 0,
        searches_performed => 0,
        prompts_augmented => 0
    },
    logger:info("RAG store cleared"),
    {reply, ok, State#state{stats = NewStats}};

handle_call(stats, _From, #state{stats = Stats} = State) ->
    StoreCount = try beamai_rag_store:count()
                 catch _:_ -> 0
                 end,
    FullStats = Stats#{
        store_entries => StoreCount
    },
    {reply, FullStats, State};

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
%% Internal functions
%%====================================================================

%% @private Split text into overlapping chunks.
-spec chunk_text(binary(), pos_integer(), non_neg_integer()) -> [binary()].
chunk_text(Text, ChunkSize, Overlap) when byte_size(Text) =< ChunkSize ->
    [Text];
chunk_text(Text, ChunkSize, Overlap) ->
    chunk_text_loop(Text, ChunkSize, Overlap, []).

%% @private Chunking loop.
-spec chunk_text_loop(binary(), pos_integer(), non_neg_integer(), [binary()]) -> [binary()].
chunk_text_loop(<<>>, _ChunkSize, _Overlap, Acc) ->
    lists:reverse(Acc);
chunk_text_loop(Text, ChunkSize, Overlap, Acc) ->
    TextLen = byte_size(Text),
    case TextLen =< ChunkSize of
        true ->
            lists:reverse([Text | Acc]);
        false ->
            %% Try to find a sentence/word boundary near ChunkSize
            Chunk = find_chunk_boundary(Text, ChunkSize),
            ChunkLen = byte_size(Chunk),
            %% Calculate the start of the next chunk (with overlap)
            NextStart = max(1, ChunkLen - Overlap),
            Remaining = binary:part(Text, NextStart, TextLen - NextStart),
            chunk_text_loop(Remaining, ChunkSize, Overlap, [Chunk | Acc])
    end.

%% @private Find a good chunk boundary (sentence or word boundary).
-spec find_chunk_boundary(binary(), pos_integer()) -> binary().
find_chunk_boundary(Text, ChunkSize) ->
    TextLen = byte_size(Text),
    MaxLen = min(ChunkSize, TextLen),
    Candidate = binary:part(Text, 0, MaxLen),
    %% Try to find the last sentence boundary
    case find_last_boundary(Candidate, [<<". ">>, <<".\n">>, <<"! ">>, <<"? ">>]) of
        {ok, Pos} when Pos > ChunkSize div 2 ->
            binary:part(Candidate, 0, Pos + 1);
        _ ->
            %% Fall back to word boundary
            case find_last_boundary(Candidate, [<<" ">>, <<"\n">>, <<"\t">>]) of
                {ok, Pos} when Pos > ChunkSize div 2 ->
                    binary:part(Candidate, 0, Pos);
                _ ->
                    Candidate
            end
    end.

%% @private Find the last occurrence of any boundary string.
-spec find_last_boundary(binary(), [binary()]) -> {ok, pos_integer()} | not_found.
find_last_boundary(Text, Boundaries) ->
    Positions = lists:filtermap(fun(Boundary) ->
        case find_last_occurrence(Text, Boundary) of
            nomatch -> false;
            Pos -> {true, Pos}
        end
    end, Boundaries),
    case Positions of
        [] -> not_found;
        _ -> {ok, lists:max(Positions)}
    end.

%% @private Find the last occurrence of a pattern in binary.
-spec find_last_occurrence(binary(), binary()) -> non_neg_integer() | nomatch.
find_last_occurrence(Text, Pattern) ->
    find_last_occ(Text, Pattern, 0, nomatch).

-spec find_last_occ(binary(), binary(), non_neg_integer(), non_neg_integer() | nomatch) ->
    non_neg_integer() | nomatch.
find_last_occ(Text, Pattern, Start, LastFound) ->
    case binary:match(Text, Pattern, [{scope, {Start, byte_size(Text) - Start}}]) of
        {Pos, Len} ->
            find_last_occ(Text, Pattern, Pos + Len, Pos);
        nomatch ->
            LastFound
    end.

%% @private Generate an embedding vector for text.
%% If the kernel supports embedding generation, use it.
%% Otherwise, generate a deterministic hash-based pseudo-embedding.
-spec generate_embedding(atom() | pid(), binary()) -> [float()].
generate_embedding(KernelRef, Text) ->
    %% Try to use the kernel's embedding capability
    try
        case whereis(KernelRef) of
            undefined ->
                hash_embedding(Text);
            _Pid ->
                case beamai_kernel:invoke_tool(KernelRef, <<"embed">>, #{text => Text}, #{}) of
                    {ok, Embedding} when is_list(Embedding) ->
                        Embedding;
                    _ ->
                        hash_embedding(Text)
                end
        end
    catch
        _:_ -> hash_embedding(Text)
    end.

%% @private Generate a deterministic pseudo-embedding from text using hashing.
%% This is a fallback when no embedding model is available.
-spec hash_embedding(binary()) -> [float()].
hash_embedding(Text) ->
    %% Use SHA-256 repeatedly to fill the embedding dimension
    Seed = crypto:hash(sha256, Text),
    generate_hash_vector(Seed, ?EMBEDDING_DIM, []).

%% @private Generate a vector of floats from a hash seed.
-spec generate_hash_vector(binary(), non_neg_integer(), [float()]) -> [float()].
generate_hash_vector(_Seed, 0, Acc) ->
    %% Normalize the vector
    normalize_vector(lists:reverse(Acc));
generate_hash_vector(Seed, Remaining, Acc) ->
    SeedSize = byte_size(Seed),
    case Remaining =< SeedSize * 8 div 32 of
        true ->
            %% Extract floats from current seed
            Floats = extract_floats(Seed, Remaining),
            generate_hash_vector(<<>>, 0, lists:reverse(Floats) ++ Acc);
        false ->
            Floats = extract_floats(Seed, SeedSize * 8 div 32),
            NewSeed = crypto:hash(sha256, Seed),
            generate_hash_vector(NewSeed, Remaining - length(Floats),
                                 lists:reverse(Floats) ++ Acc)
    end.

%% @private Extract float values from a binary.
-spec extract_floats(binary(), non_neg_integer()) -> [float()].
extract_floats(<<>>, _) -> [];
extract_floats(_, 0) -> [];
extract_floats(<<Val:32/signed-integer, Rest/binary>>, N) ->
    %% Convert 32-bit integer to float in [-1, 1] range
    Float = Val / 2147483647.0,
    [Float | extract_floats(Rest, N - 1)];
extract_floats(<<_/binary>>, _) ->
    [].

%% @private Normalize a vector to unit length.
-spec normalize_vector([float()]) -> [float()].
normalize_vector([]) -> [];
normalize_vector(Vec) ->
    Magnitude = math:sqrt(lists:sum([V * V || V <- Vec])),
    case Magnitude > 0.0 of
        true -> [V / Magnitude || V <- Vec];
        false -> Vec
    end.

%% @private Apply the augmentation template.
-spec apply_template(binary(), binary(), binary()) -> binary().
apply_template(Template, Context, Prompt) ->
    T1 = binary:replace(Template, <<"{{context}}">>, Context, [global]),
    binary:replace(T1, <<"{{prompt}}">>, Prompt, [global]).

%% @private Default augmentation template.
-spec default_augmentation_template() -> binary().
default_augmentation_template() ->
    <<"Use the following context to help answer the question. ",
      "If the context is not relevant, answer based on your knowledge.\n\n",
      "Context:\n{{context}}\n\n",
      "Question: {{prompt}}">>.
