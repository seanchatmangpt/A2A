%%% @doc A2A Test Utilities Module
%%%
%%% Comprehensive test helper module for A2A Erlang/OTP implementation.
%%% Provides convenient functions for creating test data, asserting conditions,
%%% managing test processes, and setting up test scenarios.
%%%
%%% @end
-module(a2a_test_utils).

%% Test Data Generators
-export([
    new_message/0,
    new_message/1,
    new_message/2,
    new_text_message/1,
    new_text_message/2,
    new_user_message/1,
    new_agent_message/1,
    new_artifact/0,
    new_artifact/1,
    new_artifact/2,
    new_text_artifact/2,
    new_agent_card/0,
    new_agent_card/1,
    new_task_status/1,
    new_push_config/1
]).

%% Message Builders
-export([
    message_with_id/1,
    message_with_role/2,
    message_with_part/2,
    message_with_parts/2,
    message_with_context/2,
    message_with_task/2,
    message_with_metadata/2
]).

%% Part Builders
-export([
    text_part/1,
    data_part/1,
    url_part/1,
    raw_part/1,
    part_with_metadata/2,
    part_with_media_type/2
]).

%% Artifact Builders
-export([
    artifact_with_id/1,
    artifact_with_name/2,
    artifact_with_description/2,
    artifact_with_parts/2,
    artifact_append/2
]).

%% Agent Card Builders
-export([
    agent_card_with_name/2,
    agent_card_with_skill/2,
    agent_card_with_capability/2
]).

%% Assertion Helpers
-export([
    assert_task_state/2,
    assert_task_id/2,
    assert_context_id/2,
    assert_artifact_count/2,
    assert_history_length/2,
    assert_message_count/2,
    assert_has_artifact/2,
    assert_terminal_state/1,
    assert_status_message/2
]).

%% Test Process Management
-export[
    start_test_task/1,
    start_test_task/2,
    start_test_task/3,
    wait_for_state/2,
    wait_for_state/3,
    wait_for_artifact_count/3,
    collect_events/2,
    collect_events/3,
    flush_events/0,
    flush_events/1
].

%% Mock Utilities
-export([
    mock_handler/0,
    mock_handler/1,
    mock_echo_handler/0,
    mock_failing_handler/1,
    mock_input_required_handler/1,
    mock_auth_required_handler/1
]).

%% Utility Functions
-export([
    test_id/0,
    test_id/1,
    unique_context/0,
    unique_task_id/0,
    current_timestamp/0,
    timestamp_in_future/1,
    timestamp_in_past/1
]).

-include_lib("stdlib/include/assert.hrl").
-include("../../../include/a2a.hrl").

%%% ============================================================================
%%% Test Data Generators
%%% ============================================================================

%% @doc Create a new minimal message with default values
-spec new_message() -> message().
new_message() ->
    new_message(text).

%% @doc Create a new message with specified content type
-spec new_message(text | data | url | raw) -> message().
new_message(Type) ->
    MessageId = test_id("msg"),
    Content = case Type of
        text -> {text, <<"Test message">>};
        data -> {data, #{<<"test">> => <<"data">>}};
        url -> {url, <<"https://example.com/resource">>};
        raw -> {raw, crypto:strong_rand_bytes(16)}
    end,
    #message{
        message_id = MessageId,
        role = user,
        parts = [#part{content = Content}],
        metadata = #{},
        extensions = [],
        reference_task_ids = []
    }.

%% @doc Create a new message with custom role
-spec new_message(text | data | url | raw, user | agent) -> message().
new_message(Type, Role) ->
    Msg = new_message(Type),
    Msg#message{role = Role}.

%% @doc Create a new text message with given content
-spec new_text_message(binary()) -> message().
new_text_message(Text) ->
    #message{
        message_id = test_id("msg"),
        role = user,
        parts = [#part{content = {text, Text}}],
        metadata = #{},
        extensions = [],
        reference_task_ids = []
    }.

%% @doc Create a new text message with role and content
-spec new_text_message(user | agent, binary()) -> message().
new_text_message(Role, Text) ->
    #message{
        message_id = test_id("msg"),
        role = Role,
        parts = [#part{content = {text, Text}}],
        metadata = #{},
        extensions = [],
        reference_task_ids = []
    }.

%% @doc Create a new user message with text content
-spec new_user_message(binary()) -> message().
new_user_message(Text) ->
    new_text_message(user, Text).

%% @doc Create a new agent message with text content
-spec new_agent_message(binary()) -> message().
new_agent_message(Text) ->
    new_text_message(agent, Text).

%% @doc Create a new minimal artifact
-spec new_artifact() -> artifact().
new_artifact() ->
    ArtifactId = test_id("artifact"),
    #artifact{
        artifact_id = ArtifactId,
        name = undefined,
        description = undefined,
        parts = [#part{content = {text, <<"Test artifact content">>}}],
        metadata = #{},
        extensions = []
    }.

%% @doc Create a new artifact with specified name
-spec new_artifact(binary()) -> artifact().
new_artifact(Name) ->
    ArtifactId = test_id("artifact"),
    #artifact{
        artifact_id = ArtifactId,
        name = Name,
        description = undefined,
        parts = [#part{content = {text, <<"Test artifact content">>}}],
        metadata = #{},
        extensions = []
    }.

%% @doc Create a new artifact with name and description
-spec new_artifact(binary(), binary()) -> artifact().
new_artifact(Name, Description) ->
    ArtifactId = test_id("artifact"),
    #artifact{
        artifact_id = ArtifactId,
        name = Name,
        description = Description,
        parts = [#part{content = {text, <<"Test artifact content">>}}],
        metadata = #{},
        extensions = []
    }.

%% @doc Create a new text artifact with given name and content
-spec new_text_artifact(binary(), binary()) -> artifact().
new_text_artifact(Name, Content) ->
    ArtifactId = test_id("artifact"),
    #artifact{
        artifact_id = ArtifactId,
        name = Name,
        description = undefined,
        parts = [#part{content = {text, Content}}],
        metadata = #{},
        extensions = []
    }.

%% @doc Create a default agent card for testing
-spec new_agent_card() -> agent_card().
new_agent_card() ->
    new_agent_card(<<"Test Agent">>).

%% @doc Create a new agent card with specified name
-spec new_agent_card(binary()) -> agent_card().
new_agent_card(Name) ->
    #agent_card{
        name = Name,
        description = <<"Test agent for unit testing">>,
        version = <<"0.1.0">>,
        supported_interfaces = [
            #agent_interface{
                url = <<"http://localhost:8080">>,
                protocol_binding = <<"JSONRPC">>,
                protocol_version = <<"0.4">>
            }
        ],
        provider = #agent_provider{
            url = <<"https://example.com">>,
            organization = <<"Test Organization">>
        },
        capabilities = #agent_capabilities{
            streaming = true,
            push_notifications = true,
            extended_agent_card = false,
            extensions = []
        },
        default_input_modes = [<<"text/plain">>],
        default_output_modes = [<<"text/plain">>],
        skills = [
            #agent_skill{
                id = <<"test">>,
                name = <<"Test">>,
                description = <<"Test skill">>,
                tags = [<<"test">>],
                examples = [],
                input_modes = [],
                output_modes = [],
                security_requirements = []
            }
        ],
        security_schemes = #{},
        security_requirements = [],
        documentation_url = undefined,
        signatures = [],
        icon_url = undefined
    }.

%% @doc Create a new task status
-spec new_task_status(atom()) -> task_status().
new_task_status(State) ->
    #task_status{
        state = State,
        message = undefined,
        timestamp = current_timestamp()
    }.

%% @doc Create a new push notification configuration
-spec new_push_config(binary()) -> push_notification_config().
new_push_config(Url) ->
    #push_notification_config{
        id = test_id("push"),
        url = Url,
        token = undefined,
        authentication = undefined
    }.

%%% ============================================================================
%%% Message Builders
%%% ============================================================================

%% @doc Set message ID
-spec message_with_id(binary(), message()) -> message().
message_with_id(Id, Message) ->
    Message#message{message_id = Id}.

%% @doc Set message role
-spec message_with_role(user | agent, message()) -> message().
message_with_role(Role, Message) ->
    Message#message{role = Role}.

%% @doc Add a part to message
-spec message_with_part(part(), message()) -> message().
message_with_part(Part, Message) ->
    Parts = Message#message.parts ++ [Part],
    Message#message{parts = Parts}.

%% @doc Set multiple parts on message
-spec message_with_parts([part()], message()) -> message().
message_with_parts(Parts, Message) ->
    Message#message{parts = Parts}.

%% @doc Set context ID
-spec message_with_context(binary(), message()) -> message().
message_with_context(ContextId, Message) ->
    Message#message{context_id = ContextId}.

%% @doc Set task ID
-spec message_with_task(binary(), message()) -> message().
message_with_task(TaskId, Message) ->
    Message#message{task_id = TaskId}.

%% @doc Set metadata
-spec message_with_metadata(map(), message()) -> message().
message_with_metadata(Metadata, Message) ->
    Message#message{metadata = Metadata}.

%%% ============================================================================
%%% Part Builders
%%% ============================================================================

%% @doc Create a text part
-spec text_part(binary()) -> part().
text_part(Text) ->
    #part{
        content = {text, Text},
        metadata = #{},
        filename = undefined,
        media_type = <<"text/plain">>
    }.

%% @doc Create a data part
-spec data_part(map()) -> part().
data_part(Data) ->
    #part{
        content = {data, Data},
        metadata = #{},
        filename = undefined,
        media_type = <<"application/json">>
    }.

%% @doc Create a URL part
-spec url_part(binary()) -> part().
url_part(Url) ->
    #part{
        content = {url, Url},
        metadata = #{},
        filename = undefined,
        media_type = undefined
    }.

%% @doc Create a raw data part
-spec raw_part(binary()) -> part().
raw_part(Data) ->
    #part{
        content = {raw, Data},
        metadata = #{},
        filename = undefined,
        media_type = <<"application/octet-stream">>
    }.

%% @doc Add metadata to a part
-spec part_with_metadata(map(), part()) -> part().
part_with_metadata(Metadata, Part) ->
    Part#part{metadata = Metadata}.

%% @doc Set media type on a part
-spec part_with_media_type(binary(), part()) -> part().
part_with_media_type(MediaType, Part) ->
    Part#part{media_type = MediaType}.

%%% ============================================================================
%%% Artifact Builders
%%% ============================================================================

%% @doc Set artifact ID
-spec artifact_with_id(binary(), artifact()) -> artifact().
artifact_with_id(Id, Artifact) ->
    Artifact#artifact{artifact_id = Id}.

%% @doc Set artifact name
-spec artifact_with_name(binary(), artifact()) -> artifact().
artifact_with_name(Name, Artifact) ->
    Artifact#artifact{name = Name}.

%% @doc Set artifact description
-spec artifact_with_description(binary(), artifact()) -> artifact().
artifact_with_description(Description, Artifact) ->
    Artifact#artifact{description = Description}.

%% @doc Set artifact parts
-spec artifact_with_parts([part()], artifact()) -> artifact().
artifact_with_parts(Parts, Artifact) ->
    Artifact#artifact{parts = Parts}.

%% @doc Append a part to artifact
-spec artifact_append(part(), artifact()) -> artifact().
artifact_append(Part, Artifact) ->
    Parts = Artifact#artifact.parts ++ [Part],
    Artifact#artifact{parts = Parts}.

%%% ============================================================================
%%% Agent Card Builders
%%% ============================================================================

%% @doc Set agent card name
-spec agent_card_with_name(binary(), agent_card()) -> agent_card().
agent_card_with_name(Name, Card) ->
    Card#agent_card{name = Name}.

%% @doc Add a skill to agent card
-spec agent_card_with_skill(agent_skill(), agent_card()) -> agent_card().
agent_card_with_skill(Skill, Card) ->
    Skills = Card#agent_card.skills ++ [Skill],
    Card#agent_card{skills = Skills}.

%% @doc Set agent capabilities
-spec agent_card_with_capability(agent_capabilities(), agent_card()) -> agent_card().
agent_card_with_capability(Capabilities, Card) ->
    Card#agent_card{capabilities = Capabilities}.

%%% ============================================================================
%%% Assertion Helpers
%%% ============================================================================

%% @doc Assert that task is in expected state
-spec assert_task_state(atom(), task()) -> task().
assert_task_state(ExpectedState, Task) ->
    ActualState = (Task#task.status)#task_status.state,
    ?assertEqual(ExpectedState, ActualState,
        {expected_state, ExpectedState, actual_state, ActualState}),
    Task.

%% @doc Assert that task has expected ID
-spec assert_task_id(binary(), task()) -> task().
assert_task_id(ExpectedId, Task) ->
    ?assertEqual(ExpectedId, Task#task.id),
    Task.

%% @doc Assert that task has expected context ID
-spec assert_context_id(binary(), task()) -> task().
assert_context_id(ExpectedContextId, Task) ->
    ?assertEqual(ExpectedContextId, Task#task.context_id),
    Task.

%% @doc Assert that task has expected number of artifacts
-spec assert_artifact_count(integer(), task()) -> task().
assert_artifact_count(ExpectedCount, Task) ->
    ActualCount = length(Task#task.artifacts),
    ?assertEqual(ExpectedCount, ActualCount),
    Task.

%% @doc Assert that task history has expected length
-spec assert_history_length(integer(), task()) -> task().
assert_history_length(ExpectedLength, Task) ->
    ActualLength = length(Task#task.history),
    ?assertEqual(ExpectedLength, ActualLength),
    Task.

%% @doc Assert that task history has expected number of messages
-spec assert_message_count(integer(), task()) -> task().
assert_message_count(ExpectedCount, Task) ->
    assert_history_length(ExpectedCount, Task).

%% @doc Assert that task contains an artifact with given ID
-spec assert_has_artifact(binary(), task()) -> task().
assert_has_artifact(ArtifactId, Task) ->
    Artifacts = Task#task.artifacts,
    Found = lists:any(fun(A) -> A#artifact.artifact_id =:= ArtifactId end, Artifacts),
    ?assert(Found, {artifact_not_found, ArtifactId}),
    Task.

%% @doc Assert that task is in a terminal state
-spec assert_terminal_state(task()) -> task().
assert_terminal_state(Task) ->
    State = (Task#task.status)#task_status.state,
    ?assert(lists:member(State, ?TERMINAL_STATES),
        {not_terminal_state, State}),
    Task.

%% @doc Assert that status has a message
-spec assert_status_message(boolean(), task()) -> task().
assert_status_message(ShouldHave, Task) ->
    Status = Task#task.status,
    HasMessage = Status#task_status.message =/= undefined,
    ?assertEqual(ShouldHave, HasMessage),
    Task.

%%% ============================================================================
%%% Test Process Management
%%% ============================================================================

%% @doc Start a test task with default message
-spec start_test_task(message()) -> {ok, pid()}.
start_test_task(Message) ->
    start_test_task(Message, #{}).

%% @doc Start a test task with options
-spec start_test_task(message(), map()) -> {ok, pid()}.
start_test_task(Message, Opts) ->
    ContextId = unique_context(),
    MessageWithContext = Message#message{context_id = ContextId},
    a2a_task_statem:start_link(MessageWithContext, Opts).

%% @doc Start a test task with message, context, and options
-spec start_test_task(message(), binary(), map()) -> {ok, pid()}.
start_test_task(Message, ContextId, Opts) ->
    MessageWithContext = Message#message{context_id = ContextId},
    a2a_task_statem:start_link(MessageWithContext, Opts).

%% @doc Wait for task to reach expected state (default 5s timeout)
-spec wait_for_state(pid(), atom()) -> ok | {error, timeout}.
wait_for_state(TaskPid, ExpectedState) ->
    wait_for_state(TaskPid, ExpectedState, 5000).

%% @doc Wait for task to reach expected state with custom timeout
-spec wait_for_state(pid(), atom(), integer()) -> ok | {error, timeout}.
wait_for_state(TaskPid, ExpectedState, Timeout) ->
    Start = erlang:monotonic_time(millisecond),
    wait_for_state_loop(TaskPid, ExpectedState, Timeout, Start).

wait_for_state_loop(TaskPid, ExpectedState, Timeout, Start) ->
    Elapsed = erlang:monotonic_time(millisecond) - Start,
    if
        Elapsed >= Timeout ->
            {error, timeout};
        true ->
            case a2a_task_statem:get_task(TaskPid) of
                {ok, Task} ->
                    CurrentState = (Task#task.status)#task_status.state,
                    if
                        CurrentState =:= ExpectedState ->
                            ok;
                        CurrentState =:= undefined ->
                            timer:sleep(50),
                            wait_for_state_loop(TaskPid, ExpectedState, Timeout, Start);
                        true ->
                            case lists:member(CurrentState, ?TERMINAL_STATES) of
                                true ->
                                    {error, {terminal_state_reached, CurrentState}};
                                false ->
                                    timer:sleep(50),
                                    wait_for_state_loop(TaskPid, ExpectedState, Timeout, Start)
                            end
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @doc Wait for task to have expected artifact count
-spec wait_for_artifact_count(pid(), integer(), integer()) -> ok | {error, timeout}.
wait_for_artifact_count(TaskPid, ExpectedCount, Timeout) ->
    Start = erlang:monotonic_time(millisecond),
    wait_for_artifact_count_loop(TaskPid, ExpectedCount, Timeout, Start).

wait_for_artifact_count_loop(TaskPid, ExpectedCount, Timeout, Start) ->
    Elapsed = erlang:monotonic_time(millisecond) - Start,
    if
        Elapsed >= Timeout ->
            {error, timeout};
        true ->
            case a2a_task_statem:get_task(TaskPid) of
                {ok, Task} ->
                    ActualCount = length(Task#task.artifacts),
                    if
                        ActualCount >= ExpectedCount ->
                            ok;
                        true ->
                            timer:sleep(50),
                            wait_for_artifact_count_loop(TaskPid, ExpectedCount, Timeout, Start)
                    end;
                {error, _Reason} ->
                    timer:sleep(50),
                    wait_for_artifact_count_loop(TaskPid, ExpectedCount, Timeout, Start)
            end
    end.

%% @doc Collect events from task (default 1s timeout)
-spec collect_events(pid(), integer()) -> [term()].
collect_events(TaskPid, ExpectedCount) ->
    collect_events(TaskPid, ExpectedCount, 1000).

%% @doc Collect events from task with custom timeout
-spec collect_events(pid(), integer(), integer()) -> [term()].
collect_events(_TaskPid, ExpectedCount, Timeout) ->
    collect_events_loop(ExpectedCount, Timeout, []).

collect_events_loop(0, _Timeout, Acc) ->
    lists:reverse(Acc);
collect_events_loop(_Count, Timeout, Acc) when Timeout =< 0 ->
    lists:reverse(Acc);
collect_events_loop(Count, Timeout, Acc) ->
    receive
        {a2a_task_event, _TaskId, Event} ->
            collect_events_loop(Count - 1, Timeout - 10, [Event | Acc]);
        Other ->
            %% Unexpected message, put it back
            self() ! Other,
            collect_events_loop(Count, Timeout - 10, Acc)
    after 10 ->
        collect_events_loop(Count, Timeout - 10, Acc)
    end.

%% @doc Flush all events from mailbox (default 100ms)
-spec flush_events() -> [term()].
flush_events() ->
    flush_events(100).

%% @doc Flush all events from mailbox with custom timeout
-spec flush_events(integer()) -> [term()].
flush_events(Timeout) ->
    flush_events_loop(Timeout, []).

flush_events_loop(Timeout, Acc) when Timeout =< 0 ->
    lists:reverse(Acc);
flush_events_loop(Timeout, Acc) ->
    receive
        {a2a_task_event, _TaskId, Event} ->
            flush_events_loop(Timeout - 1, [Event | Acc]);
        Other ->
            %% Non-A2A message, discard
            flush_events_loop(Timeout - 1, Acc)
    after 0 ->
        lists:reverse(Acc)
    end.

%%% ============================================================================
%%% Mock Utilities
%%% ============================================================================

%% @doc Create a mock handler module that does nothing
-spec mock_handler() -> module().
mock_handler() ->
    mock_handler(echo).

%% @doc Create a mock handler with specified behavior
-spec mock_handler(echo | null | passthrough) -> module().
mock_handler(echo) ->
    mock_echo_handler();
mock_handler(null) ->
    create_mock_handler(null_handler_behavior);
mock_handler(passthrough) ->
    create_mock_handler(passthrough_handler_behavior).

%% @doc Create an echo handler that returns the message
-spec mock_echo_handler() -> module().
mock_echo_handler() ->
    create_mock_handler(echo_handler_behavior).

%% @doc Create a handler that always fails with given reason
-spec mock_failing_handler(term()) -> module().
mock_failing_handler(Reason) ->
    create_mock_handler({failing_handler_behavior, Reason}).

%% @doc Create a handler that requests input
-spec mock_input_required_handler(binary()) -> module().
mock_input_required_handler(Prompt) ->
    create_mock_handler({input_required_handler_behavior, Prompt}).

%% @doc Create a handler that requests authentication
-spec mock_auth_required_handler(map()) -> module().
mock_auth_required_handler(Details) ->
    create_mock_handler({auth_required_handler_behavior, Details}).

%% Internal: Create a mock handler module dynamically
create_mock_handler(Behavior) ->
    %% For now, return a simple module reference
    %% In a real implementation, you'd use meck or similar
    case Behavior of
        echo_handler_behavior ->
            a2a_echo_handler;
        null_handler_behavior ->
            a2a_null_test_handler;
        passthrough_handler_behavior ->
            a2a_passthrough_test_handler;
        {failing_handler_behavior, _Reason} ->
            a2a_failing_test_handler;
        {input_required_handler_behavior, _Prompt} ->
            a2a_input_test_handler;
        {auth_required_handler_behavior, _Details} ->
            a2a_auth_test_handler
    end.

%%% ============================================================================
%%% Utility Functions
%%% ============================================================================

%% @doc Generate a test ID with prefix
-spec test_id() -> binary().
test_id() ->
    test_id(<<"test">>).

%% @doc Generate a test ID with custom prefix
-spec test_id(binary()) -> binary().
test_id(Prefix) ->
    Timestamp = erlang:unique_integer([positive]),
    BinPrefix = case is_list(Prefix) of
        true -> list_to_binary(Prefix);
        false -> Prefix
    end,
    <<BinPrefix/binary, "-", (integer_to_binary(Timestamp))/binary>>.

%% @doc Generate a unique context ID for testing
-spec unique_context() -> binary().
unique_context() ->
    test_id(<<"context">>).

%% @doc Generate a unique task ID for testing
-spec unique_task_id() -> binary().
unique_task_id() ->
    test_id(<<"task">>).

%% @doc Get current timestamp in milliseconds
-spec current_timestamp() -> integer().
current_timestamp() ->
    erlang:system_time(millisecond).

%% @doc Get timestamp in the future (milliseconds from now)
-spec timestamp_in_future(integer()) -> integer().
timestamp_in_future(Millis) ->
    current_timestamp() + Millis.

%% @doc Get timestamp in the past (milliseconds before now)
-spec timestamp_in_past(integer()) -> integer().
timestamp_in_past(Millis) ->
    current_timestamp() - Millis.
