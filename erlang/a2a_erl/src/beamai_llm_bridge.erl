%%%-------------------------------------------------------------------
%%% @doc LLM Bridge: delegates yawl_claude_headless to beamai LLM APIs
%%%
%%% Creates a beamai_chat_completion config for Anthropic on start,
%%% then delegates chat/2 and validate/2 through the real beamai
%%% chat completion and output parser modules.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_llm_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, chat/2, validate/2, get_provider/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    llm_config :: beamai_chat_completion:config(),
    kernel     :: beamai_kernel:kernel(),
    parser     :: beamai_output_parser:parser()
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec chat(binary(), map()) -> {ok, map()} | {error, term()}.
chat(Prompt, Opts) ->
    gen_server:call(?MODULE, {chat, Prompt, Opts}, ?DEFAULT_LLM_TIMEOUT).

-spec validate(binary(), map()) -> {ok, term()} | {error, term()}.
validate(Text, Schema) ->
    gen_server:call(?MODULE, {validate, Text, Schema}, ?DEFAULT_TIMEOUT).

-spec get_provider(pid() | atom()) -> {ok, beamai_chat_completion:provider()}.
get_provider(Ref) ->
    gen_server:call(Ref, get_provider).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    ApiKey = case os:getenv("ANTHROPIC_API_KEY") of
        false -> <<>>;
        Key   -> list_to_binary(Key)
    end,
    LlmConfig = beamai_chat_completion:create(anthropic, #{
        model   => <<"claude-sonnet-4-20250514">>,
        api_key => ApiKey
    }),
    Kernel0 = beamai_kernel:new(#{max_tool_iterations => 5}),
    Kernel  = beamai_kernel:add_service(Kernel0, LlmConfig),
    Parser  = beamai_output_parser:json(#{extract_codeblock => true}),
    ?LOG_INFO("beamai_llm_bridge started with anthropic provider"),
    {ok, #state{llm_config = LlmConfig, kernel = Kernel, parser = Parser}}.

handle_call({chat, Prompt, Opts}, _From, #state{llm_config = Cfg} = State) ->
    Messages = build_messages(Prompt, Opts),
    ChatOpts = maps:without([system_prompt], Opts),
    Reply = beamai_chat_completion:chat(Cfg, Messages, ChatOpts),
    {reply, Reply, State};

handle_call({validate, Text, Schema}, _From, #state{parser = BaseParser} = State) ->
    Parser = beamai_output_parser:json(#{schema => Schema}),
    Reply = beamai_output_parser:parse(Parser, Text),
    {reply, Reply, State};

handle_call(get_provider, _From, #state{llm_config = Cfg} = State) ->
    Provider = maps:get(provider, Cfg),
    {reply, {ok, Provider}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

build_messages(Prompt, Opts) ->
    SystemMsgs = case maps:get(system_prompt, Opts, undefined) of
        undefined -> [];
        SysPrompt -> [#{role => system, content => SysPrompt}]
    end,
    UserMsg = #{role => user, content => Prompt},
    SystemMsgs ++ [UserMsg].
