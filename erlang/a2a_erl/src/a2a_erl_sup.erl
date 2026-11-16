%%% @doc A2A Erlang Top-Level Supervisor
%%%
%%% This supervisor manages the core A2A services and YAWL workflow engine:
%%% - a2a_task_store: ETS-backed task storage
%%% - a2a_agent_card: Agent card management
%%% - a2a_task_sup: Dynamic supervisor for task state machines
%%% - YAWL services: orchestrator, persistence, resource manager, etc.
%%% - HotCI services: disaster recovery, rollback manager, monitoring, security,
%%%                   failure injection, Docker-based peer testing
-module(a2a_erl_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%% ============================================================================
%%% Supervisor Callbacks
%%% ============================================================================

init([]) ->
    %% Supervisor flags - one_for_one strategy
    %% If a child process terminates, only that process is restarted.
    %% This is appropriate for the YAWL supervision tree where components
    %% are largely independent and can recover independently.
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },

    %% Child specifications
    %% Order matters for dependencies: persistence must start before other services
    ChildSpecs = [
        %% ========================================
        %% Core Infrastructure Services
        %% ========================================

        %% YAWL Persistence Manager - CRITICAL: Must start first
        %% Manages Mnesia tables and provides persistence for all YAWL data
        #{
            id => yawl_persistence,
            start => {yawl_persistence, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_persistence]
        },

        %% Task Store - ETS-backed task storage for A2A tasks
        #{
            id => a2a_task_store,
            start => {a2a_task_store, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_task_store]
        },

        %% ========================================
        %% YAWL Core Services
        %% ========================================

        %% YAWL Event Manager - Observer pattern for workflow events
        #{
            id => yawl_events,
            start => {yawl_events, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_events]
        },

        %% YAWL Service Registry - Manages available workflow services
        #{
            id => yawl_service_registry,
            start => {yawl_service_registry, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_service_registry]
        },

        %% YAWL Resource Manager - Handles resource allocation for workflows
        #{
            id => yawl_resource_manager,
            start => {yawl_resource_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_resource_manager]
        },

        %% YAWL Orchestrator - Central workflow lifecycle management
        %% Coordinates workflow execution and delegates to instances
        #{
            id => yawl_orchestrator,
            start => {yawl_orchestrator, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_orchestrator]
        },

        %% YAWL Metrics Collector - Collects and reports workflow metrics
        #{
            id => yawl_metrics,
            start => {yawl_metrics, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_metrics]
        },

        %% YAWL Error Recovery Manager - Handles error recovery strategies
        #{
            id => yawl_error_recovery,
            start => {yawl_error_recovery, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_error_recovery]
        },

        %% ========================================
        %% YAWL Supporting Services
        %% ========================================

        %% YAWL Human Task Service - Manages human-in-the-loop tasks
        #{
            id => yawl_human_task,
            start => {yawl_human_task, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_human_task]
        },

        %% YAWL Work Item Processor - Processes work items
        #{
            id => yawl_workitem_processor,
            start => {yawl_workitem_processor, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_workitem_processor]
        },

        %% ========================================
        %% A2A Integration Services
        %% ========================================

        %% Agent Card Manager - Manages agent card discovery
        #{
            id => a2a_agent_card,
            start => {a2a_agent_card, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_agent_card]
        },

        %% YAWL-A2A Bridge - Integration between YAWL and A2A protocols
        #{
            id => yawl_a2a_bridge,
            start => {yawl_a2a_bridge, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_bridge]
        },

        %% YAWL-A2A Event Notification System
        #{
            id => yawl_a2a_events,
            start => {yawl_a2a_events, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_events]
        },

        %% YAWL-A2A Resource Integration
        #{
            id => yawl_a2a_resource_integration,
            start => {yawl_a2a_resource_integration, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_resource_integration]
        },

        %% Y Combinator Demo Logger - For demo logging and telemetry
        #{
            id => y_combinator_logger,
            start => {y_combinator_logger, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [y_combinator_logger]
        },

        %% ========================================
        %% HotCI Testing and Disaster Recovery
        %% ========================================

        %% HotCI Failure Injector - Simulates failure scenarios for testing
        #{
            id => hotci_failure_injector,
            start => {hotci_failure_injector, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [hotci_failure_injector]
        },

        %% HotCI Disaster Recovery - Manages disaster recovery procedures
        #{
            id => a2a_disaster_recovery,
            start => {a2a_disaster_recovery, start_link, []},
            restart => permanent,
            shutdown => 10000,
            type => worker,
            modules => [a2a_disaster_recovery]
        },

        %% HotCI Rollback Manager - Manages rollback based on health and criticality
        #{
            id => a2a_rollback_manager,
            start => {a2a_rollback_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_rollback_manager]
        },

        %% HotCI Monitoring - Monitors CPU, memory, response time, and error rate
        #{
            id => a2a_monitoring,
            start => {a2a_monitoring, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_monitoring]
        },

        %% HotCI Security - Multi-algorithm signature verification for upgrades
        #{
            id => a2a_hotci_security,
            start => {a2a_hotci_security, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_hotci_security]
        },

        %% HotCI Docker Peer Manager - Docker-based peer testing for real-environment tests
        #{
            id => a2a_hotci_docker_peer,
            start => {a2a_hotci_docker_peer, start_link, []},
            restart => permanent,
            shutdown => 15000,
            type => worker,
            modules => [a2a_hotci_docker_peer]
        },

        %% ========================================
        %% Dynamic Supervisors (simple_one_for_one)
        %% ========================================

        %% YAWL Workflow Instance Supervisor
        %% Dynamic supervisor for workflow instances (simple_one_for_one)
        %% Each workflow instance is a dynamically supervised child
        #{
            id => yawl_workflow_instance_sup,
            start => {yawl_workflow_instance_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [yawl_workflow_instance_sup]
        },

        %% Task State Machine Supervisor
        %% Dynamic supervisor for A2A task state machines
        #{
            id => a2a_task_sup,
            start => {a2a_task_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [a2a_task_sup]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
