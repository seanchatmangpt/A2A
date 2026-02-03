%%% @doc A2A Protocol Record Definitions
%%% Based on the A2A Protocol Specification v0.4.0
%%% https://github.com/a2aproject/A2A

-ifndef(A2A_HRL).
-define(A2A_HRL, true).

%%% ============================================================================
%%% Task States (TaskState enum)
%%% ============================================================================

-define(TASK_STATE_UNSPECIFIED, unspecified).
-define(TASK_STATE_SUBMITTED, submitted).
-define(TASK_STATE_WORKING, working).
-define(TASK_STATE_COMPLETED, completed).
-define(TASK_STATE_FAILED, failed).
-define(TASK_STATE_CANCELED, canceled).
-define(TASK_STATE_INPUT_REQUIRED, input_required).
-define(TASK_STATE_REJECTED, rejected).
-define(TASK_STATE_AUTH_REQUIRED, auth_required).

%% Terminal states - task cannot transition from these
-define(TERMINAL_STATES, [?TASK_STATE_COMPLETED, ?TASK_STATE_FAILED,
                          ?TASK_STATE_CANCELED, ?TASK_STATE_REJECTED]).

%% Interrupted states - awaiting external action
-define(INTERRUPTED_STATES, [?TASK_STATE_INPUT_REQUIRED, ?TASK_STATE_AUTH_REQUIRED]).

%%% ============================================================================
%%% Role enum
%%% ============================================================================

-define(ROLE_UNSPECIFIED, unspecified).
-define(ROLE_USER, user).
-define(ROLE_AGENT, agent).

%%% ============================================================================
%%% Part - Content container
%%% ============================================================================

-record(part, {
    %% One of: {text, binary()} | {raw, binary()} | {url, binary()} | {data, map()}
    content :: {text, binary()} | {raw, binary()} | {url, binary()} | {data, map()},
    metadata = #{} :: map(),
    filename :: binary() | undefined,
    media_type :: binary() | undefined
}).

-type part() :: #part{}.

%%% ============================================================================
%%% Message - Single turn of communication
%%% ============================================================================

-record(message, {
    message_id :: binary(),           % Required: unique identifier
    context_id :: binary() | undefined,
    task_id :: binary() | undefined,
    role :: user | agent,             % Required
    parts = [] :: [part()],           % Required: at least one part
    metadata = #{} :: map(),
    extensions = [] :: [binary()],
    reference_task_ids = [] :: [binary()]
}).

-type message() :: #message{}.

%%% ============================================================================
%%% TaskStatus - Status container
%%% ============================================================================

-record(task_status, {
    state :: atom(),                  % Required: TaskState
    message :: message() | undefined,
    timestamp :: integer()            % Unix timestamp in milliseconds
}).

-type task_status() :: #task_status{}.

%%% ============================================================================
%%% Artifact - Task output
%%% ============================================================================

-record(artifact, {
    artifact_id :: binary(),          % Required: unique within task
    name :: binary() | undefined,
    description :: binary() | undefined,
    parts = [] :: [part()],           % Required: at least one part
    metadata = #{} :: map(),
    extensions = [] :: [binary()]
}).

-type artifact() :: #artifact{}.

%%% ============================================================================
%%% Task - Core unit of work
%%% ============================================================================

-record(task, {
    id :: binary(),                   % Required: unique identifier
    context_id :: binary(),           % Required: conversation group
    status :: task_status(),          % Required: current status
    artifacts = [] :: [artifact()],
    history = [] :: [message()],
    metadata = #{} :: map()
}).

-type task() :: #task{}.

%%% ============================================================================
%%% Events for streaming
%%% ============================================================================

-record(task_status_update_event, {
    task_id :: binary(),              % Required
    context_id :: binary(),           % Required
    status :: task_status(),          % Required
    metadata = #{} :: map()
}).

-type task_status_update_event() :: #task_status_update_event{}.

-record(task_artifact_update_event, {
    task_id :: binary(),              % Required
    context_id :: binary(),           % Required
    artifact :: artifact(),           % Required
    append = false :: boolean(),
    last_chunk = false :: boolean(),
    metadata = #{} :: map()
}).

-type task_artifact_update_event() :: #task_artifact_update_event{}.

%%% ============================================================================
%%% Push Notification Configuration
%%% ============================================================================

-record(authentication_info, {
    scheme :: binary(),               % Required: HTTP auth scheme (Bearer, Basic, etc.)
    credentials :: binary() | undefined
}).

-type authentication_info() :: #authentication_info{}.

-record(push_notification_config, {
    id :: binary() | undefined,
    url :: binary(),                  % Required: webhook URL
    token :: binary() | undefined,
    authentication :: authentication_info() | undefined
}).

-type push_notification_config() :: #push_notification_config{}.

-record(task_push_notification_config, {
    tenant :: binary() | undefined,
    id :: binary(),                   % Required
    task_id :: binary(),              % Required
    push_notification_config :: push_notification_config() % Required
}).

-type task_push_notification_config() :: #task_push_notification_config{}.

%%% ============================================================================
%%% Agent Card and Skills
%%% ============================================================================

-record(agent_interface, {
    url :: binary(),                  % Required: absolute HTTPS URL
    protocol_binding :: binary(),     % Required: JSONRPC, GRPC, HTTP+JSON
    tenant :: binary() | undefined,
    protocol_version :: binary()      % Required: e.g., "0.4"
}).

-type agent_interface() :: #agent_interface{}.

-record(agent_provider, {
    url :: binary(),                  % Required
    organization :: binary()          % Required
}).

-type agent_provider() :: #agent_provider{}.

-record(agent_extension, {
    uri :: binary(),
    description :: binary() | undefined,
    required = false :: boolean(),
    params = #{} :: map()
}).

-type agent_extension() :: #agent_extension{}.

-record(agent_capabilities, {
    streaming :: boolean() | undefined,
    push_notifications :: boolean() | undefined,
    extensions = [] :: [agent_extension()],
    extended_agent_card :: boolean() | undefined
}).

-type agent_capabilities() :: #agent_capabilities{}.

-record(agent_skill, {
    id :: binary(),                   % Required
    name :: binary(),                 % Required
    description :: binary(),          % Required
    tags = [] :: [binary()],          % Required
    examples = [] :: [binary()],
    input_modes = [] :: [binary()],
    output_modes = [] :: [binary()],
    security_requirements = [] :: [map()]
}).

-type agent_skill() :: #agent_skill{}.

-record(agent_card, {
    name :: binary(),                 % Required
    description :: binary(),          % Required
    supported_interfaces = [] :: [agent_interface()], % Required
    provider :: agent_provider() | undefined,
    version :: binary(),              % Required
    documentation_url :: binary() | undefined,
    capabilities :: agent_capabilities(), % Required
    security_schemes = #{} :: map(),
    security_requirements = [] :: [map()],
    default_input_modes = [] :: [binary()], % Required
    default_output_modes = [] :: [binary()], % Required
    skills = [] :: [agent_skill()],   % Required
    signatures = [] :: [map()],
    icon_url :: binary() | undefined
}).

-type agent_card() :: #agent_card{}.

%%% ============================================================================
%%% Request/Response Messages
%%% ============================================================================

-record(send_message_configuration, {
    accepted_output_modes = [] :: [binary()],
    push_notification_config :: push_notification_config() | undefined,
    history_length :: integer() | undefined,
    blocking = false :: boolean()
}).

-type send_message_configuration() :: #send_message_configuration{}.

-record(send_message_request, {
    tenant :: binary() | undefined,
    message :: message(),             % Required
    configuration :: send_message_configuration() | undefined,
    metadata = #{} :: map()
}).

-type send_message_request() :: #send_message_request{}.

-record(get_task_request, {
    tenant :: binary() | undefined,
    id :: binary(),                   % Required
    history_length :: integer() | undefined
}).

-type get_task_request() :: #get_task_request{}.

-record(list_tasks_request, {
    tenant :: binary() | undefined,
    context_id :: binary() | undefined,
    status :: atom() | undefined,
    page_size :: integer() | undefined,
    page_token :: binary() | undefined,
    history_length :: integer() | undefined,
    status_timestamp_after :: integer() | undefined,
    include_artifacts :: boolean() | undefined
}).

-type list_tasks_request() :: #list_tasks_request{}.

-record(cancel_task_request, {
    tenant :: binary() | undefined,
    id :: binary()                    % Required
}).

-type cancel_task_request() :: #cancel_task_request{}.

-record(subscribe_to_task_request, {
    tenant :: binary() | undefined,
    id :: binary()                    % Required
}).

-type subscribe_to_task_request() :: #subscribe_to_task_request{}.

%%% ============================================================================
%%% Stream Response wrapper
%%% ============================================================================

-record(stream_response, {
    %% One of: {task, task()} | {message, message()} |
    %%         {status_update, task_status_update_event()} |
    %%         {artifact_update, task_artifact_update_event()}
    payload :: {task, task()} | {message, message()} |
               {status_update, task_status_update_event()} |
               {artifact_update, task_artifact_update_event()}
}).

-type stream_response() :: #stream_response{}.

%%% ============================================================================
%%% JSON-RPC 2.0 Messages
%%% ============================================================================

-record(jsonrpc_request, {
    jsonrpc = <<"2.0">> :: binary(),
    method :: binary(),
    params = #{} :: map(),
    id :: binary() | integer() | undefined
}).

-record(jsonrpc_response, {
    jsonrpc = <<"2.0">> :: binary(),
    result :: term() | undefined,
    error :: map() | undefined,
    id :: binary() | integer() | undefined
}).

-record(jsonrpc_error, {
    code :: integer(),
    message :: binary(),
    data :: term() | undefined
}).

%% Standard JSON-RPC error codes
-define(JSONRPC_PARSE_ERROR, -32700).
-define(JSONRPC_INVALID_REQUEST, -32600).
-define(JSONRPC_METHOD_NOT_FOUND, -32601).
-define(JSONRPC_INVALID_PARAMS, -32602).
-define(JSONRPC_INTERNAL_ERROR, -32603).

%% A2A specific error codes (application-defined)
-define(A2A_TASK_NOT_FOUND, -32001).
-define(A2A_TASK_ALREADY_TERMINAL, -32002).
-define(A2A_UNSUPPORTED_OPERATION, -32003).
-define(A2A_AUTHENTICATION_REQUIRED, -32004).

-endif.
