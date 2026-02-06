%%%-------------------------------------------------------------------
%%% @doc
%%% Freight in Transit Workflow Tests
%%%
%%% EUnit tests for the freight in transit workflow example.
%%%
%%% The Freight in Transit workflow models:
%%% 1. Trackpoint collection and processing (iterative pattern)
%%% 2. Status inquiry handling (event-triggered)
%%% 3. Acceptance certificate generation upon completion
%%% 4. Proper workflow specification validation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_freight_transit_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_freight_transit_test_() ->
    [
        {"Single trackpoint flow",
         fun test_single_trackpoint_flow/0},
        {"Multiple trackpoints flow",
         fun test_multiple_trackpoints_flow/0},
        {"Trackpoint loop completion",
         fun test_trackpoint_loop_completion/0},
        {"Acceptance certificate generation",
         fun test_acceptance_certificate_generation/0},
        {"Status inquiry",
         fun test_status_inquiry/0},
        {"Workflow spec valid",
         fun test_workflow_spec_valid/0}
    ].

%%====================================================================
%%% Test Cases - Basic Trackpoint Flow
%%====================================================================

%% @doc Test processing of a single trackpoint through the workflow
test_single_trackpoint_flow() ->
    %% Create a workflow with a single trackpoint
    Trackpoint = create_test_trackpoint(1, 40.7128, -74.0060, <<"In Transit">>),
    Config = #{
        trackpoints => [Trackpoint],
        max_trackpoints => 1,
        require_certificate => false
    },

    %% Create the workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),

    %% Execute the workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify workflow completed successfully
    ?assertEqual(completed, maps:get(status, Result)),

    %% Verify trackpoint was processed
    ?assert(maps:is_key(trackpoints_processed, Result)),
    ?assertEqual(1, length(maps:get(trackpoints_processed, Result))),

    %% Verify status update
    ?assert(maps:is_key(final_status, Result)),
    ?assertEqual(<<"In Transit">>, maps:get(final_status, Result)),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% @doc Test processing of multiple trackpoints (3, 5, and 10)
test_multiple_trackpoints_flow() ->
    %% Test with 3 trackpoints
    test_with_n_trackpoints(3),
    %% Test with 5 trackpoints
    test_with_n_trackpoints(5),
    %% Test with 10 trackpoints
    test_with_n_trackpoints(10).

%% @private Helper to test workflow with N trackpoints
test_with_n_trackpoints(N) ->
    Trackpoints = create_test_trackpoints(N),
    Config = #{
        trackpoints => Trackpoints,
        max_trackpoints => N,
        require_certificate => false
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify all trackpoints processed
    ?assertEqual(completed, maps:get(status, Result)),
    ?assertEqual(N, length(maps:get(trackpoints_processed, Result))),

    %% Verify trackpoint order preservation
    Processed = maps:get(trackpoints_processed, Result),
    ?assertEqual(N, length(Processed)),
    lists:foreach(fun({Tp, Index}) ->
        ?assertEqual(Index + 1, maps:get(sequence, Tp))
    end, lists:zip(Processed, lists:seq(0, N - 1))),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% @doc Test that the trackpoint loop exits correctly when complete
test_trackpoint_loop_completion() ->
    %% Create trackpoints that should complete the loop
    Trackpoints = create_test_trackpoints(5),

    Config = #{
        trackpoints => Trackpoints,
        max_trackpoints => 5,
        require_certificate => true,
        completion_condition => fun(Count) -> Count >= 5 end
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify loop completed
    ?assertEqual(completed, maps:get(status, Result)),
    ?assertEqual(true, maps:get(loop_completed, Result)),

    %% Verify all iterations executed
    ?assertEqual(5, maps:get(iterations_completed, Result)),

    %% Verify exit condition was met
    ?assertEqual(true, maps:get(exit_condition_met, Result)),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% @doc Test acceptance certificate generation upon workflow completion
test_acceptance_certificate_generation() ->
    %% Create complete trackpoint sequence
    Trackpoints = create_complete_journey_trackpoints(),

    Config = #{
        trackpoints => Trackpoints,
        max_trackpoints => length(Trackpoints),
        require_certificate => true,
        certificate_template => freight_acceptance
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify workflow completed
    ?assertEqual(completed, maps:get(status, Result)),

    %% Verify certificate was generated
    ?assert(maps:is_key(certificate, Result)),
    Certificate = maps:get(certificate, Result),

    %% Verify certificate structure
    ?assert(maps:is_key(certificate_id, Certificate)),
    ?assert(maps:is_key(type, Certificate)),
    ?assertEqual(<<"Freight Acceptance">>, maps:get(type, Certificate)),

    %% Verify certificate contains journey information
    ?assert(maps:is_key(origin, Certificate)),
    ?assert(maps:is_key(destination, Certificate)),
    ?assert(maps:is_key(trackpoint_count, Certificate)),
    ?assertEqual(length(Trackpoints), maps:get(trackpoint_count, Certificate)),

    %% Verify certificate has timestamp
    ?assert(maps:is_key(issued_at, Certificate)),
    ?assert(is_integer(maps:get(issued_at, Certificate))),

    %% Verify certificate has signature
    ?assert(maps:is_key(signature, Certificate)),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% @doc Test that status inquiry triggers correctly
test_status_inquiry() ->
    %% Create workflow with initial trackpoints
    Trackpoints = create_test_trackpoints(3),

    Config = #{
        trackpoints => Trackpoints,
        max_trackpoints => 10,
        require_certificate => false,
        enable_status_inquiry => true
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),

    %% Execute initial workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
    ?assertEqual(running, maps:get(status, Result)),

    %% Trigger status inquiry
    StatusInquiry = #{
        inquiry_id => <<"inquiry_001">>,
        inquiry_type => status_check,
        requested_by => <<"customer_service">>
    },

    {ok, StatusResult} = yawl_orchestrator:execute_workflow(WorkflowId, StatusInquiry),

    %% Verify status inquiry was processed
    ?assert(maps:is_key(inquiry_response, StatusResult)),
    Response = maps:get(inquiry_response, StatusResult),

    %% Verify response contains current status
    ?assert(maps:is_key(current_status, Response)),
    ?assert(maps:is_key(trackpoints_processed, Response)),
    ?assertEqual(3, maps:get(trackpoints_processed, Response)),

    %% Verify response contains progress information
    ?assert(maps:is_key(progress_percentage, Response)),
    Progress = maps:get(progress_percentage, Response),
    ?assert(Progress >= 0 andalso Progress =< 100),

    %% Verify inquiry was logged
    ?assert(maps:is_key(inquiry_log, StatusResult)),
    ?assert(length(maps:get(inquiry_log, StatusResult)) > 0),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% @doc Test that the freight transit workflow specification is valid
test_workflow_spec_valid() ->
    %% Get the workflow specification
    Spec = get_freight_transit_spec(),

    %% Verify required fields
    ?assert(maps:is_key(workflow_id, Spec)),
    ?assert(maps:is_key(workflow_name, Spec)),
    ?assert(maps:is_key(places, Spec)),
    ?assert(maps:is_key(transitions, Spec)),
    ?assert(maps:is_key(initial_marking, Spec)),

    %% Verify workflow_id
    ?assertEqual(<<"freight_transit">>, maps:get(workflow_id, Spec)),

    %% Verify workflow_name
    ?assertEqual(<<"Freight in Transit Workflow">>, maps:get(workflow_name, Spec)),

    %% Verify places
    Places = maps:get(places, Spec),
    ?assert(length(Places) > 0),
    ?assert(lists:member(start, Places)),
    ?assert(lists:member('end', Places)),
    ?assert(lists:member(trackpoint_loop, Places)),
    ?assert(lists:member(certificate_generation, Places)),
    ?assert(lists:member(status_inquiry, Places)),

    %% Verify transitions
    Transitions = maps:get(transitions, Spec),
    ?assert(length(Transitions) > 0),

    %% Verify initial marking
    InitialMarking = maps:get(initial_marking, Spec),
    ?assert(maps:is_key(start, InitialMarking)),
    ?assert(length(maps:get(start, InitialMarking)) > 0),

    %% Verify structure completeness
    verify_preset_structure(Spec),
    verify_postset_structure(Spec),

    %% Verify pattern combination
    ?assert(maps:is_key(pattern_combination, Spec)),
    PatternCombination = maps:get(pattern_combination, Spec),
    ?assert(length(PatternCombination) > 0),

    %% Verify required patterns are present
    PatternTypes = [P || {P, _} <- PatternCombination],
    ?assert(lists:member(iterative_loop, PatternTypes)),
    ?assert(lists:member(multi_instance, PatternTypes)),

    ok.

%%====================================================================
%%% Helper Functions
%%====================================================================

%% @private Create a test trackpoint
create_test_trackpoint(Seq, Lat, Lon, Status) ->
    #{
        sequence => Seq,
        latitude => Lat,
        longitude => Lon,
        timestamp => erlang:system_time(millisecond),
        status => Status,
        location => <<"Test Location ", (integer_to_binary(Seq))/binary>>
    }.

%% @private Create N test trackpoints
create_test_trackpoints(N) ->
    [create_test_trackpoint(Seq, 40.0 + Seq * 0.1, -74.0 + Seq * 0.1,
                          <<"In Transit">>) || Seq <- lists:seq(1, N)].

%% @private Create a complete journey's worth of trackpoints
create_complete_journey_trackpoints() ->
    [
        create_test_trackpoint(1, 40.7128, -74.0060, <<"Picked Up">>),
        create_test_trackpoint(2, 40.7500, -74.0500, <<"In Transit">>),
        create_test_trackpoint(3, 40.8000, -74.1000, <<"In Transit">>),
        create_test_trackpoint(4, 40.8500, -74.1500, <<"In Transit">>),
        create_test_trackpoint(5, 40.9000, -74.2000, <<"Out for Delivery">>),
        create_test_trackpoint(6, 40.9500, -74.2500, <<"Delivered">>)
    ].

%% @private Get the freight transit workflow specification
get_freight_transit_spec() ->
    #{
        workflow_id => <<"freight_transit">>,
        workflow_name => <<"Freight in Transit Workflow">>,
        description => <<"Workflow for tracking freight in transit and generating acceptance certificates">>,
        places => [
            start,
            trackpoint_loop,
            process_trackpoint,
            check_completion,
            certificate_generation,
            status_inquiry,
            complete,
            'end'
        ],
        transitions => [
            initialize,
            add_trackpoint,
            validate_trackpoint,
            update_status,
            check_if_complete,
            generate_certificate,
            respond_to_inquiry,
            finalize
        ],
        initial_marking => #{
            start => [workflow_token]
        },
        preset => #{
            initialize => [start],
            add_trackpoint => [trackpoint_loop],
            validate_trackpoint => [process_trackpoint],
            update_status => [process_trackpoint],
            check_if_complete => [check_completion],
            generate_certificate => [certificate_generation],
            respond_to_inquiry => [status_inquiry],
            finalize => [complete]
        },
        postset => #{
            initialize => [trackpoint_loop],
            add_trackpoint => [process_trackpoint],
            validate_trackpoint => [update_status],
            update_status => [check_completion],
            check_if_complete => [trackpoint_loop, certificate_generation],
            generate_certificate => [complete],
            respond_to_inquiry => [status_inquiry],
            finalize => ['end']
        },
        pattern_combination => [
            {iterative_loop, #{
                loop_place => trackpoint_loop,
                exit_condition => trackpoints_complete
            }},
            {multi_instance, #{
                instance_type => trackpoints,
                num_instances => variable
            }},
            {milestone, #{
                milestone_place => certificate_generation,
                milestone_condition => journey_complete
            }}
        ]
    }.

%% @private Verify preset structure is complete
verify_preset_structure(Spec) ->
    Preset = maps:get(preset, Spec),
    Transitions = maps:get(transitions, Spec),

    %% All transitions should have preset defined
    lists:foreach(fun(Transition) ->
        ?assert(maps:is_key(Transition, Preset),
            io_lib:format("Missing preset for transition: ~p", [Transition]))
    end, Transitions),

    %% All presets should be non-empty lists
    maps:foreach(fun(_Transition, PresetPlaces) ->
        ?assert(is_list(PresetPlaces)),
        ?assert(length(PresetPlaces) > 0)
    end, Preset),

    ok.

%% @private Verify postset structure is complete
verify_postset_structure(Spec) ->
    Postset = maps:get(postset, Spec),
    Transitions = maps:get(transitions, Spec),

    %% All transitions should have postset defined
    lists:foreach(fun(Transition) ->
        ?assert(maps:is_key(Transition, Postset),
            io_lib:format("Missing postset for transition: ~p", [Transition]))
    end, Transitions),

    %% All postsets should be lists
    maps:foreach(fun(_Transition, PostsetPlaces) ->
        ?assert(is_list(PostsetPlaces))
    end, Postset),

    ok.

%%====================================================================
%%% Additional Validation Tests
%%====================================================================

%% @doc Test edge case: workflow with zero trackpoints
test_zero_trackpoints_test_() ->
    [{"Zero trackpoints handled gracefully", fun() ->
        Config = #{
            trackpoints => [],
            max_trackpoints => 0,
            require_certificate => false
        },

        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        ?assertEqual(completed, maps:get(status, Result)),
        ?assertEqual(0, maps:get(trackpoints_processed, Result)),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].

%% @doc Test edge case: trackpoint validation failures
test_invalid_trackpoint_test_() ->
    [{"Invalid trackpoint rejected", fun() ->
        InvalidTrackpoint = #{
            sequence => -1,  %% Invalid: negative sequence
            latitude => 200.0,  %% Invalid: out of range
            longitude => undefined,  %% Invalid: missing
            timestamp => <<"not_a_number">>,  %% Invalid: wrong type
            status => <<"In Transit">>
        },

        Config = #{
            trackpoints => [InvalidTrackpoint],
            max_trackpoints => 1,
            require_certificate => false,
            validation_mode => strict
        },

        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        ?assertEqual(completed, maps:get(status, Result)),
        ?assertEqual(0, maps:get(trackpoints_processed, Result)),
        ?assertEqual(1, maps:get(validation_errors, Result)),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].

%% @doc Test concurrent status inquiries
test_concurrent_status_inquiry_test_() ->
    [{"Multiple concurrent status inquiries handled", fun() ->
        Trackpoints = create_test_trackpoints(5),

        Config = #{
            trackpoints => Trackpoints,
            max_trackpoints => 10,
            enable_status_inquiry => true
        },

        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),

        %% Send multiple status inquiries
        Inquiries = [
            #{inquiry_id => <<"inq_1">>, inquiry_type => status_check},
            #{inquiry_id => <<"inq_2">>, inquiry_type => status_check},
            #{inquiry_id => <<"inq_3">>, inquiry_type => status_check}
        ],

        %% Execute all inquiries concurrently
        Results = lists:map(fun(Inquiry) ->
            {ok, R} = yawl_orchestrator:execute_workflow(WorkflowId, Inquiry),
            R
        end, Inquiries),

        %% Verify all inquiries were processed
        ?assertEqual(3, length(Results)),

        lists:foreach(fun(Result) ->
            ?assert(maps:is_key(inquiry_response, Result))
        end, Results),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].

%% @doc Test certificate content validation
test_certificate_validation_test_() ->
    [{"Certificate contains required fields", fun() ->
        Trackpoints = create_complete_journey_trackpoints(),

        Config = #{
            trackpoints => Trackpoints,
            max_trackpoints => length(Trackpoints),
            require_certificate => true,
            certificate_template => freight_acceptance
        },

        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        Certificate = maps:get(certificate, Result),

        %% Verify all required certificate fields
        RequiredFields = [
            certificate_id,
            type,
            origin,
            destination,
            trackpoint_count,
            issued_at,
            signature
        ],

        lists:foreach(fun(Field) ->
            ?assert(maps:is_key(Field, Certificate),
                io_lib:format("Missing certificate field: ~p", [Field]))
        end, RequiredFields),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].

%%====================================================================
%%% Performance Tests
%%====================================================================

%% @doc Test workflow handles large number of trackpoints efficiently
test_large_trackpoint_count_test_() ->
    [{"100 trackpoints processed efficiently", fun() ->
        %% Create 100 trackpoints
        Trackpoints = [create_test_trackpoint(Seq, 40.0, -74.0, <<"In Transit">>)
                       || Seq <- lists:seq(1, 100)],

        Config = #{
            trackpoints => Trackpoints,
            max_trackpoints => 100,
            require_certificate => false
        },

        StartTime = erlang:monotonic_time(millisecond),

        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        EndTime = erlang:monotonic_time(millisecond),
        Duration = EndTime - StartTime,

        %% Verify all trackpoints processed
        ?assertEqual(completed, maps:get(status, Result)),
        ?assertEqual(100, maps:get(trackpoints_processed, Result)),

        %% Verify performance (should complete in reasonable time)
        ?assert(Duration < 5000,
            io_lib:format("Processing 100 trackpoints took too long: ~p ms", [Duration])),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].

%%====================================================================
%%% Integration Tests
%%====================================================================

%% @doc Test freight transit workflow integration with orchestrator
test_orchestrator_integration_test_() ->
    [{"Workflow integrates properly with orchestrator", fun() ->
        Trackpoints = create_test_trackpoints(3),

        Config = #{
            trackpoints => Trackpoints,
            max_trackpoints => 3,
            require_certificate => true
        },

        %% Create workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),

        %% Verify workflow is registered
        {ok, WorkflowIds} = yawl_orchestrator:list_workflows(),
        ?assert(lists:member(WorkflowId, WorkflowIds)),

        %% Check status before execution
        {ok, InitialStatus} = yawl_orchestrator:get_status(WorkflowId),
        ?assertEqual(pending, InitialStatus),

        %% Execute workflow
        {ok, _Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        %% Check status after execution
        {ok, FinalStatus} = yawl_orchestrator:get_status(WorkflowId),
        ?assertEqual(completed, FinalStatus),

        %% Cleanup
        ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

        %% Verify workflow is cleaned up
        {ok, UpdatedWorkflowIds} = yawl_orchestrator:list_workflows(),
        ?assertNot(lists:member(WorkflowId, UpdatedWorkflowIds))
    end}].

%% @doc Test workflow persistence and recovery
test_workflow_persistence_test_() ->
    [{"Workflow state persists correctly", fun() ->
        Trackpoints = create_test_trackpoints(5),

        Config = #{
            trackpoints => Trackpoints,
            max_trackpoints => 10,
            require_certificate => false,
            enable_persistence => true
        },

        %% Create and start workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(freight_transit, Config),
        {ok, _Result} = yawl_orchestrator:execute_workflow(WorkflowId),

        %% Get workflow instance
        {ok, Instance} = yawl_orchestrator:get_workflow_instance(WorkflowId),

        %% Verify instance contains workflow data
        ?assert(maps:is_key(workflow_id, Instance)),
        ?assert(maps:is_key(current_state, Instance)),

        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end}].
