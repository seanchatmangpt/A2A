%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Buffer
%%%
%%% Provides buffer management for conversation context and streaming
%%% data. Implements a bounded circular buffer with configurable
%%% eviction strategies:
%%%
%%%   - Sliding window: removes oldest items when full (FIFO)
%%%   - Priority-based: retains high-priority items, evicts lowest
%%%   - Token-aware: tracks estimated token count and trims to limit
%%%
%%% Buffers are lightweight, pure data structures (no gen_server
%%% needed for basic operations). They can be stored in the memory
%%% store or used inline within agent conversation flows.
%%%
%%% Each buffer item has:
%%%   - content: the actual data
%%%   - priority: integer, higher = more important (default: 0)
%%%   - tokens: estimated token count (default: 0)
%%%   - timestamp: insertion time
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_buffer).

%% API - Buffer creation and manipulation
-export([
    new/1,
    new/0,
    add/2,
    add/3,
    get/1,
    trim/2,
    size/1,
    to_list/1,
    from_list/2,
    is_full/1,
    clear/1,
    peek/1,
    pop/1,
    token_count/1,
    trim_to_tokens/2,
    merge/2,
    filter/2,
    map/2
]).

%% Types
-export_type([buffer/0, buffer_opts/0, buffer_item/0]).

-record(buffer_item, {
    content    :: term(),
    priority   :: integer(),
    tokens     :: non_neg_integer(),
    timestamp  :: integer(),
    metadata   :: map()
}).

-record(buffer, {
    items      :: queue:queue(#buffer_item{}),
    max_size   :: pos_integer(),
    max_tokens :: pos_integer() | infinity,
    strategy   :: sliding | priority,
    size       :: non_neg_integer(),
    total_tokens :: non_neg_integer()
}).

-type buffer() :: #buffer{}.
-type buffer_opts() :: #{
    max_size => pos_integer(),
    max_tokens => pos_integer() | infinity,
    strategy => sliding | priority
}.
-type buffer_item() :: #buffer_item{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Create a new buffer with default settings (max 1000 items, sliding window).
-spec new() -> buffer().
new() ->
    new(#{}).

%% @doc Create a new buffer with custom options.
%% Options:
%%   max_size: maximum number of items (default: 1000)
%%   max_tokens: maximum total token count (default: infinity)
%%   strategy: sliding | priority (default: sliding)
-spec new(buffer_opts()) -> buffer().
new(Opts) ->
    MaxSize = maps:get(max_size, Opts,
                       beamai_memory_app:get_config(max_buffer_size, 1000)),
    MaxTokens = maps:get(max_tokens, Opts, infinity),
    Strategy = maps:get(strategy, Opts, sliding),

    #buffer{
        items = queue:new(),
        max_size = MaxSize,
        max_tokens = MaxTokens,
        strategy = Strategy,
        size = 0,
        total_tokens = 0
    }.

%% @doc Add an item to the buffer. If full, applies the eviction strategy.
-spec add(buffer(), term()) -> buffer().
add(Buffer, Content) ->
    add(Buffer, Content, #{}).

%% @doc Add an item with options: #{priority => integer(), tokens => integer(), metadata => map()}.
-spec add(buffer(), term(), map()) -> buffer().
add(Buffer, Content, Opts) ->
    Now = erlang:system_time(millisecond),
    Priority = maps:get(priority, Opts, 0),
    Tokens = maps:get(tokens, Opts, estimate_tokens(Content)),
    Meta = maps:get(metadata, Opts, #{}),

    Item = #buffer_item{
        content = Content,
        priority = Priority,
        tokens = Tokens,
        timestamp = Now,
        metadata = Meta
    },

    %% Add item and apply eviction if necessary
    Buffer1 = enqueue_item(Buffer, Item),
    Buffer2 = enforce_size_limit(Buffer1),
    enforce_token_limit(Buffer2).

%% @doc Get all items from the buffer as a list of content values (oldest first).
-spec get(buffer()) -> [term()].
get(Buffer) ->
    Items = queue:to_list(Buffer#buffer.items),
    [Item#buffer_item.content || Item <- Items].

%% @doc Trim the buffer to at most N items, keeping the most recent.
-spec trim(buffer(), pos_integer()) -> buffer().
trim(Buffer, MaxItems) when MaxItems >= Buffer#buffer.size ->
    Buffer;
trim(Buffer, MaxItems) ->
    Items = queue:to_list(Buffer#buffer.items),
    %% Keep the most recent MaxItems
    Kept = case Buffer#buffer.strategy of
        sliding ->
            %% Keep the tail (most recent)
            lists:nthtail(length(Items) - MaxItems, Items);
        priority ->
            %% Keep highest priority
            Sorted = lists:sort(fun(A, B) ->
                A#buffer_item.priority >= B#buffer_item.priority
            end, Items),
            lists:sublist(Sorted, MaxItems)
    end,
    rebuild_buffer(Buffer, Kept).

%% @doc Get the number of items in the buffer.
-spec size(buffer()) -> non_neg_integer().
size(Buffer) ->
    Buffer#buffer.size.

%% @doc Convert the buffer to a list of maps with full metadata.
-spec to_list(buffer()) -> [map()].
to_list(Buffer) ->
    Items = queue:to_list(Buffer#buffer.items),
    lists:map(fun item_to_map/1, Items).

%% @doc Create a buffer from a list of content items.
-spec from_list(buffer_opts(), [term()]) -> buffer().
from_list(Opts, ContentList) ->
    Buffer = new(Opts),
    lists:foldl(fun(Content, Buf) ->
        add(Buf, Content)
    end, Buffer, ContentList).

%% @doc Check if the buffer is at capacity.
-spec is_full(buffer()) -> boolean().
is_full(Buffer) ->
    Buffer#buffer.size >= Buffer#buffer.max_size.

%% @doc Clear all items from the buffer.
-spec clear(buffer()) -> buffer().
clear(Buffer) ->
    Buffer#buffer{
        items = queue:new(),
        size = 0,
        total_tokens = 0
    }.

%% @doc Peek at the oldest item without removing it.
-spec peek(buffer()) -> {ok, term()} | empty.
peek(Buffer) ->
    case queue:is_empty(Buffer#buffer.items) of
        true -> empty;
        false ->
            {{value, Item}, _} = queue:out(Buffer#buffer.items),
            {ok, Item#buffer_item.content}
    end.

%% @doc Remove and return the oldest item.
-spec pop(buffer()) -> {{ok, term()}, buffer()} | {empty, buffer()}.
pop(Buffer) ->
    case queue:is_empty(Buffer#buffer.items) of
        true ->
            {empty, Buffer};
        false ->
            {{value, Item}, NewQueue} = queue:out(Buffer#buffer.items),
            NewBuffer = Buffer#buffer{
                items = NewQueue,
                size = Buffer#buffer.size - 1,
                total_tokens = Buffer#buffer.total_tokens - Item#buffer_item.tokens
            },
            {{ok, Item#buffer_item.content}, NewBuffer}
    end.

%% @doc Get the total estimated token count of all items.
-spec token_count(buffer()) -> non_neg_integer().
token_count(Buffer) ->
    Buffer#buffer.total_tokens.

%% @doc Trim the buffer to fit within a token limit, removing oldest items first.
-spec trim_to_tokens(buffer(), pos_integer()) -> buffer().
trim_to_tokens(Buffer, MaxTokens) when Buffer#buffer.total_tokens =< MaxTokens ->
    Buffer;
trim_to_tokens(Buffer, MaxTokens) ->
    %% Remove oldest items until under the token limit
    case queue:is_empty(Buffer#buffer.items) of
        true ->
            Buffer;
        false ->
            {{value, Item}, NewQueue} = queue:out(Buffer#buffer.items),
            NewBuffer = Buffer#buffer{
                items = NewQueue,
                size = Buffer#buffer.size - 1,
                total_tokens = Buffer#buffer.total_tokens - Item#buffer_item.tokens
            },
            case NewBuffer#buffer.total_tokens =< MaxTokens of
                true -> NewBuffer;
                false -> trim_to_tokens(NewBuffer, MaxTokens)
            end
    end.

%% @doc Merge two buffers. Items from Buffer2 are appended to Buffer1.
%% The resulting buffer respects Buffer1's size and token limits.
-spec merge(buffer(), buffer()) -> buffer().
merge(Buffer1, Buffer2) ->
    Items2 = queue:to_list(Buffer2#buffer.items),
    lists:foldl(fun(Item, Buf) ->
        add(Buf, Item#buffer_item.content, #{
            priority => Item#buffer_item.priority,
            tokens => Item#buffer_item.tokens,
            metadata => Item#buffer_item.metadata
        })
    end, Buffer1, Items2).

%% @doc Filter buffer items, keeping only those for which Fun(Content) returns true.
-spec filter(buffer(), fun((term()) -> boolean())) -> buffer().
filter(Buffer, Fun) ->
    Items = queue:to_list(Buffer#buffer.items),
    Kept = lists:filter(fun(Item) -> Fun(Item#buffer_item.content) end, Items),
    rebuild_buffer(Buffer, Kept).

%% @doc Transform buffer items by applying Fun to each content value.
-spec map(buffer(), fun((term()) -> term())) -> buffer().
map(Buffer, Fun) ->
    Items = queue:to_list(Buffer#buffer.items),
    Mapped = lists:map(fun(Item) ->
        NewContent = Fun(Item#buffer_item.content),
        NewTokens = estimate_tokens(NewContent),
        Item#buffer_item{
            content = NewContent,
            tokens = NewTokens
        }
    end, Items),
    rebuild_buffer(Buffer, Mapped).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Add an item to the queue.
enqueue_item(Buffer, Item) ->
    NewQueue = queue:in(Item, Buffer#buffer.items),
    Buffer#buffer{
        items = NewQueue,
        size = Buffer#buffer.size + 1,
        total_tokens = Buffer#buffer.total_tokens + Item#buffer_item.tokens
    }.

%% @private Enforce the maximum item count.
enforce_size_limit(Buffer) when Buffer#buffer.size =< Buffer#buffer.max_size ->
    Buffer;
enforce_size_limit(Buffer) ->
    case Buffer#buffer.strategy of
        sliding ->
            %% Remove oldest
            {{value, Removed}, NewQueue} = queue:out(Buffer#buffer.items),
            enforce_size_limit(Buffer#buffer{
                items = NewQueue,
                size = Buffer#buffer.size - 1,
                total_tokens = Buffer#buffer.total_tokens - Removed#buffer_item.tokens
            });
        priority ->
            %% Remove lowest priority item
            Items = queue:to_list(Buffer#buffer.items),
            {LowestItem, RestItems} = remove_lowest_priority(Items),
            NewQueue = queue:from_list(RestItems),
            enforce_size_limit(Buffer#buffer{
                items = NewQueue,
                size = Buffer#buffer.size - 1,
                total_tokens = Buffer#buffer.total_tokens - LowestItem#buffer_item.tokens
            })
    end.

%% @private Enforce the maximum token count.
enforce_token_limit(#buffer{max_tokens = infinity} = Buffer) ->
    Buffer;
enforce_token_limit(Buffer) when Buffer#buffer.total_tokens =< Buffer#buffer.max_tokens ->
    Buffer;
enforce_token_limit(Buffer) ->
    case queue:is_empty(Buffer#buffer.items) of
        true ->
            Buffer;
        false ->
            {{value, Removed}, NewQueue} = queue:out(Buffer#buffer.items),
            NewBuffer = Buffer#buffer{
                items = NewQueue,
                size = Buffer#buffer.size - 1,
                total_tokens = Buffer#buffer.total_tokens - Removed#buffer_item.tokens
            },
            enforce_token_limit(NewBuffer)
    end.

%% @private Find and remove the lowest priority item from a list.
remove_lowest_priority([Single]) ->
    {Single, []};
remove_lowest_priority(Items) ->
    {Lowest, _} = lists:foldl(fun(Item, {MinItem, MinPrio}) ->
        case Item#buffer_item.priority < MinPrio of
            true -> {Item, Item#buffer_item.priority};
            false -> {MinItem, MinPrio}
        end
    end, {hd(Items), (hd(Items))#buffer_item.priority}, Items),
    Rest = lists:delete(Lowest, Items),
    {Lowest, Rest}.

%% @private Rebuild a buffer from a list of items.
rebuild_buffer(Buffer, ItemList) ->
    NewQueue = queue:from_list(ItemList),
    TotalTokens = lists:foldl(fun(Item, Acc) ->
        Acc + Item#buffer_item.tokens
    end, 0, ItemList),
    Buffer#buffer{
        items = NewQueue,
        size = length(ItemList),
        total_tokens = TotalTokens
    }.

%% @private Convert a buffer item to a map.
item_to_map(#buffer_item{} = Item) ->
    #{
        content => Item#buffer_item.content,
        priority => Item#buffer_item.priority,
        tokens => Item#buffer_item.tokens,
        timestamp => Item#buffer_item.timestamp,
        metadata => Item#buffer_item.metadata
    }.

%% @private Estimate token count for content.
%% Uses a simple heuristic: ~4 characters per token for text,
%% or a fixed estimate for non-text data.
estimate_tokens(Content) when is_binary(Content) ->
    max(1, byte_size(Content) div 4);
estimate_tokens(Content) when is_list(Content) ->
    try
        %% Assume it might be a string
        max(1, length(Content) div 4)
    catch
        _:_ -> 10
    end;
estimate_tokens(Content) when is_map(Content) ->
    %% Estimate based on the number of keys
    max(1, map_size(Content) * 5);
estimate_tokens(_) ->
    10. %% Default estimate for unknown types
