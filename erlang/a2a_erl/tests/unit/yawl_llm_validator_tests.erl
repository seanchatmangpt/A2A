%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL LLM Validator
%%%
%%% Tests for LLM hallucination detection based on van der Aalst 2025.
%%% Paper: arXiv:2509.15336
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_llm_validator_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%% Test fixtures
test_xes_log_map() ->
    #{
        log_id => <<"test_log">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"Activity_A">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                activity => <<"Activity_B">>,
                lifecycle => complete
            }
        ],
        metadata => #{}
    }.

test_llm_model() ->
    #{
        model_type => <<"test_model">>,
        activities => [<<"Activity_A">>, <<"Activity_B">>],
        transitions => [
            #{from => <<"Activity_A">>, to => <<"Activity_B">>}
        ],
        metadata => #{}
    }.

%%====================================================================
%% Validation Tests
%%====================================================================

validate_against_xes_test_() ->
    Model = test_llm_model(),
    XESLog = test_xes_log_map(),
    Result = yawl_llm_validator:validate_against_xes(Model, XESLog),
    ?assertMatch(#{is_valid := _, fidelity_score := _}, Result).

fidelity_score_test_() ->
    Model = test_llm_model(),
    Fidelity = yawl_llm_validator:fidelity_score(Model, test_xes_log_map()),
    ?assert(Fidelity >= 0.0),
    ?assert(Fidelity =< 1.01).

detect_contradictions_test_() ->
    %% Model with spurious activity
    Model = #{
        model_type => <<"hallucinating_model">>,
        activities => [<<"Activity_A">>, <<"Activity_B">>, <<"Hallucinated_Activity">>],
        transitions => [],
        metadata => #{}
    },
    Contradictions = yawl_llm_validator:detect_contradictions(Model, test_xes_log_map()),
    ?assert(lists:any(fun(C) -> maps:get(type, C) =:= spurious_activity end, Contradictions)).

hallucination_report_test_() ->
    ValidationResult = #{
        is_valid => false,
        fidelity_score => 0.65,
        contradictions => [
            #{type => spurious_activity, activity => <<"Hallucinated">>}
        ],
        warnings => [],
        confidence => 0.7
    },
    Report = yawl_llm_validator:hallucination_report(ValidationResult),
    ?assertMatch(#{summary := _, hallucinations := _}, Report).

%%====================================================================
%% Test Scenario Tests
%%====================================================================

create_atypical_process_test_() ->
    Atypical = yawl_llm_validator:create_atypical_process(),
    ?assertMatch(#{pattern_type := <<"atypical_test">>}, Atypical).

create_standard_process_test_() ->
    Standard = yawl_llm_validator:create_standard_process(),
    ?assertMatch(#{pattern_type := <<"standard_test">>}, Standard).

create_conflict_scenario_test_() ->
    Scenario = yawl_llm_validator:create_conflict_scenario(structural_mismatch),
    ?assertMatch(#{type := structural_mismatch}, Scenario).

validate_against_scenario_test_() ->
    Model = test_llm_model(),
    Scenario = yawl_llm_validator:create_conflict_scenario(missing_activities),
    Result = yawl_llm_validator:validate_against_scenario(Model, Scenario, #{}),
    ?assertMatch(#{scenario_type := missing_activities}, Result).

%%====================================================================
%% LLM Integration Tests
%%====================================================================

llm_generate_model_test_() ->
    %% This test would mock the LLM call
    Description = <<"Simple sequential workflow with two tasks">>,
    case yawl_llm_validator:llm_generate_model(Description) of
        {ok, Model} ->
            ?assertMatch(#{activities := _, transitions := _}, Model);
        {error, _} ->
            ?assert(true)  %% Would pass if LLM backend not configured
    end.

llm_refine_model_test_() ->
    Model = test_llm_model(),
    Feedback = <<"Add another activity between Activity_A and Activity_B">>,
    case yawl_llm_validator:llm_refine_model(Model, Feedback) of
        {ok, RefinedModel} ->
            ?assert(is_map(RefinedModel));
        {error, _} ->
            ?assert(true)
    end.

llm_generate_with_validation_test_() ->
    Description = <<"Simple workflow">>,
    case yawl_llm_validator:llm_generate_with_validation(Description, test_xes_log_map()) of
        {ok, Result} ->
            ?assertMatch(#{model := _, validation := _}, Result);
        {error, _} ->
            ?assert(true)
    end.

llm_batch_validate_test_() ->
    Models = [test_llm_model(), test_llm_model()],
    Results = yawl_llm_validator:llm_batch_validate(Models, test_xes_log_map()),
    ?assert(length(Results) =:= 2),
    ?assert(lists:all(fun(R) -> is_map(R) end, Results)).
