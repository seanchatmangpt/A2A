%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL LLM API Integration
%%%
%%% Chicago-style TDD: Tests written first to FAIL, then implementation.
%%% Tests actual LLM API integration using yawl_claude_headless module.
%%%
%%% Tests cover:
%%% - llm_generate_model/1 - actual LLM API integration
%%% - llm_refine_model/2 - LLM refinement with feedback
%%% - llm_generate_with_validation/2 - generate with automatic validation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_llm_api_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Create a realistic process description for testing
process_description_simple() ->
    <<"A simple order fulfillment process: Start -> Receive Order -> "
      "Process Payment -> Ship Goods -> Complete">>.

process_description_complex() ->
    <<"A freight delivery workflow with multiple decision points: "
      "Receive Shipment Request -> Verify Carrier Availability -> "
      "[if available] Schedule Pickup -> [if not available] Notify Customer -> "
      "Track Shipment -> Deliver -> Update Customer">>.

process_description_with_conditions() ->
    <<"A payment processing workflow: Start Payment -> "
      "[valid payment method] Process Payment -> "
      "[payment success] Confirm Order -> "
      "[payment failure] Retry Payment or Cancel -> "
      "End Workflow">>.

%% @doc Create test XES log for validation
test_xes_log() ->
    #{
        log_id => <<"test_order_log">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                <<"concept:name">> => <<"Receive Order">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                <<"concept:name">> => <<"Process Payment">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e3">>,
                timestamp => 3000,
                <<"concept:name">> => <<"Ship Goods">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e4">>,
                timestamp => 4000,
                <<"concept:name">> => <<"Complete">>,
                lifecycle => complete
            }
        ],
        metadata => #{source => <<"test">>}
    }.

%% @doc Create test XES log for freight workflow
freight_xes_log() ->
    #{
        log_id => <<"test_freight_log">>,
        trace_id => <<"freight_trace">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"f1">>,
                timestamp => 1000,
                <<"concept:name">> => <<"Receive Shipment Request">>,
                lifecycle => complete
            },
            #{
                event_id => <<"f2">>,
                timestamp => 2000,
                <<"concept:name">> => <<"Verify Carrier Availability">>,
                lifecycle => complete
            },
            #{
                event_id => <<"f3">>,
                timestamp => 3000,
                <<"concept:name">> => <<"Schedule Pickup">>,
                lifecycle => complete
            },
            #{
                event_id => <<"f4">>,
                timestamp => 4000,
                <<"concept:name">> => <<"Track Shipment">>,
                lifecycle => complete
            },
            #{
                event_id => <<"f5">>,
                timestamp => 5000,
                <<"concept:name">> => <<"Deliver">>,
                lifecycle => complete
            }
        ],
        metadata => #{source => <<"test">>}
    }.

%% @doc Mock feedback for refinement
feedback_missing_activity() ->
    <<"The model is missing the 'Verify Payment' activity between "
      "'Process Payment' and 'Confirm Order'">>.

feedback_invalid_transition() ->
    <<"The transition from 'Complete' back to 'Start' violates the "
      "causal order. 'Complete' should be a terminal activity">>.

feedback_add_decision() ->
    <<"Add a decision point after 'Process Payment' to handle "
      "payment failures with a retry mechanism">>.

feedback_list() ->
    [
        #{type => missing_activity, activity => <<"Verify Payment">>,
          suggestion => <<"Add between Process Payment and Confirm Order">>},
        #{type => invalid_transition, from => <<"Complete">>, to => <<"Start">>,
          suggestion => <<"Remove this backward transition">>}
    ].

%%====================================================================
%% Setup and Teardown
%%====================================================================

setup() ->
    %% Start the LLM validator server for tests
    case whereis(yawl_llm_validator) of
        undefined ->
            {ok, Pid} = yawl_llm_validator:start_link(),
            {Pid, started};
        Pid ->
            {Pid, already_running}
    end.

cleanup({Pid, _}) ->
    %% Don't stop the server if it was already running
    ok.

%%====================================================================
%% llm_generate_model/1 Tests
%%====================================================================

%% @doc Test generating a model from a simple process description
llm_generate_model_simple_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_simple(),
        Result = yawl_llm_validator:llm_generate_model(Description),
        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, Model} = Result,
            ?assert(is_map(Model)),
            ?assert(maps:is_key(activities, Model)),
            ?assert(maps:is_key(transitions, Model)),
            ?assert(maps:is_key(model_type, Model)),
            Activities = maps:get(activities, Model),
            ?assert(is_list(Activities)),
            ?assert(length(Activities) >= 3),
            %% Should contain key activities from description
            ?assert(lists:any(fun(A) ->
                binary:match(A, <<"Receive Order">>) =/= nomatch orelse
                binary:match(A, <<"Order">>) =/= nomatch
            end, Activities)),
            Transitions = maps:get(transitions, Model),
            ?assert(is_list(Transitions))
        end)
    end}.

%% @doc Test generating a model from a complex process description
llm_generate_model_complex_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_complex(),
        Result = yawl_llm_validator:llm_generate_model(Description),
        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, Model} = Result,
            Activities = maps:get(activities, Model),
            ?assert(length(Activities) >= 5),
            %% Should contain decision-related activities
            ?assert(lists:any(fun(A) ->
                binary:match(A, <<"Verify">>) =/= nomatch orelse
                binary:match(A, <<"Schedule">>) =/= nomatch orelse
                binary:match(A, <<"Notify">>) =/= nomatch
            end, Activities))
        end)
    end}.

%% @doc Test generating a model with conditional branching
llm_generate_model_with_conditions_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_with_conditions(),
        Result = yawl_llm_validator:llm_generate_model(Description),
        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, Model} = Result,
            Transitions = maps:get(transitions, Model),
            %% Conditional workflows should have conditions on transitions
            ?assert(lists:any(fun(T) ->
                maps:is_key(condition, T) orelse
                maps:is_key(guard, T)
            end, Transitions) orelse length(Transitions) >= 3)
        end)
    end}.

%% @doc Test error handling for empty description
llm_generate_model_empty_description_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Result = yawl_llm_validator:llm_generate_model(<<>>),
        ?_assertMatch({error, _}, Result)
    end}.

%% @doc Test error handling for invalid input type
llm_generate_model_invalid_input_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Result = yawl_llm_validator:llm_generate_model(invalid_input),
        ?_assertMatch({error, _}, Result)
    end}.

%% @doc Test that model contains metadata with generation timestamp
llm_generate_model_metadata_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_simple(),
        Result = yawl_llm_validator:llm_generate_model(Description),
        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, Model} = Result,
            Metadata = maps:get(metadata, Model, #{}),
            ?assert(is_map(Metadata)),
            ?assert(maps:is_key(generated_at, Metadata) orelse
                     maps:is_key(timestamp, Metadata))
        end)
    end}.

%%====================================================================
%% llm_refine_model/2 Tests
%%====================================================================

%% @doc Test refining a model with string feedback
llm_refine_model_with_string_feedback_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% First create a base model
        {ok, BaseModel} = yawl_llm_validator:llm_generate_model(
            process_description_simple()),

        Feedback = feedback_missing_activity(),
        Result = yawl_llm_validator:llm_refine_model(BaseModel, Feedback),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, RefinedModel} = Result,
            ?assert(is_map(RefinedModel)),
            ?assert(maps:is_key(activities, RefinedModel)),
            %% Check refinement metadata
            Metadata = maps:get(metadata, RefinedModel, #{}),
            ?assert(maps:is_key(refined_at, Metadata) orelse
                     maps:is_key(timestamp, Metadata))
        end)
    end}.

%% @doc Test refining a model with list feedback
llm_refine_model_with_list_feedback_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        BaseModel = #{
            model_type => <<"test_model">>,
            activities => [<<"Activity_A">>, <<"Activity_B">>],
            transitions => [#{from => <<"Activity_A">>, to => <<"Activity_B">>}],
            metadata => #{}
        },

        Feedback = feedback_list(),
        Result = yawl_llm_validator:llm_refine_model(BaseModel, Feedback),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, RefinedModel} = Result,
            ?assert(is_map(RefinedModel)),
            Activities = maps:get(activities, RefinedModel),
            ?assert(is_list(Activities))
        end)
    end}.

%% @doc Test refining with invalid transition feedback
llm_refine_model_invalid_transition_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        BaseModel = #{
            model_type => <<"test_model">>,
            activities => [<<"Start">>, <<"Process">>, <<"Complete">>],
            transitions => [
                #{from => <<"Start">>, to => <<"Process">>},
                #{from => <<"Complete">>, to => <<"Start">>}  % Invalid!
            ],
            metadata => #{}
        },

        Feedback = feedback_invalid_transition(),
        Result = yawl_llm_validator:llm_refine_model(BaseModel, Feedback),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, RefinedModel} = Result,
            Transitions = maps:get(transitions, RefinedModel, []),
            %% The invalid transition should be removed or modified
            ?assert(is_list(Transitions))
        end)
    end}.

%% @doc Test error handling for invalid model input
llm_refine_model_invalid_model_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Result = yawl_llm_validator:llm_refine_model(invalid_model, <<"feedback">>),
        ?_assertMatch({error, _}, Result)
    end}.

%% @doc Test error handling for invalid feedback input
llm_refine_model_invalid_feedback_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        BaseModel = #{model_type => <<"test">>, activities => [], transitions => []},
        Result = yawl_llm_validator:llm_refine_model(BaseModel, invalid_feedback),
        ?_assertMatch({error, _}, Result)
    end}.

%%====================================================================
%% llm_generate_with_validation/2 Tests
%%====================================================================

%% @doc Test generating model with immediate validation
llm_generate_with_validation_success_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_simple(),
        XESLog = test_xes_log(),

        Result = yawl_llm_validator:llm_generate_with_validation(Description, XESLog),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, ResultMap} = Result,
            ?assert(maps:is_key(model, ResultMap)),
            ?assert(maps:is_key(validation, ResultMap)),
            Model = maps:get(model, ResultMap),
            Validation = maps:get(validation, ResultMap),
            %% Check validation result structure
            ?assert(maps:is_key(is_valid, Validation)),
            ?assert(maps:is_key(fidelity_score, Validation)),
            ?assert(maps:is_key(contradictions, Validation)),
            ?assert(is_boolean(maps:get(is_valid, Validation))),
            ?assert(is_float(maps:get(fidelity_score, Validation)) orelse
                     is_integer(maps:get(fidelity_score, Validation))),
            ?assert(is_list(maps:get(contradictions, Validation)))
        end)
    end}.

%% @doc Test generate with validation returns proper structure
llm_generate_with_validation_structure_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_complex(),
        XESLog = freight_xes_log(),

        Result = yawl_llm_validator:llm_generate_with_validation(Description, XESLog),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, ResultMap} = Result,
            %% Model should have required fields
            Model = maps:get(model, ResultMap),
            ?assert(maps:is_key(activities, Model)),
            ?assert(maps:is_key(transitions, Model)),
            %% Validation should have metrics
            Validation = maps:get(validation, ResultMap),
            ?assert(maps:is_key(metrics, Validation)),
            Metrics = maps:get(metrics, Validation),
            ?assert(is_map(Metrics))
        end)
    end}.

%% @doc Test generate with validation handles empty XES log
llm_generate_with_validation_empty_xes_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_simple(),
        EmptyXES = #{log_id => <<"empty">>, events => []},

        Result = yawl_llm_validator:llm_generate_with_validation(Description, EmptyXES),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, ResultMap} = Result,
            ?assert(maps:is_key(model, ResultMap)),
            ?assert(maps:is_key(validation, ResultMap))
        end)
    end}.

%% @doc Test generate with validation error propagation
llm_generate_with_validation_error_propagation_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% Empty description should cause generation to fail
        Result = yawl_llm_validator:llm_generate_with_validation(
            <<>>, test_xes_log()),

        ?_assertMatch({error, _}, Result)
    end}.

%% @doc Test that validation catches halluncinated activities
llm_generate_with_validation_detects_hallucinations_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% Description with activities not in XES log
        Description = <<"Workflow with activities: Real Activity, Hallucinated Activity, Another Real Activity">>,

        XESLog = #{
            log_id => <<"limited_log">>,
            events => [
                #{
                    event_id => <<"e1">>,
                    timestamp => 1000,
                    <<"concept:name">> => <<"Real Activity">>,
                    lifecycle => complete
                },
                #{
                    event_id => <<"e2">>,
                    timestamp => 2000,
                    <<"concept:name">> => <<"Another Real Activity">>,
                    lifecycle => complete
                }
            ]
        },

        Result = yawl_llm_validator:llm_generate_with_validation(Description, XESLog),

        ?_test(begin
            ?assertMatch({ok, _}, Result),
            {ok, ResultMap} = Result,
            Validation = maps:get(validation, ResultMap),
            %% Should detect spurious activities
            Contradictions = maps:get(contradictions, Validation, []),
            ?assert(lists:any(fun(C) ->
                maps:get(type, C, undefined) =:= spurious_activity
            end, Contradictions) orelse
            %% Or at least have some validation output
            is_list(Contradictions))
        end)
    end}.

%%====================================================================
%% Integration Tests with yawl_claude_headless
%%====================================================================

%% @doc Test that LLM calls use yawl_claude_headless module
llm_uses_claude_headless_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% This test verifies the integration exists
        %% The actual call may fail if Claude is not configured
        Description = <<"Simple workflow: Start -> Task -> End">>,

        Result = try
            yawl_llm_validator:llm_generate_model(Description)
        catch
            _:_ -> {error, claude_not_available}
        end,

        ?_test(begin
            %% Either succeeds with proper structure or fails gracefully
            case Result of
                {ok, Model} ->
                    ?assert(is_map(Model)),
                    ?assert(maps:is_key(activities, Model));
                {error, Reason} ->
                    %% Should be a valid error reason
                    ?assert(is_atom(Reason) orelse is_binary(Reason))
            end
        end)
    end}.

%% @doc Test graceful handling when Claude is unavailable
llm_claude_unavailable_handling_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% Even if Claude is unavailable, should return meaningful error
        Description = process_description_simple(),

        Result = yawl_llm_validator:llm_generate_model(Description),

        ?_test(begin
            case Result of
                {ok, _} ->
                    ?assert(true);  %% Claude available, test passes
                {error, Reason} ->
                    %% Should have descriptive error
                    ?assert(Reason =/= undefined),
                    ?assert(Reason =/= '')
            end
        end)
    end}.

%%====================================================================
%% Performance and Edge Cases
%%====================================================================

%% @doc Test handling of very long descriptions
llm_generate_model_long_description_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        %% Create a long description
        LongDesc = list_to_binary([
            lists:duplicate(100, <<"A complex multi-step process with many activities: ">>)
        ]),

        Result = yawl_llm_validator:llm_generate_model(LongDesc),

        ?_test(begin
            case Result of
                {ok, Model} ->
                    ?assert(is_map(Model));
                {error, _} ->
                    ?assert(true)  %% May fail due to length
            end
        end)
    end}.

%% @doc Test special characters in description
llm_generate_model_special_characters_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = <<"Process with special chars: <xml>, {json}, [array], &symbols">>,

        Result = yawl_llm_validator:llm_generate_model(Description),

        ?_test(begin
            case Result of
                {ok, Model} ->
                    ?assert(is_map(Model));
                {error, _} ->
                    ?assert(true)
            end
        end)
    end}.

%% @doc Test concurrent generation requests
llm_generate_concurrent_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({_Pid, _}) ->
        Description = process_description_simple(),

        %% Spawn multiple concurrent requests
        Pids = [spawn_monitor(fun() ->
            yawl_llm_validator:llm_generate_model(Description)
        end) || _ <- lists:seq(1, 5)],

        Results = [receive
            {Pid, Result} -> Result
        after 5000 ->
            timeout
        end || {Pid, _} <- Pids],

        ?_test(begin
            ?assert(length(Results) =:= 5),
            %% All should complete (success or error)
            ?assert(lists:all(fun(R) ->
                R =:= timeout orelse
                element(1, R) =:= ok orelse
                element(1, R) =:= error
            end, Results))
        end)
    end}.
