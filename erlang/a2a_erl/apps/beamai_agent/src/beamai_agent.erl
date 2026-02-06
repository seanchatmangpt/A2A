%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent - Stateful Multi-turn Conversation Agent
%%%
%%% Implements a ReAct (Reasoning + Acting) agent that maintains
%%% multi-turn conversation state, executes tool-calling loops
%%% with filter pipelines, and provides observability through
%%% callbacks. Optionally persists state through beamai_memory.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent).

-behaviour(gen_server).

%% API
-export([
    new/1,
    run/2,
    run/3,
    stream/2,
    stream/3,
    resume/2,
    messages/1,
    save/1,
    restore/2,
    get_state/1,
    stop/1
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

-define(DEFAULT_MAX_TURNS, 10).
-define(DEFAULT_MAX_TOOL_CALLS, 50).

-record(state, {
    id              :: binary(),
    kernel_ref      :: atom() | pid(),
    system_prompt   :: binary(),
    messages        :: [map()],
    agent_state     :: atom(),
    callbacks       :: module() | undefined,
    callback_state  :: term(),
    max_turns       :: pos_integer(),
    max_tool_calls  :: pos_integer(),
    turn_count      :: non_neg_integer(),
    tool_call_count :: non_neg_integer(),
    config          :: map(),
    metadata        :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Create a new agent with the given configuration.
%% Options:
%%   kernel_ref - BeamAI kernel reference (default: beamai_kernel)
%%   system_prompt - System prompt for the agent
%%   callbacks - Callback module implementing beamai_agent_callbacks
%%   max_turns - Maximum conversation turns (default: 10)
%%   max_tool_calls - Maximum total tool calls (default: 50)
%%   id - Agent identifier (auto-generated if not provided)
-spec new(map()) -> {ok, pid()} | {error, term()}.
new(Config) ->
    gen_server:start_link(?MODULE, Config, []).

%% @doc Run the agent with a user message, blocking until complete.
-spec run(pid(), binary()) -> {ok, binary()} | {error, term()}.
run(Agent, Message) ->
    run(Agent, Message, #{}).

%% @doc Run the agent with a user message and options.
-spec run(pid(), binary(), map()) -> {ok, binary()} | {error, term()}.
run(Agent, Message, Opts) ->
    gen_server:call(Agent, {run, Message, Opts}, 120000).

%% @doc Stream the agent response for a user message.
%% Sends {agent_token, Token} messages to the caller.
-spec stream(pid(), binary()) -> {ok, binary()} | {error, term()}.
stream(Agent, Message) ->
    stream(Agent, Message, #{}).

%% @doc Stream the agent response with options.
-spec stream(pid(), binary(), map()) -> {ok, binary()} | {error, term()}.
stream(Agent, Message, Opts) ->
    StreamOpts = Opts#{stream => true, stream_to => self()},
    gen_server:call(Agent, {run, Message, StreamOpts}, 120000).

%% @doc Resume a paused agent (e.g., after input_required).
-spec resume(pid(), binary()) -> {ok, binary()} | {error, term()}.
resume(Agent, Input) ->
    gen_server:call(Agent, {resume, Input}, 120000).

%% @doc Get the current message history.
-spec messages(pid()) -> [map()].
messages(Agent) ->
    gen_server:call(Agent, get_messages).

%% @doc Save the agent state to persistent storage.
-spec save(pid()) -> {ok, binary()} | {error, term()}.
save(Agent) ->
    gen_server:call(Agent, save).

%% @doc Restore an agent from saved state.
-spec restore(pid(), binary()) -> ok | {error, term()}.
restore(Agent, StateId) ->
    gen_server:call(Agent, {restore, StateId}).

%% @doc Get the current agent state atom.
-spec get_state(pid()) -> atom().
get_state(Agent) ->
    gen_server:call(Agent, get_agent_state).

%% @doc Stop the agent.
-spec stop(pid()) -> ok.
stop(Agent) ->
    gen_server:stop(Agent, normal, 5000).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    Id = maps:get(id, Config, generate_agent_id()),
    KernelRef = maps:get(kernel_ref, Config, beamai_kernel),
    SystemPrompt = maps:get(system_prompt, Config, default_system_prompt()),
    Callbacks = maps:get(callbacks, Config, undefined),
    MaxTurns = maps:get(max_turns, Config, ?DEFAULT_MAX_TURNS),
    MaxToolCalls = maps:get(max_tool_calls, Config, ?DEFAULT_MAX_TOOL_CALLS),

    InitialMessages = case SystemPrompt of
        <<>> -> [];
        _ -> [#{<<"role">> => <<"system">>, <<"content">> => SystemPrompt}]
    end,

    State = #state{
        id = Id,
        kernel_ref = KernelRef,
        system_prompt = SystemPrompt,
        messages = InitialMessages,
        agent_state = idle,
        callbacks = Callbacks,
        callback_state = undefined,
        max_turns = MaxTurns,
        max_tool_calls = MaxToolCalls,
        turn_count = 0,
        tool_call_count = 0,
        config = Config,
        metadata = #{created_at => erlang:system_time(millisecond)}
    },
    logger:info("BeamAI agent ~s created", [Id]),
    {ok, State}.

%% @private
handle_call({run, Message, Opts}, From, State) ->
    #state{agent_state = AgentState} = State,
    case beamai_agent_state:can_transition(AgentState, thinking) of
        true ->
            NewState = State#state{agent_state = thinking},
            %% Run the agent loop asynchronously
            Self = self(),
            spawn_link(fun() ->
                Result = do_run(Message, Opts, NewState),
                gen_server:cast(Self, {run_complete, From, Result})
            end),
            {noreply, NewState};
        false ->
            {reply, {error, {invalid_state, AgentState}}, State}
    end;

handle_call({resume, Input}, From, State) ->
    #state{agent_state = AgentState} = State,
    case AgentState of
        waiting_input ->
            NewState = State#state{agent_state = thinking},
            Self = self(),
            spawn_link(fun() ->
                Result = do_run(Input, #{}, NewState),
                gen_server:cast(Self, {run_complete, From, Result})
            end),
            {noreply, NewState};
        _ ->
            {reply, {error, {not_waiting_input, AgentState}}, State}
    end;

handle_call(get_messages, _From, #state{messages = Messages} = State) ->
    {reply, Messages, State};

handle_call(save, _From, State) ->
    case do_save(State) of
        {ok, StateId} ->
            {reply, {ok, StateId}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({restore, StateId}, _From, State) ->
    case do_restore(StateId, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_agent_state, _From, #state{agent_state = AgentState} = State) ->
    {reply, AgentState, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({run_complete, From, {ok, Response, NewState}}, _State) ->
    gen_server:reply(From, {ok, Response}),
    {noreply, NewState#state{agent_state = idle}};

handle_cast({run_complete, From, {error, Reason, NewState}}, _State) ->
    gen_server:reply(From, {error, Reason}),
    {noreply, NewState#state{agent_state = error}};

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

%% @private Execute the agent run loop.
-spec do_run(binary(), map(), #state{}) ->
    {ok, binary(), #state{}} | {error, term(), #state{}}.
do_run(Message, Opts, State) ->
    #state{
        kernel_ref = KernelRef,
        messages = Messages,
        callbacks = Callbacks,
        turn_count = TurnCount,
        max_turns = MaxTurns
    } = State,

    case TurnCount >= MaxTurns of
        true ->
            {error, max_turns_exceeded, State};
        false ->
            %% Add user message
            UserMsg = #{<<"role">> => <<"user">>, <<"content">> => Message},
            NewMessages = Messages ++ [UserMsg],

            %% Fire callback
            notify_callback(Callbacks, on_turn_start, [TurnCount + 1, UserMsg]),

            %% Send to LLM with tools
            ChatOpts = maps:merge(#{}, Opts),
            case do_chat_with_tools(KernelRef, NewMessages, ChatOpts) of
                {ok, LlmResponse} ->
                    notify_callback(Callbacks, on_llm_call, [LlmResponse, #{}]),

                    %% Check if LLM wants to call tools
                    case beamai_agent_tool_loop:parse_tool_calls(LlmResponse) of
                        [] ->
                            %% No tool calls, we have a final response
                            ResponseText = extract_text_response(LlmResponse),
                            AssistantMsg = #{<<"role">> => <<"assistant">>,
                                            <<"content">> => ResponseText},
                            FinalMessages = NewMessages ++ [AssistantMsg],
                            notify_callback(Callbacks, on_turn_end, [TurnCount + 1, AssistantMsg]),
                            FinalState = State#state{
                                messages = FinalMessages,
                                turn_count = TurnCount + 1
                            },
                            %% Stream tokens if requested
                            maybe_stream_response(ResponseText, Opts),
                            {ok, ResponseText, FinalState};

                        ToolCalls ->
                            %% Execute tool loop
                            AssistantMsg = #{<<"role">> => <<"assistant">>,
                                            <<"content">> => LlmResponse},
                            MsgsWithAssistant = NewMessages ++ [AssistantMsg],
                            case do_tool_loop(ToolCalls, MsgsWithAssistant, Opts,
                                              State#state{messages = MsgsWithAssistant,
                                                          turn_count = TurnCount + 1}) of
                                {ok, FinalResponse, FinalState} ->
                                    {ok, FinalResponse, FinalState};
                                {error, Reason, ErrState} ->
                                    notify_callback(Callbacks, on_turn_error, [TurnCount + 1, Reason]),
                                    {error, Reason, ErrState}
                            end
                    end;

                {error, Reason} ->
                    notify_callback(Callbacks, on_turn_error, [TurnCount + 1, Reason]),
                    {error, Reason, State#state{messages = NewMessages}}
            end
    end.

%% @private Execute the tool calling loop.
-spec do_tool_loop([map()], [map()], map(), #state{}) ->
    {ok, binary(), #state{}} | {error, term(), #state{}}.
do_tool_loop(ToolCalls, Messages, Opts, State) ->
    #state{
        kernel_ref = KernelRef,
        callbacks = Callbacks,
        tool_call_count = ToolCallCount,
        max_tool_calls = MaxToolCalls,
        turn_count = TurnCount,
        max_turns = MaxTurns
    } = State,

    NewToolCallCount = ToolCallCount + length(ToolCalls),
    case NewToolCallCount > MaxToolCalls of
        true ->
            {error, max_tool_calls_exceeded, State};
        false ->
            %% Execute each tool call
            ToolResults = lists:map(fun(ToolCall) ->
                ToolName = maps:get(<<"name">>, ToolCall, <<>>),
                ToolArgs = maps:get(<<"arguments">>, ToolCall, #{}),
                ToolId = maps:get(<<"id">>, ToolCall, generate_tool_call_id()),

                notify_callback(Callbacks, on_tool_call, [ToolName, ToolArgs]),

                case beamai_agent_tool_loop:execute_tool(KernelRef, ToolName, ToolArgs) of
                    {ok, Result} ->
                        #{<<"role">> => <<"tool">>,
                          <<"tool_call_id">> => ToolId,
                          <<"content">> => beamai_agent_tool_loop:format_result(Result)};
                    {error, Reason} ->
                        #{<<"role">> => <<"tool">>,
                          <<"tool_call_id">> => ToolId,
                          <<"content">> => iolist_to_binary(
                              io_lib:format("Error: ~p", [Reason]))}
                end
            end, ToolCalls),

            NewMessages = Messages ++ ToolResults,
            UpdatedState = State#state{
                messages = NewMessages,
                tool_call_count = NewToolCallCount
            },

            %% Check if we can continue
            case TurnCount >= MaxTurns of
                true ->
                    LastResult = lists:last(ToolResults),
                    {ok, maps:get(<<"content">>, LastResult, <<>>), UpdatedState};
                false ->
                    %% Send updated conversation back to LLM
                    case do_chat_with_tools(KernelRef, NewMessages, Opts) of
                        {ok, LlmResponse} ->
                            notify_callback(Callbacks, on_llm_call, [LlmResponse, #{}]),
                            case beamai_agent_tool_loop:parse_tool_calls(LlmResponse) of
                                [] ->
                                    %% No more tool calls, final response
                                    ResponseText = extract_text_response(LlmResponse),
                                    AssistantMsg = #{<<"role">> => <<"assistant">>,
                                                    <<"content">> => ResponseText},
                                    FinalMessages = NewMessages ++ [AssistantMsg],
                                    FinalState = UpdatedState#state{
                                        messages = FinalMessages,
                                        turn_count = TurnCount + 1
                                    },
                                    notify_callback(Callbacks, on_turn_end, [TurnCount + 1, AssistantMsg]),
                                    maybe_stream_response(ResponseText, Opts),
                                    {ok, ResponseText, FinalState};
                                MoreToolCalls ->
                                    %% More tool calls, recurse
                                    AssistantMsg = #{<<"role">> => <<"assistant">>,
                                                    <<"content">> => LlmResponse},
                                    MsgsWithAssistant = NewMessages ++ [AssistantMsg],
                                    do_tool_loop(MoreToolCalls, MsgsWithAssistant, Opts,
                                                 UpdatedState#state{
                                                     messages = MsgsWithAssistant,
                                                     turn_count = TurnCount + 1
                                                 })
                            end;
                        {error, Reason} ->
                            {error, Reason, UpdatedState}
                    end
            end
    end.

%% @private Send chat with tools through the kernel.
-spec do_chat_with_tools(atom() | pid(), [map()], map()) ->
    {ok, term()} | {error, term()}.
do_chat_with_tools(KernelRef, Messages, Opts) ->
    try
        MessagePayload = #{<<"messages">> => Messages},
        case whereis(KernelRef) of
            undefined ->
                {error, kernel_not_available};
            _Pid ->
                beamai_kernel:chat_with_tools(KernelRef, MessagePayload, Opts)
        end
    catch
        _:Reason -> {error, Reason}
    end.

%% @private Extract text from an LLM response.
-spec extract_text_response(term()) -> binary().
extract_text_response(Response) when is_binary(Response) ->
    Response;
extract_text_response(#{<<"content">> := Content}) when is_binary(Content) ->
    Content;
extract_text_response(#{<<"content">> := [#{<<"text">> := Text} | _]}) ->
    Text;
extract_text_response(#{<<"text">> := Text}) when is_binary(Text) ->
    Text;
extract_text_response(Response) when is_map(Response) ->
    jsx:encode(Response);
extract_text_response(_) ->
    <<>>.

%% @private Stream response tokens to the caller if streaming is enabled.
-spec maybe_stream_response(binary(), map()) -> ok.
maybe_stream_response(Response, #{stream := true, stream_to := Pid}) ->
    Pid ! {agent_token, Response},
    ok;
maybe_stream_response(_Response, _Opts) ->
    ok.

%% @private Save agent state using beamai_agent_memory.
-spec do_save(#state{}) -> {ok, binary()} | {error, term()}.
do_save(#state{id = Id, messages = Messages, config = Config, metadata = Meta,
               turn_count = TurnCount, tool_call_count = ToolCallCount}) ->
    StateData = #{
        id => Id,
        messages => Messages,
        config => Config,
        metadata => Meta,
        turn_count => TurnCount,
        tool_call_count => ToolCallCount,
        saved_at => erlang:system_time(millisecond)
    },
    beamai_agent_memory:save(Id, StateData).

%% @private Restore agent state from beamai_agent_memory.
-spec do_restore(binary(), #state{}) -> {ok, #state{}} | {error, term()}.
do_restore(StateId, State) ->
    case beamai_agent_memory:restore(StateId, #{}) of
        {ok, StateData} ->
            NewState = State#state{
                id = maps:get(id, StateData, State#state.id),
                messages = maps:get(messages, StateData, []),
                turn_count = maps:get(turn_count, StateData, 0),
                tool_call_count = maps:get(tool_call_count, StateData, 0),
                metadata = maps:get(metadata, StateData, #{}),
                agent_state = idle
            },
            {ok, NewState};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private Notify a callback module if configured.
-spec notify_callback(module() | undefined, atom(), [term()]) -> ok.
notify_callback(undefined, _Function, _Args) ->
    ok;
notify_callback(Module, Function, Args) ->
    try
        erlang:apply(Module, Function, Args)
    catch
        _:_ -> ok
    end,
    ok.

%% @private Generate a unique agent identifier.
-spec generate_agent_id() -> binary().
generate_agent_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"agent-", Hex/binary>>.

%% @private Generate a unique tool call identifier.
-spec generate_tool_call_id() -> binary().
generate_tool_call_id() ->
    Bytes = crypto:strong_rand_bytes(6),
    Hex = binary:encode_hex(Bytes),
    <<"tc-", Hex/binary>>.

%% @private Default system prompt.
-spec default_system_prompt() -> binary().
default_system_prompt() ->
    <<"You are a helpful assistant powered by the BeamAI framework. ",
      "You can use tools to help answer questions and complete tasks. ",
      "Always be clear and concise in your responses.">>.
