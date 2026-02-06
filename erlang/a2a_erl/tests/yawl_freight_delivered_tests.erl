%%%-------------------------------------------------------------------
%%% @doc
%%% Freight Delivered Workflow Tests
%%%
%%% EUnit tests for the freight delivered workflow, which handles
%%% post-delivery processes including loss/damage claims and merchandise
%%% returns.
%%%
%%% Workflow Description:
%%% 1. Freight Delivered - Trigger when freight delivery is confirmed
%%% 2. Claims Processing - Handle loss/damage claims
%%% 3. Return Processing - Handle merchandise returns
%%% 4. Authorization - Approve/reject claims and returns
%%% 5. Deadline Management - Cancel pending claims after deadline expires
%%% 6. Exclusive Choice - Only one path (claim OR return) allowed
%%%
%%% Patterns Used:
%%% - Sequence: Delivered -> Processing -> Authorization
%%% - Exclusive Choice: Claim path vs Return path
%%% - Deferred Choice: Authorization decision
%%% - Cancellation: Timer cancels pending claims
%%% - Discriminator: First response completes, cancel others
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_freight_delivered_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_freight_delivered_test_() ->
    [
        {"Loss/damage claim approved",
         fun test_loss_damage_claim_approved/0},
        {"Loss/damage claim rejected",
         fun test_loss_damage_claim_rejected/0},
        {"Return merchandise approved",
         fun test_return_merchandise_approved/0},
        {"Return merchandise rejected",
         fun test_return_merchandise_rejected/0},
        {"Claims deadline expiration",
         fun test_claims_deadline_expiration/0},
        {"Exclusive choice claim or return",
         fun test_exclusive_choice_claim_or_return/0},
        {"Workflow spec valid",
         fun test_workflow_spec_valid/0}
    ].

%%====================================================================
%%% Test Cases - Claim Authorization Tests
%%====================================================================

%% @doc Test successful loss/damage claim authorization
test_loss_damage_claim_approved() ->
    % Create claim data with valid evidence
    ClaimData = #{
        claim_id => <<"claim_001">>,
        delivery_id => <<"delivery_12345">>,
        claim_type => loss,
        description => <<"Package damaged during transit">>,
        evidence => [<<"photo1.jpg">>, <<"damage_report.pdf">>],
        claimed_amount => 25000,
        filed_date => erlang:system_time(second)
    },

    % Initialize workflow with claim
    InitialMarking = initialize_freight_delivered_workflow(claim, ClaimData),

    % Simulate claim submission path
    MarkingAfterSubmit = apply_transition(InitialMarking, submit_claim, ClaimData),

    % Verify claim is in pending state
    ?assertMatch([#{status := pending}], maps:get(claim_pending, MarkingAfterSubmit, [])),

    % Simulate claim approval
    MarkingAfterApproval = apply_transition(MarkingAfterSubmit, authorize_claim, #{
        decision => approved,
        authorized_by => <<"claims_agent_001">>,
        approved_amount => 25000,
        notes => <<"Claim approved with supporting evidence">>
    }),

    % Verify claim is approved and in final state
    ?assertMatch([#{status := approved, authorized_amount := 25000}],
                 maps:get(claim_approved, MarkingAfterApproval, [])),

    % Verify workflow reaches completion
    ?assert(maps:is_key(claim_completed, MarkingAfterApproval)).

%% @doc Test loss/damage claim rejection
test_loss_damage_claim_rejected() ->
    % Create claim data with insufficient evidence
    ClaimData = #{
        claim_id => <<"claim_002">>,
        delivery_id => <<"delivery_12346">>,
        claim_type => damage,
        description => <<"Item arrived broken">>,
        evidence => [],  % No evidence provided
        claimed_amount => 5000,
        filed_date => erlang:system_time(second)
    },

    % Initialize workflow with claim
    InitialMarking = initialize_freight_delivered_workflow(claim, ClaimData),

    % Simulate claim submission
    MarkingAfterSubmit = apply_transition(InitialMarking, submit_claim, ClaimData),

    % Verify claim is pending
    ?assertMatch([#{status := pending}], maps:get(claim_pending, MarkingAfterSubmit, [])),

    % Simulate claim rejection
    RejectionReason = <<"Insufficient evidence provided for claim">>,
    MarkingAfterRejection = apply_transition(MarkingAfterSubmit, authorize_claim, #{
        decision => rejected,
        authorized_by => <<"claims_agent_002">>,
        rejection_reason => RejectionReason
    }),

    % Verify claim is rejected with reason
    ?assertMatch([#{status := rejected, rejection_reason := RejectionReason}],
                 maps:get(claim_rejected, MarkingAfterRejection, [])),

    % Verify workflow reaches completion
    ?assert(maps:is_key(claim_closed, MarkingAfterRejection)).

%%====================================================================
%%% Test Cases - Return Authorization Tests
%%====================================================================

%% @doc Test successful merchandise return authorization
test_return_merchandise_approved() ->
    % Create return request with valid reason
    ReturnData = #{
        return_id => <<"return_001">>,
        delivery_id => <<"delivery_23456">>,
        return_reason => defective_product,
        description => <<"Product arrived defective, not working">>,
        items => [
            #{sku => <<"SKU-12345">>, quantity => 1, condition => new}
        ],
        refund_requested => 7999,
        filed_date => erlang:system_time(second)
    },

    % Initialize workflow with return request
    InitialMarking = initialize_freight_delivered_workflow(return, ReturnData),

    % Simulate return submission
    MarkingAfterSubmit = apply_transition(InitialMarking, submit_return, ReturnData),

    % Verify return is in pending state
    ?assertMatch([#{status := pending}], maps:get(return_pending, MarkingAfterSubmit, [])),

    % Simulate return approval
    MarkingAfterApproval = apply_transition(MarkingAfterSubmit, authorize_return, #{
        decision => approved,
        authorized_by => <<"returns_agent_001">>,
        refund_method => credit_card,
        refund_amount => 7999,
        return_shipping => prepaid
    }),

    % Verify return is approved with refund details
    ?assertMatch([#{status := approved,
                     refund_amount := 7999,
                     refund_method := credit_card}],
                 maps:get(return_approved, MarkingAfterApproval, [])),

    % Verify return shipping label generated
    ?assert(maps:is_key(return_label_generated, MarkingAfterApproval)),

    % Verify workflow reaches completion
    ?assert(maps:is_key(return_completed, MarkingAfterApproval)).

%% @doc Test merchandise return rejection
test_return_merchandise_rejected() ->
    % Create return request outside return window
    ThirtyOneDaysAgo = erlang:system_time(second) - (31 * 86400),
    ReturnData = #{
        return_id => <<"return_002">>,
        delivery_id => <<"delivery_23457">>,
        return_reason => no_longer_needed,
        description => <<"Customer changed mind">>,
        items => [
            #{sku => <<"SKU-67890">>, quantity => 1, condition => opened}
        ],
        refund_requested => 15000,
        filed_date => ThirtyOneDaysAgo,  % Outside 30-day window
        delivery_date => ThirtyOneDaysAgo - (7 * 86400)
    },

    % Initialize workflow with return request
    InitialMarking = initialize_freight_delivered_workflow(return, ReturnData),

    % Simulate return submission
    MarkingAfterSubmit = apply_transition(InitialMarking, submit_return, ReturnData),

    % Verify return is pending
    ?assertMatch([#{status := pending}], maps:get(return_pending, MarkingAfterSubmit, [])),

    % Simulate return rejection due to policy
    MarkingAfterRejection = apply_transition(MarkingAfterSubmit, authorize_return, #{
        decision => rejected,
        authorized_by => <<"returns_agent_002">>,
        rejection_reason => <<"Return window of 30 days has expired">>,
        policy_reference => <<"return_policy_section_3.1">>
    }),

    % Verify return is rejected
    ?assertMatch([#{status := rejected,
                     rejection_reason := <<"Return window of 30 days has expired">>}],
                 maps:get(return_rejected, MarkingAfterRejection, [])),

    % Verify rejection notification sent
    ?assert(maps:is_key(return_notification_sent, MarkingAfterRejection)),

    % Verify workflow reaches closed state
    ?assert(maps:is_key(return_closed, MarkingAfterRejection)).

%%====================================================================
%%% Test Cases - Deadline Expiration Tests
%%====================================================================

%% @doc Test claims deadline cancellation via timer
test_claims_deadline_expiration() ->
    % Create claim near deadline
    ClaimData = #{
        claim_id => <<"claim_deadline_001">>,
        delivery_id => <<"delivery_34567">>,
        claim_type => damage,
        description => <<"Damage discovered late">>,
        evidence => [<<"photo.jpg">>],
        claimed_amount => 10000,
        filed_date => erlang:system_time(second) - (86 * 86400),  % 86 days ago
        delivery_date => erlang:system_time(second) - (90 * 86400),  % 90 days ago
        deadline_days => 90
    },

    % Initialize workflow with claim
    InitialMarking = initialize_freight_delivered_workflow(claim, ClaimData),

    % Simulate claim submission
    MarkingAfterSubmit = apply_transition(InitialMarking, submit_claim, ClaimData),

    % Verify claim is pending
    ?assertMatch([#{status := pending}], maps:get(claim_pending, MarkingAfterSubmit, [])),

    % Start deadline timer
    MarkingWithTimer = apply_transition(MarkingAfterSubmit, start_deadline_timer, #{
        deadline_seconds => 4 * 86400,  % 4 days remaining
        timer_ref => make_ref()
    }),

    % Verify timer is active
    ?assertMatch([#{timer_status := active}], maps:get(timer_active, MarkingWithTimer, [])),

    % Simulate deadline expiration
    MarkingAfterExpiry = apply_transition(MarkingWithTimer, deadline_expired, #{
        expiry_reason => claims_deadline,
        expired_at => erlang:system_time(second)
    }),

    % Verify claim is cancelled due to deadline
    ?assertMatch([#{status := cancelled,
                     cancellation_reason := claims_deadline}],
                 maps:get(claim_cancelled, MarkingAfterExpiry, [])),

    % Verify timer is stopped
    ?assertMatch([#{timer_status := stopped}], maps:get(timer_stopped, MarkingAfterExpiry, [])),

    % Verify pending claim place is cleared
    ?assertEqual([], maps:get(claim_pending, MarkingAfterExpiry, [])).

%%====================================================================
%%% Test Cases - Exclusive Choice Tests
%%====================================================================

%% @doc Test exclusive choice between claim and return paths
test_exclusive_choice_claim_or_return() ->
    % Create delivery that could have either claim or return
    DeliveryData = #{
        delivery_id => <<"delivery_45678">>,
        customer_id => <<"customer_123">>,
        items => [
            #{sku => <<"SKU-001">>, quantity => 1, price => 5000},
            #{sku => <<"SKU-002">>, quantity => 2, price => 2500}
        ],
        delivered_at => erlang:system_time(second)
    },

    % Initialize workflow at decision point
    InitialMarking = initialize_freight_delivered_workflow(decision, DeliveryData),

    % Verify we're at the exclusive choice point
    ?assertMatch([_Token], maps:get(exclusive_choice_point, InitialMarking, [])),

    % Test 1: Choose claim path
    MarkingClaimPath = apply_transition(InitialMarking, choose_claim_path, #{
        choice => claim,
        reason => <<"damaged_items">>
    }),

    % Verify claim path is taken, return path is not available
    ?assertMatch([_], maps:get(claim_path_selected, MarkingClaimPath, [])),
    ?assertEqual(undefined, maps:get(return_path_selected, MarkingClaimPath, undefined)),

    % Test 2: Starting fresh, choose return path
    InitialMarking2 = initialize_freight_delivered_workflow(decision, DeliveryData),
    MarkingReturnPath = apply_transition(InitialMarking2, choose_return_path, #{
        choice => return,
        reason => <<"product_not_as_described">>
    }),

    % Verify return path is taken, claim path is not available
    ?assertMatch([_], maps:get(return_path_selected, MarkingReturnPath, [])),
    ?assertEqual(undefined, maps:get(claim_path_selected, MarkingReturnPath, undefined)),

    % Test 3: Verify mutual exclusion - cannot have both active
    % Once a path is chosen, the other should be blocked
    MarkingClaimBlocked = apply_transition(MarkingClaimPath, validate_exclusivity, #{
        current_path => claim,
        blocked_paths => [return]
    }),

    ?assertMatch([#{blocked_path := return}],
                 maps:get(path_enforcement, MarkingClaimBlocked, [])).

%%====================================================================
%%% Test Cases - Workflow Specification Tests
%%====================================================================

%% @doc Test workflow specification is valid
test_workflow_spec_valid() ->
    Spec = get_freight_delivered_spec(),

    % Verify required spec fields
    ?assert(maps:is_key(workflow_id, Spec)),
    ?assert(maps:is_key(workflow_name, Spec)),
    ?assert(maps:is_key(places, Spec)),
    ?assert(maps:is_key(transitions, Spec)),
    ?assert(maps:is_key(initial_marking, Spec)),

    % Verify places are non-empty
    Places = maps:get(places, Spec),
    ?assert(length(Places) > 0),

    % Verify required places exist
    ?assert(lists:member(freight_delivered, Places)),
    ?assert(lists:member(claim_pending, Places)),
    ?assert(lists:member(return_pending, Places)),
    ?assert(lists:member(claim_approved, Places)),
    ?assert(lists:member(claim_rejected, Places)),
    ?assert(lists:member(return_approved, Places)),
    ?assert(lists:member(return_rejected, Places)),

    % Verify transitions are non-empty
    Transitions = maps:get(transitions, Spec),
    ?assert(length(Transitions) > 0),

    % Verify required transitions exist
    ?assert(lists:member(submit_claim, Transitions)),
    ?assert(lists:member(submit_return, Transitions)),
    ?assert(lists:member(authorize_claim, Transitions)),
    ?assert(lists:member(authorize_return, Transitions)),
    ?assert(lists:member(start_deadline_timer, Transitions)),
    ?assert(lists:member(deadline_expired, Transitions)),

    % Verify patterns used
    PatternsUsed = maps:get(patterns_used, Spec, []),
    ?assert(lists:member(exclusive_choice, PatternsUsed)),
    ?assert(lists:member(deferred_choice, PatternsUsed)),
    ?assert(lists:member(cancelation, PatternsUsed)),

    % Verify initial marking
    InitialMarking = maps:get(initial_marking, Spec),
    ?assert(is_map(InitialMarking)),
    ?assert(maps:is_key(freight_delivered, InitialMarking)),

    % Verify spec version
    ?assert(maps:is_key(version, Spec)),
    ?assertMatch(<<"1.", _/binary>>, maps:get(version, Spec)).

%%====================================================================
%%% Internal Helper Functions
%%====================================================================

%% @private
%% @doc Get the freight delivered workflow specification
-spec get_freight_delivered_spec() -> map().
get_freight_delivered_spec() ->
    #{
        workflow_id => <<"freight_delivered">>,
        workflow_name => <<"Freight Delivered Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Post-delivery claims and returns processing">>,
        places => [
            freight_delivered,
            exclusive_choice_point,
            claim_path_selected,
            return_path_selected,
            claim_pending,
            claim_review,
            claim_approved,
            claim_rejected,
            claim_cancelled,
            claim_completed,
            claim_closed,
            return_pending,
            return_review,
            return_approved,
            return_rejected,
            return_cancelled,
            return_completed,
            return_closed,
            return_label_generated,
            return_notification_sent,
            timer_active,
            timer_stopped,
            timer_expired,
            'end'
        ],
        transitions => [
            freight_delivery_complete,
            choose_claim_path,
            choose_return_path,
            submit_claim,
            submit_return,
            authorize_claim,
            authorize_return,
            start_deadline_timer,
            deadline_expired,
            process_refund,
            generate_return_label,
            send_notification,
            validate_exclusivity,
            complete_claim,
            complete_return,
            close_workflow
        ],
        initial_marking => #{
            freight_delivered => [delivery_token]
        },
        patterns_used => [
            basic_sequential,
            exclusive_choice,
            deferred_choice,
            cancelation,
            discriminator
        ]
    }.

%% @private
%% @doc Initialize workflow with specific data type
-spec initialize_freight_delivered_workflow(claim | return | decision, map()) -> map().
initialize_freight_delivered_workflow(Type, Data) ->
    BaseMarking = #{
        freight_delivered => [delivery_complete],
        exclusive_choice_point => [choice_token]
    },

    case Type of
        claim ->
            BaseMarking#{
                claim_data => Data,
                claim_path_available => true
            };
        return ->
            BaseMarking#{
                return_data => Data,
                return_path_available => true
            };
        decision ->
            BaseMarking#{
                delivery_data => Data,
                claim_path_available => true,
                return_path_available => true
            }
    end.

%% @private
%% @doc Apply a transition to the marking (simulation)
-spec apply_transition(map(), atom(), map()) -> map().
apply_transition(Marking, Transition, Data) ->
    case Transition of
        submit_claim ->
            ClaimData = maps:get(claim_data, Data, #{}),
            Marking#{
                claim_pending => [ClaimData#{status => pending}],
                exclusive_choice_point => []
            };

        authorize_claim ->
            Decision = maps:get(decision, Data),
            ClaimPending = hd(maps:get(claim_pending, Marking, [#{}])),
            ClaimData = maps:get(claim_data, Marking, #{}),

            case Decision of
                approved ->
                    Marking#{
                        claim_pending => [],
                        claim_approved => [ClaimData#{
                            status => approved,
                            authorized_amount => maps:get(approved_amount, Data),
                            authorized_by => maps:get(authorized_by, Data)
                        }],
                        claim_completed => [completion_token]
                    };
                rejected ->
                    Marking#{
                        claim_pending => [],
                        claim_rejected => [ClaimData#{
                            status => rejected,
                            rejection_reason => maps:get(rejection_reason, Data),
                            authorized_by => maps:get(authorized_by, Data)
                        }],
                        claim_closed => [closed_token]
                    }
            end;

        submit_return ->
            ReturnData = maps:get(return_data, Data, #{}),
            Marking#{
                return_pending => [ReturnData#{status => pending}],
                exclusive_choice_point => []
            };

        authorize_return ->
            Decision = maps:get(decision, Data),
            ReturnPending = hd(maps:get(return_pending, Marking, [#{}])),
            ReturnData = maps:get(return_data, Marking, #{}),

            case Decision of
                approved ->
                    Marking#{
                        return_pending => [],
                        return_approved => [ReturnData#{
                            status => approved,
                            refund_amount => maps:get(refund_amount, Data),
                            refund_method => maps:get(refund_method, Data)
                        }],
                        return_label_generated => [label_token],
                        return_completed => [completion_token]
                    };
                rejected ->
                    Marking#{
                        return_pending => [],
                        return_rejected => [ReturnData#{
                            status => rejected,
                            rejection_reason => maps:get(rejection_reason, Data)
                        }],
                        return_notification_sent => [notification_token],
                        return_closed => [closed_token]
                    }
            end;

        start_deadline_timer ->
            Marking#{
                timer_active => [Data#{timer_status => active}]
            };

        deadline_expired ->
            ClaimData = hd(maps:get(claim_pending, Marking, [#{}])),
            Marking#{
                claim_pending => [],
                claim_cancelled => [ClaimData#{
                    status => cancelled,
                    cancellation_reason => maps:get(expiry_reason, Data)
                }],
                timer_active => [],
                timer_stopped => [#{timer_status => stopped}]
            };

        choose_claim_path ->
            Marking#{
                exclusive_choice_point => [],
                claim_path_selected => [Data#{selected_at => erlang:system_time(second)}],
                return_path_available => false
            };

        choose_return_path ->
            Marking#{
                exclusive_choice_point => [],
                return_path_selected => [Data#{selected_at => erlang:system_time(second)}],
                claim_path_available => false
            };

        validate_exclusivity ->
            Marking#{
                path_enforcement => [#{
                    current_path => maps:get(current_path, Data),
                    blocked_paths => maps:get(blocked_paths, Data)
                }]
            };

        _ ->
            Marking
    end.
