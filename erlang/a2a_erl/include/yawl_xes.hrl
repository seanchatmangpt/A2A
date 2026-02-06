%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Logging Definitions
%%%
%%% This header file defines records and types for XES (eXtensible Event Stream)
%%% logging support in YAWL workflows. XES is an IEEE-standard format for
%%% event-based logs used in process mining.
%%%
%%% XES Specification:
%%% - Events represent state changes in a workflow
%%% - Traces contain all events for a single workflow instance
%%% - Logs contain multiple traces (multiple workflow instances)
%%%
%%% @end
%%%-------------------------------------------------------------------

%%====================================================================
%% XES Event Records
%%====================================================================

%% XES Event - Represents a single event in a process execution
-record(xes_event, {
    event_id :: binary(),
    timestamp :: integer(),
    lifecycle :: xes_lifecycle(),
    activity :: binary(),
    transition :: binary() | undefined,
    resource :: binary() | undefined,
    data_attrs :: map(),
    org_attrs :: map(),
    cost_attrs :: map(),
    metadata :: map()
}).

%% XES Trace - Contains all events for a single workflow instance
-record(xes_trace, {
    trace_id :: binary(),
    case_id :: binary(),
    workflow_id :: binary(),
    workflow_name :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    events :: [#xes_event{}],
    attributes :: map(),
    status :: running | completed | failed | cancelled
}).

%% XES Log - Contains multiple traces (multiple workflow instances)
-record(xes_log, {
    log_id :: binary(),
    traces :: [#xes_trace{}],
    extensions :: [binary()],
    classifiers :: map(),
    global_trace_attrs :: map(),
    global_event_attrs :: map(),
    metadata :: map()
}).

%%====================================================================
%% XES Configuration Records
%%====================================================================

%% XES Logger Configuration
-record(xes_config, {
    enabled :: boolean(),
    log_level :: xes_log_level(),
    output_mode :: xes_output_mode(),
    file_path :: binary() | undefined,
    buffer_size :: integer(),
    flush_interval :: integer(),
    include_data_attrs :: boolean(),
    include_org_attrs :: boolean(),
    include_cost_attrs :: boolean(),
    trace_filter :: function()
}).

%% XES Pattern Execution Record
-record(xes_pattern_exec, {
    pattern_id :: binary(),
    pattern_type :: atom(),
    instance_id :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    transitions_executed :: [binary()],
    result :: atom()
}).

%% XES Workitem Lifecycle Record
-record(xes_workitem, {
    workitem_id :: binary(),
    task_name :: binary(),
    status :: atom(),
    assigned_to :: binary() | undefined,
    created_at :: integer(),
    started_at :: integer() | undefined,
    completed_at :: integer() | undefined
}).

%%====================================================================
%% Type Definitions
%%====================================================================

-type xes_lifecycle() :: start | complete | suspend | resume | assign |
                         reassign | withhold_withdraw | withhold_reattack |
                         pi_abort | pi_schedule | pi_unknown |
                         manual_start | manual_complete.

-type xes_log_level() :: trace | debug | info | warn | error | none.
-type xes_output_mode() :: file | console | both | ets | memory.

-type xes_event_type() :: workflow_start | workflow_complete |
                          workflow_fail | workflow_cancel |
                          transition_start | transition_complete |
                          pattern_start | pattern_complete |
                          workitem_create | workitem_assign |
                          workitem_start | workitem_complete |
                          workitem_suspend | workitem_resume |
                          timeout_start | timeout_fire |
                          cancellation_trigger.

-type xes_attribute() :: {binary(), term()}.

%%====================================================================
%% XES Standard Attribute Keys (IEEE XES Standard)
%%====================================================================

%% Concept extensions
-define(XES_CONCEPT_NAME, <<"concept:name">>).
-define(XES_CONCEPT_INSTANCE, <<"concept:instance">>).
-define(XES_CONCEPT_LIFECYCLE, <<"concept:lifecycle">>).

%% Time extensions
-define(XES_TIME_TIMESTAMP, <<"time:timestamp">>).

%% Organizational extensions
-define(XES_ORG_RESOURCE, <<"org:resource">>).
-define(XES_ORG_GROUP, <<"org:group">>).
-define(XES_ORG_ROLE, <<"org:role">>).

%% Cost extensions
-define(XES_COST_TOTAL, <<"cost:total">>).
-define(XES_COST_CURRENCY, <<"cost:currency">>).

%%====================================================================
%% XES Lifecycle Transition Mappings
%%====================================================================

-define(XES_LIFECYCLE_MAP, #{
    start => schedule,
    complete => complete,
    assign => assign,
    reassign => reassign,
    suspend => suspend,
    resume => reassign,
    cancel => pi_abort,
    timeout => pi_schedule
}).

%%====================================================================
%% XES Default Configuration
%%====================================================================

-define(XES_DEFAULT_CONFIG, #xes_config{
    enabled = true,
    log_level = info,
    output_mode = both,
    file_path = <<"logs/yawl_workflow.xes">>,
    buffer_size = 100,
    flush_interval = 5000,
    include_data_attrs = true,
    include_org_attrs = true,
    include_cost_attrs = false,
    trace_filter = fun(_) -> true end
}).

%%====================================================================
%% XES Namespace Definitions
%%====================================================================

-define(XES_NAMESPACE, <<"http://www.xes-standard.org/">>).
-define(XES_EXTENSION_CONCEPT, <<"concept">>).
-define(XES_EXTENSION_TIME, <<"time">>).
-define(XES_EXTENSION_ORGANIZATIONAL, <<"org">>).
-define(XES_EXTENSION_COST, <<"cost">>).
-define(XES_EXTENSION_LIFECYCLE, <<"lifecycle">>).

%%====================================================================
%% Helper Macros
%%====================================================================

%% Check if XES logging is enabled
-define(XES_LOG_ENABLED(),
    case application:get_env(a2a_erl, xes_enabled) of
        {ok, true} -> true;
        _ -> false
    end).

%% Log XES event if enabled
-define(XES_LOG(Event),
    begin
        case ?XES_LOG_ENABLED() of
            true -> yawl_workflow_xes:log_event(Event);
            false -> ok
        end
    end).

%% Log workflow start
-define(XES_LOG_WORKFLOW_START(WorkflowId, CaseId),
    ?XES_LOG(yawl_workflow_xes:create_workflow_start_event(WorkflowId, CaseId))).

%% Log workflow complete
-define(XES_LOG_WORKFLOW_COMPLETE(WorkflowId, CaseId),
    ?XES_LOG(yawl_workflow_xes:create_workflow_complete_event(WorkflowId, CaseId))).

%% Log workflow fail
-define(XES_LOG_WORKFLOW_FAIL(WorkflowId, CaseId),
    ?XES_LOG(yawl_workflow_xes:create_workflow_fail_event(WorkflowId, CaseId))).

%% Log transition
-define(XES_LOG_TRANSITION(WorkflowId, Transition, State),
    ?XES_LOG(yawl_workflow_xes:create_transition_event(WorkflowId, Transition, State))).

%% Log pattern execution
-define(XES_LOG_PATTERN(WorkflowId, PatternType, InstanceId, Status),
    ?XES_LOG(yawl_workflow_xes:create_pattern_event(WorkflowId, PatternType, InstanceId, Status))).

%%====================================================================
%% van der Aalst 2025-2026: XES Extensions for Research Integration
%%====================================================================

%% Object-Centric Event Log (OCEL) Extension - Paper 2508.00116
-define(OCEL_EXTENSION, <<"ocel">>).
-define(OCEL_PREFIX, <<"ocel:">>).
-define(OCEL_NAMESPACE, <<"http://www.xes-standard.org/ocel.xesext">>).
-define(OCEL_OBJECT_TYPE, <<"ocel:object-type">>).
-define(OCEL_OBJECT_ID, <<"ocel:object-id">>).
-define(OCEL_LIFECYCLE_TRANSITION, <<"ocel:lifecycle-transition">>).

%% Partial Order Extension - Paper 2509.15346
-define(PO_EXTENSION, <<"po">>).
-define(PO_PREFIX, <<"po:">>).
-define(PO_NAMESPACE, <<"http://www.yawl.org/partial-order.xesext">>).
-define(PO_CONCURRENT_WITH, <<"po:concurrent-with">>).
-define(PO_ORDER_AFTER, <<"po:order-after">>).

%% LLM Validation Extension - Paper 2509.15336
-define(LLM_EXTENSION, <<"llm">>).
-define(LLM_PREFIX, <<"llm:">>).
-define(LLM_NAMESPACE, <<"http://www.yawl.org/llm.xesext">>).
-define(LLM_GENERATED_BY, <<"llm:generated-by">>).
-define(LLM_CONFIDENCE, <<"llm:confidence">>).
-define(LLM_HALLUCINATION, <<"llm:hallucination">>).

%% Reachability Diagnostics Extension - Paper 2602.02447
-define(REACH_EXTENSION, <<"reach">>).
-define(REACH_PREFIX, <<"reach:">>).
-define(REACH_NAMESPACE, <<"http://www.yawl.org/reachability.xesext">>).
-define(REACH_IS_REACHABLE, <<"reach:is-reachable">>).
-define(REACH_ADMISSIBLE, <<"reach:admissible">>).
-define(REACH_COMPLEXITY, <<"reach:complexity">>).

%% Colored Petri Net Extension - Paper 2506.12238
-define(CPN_EXTENSION, <<"cpn">>).
-define(CPN_PREFIX, <<"cpn:">>).
-define(CPN_NAMESPACE, <<"http://www.yawl.org/cpn.xesext">>).
-define(CPN_COLOR_SET, <<"cpn:color-set">>).
-define(CPN_TOKEN_DATA, <<"cpn:token-data">>).
-define(CPN_GUARD, <<"cpn:guard">>).

%% Helper macros for extended XES attributes
-define(XES_OCEL_ATTR(Key, Value), {OCEL_PREFIX, Key, Value}).
-define(XES_PO_ATTR(Key, Value), {PO_PREFIX, Key, Value}).
-define(XES_LLM_ATTR(Key, Value), {LLM_PREFIX, Key, Value}).
-define(XES_REACH_ATTR(Key, Value), {REACH_PREFIX, Key, Value}).
-define(XES_CPN_ATTR(Key, Value), {CPN_PREFIX, Key, Value}).
