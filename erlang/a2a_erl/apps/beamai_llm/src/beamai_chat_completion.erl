%%%-------------------------------------------------------------------
%%% @doc BeamAI Chat Completion Module.
%%%
%%% Provides a unified interface for sending chat messages to LLM
%%% providers with support for:
%%% - Multiple providers (Anthropic, OpenAI, etc.)
%%% - Streaming responses via SSE
%%% - Tool use / function calling
%%% - Automatic retry with exponential backoff on transient failures
%%% - Configurable temperature, max tokens, and model selection
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_chat_completion).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    complete/2,
    complete/3,
    stream/2,
    stream/3,
    with_tools/3
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

%%====================================================================
%% Records
%%====================================================================

-record(completion_request, {
    provider    :: atom(),
    model       :: binary(),
    messages    :: list(),
    tools = []  :: list(),
    temperature = 0.7  :: float(),
    max_tokens  = 4096 :: integer(),
    stream = false     :: boolean()
}).

-record(state, {
    providers      = #{} :: #{atom() => module()},
    default_provider     :: atom(),
    retry_max      = 3   :: non_neg_integer(),
    retry_base_ms  = 1000 :: non_neg_integer(),
    stream_timeout = 60000 :: non_neg_integer(),
    request_count  = 0   :: non_neg_integer(),
    error_count    = 0   :: non_neg_integer()
}).

-type completion_opts() :: #{
    provider => atom(),
    model => binary(),
    temperature => float(),
    max_tokens => integer(),
    system_prompt => binary(),
    stop_sequences => [binary()],
    metadata => map()
}.

-type stream_callback() :: fun((map() | eof | {error, term()}) -> ok).

-export_type([completion_opts/0, stream_callback/0]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the chat completion server with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the chat completion server with custom options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Send a chat completion request with default options.
%% Messages is a list of #{role => binary(), content => binary()} maps,
%% or a single binary prompt string.
-spec complete(atom(), list() | binary()) ->
    {ok, map()} | {error, term()}.
complete(Provider, Messages) ->
    complete(Provider, Messages, #{}).

%% @doc Send a chat completion request with options.
-spec complete(atom(), list() | binary(), completion_opts()) ->
    {ok, map()} | {error, term()}.
complete(Provider, Messages, Opts) ->
    gen_server:call(?SERVER, {complete, Provider, Messages, Opts}, 120000).

%% @doc Stream a chat completion with default options.
%% Callback receives chunks as maps, then 'eof' when done.
-spec stream(atom(), list() | binary()) ->
    {ok, reference()} | {error, term()}.
stream(Provider, Messages) ->
    stream(Provider, Messages, #{}).

%% @doc Stream a chat completion with options.
-spec stream(atom(), list() | binary(), completion_opts()) ->
    {ok, reference()} | {error, term()}.
stream(Provider, Messages, Opts) ->
    Caller = self(),
    gen_server:call(?SERVER, {stream, Provider, Messages, Opts, Caller}, 120000).

%% @doc Send a chat completion request with tool definitions.
%% Tools is a list of tool definition maps compatible with the
%% provider's function calling API.
-spec with_tools(atom(), list() | binary(), list()) ->
    {ok, map()} | {error, term()}.
with_tools(Provider, Messages, Tools) ->
    gen_server:call(?SERVER, {with_tools, Provider, Messages, Tools}, 120000).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    DefaultProvider = get_env(default_provider, maps:get(default_provider, Opts, anthropic)),
    RetryMax = get_env(retry_max_attempts, maps:get(retry_max, Opts, 3)),
    RetryBase = get_env(retry_base_delay_ms, maps:get(retry_base_ms, Opts, 1000)),
    StreamTimeout = get_env(stream_timeout_ms, maps:get(stream_timeout, Opts, 60000)),

    %% Register built-in providers
    Providers = #{
        anthropic => beamai_llm_anthropic,
        openai    => beamai_llm_openai
    },

    %% Merge any custom providers from opts
    CustomProviders = maps:get(providers, Opts, #{}),
    AllProviders = maps:merge(Providers, CustomProviders),

    logger:info("BeamAI chat completion started with default provider: ~p", [DefaultProvider]),

    {ok, #state{
        providers = AllProviders,
        default_provider = DefaultProvider,
        retry_max = RetryMax,
        retry_base_ms = RetryBase,
        stream_timeout = StreamTimeout
    }}.

%% @private
handle_call({complete, Provider, Messages, Opts}, _From, State) ->
    Result = do_complete(Provider, Messages, Opts, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

handle_call({stream, Provider, Messages, Opts, Caller}, _From, State) ->
    Result = do_stream(Provider, Messages, Opts, Caller, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

handle_call({with_tools, Provider, Messages, Tools}, _From, State) ->
    Opts = #{tools => Tools},
    Result = do_complete(Provider, Messages, Opts, State),
    NewState = update_counters(Result, State),
    {reply, Result, NewState};

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
%% Execute a completion request with retry logic.
-spec do_complete(atom(), list() | binary(), map(), #state{}) ->
    {ok, map()} | {error, term()}.
do_complete(Provider, Messages, Opts, State) ->
    case resolve_provider(Provider, State) of
        {ok, Module} ->
            NormalizedMsgs = normalize_messages(Messages),
            Request = build_request(Provider, NormalizedMsgs, Opts, State),
            execute_with_retry(Module, Request, State#state.retry_max, State#state.retry_base_ms);
        {error, _} = Err ->
            Err
    end.

%% @private
%% Execute a streaming request.
-spec do_stream(atom(), list() | binary(), map(), pid(), #state{}) ->
    {ok, reference()} | {error, term()}.
do_stream(Provider, Messages, Opts, Caller, State) ->
    case resolve_provider(Provider, State) of
        {ok, Module} ->
            NormalizedMsgs = normalize_messages(Messages),
            Request = build_request(Provider, NormalizedMsgs, Opts#{stream => true}, State),
            StreamRef = make_ref(),
            spawn_link(fun() ->
                stream_worker(Module, Request, Caller, StreamRef, State#state.stream_timeout)
            end),
            {ok, StreamRef};
        {error, _} = Err ->
            Err
    end.

%% @private
%% Look up the module implementing the provider.
-spec resolve_provider(atom(), #state{}) -> {ok, module()} | {error, term()}.
resolve_provider(Provider, #state{providers = Providers, default_provider = Default}) ->
    ResolvedProvider = case Provider of
        undefined -> Default;
        default   -> Default;
        P         -> P
    end,
    case maps:find(ResolvedProvider, Providers) of
        {ok, Module} -> {ok, Module};
        error -> {error, {unknown_provider, ResolvedProvider}}
    end.

%% @private
%% Build a completion_request record from user inputs.
-spec build_request(atom(), list(), map(), #state{}) -> #completion_request{}.
build_request(Provider, Messages, Opts, _State) ->
    DefaultTemp = get_env(default_temperature, 0.7),
    DefaultMaxTokens = get_env(default_max_tokens, 4096),

    %% Add system prompt as first message if provided
    SystemMessages = case maps:get(system_prompt, Opts, undefined) of
        undefined -> [];
        SysPrompt -> [#{role => <<"system">>, content => SysPrompt}]
    end,

    #completion_request{
        provider    = Provider,
        model       = maps:get(model, Opts, undefined),
        messages    = SystemMessages ++ Messages,
        tools       = maps:get(tools, Opts, []),
        temperature = maps:get(temperature, Opts, DefaultTemp),
        max_tokens  = maps:get(max_tokens, Opts, DefaultMaxTokens),
        stream      = maps:get(stream, Opts, false)
    }.

%% @private
%% Normalize various message input formats to a canonical list of maps.
-spec normalize_messages(list() | binary()) -> list().
normalize_messages(Prompt) when is_binary(Prompt) ->
    [#{role => <<"user">>, content => Prompt}];
normalize_messages(Messages) when is_list(Messages) ->
    lists:map(fun normalize_single_message/1, Messages);
normalize_messages(Other) ->
    [#{role => <<"user">>, content => ensure_binary(Other)}].

%% @private
normalize_single_message(#{role := _Role, content := _Content} = Msg) ->
    Msg;
normalize_single_message(#{<<"role">> := Role, <<"content">> := Content} = Msg) ->
    Base = #{role => Role, content => Content},
    case maps:find(<<"name">>, Msg) of
        {ok, Name} -> Base#{name => Name};
        error -> Base
    end;
normalize_single_message(Bin) when is_binary(Bin) ->
    #{role => <<"user">>, content => Bin};
normalize_single_message(Other) ->
    #{role => <<"user">>, content => ensure_binary(Other)}.

%% @private
%% Execute with exponential backoff retry on transient errors.
-spec execute_with_retry(module(), #completion_request{}, non_neg_integer(), non_neg_integer()) ->
    {ok, map()} | {error, term()}.
execute_with_retry(Module, Request, MaxRetries, BaseDelay) ->
    execute_with_retry(Module, Request, 0, MaxRetries, BaseDelay).

execute_with_retry(Module, Request, Attempt, MaxRetries, BaseDelay) ->
    case catch Module:chat(Request, #{}) of
        {ok, Response} ->
            {ok, Response};
        {error, {transient, Reason}} when Attempt < MaxRetries ->
            Delay = BaseDelay * (1 bsl Attempt),
            Jitter = rand:uniform(Delay div 2),
            timer:sleep(Delay + Jitter),
            logger:warning("Retrying LLM request (attempt ~p/~p): ~p",
                          [Attempt + 1, MaxRetries, Reason]),
            execute_with_retry(Module, Request, Attempt + 1, MaxRetries, BaseDelay);
        {error, Reason} ->
            {error, Reason};
        {'EXIT', Reason} ->
            {error, {provider_crash, Reason}};
        Other ->
            {error, {unexpected_response, Other}}
    end.

%% @private
%% Worker process for streaming responses back to caller.
-spec stream_worker(module(), #completion_request{}, pid(), reference(), non_neg_integer()) -> ok.
stream_worker(Module, Request, Caller, StreamRef, Timeout) ->
    CallbackFun = fun(Chunk) ->
        Caller ! {beamai_stream, StreamRef, Chunk}
    end,
    try
        case Module:stream(Request, #{callback => CallbackFun, timeout => Timeout}) of
            {ok, _FinalResponse} ->
                Caller ! {beamai_stream, StreamRef, eof},
                ok;
            {error, Reason} ->
                Caller ! {beamai_stream, StreamRef, {error, Reason}},
                ok
        end
    catch
        Class:Error:_Stack ->
            Caller ! {beamai_stream, StreamRef, {error, {Class, Error}}},
            ok
    end.

%% @private
-spec update_counters({ok, term()} | {error, term()}, #state{}) -> #state{}.
update_counters({ok, _}, State) ->
    State#state{request_count = State#state.request_count + 1};
update_counters({error, _}, State) ->
    State#state{
        request_count = State#state.request_count + 1,
        error_count = State#state.error_count + 1
    };
update_counters(_, State) ->
    State#state{request_count = State#state.request_count + 1}.

%% @private
-spec get_env(atom(), term()) -> term().
get_env(Key, Default) ->
    application:get_env(beamai_llm, Key, Default).

%% @private
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V)   -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V)   -> list_to_binary(V);
ensure_binary(V) when is_integer(V) -> integer_to_binary(V);
ensure_binary(V) -> list_to_binary(io_lib:format("~p", [V])).
