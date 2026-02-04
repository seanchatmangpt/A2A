%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Mnesia Schema Definitions
%%%
%%% This header file defines all Mnesia records used for YAWL workflow
%%% persistence. These records enable workflow state to survive node
%%% restarts and support distributed workflow execution.
%%%
%%% @end
%%%-------------------------------------------------------------------

%%====================================================================
%% Workflow Persistence Records
%%====================================================================

-record(yawl_workflow_persist, {
    workflow_id        :: binary(),
    spec_id            :: binary(),
    pattern_type       :: atom(),
    status             :: workflow_status(),
    marking            :: map(),
    current_place      :: atom() | undefined,
    data               :: map(),
    parent_workflow_id :: binary() | undefined,
    created_at         :: integer(),
    updated_at         :: integer(),
    completed_at       :: integer() | undefined,
    error              :: term() | undefined
}).

%%====================================================================
%% Work Item Persistence Records
%%====================================================================

-record(yawl_workitem_persist, {
    workitem_id      :: binary(),
    workflow_id      :: binary(),
    task_id          :: atom(),
    task_name        :: binary(),
    status           :: pending | allocated | started | completed | failed | cancelled,
    data             :: map(),
    allocated_to     :: {pid(), term()} | undefined,
    allocation_time  :: integer() | undefined,
    start_time       :: integer() | undefined,
    completion_time  :: integer() | undefined,
    error            :: term() | undefined,
    retry_count      :: non_neg_integer(),
    priority         :: low | normal | high | urgent
}).

%%====================================================================
%% Resource Persistence Records
%%====================================================================

-record(yawl_resource_persist, {
    resource_id     :: binary(),
    resource_type   :: human | service | system,
    name            :: binary(),
    capabilities    :: [atom()],
    attributes      :: map(),
    status          :: available | busy | unavailable | offline,
    current_load    :: non_neg_integer(),
    max_capacity    :: pos_integer(),
    last_heartbeat  :: integer() | undefined,
    metadata        :: map()
}).

%%====================================================================
%% Task Execution History Records
%%====================================================================

-record(yawl_execution_history, {
    history_id      :: binary(),
    workflow_id     :: binary(),
    workitem_id     :: binary() | undefined,
    event_type      :: atom(),
    event_data      :: map(),
    timestamp       :: integer(),
    source          :: term()
}).

%%====================================================================
%% Checkpoint Records for Recovery
%%====================================================================

-record(yawl_checkpoint, {
    checkpoint_id    :: binary(),
    workflow_id      :: binary(),
    checkpoint_state :: term(),
    marking          :: map(),
    data             :: map(),
    timestamp        :: integer(),
    sequence_num     :: pos_integer()
}).

%%====================================================================
%% Service Registry Records
%%====================================================================

-record(yawl_service_registry, {
    service_id      :: binary(),
    service_name    :: binary(),
    service_type    :: atom(),
    endpoint        :: binary(),
    health_check_url:: binary() | undefined,
    status          :: active | inactive | degraded,
    last_check      :: integer() | undefined,
    response_time   :: integer() | undefined,
    success_rate    :: float() | undefined,
    metadata        :: map()
}).

%%====================================================================
%% Human Task Queue Records
%%====================================================================

-record(yawl_task_queue, {
    queue_id        :: binary(),
    task_id         :: binary(),
    queue_name      :: binary(),
    assigned_user   :: binary() | undefined,
    assigned_group  :: binary() | undefined,
    claim_expiry    :: integer() | undefined,
    priority        :: low | normal | high | urgent,
    due_date        :: integer() | undefined,
    created_at      :: integer(),
    claimed_at      :: integer() | undefined
}).

%%====================================================================
%% Type Definitions
%%====================================================================
%% Note: workflow_status() and workflow_instance_status() are defined in yawl_types.hrl
%% These are additional types specific to the persistence layer

-type workitem_status() :: pending | allocated | started | completed | failed | cancelled.
-type resource_type() :: human | service | system.
-type resource_status() :: available | busy | unavailable | offline.
-type priority() :: low | normal | high | urgent.
-type service_status() :: active | inactive | degraded.
