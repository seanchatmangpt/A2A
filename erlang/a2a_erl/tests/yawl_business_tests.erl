%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Business Domain Test Suite
%%%
%%% This module contains Common Test suites for testing business domain
%%% scenarios across all 10 supported domains with various complexity
%%% levels.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_business_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%% Export tests
-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases - Order Processing
-export([
    test_order_processing_low/1,
    test_order_processing_medium/1,
    test_order_processing_high/1
]).

%% Test cases - Document Workflow
-export([
    test_document_workflow_low/1,
    test_document_workflow_medium/1,
    test_document_workflow_high/1
]).

%% Test cases - Data Pipeline
-export([
    test_data_pipeline_low/1,
    test_data_pipeline_medium/1,
    test_data_pipeline_high/1
]).

%% Test cases - Approval Chain
-export([
    test_approval_chain_low/1,
    test_approval_chain_medium/1,
    test_approval_chain_high/1
]).

%% Test cases - Notification System
-export([
    test_notification_system_low/1,
    test_notification_system_medium/1,
    test_notification_system_high/1
]).

%% Test cases - Financial Workflow
-export([
    test_financial_workflow_low/1,
    test_financial_workflow_medium/1,
    test_financial_workflow_high/1
]).

%% Test cases - Supply Chain
-export([
    test_supply_chain_low/1,
    test_supply_chain_medium/1,
    test_supply_chain_high/1
]).

%% Test cases - Customer Service
-export([
    test_customer_service_low/1,
    test_customer_service_medium/1,
    test_customer_service_high/1
]).

%% Test cases - HR Workflow
-export([
    test_hr_workflow_low/1,
    test_hr_workflow_medium/1,
    test_hr_workflow_high/1
]).

%% Test cases - Security Audit
-export([
    test_security_audit_low/1,
    test_security_audit_medium/1,
    test_security_audit_high/1
]).

%% Test cases - Validation Tests
-export([
    test_business_domain_validation/1,
    test_scenario_execution/1,
    test_business_rules/1,
    test_resource_allocations/1,
    test_data_flows/1,
    test_success_criteria/1,
    test_error_scenarios/1
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        %% Order Processing Tests
        test_order_processing_low,
        test_order_processing_medium,
        test_order_processing_high,
        %% Document Workflow Tests
        test_document_workflow_low,
        test_document_workflow_medium,
        test_document_workflow_high,
        %% Data Pipeline Tests
        test_data_pipeline_low,
        test_data_pipeline_medium,
        test_data_pipeline_high,
        %% Approval Chain Tests
        test_approval_chain_low,
        test_approval_chain_medium,
        test_approval_chain_high,
        %% Notification System Tests
        test_notification_system_low,
        test_notification_system_medium,
        test_notification_system_high,
        %% Financial Workflow Tests
        test_financial_workflow_low,
        test_financial_workflow_medium,
        test_financial_workflow_high,
        %% Supply Chain Tests
        test_supply_chain_low,
        test_supply_chain_medium,
        test_supply_chain_high,
        %% Customer Service Tests
        test_customer_service_low,
        test_customer_service_medium,
        test_customer_service_high,
        %% HR Workflow Tests
        test_hr_workflow_low,
        test_hr_workflow_medium,
        test_hr_workflow_high,
        %% Security Audit Tests
        test_security_audit_low,
        test_security_audit_medium,
        test_security_audit_high,
        %% Validation Tests
        test_business_domain_validation,
        test_scenario_execution,
        test_business_rules,
        test_resource_allocations,
        test_data_flows,
        test_success_criteria,
        test_error_scenarios
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {order_processing_tests, [sequence], [
            test_order_processing_low,
            test_order_processing_medium,
            test_order_processing_high
        ]},
        {document_workflow_tests, [sequence], [
            test_document_workflow_low,
            test_document_workflow_medium,
            test_document_workflow_high
        ]},
        {data_pipeline_tests, [sequence], [
            test_data_pipeline_low,
            test_data_pipeline_medium,
            test_data_pipeline_high
        ]},
        {approval_chain_tests, [sequence], [
            test_approval_chain_low,
            test_approval_chain_medium,
            test_approval_chain_high
        ]},
        {notification_tests, [sequence], [
            test_notification_system_low,
            test_notification_system_medium,
            test_notification_system_high
        ]},
        {financial_tests, [sequence], [
            test_financial_workflow_low,
            test_financial_workflow_medium,
            test_financial_workflow_high
        ]},
        {supply_chain_tests, [sequence], [
            test_supply_chain_low,
            test_supply_chain_medium,
            test_supply_chain_high
        ]},
        {customer_service_tests, [sequence], [
            test_customer_service_low,
            test_customer_service_medium,
            test_customer_service_high
        ]},
        {hr_tests, [sequence], [
            test_hr_workflow_low,
            test_hr_workflow_medium,
            test_hr_workflow_high
        ]},
        {security_tests, [sequence], [
            test_security_audit_low,
            test_security_audit_medium,
            test_security_audit_high
        ]},
        {validation_tests, [sequence], [
            test_business_domain_validation,
            test_scenario_execution,
            test_business_rules,
            test_resource_allocations,
            test_data_flows,
            test_success_criteria,
            test_error_scenarios
        ]}
    ].

%% @doc Initialize test suite.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("Starting YAWL Business Domain Test Suite"),
    ct:pal("Testing 10 domains x 3 complexity levels = 30 domain tests"),
    {ok, _} = application:ensure_all_started(a2a_erl),
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
    [{orchestrator_pid, OrchestratorPid} | Config].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    OrchestratorPid = proplists:get_value(orchestrator_pid, Config),
    gen_server:stop(OrchestratorPid),
    application:stop(a2a_erl),
    ct:pal("Completed YAWL Business Domain Test Suite"),
    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    Config.

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, _Config) ->
    ct:pal("Completed group: ~p", [GroupName]),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting test: ~p", [TestName]),
    Config.

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, _Config) ->
    ct:pal("Completed test: ~p", [TestName]),
    ok.

%%====================================================================
%% Order Processing Tests
%%====================================================================

%% @doc Test order processing scenario with low complexity.
-spec test_order_processing_low(Config) -> ok when Config :: [tuple()].
test_order_processing_low(_Config) ->
    Scenario = yawl_business_scenarios:order_processing_scenario(low),
    verify_scenario(Scenario, order_processing, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "e-commerce"),
    ct:pal("Order Processing (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test order processing scenario with medium complexity.
-spec test_order_processing_medium(Config) -> ok when Config :: [tuple()].
test_order_processing_medium(_Config) ->
    Scenario = yawl_business_scenarios:order_processing_scenario(medium),
    verify_scenario(Scenario, order_processing, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 6),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Order Processing (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test order processing scenario with high complexity.
-spec test_order_processing_high(Config) -> ok when Config :: [tuple()].
test_order_processing_high(_Config) ->
    Scenario = yawl_business_scenarios:order_processing_scenario(high),
    verify_scenario(Scenario, order_processing, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 6),
    verify_success_criteria(Scenario#yawl_scenario.success_criteria, [fraud_detection_rate]),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Order Processing (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Document Workflow Tests
%%====================================================================

%% @doc Test document workflow scenario with low complexity.
-spec test_document_workflow_low(Config) -> ok when Config :: [tuple()].
test_document_workflow_low(_Config) ->
    Scenario = yawl_business_scenarios:document_workflow_scenario(low),
    verify_scenario(Scenario, document_workflow, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "finance"),
    ct:pal("Document Workflow (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test document workflow scenario with medium complexity.
-spec test_document_workflow_medium(Config) -> ok when Config :: [tuple()].
test_document_workflow_medium(_Config) ->
    Scenario = yawl_business_scenarios:document_workflow_scenario(medium),
    verify_scenario(Scenario, document_workflow, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Document Workflow (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test document workflow scenario with high complexity.
-spec test_document_workflow_high(Config) -> ok when Config :: [tuple()].
test_document_workflow_high(_Config) ->
    Scenario = yawl_business_scenarios:document_workflow_scenario(high),
    verify_scenario(Scenario, document_workflow, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 7),
    verify_success_criteria(Scenario#yawl_scenario.success_criteria, [audit_completeness]),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Document Workflow (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Data Pipeline Tests
%%====================================================================

%% @doc Test data pipeline scenario with low complexity.
-spec test_data_pipeline_low(Config) -> ok when Config :: [tuple()].
test_data_pipeline_low(_Config) ->
    Scenario = yawl_business_scenarios:data_pipeline_scenario(low),
    verify_scenario(Scenario, data_pipeline, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "technology"),
    ct:pal("Data Pipeline (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test data pipeline scenario with medium complexity.
-spec test_data_pipeline_medium(Config) -> ok when Config :: [tuple()].
test_data_pipeline_medium(_Config) ->
    Scenario = yawl_business_scenarios:data_pipeline_scenario(medium),
    verify_scenario(Scenario, data_pipeline, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Data Pipeline (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test data pipeline scenario with high complexity.
-spec test_data_pipeline_high(Config) -> ok when Config :: [tuple()].
test_data_pipeline_high(_Config) ->
    Scenario = yawl_business_scenarios:data_pipeline_scenario(high),
    verify_scenario(Scenario, data_pipeline, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 6),
    verify_success_criteria(Scenario#yawl_scenario.success_criteria, [throughput, latency]),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Data Pipeline (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Approval Chain Tests
%%====================================================================

%% @doc Test approval chain scenario with low complexity.
-spec test_approval_chain_low(Config) -> ok when Config :: [tuple()].
test_approval_chain_low(_Config) ->
    Scenario = yawl_business_scenarios:approval_chain_scenario(low),
    verify_scenario(Scenario, approval_chain, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "manufacturing"),
    ct:pal("Approval Chain (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test approval chain scenario with medium complexity.
-spec test_approval_chain_medium(Config) -> ok when Config :: [tuple()].
test_approval_chain_medium(_Config) ->
    Scenario = yawl_business_scenarios:approval_chain_scenario(medium),
    verify_scenario(Scenario, approval_chain, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Approval Chain (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test approval chain scenario with high complexity.
-spec test_approval_chain_high(Config) -> ok when Config :: [tuple()].
test_approval_chain_high(_Config) ->
    Scenario = yawl_business_scenarios:approval_chain_scenario(high),
    verify_scenario(Scenario, approval_chain, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 6),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Approval Chain (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Notification System Tests
%%====================================================================

%% @doc Test notification system scenario with low complexity.
-spec test_notification_system_low(Config) -> ok when Config :: [tuple()].
test_notification_system_low(_Config) ->
    Scenario = yawl_business_scenarios:notification_scenario(low),
    verify_scenario(Scenario, notification_system, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "communications"),
    ct:pal("Notification System (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test notification system scenario with medium complexity.
-spec test_notification_system_medium(Config) -> ok when Config :: [tuple()].
test_notification_system_medium(_Config) ->
    Scenario = yawl_business_scenarios:notification_scenario(medium),
    verify_scenario(Scenario, notification_system, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Notification System (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test notification system scenario with high complexity.
-spec test_notification_system_high(Config) -> ok when Config :: [tuple()].
test_notification_system_high(_Config) ->
    Scenario = yawl_business_scenarios:notification_scenario(high),
    verify_scenario(Scenario, notification_system, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Notification System (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Financial Workflow Tests
%%====================================================================

%% @doc Test financial workflow scenario with low complexity.
-spec test_financial_workflow_low(Config) -> ok when Config :: [tuple()].
test_financial_workflow_low(_Config) ->
    Scenario = yawl_business_scenarios:financial_workflow_scenario(low),
    verify_scenario(Scenario, financial_workflow, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "finance"),
    ct:pal("Financial Workflow (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test financial workflow scenario with medium complexity.
-spec test_financial_workflow_medium(Config) -> ok when Config :: [tuple()].
test_financial_workflow_medium(_Config) ->
    Scenario = yawl_business_scenarios:financial_workflow_scenario(medium),
    verify_scenario(Scenario, financial_workflow, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Financial Workflow (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test financial workflow scenario with high complexity.
-spec test_financial_workflow_high(Config) -> ok when Config :: [tuple()].
test_financial_workflow_high(_Config) ->
    Scenario = yawl_business_scenarios:financial_workflow_scenario(high),
    verify_scenario(Scenario, financial_workflow, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Financial Workflow (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Supply Chain Tests
%%====================================================================

%% @doc Test supply chain scenario with low complexity.
-spec test_supply_chain_low(Config) -> ok when Config :: [tuple()].
test_supply_chain_low(_Config) ->
    Scenario = yawl_business_scenarios:supply_chain_scenario(low),
    verify_scenario(Scenario, supply_chain, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "logistics"),
    ct:pal("Supply Chain (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test supply chain scenario with medium complexity.
-spec test_supply_chain_medium(Config) -> ok when Config :: [tuple()].
test_supply_chain_medium(_Config) ->
    Scenario = yawl_business_scenarios:supply_chain_scenario(medium),
    verify_scenario(Scenario, supply_chain, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Supply Chain (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test supply chain scenario with high complexity.
-spec test_supply_chain_high(Config) -> ok when Config :: [tuple()].
test_supply_chain_high(_Config) ->
    Scenario = yawl_business_scenarios:supply_chain_scenario(high),
    verify_scenario(Scenario, supply_chain, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 6),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Supply Chain (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Customer Service Tests
%%====================================================================

%% @doc Test customer service scenario with low complexity.
-spec test_customer_service_low(Config) -> ok when Config :: [tuple()].
test_customer_service_low(_Config) ->
    Scenario = yawl_business_scenarios:customer_service_scenario(low),
    verify_scenario(Scenario, customer_service, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "services"),
    ct:pal("Customer Service (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test customer service scenario with medium complexity.
-spec test_customer_service_medium(Config) -> ok when Config :: [tuple()].
test_customer_service_medium(_Config) ->
    Scenario = yawl_business_scenarios:customer_service_scenario(medium),
    verify_scenario(Scenario, customer_service, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Customer Service (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test customer service scenario with high complexity.
-spec test_customer_service_high(Config) -> ok when Config :: [tuple()].
test_customer_service_high(_Config) ->
    Scenario = yawl_business_scenarios:customer_service_scenario(high),
    verify_scenario(Scenario, customer_service, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Customer Service (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% HR Workflow Tests
%%====================================================================

%% @doc Test HR workflow scenario with low complexity.
-spec test_hr_workflow_low(Config) -> ok when Config :: [tuple()].
test_hr_workflow_low(_Config) ->
    Scenario = yawl_business_scenarios:hr_workflow_scenario(low),
    verify_scenario(Scenario, hr_workflow, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "hr"),
    ct:pal("HR Workflow (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test HR workflow scenario with medium complexity.
-spec test_hr_workflow_medium(Config) -> ok when Config :: [tuple()].
test_hr_workflow_medium(_Config) ->
    Scenario = yawl_business_scenarios:hr_workflow_scenario(medium),
    verify_scenario(Scenario, hr_workflow, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("HR Workflow (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test HR workflow scenario with high complexity.
-spec test_hr_workflow_high(Config) -> ok when Config :: [tuple()].
test_hr_workflow_high(_Config) ->
    Scenario = yawl_business_scenarios:hr_workflow_scenario(high),
    verify_scenario(Scenario, hr_workflow, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("HR Workflow (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Security Audit Tests
%%====================================================================

%% @doc Test security audit scenario with low complexity.
-spec test_security_audit_low(Config) -> ok when Config :: [tuple()].
test_security_audit_low(_Config) ->
    Scenario = yawl_business_scenarios:security_audit_scenario(low),
    verify_scenario(Scenario, security_audit, low),
    verify_pattern_combination(Scenario#yawl_scenario.pattern_combination),
    verify_metadata_industry(Scenario, "security"),
    ct:pal("Security Audit (low): ~p patterns", [length(Scenario#yawl_scenario.pattern_combination)]),
    ok.

%% @doc Test security audit scenario with medium complexity.
-spec test_security_audit_medium(Config) -> ok when Config :: [tuple()].
test_security_audit_medium(_Config) ->
    Scenario = yawl_business_scenarios:security_audit_scenario(medium),
    verify_scenario(Scenario, security_audit, medium),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 4),
    verify_business_rules_structure(Scenario#yawl_scenario.business_rules),
    ct:pal("Security Audit (medium): ~p patterns, ~p rules",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.business_rules)]),
    ok.

%% @doc Test security audit scenario with high complexity.
-spec test_security_audit_high(Config) -> ok when Config :: [tuple()].
test_security_audit_high(_Config) ->
    Scenario = yawl_business_scenarios:security_audit_scenario(high),
    verify_scenario(Scenario, security_audit, high),
    ?assert(length(Scenario#yawl_scenario.pattern_combination) >= 5),
    verify_error_scenarios(Scenario#yawl_scenario.error_scenarios),
    ct:pal("Security Audit (high): ~p patterns, ~p errors",
        [length(Scenario#yawl_scenario.pattern_combination),
         length(Scenario#yawl_scenario.error_scenarios)]),
    ok.

%%====================================================================
%% Validation Tests
%%====================================================================

%% @doc Test business domain validation.
-spec test_business_domain_validation(Config) -> ok when Config :: [tuple()].
test_business_domain_validation(_Config) ->
    %% Test all valid domains
    ValidDomains = yawl_business_scenarios:list_domains(),
    ?assertEqual(10, length(ValidDomains)),
    lists:foreach(fun(Domain) ->
        ?assert(yawl_business_scenarios:validate_domain(Domain))
    end, ValidDomains),
    %% Test all expected domains are present
    ExpectedDomains = ?BUSINESS_DOMAINS,
    lists:foreach(fun(Domain) ->
        ?assert(lists:member(Domain, ValidDomains))
    end, ExpectedDomains),
    %% Test invalid domain
    ?assertNot(yawl_business_scenarios:validate_domain(invalid_domain)),
    ct:pal("All 10 business domains validated successfully"),
    ok.

%% @doc Test scenario execution.
-spec test_scenario_execution(Config) -> ok when Config :: [tuple()].
test_scenario_execution(_Config) ->
    %% Test executing a simple business scenario
    Scenario = yawl_business_scenarios:order_processing_scenario(low),
    PatternCombination = Scenario#yawl_scenario.pattern_combination,
    %% Execute each pattern in the combination
    Results = lists:map(fun({Pattern, Config}) ->
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(Pattern, Config),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
        {Pattern, maps:get(status, Result)}
    end, PatternCombination),
    %% Verify all patterns executed successfully
    ?assert(lists:all(fun({_, Status}) -> Status =:= completed end, Results)),
    ct:pal("Scenario execution results: ~p", [Results]),
    ok.

%% @doc Test business rules validation.
-spec test_business_rules(Config) -> ok when Config :: [tuple()].
test_business_rules(_Config) ->
    %% Test business rules for multiple domains
    TestScenarios = [
        {order_processing, medium},
        {document_workflow, medium},
        {financial_workflow, medium}
    ],
    lists:foreach(fun({Domain, Complexity}) ->
        Scenario = get_scenario(Domain, Complexity),
        Rules = Scenario#yawl_scenario.business_rules,
        ?assert(length(Rules) > 0),
        %% Verify rule structure
        lists:foreach(fun({RuleName, RuleData}) ->
            ?assert(is_atom(RuleName)),
            ?assert(is_map(RuleData)),
            ?assert(maps:is_key(condition, RuleData)),
            ?assert(maps:is_key(action, RuleData)),
            %% Verify condition is a string or binary
            Condition = maps:get(condition, RuleData),
            ?assert(is_list(Condition) orelse is_binary(Condition)),
            %% Verify action is an atom
            Action = maps:get(action, RuleData),
            ?assert(is_atom(Action))
        end, Rules),
        ct:pal("~p: ~p rules validated", [Domain, length(Rules)])
    end, TestScenarios),
    ok.

%% @doc Test resource allocations validation.
-spec test_resource_allocations(Config) -> ok when Config :: [tuple()].
test_resource_allocations(_Config) ->
    %% Test resource allocations for multiple domains
    TestScenarios = [
        {order_processing, low, fun verify_order_processing_resources/1},
        {data_pipeline, medium, fun verify_data_pipeline_resources/1},
        {financial_workflow, high, fun verify_financial_resources/1}
    ],
    lists:foreach(fun({Domain, Complexity, VerifyFun}) ->
        Scenario = get_scenario(Domain, Complexity),
        Resources = Scenario#yawl_scenario.resource_allocations,
        ?assert(is_map(Resources)),
        ?assert(map_size(Resources) > 0),
        %% Verify resource structure
        maps:foreach(fun(Task, ResourceList) ->
            ?assert(is_list(Task) orelse is_binary(Task)),
            ?assert(is_list(ResourceList)),
            ?assert(length(ResourceList) > 0),
            %% Verify each resource is a string/binary
            lists:foreach(fun(Resource) ->
                ?assert(is_list(Resource) orelse is_binary(Resource))
            end, ResourceList)
        end, Resources),
        %% Run domain-specific verification
        VerifyFun(Resources),
        ct:pal("~p: ~p tasks with resources allocated", [Domain, map_size(Resources)])
    end, TestScenarios),
    ok.

%% @doc Test data flows validation.
-spec test_data_flows(Config) -> ok when Config :: [tuple()].
test_data_flows(_Config) ->
    %% Test data flows for multiple domains
    TestScenarios = [
        {order_processing, low},
        {document_workflow, medium},
        {approval_chain, high}
    ],
    lists:foreach(fun({Domain, Complexity}) ->
        Scenario = get_scenario(Domain, Complexity),
        DataFlows = Scenario#yawl_scenario.data_flows,
        ?assert(is_map(DataFlows)),
        ?assert(map_size(DataFlows) > 0),
        %% Verify data flow structure
        maps:foreach(fun(DataName, TaskList) ->
            ?assert(is_list(DataName) orelse is_binary(DataName)),
            ?assert(is_list(TaskList)),
            ?assert(length(TaskList) > 0),
            %% Verify each task is a string/binary
            lists:foreach(fun(Task) ->
                ?assert(is_list(Task) orelse is_binary(Task))
            end, TaskList)
        end, DataFlows),
        ct:pal("~p: ~p data flows validated", [Domain, map_size(DataFlows)])
    end, TestScenarios),
    ok.

%% @doc Test success criteria validation.
-spec test_success_criteria(Config) -> ok when Config :: [tuple()].
test_success_criteria(_Config) ->
    %% Test success criteria across all complexity levels
    TestCases = [
        {order_processing, low, #{max_duration => 30000, min_success_rate => 0.95}},
        {data_pipeline, high, #{max_duration => 300000, min_success_rate => 0.99, throughput => 100000}},
        {financial_workflow, medium, #{max_duration => 45000, min_success_rate => 0.99}}
    ],
    lists:foreach(fun({Domain, Complexity, ExpectedKeys}) ->
        Scenario = get_scenario(Domain, Complexity),
        Criteria = Scenario#yawl_scenario.success_criteria,
        ?assert(is_map(Criteria)),
        ?assert(map_size(Criteria) > 0),
        %% Verify expected keys are present
        maps:foreach(fun(Key, Value) ->
            ?assert(maps:is_key(Key, Criteria)),
            %% Verify value types
            case Key of
                max_duration -> ?assert(is_integer(Value));
                min_success_rate -> ?assert(is_float(Value));
                throughput -> ?assert(is_integer(Value));
                latency -> ?assert(is_integer(Value));
                compliance_rate -> ?assert(is_float(Value));
                coverage -> ?assert(is_float(Value));
                response_time -> ?assert(is_integer(Value));
                _ -> ok
            end
        end, ExpectedKeys),
        ct:pal("~p (~p): success criteria validated", [Domain, Complexity])
    end, TestCases),
    ok.

%% @doc Test error scenarios validation.
-spec test_error_scenarios(Config) -> ok when Config :: [tuple()].
test_error_scenarios(_Config) ->
    %% Test error scenarios for multiple domains
    TestScenarios = [
        {order_processing, high},
        {document_workflow, high},
        {data_pipeline, high}
    ],
    lists:foreach(fun({Domain, Complexity}) ->
        Scenario = get_scenario(Domain, Complexity),
        Errors = Scenario#yawl_scenario.error_scenarios,
        ?assert(is_list(Errors)),
        ?assert(length(Errors) > 0),
        %% Verify error scenario structure
        lists:foreach(fun({ErrorName, Handler, Description}) ->
            ?assert(is_atom(ErrorName)),
            ?assert(is_atom(Handler)),
            ?assert(is_list(Description) orelse is_binary(Description))
        end, Errors),
        ct:pal("~p: ~p error scenarios validated", [Domain, length(Errors)])
    end, TestScenarios),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Get scenario for domain and complexity.
get_scenario(order_processing, Complexity) ->
    yawl_business_scenarios:order_processing_scenario(Complexity);
get_scenario(document_workflow, Complexity) ->
    yawl_business_scenarios:document_workflow_scenario(Complexity);
get_scenario(data_pipeline, Complexity) ->
    yawl_business_scenarios:data_pipeline_scenario(Complexity);
get_scenario(approval_chain, Complexity) ->
    yawl_business_scenarios:approval_chain_scenario(Complexity);
get_scenario(notification_system, Complexity) ->
    yawl_business_scenarios:notification_scenario(Complexity);
get_scenario(financial_workflow, Complexity) ->
    yawl_business_scenarios:financial_workflow_scenario(Complexity);
get_scenario(supply_chain, Complexity) ->
    yawl_business_scenarios:supply_chain_scenario(Complexity);
get_scenario(customer_service, Complexity) ->
    yawl_business_scenarios:customer_service_scenario(Complexity);
get_scenario(hr_workflow, Complexity) ->
    yawl_business_scenarios:hr_workflow_scenario(Complexity);
get_scenario(security_audit, Complexity) ->
    yawl_business_scenarios:security_audit_scenario(Complexity).

%% @private
%% @doc Verify scenario structure.
verify_scenario(Scenario, ExpectedDomain, ExpectedComplexity) ->
    ?assertEqual(ExpectedDomain, Scenario#yawl_scenario.business_domain),
    ?assertEqual(ExpectedComplexity, Scenario#yawl_scenario.complexity),
    ?assert(is_list(Scenario#yawl_scenario.pattern_combination)),
    ?assert(is_map(Scenario#yawl_scenario.resource_allocations)),
    ?assert(is_map(Scenario#yawl_scenario.data_flows)),
    ?assert(is_list(Scenario#yawl_scenario.business_rules)),
    ?assert(is_map(Scenario#yawl_scenario.success_criteria)),
    ?assert(is_list(Scenario#yawl_scenario.error_scenarios)),
    ?assert(is_map(Scenario#yawl_scenario.metadata)),
    ?assert(is_list(Scenario#yawl_scenario.name)),
    ?assert(is_list(Scenario#yawl_scenario.description)).

%% @private
%% @doc Verify pattern combination structure.
verify_pattern_combination(PatternCombination) ->
    ?assert(length(PatternCombination) > 0),
    lists:foreach(fun({Pattern, Config}) ->
        ?assert(is_atom(Pattern)),
        ?assert(is_map(Config)),
        ?assert(lists:member(Pattern, ?YAWL_PATTERNS))
    end, PatternCombination).

%% @private
%% @doc Verify business rules structure.
verify_business_rules_structure(Rules) ->
    ?assert(is_list(Rules)),
    ?assert(length(Rules) > 0),
    lists:foreach(fun({RuleName, RuleData}) ->
        ?assert(is_atom(RuleName)),
        ?assert(is_map(RuleData)),
        ?assert(maps:is_key(condition, RuleData)),
        ?assert(maps:is_key(action, RuleData))
    end, Rules).

%% @private
%% @doc Verify success criteria contains expected keys.
verify_success_criteria(Criteria, ExpectedKeys) ->
    lists:foreach(fun(Key) ->
        ?assert(maps:is_key(Key, Criteria),
            io_lib:format("Missing expected key: ~p in ~p", [Key, Criteria]))
    end, ExpectedKeys).

%% @private
%% @doc Verify error scenarios structure.
verify_error_scenarios(Errors) ->
    ?assert(is_list(Errors)),
    ?assert(length(Errors) > 0),
    lists:foreach(fun({ErrorName, Handler, Description}) ->
        ?assert(is_atom(ErrorName)),
        ?assert(is_atom(Handler)),
        ?assert(is_list(Description) orelse is_binary(Description))
    end, Errors).

%% @private
%% @doc Verify metadata contains expected industry.
verify_metadata_industry(Scenario, ExpectedIndustry) ->
    Metadata = Scenario#yawl_scenario.metadata,
    ?assert(maps:is_key(industry, Metadata)),
    ?assertEqual(ExpectedIndustry, maps:get(industry, Metadata)).

%% @private
%% @doc Verify order processing specific resources.
verify_order_processing_resources(Resources) ->
    ExpectedTasks = ["validate_order", "process_payment", "check_inventory", "ship_order"],
    lists:foreach(fun(Task) ->
        ?assert(maps:is_key(Task, Resources),
            io_lib:format("Missing task: ~p in resources", [Task]))
    end, ExpectedTasks).

%% @private
%% @doc Verify data pipeline specific resources.
verify_data_pipeline_resources(Resources) ->
    ExpectedTasks = ["extract_data", "validate_data", "transform_data", "store_data"],
    lists:foreach(fun(Task) ->
        ?assert(maps:is_key(Task, Resources),
            io_lib:format("Missing task: ~p in resources", [Task]))
    end, ExpectedTasks).

%% @private
%% @doc Verify financial workflow specific resources.
verify_financial_resources(Resources) ->
    ExpectedTasks = ["initiate_transaction", "fraud_check", "execute_transfer"],
    lists:foreach(fun(Task) ->
        ?assert(maps:is_key(Task, Resources),
            io_lib:format("Missing task: ~p in resources", [Task]))
    end, ExpectedTasks).
