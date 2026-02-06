%%%-------------------------------------------------------------------
%%% @doc BeamAI Tool Middleware Pipeline.
%%%
%%% Provides a middleware pipeline for tool execution with:
%%% - Pre-execution hooks (logging, validation, authorization)
%%% - Post-execution hooks (formatting, caching, auditing)
%%% - Error handling middleware
%%% - Chainable middleware composition
%%% - Priority-based ordering
%%%
%%% Middleware functions receive and return a context map containing
%%% tool_name, args, context, and result (for post-execution).
%%% A middleware can short-circuit by returning {error, Reason}.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tool_middleware).

-export([
    chain/1,
    add/2,
    execute/3,
    wrap/2,
    logging_middleware/0,
    timing_middleware/0,
    validation_middleware/0,
    caching_middleware/1
]).

%%====================================================================
%% Type Definitions
%%====================================================================

-type middleware_fun() :: fun((map()) -> map() | {error, term()}).
-type middleware_def() :: #{
    name := binary(),
    priority => integer(),
    stage => pre | post | both,
    function := middleware_fun()
}.
-type middleware_chain() :: [middleware_fun() | middleware_def()].
-type handler_fun() :: fun((map()) -> {ok, term()} | {error, term()}).

-export_type([middleware_fun/0, middleware_def/0, middleware_chain/0]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Create a middleware chain from a list of middleware functions or defs.
%% The chain is sorted by priority (lower number = earlier execution).
-spec chain([middleware_fun() | middleware_def()]) -> middleware_chain().
chain(Middlewares) ->
    %% Normalize all entries to middleware defs
    Normalized = lists:map(fun normalize_middleware/1, Middlewares),
    %% Sort by priority
    Sorted = lists:sort(fun(A, B) ->
        PrioA = maps:get(priority, A, 100),
        PrioB = maps:get(priority, B, 100),
        PrioA =< PrioB
    end, Normalized),
    Sorted.

%% @doc Add a middleware to an existing chain.
-spec add(middleware_chain(), middleware_fun() | middleware_def()) -> middleware_chain().
add(Chain, Middleware) ->
    Normalized = normalize_middleware(Middleware),
    %% Insert in priority order
    insert_by_priority(Chain, Normalized).

%% @doc Execute a middleware chain around a handler function.
%% Pre-middlewares are run before the handler; post-middlewares after.
%% If any pre-middleware returns {error, Reason}, the handler is skipped.
-spec execute(middleware_chain(), map(), handler_fun()) ->
    {ok, term()} | {error, term()}.
execute(Chain, InitialCtx, Handler) ->
    %% Separate pre and post middlewares
    {PreMiddlewares, PostMiddlewares} = partition_middlewares(Chain),

    %% Run pre-execution middlewares
    case run_pre_middlewares(PreMiddlewares, InitialCtx) of
        {ok, PreCtx} ->
            %% Execute the handler
            case Handler(PreCtx) of
                {ok, Result} ->
                    %% Run post-execution middlewares
                    PostCtx = PreCtx#{result => Result},
                    case run_post_middlewares(PostMiddlewares, PostCtx) of
                        {ok, FinalCtx} ->
                            {ok, maps:get(result, FinalCtx, Result)};
                        {error, _} = Err ->
                            Err
                    end;
                {error, _} = Err ->
                    %% Run post-middlewares with error context for logging/cleanup
                    PostCtx = InitialCtx#{error => Err},
                    catch run_post_middlewares(PostMiddlewares, PostCtx),
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

%% @doc Wrap a handler function with a middleware, creating a new handler.
-spec wrap(middleware_fun(), handler_fun()) -> handler_fun().
wrap(Middleware, Handler) ->
    fun(Ctx) ->
        case Middleware(Ctx) of
            {error, _} = Err ->
                Err;
            ModifiedCtx when is_map(ModifiedCtx) ->
                Handler(ModifiedCtx)
        end
    end.

%%====================================================================
%% Built-in Middlewares
%%====================================================================

%% @doc Create a logging middleware that logs tool invocations.
-spec logging_middleware() -> middleware_def().
logging_middleware() ->
    #{
        name => <<"logging">>,
        priority => 10,
        stage => both,
        function => fun(Ctx) ->
            ToolName = maps:get(tool_name, Ctx, <<"unknown">>),
            case maps:is_key(result, Ctx) of
                false ->
                    %% Pre-execution
                    logger:info("Tool invocation: ~s", [ToolName]),
                    Ctx;
                true ->
                    %% Post-execution
                    Result = maps:get(result, Ctx, undefined),
                    case maps:get(error, Ctx, undefined) of
                        undefined ->
                            logger:info("Tool ~s completed successfully", [ToolName]);
                        Err ->
                            logger:warning("Tool ~s failed: ~p", [ToolName, Err])
                    end,
                    Ctx
            end
        end
    }.

%% @doc Create a timing middleware that records execution duration.
-spec timing_middleware() -> middleware_def().
timing_middleware() ->
    #{
        name => <<"timing">>,
        priority => 5,
        stage => both,
        function => fun(Ctx) ->
            case maps:is_key(result, Ctx) of
                false ->
                    %% Pre-execution: record start time
                    Ctx#{_start_time => erlang:monotonic_time(microsecond)};
                true ->
                    %% Post-execution: compute duration
                    StartTime = maps:get(_start_time, Ctx, erlang:monotonic_time(microsecond)),
                    Duration = erlang:monotonic_time(microsecond) - StartTime,
                    ToolName = maps:get(tool_name, Ctx, <<"unknown">>),
                    logger:debug("Tool ~s execution time: ~p us", [ToolName, Duration]),
                    Ctx#{execution_time_us => Duration}
            end
        end
    }.

%% @doc Create a validation middleware that validates args against tool schema.
-spec validation_middleware() -> middleware_def().
validation_middleware() ->
    #{
        name => <<"validation">>,
        priority => 20,
        stage => pre,
        function => fun(Ctx) ->
            ToolName = maps:get(tool_name, Ctx, undefined),
            Args = maps:get(args, Ctx, #{}),
            case ToolName of
                undefined -> Ctx;
                _ ->
                    case beamai_tools:validate_input(ToolName, Args) of
                        ok -> Ctx;
                        {error, Reason} -> {error, {validation_failed, Reason}}
                    end
            end
        end
    }.

%% @doc Create a caching middleware backed by an ETS table.
%% CacheTable must be a pre-existing ETS table name.
-spec caching_middleware(atom()) -> middleware_def().
caching_middleware(CacheTable) ->
    #{
        name => <<"caching">>,
        priority => 15,
        stage => both,
        function => fun(Ctx) ->
            ToolName = maps:get(tool_name, Ctx, <<>>),
            Args = maps:get(args, Ctx, #{}),
            CacheKey = {ToolName, erlang:phash2(Args)},
            case maps:is_key(result, Ctx) of
                false ->
                    %% Pre-execution: check cache
                    case catch ets:lookup(CacheTable, CacheKey) of
                        [{_, CachedResult, Expiry}] ->
                            Now = erlang:monotonic_time(millisecond),
                            case Now < Expiry of
                                true ->
                                    %% Cache hit: store result and skip handler
                                    Ctx#{result => CachedResult, _cache_hit => true};
                                false ->
                                    %% Expired
                                    ets:delete(CacheTable, CacheKey),
                                    Ctx
                            end;
                        _ ->
                            Ctx
                    end;
                true ->
                    %% Post-execution: store in cache
                    case maps:get(_cache_hit, Ctx, false) of
                        true ->
                            Ctx;  %% Already from cache
                        false ->
                            Result = maps:get(result, Ctx, undefined),
                            TTL = 300000,  %% 5 minutes default
                            Expiry = erlang:monotonic_time(millisecond) + TTL,
                            catch ets:insert(CacheTable, {CacheKey, Result, Expiry}),
                            Ctx
                    end
            end
        end
    }.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
normalize_middleware(Fun) when is_function(Fun, 1) ->
    #{
        name => <<"anonymous">>,
        priority => 100,
        stage => both,
        function => Fun
    };
normalize_middleware(#{function := _} = Def) ->
    maps:merge(#{
        name => <<"unnamed">>,
        priority => 100,
        stage => both
    }, Def);
normalize_middleware(Other) ->
    #{
        name => <<"invalid">>,
        priority => 999,
        stage => both,
        function => fun(Ctx) ->
            logger:warning("Invalid middleware skipped: ~p", [Other]),
            Ctx
        end
    }.

%% @private
insert_by_priority([], New) ->
    [New];
insert_by_priority([H | T], New) ->
    HPrio = maps:get(priority, H, 100),
    NPrio = maps:get(priority, New, 100),
    case NPrio =< HPrio of
        true -> [New, H | T];
        false -> [H | insert_by_priority(T, New)]
    end.

%% @private
partition_middlewares(Chain) ->
    Pre = [M || M <- Chain, middleware_stage(M) =:= pre orelse middleware_stage(M) =:= both],
    Post = [M || M <- Chain, middleware_stage(M) =:= post orelse middleware_stage(M) =:= both],
    {Pre, Post}.

%% @private
middleware_stage(#{stage := Stage}) -> Stage;
middleware_stage(_) -> both.

%% @private
run_pre_middlewares([], Ctx) ->
    {ok, Ctx};
run_pre_middlewares([Middleware | Rest], Ctx) ->
    Fun = maps:get(function, Middleware, fun(C) -> C end),
    try
        case Fun(Ctx) of
            {error, _} = Err ->
                Err;
            ModifiedCtx when is_map(ModifiedCtx) ->
                %% If middleware added a result (e.g., cache hit), stop early
                case maps:is_key(result, ModifiedCtx) andalso
                     not maps:is_key(result, Ctx) of
                    true ->
                        {ok, ModifiedCtx};
                    false ->
                        run_pre_middlewares(Rest, ModifiedCtx)
                end
        end
    catch
        Class:Reason:Stack ->
            MwName = maps:get(name, Middleware, <<"unknown">>),
            logger:error("Pre-middleware ~s failed: ~p:~p~n~p",
                        [MwName, Class, Reason, Stack]),
            run_pre_middlewares(Rest, Ctx)
    end.

%% @private
run_post_middlewares([], Ctx) ->
    {ok, Ctx};
run_post_middlewares([Middleware | Rest], Ctx) ->
    Fun = maps:get(function, Middleware, fun(C) -> C end),
    try
        case Fun(Ctx) of
            {error, _} = Err ->
                Err;
            ModifiedCtx when is_map(ModifiedCtx) ->
                run_post_middlewares(Rest, ModifiedCtx)
        end
    catch
        Class:Reason:Stack ->
            MwName = maps:get(name, Middleware, <<"unknown">>),
            logger:error("Post-middleware ~s failed: ~p:~p~n~p",
                        [MwName, Class, Reason, Stack]),
            run_post_middlewares(Rest, Ctx)
    end.
