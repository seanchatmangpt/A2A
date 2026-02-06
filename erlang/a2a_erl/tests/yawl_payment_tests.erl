%%%-------------------------------------------------------------------
%%% @doc
%%% Payment Workflow Tests
%%%
%%% EUnit tests for the payment workflow example covering:
%%% - Pre-paid invoice path
%%% - Post-paid payment path
%%% - Debit adjustment (balance > 0, underpayment)
%%% - Credit adjustment (balance < 0, overcharge)
%%% - Payment order approval
%%% - Payment order rejection
%%% - Invoice not required (skip)
%%% - Workflow spec validation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_payment_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%%% Test Generator
%%%====================================================================

yawl_payment_test_() ->
    [
        {"Prepaid invoice flow",
         fun test_prepaid_invoice_flow/0},
        {"Postpaid payment flow",
         fun test_postpaid_payment_flow/0},
        {"Debit adjustment",
         fun test_debit_adjustment/0},
        {"Credit adjustment",
         fun test_credit_adjustment/0},
        {"Payment order approval",
         fun test_payment_order_approval/0},
        {"Payment order rejection",
         fun test_payment_order_rejection/0},
        {"Invoice not required",
         fun test_invoice_not_required/0},
        {"Workflow spec valid",
         fun test_workflow_spec_valid/0}
    ].

%%====================================================================
%%% Test Cases - Prepaid/Postpaid Paths
%%====================================================================

%% @doc Test prepaid invoice flow - payment received before service delivery
test_prepaid_invoice_flow() ->
    %% Prepaid scenario: Customer pays upfront, invoice generated immediately
    PaymentData = #{
        payment_type => prepaid,
        customer_id => <<"customer_001">>,
        amount => 50000,  % $500.00 in cents
        currency => <<"USD">>,
        payment_method => credit_card,
        invoice_required => true,
        service_id => <<"service_monthly">>
    },

    %% Simulate the prepaid flow through payment workflow
    Result = simulate_prepaid_flow(PaymentData),
    ?assertMatch({ok, #{status := completed}}, Result),

    {ok, ResultMap} = Result,
    %% Verify invoice was generated
    ?assert(maps:is_key(invoice_id, ResultMap)),
    ?assert(maps:is_key(payment_confirmed, ResultMap)),
    %% Verify balance is zero (prepaid = no balance due)
    ?assertEqual(0, maps:get(balance, ResultMap, 0)),

    %% Verify the flow places were visited correctly
    ?assertMatch(#{payment_received := [_], invoice_generated := [_]}, ResultMap),

    ok.

%% @doc Test postpaid payment path - service delivered before payment
test_postpaid_payment_flow() ->
    %% Postpaid scenario: Service delivered first, payment collected after
    PaymentData = #{
        payment_type => postpaid,
        customer_id => <<"customer_002">>,
        amount => 75000,  % $750.00 in cents
        currency => <<"USD">>,
        payment_method => ach,
        invoice_required => true,
        service_id => <<"service_onetime">>,
        billing_cycle => monthly
    },

    %% Simulate the postpaid flow through payment workflow
    Result = simulate_postpaid_flow(PaymentData),
    ?assertMatch({ok, #{status := completed}}, Result),

    {ok, ResultMap} = Result,
    %% Verify invoice was generated before payment
    ?assert(maps:is_key(invoice_id, ResultMap)),
    ?assert(maps:is_key(payment_pending, ResultMap)),
    %% Verify final payment collected
    ?assert(maps:is_key(payment_confirmed, ResultMap)),

    %% Verify the flow places for postpaid
    ?assertMatch(#{service_delivered := [_], invoice_generated := [_], payment_collected := [_]}, ResultMap),

    ok.

%%====================================================================
%%% Test Cases - Balance Adjustments
%%====================================================================

%% @doc Test debit adjustment - positive balance (underpayment scenario)
test_debit_adjustment() ->
    %% Debit adjustment: Customer underpaid, has positive balance due
    PaymentData = #{
        payment_type => postpaid,
        customer_id => <<"customer_003">>,
        amount => 100000,  % $1000.00 billed
        currency => <<"USD">>,
        amount_paid => 75000,  % $750.00 paid (underpayment)
        adjustment_type => debit,
        invoice_required => true
    },

    Result = simulate_adjustment_flow(PaymentData),
    ?assertMatch({ok, #{status := completed, adjustment := debit}}, Result),

    {ok, ResultMap} = Result,
    %% Balance should be positive (amount owed)
    Balance = maps:get(balance, ResultMap),
    ?assert(Balance > 0),
    ?assertEqual(25000, Balance),  % $250.00 remaining balance

    %% Verify debit adjustment recorded
    ?assert(maps:is_key(debit_recorded, ResultMap)),
    ?assert(maps:is_key(notify_balance_due, ResultMap)),

    ok.

%% @doc Test credit adjustment - negative balance (overcharge scenario)
test_credit_adjustment() ->
    %% Credit adjustment: Customer overpaid, has credit balance
    PaymentData = #{
        payment_type => prepaid,
        customer_id => <<"customer_004">>,
        amount => 50000,  % $500.00 expected
        currency => <<"USD">>,
        amount_paid => 75000,  % $750.00 paid (overpayment)
        adjustment_type => credit,
        invoice_required => true
    },

    Result = simulate_adjustment_flow(PaymentData),
    ?assertMatch({ok, #{status := completed, adjustment := credit}}, Result),

    {ok, ResultMap} = Result,
    %% Balance should be negative (credit owed to customer)
    Balance = maps:get(balance, ResultMap),
    ?assert(Balance < 0),
    ?assertEqual(-25000, Balance),  % -$250.00 credit

    %% Verify credit adjustment recorded
    ?assert(maps:is_key(credit_recorded, ResultMap)),
    ?assert(maps:is_key(credit_applied, ResultMap)),
    ?assert(maps:is_key(notify_credit_issued, ResultMap)),

    ok.

%%====================================================================
%%% Test Cases - Approval/Rejection
%%====================================================================

%% @doc Test payment order approval success
test_payment_order_approval() ->
    %% High-value payment requiring approval
    PaymentData = #{
        payment_type => postpaid,
        customer_id => <<"customer_005">>,
        amount => 500000,  % $5000.00 - requires approval
        currency => <<"USD">>,
        requires_approval => true,
        approver_id => <<"manager_001">>,
        approval_threshold => 100000  % $1000.00 threshold
    },

    Result = simulate_approval_flow(PaymentData, approve),
    ?assertMatch({ok, #{status := approved}}, Result),

    {ok, ResultMap} = Result,
    %% Verify approval recorded
    ?assert(maps:is_key(approval_requested, ResultMap)),
    ?assert(maps:is_key(approval_granted, ResultMap)),
    ?assertEqual(<<"manager_001">>, maps:get(approved_by, ResultMap)),
    ?assert(maps:is_key(approval_timestamp, ResultMap)),

    %% Payment proceeds after approval
    ?assert(maps:is_key(payment_processed, ResultMap)),

    ok.

%% @doc Test payment order rejection failure
test_payment_order_rejection() ->
    %% High-value payment that gets rejected
    PaymentData = #{
        payment_type => postpaid,
        customer_id => <<"customer_006">>,
        amount => 500000,  % $5000.00
        currency => <<"USD">>,
        requires_approval => true,
        approver_id => <<"manager_002">>,
        rejection_reason => <<"Insufficient budget allocation">>
    },

    Result = simulate_approval_flow(PaymentData, reject),
    ?assertMatch({ok, #{status := rejected}}, Result),

    {ok, ResultMap} = Result,
    %% Verify rejection recorded
    ?assert(maps:is_key(approval_requested, ResultMap)),
    ?assert(maps:is_key(approval_denied, ResultMap)),
    ?assertEqual(<<"manager_002">>, maps:get(rejected_by, ResultMap)),
    ?assertEqual(<<"Insufficient budget allocation">>,
                 maps:get(rejection_reason, ResultMap)),

    %% Verify notification sent
    ?assert(maps:is_key(rejection_notification_sent, ResultMap)),

    ok.

%%====================================================================
%%% Test Cases - Skip Invoice
%%====================================================================

%% @doc Test invoice not required - skip invoice generation
test_invoice_not_required() ->
    %% Small payment or auto-pay where invoice is not required
    PaymentData = #{
        payment_type => prepaid,
        customer_id => <<"customer_007">>,
        amount => 1000,  % $10.00 - below invoicing threshold
        currency => <<"USD">>,
        payment_method => apple_pay,
        invoice_required => false,
        auto_pay_enabled => true
    },

    Result = simulate_no_invoice_flow(PaymentData),
    ?assertMatch({ok, #{status := completed}}, Result),

    {ok, ResultMap} = Result,
    %% Verify invoice was NOT generated
    ?assertNot(maps:is_key(invoice_id, ResultMap)),
    ?assertNot(maps:is_key(invoice_generated, ResultMap)),

    %% But payment still processed
    ?assert(maps:is_key(payment_confirmed, ResultMap)),
    ?assert(maps:is_key(receipt_generated, ResultMap)),

    %% Verify flow skipped invoice generation
    ?assertMatch(#{payment_received := [_], receipt_issued := [_]}, ResultMap),

    ok.

%%====================================================================
%%% Test Cases - Spec Validation
%%====================================================================

%% @doc Test workflow specification is valid
test_workflow_spec_valid() ->
    Spec = payment_workflow:get_spec(),

    %% Verify required top-level fields
    ?assert(maps:is_key(workflow_id, Spec)),
    ?assert(maps:is_key(workflow_name, Spec)),
    ?assert(maps:is_key(places, Spec)),
    ?assert(maps:is_key(transitions, Spec)),
    ?assert(maps:is_key(initial_marking, Spec)),

    %% Verify workflow metadata
    ?assertEqual(<<"payment_workflow">>, maps:get(workflow_id, Spec)),
    ?assert(is_list(maps:get(places, Spec))),
    ?assert(is_list(maps:get(transitions, Spec))),

    %% Verify non-empty structure
    ?assert(length(maps:get(places, Spec)) > 0),
    ?assert(length(maps:get(transitions, Spec)) > 0),

    %% Verify places include payment-specific places
    Places = maps:get(places, Spec),
    ?assert(lists:member(payment_received, Places)),
    ?assert(lists:member(invoice_generated, Places)),
    ?assert(lists:member(approval_requested, Places)),

    %% Verify transitions include payment-specific transitions
    Transitions = maps:get(transitions, Spec),
    ?assert(lists:member(process_payment, Transitions)),
    ?assert(lists:member(generate_invoice, Transitions)),
    ?assert(lists:member(request_approval, Transitions)),

    %% Verify initial marking
    InitialMarking = maps:get(initial_marking, Spec),
    ?assert(is_map(InitialMarking)),
    ?assert(maps:is_key(start, InitialMarking)),

    %% Verify patterns used
    Patterns = maps:get(patterns_used, Spec, []),
    ?assert(lists:member(exclusive_choice, Patterns)),
    ?assert(lists:member(parallel_split, Patterns)),

    ok.

%%====================================================================
%%% Internal Helper Functions
%%====================================================================

%% @private
%% @doc Simulate prepaid payment flow
simulate_prepaid_flow(PaymentData) ->
    %% Prepaid flow: Payment -> Invoice -> Delivery (simplified)
    InitialMarking = #{
        start => [workflow_token],
        payment_pending => [PaymentData]
    },

    %% Fire transition sequence for prepaid flow
    Transitions = [
        receive_payment,
        validate_payment,
        generate_invoice,
        confirm_payment,
        complete
    ],

    fire_transition_sequence(InitialMarking, Transitions, PaymentData).

%% @private
%% @doc Simulate postpaid payment flow
simulate_postpaid_flow(PaymentData) ->
    %% Postpaid flow: Service -> Invoice -> Payment
    InitialMarking = #{
        start => [workflow_token],
        service_pending => [PaymentData]
    },

    %% Fire transition sequence for postpaid flow
    Transitions = [
        deliver_service,
        calculate_amount,
        generate_invoice,
        send_invoice,
        receive_payment,
        validate_payment,
        confirm_payment,
        complete
    ],

    fire_transition_sequence(InitialMarking, Transitions, PaymentData).

%% @private
%% @doc Simulate adjustment flow (debit or credit)
simulate_adjustment_flow(PaymentData) ->
    InitialMarking = #{
        start => [workflow_token],
        payment_processed => [PaymentData]
    },

    AdjustmentType = maps:get(adjustment_type, PaymentData),

    Transitions = case AdjustmentType of
        debit ->
            [calculate_balance, detect_underpayment, record_debit,
             notify_balance_due, complete];
        credit ->
            [calculate_balance, detect_overpayment, record_credit,
             apply_credit, notify_credit_issued, complete]
    end,

    fire_transition_sequence(InitialMarking, Transitions, PaymentData).

%% @private
%% @doc Simulate approval flow
simulate_approval_flow(PaymentData, Decision) ->
    InitialMarking = #{
        start => [workflow_token],
        payment_pending => [PaymentData]
    },

    Transitions = [
        receive_payment,
        check_approval_required,
        request_approval,
        Decision,  % approve or reject
        complete
    ],

    fire_transition_sequence(InitialMarking, Transitions, PaymentData).

%% @private
%% @doc Simulate flow without invoice
simulate_no_invoice_flow(PaymentData) ->
    InitialMarking = #{
        start => [workflow_token],
        payment_pending => [PaymentData]
    },

    Transitions = [
        receive_payment,
        check_invoice_required,
        skip_invoice,
        process_payment,
        generate_receipt,
        confirm_payment,
        complete
    ],

    fire_transition_sequence(InitialMarking, Transitions, PaymentData).

%% @private
%% @doc Fire a sequence of transitions for simulation
fire_transition_sequence(InitialMarking, Transitions, PaymentData) ->
    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        Preset = get_preset(Transition),
        Mode = build_mode(Preset, CurrentMarking),
        case is_transition_enabled(Transition, Mode, PaymentData) of
            true ->
                NewMarking = fire_transition(Transition, Mode, CurrentMarking, PaymentData),
                {ok, NewMarking};
            false ->
                {ok, CurrentMarking}
        end
    end, {ok, InitialMarking}, Transitions).

%% @private
%% @doc Get preset places for a transition
get_preset(receive_payment) -> [start, payment_pending];
get_preset(validate_payment) -> [payment_received];
get_preset(generate_invoice) -> [payment_validated];
get_preset(confirm_payment) -> [invoice_generated];
get_preset(complete) -> [payment_confirmed];
get_preset(deliver_service) -> [start];
get_preset(calculate_amount) -> [service_delivered];
get_preset(send_invoice) -> [invoice_generated];
get_preset(calculate_balance) -> [payment_processed];
get_preset(detect_underpayment) -> [balance_calculated];
get_preset(detect_overpayment) -> [balance_calculated];
get_preset(record_debit) -> [underpayment_detected];
get_preset(record_credit) -> [overpayment_detected];
get_preset(notify_balance_due) -> [debit_recorded];
get_preset(apply_credit) -> [credit_recorded];
get_preset(notify_credit_issued) -> [credit_applied];
get_preset(check_approval_required) -> [payment_received];
get_preset(request_approval) -> [approval_required];
get_preset(approve) -> [approval_requested];
get_preset(reject) -> [approval_requested];
get_preset(check_invoice_required) -> [payment_received];
get_preset(skip_invoice) -> [invoice_not_required];
get_preset(process_payment) -> [invoice_skipped];
get_preset(generate_receipt) -> [payment_received];
get_preset(_Transition) -> [].

%% @private
%% @doc Build mode map from preset and marking
build_mode(Preset, Marking) ->
    lists:foldl(fun(Place, Acc) ->
        Tokens = maps:get(Place, Marking, []),
        Acc#{Place => Tokens}
    end, #{}, Preset).

%% @private
%% @doc Check if transition is enabled
is_transition_enabled(receive_payment, Mode, _Data) ->
    has_token(start, Mode) orelse has_token(payment_pending, Mode);
is_transition_enabled(validate_payment, Mode, _Data) ->
    has_token(payment_validated, Mode) orelse has_token(payment_received, Mode);
is_transition_enabled(generate_invoice, Mode, _Data) ->
    has_token(payment_validated, Mode);
is_transition_enabled(confirm_payment, Mode, _Data) ->
    has_token(invoice_generated, Mode) orelse has_token(payment_received, Mode);
is_transition_enabled(complete, _Mode, _Data) ->
    true;
is_transition_enabled(deliver_service, Mode, _Data) ->
    has_token(start, Mode);
is_transition_enabled(calculate_amount, Mode, _Data) ->
    has_token(service_delivered, Mode);
is_transition_enabled(send_invoice, Mode, _Data) ->
    has_token(invoice_generated, Mode);
is_transition_enabled(calculate_balance, Mode, _Data) ->
    has_token(payment_processed, Mode);
is_transition_enabled(detect_underpayment, Mode, Data) ->
    has_token(balance_calculated, Mode) andalso (maps:get(amount, Data, 0) > maps:get(amount_paid, Data, 0));
is_transition_enabled(detect_overpayment, Mode, Data) ->
    has_token(balance_calculated, Mode) andalso (maps:get(amount_paid, Data, 0) > maps:get(amount, Data, 0));
is_transition_enabled(record_debit, Mode, _Data) ->
    has_token(underpayment_detected, Mode);
is_transition_enabled(record_credit, Mode, _Data) ->
    has_token(overpayment_detected, Mode);
is_transition_enabled(notify_balance_due, Mode, _Data) ->
    has_token(debit_recorded, Mode);
is_transition_enabled(apply_credit, Mode, _Data) ->
    has_token(credit_recorded, Mode);
is_transition_enabled(notify_credit_issued, Mode, _Data) ->
    has_token(credit_applied, Mode);
is_transition_enabled(check_approval_required, Mode, Data) ->
    has_token(payment_received, Mode) andalso maps:get(requires_approval, Data, false);
is_transition_enabled(request_approval, Mode, _Data) ->
    has_token(approval_required, Mode);
is_transition_enabled(approve, Mode, _Data) ->
    has_token(approval_requested, Mode);
is_transition_enabled(reject, Mode, _Data) ->
    has_token(approval_requested, Mode);
is_transition_enabled(check_invoice_required, Mode, Data) ->
    has_token(payment_received, Mode) andalso not maps:get(invoice_required, Data, true);
is_transition_enabled(skip_invoice, Mode, _Data) ->
    has_token(invoice_not_required, Mode);
is_transition_enabled(process_payment, Mode, _Data) ->
    has_token(invoice_skipped, Mode);
is_transition_enabled(generate_receipt, Mode, _Data) ->
    has_token(payment_received, Mode);
is_transition_enabled(_Transition, _Mode, _Data) ->
    false.

%% @private
%% @doc Fire transition and produce new marking
fire_transition(receive_payment, _Mode, Marking, Data) ->
    Amount = maps:get(amount, Data, 0),
    PaymentType = maps:get(payment_type, Data, unknown),
    Marking#{
        payment_received => [{payment, Data}],
        payment_validated => [validated],
        amount => Amount,
        payment_type => PaymentType
    };
fire_transition(validate_payment, _Mode, Marking, Data) ->
    PaymentType = maps:get(payment_type, Data, postpaid),
    case PaymentType of
        prepaid ->
            Marking#{payment_validated => [prepayment_valid]};
        postpaid ->
            Marking#{payment_validated => [postpayment_valid]}
    end;
fire_transition(generate_invoice, _Mode, Marking, _Data) ->
    InvoiceId = <<"invoice_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Marking#{
        invoice_generated => [InvoiceId],
        invoice_id => InvoiceId
    };
fire_transition(confirm_payment, _Mode, Marking, _Data) ->
    Marking#{
        payment_confirmed => [confirmed],
        status => completed,
        balance => 0
    };
fire_transition(complete, _Mode, Marking, _Data) ->
    Marking#{'end' => [completed]};
fire_transition(deliver_service, _Mode, Marking, Data) ->
    Marking#{
        service_delivered => [delivered],
        service_id => maps:get(service_id, Data)
    };
fire_transition(calculate_amount, _Mode, Marking, Data) ->
    Marking#{
        amount_calculated => [calculated],
        amount => maps:get(amount, Data, 0)
    };
fire_transition(send_invoice, _Mode, Marking, _Data) ->
    Marking#{
        invoice_sent => [sent],
        payment_pending => [awaiting_payment]
    };
fire_transition(calculate_balance, _Mode, Marking, Data) ->
    Amount = maps:get(amount, Data, 0),
    AmountPaid = maps:get(amount_paid, Data, 0),
    Balance = AmountPaid - Amount,
    Marking#{
        balance_calculated => [calculated],
        balance => Balance,
        amount => Amount,
        amount_paid => AmountPaid
    };
fire_transition(detect_underpayment, _Mode, Marking, _Data) ->
    Marking#{underpayment_detected => [detected]};
fire_transition(detect_overpayment, _Mode, Marking, _Data) ->
    Marking#{overpayment_detected => [detected]};
fire_transition(record_debit, _Mode, Marking, _Data) ->
    Marking#{debit_recorded => [recorded], adjustment => debit};
fire_transition(record_credit, _Mode, Marking, _Data) ->
    Marking#{credit_recorded => [recorded], adjustment => credit};
fire_transition(notify_balance_due, _Mode, Marking, _Data) ->
    Marking#{notify_balance_due => [notified], status => completed};
fire_transition(apply_credit, _Mode, Marking, _Data) ->
    Marking#{credit_applied => [applied]};
fire_transition(notify_credit_issued, _Mode, Marking, _Data) ->
    Marking#{notify_credit_issued => [notified], status => completed};
fire_transition(check_approval_required, _Mode, Marking, _Data) ->
    Marking#{approval_required => [required]};
fire_transition(request_approval, _Mode, Marking, Data) ->
    Marking#{
        approval_requested => [requested],
        approver_id => maps:get(approver_id, Data)
    };
fire_transition(approve, _Mode, Marking, Data) ->
    Marking#{
        approval_granted => [granted],
        status => approved,
        approved_by => maps:get(approver_id, Data),
        approval_timestamp => erlang:system_time(millisecond),
        payment_processed => [processed]
    };
fire_transition(reject, _Mode, Marking, Data) ->
    Marking#{
        approval_denied => [denied],
        status => rejected,
        rejected_by => maps:get(approver_id, Data),
        rejection_reason => maps:get(rejection_reason, Data),
        rejection_notification_sent => [sent]
    };
fire_transition(check_invoice_required, _Mode, Marking, _Data) ->
    Marking#{invoice_not_required => [not_required]};
fire_transition(skip_invoice, _Mode, Marking, _Data) ->
    Marking#{invoice_skipped => [skipped]};
fire_transition(process_payment, _Mode, Marking, _Data) ->
    Marking#{payment_processed => [processed]};
fire_transition(generate_receipt, _Mode, Marking, _Data) ->
    ReceiptId = <<"receipt_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Marking#{
        receipt_issued => [ReceiptId],
        receipt_id => ReceiptId
    };
fire_transition(_Transition, _Mode, Marking, _Data) ->
    Marking.

%% @private
%% @doc Check if place has tokens
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        _ -> true
    end.
