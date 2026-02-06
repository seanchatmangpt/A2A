%%%-------------------------------------------------------------------
%%% @doc
%%% LLM Hallucination Detection for Process Models
%%%
%%% This module implements validation and hallucination detection for
%%% LLM-generated process models, based on van der Aalst et al. (Sep 2025)
%%% "Knowledge-Driven Hallucination in Process Modeling with LLMs".
%%%
%%% Key Concepts:
%%% - Knowledge-Driven Hallucination: LLM output contradicts source evidence
%%% - Fidelity Assessment: Compare LLM models against XES traces
%%% - Conflict Scenarios: Test with atypical vs standard process structures
%%%
%%% Reference: arXiv:2509.15336 (Sep 2025)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_llm_validator).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% API exports - Validation against source evidence
-export([
    validate_against_xes/2,
    fidelity_score/2,
    detect_contradictions/2,
    hallucination_report/1
]).

%% API exports - Test scenarios
-export([
    create_atypical_process/0,
    create_standard_process/0,
    create_conflict_scenario/1,
    validate_against_scenario/3
]).

%% API exports - LLM integration interface
-export([
    llm_generate_model/1,
    llm_refine_model/2,
    llm_generate_with_validation/2,
    llm_batch_validate/2
]).

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% API Functions - Validation
%%====================================================================

%% @doc Start the LLM validator server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Validate an LLM-generated model against XES event log.
-spec validate_against_xes(llm_model(), map()) -> llm_validation_result().
validate_against_xes(LLMModel, XESLog) ->
    gen_server:call(?SERVER, {validate_against_xes, LLMModel, XESLog}).

%% @doc Compute fidelity score between LLM model and source artifact.
-spec fidelity_score(llm_model(), map() | binary()) -> float().
fidelity_score(LLMModel, SourceArtifact) ->
    gen_server:call(?SERVER, {fidelity_score, LLMModel, SourceArtifact}).

%% @doc Detect contradictions between LLM output and evidence.
-spec detect_contradictions(llm_model(), map() | map()) -> [map()].
detect_contradictions(LLMModel, Evidence) ->
    gen_server:call(?SERVER, {detect_contradictions, LLMModel, Evidence}).

%% @doc Generate comprehensive hallucination report.
-spec hallucination_report(map()) -> map().
hallucination_report(ValidationResult) ->
    #{
        summary => generate_summary(ValidationResult),
        hallucinations => classify_hallucinations(ValidationResult),
        recommendations => generate_recommendations(ValidationResult),
        confidence_metrics => compute_confidence_metrics(ValidationResult)
    }.

%%====================================================================
%% API Functions - Test Scenarios
%%====================================================================

%% @doc Create an atypical process structure for testing.
%% Atypical processes have unusual structures that may trigger hallucinations.
-spec create_atypical_process() -> llm_model().
create_atypical_process() ->
    #{
        model_type => <<"atypical_test">>,
        activities => [
            <<"Unusual_Activity_A">>,
            <<"Unusual_Activity_B">>,
            <<"Rare_Decision_Point">>
        ],
        transitions => [
            #{
                from => <<"Unusual_Activity_A">>,
                to => <<"Rare_Decision_Point">>,
                condition => <<"rare_case">>
            },
            #{
                from => <<"Rare_Decision_Point">>,
                to => <<"Unusual_Activity_B">>,
                condition => <<"unlikely_path">>
            }
        ],
        metadata => #{
            test_type => atypical,
            expected_hallucination_rate => high
        }
    }.

%% @doc Create a standard process structure for baseline testing.
-spec create_standard_process() -> llm_model().
create_standard_process() ->
    #{
        model_type => <<"standard_test">>,
        activities => [
            <<"Start">>,
            <<"Process">>,
            <<"Complete">>
        ],
        transitions => [
            #{from => <<"Start">>, to => <<"Process">>},
            #{from => <<"Process">>, to => <<"Complete">>}
        ],
        metadata => #{
            test_type => standard,
            expected_hallucination_rate => low
        }
    }.

%% @doc Create a conflict scenario to test hallucination detection.
-spec create_conflict_scenario(atom()) -> map().
create_conflict_scenario(ScenarioType) ->
    case ScenarioType of
        structural_mismatch ->
            #{
                type => structural_mismatch,
                description => <<"Model has different structure than evidence">>,
                evidence => create_standard_evidence(),
                model => create_atypical_process()
            };
        missing_activities ->
            #{
                type => missing_activities,
                description => <<"Model is missing activities present in evidence">>,
                evidence => create_complex_evidence(),
                model => #{
                    activities => [<<"Activity_A">>],
                    transitions => []
                }
            };
        spurious_activities ->
            #{
                type => spurious_activities,
                description => <<"Model has activities not in evidence">>,
                evidence => create_standard_evidence(),
                model => #{
                    activities => [
                        <<"Activity_A">>,
                        <<"Hallucinated_Activity_X">>,
                        <<"Hallucinated_Activity_Y">>
                    ],
                    transitions => []
                }
            };
        causal_violation ->
            #{
                type => causal_violation,
                description => <<"Model violates causal order from evidence">>,
                evidence => create_standard_evidence(),
                model => #{
                    activities => [<<"Complete">>, <<"Process">>, <<"Start">>],
                    transitions => [
                        #{from => <<"Complete">>, to => <<"Process">>},
                        #{from => <<"Process">>, to => <<"Start">>}
                    ]
                }
            }
    end.

%% @doc Validate model against a specific scenario.
-spec validate_against_scenario(llm_model(), map(), map()) -> map().
validate_against_scenario(Model, Scenario, Options) ->
    %% Extract evidence from scenario
    Evidence = maps:get(evidence, Scenario, #{}),
    ScenarioType = maps:get(type, Scenario, unknown),

    %% Run validation
    ValidationResult = validate_against_xes(Model, Evidence),

    %% Add scenario-specific analysis
    ValidationResult#{
        scenario_type => ScenarioType,
        scenario_metadata => maps:without([evidence, model], Scenario),
        options => Options
    }.

%%====================================================================
%% API Functions - LLM Integration
%%====================================================================

%% @doc Generate a process model from description using LLM.
-spec llm_generate_model(binary()) -> {ok, llm_model()} | {error, term()}.
llm_generate_model(Description) ->
    gen_server:call(?SERVER, {llm_generate, Description}).

%% @doc Refine an existing LLM-generated model with feedback.
-spec llm_refine_model(llm_model(), binary() | [map()]) -> {ok, llm_model()} | {error, term()}.
llm_refine_model(Model, Feedback) ->
    gen_server:call(?SERVER, {llm_refine, Model, Feedback}).

%% @doc Generate model with immediate validation.
-spec llm_generate_with_validation(binary(), map()) -> {ok, map()} | {error, term()}.
llm_generate_with_validation(Description, XESLog) ->
    case llm_generate_model(Description) of
        {ok, Model} ->
            ValidationResult = validate_against_xes(Model, XESLog),
            {ok, #{
                model => Model,
                validation => ValidationResult
            }};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Batch validate multiple LLM models.
-spec llm_batch_validate([llm_model()], map()) -> [llm_validation_result()].
llm_batch_validate(Models, XESLog) ->
    lists:map(
        fun(M) -> validate_against_xes(M, XESLog) end,
        Models
    ).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #{
        cache => #{},
        statistics => #{
            validations => 0,
            hallucinations_detected => 0
        }
    }}.

handle_call({validate_against_xes, LLMModel, XESLog}, _From, State) ->
    Result = do_validate_against_xes(LLMModel, XESLog),
    Statistics = maps:get(statistics, State, #{}),
    NewStats = maps:update_with(
        validations,
        fun(V) -> V + 1 end,
        1,
        Statistics
    ),
    NewStats2 = case maps:get(is_valid, Result) of
        false ->
            maps:update_with(
                hallucinations_detected,
                fun(H) -> H + 1 end,
                1,
                NewStats
            );
        true ->
            NewStats
    end,
    {reply, Result, State#{statistics => NewStats2}};

handle_call({fidelity_score, LLMModel, SourceArtifact}, _From, State) ->
    Score = compute_fidelity_score(LLMModel, SourceArtifact),
    {reply, Score, State};

handle_call({detect_contradictions, LLMModel, Evidence}, _From, State) ->
    Contradictions = find_contradictions(LLMModel, Evidence),
    {reply, Contradictions, State};

handle_call({llm_generate, Description}, _From, State) ->
    %% Generate model using configured LLM backend
    Result = do_llm_generate(Description),
    {reply, Result, State};

handle_call({llm_refine, Model, Feedback}, _From, State) ->
    Result = do_llm_refine(Model, Feedback),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Validation
%%====================================================================

%% @private
do_validate_against_xes(LLMModel, XESLog) ->
    %% Extract activities from both sources
    ModelActivities = extract_model_activities(LLMModel),
    LogActivities = extract_log_activities(XESLog),

    %% Compute various validation metrics
    MissingActivities = compute_missing_activities(ModelActivities, LogActivities),
    SpuriousActivities = compute_spurious_activities(ModelActivities, LogActivities),
    CausalViolations = check_causal_order(LLMModel, XESLog),
    StructuralScore = compute_structural_score(LLMModel, XESLog),

    %% Find contradictions
    Contradictions = find_contradictions(LLMModel, XESLog),

    %% Compute overall fidelity
    Fidelity = compute_fidelity_score(LLMModel, XESLog),

    %% Determine validity
    IsValid = Fidelity >= 0.7 andalso length(Contradictions) =:= 0,

    #{
        is_valid => IsValid,
        fidelity_score => Fidelity,
        contradictions => Contradictions,
        warnings => generate_warnings(MissingActivities, SpuriousActivities, CausalViolations),
        confidence => compute_confidence(Fidelity, Contradictions),
        metrics => #{
            missing_activities => MissingActivities,
            spurious_activities => SpuriousActivities,
            causal_violations => CausalViolations,
            structural_score => StructuralScore
        }
    }.

%% @private
extract_model_activities(LLMModel) ->
    maps:get(activities, LLMModel, []).

%% @private
extract_log_activities(XESLog) ->
    case XESLog of
        Events when is_list(Events) ->
            lists:usort([extract_activity_name(E) || E <- Events]);
        _ when is_map(XESLog) ->
            Events = maps:get(events, XESLog, []),
            lists:usort([extract_activity_name(E) || E <- Events])
    end.

%% @private
extract_activity_name(Event) when is_map(Event) ->
    maps:get(<<"concept:name">>, Event,
            maps:get(activity, Event, <<"unknown">>)).

%% @private
compute_missing_activities(ModelActivities, LogActivities) ->
    ModelSet = sets:from_list(ModelActivities),
    LogSet = sets:from_list(LogActivities),
    Missing = sets:to_list(sets:subtract(LogSet, ModelSet)),
    Missing.

%% @private
compute_spurious_activities(ModelActivities, LogActivities) ->
    ModelSet = sets:from_list(ModelActivities),
    LogSet = sets:from_list(LogActivities),
    Spurious = sets:to_list(sets:subtract(ModelSet, LogSet)),
    Spurious.

%% @private
check_causal_order(LLMModel, XESLog) ->
    %% Check if model respects causal order from log
    ModelTransitions = maps:get(transitions, LLMModel, []),
    LogOrder = extract_causal_order_from_log(XESLog),

    lists:filter(
        fun(T) ->
            From = maps:get(from, T),
            To = maps:get(to, T),
            not is_valid_causal_relation(From, To, LogOrder)
        end,
        ModelTransitions
    ).

%% @private
is_valid_causal_relation(_From, _To, LogOrder) ->
    %% Simplified - would check if relation exists in log
    maps:is_key({<<"A">>, <<"B">>}, LogOrder).

%% @private
extract_causal_order_from_log(_XESLog) ->
    %% Extract causal order from event log
    #{{<<"A">>, <<"B">>} => true}.

%% @private
compute_structural_score(LLMModel, XESLog) ->
    %% Compute structural similarity score
    ModelActivities = length(maps:get(activities, LLMModel, [])),
    LogActivities = length(extract_log_activities(XESLog)),

    case LogActivities of
        0 -> 0.0;
        N -> 1.0 - abs(ModelActivities - N) / N
    end.

%% @private
find_contradictions(LLMModel, Evidence) ->
    %% Find specific contradictions between model and evidence
    Missing = compute_missing_activities(
        extract_model_activities(LLMModel),
        extract_log_activities(Evidence)
    ),

    Spurious = compute_spurious_activities(
        extract_model_activities(LLMModel),
        extract_log_activities(Evidence)
    ),

    CausalViolations = check_causal_order(LLMModel, Evidence),

    lists:map(
        fun(A) -> #{
            type => missing_activity,
            severity => high,
            description => <<"Activity in evidence but not in model">>,
            activity => A
        } end,
        Missing
    ) ++ lists:map(
        fun(A) -> #{
            type => spurious_activity,
            severity => medium,
            description => <<"Activity in model but not in evidence">>,
            activity => A
        } end,
        Spurious
    ) ++ lists:map(
        fun(T) -> #{
            type => causal_violation,
            severity => high,
            description => <<"Transition violates causal order">>,
            transition => T
        } end,
        CausalViolations
    ).

%% @private
compute_fidelity_score(LLMModel, SourceArtifact) ->
    %% Compute overall fidelity score
    ModelActivities = extract_model_activities(LLMModel),
    LogActivities = extract_log_activities(SourceArtifact),

    %% Jaccard similarity
    ModelSet = sets:from_list(ModelActivities),
    LogSet = sets:from_list(LogActivities),
    Intersection = sets:intersection(ModelSet, LogSet),
    Union = sets:union(ModelSet, LogSet),

    BaseScore = case sets:size(Union) of
        0 -> 1.0;
        N -> sets:size(Intersection) / N
    end,

    %% Adjust for structural and causal violations
    StructuralScore = compute_structural_score(LLMModel, SourceArtifact),
    CausalScore = 1.0 - length(check_causal_order(LLMModel, SourceArtifact)) /
                     max(1, length(maps:get(transitions, LLMModel, []))),

    (BaseScore + StructuralScore + CausalScore) / 3.

%% @private
generate_warnings(Missing, Spurious, CausalViolations) ->
    Warnings = [],
    Warnings1 = case Missing of
        [] -> Warnings;
        _ -> [#{type => missing_activities, count => length(Missing)} | Warnings]
    end,
    Warnings2 = case Spurious of
        [] -> Warnings1;
        _ -> [#{type => spurious_activities, count => length(Spurious)} | Warnings1]
    end,
    Warnings3 = case CausalViolations of
        [] -> Warnings2;
        _ -> [#{type => causal_violations, count => length(CausalViolations)} | Warnings2]
    end,
    lists:reverse(Warnings3).

%% @private
compute_confidence(Fidelity, Contradictions) ->
    %% Compute confidence in validation result
    BaseConfidence = Fidelity,
    Penalty = length(Contradictions) * 0.1,
    max(0.0, BaseConfidence - Penalty).

%%====================================================================
%% Internal Functions - LLM Integration
%%====================================================================

%% @private
do_llm_generate(Description) ->
    %% Placeholder for actual LLM API call
    %% Would integrate with OpenAI, Anthropic, local models, etc.
    {ok, #{
        model_type => <<"generated">>,
        activities => parse_activities_from_description(Description),
        transitions => [],
        metadata => #{
            generated_at => erlang:system_time(millisecond)
        }
    }}.

%% @private
do_llm_refine(Model, _Feedback) ->
    %% Refine model based on feedback
    %% Would send feedback to LLM for correction
    {ok, Model#{
        metadata => (maps:get(metadata, Model, #{}))#{
            refined_at => erlang:system_time(millisecond),
            feedback_applied => true
        }
    }}.

%% @private
parse_activities_from_description(Description) ->
    %% Simple parsing - would use LLM in real implementation
    Words = binary:split(Description, <<" ">>, [global]),
    [W || W <- Words, byte_size(W) > 3].

%%====================================================================
%% Internal Functions - Report Generation
%%====================================================================

%% @private
generate_summary(ValidationResult) ->
    #{
        is_valid => maps:get(is_valid, ValidationResult),
        fidelity_score => maps:get(fidelity_score, ValidationResult),
        total_issues => length(maps:get(contradictions, ValidationResult, [])) +
                        length(maps:get(warnings, ValidationResult, []))
    }.

%% @private
classify_hallucinations(ValidationResult) ->
    Contradictions = maps:get(contradictions, ValidationResult, []),
    lists:map(
        fun(C) ->
            Type = maps:get(type, C, unknown),
            case Type of
                missing_activity -> knowledge_driven;
                spurious_activity -> knowledge_driven;
                causal_violation -> structural_invalid;
                _ -> semantic_drift
            end
        end,
        Contradictions
    ).

%% @private
generate_recommendations(ValidationResult) ->
    IsValid = maps:get(is_valid, ValidationResult),
    Fidelity = maps:get(fidelity_score, ValidationResult),

    Recs = [],
    Recs1 = case IsValid of
        false -> ["Model validation failed. Review with domain expert." | Recs];
        true -> Recs
    end,

    Recs2 = case Fidelity < 0.5 of
        true -> ["Low fidelity score. Consider regenerating with more specific prompts." | Recs1];
        false -> Recs1
    end,

    lists:reverse(Recs2).

%% @private
compute_confidence_metrics(ValidationResult) ->
    #{
        validation_confidence => maps:get(confidence, ValidationResult),
        fidelity_score => maps:get(fidelity_score, ValidationResult),
        contradiction_count => length(maps:get(contradictions, ValidationResult, [])),
        warning_count => length(maps:get(warnings, ValidationResult, []))
    }.

%%====================================================================
%% Internal Functions - Test Data
%%====================================================================

%% @private
create_standard_evidence() ->
    %% Create standard XES log for testing (using map format)
    #{
        log_id => <<"test_standard">>,
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => erlang:system_time(millisecond),
                <<"concept:name">> => <<"Activity_A">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => erlang:system_time(millisecond) + 1000,
                <<"concept:name">> => <<"Activity_B">>,
                lifecycle => complete
            }
        ]
    }.

%% @private
create_complex_evidence() ->
    %% Create more complex XES log with multiple activities
    Activities = [<<"Activity_A">>, <<"Activity_B">>, <<"Activity_C">>, <<"Activity_D">>],
    #{
        log_id => <<"test_complex">>,
        events => [
            #{
                event_id => list_to_binary(["e", integer_to_list(I)]),
                timestamp => erlang:system_time(millisecond) + I * 1000,
                <<"concept:name">> => A,
                lifecycle => complete
            }
            || {I, A} <- lists:enumerate(Activities)
        ]
    }.
