%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Scenario Generator
%%%
%%% This module generates realistic business scenarios for testing YAWL
%%% workflow patterns. It creates comprehensive test cases based on
%%% various business domains and complexity levels.
%%%
%%% Features:
%%% - Business domain scenario generation
%%% - Edge case scenario generation
%%% - Performance benchmark scenarios
%%% - Error condition scenarios
%%% - Custom scenario creation
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_scenario_generator).
-author("A2A Team").

%% API exports
-export([
    generate_scenario/3,
    generate_business_scenario/2,
    generate_edge_case_scenario/2,
    generate_performance_scenario/2,
    generate_error_scenario/2,
    generate_custom_scenario/3,
    list_available_domains/0,
    get_scenario_complexity/1,
    validate_scenario/1
]).

%% Internal exports
-export([
    generate_order_processing/2,
    generate_document_workflow/2,
    generate_data_pipeline/2,
    generate_approval_chain/2,
    generate_notification_system/2,
    generate_financial_workflow/2,
    generate_supply_chain/2,
    generate_customer_service/2,
    generate_hr_workflow/2,
    generate_security_audit/2
]).

%% Type definitions
-type complexity() :: low | medium | high.
-type business_domain() :: order_processing | document_workflow | data_pipeline |
                         approval_chain | notification_system | financial_workflow |
                         supply_chain | customer_service | hr_workflow | security_audit.

-type scenario() :: #{
    scenario_id := binary(),
    name := string(),
    description := string(),
    business_domain := business_domain(),
    complexity := complexity(),
    pattern_combination := list(),
    resource_allocations := map(),
    data_flows := map(),
    business_rules := list(),
    success_criteria := map(),
    error_scenarios := list(),
    metadata := map()
}.

%%====================================================================
%% API Functions
%%====================================================================

generate_scenario(BusinessDomain, Complexity, Config) ->
    %% Generate a scenario for the specified business domain and complexity
    Scenario = case BusinessDomain of
        order_processing ->
            generate_order_processing(Complexity, Config);
        document_workflow ->
            generate_document_workflow(Complexity, Config);
        data_pipeline ->
            generate_data_pipeline(Complexity, Config);
        approval_chain ->
            generate_approval_chain(Complexity, Config);
        notification_system ->
            generate_notification_system(Complexity, Config);
        financial_workflow ->
            generate_financial_workflow(Complexity, Config);
        supply_chain ->
            generate_supply_chain(Complexity, Config);
        customer_service ->
            generate_customer_service(Complexity, Config);
        hr_workflow ->
            generate_hr_workflow(Complexity, Config);
        security_audit ->
            generate_security_audit(Complexity, Config)
    end,

    %% Validate the generated scenario
    case validate_scenario(Scenario) of
        true -> Scenario;
        false -> throw(invalid_scenario)
    end.

generate_business_scenario(BusinessDomain, Config) ->
    %% Generate business scenario with appropriate complexity
    Complexity = determine_scenario_complexity(BusinessDomain, Config),
    generate_scenario(BusinessDomain, Complexity, Config).

generate_edge_case_scenario(BusinessDomain, Config) ->
    %% Generate edge case scenario
    Scenario = generate_scenario(BusinessDomain, high, Config),
    Scenario#{
        type => edge_case,
        characteristics => #{
            extreme_conditions => true,
            boundary_testing => true,
            error_injection => true,
            performance_stress => true
        }
    }.

generate_performance_scenario(BusinessDomain, Config) ->
    %% Generate performance benchmark scenario
    Scenario = generate_scenario(BusinessDomain, high, Config),
    Scenario#{
        type => performance,
        load_profile => generate_load_profile(),
        performance_metrics => #{
            target_throughput => 1000,
            target_latency => 100,
            target_cpu_utilization => 0.7,
            target_memory_utilization => 0.8
        }
    }.

generate_error_scenario(BusinessDomain, Config) ->
    %% Generate error condition scenario
    Scenario = generate_scenario(BusinessDomain, medium, Config),
    Scenario#{
        type => error,
        failure_injection => generate_failure_injections(),
        recovery_strategies => generate_recovery_strategies(),
        validation_criteria => #{
            error_detection => 1.0,
            recovery_success => 0.9,
            system_stability => true
        }
    }.

generate_custom_scenario(BusinessDomain, Complexity, CustomConfig) ->
    %% Generate custom scenario with user-defined configuration
    BaseScenario = generate_scenario(BusinessDomain, Complexity, CustomConfig),
    MergeScenario = merge_custom_config(BaseScenario, CustomConfig),
    case validate_scenario(MergeScenario) of
        true -> MergeScenario;
        false -> throw(invalid_custom_scenario)
    end.

list_available_domains() ->
    %% List all available business domains
    [
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
    ].

get_scenario_complexity(Scenario) ->
    %% Get complexity level of a scenario
    maps:get(complexity, Scenario).

validate_scenario(Scenario) ->
    %% Validate scenario structure and content
    RequiredFields = [
        scenario_id, name, description, business_domain,
        complexity, pattern_combination, resource_allocations,
        data_flows, business_rules, success_criteria
    ],

    lists:all(fun(Field) -> maps:is_key(Field, Scenario) end, RequiredFields).

%%====================================================================
%% Business Domain Scenario Generators
%%====================================================================

%% E-commerce Order Processing Scenarios
generate_order_processing(Complexity, Config) ->
    #{
        scenario_id => <<"order_processing_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "E-commerce Order Processing",
        description => "Complete e-commerce order processing from validation to fulfillment",
        business_domain => order_processing,
        complexity => Complexity,
        pattern_combination => generate_order_patterns(Complexity),
        resource_allocations => generate_order_resources(Complexity),
        data_flows => generate_order_data_flows(Complexity),
        business_rules => generate_order_business_rules(Complexity),
        success_criteria => generate_order_success_criteria(Complexity),
        error_scenarios => generate_order_error_scenarios(Complexity),
        metadata => #{
            industry => "e-commerce",
            transaction_volume => "high",
            seasonality => true,
            peak_load_factor => 3.0
        }
    }.

generate_order_patterns(Complexity) ->
    case Complexity of
        low ->
            [
                {basic_sequential, #{task => "validate_order"}},
                {exclusive_choice, #{conditions => [is_valid, needs_approval]}},
                {parallel_split, #{branches => 2, tasks => ["process_payment", "check_inventory"]}},
                {parallel_join, #{branches => 2}},
                {basic_sequential, #{task => "ship_order"}}
            ];
        medium ->
            [
                {basic_sequential, #{task => "validate_order"}},
                {exclusive_choice, #{conditions => [is_valid, needs_approval, requires_review]}},
                {parallel_split, #{branches => 3, tasks => ["process_payment", "check_inventory", "calculate_shipping"]}},
                {parallel_join, #{branches => 3}},
                {exclusive_choice, #{conditions => [can_ship, backorder, cancel_order]}},
                {multi_instance, #{num_instances => 3, data => order_items}},
                {basic_sequential, #{task => "ship_order"}},
                {iterative_loop, #{condition => has_items_to_backorder}}
            ];
        high ->
            [
                {basic_sequential, #{task => "validate_order"}},
                {exclusive_choice, #{conditions => [is_valid, needs_approval, requires_review, is_international]}},
                {parallel_split, #{branches => 4, tasks => ["process_payment", "check_inventory", "calculate_shipping", "fraud_check"]}},
                {interleaved_parallelism, #{tasks => ["price_validation", "coupon_check"]}},
                {parallel_join, #{branches => 4}},
                {exclusive_choice, #{conditions => [can_ship, backorder, cancel_order, hold_for_review]}},
                {multi_instance, #{num_instances => 5, data => order_items}},
                {basic_sequential, #{task => "ship_order"}},
                {iterative_loop, #{condition => has_items_to_backorder, max_iterations => 10}},
                {cancelation_block, #{scope => "fulfillment_process"}},
                {nested_patterns, #{patterns => [tracking_updates, customer_communication]}}
            ]
    end.

generate_order_resources(Complexity) ->
    BaseResources = #{
        "validate_order" => ["order_validation_service", "customer_database"],
        "process_payment" => ["payment_gateway", "fraud_detection"],
        "check_inventory" => ["inventory_service", "cache_system"],
        "calculate_shipping" => ["shipping_service", "address_validation"],
        "fraud_check" => ["fraud_detection", "behavioral_analytics"],
        "ship_order" => ["fulfillment_service", "tracking_system"]
    },

    case Complexity of
        low -> BaseResources;
        medium -> BaseResources#{"price_validation" => ["pricing_service"], "coupon_check" => ["promotion_service"]};
        high -> BaseResources#{"price_validation" => ["pricing_service"], "coupon_check" => ["promotion_service"],
                              "tracking_updates" => ["tracking_service"], "customer_communication" => ["notification_service"]}
    end.

generate_order_data_flows(Complexity) ->
    BaseFlows = #{
        "order_data" => ["validate_order", "process_payment", "check_inventory"],
        "customer_data" => ["validate_order", "calculate_shipping"],
        "payment_data" => ["process_payment", "fraud_check"],
        "inventory_data" => ["check_inventory", "ship_order"],
        "shipping_data" => ["calculate_shipping", "ship_order"]
    },

    case Complexity of
        low -> BaseFlows;
        medium -> BaseFlows#{"promotion_data" => ["coupon_check", "process_payment"]};
        high -> BaseFlows#{"promotion_data" => ["coupon_check", "process_payment"],
                          "tracking_data" => ["ship_order", "tracking_updates"],
                          "customer_data" => ["validate_order", "calculate_shipping", "customer_communication"]}
    end.

generate_order_business_rules(Complexity) ->
    BaseRules = #[
        {rule_id, auto_approve, condition => order_amount < 50 and customer_status == "verified", action => approve},
        {rule_id, manual_review, condition => order_amount > 1000, action => require_review},
        {rule_id, free_shipping, condition => order_amount > 100, action => apply_free_shipping}
    ],

    case Complexity of
        low -> BaseRules;
        medium -> BaseRules ++ [
            {rule_id, international_shipping, condition => is_international, action => apply_international_rules},
            {rule_id, priority_handling, condition => order_type == "express", action => expedite_processing}
        ];
        high -> BaseRules ++ [
            {rule_id, international_shipping, condition => is_international, action => apply_international_rules},
            {rule_id, priority_handling, condition => order_type == "express", action => expedite_processing},
            {rule_id, fraud_high_risk, condition => fraud_score > 0.8, action => require_manual_review},
            {rule_id, volume_discount, condition => order_items > 10, action => apply_volume_discount}
        ]
    end.

generate_order_success_criteria(Complexity) ->
    BaseCriteria = #{
        max_duration => 30000,
        min_success_rate => 0.95,
        target_conversion_rate => 0.85
    },

    case Complexity of
        low -> BaseCriteria;
        medium -> BaseCriteria#{max_duration => 45000, target_conversion_rate => 0.90};
        high -> BaseCriteria#{max_duration => 60000, target_conversion_rate => 0.92,
                           fraud_detection_rate => 0.98, inventory_accuracy => 0.99}
    end.

generate_order_error_scenarios(Complexity) ->
    BaseScenarios = [
        {payment_failed, handle_retry, "Retry payment with alternative method"},
        {inventory_unavailable, backorder, "Create backorder and notify customer"},
        {shipping_address_invalid, request_update, "Request correct address from customer"}
    ],

    case Complexity of
        low -> BaseScenarios;
        medium -> BaseScenarios ++ [
            {fraud_detected, manual_review, "Escalate to fraud investigation team"},
            {price_changed, notify_customer, "Notify customer of price adjustment"}
        ];
        high -> BaseScenarios ++ [
            {fraud_detected, manual_review, "Escalate to fraud investigation team"},
            {price_changed, notify_customer, "Notify customer of price adjustment"},
            {inventory_corrupted, restore_from_backup, "Restore inventory from backup"},
            {system_overload, implement_throttling, "Throttle requests and prioritize"},
            {multi_item_backorder, partial_fulfillment, "Ship available items, backorder rest"}
        ]
    end.

%% Document Workflow Scenarios
generate_document_workflow(Complexity, Config) ->
    #{
        scenario_id => <<"document_workflow_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Document Approval Workflow",
        description => "Multi-stage document approval process with review and routing",
        business_domain => document_workflow,
        complexity => Complexity,
        pattern_combination => generate_document_patterns(Complexity),
        resource_allocations => generate_document_resources(Complexity),
        data_flows => generate_document_data_flows(Complexity),
        business_rules => generate_document_business_rules(Complexity),
        success_criteria => generate_document_success_criteria(Complexity),
        error_scenarios => generate_document_error_scenarios(Complexity),
        metadata => #{
            industry => "finance",
            document_types => ["contract", "agreement", "policy"],
            approval_required => true,
            retention_period => 7
        }
    }.

generate_document_patterns(Complexity) ->
    case Complexity of
        low ->
            [
                {basic_sequential, #{task => "submit_document"}},
                {exclusive_choice, #{conditions => [standard, review_needed]}},
                {basic_sequential, #{task => "approve_document"}},
                {basic_sequential, #{task => "archive_document"}}
            ];
        medium ->
            [
                {basic_sequential, #{task => "submit_document"}},
                {exclusive_choice, #{conditions => [standard, legal, confidential]}},
                {parallel_split, #{branches => 3, tasks => ["legal_review", "technical_review", "compliance_review"]}},
                {synchronizing_merge, #{branches => 3}},
                {exclusive_choice, #{conditions => [approve, request_changes, reject]}},
                {iterative_loop, #{condition => requested_changes, max_iterations => 3}},
                {basic_sequential, #{task => "archive_document"}}
            ];
        high ->
            [
                {basic_sequential, #{task => "submit_document"}},
                {exclusive_choice, #{conditions => [standard, legal, confidential, executive]}},
                {parallel_split, #{branches => 4, tasks => ["legal_review", "technical_review", "compliance_review", "executive_review"]}},
                {interleaved_parallelism, #{tasks => ["content_check", "format_validation"]}},
                {synchronizing_merge, #{branches => 4}},
                {exclusive_choice, #{conditions => [approve, request_changes, reject, escalate]}},
                {iterative_loop, #{condition => requested_changes, max_iterations => 5}},
                {multi_instance, #{num_instances => 3, data => stakeholder_reviews}},
                {basic_sequential, #{task => "archive_document"}},
                {cancelation_block, #{scope => "approval_process"}},
                {nested_patterns, #{patterns => ["notification_system", "audit_tracking"]}}
            ]
    end.

generate_document_resources(Complexity) ->
    BaseResources = #{
        "submit_document" => ["document_system", "user_interface"],
        "legal_review" => ["legal_experts", "compliance_tools"],
        "technical_review" => ["technical_specialists", "standards_checkers"],
        "compliance_review" => ["compliance_officers", "audit_tools"],
        "approve" => ["authority_system", "digital_signature"],
        "archive" => ["document_repository", "backup_system"]
    },

    case Complexity of
        low -> BaseResources;
        medium -> BaseResources#{"content_check" => ["content_analyzer"], "format_validation" => ["format_checker"]};
        high -> BaseResources#{"content_check" => ["content_analyzer"], "format_validation" => ["format_checker"],
                              "notification_system" => ["notification_service"], "audit_tracking" => ["audit_logger"]}
    end.

generate_document_data_flows(Complexity) ->
    BaseFlows = #{
        "document_content" => ["submit_document", "legal_review", "technical_review"],
        "review_feedback" => ["legal_review", "technical_review", "compliance_review"],
        "approval_status" => ["approve", "request_changes", "reject"]
    },

    case Complexity of
        low -> BaseFlows;
        medium -> BaseFlows#{"compliance_data" => ["compliance_review", "archive"]};
        high -> BaseFlows#{"compliance_data" => ["compliance_review", "archive"],
                          "audit_data" => ["audit_tracking", "archive"],
                          "notifications" => ["notification_system", "stakeholders"]}
    end.

generate_document_business_rules(Complexity) ->
    BaseRules = #[
        {rule_id, auto_approve, condition => document_type == "standard" and risk_level == "low", action => approve},
        {rule_id, mandatory_review, condition => document_type == "contract" or document_type == "legal", action => require_all_reviews},
        {rule_id, urgent_handling, condition => priority == "urgent", action => expedite_processing}
    ],

    case Complexity of
        low -> BaseRules;
        medium -> BaseRules ++ [
            {rule_id, confidentiality_check, condition => document_type == "confidential", action => restrict_access},
            {rule_id, executive_override, condition => risk_score > 0.8, action => require_executive_approval}
        ];
        high -> BaseRules ++ [
            {rule_id, confidentiality_check, condition => document_type == "confidential", action => restrict_access},
            {rule_id, executive_override, condition => risk_score > 0.8, action => require_executive_approval},
            {rule_id, international_approval, condition => has_international_implications, action => require_global_approval},
            {rule_id, retention_policy, condition => document_age > 7, action => archive}
        ]
    end.

generate_document_success_criteria(Complexity) ->
    BaseCriteria = #{
        max_duration => 30000,
        min_success_rate => 0.90,
        compliance_score => 0.95
    },

    case Complexity of
        low -> BaseCriteria;
        medium -> BaseCriteria#{max_duration => 45000, approval_accuracy => 0.98};
        high -> BaseCriteria#{max_duration => 60000, approval_accuracy => 0.99,
                           audit_completeness => 1.0, security_compliance => 1.0}
    end.

generate_document_error_scenarios(Complexity) ->
    BaseScenarios = [
        {reviewer_unavailable, assign_backup, "Assign backup reviewer"},
        {document_corrupted, restore_version, "Restore from backup version"},
        {approval_timeout, escalate_manager, "Escalate to senior manager"}
    ],

    case Complexity of
        low -> BaseScenarios;
        medium -> BaseScenarios ++ [
            {conflict_detected, resolve_conflict, "Manual conflict resolution"},
            {signature_error, reprocess_signature, "Request re-signature"}
        ];
        high -> BaseScenarios ++ [
            {conflict_detected, resolve_conflict, "Manual conflict resolution"},
            {signature_error, reprocess_signature, "Request re-signature"},
            {system_failure, manual_intervention, "Switch to manual processing"},
            {breach_detected, security_protocol, "Activate security protocols"},
            {international_conflict, arbitration, "Initiate arbitration process"}
        ]
    end.

%% Data Pipeline Scenarios
generate_data_pipeline(Complexity, Config) ->
    #{
        scenario_id => <<"data_pipeline_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Data Processing Pipeline",
        description => "Large-scale data processing with validation, transformation, and storage",
        business_domain => data_pipeline,
        complexity => Complexity,
        pattern_combination => generate_pipeline_patterns(Complexity),
        resource_allocations => generate_pipeline_resources(Complexity),
        data_flows => generate_pipeline_data_flows(Complexity),
        business_rules => generate_pipeline_business_rules(Complexity),
        success_criteria => generate_pipeline_success_criteria(Complexity),
        error_scenarios => generate_pipeline_error_scenarios(Complexity),
        metadata => #{
            industry => "technology",
            data_volume => "very_high",
            processing_type => "batch_streaming",
            quality_requirements => "strict"
        }
    }.

generate_pipeline_patterns(Complexity) ->
    case Complexity of
        low ->
            [
                {basic_sequential, #{task => "extract_data"}},
                {parallel_split, #{branches => 2, tasks => ["validate_data", "transform_data"]}},
                {simple_merge, #{branches => 2}},
                {basic_sequential, #{task => "store_data"}}
            ];
        medium ->
            [
                {basic_sequential, #{task => "extract_data"}},
                {parallel_split, #{branches => 4, tasks => ["validate_format", "check_completeness", "transform_data", "enrich_data"]}},
                {interleaved_parallelism, #{tasks => ["quality_check", "consistency_check"]}},
                {multiple_merge, #{branches => 3}},
                {multi_instance, #{num_instances => 5, data => data_records}},
                {basic_sequential, #{task => "store_data"}},
                {iterative_loop, #{condition => has_more_data, max_iterations => 10}}
            ];
        high ->
            [
                {basic_sequential, #{task => "extract_data"}},
                {parallel_split, #{branches => 6, tasks => ["validate_format", "check_completeness", "transform_data", "enrich_data", "deduplicate", "aggregate"]}},
                {interleaved_parallelism, #{tasks => ["quality_check", "consistency_check", "anomaly_detection"]}},
                {multiple_merge, #{branches => 4}},
                {multi_instance, #{num_instances => 10, data => data_records}},
                {basic_sequential, #{task => "store_data"}},
                {iterative_loop, #{condition => has_more_data, max_iterations => 20}},
                {cancelation_block, #{scope => "processing_pipeline"}},
                {nested_patterns, #{patterns => ["monitoring_system", "alerting_system"]}}
            ]
    end.

generate_pipeline_resources(Complexity) ->
    BaseResources = #{
        "extract_data" => ["extractors", "source_connectors"],
        "validate_format" => ["format_validators", "schema_checkers"],
        "check_completeness" => ["completeness_checkers", "profilers"],
        "transform_data" => ["transformation_engines", "rule_processors"],
        "enrich_data" => ["enrichment_services", "external_apis"],
        "store_data" => ["storage_systems", "database_clusters"]
    },

    case Complexity of
        low -> BaseResources;
        medium -> BaseResources#{"quality_check" => ["quality_assurance", "anomaly_detectors"],
                               "consistency_check" => ["consistency_validators", "data_validators"]};
        high -> BaseResources#{"quality_check" => ["quality_assurance", "anomaly_detectors"],
                               "consistency_check" => ["consistency_validators", "data_validators"],
                               "deduplicate" => ["deduplication_services"],
                               "aggregate" => ["aggregation_engines"],
                               "monitoring_system" => ["monitoring_service"],
                               "alerting_system" => ["alerting_service"]}
    end.

generate_pipeline_data_flows(Complexity) ->
    BaseFlows = #{
        "raw_data" => ["extract_data", "validate_format", "check_completeness"],
        "validated_data" => ["validate_format", "transform_data", "enrich_data"],
        "processed_data" => ["transform_data", "enrich_data", "store_data"]
    },

    case Complexity of
        low -> BaseFlows;
        medium -> BaseFlows#{"quality_results" => ["quality_check", "store_data"],
                            "consistency_results" => ["consistency_check", "store_data"]};
        high -> BaseFlows#{"quality_results" => ["quality_check", "store_data"],
                          "consistency_results" => ["consistency_check", "store_data"],
                          "deduplication_results" => ["deduplicate", "store_data"],
                          "aggregation_results" => ["aggregate", "store_data"],
                          "monitoring_data" => ["monitoring_system", "alerting_system"]}
    end.

generate_pipeline_business_rules(Complexity) ->
    BaseRules = #[
        {rule_id, skip_small_batches, condition => batch_size < 1000, action => bypass_validation},
        {rule_id, external_enrichment, condition => enrichment_required == true, action => call_external_apis},
        {rule_id, archival_policy, condition => data_type == "historical", action => archive_to_cold_storage}
    ],

    case Complexity of {
        low -> BaseRules;
        medium -> BaseRules ++ [
            {rule_id, real_time_processing, condition => processing_mode == "streaming", action => apply_real_time_rules},
            {rule_id, quality_gating, condition => quality_score < 0.8, action => reject_low_quality}
        ];
        high -> BaseRules ++ [
            {rule_id, real_time_processing, condition => processing_mode == "streaming", action => apply_real_time_rules},
            {rule_id, quality_gating, condition => quality_score < 0.8, action => reject_low_quality},
            {rule_id, adaptive_processing, condition => system_load > 0.8, action => implement_adaptive_processing},
            {rule_id, automated_optimization, condition => continuous_improvement == true, action => optimize_pipeline}
        ]
    end.

generate_pipeline_success_criteria(Complexity) ->
    BaseCriteria = #{
        max_duration => 120000,
        min_success_rate => 0.98,
        throughput => 10000,
        data_quality => 0.99
    },

    case Complexity of
        low -> BaseCriteria;
        medium -> BaseCriteria#{max_duration => 180000, throughput => 50000, data_quality => 0.995};
        high -> BaseCriteria#{max_duration => 300000, throughput => 100000, data_quality => 0.999,
                            system_availability => 0.999, latency => < 1000}
    end.

generate_pipeline_error_scenarios(Complexity) ->
    BaseScenarios = [
        {data_corruption, restore_backup, "Restore from backup"},
        {service_unavailable, retry_fallback, "Retry with fallback service"},
        {memory_exhaustion, implement_chunking, "Implement data chunking"}
    ],

    case Complexity of {
        low -> BaseScenarios;
        medium -> BaseScenarios ++ [
            {schema_mismatch, apply_transformation, "Apply schema transformation"},
            {rate_limit_hit, implement_backoff, "Implement exponential backoff"}
        ];
        high -> BaseScenarios ++ [
            {schema_mismatch, apply_transformation, "Apply schema transformation"},
            {rate_limit_hit, implement_backoff, "Implement exponential backoff"},
            {network_partition, implement_tolerance, "Implement network partition tolerance"},
            {data_drift, adapt_schema, "Adapt to data drift"},
            {performance_degradation, auto_scale, "Auto-scale infrastructure"}
        ]
    end.

%% Additional business domain generators (abbreviated for space)
generate_approval_chain(Complexity, Config) ->
    #{
        scenario_id => <<"approval_chain_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Multi-level Approval Chain",
        description => "Complex approval workflow with multiple levels and dependencies",
        business_domain => approval_chain,
        complexity => Complexity,
        pattern_combination => generate_approval_patterns(Complexity),
        resource_allocations => generate_approval_resources(Complexity),
        data_flows => generate_approval_data_flows(Complexity),
        business_rules => generate_approval_business_rules(Complexity),
        success_criteria => generate_approval_success_criteria(Complexity),
        error_scenarios => generate_approval_error_scenarios(Complexity),
        metadata => #{
            industry => "manufacturing",
            approval_levels => "multi_tier",
            escalation_required => true,
            approval_matrix => "complex"
        }
    }.

generate_notification_system(Complexity, Config) ->
    #{
        scenario_id => <<"notification_system_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Multi-channel Notification System",
        description => "Distributed notification system with multiple channels and routing rules",
        business_domain => notification_system,
        complexity => Complexity,
        pattern_combination => generate_notification_patterns(Complexity),
        resource_allocations => generate_notification_resources(Complexity),
        data_flows => generate_notification_data_flows(Complexity),
        business_rules => generate_notification_business_rules(Complexity),
        success_criteria => generate_notification_success_criteria(Complexity),
        error_scenarios => generate_notification_error_scenarios(Complexity),
        metadata => #{
            industry => "communications",
            channels => ["email", "sms", "push", "voice"],
            routing => "intelligent",
            personalization => true
        }
    }.

%% Additional domain generators (financial, supply chain, customer service, HR, security)
generate_financial_workflow(Complexity, Config) ->
    #{
        scenario_id => <<"financial_workflow_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Financial Transaction Processing",
        description => "Secure financial transaction processing with validation and compliance",
        business_domain => financial_workflow,
        complexity => Complexity,
        pattern_combination => generate_financial_patterns(Complexity),
        resource_allocations => generate_financial_resources(Complexity),
        data_flows => generate_financial_data_flows(Complexity),
        business_rules => generate_financial_business_rules(Complexity),
        success_criteria => generate_financial_success_criteria(Complexity),
        error_scenarios => generate_financial_error_scenarios(Complexity),
        metadata => #{
            industry => "finance",
            transaction_volume => "high",
            compliance_level => "strict",
            security_level => "maximum"
        }
    }.

generate_supply_chain(Complexity, Config) ->
    #{
        scenario_id => <<"supply_chain_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Supply Chain Management",
        description => "End-to-end supply chain management with inventory and logistics",
        business_domain => supply_chain,
        complexity => Complexity,
        pattern_combination => generate_supply_chain_patterns(Complexity),
        resource_allocations => generate_supply_chain_resources(Complexity),
        data_flows => generate_supply_chain_data_flows(Complexity),
        business_rules => generate_supply_chain_business_rules(Complexity),
        success_criteria => generate_supply_chain_success_criteria(Complexity),
        error_scenarios => generate_supply_chain_error_scenarios(Complexity),
        metadata => #{
            industry => "logistics",
            partners => "multi_tier",
            tracking => "real_time",
            optimization => "dynamic"
        }
    }.

generate_customer_service(Complexity, Config) ->
    #{
        scenario_id => <<"customer_service_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Customer Service Workflow",
        description => "Customer service ticket handling with routing and resolution",
        business_domain => customer_service,
        complexity => Complexity,
        pattern_combination => generate_customer_service_patterns(Complexity),
        resource_allocations => generate_customer_service_resources(Complexity),
        data_flows => generate_customer_service_data_flows(Complexity),
        business_rules => generate_customer_service_business_rules(Complexity),
        success_criteria => generate_customer_service_success_criteria(Complexity),
        error_scenarios => generate_customer_service_error_scenarios(Complexity),
        metadata => #{
            industry => "services",
            channels => ["multi_channel"],
            service_level => "premium",
            response_time => "critical"
        }
    }.

generate_hr_workflow(Complexity, Config) ->
    #{
        scenario_id => <<"hr_workflow_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Human Resources Workflow",
        description => "HR employee lifecycle management processes",
        business_domain => hr_workflow,
        complexity => Complexity,
        pattern_combination => generate_hr_patterns(Complexity),
        resource_allocations => generate_hr_resources(Complexity),
        data_flows => generate_hr_data_flows(Complexity),
        business_rules => generate_hr_business_rules(Complexity),
        success_criteria => generate_hr_success_criteria(Complexity),
        error_scenarios => generate_hr_error_scenarios(Complexity),
        metadata => #{
            industry => "hr",
            processes => ["employee_lifecycle"],
            compliance => "strict",
            confidentiality => "high"
        }
    }.

generate_security_audit(Complexity, Config) ->
    #{
        scenario_id => <<"security_audit_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Security Audit Workflow",
        description => "Security audit processing with compliance checks",
        business_domain => security_audit,
        complexity => Complexity,
        pattern_combination => generate_security_patterns(Complexity),
        resource_allocations => generate_security_resources(Complexity),
        data_flows => generate_security_data_flows(Complexity),
        business_rules => generate_security_business_rules(Complexity),
        success_criteria => generate_security_success_criteria(Complexity),
        error_scenarios => generate_security_error_scenarios(Complexity),
        metadata => #{
            industry => "security",
            audit_type => "comprehensive",
            compliance_framework => "multiple",
            risk_level => "high"
        }
    }.

%%====================================================================
%% Helper Functions
%%====================================================================

determine_scenario_complexity(BusinessDomain, Config) ->
    %% Determine appropriate complexity for business domain
    case BusinessDomain of
        order_processing -> medium;
        document_workflow -> medium;
        data_pipeline -> high;
        approval_chain -> high;
        notification_system -> medium;
        financial_workflow -> high;
        supply_chain -> high;
        customer_service -> medium;
        hr_workflow -> medium;
        security_audit -> high
    end.

generate_load_profile() ->
    #{
        initial_load => 10,
        peak_load => 1000,
        ramp_up_time => 30000,
        sustained_duration => 240000,
        ramp_down_time => 30000,
        load_profile_type => "gradual"
    }.

generate_failure_injections() ->
    [
        {service_timeout, probability => 0.1, duration => 5000},
        {resource_exhaustion, probability => 0.05, resource => "memory"},
        {network_partition, probability => 0.08, duration => 10000},
        {data_corruption, probability => 0.02, severity => "critical"}
    ].

generate_recovery_strategies() ->
    [
        {retry_with_exponential_backoff, max_attempts => 5, base_delay => 1000},
        {circuit_breaker, threshold => 10, timeout => 30000},
        {graceful_degradation, fallback_service => "backup_service"},
        {manual_intervention, escalation_threshold => 0.9}
    ].

merge_custom_config(BaseScenario, CustomConfig) ->
    %% Merge custom configuration with base scenario
    maps:merge(BaseScenario, CustomConfig).

%% Remaining pattern, resource, data flow, business rule, success criteria,
%% and error scenario generators would follow similar patterns to the ones above.
%% They would generate domain-specific configurations based on complexity level.

generate_approval_patterns(Complexity) ->
    case Complexity of
        low ->
            [
                {basic_sequential, #{task => "submit_request"}},
                {exclusive_choice, #{conditions => [standard_request, complex_request]}},
                {basic_sequential, #{task => "approve_request"}},
                {basic_sequential, #{task => "execute_request"}}
            ];
        medium ->
            [
                {basic_sequential, #{task => "submit_request"}},
                {exclusive_choice, #{conditions => [standard, expensive, emergency]}},
                {parallel_split, #{branches => 3, tasks => ["department_review", "finance_review", "risk_assessment"]}},
                {simple_merge, #{branches => 3}},
                {exclusive_choice, #{conditions => [approve, request_more_info, reject]}},
                {iterative_loop, #{condition => request_more_info, max_iterations => 3}},
                {basic_sequential, #{task => "execute_request"}}
            ];
        high ->
            [
                {basic_sequential, #{task => "submit_request"}},
                {exclusive_choice, #{conditions => [standard, expensive, emergency, strategic]}},
                {parallel_split, #{branches => 4, tasks => ["department_review", "finance_review", "risk_assessment", "compliance_check"]}},
                {interleaved_parallelism, #{tasks => ["impact_analysis", "benefit_evaluation"]}},
                {simple_merge, #{branches => 4}},
                {exclusive_choice, #{conditions => [approve, request_more_info, reject, escalate]}},
                {multi_instance, #{num_instances => 5, data => stakeholder_reviews}},
                {iterative_loop, #{condition => request_more_info, max_iterations => 5}},
                {basic_sequential, #{task => "execute_request"}},
                {cancelation_block, #{scope => "approval_process"}}
            ]
    end.

generate_approval_resources(Complexity) ->
    BaseResources = #{
        "submit_request" => ["request_system", "routing_engine"],
        "department_review" => ["department_managers", "policy_checkers"],
        "finance_review" => ["finance_team", "budget_validators"],
        "risk_assessment" => ["risk_officers", "compliance_tools"],
        "approve" => ["final_approver", "authority_system"]
    },

    case Complexity of
        low -> BaseResources;
        medium -> BaseResources#{"compliance_check" => ["compliance_officers"]};
        high -> BaseResources#{"compliance_check" => ["compliance_officers"],
                             "impact_analysis" => ["analysts"], "benefit_evaluation" => ["evaluators"]}
    end.

generate_notification_patterns(Complexity) ->
    case Complexity of
        low ->
            [
                {basic_sequential, #{task => "event_detected"}},
                {parallel_split, #{branches => 2, tasks => ["send_email", "send_sms"]}},
                {simple_merge, #{branches => 2}},
                {basic_sequential, #{task => "confirm_delivery"}}
            ];
        medium ->
            [
                {basic_sequential, #{task => "event_detected"}},
                {exclusive_choice, #{conditions => [critical_event, normal_event, bulk_notification]}},
                {parallel_split, #{branches => 4, tasks => ["immediate_alert", "scheduled_notification", "bulk_email", "sms_alert"]}},
                {interleaved_parallelism, #{tasks => ["priority_routing", "channel_optimization"]}},
                {simple_merge, #{branches => 4}},
                {basic_sequential, #{task => "confirm_delivery"}},
                {iterative_loop, #{condition => delivery_failed, max_iterations => 3}}
            ];
        high ->
            [
                {basic_sequential, #{task => "event_detected"}},
                {exclusive_choice, #{conditions => [critical_event, normal_event, bulk_notification, emergency_broadcast]}},
                {parallel_split, #{branches => 5, tasks => ["immediate_alert", "scheduled_notification", "bulk_email", "sms_alert", "push_notification"]}},
                {interleaved_parallelism, #{tasks => ["priority_routing", "channel_optimization", "personalization"]}},
                {simple_merge, #{branches => 5}},
                {basic_sequential, #{task => "confirm_delivery"}},
                {iterative_loop, #{condition => delivery_failed, max_iterations => 5}},
                {multi_instance, #{num_instances => 10, data => user_notifications}},
                {cancelation_block, #{scope => "notification_process"}},
                {nested_patterns, #{patterns => ["analytics_system", "feedback_loop"]}}
            ]
    end.

generate_notification_resources(Complexity) ->
    BaseResources = #{
        "event_detected" => ["event_monitor", "alert_processor"],
        "immediate_alert" => ["push_service", "priority_queue"],
        "scheduled_notification" => ["scheduler_service", "database"],
        "bulk_email" => ["email_service", "template_engine"],
        "sms_alert" => ["sms_service", "rate_limiter"],
        "confirm_delivery" => ["confirmation_system", "tracking_service"]
    },

    case Complexity of
        low -> BaseResources;
        medium -> BaseResources#{"priority_routing" => ["routing_service"], "channel_optimization" => ["optimization_engine"]};
        high -> BaseResources#{"priority_routing" => ["routing_service"], "channel_optimization" => ["optimization_engine"],
                              "personalization" => ["personalization_engine"],
                              "analytics_system" => ["analytics_service"], "feedback_loop" => ["feedback_service"]}
    end.