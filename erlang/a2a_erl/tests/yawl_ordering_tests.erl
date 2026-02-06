%%%-------------------------------------------------------------------
%%% @doc
%%% Ordering (Purchase Order) Workflow Tests
%%%
%%% EUnit tests for the ordering/purchase order workflow example.
%%%
%%% Workflow Description:
%%% 1. PO Creation - Create new purchase order
%%% 2. PO Approval - Manager approval process
%%% 3. PO Modification - Allow modifications before approval
%%% 4. Delegation - Delegate approval to alternate approver
%%% 5. Rejection Path - Handle rejected POs
%%% 6. Timeout Cancellation - Auto-cancel after 3 days
%%%
%%% Patterns Used:
%%% - Sequence: Create -> Modify -> Approve -> Complete
%%% - Exclusive Choice: Approve vs Reject path
%%% - Cancellation After: Timeout triggers cancellation
%%% - Deferred Choice: Delegation option
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_ordering_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_ordering_test_() ->
    [
        {"Workflow specification is valid",
         fun test_workflow_spec_valid/0},
        {"Create and approve PO - normal flow",
         fun test_create_and_approve_po/0},
        {"PO timeout cancellation after 3 days",
         fun test_po_timeout_cancellation/0},
        {"Modify before approval",
         fun test_modify_before_approval/0},
        {"PO rejection path",
         fun test_po_rejection/0},
        {"Delegate approval",
         fun test_delegate_approval/0},
        {"Skip modification - optional modification",
         fun test_skip_modification/0},
        {"Exactly 3-day boundary approval",
         fun test_exactly_3_days_boundary/0},
        {"Multiple modifications before approval",
         fun test_multiple_modifications/0},
        {"Pattern structure completeness",
         fun test_pattern_structure_completeness/0}
    ].

%%====================================================================
%%% Test Cases
%%====================================================================

%% @doc Test that workflow specification is valid and complete
test_workflow_spec_valid() ->
    Spec = ordering_workflow:get_workflow_spec(),
    ?assert(maps:is_key(workflow_id, Spec)),
    ?assert(maps:is_key(workflow_name, Spec)),
    ?assert(maps:is_key(places, Spec)),
    ?assert(maps:is_key(transitions, Spec)),
    ?assert(maps:is_key(initial_marking, Spec)),
    ?assert(length(maps:get(places, Spec)) > 0),
    ?assert(length(maps:get(transitions, Spec)) > 0),
    % Verify workflow ID matches expected value
    ?assertEqual(<<"ordering">>, maps:get(workflow_id, Spec)),
    % Verify patterns used includes expected patterns
    PatternsUsed = maps:get(patterns_used, Spec),
    ?assert(lists:member(basic_sequential, PatternsUsed)),
    ?assert(lists:member(exclusive_choice, PatternsUsed)).

%% @doc Test normal approval flow - PO approved within timeout
test_create_and_approve_po() ->
    Result = ordering_workflow:simulate_normal_approval(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify simulation completed with end place marked
    EndTokens = maps:get('end', Marking, []),
    ?assert(length(EndTokens) > 0),
    % Verify po_confirmed place has tokens (approved path)
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0),
    % Verify po_timeout is empty (no timeout occurred)
    TimeoutTokens = maps:get(po_timeout, Marking, []),
    ?assertEqual([], TimeoutTokens).

%% @doc Test 3-day timeout triggering cancellation
test_po_timeout_cancellation() ->
    Result = ordering_workflow:simulate_timeout_cancellation(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify end place has cancelled token
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(cancelled, EndTokens)),
    % Verify po_timeout place has tokens
    TimeoutTokens = maps:get(po_timeout, Marking, []),
    ?assert(length(TimeoutTokens) > 0),
    % Verify po_confirmed is empty (not approved)
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assertEqual([], ConfirmedTokens).

%% @doc Test modification flow before approval
test_modify_before_approval() ->
    Result = ordering_workflow:simulate_modify_before_approval(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify po_modified place was visited
    ModifiedTokens = maps:get(po_modified, Marking, []),
    ?assert(length(ModifiedTokens) > 0),
    % Verify workflow completed successfully
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(completed, EndTokens)),
    % Verify po_confirmed has tokens
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0).

%% @doc Test PO rejection path
test_po_rejection() ->
    Result = ordering_workflow:simulate_po_rejection(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify po_rejected place has tokens
    RejectedTokens = maps:get(po_rejected, Marking, []),
    ?assert(length(RejectedTokens) > 0),
    % Verify po_approved is empty (not approved)
    ApprovedTokens = maps:get(po_approved, Marking, []),
    ?assertEqual([], ApprovedTokens),
    % Verify po_confirmed is empty (not confirmed)
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assertEqual([], ConfirmedTokens).

%% @doc Test delegation approval scenario
test_delegate_approval() ->
    Result = ordering_workflow:simulate_delegate_approval(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify workflow completed successfully
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(completed, EndTokens)),
    % Verify po_approved has delegated approval
    ApprovedTokens = maps:get(po_approved, Marking, []),
    ?assert(length(ApprovedTokens) > 0),
    % Verify po_confirmed has tokens
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0).

%% @doc Test skipping modification (optional modification skipped)
test_skip_modification() ->
    Result = ordering_workflow:simulate_skip_modification(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify workflow completed successfully
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(completed, EndTokens)),
    % Verify po_confirmed has tokens (approved without modification)
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0),
    % Verify po_modified is empty (modification was skipped)
    ModifiedTokens = maps:get(po_modified, Marking, []),
    ?assertEqual([], ModifiedTokens).

%% @doc Test exactly 3-day boundary approval (should still be allowed)
test_exactly_3_days_boundary() ->
    Result = ordering_workflow:simulate_exactly_3_days(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify workflow completed successfully (boundary allows approval)
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(completed, EndTokens)),
    % Verify po_confirmed has tokens
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0),
    % Verify no timeout occurred
    TimeoutTokens = maps:get(po_timeout, Marking, []),
    ?assertEqual([], TimeoutTokens).

%% @doc Test multiple modifications before final approval
test_multiple_modifications() ->
    Result = ordering_workflow:simulate_multiple_modifications(),
    ?assertMatch({ok, Marking}, Result),
    {ok, Marking} = Result,
    % Verify workflow completed successfully after multiple modifications
    EndTokens = maps:get('end', Marking, []),
    ?assert(lists:member(completed, EndTokens)),
    % Verify po_confirmed has tokens
    ConfirmedTokens = maps:get(po_confirmed, Marking, []),
    ?assert(length(ConfirmedTokens) > 0),
    % Verify po_approved was reached after modifications
    ApprovedTokens = maps:get(po_approved, Marking, []),
    ?assert(length(ApprovedTokens) > 0).

%% @doc Test pattern structure completeness
test_pattern_structure_completeness() ->
    Places = ordering_workflow:place_lst(),
    Transitions = ordering_workflow:trsn_lst(),

    % Verify all places and transitions are non-empty
    ?assert(length(Places) > 0),
    ?assert(length(Transitions) > 0),

    % Verify expected places exist
    ?assert(lists:member(start, Places)),
    ?assert(lists:member(po_approval_pending, Places)),
    ?assert(lists:member(po_approved, Places)),
    ?assert(lists:member(po_modified, Places)),
    ?assert(lists:member(po_timeout, Places)),
    ?assert(lists:member(po_confirmed, Places)),
    ?assert(lists:member(po_rejected, Places)),
    ?assert(lists:member('end', Places)),

    % Verify expected transitions exist
    ?assert(lists:member(create_purchase_order, Transitions)),
    ?assert(lists:member(approve_po, Transitions)),
    ?assert(lists:member(modify_po, Transitions)),
    ?assert(lists:member(skip_modification, Transitions)),
    ?assert(lists:member(confirm_po, Transitions)),
    ?assert(lists:member(order_timeout_timer, Transitions)),
    ?assert(lists:member(reject_po, Transitions)),
    ?assert(lists:member(cancel_workflow, Transitions)),
    ?assert(lists:member(complete, Transitions)),

    % Verify each transition has preset and postset
    ?assert(lists:all(fun(T) -> length(ordering_workflow:preset(T)) > 0 end, Transitions)),
    ?assert(lists:all(fun(T) -> length(ordering_workflow:postset(T)) > 0 end, Transitions)).

%%====================================================================
%%% Additional Validation Tests
%%====================================================================

%% @doc Test that timeout is exactly 3 days (259200000 ms)
timeout_value_test_() ->
    [
        {"Timeout is 3 days in milliseconds", fun() ->
            % 3 days = 3 * 24 * 60 * 60 * 1000 = 259200000 ms
            ExpectedTimeout = 3 * 24 * 60 * 60 * 1000,
            Spec = ordering_workflow:get_workflow_spec(),
            BusinessRules = maps:get(business_rules, Spec, []),
            TimeoutRule = lists:keyfind(timeout, 1, BusinessRules),
            ?assertMatch({timeout, 3, days}, TimeoutRule)
        end}
    ].

%% @doc test workflow creation with PO data
create_workflow_test_() ->
    [
        {"Create workflow with valid PO data", fun() ->
            POData = #{
                po_id => <<"PO-TEST-001">>,
                supplier_id => <<"SUPP-TEST">>,
                items => [#{item_id => <<"ITEM-TEST">>, quantity => 10, unit_price => 100.00}],
                total_amount => 1000.00,
                requested_by => <<"test_user">>
            },
            Result = ordering_workflow:create_workflow(POData),
            ?assertMatch({ok, _}, Result),
            {ok, Workflow} = Result,
            ?assertEqual(<<"PO-TEST-001">>, maps:get(workflow_id, Workflow))
        end},
        {"Create workflow with default PO ID", fun() ->
            POData = #{
                supplier_id => <<"SUPP-TEST">>,
                items => [],
                total_amount => 0.0
            },
            Result = ordering_workflow:create_workflow(POData),
            ?assertMatch({ok, _}, Result),
            {ok, Workflow} = Result,
            ?assertEqual(<<"ordering">>, maps:get(workflow_id, Workflow))
        end}
    ].

%% @doc Test transition enablement conditions
transition_enablement_test_() ->
    [
        {"approve_po enabled when not timed out", fun() ->
            Mode = #{
                po_approval_pending => [{pending, erlang:system_time(millisecond) + 1000000}]
            },
            ?assert(ordering_workflow:is_enabled(approve_po, Mode, []))
        end},
        {"approve_po disabled when timed out", fun() ->
            Mode = #{
                po_approval_pending => [{pending, erlang:system_time(millisecond) - 1000}]
            },
            ?assertNot(ordering_workflow:is_enabled(approve_po, Mode, []))
        end},
        {"order_timeout_timer enabled when timed out", fun() ->
            Mode = #{
                po_approval_pending => [{pending, erlang:system_time(millisecond) - 1000}]
            },
            ?assert(ordering_workflow:is_enabled(order_timeout_timer, Mode, []))
        end},
        {"modify_po enabled when not timed out", fun() ->
            Mode = #{
                po_approval_pending => [{pending, erlang:system_time(millisecond) + 1000000}]
            },
            ?assert(ordering_workflow:is_enabled(modify_po, Mode, []))
        end}
    ].

%%====================================================================
%%% Setup and Teardown
%%====================================================================

setup() ->
    % Ensure yawl_orchestrator is available if needed
    case whereis(yawl_orchestrator) of
        undefined ->
            {ok, Pid} = yawl_orchestrator:start_link(),
            Pid;
        Pid ->
            Pid
    end.

cleanup(_Pid) ->
    ok.

%%====================================================================
%%% Test Suites
%%====================================================================

%% @doc Full workflow suite testing all paths
ordering_workflow_comprehensive_suite_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        [
            fun(_) -> test_create_and_approve_po() end,
            fun(_) -> test_po_timeout_cancellation() end,
            fun(_) -> test_modify_before_approval() end,
            fun(_) -> test_po_rejection() end,
            fun(_) -> test_delegate_approval() end,
            fun(_) -> test_skip_modification() end,
            fun(_) -> test_exactly_3_days_boundary() end,
            fun(_) -> test_multiple_modifications() end
        ]
    }.

%% @doc Suite for testing specification and structure
ordering_structure_suite_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        [
            fun(_) -> test_workflow_spec_valid() end,
            fun(_) -> test_pattern_structure_completeness() end
        ]
    }.
