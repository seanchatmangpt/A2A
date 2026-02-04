%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Business Scenarios
%%%
%%% This module defines business domain scenario generators for YAWL
%%% workflow patterns. Each scenario represents a realistic business
%%% process that can be modeled using YAWL patterns.
%%%
%%% ## Supported Business Domains
%%%
%%% - Order Processing (e-commerce)
%%% - Document Workflow (approvals)
%%% - Data Pipeline (ETL/ELT)
%%% - Approval Chain (multi-level)
%%% - Notification System (multi-channel)
%%% - Financial Workflow (transactions)
%%% - Supply Chain (logistics)
%%% - Customer Service (ticket handling)
%%% - HR Workflow (employee lifecycle)
%%% - Security Audit (compliance)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_business_scenarios).
-author("A2A Team").

%% API exports
-export([
    order_processing_scenario/1,
    document_workflow_scenario/1,
    data_pipeline_scenario/1,
    approval_chain_scenario/1,
    notification_scenario/1,
    financial_workflow_scenario/1,
    supply_chain_scenario/1,
    customer_service_scenario/1,
    hr_workflow_scenario/1,
    security_audit_scenario/1,
    list_domains/0,
    validate_domain/1,
    get_scenario_template/2
]).

%% Include type definitions
-include("yawl_types.hrl").

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Generate order processing scenario.
-spec order_processing_scenario(low | medium | high) -> #yawl_scenario{}.
order_processing_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(order_processing),
    PatternCombination = order_processing_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "E-commerce Order Processing",
        description = "Complete e-commerce order processing from validation to fulfillment",
        business_domain = order_processing,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = order_processing_resources(Complexity),
        data_flows = order_processing_data_flows(Complexity),
        business_rules = order_processing_rules(Complexity),
        success_criteria = order_processing_success_criteria(Complexity),
        error_scenarios = order_processing_errors(Complexity),
        metadata = #{
            industry => "e-commerce",
            transaction_volume => "high",
            seasonality => true,
            peak_load_factor => 3.0
        }
    }.

%% @doc Generate document workflow scenario.
-spec document_workflow_scenario(low | medium | high) -> #yawl_scenario{}.
document_workflow_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(document_workflow),
    PatternCombination = document_workflow_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Document Approval Workflow",
        description = "Multi-stage document approval process with review and routing",
        business_domain = document_workflow,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = document_workflow_resources(Complexity),
        data_flows = document_workflow_data_flows(Complexity),
        business_rules = document_workflow_rules(Complexity),
        success_criteria = document_workflow_success_criteria(Complexity),
        error_scenarios = document_workflow_errors(Complexity),
        metadata = #{
            industry => "finance",
            document_types => ["contract", "agreement", "policy"],
            approval_required => true,
            retention_period => 7
        }
    }.

%% @doc Generate data pipeline scenario.
-spec data_pipeline_scenario(low | medium | high) -> #yawl_scenario{}.
data_pipeline_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(data_pipeline),
    PatternCombination = data_pipeline_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Data Processing Pipeline",
        description = "Large-scale data processing with validation, transformation, and storage",
        business_domain = data_pipeline,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = data_pipeline_resources(Complexity),
        data_flows = data_pipeline_data_flows(Complexity),
        business_rules = data_pipeline_rules(Complexity),
        success_criteria = data_pipeline_success_criteria(Complexity),
        error_scenarios = data_pipeline_errors(Complexity),
        metadata = #{
            industry => "technology",
            data_volume => "very_high",
            processing_type => "batch_streaming",
            quality_requirements => "strict"
        }
    }.

%% @doc Generate approval chain scenario.
-spec approval_chain_scenario(low | medium | high) -> #yawl_scenario{}.
approval_chain_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(approval_chain),
    PatternCombination = approval_chain_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Multi-level Approval Chain",
        description = "Complex approval workflow with multiple levels and dependencies",
        business_domain = approval_chain,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = approval_chain_resources(Complexity),
        data_flows = approval_chain_data_flows(Complexity),
        business_rules = approval_chain_rules(Complexity),
        success_criteria = approval_chain_success_criteria(Complexity),
        error_scenarios = approval_chain_errors(Complexity),
        metadata = #{
            industry => "manufacturing",
            approval_levels => "multi_tier",
            escalation_required => true,
            approval_matrix => "complex"
        }
    }.

%% @doc Generate notification system scenario.
-spec notification_scenario(low | medium | high) -> #yawl_scenario{}.
notification_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(notification_system),
    PatternCombination = notification_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Multi-channel Notification System",
        description = "Distributed notification system with multiple channels and routing rules",
        business_domain = notification_system,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = notification_resources(Complexity),
        data_flows = notification_data_flows(Complexity),
        business_rules = notification_rules(Complexity),
        success_criteria = notification_success_criteria(Complexity),
        error_scenarios = notification_errors(Complexity),
        metadata = #{
            industry => "communications",
            channels => ["email", "sms", "push", "voice"],
            routing => "intelligent",
            personalization => true
        }
    }.

%% @doc Generate financial workflow scenario.
-spec financial_workflow_scenario(low | medium | high) -> #yawl_scenario{}.
financial_workflow_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(financial_workflow),
    PatternCombination = financial_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Financial Transaction Processing",
        description = "Secure financial transaction processing with validation and compliance",
        business_domain = financial_workflow,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = financial_resources(Complexity),
        data_flows = financial_data_flows(Complexity),
        business_rules = financial_rules(Complexity),
        success_criteria = financial_success_criteria(Complexity),
        error_scenarios = financial_errors(Complexity),
        metadata = #{
            industry => "finance",
            transaction_volume => "high",
            compliance_level => "strict",
            security_level => "maximum"
        }
    }.

%% @doc Generate supply chain scenario.
-spec supply_chain_scenario(low | medium | high) -> #yawl_scenario{}.
supply_chain_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(supply_chain),
    PatternCombination = supply_chain_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Supply Chain Management",
        description = "End-to-end supply chain management with inventory and logistics",
        business_domain = supply_chain,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = supply_chain_resources(Complexity),
        data_flows = supply_chain_data_flows(Complexity),
        business_rules = supply_chain_rules(Complexity),
        success_criteria = supply_chain_success_criteria(Complexity),
        error_scenarios = supply_chain_errors(Complexity),
        metadata = #{
            industry => "logistics",
            partners => "multi_tier",
            tracking => "real_time",
            optimization => "dynamic"
        }
    }.

%% @doc Generate customer service scenario.
-spec customer_service_scenario(low | medium | high) -> #yawl_scenario{}.
customer_service_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(customer_service),
    PatternCombination = customer_service_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Customer Service Workflow",
        description = "Customer service ticket handling with routing and resolution",
        business_domain = customer_service,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = customer_service_resources(Complexity),
        data_flows = customer_service_data_flows(Complexity),
        business_rules = customer_service_rules(Complexity),
        success_criteria = customer_service_success_criteria(Complexity),
        error_scenarios = customer_service_errors(Complexity),
        metadata = #{
            industry => "services",
            channels => ["multi_channel"],
            service_level => "premium",
            response_time => "critical"
        }
    }.

%% @doc Generate HR workflow scenario.
-spec hr_workflow_scenario(low | medium | high) -> #yawl_scenario{}.
hr_workflow_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(hr_workflow),
    PatternCombination = hr_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Human Resources Workflow",
        description = "HR employee lifecycle management processes",
        business_domain = hr_workflow,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = hr_resources(Complexity),
        data_flows = hr_data_flows(Complexity),
        business_rules = hr_rules(Complexity),
        success_criteria = hr_success_criteria(Complexity),
        error_scenarios = hr_errors(Complexity),
        metadata = #{
            industry => "hr",
            processes => ["employee_lifecycle"],
            compliance => "strict",
            confidentiality => "high"
        }
    }.

%% @doc Generate security audit scenario.
-spec security_audit_scenario(low | medium | high) -> #yawl_scenario{}.
security_audit_scenario(Complexity) ->
    ScenarioId = generate_scenario_id(security_audit),
    PatternCombination = security_patterns(Complexity),
    #yawl_scenario{
        scenario_id = ScenarioId,
        name = "Security Audit Workflow",
        description = "Security audit processing with compliance checks",
        business_domain = security_audit,
        complexity = Complexity,
        pattern_combination = PatternCombination,
        resource_allocations = security_resources(Complexity),
        data_flows = security_data_flows(Complexity),
        business_rules = security_rules(Complexity),
        success_criteria = security_success_criteria(Complexity),
        error_scenarios = security_errors(Complexity),
        metadata = #{
            industry => "security",
            audit_type => "comprehensive",
            compliance_framework => "multiple",
            risk_level => "high"
        }
    }.

%% @doc List all available business domains.
-spec list_domains() -> [business_domain()].
list_domains() ->
    ?BUSINESS_DOMAINS.

%% @doc Validate a business domain.
-spec validate_domain(business_domain()) -> boolean().
validate_domain(Domain) ->
    lists:member(Domain, list_domains()).

%% @doc Get a scenario template for a domain and complexity.
-spec get_scenario_template(business_domain(), low | medium | high) -> #yawl_scenario{}.
get_scenario_template(order_processing, Complexity) -> order_processing_scenario(Complexity);
get_scenario_template(document_workflow, Complexity) -> document_workflow_scenario(Complexity);
get_scenario_template(data_pipeline, Complexity) -> data_pipeline_scenario(Complexity);
get_scenario_template(approval_chain, Complexity) -> approval_chain_scenario(Complexity);
get_scenario_template(notification_system, Complexity) -> notification_scenario(Complexity);
get_scenario_template(financial_workflow, Complexity) -> financial_workflow_scenario(Complexity);
get_scenario_template(supply_chain, Complexity) -> supply_chain_scenario(Complexity);
get_scenario_template(customer_service, Complexity) -> customer_service_scenario(Complexity);
get_scenario_template(hr_workflow, Complexity) -> hr_workflow_scenario(Complexity);
get_scenario_template(security_audit, Complexity) -> security_audit_scenario(Complexity).

%%====================================================================
%% Internal Pattern Generators
%%====================================================================

%% Order Processing Patterns
order_processing_patterns(low) ->
    [
        {basic_sequential, #{task => "validate_order"}},
        {exclusive_choice, #{conditions => [is_valid, needs_approval]}},
        {parallel_split, #{branches => 2, tasks => ["process_payment", "check_inventory"]}},
        {parallel_join, #{branches => 2}},
        {basic_sequential, #{task => "ship_order"}}
    ];
order_processing_patterns(medium) ->
    [
        {basic_sequential, #{task => "validate_order"}},
        {exclusive_choice, #{conditions => [is_valid, needs_approval, requires_review]}},
        {parallel_split, #{branches => 3, tasks => ["process_payment", "check_inventory", "calculate_shipping"]}},
        {parallel_join, #{branches => 3}},
        {exclusive_choice, #{conditions => [can_ship, backorder, cancel_order]}},
        {multi_instance, #{num_instances => 3, data => order_items}},
        {iterative_loop, #{condition => has_items_to_backorder}}
    ];
order_processing_patterns(high) ->
    [
        {basic_sequential, #{task => "validate_order"}},
        {exclusive_choice, #{conditions => [is_valid, needs_approval, requires_review, is_international]}},
        {parallel_split, #{branches => 4, tasks => ["process_payment", "check_inventory", "calculate_shipping", "fraud_check"]}},
        {interleaved_parallelism, #{tasks => ["price_validation", "coupon_check"]}},
        {parallel_join, #{branches => 4}},
        {exclusive_choice, #{conditions => [can_ship, backorder, cancel_order, hold_for_review]}},
        {multi_instance, #{num_instances => 5, data => order_items}},
        {cancelation_block, #{scope => "fulfillment_process"}}
    ].

%% Document Workflow Patterns
document_workflow_patterns(low) ->
    [
        {basic_sequential, #{task => "submit_document"}},
        {exclusive_choice, #{conditions => [standard, review_needed]}},
        {basic_sequential, #{task => "approve_document"}},
        {basic_sequential, #{task => "archive_document"}}
    ];
document_workflow_patterns(medium) ->
    [
        {basic_sequential, #{task => "submit_document"}},
        {exclusive_choice, #{conditions => [standard, legal, confidential]}},
        {parallel_split, #{branches => 3, tasks => ["legal_review", "technical_review", "compliance_review"]}},
        {simple_merge, #{branches => 3}},
        {exclusive_choice, #{conditions => [approve, request_changes, reject]}},
        {iterative_loop, #{condition => requested_changes}}
    ];
document_workflow_patterns(high) ->
    [
        {basic_sequential, #{task => "submit_document"}},
        {exclusive_choice, #{conditions => [standard, legal, confidential, executive]}},
        {parallel_split, #{branches => 4, tasks => ["legal_review", "technical_review", "compliance_review", "executive_review"]}},
        {interleaved_parallelism, #{tasks => ["content_check", "format_validation"]}},
        {simple_merge, #{branches => 4}},
        {exclusive_choice, #{conditions => [approve, request_changes, reject, escalate]}},
        {multi_instance, #{num_instances => 3, data => stakeholder_reviews}},
        {cancelation_block, #{scope => "approval_process"}}
    ].

%% Data Pipeline Patterns
data_pipeline_patterns(low) ->
    [
        {basic_sequential, #{task => "extract_data"}},
        {parallel_split, #{branches => 2, tasks => ["validate_data", "transform_data"]}},
        {simple_merge, #{branches => 2}},
        {basic_sequential, #{task => "store_data"}}
    ];
data_pipeline_patterns(medium) ->
    [
        {basic_sequential, #{task => "extract_data"}},
        {parallel_split, #{branches => 4, tasks => ["validate_format", "check_completeness", "transform_data", "enrich_data"]}},
        {interleaved_parallelism, #{tasks => ["quality_check", "consistency_check"]}},
        {multiple_merge, #{branches => 3}},
        {multi_instance, #{num_instances => 5, data => data_records}},
        {iterative_loop, #{condition => has_more_data}}
    ];
data_pipeline_patterns(high) ->
    [
        {basic_sequential, #{task => "extract_data"}},
        {parallel_split, #{branches => 6, tasks => ["validate_format", "check_completeness", "transform_data", "enrich_data", "deduplicate", "aggregate"]}},
        {interleaved_parallelism, #{tasks => ["quality_check", "consistency_check", "anomaly_detection"]}},
        {multiple_merge, #{branches => 4}},
        {multi_instance, #{num_instances => 10, data => data_records}},
        {iterative_loop, #{condition => has_more_data, max_iterations => 20}},
        {cancelation_block, #{scope => "processing_pipeline"}}
    ].

%% Approval Chain Patterns
approval_chain_patterns(low) ->
    [
        {basic_sequential, #{task => "submit_request"}},
        {exclusive_choice, #{conditions => [standard_request, complex_request]}},
        {basic_sequential, #{task => "approve_request"}},
        {basic_sequential, #{task => "execute_request"}}
    ];
approval_chain_patterns(medium) ->
    [
        {basic_sequential, #{task => "submit_request"}},
        {exclusive_choice, #{conditions => [standard, expensive, emergency]}},
        {parallel_split, #{branches => 3, tasks => ["department_review", "finance_review", "risk_assessment"]}},
        {simple_merge, #{branches => 3}},
        {exclusive_choice, #{conditions => [approve, request_more_info, reject]}},
        {iterative_loop, #{condition => request_more_info}}
    ];
approval_chain_patterns(high) ->
    [
        {basic_sequential, #{task => "submit_request"}},
        {exclusive_choice, #{conditions => [standard, expensive, emergency, strategic]}},
        {parallel_split, #{branches => 4, tasks => ["department_review", "finance_review", "risk_assessment", "compliance_check"]}},
        {interleaved_parallelism, #{tasks => ["impact_analysis", "benefit_evaluation"]}},
        {simple_merge, #{branches => 4}},
        {exclusive_choice, #{conditions => [approve, request_more_info, reject, escalate]}},
        {multi_instance, #{num_instances => 5, data => stakeholder_reviews}},
        {iterative_loop, #{condition => request_more_info}},
        {cancelation_block, #{scope => "approval_process"}}
    ].

%% Notification Patterns
notification_patterns(low) ->
    [
        {basic_sequential, #{task => "event_detected"}},
        {parallel_split, #{branches => 2, tasks => ["send_email", "send_sms"]}},
        {simple_merge, #{branches => 2}},
        {basic_sequential, #{task => "confirm_delivery"}}
    ];
notification_patterns(medium) ->
    [
        {basic_sequential, #{task => "event_detected"}},
        {exclusive_choice, #{conditions => [critical_event, normal_event, bulk_notification]}},
        {parallel_split, #{branches => 4, tasks => ["immediate_alert", "scheduled_notification", "bulk_email", "sms_alert"]}},
        {interleaved_parallelism, #{tasks => ["priority_routing", "channel_optimization"]}},
        {simple_merge, #{branches => 4}},
        {iterative_loop, #{condition => delivery_failed}}
    ];
notification_patterns(high) ->
    [
        {basic_sequential, #{task => "event_detected"}},
        {exclusive_choice, #{conditions => [critical_event, normal_event, bulk_notification, emergency_broadcast]}},
        {parallel_split, #{branches => 5, tasks => ["immediate_alert", "scheduled_notification", "bulk_email", "sms_alert", "push_notification"]}},
        {interleaved_parallelism, #{tasks => ["priority_routing", "channel_optimization", "personalization"]}},
        {simple_merge, #{branches => 5}},
        {iterative_loop, #{condition => delivery_failed}},
        {multi_instance, #{num_instances => 10, data => user_notifications}},
        {cancelation_block, #{scope => "notification_process"}}
    ].

%% Financial Workflow Patterns
financial_patterns(low) ->
    [
        {basic_sequential, #{task => "initiate_transaction"}},
        {exclusive_choice, #{conditions => [standard, high_value]}},
        {basic_sequential, #{task => "validate_transaction"}},
        {basic_sequential, #{task => "process_payment"}}
    ];
financial_patterns(medium) ->
    [
        {basic_sequential, #{task => "initiate_transaction"}},
        {exclusive_choice, #{conditions => [standard, high_value, international]}},
        {parallel_split, #{branches => 3, tasks => ["fraud_check", "compliance_check", "balance_check"]}},
        {parallel_join, #{branches => 3}},
        {exclusive_choice, #{conditions => [approve, decline, manual_review]}},
        {basic_sequential, #{task => "execute_transfer"}}
    ];
financial_patterns(high) ->
    [
        {basic_sequential, #{task => "initiate_transaction"}},
        {exclusive_choice, #{conditions => [standard, high_value, international, regulated]}},
        {parallel_split, #{branches => 5, tasks => ["fraud_check", "compliance_check", "balance_check", "sanctions_check", "aml_check"]}},
        {interleaved_parallelism, #{tasks => ["risk_scoring", "customer_verification"]}},
        {parallel_join, #{branches => 5}},
        {exclusive_choice, #{conditions => [approve, decline, manual_review, hold]}},
        {multi_instance, #{num_instances => 3, data => regulatory_approvals}},
        {cancelation_block, #{scope => "transaction_process"}}
    ].

%% Supply Chain Patterns
supply_chain_patterns(low) ->
    [
        {basic_sequential, #{task => "receive_order"}},
        {exclusive_choice, #{conditions => [in_stock, out_of_stock]}},
        {basic_sequential, #{task => "allocate_inventory"}},
        {basic_sequential, #{task => "schedule_shipment"}}
    ];
supply_chain_patterns(medium) ->
    [
        {basic_sequential, #{task => "receive_order"}},
        {parallel_split, #{branches => 3, tasks => ["check_inventory", "select_supplier", "calculate_shipping"]}},
        {parallel_join, #{branches => 3}},
        {exclusive_choice, #{conditions => [fulfill, backorder, cancel]}},
        {multi_instance, #{num_instances => 3, data => warehouse_locations}},
        {basic_sequential, #{task => "confirm_shipment"}}
    ];
supply_chain_patterns(high) ->
    [
        {basic_sequential, #{task => "receive_order"}},
        {parallel_split, #{branches => 5, tasks => ["check_inventory", "select_suppliers", "optimize_routing", "calculate_costs", "verify_compliance"]}},
        {interleaved_parallelism, #{tasks => ["demand_forecasting", "capacity_planning"]}},
        {parallel_join, #{branches => 5}},
        {exclusive_choice, #{conditions => [fulfill, partial_fulfill, backorder, cancel, escalate]}},
        {multi_instance, #{num_instances => 10, data => distribution_centers}},
        {iterative_loop, #{condition => awaiting_replenishment}},
        {cancelation_block, #{scope => "fulfillment_process"}}
    ].

%% Customer Service Patterns
customer_service_patterns(low) ->
    [
        {basic_sequential, #{task => "receive_ticket"}},
        {exclusive_choice, #{conditions => [general, technical, billing]}},
        {basic_sequential, #{task => "assign_agent"}},
        {basic_sequential, #{task => "resolve_ticket"}}
    ];
customer_service_patterns(medium) ->
    [
        {basic_sequential, #{task => "receive_ticket"}},
        {exclusive_choice, #{conditions => [general, technical, billing, urgent]}},
        {parallel_split, #{branches => 3, tasks => ["categorize", "prioritize", "route"]}},
        {parallel_join, #{branches => 3}},
        {iterative_loop, #{condition => awaiting_response}},
        {basic_sequential, #{task => "close_ticket"}}
    ];
customer_service_patterns(high) ->
    [
        {basic_sequential, #{task => "receive_ticket"}},
        {exclusive_choice, #{conditions => [general, technical, billing, urgent, escalation]}},
        {parallel_split, #{branches => 4, tasks => ["categorize", "prioritize", "route", "estimate"]}},
        {interleaved_parallelism, #{tasks => ["knowledge_search", "similar_cases"]}},
        {parallel_join, #{branches => 4}},
        {multi_instance, #{num_instances => 3, data => support_tiers}},
        {iterative_loop, #{condition => awaiting_response}},
        {cancelation_block, #{scope => "support_process"}}
    ].

%% HR Workflow Patterns
hr_patterns(low) ->
    [
        {basic_sequential, #{task => "initiate_request"}},
        {exclusive_choice, #{conditions => [hire, transfer, terminate]}},
        {basic_sequential, #{task => "process_action"}},
        {basic_sequential, #{task => "update_records"}}
    ];
hr_patterns(medium) ->
    [
        {basic_sequential, #{task => "initiate_request"}},
        {exclusive_choice, #{conditions => [hire, transfer, promote, terminate]}},
        {parallel_split, #{branches => 3, tasks => ["legal_review", "compensation_review", "system_updates"]}},
        {parallel_join, #{branches => 3}},
        {exclusive_choice, #{conditions => [approve, reject, modify]}},
        {iterative_loop, #{condition => needs_modification}}
    ];
hr_patterns(high) ->
    [
        {basic_sequential, #{task => "initiate_request"}},
        {exclusive_choice, #{conditions => [hire, transfer, promote, terminate, leave]}},
        {parallel_split, #{branches => 5, tasks => ["legal_review", "compensation_review", "benefits_check", "system_updates", "compliance_check"]}},
        {interleaved_parallelism, #{tasks => ["background_check", "verification"]}},
        {parallel_join, #{branches => 5}},
        {multi_instance, #{num_instances => 3, data => approvals}},
        {iterative_loop, #{condition => needs_modification}},
        {cancelation_block, #{scope => "hr_process"}}
    ].

%% Security Audit Patterns
security_patterns(low) ->
    [
        {basic_sequential, #{task => "initiate_audit"}},
        {basic_sequential, #{task => "collect_evidence"}},
        {basic_sequential, #{task => "analyze_findings"}},
        {basic_sequential, #{task => "generate_report"}}
    ];
security_patterns(medium) ->
    [
        {basic_sequential, #{task => "initiate_audit"}},
        {parallel_split, #{branches => 3, tasks => ["scan_vulnerabilities", "review_logs", "interview_staff"]}},
        {parallel_join, #{branches => 3}},
        {exclusive_choice, #{conditions => [compliant, non_compliant, partial]}},
        {iterative_loop, #{condition => remediation_required}},
        {basic_sequential, #{task => "final_report"}}
    ];
security_patterns(high) ->
    [
        {basic_sequential, #{task => "initiate_audit"}},
        {parallel_split, #{branches => 5, tasks => ["scan_vulnerabilities", "review_logs", "interview_staff", "check_policies", "test_controls"]}},
        {interleaved_parallelism, #{tasks => ["threat_analysis", "risk_assessment"]}},
        {parallel_join, #{branches => 5}},
        {exclusive_choice, #{conditions => [compliant, non_compliant, partial, critical]}},
        {multi_instance, #{num_instances => 3, data => frameworks}},
        {iterative_loop, #{condition => remediation_required}},
        {cancelation_block, #{scope => "audit_process"}}
    ].

%%====================================================================
%% Resource Allocation Generators
%%====================================================================

order_processing_resources(low) ->
    #{
        "validate_order" => ["validation_service", "customer_db"],
        "process_payment" => ["payment_gateway"],
        "check_inventory" => ["inventory_service"],
        "ship_order" => ["fulfillment_service"]
    };
order_processing_resources(medium) ->
    LowRes = order_processing_resources(low),
    maps:merge(LowRes, #{
        "calculate_shipping" => ["shipping_service"],
        "price_validation" => ["pricing_service"]
    });
order_processing_resources(high) ->
    MedRes = order_processing_resources(medium),
    maps:merge(MedRes, #{
        "fraud_check" => ["fraud_detection"],
        "tracking_updates" => ["tracking_service"]
    }).

document_workflow_resources(_) ->
    #{
        "submit_document" => ["document_system", "user_interface"],
        "legal_review" => ["legal_expert", "compliance_tool"],
        "technical_review" => ["technical_lead", "standards_checker"],
        "compliance_review" => ["compliance_officer", "audit_tool"],
        "approve" => ["authority_system", "digital_signature"]
    }.

data_pipeline_resources(low) ->
    #{
        "extract_data" => ["extractor_service"],
        "validate_data" => ["validator_service"],
        "transform_data" => ["transformation_engine"],
        "store_data" => ["storage_service"]
    };
data_pipeline_resources(medium) ->
    LowRes = data_pipeline_resources(low),
    maps:merge(LowRes, #{
        "check_completeness" => ["completeness_checker"],
        "enrich_data" => ["enrichment_service"],
        "quality_check" => ["quality_assurance"]
    });
data_pipeline_resources(high) ->
    MedRes = data_pipeline_resources(medium),
    maps:merge(MedRes, #{
        "deduplicate" => ["deduplication_service"],
        "aggregate" => ["aggregation_engine"],
        "anomaly_detection" => ["anomaly_detector"]
    }).

%% Default resource allocations for remaining domains
approval_chain_resources(_) ->
    #{
        "submit_request" => ["request_system"],
        "department_review" => ["department_manager"],
        "finance_review" => ["finance_team"],
        "risk_assessment" => ["risk_officer"],
        "approve" => ["final_approver"]
    }.

notification_resources(_) ->
    #{
        "event_detected" => ["event_monitor"],
        "immediate_alert" => ["push_service"],
        "scheduled_notification" => ["scheduler_service"],
        "bulk_email" => ["email_service"],
        "sms_alert" => ["sms_service"]
    }.

financial_resources(_) ->
    #{
        "initiate_transaction" => ["transaction_service"],
        "fraud_check" => ["fraud_detection"],
        "compliance_check" => ["compliance_system"],
        "balance_check" => ["accounting_system"],
        "execute_transfer" => ["payment_processor"]
    }.

supply_chain_resources(_) ->
    #{
        "receive_order" => ["order_system"],
        "check_inventory" => ["inventory_service"],
        "select_supplier" => ["supplier_system"],
        "calculate_shipping" => ["logistics_service"],
        "confirm_shipment" => ["shipping_system"]
    }.

customer_service_resources(_) ->
    #{
        "receive_ticket" => ["ticket_system"],
        "categorize" => ["classifier"],
        "prioritize" => ["priority_engine"],
        "route" => ["router"],
        "close_ticket" => ["closing_system"]
    }.

hr_resources(_) ->
    #{
        "initiate_request" => ["hr_portal"],
        "legal_review" => ["legal_team"],
        "compensation_review" => ["compensation_team"],
        "system_updates" => ["hris_system"],
        "compliance_check" => ["compliance_team"]
    }.

security_resources(_) ->
    #{
        "initiate_audit" => ["audit_system"],
        "scan_vulnerabilities" => ["scanner"],
        "review_logs" => ["log_analyzer"],
        "interview_staff" => ["interviewer"],
        "generate_report" => ["report_generator"]
    }.

%%====================================================================
%% Data Flow Generators
%%====================================================================

order_processing_data_flows(_) ->
    #{
        "order_data" => ["validate_order", "process_payment"],
        "customer_data" => ["validate_order", "calculate_shipping"],
        "inventory_data" => ["check_inventory", "ship_order"],
        "payment_result" => ["ship_order"]
    }.

document_workflow_data_flows(_) ->
    #{
        "document_content" => ["submit_document", "legal_review", "technical_review"],
        "review_feedback" => ["legal_review", "technical_review", "compliance_review"],
        "approval_status" => ["approve", "request_changes", "reject"]
    }.

data_pipeline_data_flows(_) ->
    #{
        "raw_data" => ["extract_data", "validate_format", "check_completeness"],
        "validated_data" => ["validate_format", "transform_data", "enrich_data"],
        "transformed_data" => ["transform_data", "store_data"]
    }.

approval_chain_data_flows(_) ->
    #{
        "request_data" => ["submit_request", "department_review", "finance_review"],
        "review_outcomes" => ["department_review", "finance_review", "risk_assessment"],
        "approval_status" => ["approve", "request_more_info", "reject"]
    }.

notification_data_flows(_) ->
    #{
        "event_data" => ["event_detected", "immediate_alert", "scheduled_notification"],
        "notification_config" => ["priority_routing", "channel_optimization"],
        "delivery_status" => ["immediate_alert", "bulk_email", "sms_alert"]
    }.

financial_data_flows(_) ->
    #{
        "transaction_data" => ["initiate_transaction", "fraud_check", "compliance_check"],
        "risk_assessment" => ["fraud_check", "compliance_check", "approve"],
        "transfer_details" => ["approve", "execute_transfer"]
    }.

supply_chain_data_flows(_) ->
    #{
        "order_data" => ["receive_order", "check_inventory", "select_supplier"],
        "inventory_status" => ["check_inventory", "allocate_inventory"],
        "shipment_details" => ["schedule_shipment", "confirm_shipment"]
    }.

customer_service_data_flows(_) ->
    #{
        "ticket_data" => ["receive_ticket", "categorize", "prioritize"],
        "routing_info" => ["route", "assign_agent"],
        "resolution" => ["assign_agent", "close_ticket"]
    }.

hr_data_flows(_) ->
    #{
        "request_data" => ["initiate_request", "legal_review", "compensation_review"],
        "approval_chain" => ["legal_review", "system_updates"],
        "employee_record" => ["system_updates", "update_records"]
    }.

security_data_flows(_) ->
    #{
        "audit_scope" => ["initiate_audit", "collect_evidence"],
        "evidence_data" => ["collect_evidence", "analyze_findings"],
        "findings" => ["analyze_findings", "generate_report"]
    }.

%%====================================================================
%% Business Rule Generators
%%====================================================================

order_processing_rules(low) ->
    [
        {auto_approve, #{condition => "order_amount < 50 and customer_status == verified", action => approve}},
        {manual_review, #{condition => "order_amount > 1000", action => require_review}},
        {free_shipping, #{condition => "order_amount > 100", action => apply_free_shipping}}
    ];
order_processing_rules(medium) ->
    order_processing_rules(low) ++ [
        {international_shipping, #{condition => "is_international", action => apply_international_rules}},
        {priority_handling, #{condition => "order_type == express", action => expedite}}
    ];
order_processing_rules(high) ->
    order_processing_rules(medium) ++ [
        {fraud_high_risk, #{condition => "fraud_score > 0.8", action => require_manual_review}},
        {volume_discount, #{condition => "order_items > 10", action => apply_volume_discount}}
    ].

document_workflow_rules(low) ->
    [
        {auto_approve, #{condition => "document_type == standard and risk_level == low", action => approve}},
        {mandatory_review, #{condition => "document_type == contract or document_type == legal", action => require_all_reviews}}
    ];
document_workflow_rules(medium) ->
    document_workflow_rules(low) ++ [
        {confidentiality_check, #{condition => "document_type == confidential", action => restrict_access}},
        {executive_override, #{condition => "risk_score > 0.8", action => require_executive_approval}}
    ];
document_workflow_rules(high) ->
    document_workflow_rules(medium) ++ [
        {international_approval, #{condition => "has_international_implications", action => require_global_approval}},
        {retention_policy, #{condition => "document_age > 7", action => archive}}
    ].

data_pipeline_rules(low) ->
    [
        {skip_small_batches, #{condition => "batch_size < 1000", action => bypass_validation}},
        {external_enrichment, #{condition => "enrichment_required == true", action => call_external_apis}}
    ];
data_pipeline_rules(medium) ->
    data_pipeline_rules(low) ++ [
        {real_time_processing, #{condition => "processing_mode == streaming", action => apply_real_time_rules}},
        {quality_gating, #{condition => "quality_score < 0.8", action => reject_low_quality}}
    ];
data_pipeline_rules(high) ->
    data_pipeline_rules(medium) ++ [
        {adaptive_processing, #{condition => "system_load > 0.8", action => implement_adaptive_processing}},
        {automated_optimization, #{condition => "continuous_improvement == true", action => optimize_pipeline}}
    ].

approval_chain_rules(_) ->
    [
        {auto_approve, #{condition => "amount < 100 and request_type == standard", action => approve}},
        {committee_review, #{condition => "amount > 100000 and request_type == strategic", action => require_committee}},
        {auto_reject, #{condition => "risk_score > 0.8", action => reject}}
    ].

notification_rules(_) ->
    [
        {critical_priority, #{condition => "event_priority == critical", action => immediate_delivery}},
        {batch_processing, #{condition => "notification_count > 1000", action => batch_processing}},
        {channel_fallback, #{condition => "primary_channel_failed", action => try_alternative_channel}}
    ].

financial_rules(_) ->
    [
        {standard_processing, #{condition => "amount < 10000 and risk_score < 0.5", action => auto_process}},
        {manual_review, #{condition => "amount > 50000 or risk_score > 0.7", action => require_manual_review}},
        {regulatory_check, #{condition => "is_regulated_entity", action => enhanced_compliance}}
    ].

supply_chain_rules(_) ->
    [
        {auto_fulfill, #{condition => "in_stock and quantity < reorder_threshold", action => immediate_ship}},
        {multi_source, #{condition => "quantity > single_source_capacity", action => split_across_suppliers}},
        {expedite, #{condition => "priority == urgent", action => expedite_shipping}}
    ].

customer_service_rules(_) ->
    [
        {auto_assign, #{condition => "ticket_type == general", action => assign_to_general_pool}},
        {escalate, #{condition => "priority == urgent or wait_time > 60", action => escalate_to_specialist}},
        {auto_close, #{condition => "resolution_confirmed and no_followup", action => close_ticket}}
    ].

hr_rules(_) ->
    [
        {auto_process, #{condition => "action_type == transfer and tenure > 90", action => auto_approve}},
        {executive_approval, #{condition => "salary_change > 20_percent", action => require_executive_approval}},
        {compliance_check, #{condition => "is_regulated_position", action => enhanced_compliance}}
    ].

security_rules(_) ->
    [
        {auto_pass, #{condition => "no_vulnerabilities and compliance_score > 0.95", action => mark_compliant}},
        {remediation_required, #{condition => "critical_vulnerabilities > 0", action => initiate_remediation}},
        {audit_trail, #{condition => "always", action => maintain_audit_trail}}
    ].

%%====================================================================
%% Success Criteria Generators
%%====================================================================

order_processing_success_criteria(low) ->
    #{max_duration => 30000, min_success_rate => 0.95};
order_processing_success_criteria(medium) ->
    #{max_duration => 45000, min_success_rate => 0.90};
order_processing_success_criteria(high) ->
    #{max_duration => 60000, min_success_rate => 0.92, fraud_detection_rate => 0.98}.

document_workflow_success_criteria(low) ->
    #{max_duration => 30000, min_success_rate => 0.90};
document_workflow_success_criteria(medium) ->
    #{max_duration => 45000, min_success_rate => 0.92};
document_workflow_success_criteria(high) ->
    #{max_duration => 60000, min_success_rate => 0.95, audit_completeness => 1.0}.

data_pipeline_success_criteria(low) ->
    #{max_duration => 120000, min_success_rate => 0.98};
data_pipeline_success_criteria(medium) ->
    #{max_duration => 180000, min_success_rate => 0.98, throughput => 50000};
data_pipeline_success_criteria(high) ->
    #{max_duration => 300000, min_success_rate => 0.99, throughput => 100000, latency => 1000}.

%% Default success criteria for remaining domains
approval_chain_success_criteria(_) -> #{max_duration => 75000, min_success_rate => 0.85}.
notification_success_criteria(_) -> #{max_duration => 30000, min_success_rate => 0.98, delivery_latency => 1000}.
financial_success_criteria(_) -> #{max_duration => 45000, min_success_rate => 0.99, compliance_rate => 1.0}.
supply_chain_success_criteria(_) -> #{max_duration => 120000, min_success_rate => 0.90}.
customer_service_success_criteria(_) -> #{max_duration => 28800000, min_success_rate => 0.85, response_time => 3600}.
hr_success_criteria(_) -> #{max_duration => 120000, min_success_rate => 0.90}.
security_success_criteria(_) -> #{max_duration => 604800000, min_success_rate => 0.95, coverage => 1.0}.

%%====================================================================
%% Error Scenario Generators
%%====================================================================

order_processing_errors(low) ->
    [
        {payment_failed, handle_retry, "Retry payment with alternative method"},
        {inventory_unavailable, backorder, "Create backorder and notify customer"}
    ];
order_processing_errors(medium) ->
    order_processing_errors(low) ++ [
        {fraud_detected, manual_review, "Escalate to fraud investigation team"},
        {price_changed, notify_customer, "Notify customer of price adjustment"}
    ];
order_processing_errors(high) ->
    order_processing_errors(medium) ++ [
        {inventory_corrupted, restore_from_backup, "Restore inventory from backup"},
        {system_overload, implement_throttling, "Throttle requests and prioritize"}
    ].

document_workflow_errors(low) ->
    [
        {reviewer_unavailable, assign_backup, "Assign backup reviewer"},
        {document_corrupted, restore_version, "Restore from backup version"}
    ];
document_workflow_errors(medium) ->
    document_workflow_errors(low) ++ [
        {conflict_detected, resolve_conflict, "Manual conflict resolution"},
        {signature_error, reprocess_signature, "Request re-signature"}
    ];
document_workflow_errors(high) ->
    document_workflow_errors(medium) ++ [
        {system_failure, manual_intervention, "Switch to manual processing"},
        {breach_detected, security_protocol, "Activate security protocols"}
    ].

data_pipeline_errors(low) ->
    [
        {data_corruption, restore_backup, "Restore from backup"},
        {service_unavailable, retry_fallback, "Retry with fallback service"}
    ];
data_pipeline_errors(medium) ->
    data_pipeline_errors(low) ++ [
        {schema_mismatch, apply_transformation, "Apply schema transformation"},
        {rate_limit_hit, implement_backoff, "Implement exponential backoff"}
    ];
data_pipeline_errors(high) ->
    data_pipeline_errors(medium) ++ [
        {network_partition, implement_tolerance, "Implement network partition tolerance"},
        {data_drift, adapt_schema, "Adapt to data drift"}
    ].

%% Default error scenarios for remaining domains
approval_chain_errors(_) -> [
    {approver_unavailable, escalate_to_next_level, "Escalate to next level"},
    {budget_exceeded, require_additional_approval, "Require additional approval"}
].
notification_errors(_) -> [
    {channel_unavailable, try_alternative_channel, "Try alternative channel"},
    {rate_limit_exceeded, implement_backoff_strategy, "Implement backoff strategy"}
].
financial_errors(_) -> [
    {transaction_failed, retry_with_backoff, "Retry with exponential backoff"},
    {compliance_failure, block_and_notify, "Block transaction and notify compliance"}
].
supply_chain_errors(_) -> [
    {supplier_unavailable, activate_alternative, "Activate alternative supplier"},
    {logistics_failure, reroute_shipment, "Reroute shipment"}
].
customer_service_errors(_) -> [
    {agent_unavailable, queue_ticket, "Queue ticket for next agent"},
    {system_unavailable, notify_delay, "Notify customer of delay"}
].
hr_errors(_) -> [
    {approval_timeout, escalate_manager, "Escalate to manager"},
    {system_sync_failure, manual_reconciliation, "Manual reconciliation required"}
].
security_errors(_) -> [
    {access_denied, log_and_alert, "Log access attempt and alert security"},
    {audit_failure, initiate_investigation, "Start investigation"}
].

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
generate_scenario_id(Domain) ->
    Timestamp = erlang:system_time(millisecond),
    UniqueId = erlang:unique_integer([positive]),
    DomainBin = atom_to_binary(Domain, utf8),
    <<DomainBin/binary, "_", (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(UniqueId))/binary>>.
