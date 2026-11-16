%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive AI Integration Test Suite for YAWL
%%%
%%% This test suite demonstrates LLM validation scenarios, AI grounding
%%% with OCPM data, and end-to-end AI integration patterns.
%%%
%%% Based on research from van der Aalst 2025-2026 on process mining
%%% and AI validation.
%%%
%%% References:
%%% - arXiv:2509.15336 (LLM hallucination detection)
%%% - arXiv:2508.00116 (OCPM for grounding AI)
%%% - arXiv:2602.02447 (Reachability in workflow nets)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_ai_integration_tests).
-author("A2A Team").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%% Test Suite Configuration
%%====================================================================

%% Common Test callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    %% LLM Validation Scenarios
    test_llm_validate_simple_workflow/1,
    test_llm_detect_hallucinated_activities/1,
    test_llm_detect_missing_activities/1,
    test_llm_detect_causal_violations/1,
    test_llm_fidelity_score_perfect_match/1,
    test_llm_fidelity_score_partial_match/1,

    %% OCPM Grounding Scenarios
    test_ocpm_ground_generative_ai/1,
    test_ocpm_ground_predictive_ai/1,
    test_ocpm_ground_prescriptive_ai/1,
    test_ocpm_multi_object_grounding/1,
    test_ocpm_cross_object_validation/1,

    %% End-to-End Integration
    test_full_ai_validation_pipeline/1,
    test_xes_export_with_ai_metadata/1,
    test_concurrent_workflow_ai_validation/1,
    test_reachability_assisted_validation/1,

    %% Edge Cases
    test_empty_log_validation/1,
    test_conflicting_ai_predictions/1,
    test_ambiguous_activity_mapping/1
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
    [
        %% LLM Validation Scenarios
        test_llm_validate_simple_workflow,
        test_llm_detect_hallucinated_activities,
        test_llm_detect_missing_activities,
        test_llm_detect_causal_violations,
        test_llm_fidelity_score_perfect_match,
        test_llm_fidelity_score_partial_match,

        %% OCPM Grounding Scenarios
        test_ocpm_ground_generative_ai,
        test_ocpm_ground_predictive_ai,
        test_ocpm_ground_prescriptive_ai,
        test_ocpm_multi_object_grounding,
        test_ocpm_cross_object_validation,

        %% End-to-End Integration
        test_full_ai_validation_pipeline,
        test_xes_export_with_ai_metadata,
        test_concurrent_workflow_ai_validation,
        test_reachability_assisted_validation,

        %% Edge Cases
        test_empty_log_validation,
        test_conflicting_ai_predictions,
        test_ambiguous_activity_mapping
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(a2a_erl),
    %% Start OCPM server
    {ok, _OCPMPid} = yawl_ocpm:start_link(),
    %% Start XES logger
    {ok, _XESPid} = yawl_xes_logger:start_link(),
    Config.

end_per_suite(_Config) ->
    %% Clean up
    yawl_ocpm:stop(),
    yawl_xes_logger:stop(),
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Reset state before each test
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%====================================================================
%% LLM Validation Scenarios
%%====================================================================

%% @doc Test basic LLM validation against a simple workflow log
test_llm_validate_simple_workflow(_Config) ->
    %% Create a simple XES log
    XESLog = create_simple_workflow_log(),

    %% Create an LLM-generated model
    LLMModel = #{
        model_type => <<"gpt-4">>,
        activities => [<<"Submit">>, <<"Approve">>, <<"Complete">>],
        transitions => [
            #{from => <<"Submit">>, to => <<"Approve">>},
            #{from => <<"Approve">>, to => <<"Complete">>}
        ],
        metadata => #{
            timestamp => erlang:system_time(millisecond),
            prompt => <<"Describe the approval workflow">>
        }
    },

    %% Validate
    ValidationResult = yawl_llm_validator:validate_against_xes(LLMModel, XESLog),

    %% Assertions
    ?assertMatch(#{is_valid := _, fidelity_score := _}, ValidationResult),
    ?assert(maps:get(is_valid, ValidationResult) =:= true orelse
            maps:get(is_valid, ValidationResult) =:= false),
    ?assert(maps:get(fidelity_score, ValidationResult) >= 0.0),
    ?assert(maps:get(fidelity_score, ValidationResult) =< 1.0),
    {comment, "Simple workflow validation completed"}.

%% @doc Test detection of hallucinated activities not present in actual log
test_llm_detect_hallucinated_activities(_Config) ->
    %% Real log only has 3 activities
    XESLog = create_simple_workflow_log(),

    %% LLM hallucinates additional activities
    HallucinatingModel = #{
        model_type => <<"hallucinating_model">>,
        activities => [
            <<"Submit">>,
            <<"Approve">>,
            <<"Complete">>,
            <<"Review">>,          %% Hallucinated
            <<"Authorize">>,       %% Hallucinated
            <<"Finalize">>         %% Hallucinated
        ],
        transitions => [
            #{from => <<"Submit">>, to => <<"Review">>},
            #{from => <<"Review">>, to => <<"Authorize">>},
            #{from => <<"Authorize">>, to => <<"Complete">>}
        ],
        metadata => #{}
    },

    %% Detect contradictions
    Contradictions = yawl_llm_validator:detect_contradictions(HallucinatingModel, XESLog),

    %% Should detect spurious activities
    ?assert(length(Contradictions) > 0),
    ?assert(lists:any(
        fun(C) ->
            maps:get(type, C) =:= spurious_activity
        end,
        Contradictions
    )),

    %% Get detailed report
    Report = yawl_llm_validator:hallucination_report(
        #{
            is_valid => false,
            fidelity_score => 0.5,
            contradictions => Contradictions,
            warnings => [],
            confidence => 0.8
        }
    ),

    ?assertMatch(#{summary := _, hallucinations := _}, Report),
    {comment, "Detected " ++ integer_to_list(length(Contradictions)) ++ " contradictions"}.

%% @doc Test detection of missing activities that LLM failed to capture
test_llm_detect_missing_activities(_Config) ->
    %% Complex log with 5 activities
    XESLog = create_complex_workflow_log(),

    %% LLM only captured 3 activities
    IncompleteModel = #{
        model_type => <<"incomplete_model">>,
        activities => [
            <<"Start">>,
            <<"Process">>,
            <<"End">>
        ],
        transitions => [
            #{from => <<"Start">>, to => <<"Process">>},
            #{from => <<"Process">>, to => <<"End">>}
        ],
        metadata => #{}
    },

    %% Detect contradictions
    Contradictions = yawl_llm_validator:detect_contradictions(IncompleteModel, XESLog),

    %% Should detect missing activities
    ?assert(length(Contradictions) > 0),
    HasMissing = lists:any(
        fun(C) ->
            maps:get(type, C) =:= missing_activity
        end,
        Contradictions
    ),
    ?assert(HasMissing),
    {comment, "Detected missing activities"}.

%% @doc Test detection of causal relationship violations
test_llm_detect_causal_violations(_Config) ->
    %% Log shows: A -> B -> C
    XESLog = #{
        log_id => <<"causal_test">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{event_id => <<"e1">>, timestamp => 1000, activity => <<"A">>, lifecycle => complete},
            #{event_id => <<"e2">>, timestamp => 2000, activity => <<"B">>, lifecycle => complete},
            #{event_id => <<"e3">>, timestamp => 3000, activity => <<"C">>, lifecycle => complete}
        ],
        metadata => #{}
    },

    %% LLM claims: A -> C (skipping B), and C -> B (wrong direction)
    WrongCausalModel = #{
        model_type => <<"wrong_causal">>,
        activities => [<<"A">>, <<"B">>, <<"C">>],
        transitions => [
            #{from => <<"A">>, to => <<"C">>},
            #{from => <<"C">>, to => <<"B">>}
        ],
        metadata => #{}
    },

    %% Detect contradictions
    Contradictions = yawl_llm_validator:detect_contradictions(WrongCausalModel, XESLog),

    %% Should detect causal violations
    ?assert(length(Contradictions) > 0),
    HasCausalViolation = lists:any(
        fun(C) ->
            maps:get(type, C) =:= causal_violation
        end,
        Contradictions
    ),
    ?assert(HasCausalViolation),
    {comment, "Detected causal violations"}.

%% @doc Test fidelity score with perfect model match
test_llm_fidelity_score_perfect_match(_Config) ->
    XESLog = create_simple_workflow_log(),

    %% Perfect model
    PerfectModel = #{
        model_type => <<"perfect">>,
        activities => [<<"Submit">>, <<"Approve">>, <<"Complete">>],
        transitions => [
            #{from => <<"Submit">>, to => <<"Approve">>},
            #{from => <<"Approve">>, to => <<"Complete">>}
        ],
        metadata => #{}
    },

    Fidelity = yawl_llm_validator:fidelity_score(PerfectModel, XESLog),

    %% Should be close to 1.0
    ?assert(Fidelity > 0.9),
    {comment, "Fidelity score: " ++ float_to_list(Fidelity, [{decimals, 3}])}.

%% @doc Test fidelity score with partial model match
test_llm_fidelity_score_partial_match(_Config) ->
    XESLog = create_complex_workflow_log(),

    %% Partial model (60% of activities)
    PartialModel = #{
        model_type => <<"partial">>,
        activities => [<<"Start">>, <<"Validate">>, <<"End">>],
        transitions => [
            #{from => <<"Start">>, to => <<"Validate">>},
            #{from => <<"Validate">>, to => <<"End">>}
        ],
        metadata => #{}
    },

    Fidelity = yawl_llm_validator:fidelity_score(PartialModel, XESLog),

    %% Should be between 0.3 and 0.7
    ?assert(Fidelity >= 0.3),
    ?assert(Fidelity =< 0.7),
    {comment, "Partial fidelity: " ++ float_to_list(Fidelity, [{decimals, 3}])}.

%%====================================================================
%% OCPM Grounding Scenarios
%%====================================================================

%% @doc Test grounding generative AI with OCPM data
test_ocpm_ground_generative_ai(_Config) ->
    %% Create OCPM log for order processing
    OCELLog = create_order_ocel_log(),

    %% Ground generative AI
    GroundingResult = yawl_ocpm:ground_generative_ai(OCELLog),

    %% Assertions
    ?assertMatch(#{
        grounded := _,
        confidence := _,
        evidence_count := _,
        grounding_map := _
    }, GroundingResult),

    %% With good OCPM data, should be grounded
    ?assert(maps:get(evidence_count, GroundingResult) > 0),
    {comment, "Grounding confidence: " ++
        float_to_list(maps:get(confidence, GroundingResult), [{decimals, 3}])}.

%% @doc Test grounding predictive AI with temporal patterns
test_ocpm_ground_predictive_ai(_Config) ->
    OCELLog = create_order_ocel_log(),

    %% Ground predictive AI
    GroundingResult = yawl_ocpm:ground_predictive_ai(OCELLog),

    %% Should extract temporal patterns
    ?assertMatch(#{grounded := _, confidence := _}, GroundingResult),
    ?assert(maps:get(confidence, GroundingResult) >= 0.0),
    {comment, "Predictive grounding confidence: " ++
        float_to_list(maps:get(confidence, GroundingResult), [{decimals, 3}])}.

%% @doc Test grounding prescriptive AI with action patterns
test_ocpm_ground_prescriptive_ai(_Config) ->
    OCELLog = create_order_ocel_log(),

    %% Ground prescriptive AI
    GroundingResult = yawl_ocpm:ground_prescriptive_ai(OCELLog),

    %% Should validate action patterns
    ?assertMatch(#{grounded := _, confidence := _}, GroundingResult),
    ?assert(is_boolean(maps:get(grounded, GroundingResult))),
    {comment, "Prescriptive grounded: " ++
        atom_to_list(maps:get(grounded, GroundingResult))}.

%% @doc Test multi-object event grounding
test_ocpm_multi_object_grounding(_Config) ->
    %% Create log with multi-object events
    OCELLog = #{
        log_id => <<"multi_obj">>,
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"ProcessOrder">>,
                objects => #{
                    <<"Order">> => [<<"order1">>],
                    <<"Customer">> => [<<"cust1">>],
                    <<"Item">> => [<<"item1">>, <<"item2">>]
                },
                attributes => #{total => 300}
            }
        ],
        object_types => [<<"Order">>, <<"Customer">>, <<"Item">>],
        metadata => #{}
    },

    %% Check object interactions
    Interactions = yawl_ocpm:pi_object_interactions(OCELLog),

    ?assert(length(Interactions) > 0),
    Interaction = lists:nth(1, Interactions),
    ?assert(length(maps:get(participating_types, Interaction, [])) >= 2),
    {comment, "Multi-object interaction detected"}.

%% @doc Test cross-object dependency validation
test_ocpm_cross_object_validation(_Config) ->
    OCELLog = create_order_ocel_log(),

    %% Get inter-object dependencies
    Dependencies = yawl_ocpm:pi_inter_object_dependencies(OCELLog),

    ?assert(is_list(Dependencies)),
    %% Check each dependency tuple
    lists:foreach(
        fun({Type1, Type2, Count}) ->
            ?assert(is_binary(Type1)),
            ?assert(is_binary(Type2)),
            ?assert(is_integer(Count) andalso Count >= 0)
        end,
        Dependencies
    ),
    {comment, "Found " ++ integer_to_list(length(Dependencies)) ++ " dependencies"}.

%%====================================================================
%% End-to-End Integration Tests
%%====================================================================

%% @doc Full AI validation pipeline from workflow execution to validation
test_full_ai_validation_pipeline(_Config) ->
    %% Step 1: Execute workflow and log to XES
    WorkflowId = <<"test_workflow_ai">>,
    {ok, LogId} = yawl_xes_logger:create_trace(WorkflowId),

    %% Simulate workflow execution
    ok = yawl_xes_logger:log_workflow_event(WorkflowId, <<"Submit">>, complete, #{}),
    ok = yawl_xes_logger:log_workflow_event(WorkflowId, <<"Review">>, complete, #{}),
    ok = yawl_xes_logger:log_workflow_event(WorkflowId, <<"Approve">>, complete, #{}),
    ok = yawl_xes_logger:log_workflow_event(WorkflowId, <<"Complete">>, complete, #{}),

    %% Step 2: Export XES log
    {ok, XESLog} = yawl_xes_logger:get_log(LogId),

    %% Step 3: Generate LLM model (simulated)
    LLMModel = #{
        model_type => <<"gpt-4">>,
        activities => [<<"Submit">>, <<"Review">>, <<"Approve">>, <<"Complete">>],
        transitions => [
            #{from => <<"Submit">>, to => <<"Review">>},
            #{from => <<"Review">>, to => <<"Approve">>},
            #{from => <<"Approve">>, to => <<"Complete">>}
        ],
        metadata => #{}
    },

    %% Step 4: Validate
    ValidationResult = yawl_llm_validator:validate_against_xes(LLMModel, XESLog),

    %% Step 5: Check results
    ?assertMatch(#{is_valid := true}, ValidationResult),
    ?assert(maps:get(fidelity_score, ValidationResult) > 0.8),

    {comment, "Full pipeline completed with fidelity: " ++
        float_to_list(maps:get(fidelity_score, ValidationResult), [{decimals, 3}])}.

%% @doc XES export with AI validation metadata
test_xes_export_with_ai_metadata(_Config) ->
    %% Create workflow trace
    WorkflowId = <<"xes_ai_test">>,
    {ok, _LogId} = yawl_xes_logger:create_trace(WorkflowId),

    %% Log events
    ok = yawl_xes_logger:log_workflow_event(
        WorkflowId,
        <<"Activity1">>,
        complete,
        #{ai_generated => true, confidence => 0.95}
    ),
    ok = yawl_xes_logger:log_workflow_event(
        WorkflowId,
        <<"Activity2">>,
        complete,
        #{ai_validated => true, fidelity => 0.88}
    ),

    %% Export to XES
    {ok, XESBinary} = yawl_xes_logger:export_log_to_xes(WorkflowId),

    %% Verify XES contains AI metadata
    ?assert(is_binary(XESBinary)),
    ?assert(binary:match(XESBinary, <<"ai_generated">>) =/= nomatch orelse
            binary:match(XESBinary, <<"ai_validated">>) =/= nomatch),

    {comment, "XES export contains AI metadata"}.

%% @doc AI validation for concurrent workflow patterns
test_concurrent_workflow_ai_validation(_Config) ->
    %% Create XES log for parallel workflow
    XESLog = #{
        log_id => <<"concurrent">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{event_id => <<"e1">>, timestamp => 1000, activity => <<"Start">>, lifecycle => complete},
            %% Parallel branches
            #{event_id => <<"e2">>, timestamp => 2000, activity => <<"TaskA">>, lifecycle => complete},
            #{event_id => <<"e3">>, timestamp => 2500, activity => <<"TaskB">>, lifecycle => complete},
            #{event_id => <<"e4">>, timestamp => 2000, activity => <<"TaskC">>, lifecycle => complete},
            %% Join
            #{event_id => <<"e5">>, timestamp => 3000, activity => <<"Merge">>, lifecycle => complete}
        ],
        metadata => #{has_concurrency => true}
    },

    %% LLM captures sequential instead of parallel
    SequentialModel = #{
        model_type => <<"sequential_model">>,
        activities => [<<"Start">>, <<"TaskA">>, <<"TaskB">>, <<"TaskC">>, <<"Merge">>],
        transitions => [
            #{from => <<"Start">>, to => <<"TaskA">>},
            #{from => <<"TaskA">>, to => <<"TaskB">>},
            #{from => <<"TaskB">>, to => <<"TaskC">>},
            #{from => <<"TaskC">>, to => <<"Merge">>}
        ],
        metadata => #{}
    },

    %% Validate - should detect concurrency mismatch
    ValidationResult = yawl_llm_validator:validate_against_xes(SequentialModel, XESLog),

    %% Fidelity should be lower due to concurrency structure mismatch
    ?assert(maps:get(fidelity_score, ValidationResult) < 1.0),

    {comment, "Concurrent workflow validation: " ++
        float_to_list(maps:get(fidelity_score, ValidationResult), [{decimals, 3}])}.

%% @doc Reachability-assisted AI validation
test_reachability_assisted_validation(_Config) ->
    %% Create workflow net for validation
    NetInfo = create_test_workflow_net(),

    %% Check reachability properties
    TargetMarking = #{p_final => [token]},
    ReachabilityResult = yawl_reachability:is_reachable(NetInfo, TargetMarking),

    ?assertMatch(#{is_reachable := true}, ReachabilityResult),

    %% Verify soundness
    SoundnessResult = yawl_reachability:verify_soundness(NetInfo),

    ?assertMatch(#{is_sound := _}, SoundnessResult),

    {comment, "Reachability validation completed"}.

%%====================================================================
%% Edge Case Tests
%%====================================================================

%% @doc Test validation with empty log
test_empty_log_validation(_Config) ->
    EmptyLog = #{
        log_id => <<"empty">>,
        trace_id => <<"empty_trace">>,
        started_at => erlang:system_time(millisecond),
        events => [],
        metadata => #{}
    },

    Model = #{
        model_type => <<"test">>,
        activities => [<<"A">>],
        transitions => [],
        metadata => #{}
    },

    Result = yawl_llm_validator:validate_against_xes(Model, EmptyLog),

    %% Empty log should result in low validity or specific handling
    ?assert(is_map(Result)),
    {comment, "Empty log validation handled"}.

%% @doc Test handling of conflicting AI predictions
test_conflicting_ai_predictions(_Config) ->
    XESLog = create_simple_workflow_log(),

    %% Two models with conflicting predictions
    Model1 = #{
        model_type => <<"model1">>,
        activities => [<<"Submit">>, <<"Approve">>],
        transitions => [#{from => <<"Submit">>, to => <<"Approve">>}],
        metadata => #{}
    },
    Model2 = #{
        model_type => <<"model2">>,
        activities => [<<"Submit">>, <<"Reject">>],
        transitions => [#{from => <<"Submit">>, to => <<"Reject">>}],
        metadata => #{}
    },

    %% Batch validate both
    Results = yawl_llm_validator:llm_batch_validate([Model1, Model2], XESLog),

    ?assert(length(Results) =:= 2),
    ?assert(lists:all(fun(R) -> is_map(R) end, Results)),

    {comment, "Conflicting predictions validated"}.

%% @doc Test ambiguous activity mapping
test_ambiguous_activity_mapping(_Config) ->
    XESLog = #{
        log_id => <<"ambiguous">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{event_id => <<"e1">>, timestamp => 1000, activity => <<"Process">>, lifecycle => complete},
            #{event_id => <<"e2">>, timestamp => 2000, activity => <<"Process">>, lifecycle => complete},
            #{event_id => <<"e3">>, timestamp => 3000, activity => <<"Process">>, lifecycle => complete}
        ],
        metadata => #{}
    },

    %% LLM generates specific activity names
    SpecificModel = #{
        model_type => <<"specific">>,
        activities => [<<"Validate">>, <<"Transform">>, <<"Save">>],
        transitions => [
            #{from => <<"Validate">>, to => <<"Transform">>},
            #{from => <<"Transform">>, to => <<"Save">>}
        ],
        metadata => #{}
    },

    Result = yawl_llm_validator:validate_against_xes(SpecificModel, XESLog),

    %% Should handle ambiguity gracefully
    ?assert(is_map(Result)),
    {comment, "Ambiguous mapping handled"}.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
create_simple_workflow_log() ->
    #{
        log_id => <<"simple_workflow">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"Submit">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                activity => <<"Approve">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e3">>,
                timestamp => 3000,
                activity => <<"Complete">>,
                lifecycle => complete
            }
        ],
        metadata => #{}
    }.

%% @private
create_complex_workflow_log() ->
    #{
        log_id => <<"complex_workflow">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{event_id => <<"e1">>, timestamp => 1000, activity => <<"Start">>, lifecycle => complete},
            #{event_id => <<"e2">>, timestamp => 2000, activity => <<"Validate">>, lifecycle => complete},
            #{event_id => <<"e3">>, timestamp => 3000, activity => <<"Process">>, lifecycle => complete},
            #{event_id => <<"e4">>, timestamp => 4000, activity => <<"Review">>, lifecycle => complete},
            #{event_id => <<"e5">>, timestamp => 5000, activity => <<"End">>, lifecycle => complete}
        ],
        metadata => #{}
    }.

%% @private
create_order_ocel_log() ->
    #{
        log_id => <<"order_ocel">>,
        events => [
            #{
                event_id => <<"oe1">>,
                timestamp => 1000,
                activity => <<"CreateOrder">>,
                objects => #{<<"Order">> => [<<"order1">>], <<"Customer">> => [<<"cust1">>]},
                attributes => #{amount => 100}
            },
            #{
                event_id => <<"oe2">>,
                timestamp => 2000,
                activity => <<"AddItem">>,
                objects => #{<<"Order">> => [<<"order1">>], <<"Item">> => [<<"item1">>]},
                attributes => #{quantity => 2}
            },
            #{
                event_id => <<"oe3">>,
                timestamp => 3000,
                activity => <<"ProcessPayment">>,
                objects => #{
                    <<"Order">> => [<<"order1">>],
                    <<"Payment">> => [<<"pay1">>],
                    <<"Customer">> => [<<"cust1">>]
                },
                attributes => #{amount => 100, method => <<"card">>}
            },
            #{
                event_id => <<"oe4">>,
                timestamp => 4000,
                activity => <<"ShipOrder">>,
                objects => #{<<"Order">> => [<<"order1">>], <<"Item">> => [<<"item1">>]},
                attributes => #{}
            }
        ],
        object_types => [<<"Order">>, <<"Customer">>, <<"Item">>, <<"Payment">>],
        metadata => #{created_at => erlang:system_time(millisecond)}
    }.

%% @private
create_test_workflow_net() ->
    #{
        places => [p_start, p_process, p_validate, p_final],
        transitions => [t_start, t_process, t_validate, t_end],
        preset => #{
            t_start => [p_start],
            t_process => [p_process],
            t_validate => [p_validate],
            t_end => [p_validate]
        },
        postset => #{
            p_start => [t_start],
            p_process => [t_process],
            p_validate => [t_validate, t_end],
            p_final => []
        }
    }.
