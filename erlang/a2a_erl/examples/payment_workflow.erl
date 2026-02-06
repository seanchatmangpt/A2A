%%%-------------------------------------------------------------------
%%% @doc
%%% Payment Workflow - YAWL Pattern Example
%%%
%%% This module implements a payment workflow based on the
%%% YAWL reference specification from the order fulfillment example.
%%%
%%% Workflow Description:
%%% 1. Invoice Required Check - Determine if shipment invoice is needed
%%% 2. Payment Order Creation - Create payment order based on PrePaid status
%%% 3. Invoice Issuance - Issue shipment and freight invoices
%%% 4. Payment Approval - Approve payment order
%%% 5. Payment Processing - Process the payment
%%% 6. Balance Adjustment - Issue debit or credit adjustment based on balance
%%%
%%% Patterns Used:
%%% - Sequence: Linear flow through payment steps
%%% - Exclusive Choice: InvoiceRequired (yes/no), PrePaid (yes/no)
%%% - Exclusive Choice: Debit adjustment (balance > 0) vs Credit adjustment (balance < 0)
%%% - Parallel Split: Invoice and remittance advice can be issued in parallel
%%% - Simple Merge: Converge parallel paths
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(payment_workflow).
-author("A2A Team").

%% All exports
-export([
    % gen_pnet-compatible callbacks
    place_lst/0,
    trsn_lst/0,
    init_marking/2,
    preset/1,
    postset/1,
    is_enabled/3,
    fire/3,
    trigger/3,
    % API functions
    create_workflow/1,
    get_workflow_spec/0,
    simulate_invoice_required_prepaid/0,
    simulate_invoice_not_required_prepaid/0,
    simulate_invoice_required_not_prepaid/0,
    simulate_invoice_not_required_not_prepaid/0,
    simulate_debit_adjustment_path/0,
    simulate_credit_adjustment_path/0,
    simulate_payment_rejection/0,
    simulate_full_payment_flow/0,
    get_initial_marking/0,
    fire_transition_sequence/2
]).

%% Include gen_pnet records
-include("include/gen_pnet.hrl").
-include("include/yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%%% Constants
%%====================================================================

-define(WORKFLOW_ID, <<"payment_workflow">>).
-define(PAYMENT_TIMEOUT_MS, 300000). % 5 minutes
-define(ADJUSTMENT_THRESHOLD, 0).  % Balance threshold for debit/credit

%%====================================================================
%%% Types
%%====================================================================

-type shipment_data() :: #{
    shipment_id => binary(),
    invoice_required => boolean(),
    prepaid => boolean(),
    amount => number(),
    balance => number()
}.

-type invoice_data() :: #{
    invoice_id => binary(),
    shipment_id => binary(),
    amount => number(),
    issued_at => integer()
}.

-type payment_order_data() :: #{
    payment_order_id => binary(),
    shipment_id => binary(),
    amount => number(),
    status => pending | approved | rejected | paid
}.

-type payment_approval_data() :: #{
    approval_id => binary(),
    payment_order_id => binary(),
    approved => boolean(),
    approved_by => binary(),
    approved_at => integer()
}.

-type payment_data() :: #{
    payment_id => binary(),
    payment_order_id => binary(),
    amount => number(),
    balance => number(),
    processed_at => integer()
}.

-type adjustment_data() :: #{
    adjustment_id => binary(),
    payment_id => binary(),
    amount => number(),
    type => debit | credit,
    reason => binary()
}.

%%====================================================================
%%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    [
        start,
        payment_started,
        invoice_check_required,
        payment_order_check,
        invoice_issued,
        payment_order_created,
        freight_invoice_created,
        remittance_advice_issued,
        approval_pending,
        payment_approved,
        payment_rejected,
        payment_processed,
        balance_check,
        debit_adjustment,
        credit_adjustment,
        'end'
    ].

trsn_lst() ->
    [
        check_invoice_required,
        issue_shipment_invoice,
        check_prepaid,
        issue_payment_order,
        produce_freight_invoice,
        issue_remittance_advice,
        approve_payment_order,
        reject_payment_order,
        update_payment_order,
        process_payment,
        check_balance,
        issue_debit_adjustment,
        issue_credit_adjustment,
        complete_payment,
        cancel_payment
    ].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(Transition) ->
    case Transition of
        check_invoice_required -> [start];
        issue_shipment_invoice -> [invoice_check_required];
        check_prepaid -> [invoice_issued];
        issue_payment_order -> [payment_order_check];
        produce_freight_invoice -> [invoice_issued];
        issue_remittance_advice -> [invoice_issued];
        approve_payment_order -> [approval_pending];
        reject_payment_order -> [approval_pending];
        update_payment_order -> [payment_order_created];
        process_payment -> [payment_approved];
        check_balance -> [payment_processed];
        issue_debit_adjustment -> [balance_check];
        issue_credit_adjustment -> [balance_check];
        complete_payment -> [debit_adjustment, credit_adjustment];
        cancel_payment -> [payment_rejected]
    end.

postset(Transition) ->
    case Transition of
        check_invoice_required ->
            [payment_started, invoice_check_required, payment_order_check];
        issue_shipment_invoice ->
            [invoice_issued];
        check_prepaid ->
            [payment_order_created, freight_invoice_created];
        issue_payment_order ->
            [payment_order_created];
        produce_freight_invoice ->
            [freight_invoice_created];
        issue_remittance_advice ->
            [remittance_advice_issued];
        approve_payment_order ->
            [payment_approved];
        reject_payment_order ->
            [payment_rejected];
        update_payment_order ->
            [approval_pending];
        process_payment ->
            [payment_processed];
        check_balance ->
            [balance_check];
        issue_debit_adjustment ->
            [debit_adjustment];
        issue_credit_adjustment ->
            [credit_adjustment];
        complete_payment ->
            ['end'];
        cancel_payment ->
            ['end']
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        check_invoice_required ->
            has_token(start, Mode);
        issue_shipment_invoice ->
            has_token(invoice_check_required, Mode) andalso
            invoice_required(Mode);
        check_prepaid ->
            has_token(invoice_issued, Mode);
        issue_payment_order ->
            has_token(payment_order_check, Mode) andalso
            is_prepaid(Mode);
        produce_freight_invoice ->
            has_token(invoice_issued, Mode) andalso
            not is_prepaid(Mode);
        issue_remittance_advice ->
            has_token(invoice_issued, Mode);
        approve_payment_order ->
            has_token(approval_pending, Mode) andalso
            can_approve(Mode);
        reject_payment_order ->
            has_token(approval_pending, Mode) andalso
            not can_approve(Mode);
        update_payment_order ->
            has_token(payment_order_created, Mode);
        process_payment ->
            has_token(payment_approved, Mode);
        check_balance ->
            has_token(payment_processed, Mode);
        issue_debit_adjustment ->
            has_token(balance_check, Mode) andalso
            balance_positive(Mode);
        issue_credit_adjustment ->
            has_token(balance_check, Mode) andalso
            balance_negative(Mode);
        complete_payment ->
            has_token(debit_adjustment, Mode) orelse
            has_token(credit_adjustment, Mode);
        cancel_payment ->
            has_token(payment_rejected, Mode)
    end.

fire(Transition, _Mode, UsrInfo) ->
    ShipmentData = get_shipment_data(UsrInfo),

    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        check_invoice_required ->
            InvoiceRequired = maps:get(invoice_required, ShipmentData, true),
            {produce, #{
                payment_started => [payment_started_token],
                invoice_check_required => [invoice_check_token],
                payment_order_check => [payment_order_check_token]
            }};
        issue_shipment_invoice ->
            Invoice = create_shipment_invoice(ShipmentData),
            {produce, #{
                invoice_issued => [Invoice]
            }};
        check_prepaid ->
            PrePaid = maps:get(prepaid, ShipmentData, false),
            {produce, case PrePaid of
                true ->
                    #{
                        payment_order_created => [payment_order_created_token],
                        freight_invoice_created => [freight_invoice_token]
                    };
                false ->
                    #{freight_invoice_created => [freight_invoice_token]}
            end};
        issue_payment_order ->
            PaymentOrder = create_payment_order(ShipmentData),
            {produce, #{
                payment_order_created => [PaymentOrder]
            }};
        produce_freight_invoice ->
            FreightInvoice = create_freight_invoice(ShipmentData),
            {produce, #{
                freight_invoice_created => [FreightInvoice]
            }};
        issue_remittance_advice ->
            RemittanceAdvice = create_remittance_advice(ShipmentData),
            {produce, #{
                remittance_advice_issued => [RemittanceAdvice]
            }};
        approve_payment_order ->
            Approval = create_payment_approval(ShipmentData),
            {produce, #{
                payment_approved => [Approval]
            }};
        reject_payment_order ->
            Rejection = create_payment_rejection(ShipmentData),
            {produce, #{
                payment_rejected => [Rejection]
            }};
        update_payment_order ->
            UpdatedOrder = update_payment_order(ShipmentData),
            {produce, #{
                approval_pending => [UpdatedOrder]
            }};
        process_payment ->
            Payment = process_payment(ShipmentData),
            {produce, #{
                payment_processed => [Payment]
            }};
        check_balance ->
            Balance = maps:get(balance, ShipmentData, 0),
            {produce, #{
                balance_check => [{balance, Balance}]
            }};
        issue_debit_adjustment ->
            DebitAdjustment = create_debit_adjustment(ShipmentData),
            {produce, #{
                debit_adjustment => [DebitAdjustment]
            }};
        issue_credit_adjustment ->
            CreditAdjustment = create_credit_adjustment(ShipmentData),
            {produce, #{
                credit_adjustment => [CreditAdjustment]
            }};
        complete_payment ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete_payment, complete),
            {produce, #{
                'end' => [payment_completed]
            }};
        cancel_payment ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, cancel_payment, cancel),
            {produce, #{
                'end' => [payment_cancelled]
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            case Token of
                workflow_token -> pass;
                _ -> pass
            end;
        payment_started ->
            pass;
        invoice_check_required ->
            pass;
        payment_order_check ->
            pass;
        invoice_issued ->
            pass;
        payment_order_created ->
            pass;
        freight_invoice_created ->
            pass;
        remittance_advice_issued ->
            pass;
        approval_pending ->
            pass;
        payment_approved ->
            pass;
        payment_rejected ->
            pass;
        payment_processed ->
            pass;
        balance_check ->
            pass;
        debit_adjustment ->
            pass;
        credit_adjustment ->
            pass;
        _ ->
            pass
    end.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create a new payment workflow
-spec create_workflow(map()) -> {ok, map()} | {error, term()}.
create_workflow(ShipmentData) ->
    WorkflowId = maps:get(shipment_id, ShipmentData, ?WORKFLOW_ID),
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => composite,
        shipment_data => ShipmentData,
        timeout => maps:get(timeout, ShipmentData, ?PAYMENT_TIMEOUT_MS)
    },
    {ok, Spec#{config => Config}}.

%% @doc Get the workflow specification
-spec get_workflow_spec() -> map().
get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Payment Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Process invoice and payment for shipments">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [
            basic_sequential,
            exclusive_choice,
            parallel_split,
            simple_merge
        ]
    }.

%% @doc Get initial marking for simulation
-spec get_initial_marking() -> map().
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate invoice required + prepaid path
-spec simulate_invoice_required_prepaid() -> {ok, map()}.
simulate_invoice_required_prepaid() ->
    % Initialize XES logging for this workflow instance
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    ShipmentData = #{
        shipment_id => <<"shipment_001">>,
        invoice_required => true,
        prepaid => true,
        amount => 1000.00,
        balance => 0
    },
    try
        Result = run_simulation(ShipmentData, [
            check_invoice_required,
            issue_shipment_invoice,
            check_prepaid,
            update_payment_order,
            approve_payment_order,
            process_payment,
            check_balance,
            complete_payment
        ]),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        Result
    catch
        _:_ ->
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {ok, #{}}
    end.

%% @doc Simulate invoice not required + prepaid path
-spec simulate_invoice_not_required_prepaid() -> {ok, map()}.
simulate_invoice_not_required_prepaid() ->
    ShipmentData = #{
        shipment_id => <<"shipment_002">>,
        invoice_required => false,
        prepaid => true,
        amount => 1500.00,
        balance => 0
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_payment_order,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        complete_payment
    ]).

%% @doc Simulate invoice required + not prepaid path
-spec simulate_invoice_required_not_prepaid() -> {ok, map()}.
simulate_invoice_required_not_prepaid() ->
    ShipmentData = #{
        shipment_id => <<"shipment_003">>,
        invoice_required => true,
        prepaid => false,
        amount => 2000.00,
        balance => 0
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_shipment_invoice,
        check_prepaid,
        produce_freight_invoice,
        issue_remittance_advice,
        issue_payment_order,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        complete_payment
    ]).

%% @doc Simulate invoice not required + not prepaid path
-spec simulate_invoice_not_required_not_prepaid() -> {ok, map()}.
simulate_invoice_not_required_not_prepaid() ->
    ShipmentData = #{
        shipment_id => <<"shipment_004">>,
        invoice_required => false,
        prepaid => false,
        amount => 800.00,
        balance => 0
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_payment_order,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        complete_payment
    ]).

%% @doc Simulate debit adjustment path (balance > 0)
-spec simulate_debit_adjustment_path() -> {ok, map()}.
simulate_debit_adjustment_path() ->
    ShipmentData = #{
        shipment_id => <<"shipment_005">>,
        invoice_required => true,
        prepaid => true,
        amount => 1000.00,
        balance => 150.00  % Customer owes more
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_shipment_invoice,
        check_prepaid,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        issue_debit_adjustment,
        complete_payment
    ]).

%% @doc Simulate credit adjustment path (balance < 0)
-spec simulate_credit_adjustment_path() -> {ok, map()}.
simulate_credit_adjustment_path() ->
    ShipmentData = #{
        shipment_id => <<"shipment_006">>,
        invoice_required => true,
        prepaid => true,
        amount => 1000.00,
        balance => -100.00  % Overpayment
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_shipment_invoice,
        check_prepaid,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        issue_credit_adjustment,
        complete_payment
    ]).

%% @doc Simulate payment rejection scenario
-spec simulate_payment_rejection() -> {ok, map()}.
simulate_payment_rejection() ->
    ShipmentData = #{
        shipment_id => <<"shipment_007">>,
        invoice_required => true,
        prepaid => true,
        amount => 5000.00,
        balance => 0,
        approval_allowed => false  % Forces rejection
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_shipment_invoice,
        check_prepaid,
        update_payment_order,
        reject_payment_order,
        cancel_payment
    ]).

%% @doc Simulate full payment flow with all branches
-spec simulate_full_payment_flow() -> {ok, map()}.
simulate_full_payment_flow() ->
    ShipmentData = #{
        shipment_id => <<"shipment_full_001">>,
        invoice_required => true,
        prepaid => true,
        amount => 3500.00,
        balance => 0
    },
    run_simulation(ShipmentData, [
        check_invoice_required,
        issue_shipment_invoice,
        issue_remittance_advice,
        check_prepaid,
        update_payment_order,
        approve_payment_order,
        process_payment,
        check_balance,
        complete_payment
    ]).

%% @doc Fire a sequence of transitions for simulation
-spec fire_transition_sequence(map(), [atom()]) -> {ok, map()}.
fire_transition_sequence(InitialMarking, Transitions) ->
    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        State = #{
            marking => CurrentMarking,
            usr_info => [],
            net_mod => ?MODULE
        },
        Preset = preset(Transition),
        Mode = build_mode(Preset, CurrentMarking),
        case is_enabled(Transition, Mode, []) of
            true ->
                case fire(Transition, Mode, []) of
                    {produce, ProduceMap} ->
                        NewMarking = apply_produce(CurrentMarking, ProduceMap),
                        {ok, NewMarking};
                    abort ->
                        {ok, CurrentMarking}
                end;
            false ->
                {ok, CurrentMarking}
        end
    end, {ok, InitialMarking}, Transitions).

%%====================================================================
%%% Internal Helper Functions
%%====================================================================

%% @private
-spec run_simulation(map(), [atom()]) -> {ok, map()}.
run_simulation(ShipmentData, Transitions) ->
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        shipment_data => ShipmentData
    },
    fire_transition_sequence(UpdatedMarking, Transitions).

%% @private
-spec has_token(atom(), map()) -> boolean().
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        _ -> true
    end.

%% @private
-spec invoice_required(map()) -> boolean().
invoice_required(Mode) ->
    case maps:get(shipment_data, Mode, undefined) of
        undefined -> true;
        ShipmentData -> maps:get(invoice_required, ShipmentData, true)
    end.

%% @private
-spec is_prepaid(map()) -> boolean().
is_prepaid(Mode) ->
    case maps:get(shipment_data, Mode, undefined) of
        undefined -> false;
        ShipmentData -> maps:get(prepaid, ShipmentData, false)
    end.

%% @private
-spec can_approve(map()) -> boolean().
can_approve(Mode) ->
    case maps:get(shipment_data, Mode, undefined) of
        undefined -> true;
        ShipmentData -> maps:get(approval_allowed, ShipmentData, true)
    end.

%% @private
-spec balance_positive(map()) -> boolean().
balance_positive(Mode) ->
    case maps:get(balance_check, Mode, []) of
        [{balance, Balance}] when is_number(Balance) -> Balance > ?ADJUSTMENT_THRESHOLD;
        _ -> false
    end.

%% @private
-spec balance_negative(map()) -> boolean().
balance_negative(Mode) ->
    case maps:get(balance_check, Mode, []) of
        [{balance, Balance}] when is_number(Balance) -> Balance < ?ADJUSTMENT_THRESHOLD;
        _ -> false
    end.

%% @private
-spec get_shipment_data(term()) -> map().
get_shipment_data([]) -> #{};
get_shipment_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(shipment_data, UsrInfo, #{});
get_shipment_data(_) -> #{}.

%% @private
-spec create_shipment_invoice(map()) -> invoice_data().
create_shipment_invoice(ShipmentData) ->
    #{
        invoice_id => generate_id(<<"invoice">>),
        shipment_id => maps:get(shipment_id, ShipmentData, <<"unknown">>),
        invoice_type => shipment_invoice,
        amount => maps:get(amount, ShipmentData, 0),
        issued_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_freight_invoice(map()) -> invoice_data().
create_freight_invoice(ShipmentData) ->
    #{
        invoice_id => generate_id(<<"freight_invoice">>),
        shipment_id => maps:get(shipment_id, ShipmentData, <<"unknown">>),
        invoice_type => freight_invoice,
        amount => maps:get(amount, ShipmentData, 0) * 0.15, % 15% freight charge
        issued_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_payment_order(map()) -> payment_order_data().
create_payment_order(ShipmentData) ->
    #{
        payment_order_id => generate_id(<<"payment_order">>),
        shipment_id => maps:get(shipment_id, ShipmentData, <<"unknown">>),
        amount => maps:get(amount, ShipmentData, 0),
        status => pending
    }.

%% @private
-spec create_remittance_advice(map()) -> map().
create_remittance_advice(ShipmentData) ->
    #{
        advice_id => generate_id(<<"remittance">>),
        shipment_id => maps:get(shipment_id, ShipmentData, <<"unknown">>),
        advice_type => shipment_remittance_advice,
        issued_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_payment_approval(map()) -> payment_approval_data().
create_payment_approval(ShipmentData) ->
    #{
        approval_id => generate_id(<<"approval">>),
        payment_order_id => generate_id(<<"payment_order">>),
        approved => true,
        approved_by => <<"system">>,
        approved_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_payment_rejection(map()) -> map().
create_payment_rejection(ShipmentData) ->
    #{
        rejection_id => generate_id(<<"rejection">>),
        payment_order_id => generate_id(<<"payment_order">>),
        approved => false,
        rejected_by => <<"system">>,
        rejected_at => erlang:system_time(millisecond),
        reason => <<"Payment amount exceeds threshold">>
    }.

%% @private
-spec update_payment_order(map()) -> payment_order_data().
update_payment_order(ShipmentData) ->
    #{
        payment_order_id => generate_id(<<"payment_order">>),
        shipment_id => maps:get(shipment_id, ShipmentData, <<"unknown">>),
        amount => maps:get(amount, ShipmentData, 0),
        status => pending
    }.

%% @private
-spec process_payment(map()) -> payment_data().
process_payment(ShipmentData) ->
    Balance = maps:get(balance, ShipmentData, 0),
    #{
        payment_id => generate_id(<<"payment">>),
        payment_order_id => generate_id(<<"payment_order">>),
        amount => maps:get(amount, ShipmentData, 0),
        balance => Balance,
        processed_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_debit_adjustment(map()) -> adjustment_data().
create_debit_adjustment(ShipmentData) ->
    Balance = maps:get(balance, ShipmentData, 0),
    #{
        adjustment_id => generate_id(<<"debit_adj">>),
        payment_id => generate_id(<<"payment">>),
        amount => abs(Balance),
        type => debit,
        reason => <<"Additional payment required">>
    }.

%% @private
-spec create_credit_adjustment(map()) -> adjustment_data().
create_credit_adjustment(ShipmentData) ->
    Balance = maps:get(balance, ShipmentData, 0),
    #{
        adjustment_id => generate_id(<<"credit_adj">>),
        payment_id => generate_id(<<"payment">>),
        amount => abs(Balance),
        type => credit,
        reason => <<"Overpayment refund">>
    }.

%% @private
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Timestamp = erlang:system_time(millisecond),
    Random = rand:uniform(1000000),
    <<Prefix/binary, "_", (integer_to_binary(Timestamp))/binary, "_",
      (integer_to_binary(Random))/binary>>.

%% @private
-spec build_mode([atom()], map()) -> map().
build_mode(Preset, Marking) ->
    lists:foldl(fun(Place, Acc) ->
        Tokens = maps:get(Place, Marking, []),
        Acc#{Place => Tokens}
    end, #{}, Preset).

%% @private
-spec apply_produce(map(), map()) -> map().
apply_produce(Marking, ProduceMap) ->
    maps:fold(fun(Place, Tokens, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        Acc#{Place => CurrentTokens ++ Tokens}
    end, Marking, ProduceMap).
