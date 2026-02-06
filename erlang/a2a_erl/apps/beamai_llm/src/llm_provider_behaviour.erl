%%%-------------------------------------------------------------------
%%% @doc LLM Provider Behaviour.
%%%
%%% Defines the callback interface that all LLM provider adapters
%%% must implement. This ensures a consistent API across providers
%%% (Anthropic, OpenAI, local models, etc.) and allows the chat
%%% completion module to interact with any provider uniformly.
%%%
%%% Provider modules implementing this behaviour must export:
%%% - chat/2       : Send a completion request, return full response
%%% - stream/2     : Send a streaming request, invoke callback per chunk
%%% - models/0     : Return list of supported model identifiers
%%% - validate_config/1 : Validate provider-specific configuration
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(llm_provider_behaviour).

%%====================================================================
%% Type Definitions
%%====================================================================

-type chat_request() :: #{
    model := binary(),
    messages := [message()],
    tools => [tool_def()],
    temperature => float(),
    max_tokens => integer(),
    stop_sequences => [binary()],
    stream => boolean()
}.

-type message() :: #{
    role := binary(),
    content := binary() | [content_block()],
    name => binary()
}.

-type content_block() :: #{
    type := binary(),
    text => binary(),
    id => binary(),
    name => binary(),
    input => map()
}.

-type tool_def() :: #{
    name := binary(),
    description => binary(),
    input_schema => map()
}.

-type chat_response() :: #{
    id => binary(),
    model => binary(),
    content := [content_block()],
    stop_reason => binary(),
    usage => usage(),
    tool_calls => [tool_call()]
}.

-type tool_call() :: #{
    id := binary(),
    name := binary(),
    arguments := map() | binary()
}.

-type usage() :: #{
    input_tokens => integer(),
    output_tokens => integer(),
    total_tokens => integer()
}.

-type stream_opts() :: #{
    callback := fun((stream_event()) -> ok),
    timeout => integer()
}.

-type stream_event() :: #{
    type := binary(),
    data => term(),
    index => integer()
}.

-type provider_config() :: map().

-type model_info() :: #{
    id := binary(),
    name => binary(),
    max_tokens => integer(),
    supports_tools => boolean(),
    supports_streaming => boolean()
}.

-export_type([
    chat_request/0, message/0, content_block/0, tool_def/0,
    chat_response/0, tool_call/0, usage/0,
    stream_opts/0, stream_event/0,
    provider_config/0, model_info/0
]).

%%====================================================================
%% Callback Definitions
%%====================================================================

%% @doc Send a chat completion request and return the full response.
%% The request record/map contains provider, model, messages, tools,
%% temperature, max_tokens, and stream settings. Config contains
%% provider-specific configuration (API keys, endpoints, etc.).
%%
%% Returns {ok, Response} on success where Response is a map with
%% at least a 'content' key containing the response content blocks.
%% Returns {error, {transient, Reason}} for retryable errors (rate
%% limits, temporary server errors) or {error, Reason} for permanent
%% errors.
-callback chat(Request :: term(), Config :: provider_config()) ->
    {ok, chat_response()} | {error, term()}.

%% @doc Send a streaming chat completion request.
%% The callback function in StreamOpts is invoked for each chunk
%% received from the provider. Returns {ok, FinalResponse} when
%% the stream is complete, or {error, Reason} on failure.
-callback stream(Request :: term(), StreamOpts :: stream_opts()) ->
    {ok, chat_response()} | {error, term()}.

%% @doc Return list of models supported by this provider.
%% Each model is described as a map with at least an 'id' key.
-callback models() -> [model_info()].

%% @doc Validate provider configuration.
%% Checks that required keys (API key, endpoint, etc.) are present
%% and well-formed. Returns ok or {error, Reasons}.
-callback validate_config(Config :: provider_config()) ->
    ok | {error, [term()]}.
