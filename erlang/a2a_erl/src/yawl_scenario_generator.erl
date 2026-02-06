%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Scenario Generator (Demo Version)
%%%
%%% Minimal working version for Y Combinator Demo.
%%%
%%% ## Error Handling Features
%%%
%%% - Input validation for all parameters
%%% - Pattern validity checking
%%% - Graceful degradation for invalid inputs
%%% - Dependency checking
%%% - Error logging integration
%%%
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
    validate_scenario/1,
    validate_business_domain/1,
    validate_complexity/1,
    check_dependencies/0,
    log_error/2
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
    try
        %% Validate all inputs
        case validate_business_domain(BusinessDomain) of
            {error, Reason} ->
                log_error("generate_scenario", {invalid_domain, Reason}, #{domain => BusinessDomain}),
                {error, {invalid_domain, Reason}};
            ok ->
                case validate_complexity(Complexity) of
                    {error, Reason} ->
                        log_error("generate_scenario", {invalid_complexity, Reason}, #{complexity => Complexity}),
                        {error, {invalid_complexity, Reason}};
                    ok ->
                        case validate_config(Config) of
                            {error, Reason} ->
                                log_error("generate_scenario", {invalid_config, Reason}, #{config => Config}),
                                {error, {invalid_config, Reason}};
                            ok ->
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
                                        generate_security_audit(Complexity, Config);
                                    _InvalidDomain ->
                                        log_error("generate_scenario", unknown_domain, #{domain => BusinessDomain}),
                                        {error, unknown_domain}
                                end,
                                case Scenario of
                                    {error, _} = Error -> Error;
                                    _ ->
                                        case validate_scenario(Scenario) of
                                            true -> Scenario;
                                            false ->
                                                log_error("generate_scenario", invalid_scenario_result, #{scenario => Scenario}),
                                                {error, invalid_scenario_result}
                                        end
                                end
                        end
                end
        end
    catch
        Class:Error:Stacktrace ->
            log_error("generate_scenario", {Class, Error}, #{stacktrace => Stacktrace}),
            {error, {generation_exception, Error}}
    end.

generate_business_scenario(BusinessDomain, Complexity) ->
    generate_scenario(BusinessDomain, Complexity, #{}).

generate_edge_case_scenario(BusinessDomain, Complexity) ->
    try
        case generate_scenario(BusinessDomain, Complexity, #{}) of
            {error, _} = Error -> Error;
            BaseScenario when is_map(BaseScenario) ->
                BaseScenario#{
                    type => edge_case,
                    description => "Edge case scenario with unusual conditions",
                    edge_cases => generate_edge_cases(Complexity)
                }
        end
    catch
        _:Error:Stacktrace ->
            log_error("generate_edge_case_scenario", Error, #{stacktrace => Stacktrace}),
            {error, {edge_case_exception, Error}}
    end.

generate_performance_scenario(BusinessDomain, Complexity) ->
    try
        case generate_scenario(BusinessDomain, Complexity, #{}) of
            {error, _} = Error -> Error;
            BaseScenario when is_map(BaseScenario) ->
                BaseScenario#{
                    type => performance,
                    description => "Performance testing scenario",
                    load_profile => generate_load_profile(Complexity)
                }
        end
    catch
        _:Error:Stacktrace ->
            log_error("generate_performance_scenario", Error, #{stacktrace => Stacktrace}),
            {error, {performance_exception, Error}}
    end.

generate_error_scenario(BusinessDomain, Complexity) ->
    try
        case generate_scenario(BusinessDomain, Complexity, #{}) of
            {error, _} = Error -> Error;
            BaseScenario when is_map(BaseScenario) ->
                BaseScenario#{
                    type => error,
                    description => "Error condition scenario",
                    failure_injections => generate_failure_injections(),
                    recovery_strategies => generate_recovery_strategies()
                }
        end
    catch
        _:Error:Stacktrace ->
            log_error("generate_error_scenario", Error, #{stacktrace => Stacktrace}),
            {error, {error_scenario_exception, Error}}
    end.

generate_custom_scenario(BusinessDomain, Complexity, CustomConfig) ->
    try
        case generate_scenario(BusinessDomain, Complexity, CustomConfig) of
            {error, _} = Error -> Error;
            BaseScenario when is_map(BaseScenario) ->
                maps:merge(BaseScenario, CustomConfig)
        end
    catch
        _:Error:Stacktrace ->
            log_error("generate_custom_scenario", Error, #{stacktrace => Stacktrace}),
            {error, {custom_scenario_exception, Error}}
    end.

list_available_domains() ->
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
    maps:get(complexity, Scenario).

validate_scenario(Scenario) ->
    RequiredKeys = [scenario_id, name, business_domain, complexity, pattern_combination],
    lists:all(fun(K) -> maps:is_key(K, Scenario) end, RequiredKeys).

%%====================================================================
%% Internal Domain Generators
%%====================================================================

generate_order_processing(Complexity, _Config) ->
    #{
        scenario_id => <<"order_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Order Processing Workflow",
        description => "End-to-end order processing with payment and shipping",
        business_domain => order_processing,
        complexity => Complexity,
        pattern_combination => generate_order_patterns(Complexity),
        resource_allocations => generate_order_resources(Complexity),
        data_flows => generate_order_data_flows(Complexity),
        business_rules => generate_order_business_rules(Complexity),
        success_criteria => generate_order_success_criteria(Complexity),
        error_scenarios => generate_order_error_scenarios(Complexity),
        metadata => #{
            industry => "retail",
            transaction_volume => get_volume(Complexity),
            avg_duration => get_duration(Complexity)
        }
    }.

generate_document_workflow(Complexity, _Config) ->
    #{
        scenario_id => <<"doc_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Document Approval Workflow",
        description => "Multi-level document review and approval",
        business_domain => document_workflow,
        complexity => Complexity,
        pattern_combination => generate_document_patterns(Complexity),
        resource_allocations => generate_document_resources(Complexity),
        data_flows => generate_document_data_flows(Complexity),
        business_rules => [],
        success_criteria => generate_document_success_criteria(Complexity),
        error_scenarios => [],
        metadata => #{}
    }.

generate_data_pipeline(Complexity, _Config) ->
    #{
        scenario_id => <<"pipeline_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Data Processing Pipeline",
        description => "ETL pipeline with validation and transformation",
        business_domain => data_pipeline,
        complexity => Complexity,
        pattern_combination => generate_pipeline_patterns(Complexity),
        resource_allocations => generate_pipeline_resources(Complexity),
        data_flows => generate_pipeline_data_flows(Complexity),
        business_rules => [],
        success_criteria => generate_pipeline_success_criteria(Complexity),
        error_scenarios => [],
        metadata => #{}
    }.

generate_approval_chain(Complexity, _Config) ->
    #{
        scenario_id => <<"approval_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Approval Chain Workflow",
        description => "Multi-level approval with conditional routing",
        business_domain => approval_chain,
        complexity => Complexity,
        pattern_combination => generate_approval_patterns(Complexity),
        resource_allocations => generate_approval_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_notification_system(Complexity, _Config) ->
    #{
        scenario_id => <<"notify_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Notification System",
        description => "Multi-channel notification delivery",
        business_domain => notification_system,
        complexity => Complexity,
        pattern_combination => generate_notification_patterns(Complexity),
        resource_allocations => generate_notification_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_financial_workflow(Complexity, _Config) ->
    #{
        scenario_id => <<"finance_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Financial Transaction Workflow",
        description => "Financial processing with compliance checks",
        business_domain => financial_workflow,
        complexity => Complexity,
        pattern_combination => generate_financial_patterns(Complexity),
        resource_allocations => generate_financial_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_supply_chain(Complexity, _Config) ->
    #{
        scenario_id => <<"supply_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Supply Chain Workflow",
        description => "Supply chain management and tracking",
        business_domain => supply_chain,
        complexity => Complexity,
        pattern_combination => generate_supply_chain_patterns(Complexity),
        resource_allocations => generate_supply_chain_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_customer_service(Complexity, _Config) ->
    #{
        scenario_id => <<"support_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Customer Service Workflow",
        description => "Ticket resolution and customer support",
        business_domain => customer_service,
        complexity => Complexity,
        pattern_combination => generate_customer_service_patterns(Complexity),
        resource_allocations => generate_customer_service_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_hr_workflow(Complexity, _Config) ->
    #{
        scenario_id => <<"hr_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "HR Workflow",
        description => "Human resources processes",
        business_domain => hr_workflow,
        complexity => Complexity,
        pattern_combination => generate_hr_patterns(Complexity),
        resource_allocations => generate_hr_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

generate_security_audit(Complexity, _Config) ->
    #{
        scenario_id => <<"audit_", (integer_to_binary(rand:uniform(1000000)))/binary>>,
        name => "Security Audit Workflow",
        description => "Security audit and compliance",
        business_domain => security_audit,
        complexity => Complexity,
        pattern_combination => generate_security_patterns(Complexity),
        resource_allocations => generate_security_resources(Complexity),
        data_flows => #{},
        business_rules => [],
        success_criteria => #{},
        error_scenarios => [],
        metadata => #{}
    }.

%%====================================================================
%% Pattern Generators
%%====================================================================

generate_order_patterns(low) ->
    [{basic_sequential, #{}}, {parallel_split, #{branches => 2}}];
generate_order_patterns(medium) ->
    [{basic_sequential, #{}}, {parallel_split, #{branches => 3}},
     {exclusive_choice, #{}}, {simple_merge, #{}}];
generate_order_patterns(high) ->
    [{basic_sequential, #{}}, {parallel_split, #{branches => 5}},
     {exclusive_choice, #{}}, {iterative_loop, #{}},
     {multi_instance, #{}}].

generate_document_patterns(low) -> [{basic_sequential, #{}}];
generate_document_patterns(medium) -> [{basic_sequential, #{}}, {exclusive_choice, #{}}];
generate_document_patterns(high) -> [{parallel_split, #{}}, {exclusive_choice, #{}} | [{iterative_loop, #{}}]].

generate_pipeline_patterns(low) -> [{basic_sequential, #{}}];
generate_pipeline_patterns(medium) -> [{parallel_split, #{branches => 2}}, {simple_merge, #{}}];
generate_pipeline_patterns(high) -> [{parallel_split, #{branches => 4}}, {multi_instance, #{}}].

%% Simplified pattern generators for other domains
generate_approval_patterns(_C) -> [{basic_sequential, #{}}].
generate_notification_patterns(_C) -> [{parallel_split, #{}}].
generate_financial_patterns(_C) -> [{basic_sequential, #{}}].
generate_supply_chain_patterns(_C) -> [{parallel_split, #{}}].
generate_customer_service_patterns(_C) -> [{basic_sequential, #{}}].
generate_hr_patterns(_C) -> [{basic_sequential, #{}}].
generate_security_patterns(_C) -> [{basic_sequential, #{}}].

%%====================================================================
%% Resource Generators
%%====================================================================

generate_order_resources(low) -> #{workers => 2};
generate_order_resources(medium) -> #{workers => 5};
generate_order_resources(high) -> #{workers => 10}.

generate_document_resources(_C) -> #{}.
generate_pipeline_resources(_C) -> #{}.
generate_approval_resources(_C) -> #{}.
generate_notification_resources(_C) -> #{}.
generate_financial_resources(_C) -> #{}.
generate_supply_chain_resources(_C) -> #{}.
generate_customer_service_resources(_C) -> #{}.
generate_hr_resources(_C) -> #{}.
generate_security_resources(_C) -> #{}.

%%====================================================================
%% Data Flow Generators
%%====================================================================

generate_order_data_flows(_C) -> #{}.
generate_document_data_flows(_C) -> #{}.
generate_pipeline_data_flows(_C) -> #{}.

%%====================================================================
%% Business Rules Generators
%%====================================================================

generate_order_business_rules(_C) -> [].

%%====================================================================
%% Success Criteria Generators
%%====================================================================

generate_order_success_criteria(low) -> #{max_duration => 30000};
generate_order_success_criteria(medium) -> #{max_duration => 45000};
generate_order_success_criteria(high) -> #{max_duration => 60000}.

generate_document_success_criteria(_C) -> #{}.
generate_pipeline_success_criteria(_C) -> #{}.

%%====================================================================
%% Error Scenario Generators
%%====================================================================

generate_order_error_scenarios(low) -> [];
generate_order_error_scenarios(medium) -> [payment_failed];
generate_order_error_scenarios(high) -> [payment_failed, inventory_unavailable].

%%====================================================================
%% Helper Functions
%%====================================================================

generate_edge_cases(low) -> [basic_edge];
generate_edge_cases(medium) -> [basic_edge, complex_edge];
generate_edge_cases(high) -> [basic_edge, complex_edge, critical_edge].

generate_load_profile(low) -> #{initial_load => 10};
generate_load_profile(medium) -> #{initial_load => 50};
generate_load_profile(high) -> #{initial_load => 100}.

generate_failure_injections() ->
    [
        #{type => service_timeout, probability => 0.1},
        #{type => resource_exhaustion, probability => 0.05}
    ].

generate_recovery_strategies() ->
    [
        #{type => retry, max_attempts => 3},
        #{type => circuit_breaker, threshold => 5}
    ].

get_volume(low) -> "low";
get_volume(medium) -> "medium";
get_volume(high) -> "high".

get_duration(low) -> 30000;
get_duration(medium) -> 60000;
get_duration(high) -> 120000.

%%====================================================================
%% Validation and Error Handling Functions
%%====================================================================

%% @doc Validate business domain input
validate_business_domain(Domain) when is_atom(Domain) ->
    ValidDomains = list_available_domains(),
    case lists:member(Domain, ValidDomains) of
        true -> ok;
        false -> {error, {unknown_domain, Domain}}
    end;
validate_business_domain(Domain) ->
    {error, {invalid_domain_type, Domain}}.

%% @doc Validate complexity input
validate_complexity(Complexity) when Complexity =:= low;
                                   Complexity =:= medium;
                                   Complexity =:= high ->
    ok;
validate_complexity(Complexity) ->
    {error, {invalid_complexity_value, Complexity}}.

%% @doc Validate config input
validate_config(Config) when is_map(Config) -> ok;
validate_config(Config) -> {error, {invalid_config_type, Config}}.

%% @doc Check if all required dependencies are available
check_dependencies() ->
    RequiredModules = [
        {yawl_combinatoric_test, 'YAWL Combinatoric Test'},
        {yawl_error_codes, 'YAWL Error Codes'}
    ],
    lists:foldl(fun({Module, Name}, Acc) ->
        case code:is_loaded(Module) of
            false ->
                case code:load_file(Module) of
                    {module, _} -> Acc;
                    {error, Reason} ->
                        [{Module, Name, Reason} | Acc]
                end;
            _ ->
                Acc
        end
    end, [], RequiredModules).

%% @doc Log error to file
log_error(Context, Error) ->
    log_error(Context, Error, #{}).

%% @doc Log error with details to file
log_error(Context, Error, Details) when is_map(Details) ->
    LogPath = get_error_log_path(),
    Timestamp = format_log_timestamp(),
    LogEntry = io_lib:format("[~s] ~p: ~p Details: ~p~n",
                            [Timestamp, Context, Error, Details]),
    case filelib:ensure_dir(LogPath) of
        ok ->
            file:write_file(LogPath, LogEntry, [append]);
        _ ->
            error_logger:error_msg("Failed to write to error log: ~p~n", [LogPath])
    end.

%% @private Get error log path
get_error_log_path() ->
    PrivDir = case code:priv_dir(a2a_erl) of
        {error, bad_name} -> filename:join(["..", "priv"]);
        Dir -> Dir
    end,
    filename:join(PrivDir, "error.log").

%% @private Format timestamp for error logging
format_log_timestamp() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    FormatStr = "~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0BZ",
    lists:flatten(io_lib:format(FormatStr, [Year, Month, Day, Hour, Minute, Second])).
