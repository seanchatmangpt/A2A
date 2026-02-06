%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Type Definitions
%%%
%%% This header file defines all the records and types used throughout
%%% the YAWL workflow pattern implementation.
%%%
%%% @end
%%%-------------------------------------------------------------------

%%====================================================================
%% YAWL Pattern Records
%%====================================================================

-record(yawl_pattern, {
    type :: atom(),
    name :: string(),
    description :: string(),
    complexity :: low | medium | high,
    places :: [atom()],
    transitions :: [atom()],
    preset :: #{atom() => [atom()]},
    postset :: #{atom() => [atom()]},
    metadata :: map()
}).

%%====================================================================
%% YAWL Workflow Configuration Records
%%====================================================================

-record(yawl_workflow_config, {
    pattern_type :: atom(),
    parameters :: map(),
    resource_allocations :: map(),
    data_mappings :: map(),
    cancelation_rules :: map(),
    timeout :: integer() | undefined,
    retry_policy :: map() | undefined
}).

%%====================================================================
%% YAWL Workflow State Records
%%====================================================================

-record(yawl_workflow, {
    workflow_id :: binary(),
    pattern_type :: atom(),
    status :: pending | running | completed | failed | cancelled,
    config :: #yawl_workflow_config{},
    marking :: map(),
    current_place :: atom() | undefined,
    start_time :: integer(),
    end_time :: integer() | undefined,
    result :: map() | undefined,
    error :: term() | undefined,
    metadata :: map()
}).

%%====================================================================
%% YAWL Test Result Records
%%====================================================================

-record(yawl_test_result, {
    test_id :: binary(),
    pattern_type :: atom() | [atom()],
    status :: passed | failed | skipped | timeout,
    execution_time :: integer(),
    result :: map(),
    error_reason :: term() | undefined,
    validation_result :: map(),
    performance_metrics :: map(),
    timestamp :: integer()
}).

%%====================================================================
%% YAWL Scenario Records
%%====================================================================

-record(yawl_scenario, {
    scenario_id :: binary(),
    name :: string(),
    description :: string(),
    business_domain :: business_domain(),
    complexity :: complexity(),
    pattern_combination :: [{atom(), map()}],
    resource_allocations :: map(),
    data_flows :: map(),
    business_rules :: [tuple()],
    success_criteria :: map(),
    error_scenarios :: [tuple()],
    metadata :: map()
}).

%%====================================================================
%% YAWL Orchestrator State Records
%%====================================================================

-record(yawl_orchestrator_state, {
    workflows :: map(),
    pattern_cache :: map(),
    active_tests :: map(),
    config :: map(),
    statistics :: map()
}).

%%====================================================================
%% Type Definitions
%%====================================================================

-type complexity() :: low | medium | high.
-type business_domain() :: order_processing | document_workflow | data_pipeline |
                           approval_chain | notification_system | financial_workflow |
                           supply_chain | customer_service | hr_workflow | security_audit.
-type pattern_type() :: basic_sequential | parallel_split | parallel_join |
                       exclusive_choice | simple_merge | iterative_loop |
                       multi_instance | interleaved_parallelism |
                       implicit_merge | multiple_merge | deferred_choice |
                       interleaved_routing | milestone | cancelation_block |
                       cancelation_scope | cancelation_thread |
                       cancelation_subprocess | cancelation_multiple_instances |
                       cancelation_multiple_instances_scope |
                       cancelation_multiple_instances_thread |
                       cancelation_multiple_instances_subprocess |
                       cancelation_point | cancelation_end | cancelation_cancel |
                       cancelation_thread_after | cancelation_subprocess_after |
                       cancelation_multiple_instances_after |
                       cancelation_multiple_instances_thread_after |
                       cancelation_multiple_instances_subprocess_after |
                       cancelation_thread_or | cancelation_subprocess_or |
                       cancelation_multiple_instances_or |
                       cancelation_multiple_instances_thread_or |
                       cancelation_multiple_instances_subprocess_or |
                       cancelation_thread_and | cancelation_subprocess_and |
                       cancelation_multiple_instances_and |
                       cancelation_multiple_instances_thread_and |
                       cancelation_multiple_instances_subprocess_and.

-type workflow_status() :: pending | running | completed | failed | cancelled.
%% Extended workflow status for workflow instance state machine
-type workflow_instance_status() :: idle | running | waiting | completing | terminated | cancelled | failed.
-type test_status() :: passed | failed | skipped | timeout.
-type validation_result() :: #{valid := boolean(), errors := [term()], warnings := [term()]}.

%%====================================================================
%% Constants
%%====================================================================

-define(YAWL_PATTERNS, [
    basic_sequential,
    parallel_split,
    parallel_join,
    exclusive_choice,
    simple_merge,
    iterative_loop,
    multi_instance,
    cancelation,
    interleaved_parallelism,
    implicit_merge,
    multiple_merge,
    deferred_choice,
    interleaved_routing,
    milestone,
    cancelation_block,
    cancelation_scope,
    cancelation_thread,
    cancelation_subprocess,
    cancelation_multiple_instances,
    cancelation_multiple_instances_scope,
    cancelation_multiple_instances_thread,
    cancelation_multiple_instances_subprocess,
    cancelation_point,
    cancelation_end,
    cancelation_cancel,
    cancelation_thread_after,
    cancelation_subprocess_after,
    cancelation_multiple_instances_after,
    cancelation_multiple_instances_thread_after,
    cancelation_multiple_instances_subprocess_after,
    cancelation_thread_or,
    cancelation_subprocess_or,
    cancelation_multiple_instances_or,
    cancelation_multiple_instances_thread_or,
    cancelation_multiple_instances_subprocess_or,
    cancelation_thread_and,
    cancelation_subprocess_and,
    cancelation_multiple_instances_and,
    cancelation_multiple_instances_thread_and,
    cancelation_multiple_instances_subprocess_and
]).

-define(BUSINESS_DOMAINS, [
    order_processing,
    document_workflow,
    data_pipeline,
    approval_chain,
    notification_system,
    financial_workflow,
    supply_chain,
    customer_service,
    hr_workflow,
    security_audit
]).

-define(DEFAULT_TIMEOUT, 30000).
-define(MAX_RETRY_ATTEMPTS, 3).
-define(DEFAULT_RETRY_DELAY, 1000).

%%====================================================================
%% van der Aalst 2025-2026 Research Integration Type Definitions
%%====================================================================

%% Colored Petri Net (CPN) Types - Paper 2506.12238
-type cpn_color_set() :: boolean | integer | float | string | list | record | product.
-type cpn_token() :: #{data := term(), color_set := cpn_color_set(), timestamp => integer(), attributes => map()}.
-type cpn_marking() :: #{atom() => [cpn_token()]}.
-type cpn_guard() :: #{expression := binary(), variables := [atom()], predicate := function()}.

%% Object-Centric Process Mining (OCPM) Types - Paper 2508.00116
-type ocpm_object_id() :: binary().
-type ocpm_object_type() :: binary().
-type ocpm_event() :: #{
    event_id := binary(),
    timestamp := integer(),
    activity := binary(),
    objects := #{ocpm_object_type() => [ocpm_object_id()]},
    attributes := map()
}.
-type ocpm_log() :: #{
    log_id := binary(),
    events := [ocpm_event()],
    object_types := [ocpm_object_type()],
    metadata := map()
}.

%% Partial Order Types - Paper 2509.15346
-type partial_order() :: #{
    events := [map()],
    order := #{binary() => [binary()]},
    concurrent := sets:set({binary(), binary()}),
    trace_id := binary()
}.
-type abstraction_level() :: 0..10.

%% Reachability Diagnostics Types - Paper 2602.02447
-type reachability_diagnostics() :: #{
    is_reachable := boolean(),
    complexity := atom(),
    is_admissible := boolean(),
    maximum_admissible => cpn_marking(),
    diverging_transitions => [atom()],
    concurrent_pairs => [{atom(), atom()}],
    structural_conflicts => map()
}.

%% LLM Validation Types - Paper 2509.15336
-type llm_model() :: #{
    model_type := binary(),
    activities := [binary()],
    transitions := [map()],
    metadata => map()
}.
-type llm_validation_result() :: #{
    is_valid := boolean(),
    fidelity_score := float(),
    contradictions := [map()],
    warnings := [map()],
    confidence := float()
}.
-type hallucination_type() :: knowledge_driven | confidence_mismatch | structural_invalid | semantic_drift.
