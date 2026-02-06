%%% @doc A2A Erlang Top-Level Supervisor
%%%
%%% This supervisor manages the core A2A services and YAWL workflow engine:
%%% - a2a_task_store: ETS-backed task storage
%%% - a2a_agent_card: Agent card management
%%% - a2a_task_sup: Dynamic supervisor for task state machines
%%% - YAWL services: orchestrator, persistence, resource manager, etc.
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
    %% Supervisor flags
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 10,
        period => 60
    },

    %% Child specifications
    ChildSpecs = [
        %% YAWL Persistence Manager - CRITICAL: Must start first
        #{
            id => yawl_persistence,
            start => {yawl_persistence, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_persistence]
        },

        %% Task Store - ETS-backed task storage
        #{
            id => a2a_task_store,
            start => {a2a_task_store, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_task_store]
        },

        %% Agent Card Manager
        #{
            id => a2a_agent_card,
            start => {a2a_agent_card, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [a2a_agent_card]
        },

        %% YAWL Service Registry
        #{
            id => yawl_service_registry,
            start => {yawl_service_registry, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_service_registry]
        },

        %% YAWL Resource Manager
        #{
            id => yawl_resource_manager,
            start => {yawl_resource_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_resource_manager]
        },

        %% YAWL Human Task Service
        #{
            id => yawl_human_task,
            start => {yawl_human_task, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_human_task]
        },

        %% YAWL Work Item Processor
        #{
            id => yawl_workitem_processor,
            start => {yawl_workitem_processor, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_workitem_processor]
        },

        %% YAWL Orchestrator - depends on persistence
        #{
            id => yawl_orchestrator,
            start => {yawl_orchestrator, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_orchestrator]
        },

        %% YAWL-A2A Bridge - depends on orchestrator and task store
        #{
            id => yawl_a2a_bridge,
            start => {yawl_a2a_bridge, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_bridge]
        },

        %% YAWL-A2A Event Notification System - depends on bridge
        #{
            id => yawl_a2a_events,
            start => {yawl_a2a_events, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_events]
        },

        %% YAWL-A2A Resource Integration - depends on resource manager
        #{
            id => yawl_a2a_resource_integration,
            start => {yawl_a2a_resource_integration, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_a2a_resource_integration]
        },

        %% YAWL Error Recovery Manager
        #{
            id => yawl_error_recovery,
            start => {yawl_error_recovery, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_error_recovery]
        },

        %% YAWL Metrics Collector
        #{
            id => yawl_metrics,
            start => {yawl_metrics, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [yawl_metrics]
        },

        %% YAWL Workflow Instance Supervisor - depends on orchestrator and persistence
        #{
            id => yawl_workflow_instance_sup,
            start => {yawl_workflow_instance_sup, start_link, []},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [yawl_workflow_instance_sup]
        },

        %% Task State Machine Supervisor
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
