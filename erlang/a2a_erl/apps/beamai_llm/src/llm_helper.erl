%%%-------------------------------------------------------------------
%%% @doc LLM Helper Utilities.
%%%
%%% Provides helper functions for LLM operations including:
%%% - Message formatting and normalization
%%% - Token estimation (rough approximation)
%%% - Response parsing to extract structured data
%%% - Tool call extraction from LLM responses
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(llm_helper).

-export([
    format_messages/1,
    format_messages/2,
    estimate_tokens/1,
    estimate_tokens/2,
    parse_response/1,
    parse_response/2,
    extract_tool_calls/1,
    extract_text_content/1,
    build_tool_result_message/3,
    truncate_messages/2,
    merge_system_prompt/2
]).

%%====================================================================
%% Type Definitions
%%====================================================================

-type message() :: #{
    role := binary(),
    content := binary() | list()
}.

-type provider() :: anthropic | openai | atom().

-type tool_call() :: #{
    id := binary(),
    name := binary(),
    arguments := map()
}.

-export_type([message/0, provider/0, tool_call/0]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Format messages for the default provider (Anthropic).
-spec format_messages(list()) -> list().
format_messages(Messages) ->
    format_messages(Messages, anthropic).

%% @doc Format messages for a specific provider.
%% Transforms a canonical message list into the provider-specific format.
-spec format_messages(list(), provider()) -> list().
format_messages(Messages, anthropic) ->
    format_messages_anthropic(Messages);
format_messages(Messages, openai) ->
    format_messages_openai(Messages);
format_messages(Messages, _Provider) ->
    %% Default: return as-is
    Messages.

%% @doc Estimate token count for a string or message list.
%% Uses a rough approximation of ~4 characters per token.
-spec estimate_tokens(binary() | list()) -> non_neg_integer().
estimate_tokens(Input) ->
    estimate_tokens(Input, #{}).

%% @doc Estimate tokens with options.
%% Options:
%%   chars_per_token - Override characters per token ratio (default 4)
-spec estimate_tokens(binary() | list(), map()) -> non_neg_integer().
estimate_tokens(Text, Opts) when is_binary(Text) ->
    CharsPerToken = maps:get(chars_per_token, Opts, 4),
    max(1, byte_size(Text) div CharsPerToken);
estimate_tokens(Messages, Opts) when is_list(Messages) ->
    %% Sum tokens across all messages, plus overhead per message
    PerMessage = maps:get(per_message_overhead, Opts, 4),
    lists:foldl(fun(Msg, Acc) ->
        Content = extract_message_text(Msg),
        Role = maps:get(role, Msg, maps:get(<<"role">>, Msg, <<>>)),
        Acc + estimate_tokens(Content, Opts) +
        estimate_tokens(Role, Opts) + PerMessage
    end, 0, Messages);
estimate_tokens(Other, Opts) ->
    estimate_tokens(ensure_binary(Other), Opts).

%% @doc Parse an LLM response into a structured result.
%% Extracts content, stop reason, usage, and tool calls.
-spec parse_response(map()) -> map().
parse_response(Response) ->
    parse_response(Response, anthropic).

%% @doc Parse an LLM response for a specific provider.
-spec parse_response(map(), provider()) -> map().
parse_response(Response, anthropic) ->
    parse_anthropic_response(Response);
parse_response(Response, openai) ->
    parse_openai_response(Response);
parse_response(Response, _Provider) ->
    #{
        text => extract_text_content(Response),
        tool_calls => extract_tool_calls(Response),
        stop_reason => maps:get(stop_reason, Response,
                       maps:get(<<"stop_reason">>, Response, undefined)),
        usage => maps:get(usage, Response,
                 maps:get(<<"usage">>, Response, #{})),
        raw => Response
    }.

%% @doc Extract tool calls from an LLM response.
%% Works with both Anthropic and OpenAI response formats.
-spec extract_tool_calls(map()) -> [tool_call()].
extract_tool_calls(Response) ->
    %% Try Anthropic format first
    AnthropicCalls = extract_anthropic_tool_calls(Response),
    case AnthropicCalls of
        [] -> extract_openai_tool_calls(Response);
        Calls -> Calls
    end.

%% @doc Extract plain text content from a response.
-spec extract_text_content(map()) -> binary().
extract_text_content(Response) ->
    %% Try Anthropic format: content is a list of blocks
    case maps:get(<<"content">>, Response, maps:get(content, Response, undefined)) of
        undefined ->
            %% Try OpenAI format
            extract_openai_text(Response);
        Content when is_list(Content) ->
            TextBlocks = [maps:get(<<"text">>, Block, maps:get(text, Block, <<>>))
                         || Block <- Content,
                            maps:get(<<"type">>, Block, maps:get(type, Block, <<>>)) =:= <<"text">>],
            iolist_to_binary(TextBlocks);
        Content when is_binary(Content) ->
            Content;
        _ ->
            <<>>
    end.

%% @doc Build a tool result message to send back to the LLM.
%% Takes the tool call ID, tool name, and result content.
-spec build_tool_result_message(binary(), binary(), term()) -> map().
build_tool_result_message(ToolCallId, _ToolName, Result) ->
    ResultBin = case Result of
        R when is_binary(R) -> R;
        R when is_map(R)    -> jsx:encode(R);
        R when is_list(R)   -> jsx:encode(R);
        R -> list_to_binary(io_lib:format("~p", [R]))
    end,
    #{
        role => <<"tool">>,
        content => ResultBin,
        tool_use_id => ToolCallId
    }.

%% @doc Truncate a message list to fit within a token budget.
%% Keeps the system message (if any) and the most recent messages.
-spec truncate_messages(list(), non_neg_integer()) -> list().
truncate_messages(Messages, MaxTokens) ->
    %% Separate system messages from others
    {SystemMsgs, OtherMsgs} = lists:partition(fun(Msg) ->
        Role = maps:get(role, Msg, maps:get(<<"role">>, Msg, <<>>)),
        Role =:= <<"system">> orelse Role =:= system
    end, Messages),

    SystemTokens = estimate_tokens(SystemMsgs),
    RemainingBudget = MaxTokens - SystemTokens,

    %% Take messages from the end (most recent) that fit in budget
    ReversedOther = lists:reverse(OtherMsgs),
    SelectedReversed = select_messages_within_budget(ReversedOther, RemainingBudget, []),
    Selected = lists:reverse(SelectedReversed),

    SystemMsgs ++ Selected.

%% @doc Merge a system prompt into a message list.
%% If a system message already exists, appends to it.
%% Otherwise, prepends a new system message.
-spec merge_system_prompt(binary(), list()) -> list().
merge_system_prompt(SystemPrompt, Messages) ->
    case lists:partition(fun(Msg) ->
        Role = maps:get(role, Msg, maps:get(<<"role">>, Msg, <<>>)),
        Role =:= <<"system">> orelse Role =:= system
    end, Messages) of
        {[], OtherMsgs} ->
            [#{role => <<"system">>, content => SystemPrompt} | OtherMsgs];
        {[ExistingSystem | _], OtherMsgs} ->
            ExistingContent = maps:get(content, ExistingSystem,
                              maps:get(<<"content">>, ExistingSystem, <<>>)),
            MergedContent = <<ExistingContent/binary, "\n\n", SystemPrompt/binary>>,
            [ExistingSystem#{content => MergedContent} | OtherMsgs]
    end.

%%====================================================================
%% Internal Functions - Anthropic Format
%%====================================================================

%% @private
format_messages_anthropic(Messages) ->
    lists:map(fun(Msg) ->
        Role = ensure_binary(maps:get(role, Msg, maps:get(<<"role">>, Msg, <<"user">>))),
        Content = maps:get(content, Msg, maps:get(<<"content">>, Msg, <<>>)),
        FormattedContent = case Content of
            C when is_binary(C) ->
                [#{<<"type">> => <<"text">>, <<"text">> => C}];
            C when is_list(C) ->
                [format_content_block_anthropic(Block) || Block <- C];
            _ ->
                [#{<<"type">> => <<"text">>, <<"text">> => ensure_binary(Content)}]
        end,
        #{<<"role">> => Role, <<"content">> => FormattedContent}
    end, Messages).

%% @private
format_content_block_anthropic(Block) when is_map(Block) ->
    Block;
format_content_block_anthropic(Text) when is_binary(Text) ->
    #{<<"type">> => <<"text">>, <<"text">> => Text}.

%% @private
parse_anthropic_response(Response) ->
    Content = maps:get(<<"content">>, Response, maps:get(content, Response, [])),
    TextParts = [maps:get(<<"text">>, B, <<>>) || B <- ensure_list(Content),
                 maps:get(<<"type">>, B, <<>>) =:= <<"text">>],
    ToolCalls = extract_anthropic_tool_calls(Response),
    #{
        text => iolist_to_binary(TextParts),
        tool_calls => ToolCalls,
        stop_reason => maps:get(<<"stop_reason">>, Response,
                       maps:get(stop_reason, Response, undefined)),
        usage => maps:get(<<"usage">>, Response,
                 maps:get(usage, Response, #{})),
        raw => Response
    }.

%% @private
extract_anthropic_tool_calls(Response) ->
    Content = maps:get(<<"content">>, Response, maps:get(content, Response, [])),
    ToolBlocks = [B || B <- ensure_list(Content),
                  maps:get(<<"type">>, B, maps:get(type, B, <<>>)) =:= <<"tool_use">>],
    lists:map(fun(Block) ->
        #{
            id => maps:get(<<"id">>, Block, maps:get(id, Block, <<>>)),
            name => maps:get(<<"name">>, Block, maps:get(name, Block, <<>>)),
            arguments => maps:get(<<"input">>, Block, maps:get(input, Block, #{}))
        }
    end, ToolBlocks).

%%====================================================================
%% Internal Functions - OpenAI Format
%%====================================================================

%% @private
format_messages_openai(Messages) ->
    lists:map(fun(Msg) ->
        Role = ensure_binary(maps:get(role, Msg, maps:get(<<"role">>, Msg, <<"user">>))),
        Content = maps:get(content, Msg, maps:get(<<"content">>, Msg, <<>>)),
        ContentBin = case Content of
            C when is_binary(C) -> C;
            C when is_list(C) ->
                %% Flatten content blocks to text for OpenAI
                Parts = [maps:get(<<"text">>, B, maps:get(text, B, <<>>))
                        || B <- C, is_map(B)],
                iolist_to_binary(Parts);
            _ -> ensure_binary(Content)
        end,
        #{<<"role">> => Role, <<"content">> => ContentBin}
    end, Messages).

%% @private
parse_openai_response(Response) ->
    Choices = maps:get(<<"choices">>, Response, maps:get(choices, Response, [])),
    case Choices of
        [FirstChoice | _] ->
            Message = maps:get(<<"message">>, FirstChoice,
                      maps:get(message, FirstChoice, #{})),
            Content = maps:get(<<"content">>, Message,
                      maps:get(content, Message, <<>>)),
            ToolCalls = extract_openai_tool_calls(Response),
            #{
                text => ensure_binary_or_empty(Content),
                tool_calls => ToolCalls,
                stop_reason => maps:get(<<"finish_reason">>, FirstChoice,
                               maps:get(finish_reason, FirstChoice, undefined)),
                usage => maps:get(<<"usage">>, Response,
                         maps:get(usage, Response, #{})),
                raw => Response
            };
        [] ->
            #{
                text => <<>>,
                tool_calls => [],
                stop_reason => undefined,
                usage => #{},
                raw => Response
            }
    end.

%% @private
extract_openai_text(Response) ->
    Choices = maps:get(<<"choices">>, Response, maps:get(choices, Response, [])),
    case Choices of
        [FirstChoice | _] ->
            Message = maps:get(<<"message">>, FirstChoice,
                      maps:get(message, FirstChoice, #{})),
            ensure_binary_or_empty(
                maps:get(<<"content">>, Message,
                maps:get(content, Message, <<>>)));
        [] ->
            <<>>
    end.

%% @private
extract_openai_tool_calls(Response) ->
    Choices = maps:get(<<"choices">>, Response, maps:get(choices, Response, [])),
    case Choices of
        [FirstChoice | _] ->
            Message = maps:get(<<"message">>, FirstChoice,
                      maps:get(message, FirstChoice, #{})),
            RawCalls = maps:get(<<"tool_calls">>, Message,
                       maps:get(tool_calls, Message, [])),
            lists:map(fun(Call) ->
                Function = maps:get(<<"function">>, Call,
                           maps:get(function, Call, #{})),
                ArgsStr = maps:get(<<"arguments">>, Function,
                          maps:get(arguments, Function, <<"{}">>)),
                Args = case ArgsStr of
                    A when is_binary(A) ->
                        try jsx:decode(A, [return_maps]) catch _:_ -> #{} end;
                    A when is_map(A) ->
                        A;
                    _ ->
                        #{}
                end,
                #{
                    id => maps:get(<<"id">>, Call, maps:get(id, Call, <<>>)),
                    name => maps:get(<<"name">>, Function,
                            maps:get(name, Function, <<>>)),
                    arguments => Args
                }
            end, RawCalls);
        [] ->
            []
    end.

%%====================================================================
%% Internal Functions - Utility
%%====================================================================

%% @private
select_messages_within_budget([], _Budget, Acc) ->
    Acc;
select_messages_within_budget([Msg | Rest], Budget, Acc) ->
    Tokens = estimate_tokens([Msg]),
    case Tokens =< Budget of
        true ->
            select_messages_within_budget(Rest, Budget - Tokens, [Msg | Acc]);
        false ->
            Acc
    end.

%% @private
extract_message_text(Msg) ->
    Content = maps:get(content, Msg, maps:get(<<"content">>, Msg, <<>>)),
    case Content of
        C when is_binary(C) -> C;
        C when is_list(C) ->
            Parts = [maps:get(<<"text">>, B, maps:get(text, B, <<>>))
                    || B <- C, is_map(B)],
            iolist_to_binary(Parts);
        _ -> <<>>
    end.

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> list_to_binary(io_lib:format("~p", [V])).

%% @private
ensure_binary_or_empty(null) -> <<>>;
ensure_binary_or_empty(undefined) -> <<>>;
ensure_binary_or_empty(V) -> ensure_binary(V).

%% @private
ensure_list(L) when is_list(L) -> L;
ensure_list(_) -> [].
