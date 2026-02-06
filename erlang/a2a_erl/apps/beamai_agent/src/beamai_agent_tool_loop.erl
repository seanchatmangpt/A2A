%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent Tool Loop
%%%
%%% Handles the tool execution loop for agents. Parses LLM responses
%%% for tool calls, executes tools through the BeamAI kernel, formats
%%% results as messages, and loops until no more tool calls remain.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_tool_loop).

%% API
-export([
    run/3,
    step/3,
    parse_tool_calls/1,
    execute_tool/3,
    format_result/1
]).

-define(MAX_ITERATIONS, 50).

%%====================================================================
%% API
%%====================================================================

%% @doc Run the complete tool loop given an LLM response, messages, and kernel.
%% Returns the final response after all tool calls are resolved.
-spec run(atom() | pid(), term(), [map()]) ->
    {ok, binary(), [map()]} | {error, term()}.
run(KernelRef, LlmResponse, Messages) ->
    run_loop(KernelRef, LlmResponse, Messages, 0).

%% @doc Execute a single step of the tool loop.
%% Returns the tool results and whether more iterations are needed.
-spec step(atom() | pid(), [map()], map()) ->
    {ok, [map()], boolean()} | {error, term()}.
step(KernelRef, ToolCalls, Context) ->
    Results = execute_tool_calls(KernelRef, ToolCalls, Context),
    {ok, Results, false}.

%% @doc Parse an LLM response to extract tool call requests.
%% Supports multiple response formats from different LLM providers.
-spec parse_tool_calls(term()) -> [map()].
parse_tool_calls(Response) when is_map(Response) ->
    %% Anthropic format: content blocks with type "tool_use"
    case maps:find(<<"content">>, Response) of
        {ok, ContentList} when is_list(ContentList) ->
            parse_content_blocks(ContentList);
        _ ->
            %% OpenAI format: tool_calls in message
            case maps:find(<<"tool_calls">>, Response) of
                {ok, ToolCalls} when is_list(ToolCalls) ->
                    parse_openai_tool_calls(ToolCalls);
                _ ->
                    %% Check for function_call (legacy format)
                    case maps:find(<<"function_call">>, Response) of
                        {ok, FunctionCall} when is_map(FunctionCall) ->
                            [parse_legacy_function_call(FunctionCall)];
                        _ ->
                            []
                    end
            end
    end;
parse_tool_calls(Response) when is_binary(Response) ->
    %% Plain text response, no tool calls
    [];
parse_tool_calls(_) ->
    [].

%% @doc Execute a single tool through the BeamAI kernel.
-spec execute_tool(atom() | pid(), binary(), map()) ->
    {ok, term()} | {error, term()}.
execute_tool(KernelRef, ToolName, Args) ->
    try
        case whereis(KernelRef) of
            undefined ->
                {error, {kernel_not_available, KernelRef}};
            _Pid ->
                beamai_kernel:invoke_tool(KernelRef, ToolName, Args, #{})
        end
    catch
        Class:Reason:_Stack ->
            {error, {tool_execution_failed, Class, Reason}}
    end.

%% @doc Format a tool execution result as a string suitable for
%% including in a conversation message.
-spec format_result(term()) -> binary().
format_result(Result) when is_binary(Result) ->
    Result;
format_result(Result) when is_map(Result) ->
    try jsx:encode(Result)
    catch _:_ -> iolist_to_binary(io_lib:format("~p", [Result]))
    end;
format_result(Result) when is_list(Result) ->
    try jsx:encode(Result)
    catch _:_ -> iolist_to_binary(io_lib:format("~p", [Result]))
    end;
format_result(Result) when is_integer(Result) ->
    integer_to_binary(Result);
format_result(Result) when is_float(Result) ->
    float_to_binary(Result, [{decimals, 6}, compact]);
format_result(Result) when is_atom(Result) ->
    atom_to_binary(Result, utf8);
format_result(Result) ->
    iolist_to_binary(io_lib:format("~p", [Result])).

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Run the tool loop until no more tool calls.
-spec run_loop(atom() | pid(), term(), [map()], non_neg_integer()) ->
    {ok, binary(), [map()]} | {error, term()}.
run_loop(_KernelRef, _LlmResponse, Messages, Iteration)
  when Iteration >= ?MAX_ITERATIONS ->
    LastMsg = case Messages of
        [] -> #{<<"content">> => <<"Max tool iterations reached">>};
        _ -> lists:last(Messages)
    end,
    Content = maps:get(<<"content">>, LastMsg, <<"Max iterations">>),
    {ok, Content, Messages};

run_loop(KernelRef, LlmResponse, Messages, Iteration) ->
    case parse_tool_calls(LlmResponse) of
        [] ->
            %% No tool calls, extract final response
            FinalText = extract_final_text(LlmResponse),
            {ok, FinalText, Messages};
        ToolCalls ->
            %% Execute all tool calls
            Results = execute_tool_calls(KernelRef, ToolCalls, #{}),
            NewMessages = Messages ++ Results,

            %% Re-query LLM with tool results
            case do_llm_followup(KernelRef, NewMessages) of
                {ok, NewLlmResponse} ->
                    %% Add assistant message
                    AssistantMsg = #{<<"role">> => <<"assistant">>,
                                    <<"content">> => NewLlmResponse},
                    UpdatedMessages = NewMessages ++ [AssistantMsg],
                    run_loop(KernelRef, NewLlmResponse, UpdatedMessages, Iteration + 1);
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @private Execute a list of tool calls and return result messages.
-spec execute_tool_calls(atom() | pid(), [map()], map()) -> [map()].
execute_tool_calls(KernelRef, ToolCalls, _Context) ->
    lists:map(fun(ToolCall) ->
        ToolName = maps:get(<<"name">>, ToolCall, <<>>),
        ToolArgs = maps:get(<<"arguments">>, ToolCall, #{}),
        ToolId = maps:get(<<"id">>, ToolCall, generate_id()),
        ParsedArgs = case ToolArgs of
            A when is_binary(A) ->
                try jsx:decode(A, [return_maps])
                catch _:_ -> #{<<"input">> => A}
                end;
            A when is_map(A) -> A;
            _ -> #{}
        end,
        case execute_tool(KernelRef, ToolName, ParsedArgs) of
            {ok, Result} ->
                #{<<"role">> => <<"tool">>,
                  <<"tool_call_id">> => ToolId,
                  <<"name">> => ToolName,
                  <<"content">> => format_result(Result)};
            {error, Reason} ->
                #{<<"role">> => <<"tool">>,
                  <<"tool_call_id">> => ToolId,
                  <<"name">> => ToolName,
                  <<"content">> => format_result({error, Reason})}
        end
    end, ToolCalls).

%% @private Parse Anthropic-style content blocks for tool_use blocks.
-spec parse_content_blocks([map()]) -> [map()].
parse_content_blocks(Blocks) ->
    lists:filtermap(fun(Block) ->
        case maps:get(<<"type">>, Block, undefined) of
            <<"tool_use">> ->
                {true, #{
                    <<"id">> => maps:get(<<"id">>, Block, generate_id()),
                    <<"name">> => maps:get(<<"name">>, Block, <<>>),
                    <<"arguments">> => maps:get(<<"input">>, Block, #{})
                }};
            _ ->
                false
        end
    end, Blocks).

%% @private Parse OpenAI-style tool_calls array.
-spec parse_openai_tool_calls([map()]) -> [map()].
parse_openai_tool_calls(ToolCalls) ->
    lists:filtermap(fun(TC) ->
        case maps:get(<<"type">>, TC, <<"function">>) of
            <<"function">> ->
                Function = maps:get(<<"function">>, TC, #{}),
                Args = maps:get(<<"arguments">>, Function, <<"{}">>),
                ParsedArgs = case Args of
                    A when is_binary(A) ->
                        try jsx:decode(A, [return_maps])
                        catch _:_ -> #{}
                        end;
                    A when is_map(A) -> A;
                    _ -> #{}
                end,
                {true, #{
                    <<"id">> => maps:get(<<"id">>, TC, generate_id()),
                    <<"name">> => maps:get(<<"name">>, Function, <<>>),
                    <<"arguments">> => ParsedArgs
                }};
            _ ->
                false
        end
    end, ToolCalls).

%% @private Parse a legacy function_call object.
-spec parse_legacy_function_call(map()) -> map().
parse_legacy_function_call(FunctionCall) ->
    Args = maps:get(<<"arguments">>, FunctionCall, <<"{}">>),
    ParsedArgs = case Args of
        A when is_binary(A) ->
            try jsx:decode(A, [return_maps])
            catch _:_ -> #{}
            end;
        A when is_map(A) -> A;
        _ -> #{}
    end,
    #{
        <<"id">> => generate_id(),
        <<"name">> => maps:get(<<"name">>, FunctionCall, <<>>),
        <<"arguments">> => ParsedArgs
    }.

%% @private Extract final text from an LLM response.
-spec extract_final_text(term()) -> binary().
extract_final_text(Response) when is_binary(Response) ->
    Response;
extract_final_text(#{<<"content">> := Content}) when is_binary(Content) ->
    Content;
extract_final_text(#{<<"content">> := ContentList}) when is_list(ContentList) ->
    TextBlocks = lists:filtermap(fun(Block) ->
        case maps:get(<<"type">>, Block, <<"text">>) of
            <<"text">> -> {true, maps:get(<<"text">>, Block, <<>>)};
            _ -> false
        end
    end, ContentList),
    iolist_to_binary(lists:join(<<" ">>, TextBlocks));
extract_final_text(#{<<"text">> := Text}) when is_binary(Text) ->
    Text;
extract_final_text(_) ->
    <<>>.

%% @private Follow up with the LLM after tool execution.
-spec do_llm_followup(atom() | pid(), [map()]) -> {ok, term()} | {error, term()}.
do_llm_followup(KernelRef, Messages) ->
    try
        MessagePayload = #{<<"messages">> => Messages},
        beamai_kernel:chat_with_tools(KernelRef, MessagePayload, #{})
    catch
        _:Reason -> {error, Reason}
    end.

%% @private Generate a unique identifier.
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(6),
    Hex = binary:encode_hex(Bytes),
    <<"call_", Hex/binary>>.
