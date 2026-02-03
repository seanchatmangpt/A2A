%%% @doc A2A Echo Handler Example
%%%
%%% A simple example handler that echoes back incoming messages.
%%% Demonstrates the a2a_handler behaviour implementation.
-module(a2a_echo_handler).
-behaviour(a2a_handler).

-include("a2a.hrl").

%% a2a_handler callbacks
-export([
    init/2,
    process/2,
    handle_message/2,
    terminate/2
]).

-record(state, {
    echo_count = 0 :: non_neg_integer(),
    last_message :: message() | undefined
}).

%%% ============================================================================
%%% a2a_handler Callbacks
%%% ============================================================================

%% @doc Initialize the handler state
init(_Task, Message) ->
    {ok, #state{last_message = Message}}.

%% @doc Process the task - create echo artifact
process(Task, State) ->
    %% Get the last message to echo
    Message = State#state.last_message,

    %% Extract text from message parts
    EchoText = extract_text(Message#message.parts),

    %% Create echo artifact
    Artifact = #artifact{
        artifact_id = generate_id(),
        name = <<"Echo Response">>,
        description = <<"Echoed message content">>,
        parts = [
            #part{
                content = {text, <<"Echo: ", EchoText/binary>>},
                media_type = <<"text/plain">>
            }
        ],
        metadata = #{
            <<"echoCount">> => State#state.echo_count + 1,
            <<"originalMessageId">> => Message#message.message_id
        }
    },

    %% Return success with artifact
    {ok, #{
        artifacts => [Artifact],
        response_message => create_response_message(Task, EchoText)
    }}.

%% @doc Handle additional messages
handle_message(Message, State) ->
    %% Update state with new message
    NewState = State#state{
        last_message = Message,
        echo_count = State#state.echo_count + 1
    },
    {continue, NewState}.

%% @doc Cleanup on termination
terminate(_Reason, _State) ->
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% Extract text content from message parts
extract_text(Parts) ->
    TextParts = lists:filtermap(fun(#part{content = Content}) ->
        case Content of
            {text, Text} -> {true, Text};
            _ -> false
        end
    end, Parts),

    case TextParts of
        [] -> <<"(no text content)">>;
        _ -> iolist_to_binary(lists:join(<<" ">>, TextParts))
    end.

%% Create a response message
create_response_message(Task, EchoText) ->
    #message{
        message_id = generate_id(),
        context_id = Task#task.context_id,
        task_id = Task#task.id,
        role = agent,
        parts = [
            #part{
                content = {text, <<"I received: ", EchoText/binary>>},
                media_type = <<"text/plain">>
            }
        ]
    }.

%% Generate a UUID-like identifier
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>.
