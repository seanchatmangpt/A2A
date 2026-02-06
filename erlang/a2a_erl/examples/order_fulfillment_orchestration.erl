%%%-------------------------------------------------------------------
%%% @doc
%%% Order Fulfillment Orchestration - YAWL Integration Layer
%%%
%%% This module orchestrates all 5 YAWL order fulfillment workflows:
%%% 1. Ordering (Purchase Order) - ordering_workflow
%%% 2. Carrier Appointment - carrier_appointment_workflow
%%% 3. Freight in Transit - freight_in_transit_workflow
%%% 4. Freight Delivered - freight_delivered_workflow
%%% 5. Payment - payment_workflow
%%%
%%% The orchestration layer handles:
%%% - Workflow chaining and state transitions
%%% - Data flow between stages (POrder, TransportationQuote, etc.)
%%% - Shared data management across workflow boundaries
%%% - Cancellation propagation across stages
%%% - State management for the full order lifecycle
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(order_fulfillment_orchestration).
-author("A2A Team").

%% API exports
-export([
    start_order_fulfillment/1,
    transition_to_carrier_appointment/2,
    transition_to_freight_transit/2,
    transition_to_freight_delivered/2,
    transition_to_payment/2,
    get_full_order_status/1,
    simulate_full_order_fulfillment/0,
    simulate_with_claim/0,
    simulate_with_return/0,
    simulate_timeout_any_stage/0,
    cancel_order_fulfillment/1,
    get_orchestration_state/1,
    update_shared_data/3
]).

%% Include headers
-include("include/gen_pnet.hrl").
-include("include/yawl_types.hrl").

%%====================================================================
%%% Constants
%%====================================================================

-define(ORCHESTRATION_ID_PREFIX, <<"of_">>).
-define(DEFAULT_TIMEOUT_MS, 300000). % 5 minutes

%%====================================================================
%%% Type Definitions
%%====================================================================

-type orchestration_id() :: binary().
-type order_stage() :: ordering | carrier_appointment | freight_transit | freight_delivered | payment | completed | cancelled | failed.
-type shared_data() :: #{
    orchestration_id => binary(),
    po_order => map(),
    transportation_quote => map(),
    shipment_notice => map(),
    acceptance_certificate => map(),
    delivery_confirmation => map(),
    payment_details => map(),
    claim_data => map() | undefined,
    return_data => map() | undefined
}.
-type orchestration_state() :: #{
    orchestration_id => binary(),
    current_stage => order_stage(),
    stages_completed => [order_stage()],
    shared_data => shared_data(),
    status => atom(),
    started_at => integer(),
    updated_at => integer(),
    errors => [term()],
    cancellation_reason => term() | undefined
}.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Start a new order fulfillment orchestration
%% Takes initial order data and initiates the ordering workflow
-spec start_order_fulfillment(map()) -> {ok, orchestration_state()} | {error, term()}.
start_order_fulfillment(InitialOrderData) ->
    OrchestrationId = generate_orchestration_id(),
    Now = erlang:system_time(millisecond),

    SharedData = #{
        orchestration_id => OrchestrationId,
        po_order => InitialOrderData,
        transportation_quote => #{},
        shipment_notice => #{},
        acceptance_certificate => #{},
        delivery_confirmation => #{},
        payment_details => #{},
        claim_data => undefined,
        return_data => undefined
    },

    InitialState = #{
        orchestration_id => OrchestrationId,
        current_stage => ordering,
        stages_completed => [],
        shared_data => SharedData,
        status => running,
        started_at => Now,
        updated_at => Now,
        errors => [],
        cancellation_reason => undefined
    },

    % Start the ordering workflow
    case ordering_workflow:create_workflow(InitialOrderData) of
        {ok, _OrderingWorkflow} ->
            {ok, InitialState};
        {error, Reason} ->
            {error, {failed_to_start_ordering, Reason}}
    end.

%% @doc Transition from ordering to carrier appointment
%% Extracts PO data and creates carrier appointment workflow
-spec transition_to_carrier_appointment(orchestration_state(), map()) -> {ok, orchestration_state()} | {error, term()}.
transition_to_carrier_appointment(OrchestrationState, AppointmentData) ->
    case maps:get(current_stage, OrchestrationState) of
        ordering ->
            SharedData = maps:get(shared_data, OrchestrationState),
            POOrder = maps:get(po_order, SharedData),

            % Create transportation quote from PO data
            TransportationQuote = create_transportation_quote(POOrder, AppointmentData),
            UpdatedSharedData = SharedData#{transportation_quote => TransportationQuote},

            % Start carrier appointment workflow
            CarrierData = merge_carrier_data(POOrder, AppointmentData),
            case carrier_appointment_workflow:create_workflow(CarrierData) of
                {ok, _CarrierWorkflow} ->
                    Now = erlang:system_time(millisecond),
                    NewState = OrchestrationState#{
                        current_stage => carrier_appointment,
                        stages_completed => [ordering | maps:get(stages_completed, OrchestrationState, [])],
                        shared_data => UpdatedSharedData,
                        updated_at => Now
                    },
                    {ok, NewState};
                {error, Reason} ->
                    {error, {failed_to_start_carrier_appointment, Reason}}
            end;
        _ ->
            {error, {invalid_stage_transition, maps:get(current_stage, OrchestrationState)}}
    end.

%% @doc Transition from carrier appointment to freight transit
%% Creates shipment notice and initiates freight in transit workflow
-spec transition_to_freight_transit(orchestration_state(), map()) -> {ok, orchestration_state()} | {error, term()}.
transition_to_freight_transit(OrchestrationState, TransitData) ->
    case maps:get(current_stage, OrchestrationState) of
        carrier_appointment ->
            SharedData = maps:get(shared_data, OrchestrationState),
            TransportationQuote = maps:get(transportation_quote, SharedData),

            % Create shipment notice from carrier appointment result
            ShipmentNotice = create_shipment_notice(TransportationQuote, TransitData),
            UpdatedSharedData = SharedData#{shipment_notice => ShipmentNotice},

            % Start freight in transit workflow
            TransitWorkflowData = merge_transit_data(TransportationQuote, TransitData),
            case freight_in_transit_workflow:create_workflow(TransitWorkflowData) of
                {ok, _TransitWorkflow} ->
                    Now = erlang:system_time(millisecond),
                    NewState = OrchestrationState#{
                        current_stage => freight_transit,
                        stages_completed => [carrier_appointment | maps:get(stages_completed, OrchestrationState, [])],
                        shared_data => UpdatedSharedData,
                        updated_at => Now
                    },
                    {ok, NewState};
                {error, Reason} ->
                    {error, {failed_to_start_freight_transit, Reason}}
            end;
        _ ->
            {error, {invalid_stage_transition, maps:get(current_stage, OrchestrationState)}}
    end.

%% @doc Transition from freight transit to freight delivered
%% Creates acceptance certificate and initiates freight delivered workflow
-spec transition_to_freight_delivered(orchestration_state(), map()) -> {ok, orchestration_state()} | {error, term()}.
transition_to_freight_delivered(OrchestrationState, DeliveryData) ->
    case maps:get(current_stage, OrchestrationState) of
        freight_transit ->
            SharedData = maps:get(shared_data, OrchestrationState),
            ShipmentNotice = maps:get(shipment_notice, SharedData),

            % Create acceptance certificate from transit completion
            AcceptanceCertificate = create_acceptance_certificate(ShipmentNotice, DeliveryData),
            UpdatedSharedData = SharedData#{acceptance_certificate => AcceptanceCertificate},

            % Start freight delivered workflow
            DeliveryWorkflowData = merge_delivery_data(ShipmentNotice, DeliveryData),
            case freight_delivered_workflow:create_workflow(DeliveryWorkflowData) of
                {ok, _DeliveredWorkflow} ->
                    Now = erlang:system_time(millisecond),
                    NewState = OrchestrationState#{
                        current_stage => freight_delivered,
                        stages_completed => [freight_transit | maps:get(stages_completed, OrchestrationState, [])],
                        shared_data => UpdatedSharedData,
                        updated_at => Now
                    },
                    {ok, NewState};
                {error, Reason} ->
                    {error, {failed_to_start_freight_delivered, Reason}}
            end;
        _ ->
            {error, {invalid_stage_transition, maps:get(current_stage, OrchestrationState)}}
    end.

%% @doc Transition from freight delivered to payment
%% Finalizes delivery confirmation and initiates payment workflow
-spec transition_to_payment(orchestration_state(), map()) -> {ok, orchestration_state()} | {error, term()}.
transition_to_payment(OrchestrationState, PaymentData) ->
    case maps:get(current_stage, OrchestrationState) of
        freight_delivered ->
            SharedData = maps:get(shared_data, OrchestrationState),

            % Create delivery confirmation
            DeliveryConfirmation = create_delivery_confirmation(SharedData, PaymentData),
            UpdatedSharedData = SharedData#{delivery_confirmation => DeliveryConfirmation},

            % Start payment workflow
            PaymentWorkflowData = merge_payment_data(SharedData, PaymentData),
            case payment_workflow:create_workflow(PaymentWorkflowData) of
                {ok, _PaymentWorkflow} ->
                    Now = erlang:system_time(millisecond),
                    NewState = OrchestrationState#{
                        current_stage => payment,
                        stages_completed => [freight_delivered | maps:get(stages_completed, OrchestrationState, [])],
                        shared_data => UpdatedSharedData,
                        updated_at => Now
                    },
                    {ok, NewState};
                {error, Reason} ->
                    {error, {failed_to_start_payment, Reason}}
            end;
        _ ->
            {error, {invalid_stage_transition, maps:get(current_stage, OrchestrationState)}}
    end.

%% @doc Get full order status across all stages
-spec get_full_order_status(orchestration_id()) -> {ok, map()} | {error, term()}.
get_full_order_status(OrchestrationId) ->
    % In a real implementation, this would query persistent storage
    % For now, return a status structure
    {ok, #{
        orchestration_id => OrchestrationId,
        status => running,
        current_stage => unknown,
        stages_completed => [],
        shared_data_summary => #{},
        timestamps => #{
            started_at => erlang:system_time(millisecond),
            updated_at => erlang:system_time(millisecond)
        }
    }}.

%% @doc Simulate full order fulfillment from start to payment
-spec simulate_full_order_fulfillment() -> {ok, map()}.
simulate_full_order_fulfillment() ->
    % Stage 1: Create purchase order
    POData = #{
        po_id => <<"PO-FULL-001">>,
        supplier_id => <<"SUPPLIER-FULL-001">>,
        items => [
            #{item_id => <<"ITEM-FULL-001">>, quantity => 100, unit_price => 50.00},
            #{item_id => <<"ITEM-FULL-002">>, quantity => 50, unit_price => 75.00}
        ],
        total_amount => 8750.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-FULL-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = start_order_fulfillment(POData),

    % Stage 2: Carrier Appointment (TL path - weight > 10000)
    CarrierData = #{
        order_id => <<"ORDER-FULL-001">>,
        weight => 15000,
        destination => <<"New York, NY">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = transition_to_carrier_appointment(OrderState, CarrierData),

    % Stage 3: Freight in Transit
    TransitData = #{
        shipment_id => <<"SHIPMENT-FULL-001">>,
        origin => <<"Los Angeles, CA">>,
        destination => <<"New York, NY">>,
        carrier => <<"FedEx Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (5 * 86400000),
        trackpoint_count => 3
    },
    {ok, TransitState} = transition_to_freight_transit(CarrierState, TransitData),

    % Stage 4: Freight Delivered
    DeliveryData = #{
        delivery_id => <<"DELIVERY-FULL-001">>,
        order_id => <<"ORDER-FULL-001">>,
        customer_id => <<"CUSTOMER-FULL-001">>,
        delivery_date => erlang:system_time(millisecond),
        no_claim => true
    },
    {ok, DeliveredState} = transition_to_freight_delivered(TransitState, DeliveryData),

    % Stage 5: Payment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-FULL-001">>,
        invoice_required => true,
        prepaid => true,
        amount => 8750.00,
        balance => 0
    },
    {ok, PaymentState} = transition_to_payment(DeliveredState, PaymentData),

    % Complete the orchestration
    Now = erlang:system_time(millisecond),
    FinalState = PaymentState#{
        current_stage => completed,
        stages_completed => [payment | maps:get(stages_completed, PaymentState, [])],
        status => completed,
        updated_at => Now
    },

    {ok, format_final_state(FinalState)}.

%% @doc Simulate full order fulfillment with a claim
-spec simulate_with_claim() -> {ok, map()}.
simulate_with_claim() ->
    % Run through first 4 stages
    POData = #{
        po_id => <<"PO-CLAIM-001">>,
        supplier_id => <<"SUPPLIER-CLAIM-001">>,
        items => [
            #{item_id => <<"ITEM-CLAIM-001">>, quantity => 50, unit_price => 100.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-CLAIM-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-CLAIM-001">>,
        weight => 8000,
        destination => <<"Chicago, IL">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-CLAIM-001">>,
        origin => <<"Dallas, TX">>,
        destination => <<"Chicago, IL">>,
        carrier => <<"UPS Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (3 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = transition_to_freight_transit(CarrierState, TransitData),

    % Delivery with claim
    DeliveryData = #{
        delivery_id => <<"DELIVERY-CLAIM-001">>,
        order_id => <<"ORDER-CLAIM-001">>,
        customer_id => <<"CUSTOMER-CLAIM-001">>,
        delivery_date => erlang:system_time(millisecond),
        has_claim => true,
        claim_data => #{
            claim_id => <<"CLAIM-001">>,
            delivery_id => <<"DELIVERY-CLAIM-001">>,
            claim_type => damage,
            description => <<"Package arrived with visible damage">>,
            amount => 500,
            evidence => [<<"photo1.jpg">>, <<"photo2.jpg">>],
            filed_date => erlang:system_time(millisecond),
            approved => true
        }
    },
    {ok, DeliveredState} = transition_to_freight_delivered(TransitState, DeliveryData),

    % Update shared data with claim
    SharedData = maps:get(shared_data, DeliveredState),
    UpdatedSharedData = SharedData#{claim_data => maps:get(claim_data, DeliveryData)},
    UpdatedDeliveredState = DeliveredState#{shared_data => UpdatedSharedData},

    % Payment with claim adjustment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-CLAIM-001">>,
        invoice_required => true,
        prepaid => false,
        amount => 4500.00,  % Reduced after claim
        balance => -500.00  % Credit to customer
    },
    {ok, PaymentState} = transition_to_payment(UpdatedDeliveredState, PaymentData),

    Now = erlang:system_time(millisecond),
    FinalState = PaymentState#{
        current_stage => completed,
        stages_completed => [payment | maps:get(stages_completed, PaymentState, [])],
        status => completed,
        updated_at => Now
    },

    {ok, format_final_state(FinalState#{had_claim => true})}.

%% @doc Simulate full order fulfillment with a return
-spec simulate_with_return() -> {ok, map()}.
simulate_with_return() ->
    % Run through first 4 stages
    POData = #{
        po_id => <<"PO-RETURN-001">>,
        supplier_id => <<"SUPPLIER-RETURN-001">>,
        items => [
            #{item_id => <<"ITEM-RETURN-001">>, quantity => 25, unit_price => 200.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-RETURN-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-RETURN-001">>,
        weight => 6000,
        destination => <<"Seattle, WA">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-RETURN-001">>,
        origin => <<"Denver, CO">>,
        destination => <<"Seattle, WA">>,
        carrier => <<"XPO Logistics">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (4 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = transition_to_freight_transit(CarrierState, TransitData),

    % Delivery with return
    DeliveryData = #{
        delivery_id => <<"DELIVERY-RETURN-001">>,
        order_id => <<"ORDER-RETURN-001">>,
        customer_id => <<"CUSTOMER-RETURN-001">>,
        delivery_date => erlang:system_time(millisecond),
        has_return => true,
        return_data => #{
            return_id => <<"RETURN-001">>,
            delivery_id => <<"DELIVERY-RETURN-001">>,
            reason => <<"Product not as described">>,
            items => [{<<"ITEM-RETURN-001">>, 5}],
            return_fee => 0,
            filed_date => erlang:system_time(millisecond),
            approved => true
        }
    },
    {ok, DeliveredState} = transition_to_freight_delivered(TransitState, DeliveryData),

    % Update shared data with return
    SharedData = maps:get(shared_data, DeliveredState),
    UpdatedSharedData = SharedData#{return_data => maps:get(return_data, DeliveryData)},
    UpdatedDeliveredState = DeliveredState#{shared_data => UpdatedSharedData},

    % Payment with return adjustment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-RETURN-001">>,
        invoice_required => true,
        prepaid => true,
        amount => 5000.00,
        balance => -1000.00  % Refund for returned items
    },
    {ok, PaymentState} = transition_to_payment(UpdatedDeliveredState, PaymentData),

    Now = erlang:system_time(millisecond),
    FinalState = PaymentState#{
        current_stage => completed,
        stages_completed => [payment | maps:get(stages_completed, PaymentState, [])],
        status => completed,
        updated_at => Now
    },

    {ok, format_final_state(FinalState#{had_return => true})}.

%% @doc Simulate timeout at any stage with cancellation propagation
-spec simulate_timeout_any_stage() -> {ok, map()}.
simulate_timeout_any_stage() ->
    POData = #{
        po_id => <<"PO-TIMEOUT-ORCH-001">>,
        supplier_id => <<"SUPPLIER-TIMEOUT-001">>,
        items => [
            #{item_id => <<"ITEM-TIMEOUT-001">>, quantity => 10, unit_price => 100.00}
        ],
        total_amount => 1000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TIMEOUT-001">>,
        created_at => erlang:system_time(millisecond) - (4 * 86400000)  % 4 days ago - timed out
    },

    {ok, OrderState} = start_order_fulfillment(POData),

    % Simulate timeout at ordering stage
    Now = erlang:system_time(millisecond),
    CancelledState = OrderState#{
        current_stage => cancelled,
        status => cancelled,
        updated_at => Now,
        cancellation_reason => {po_timeout, <<"PO timed out after 3 days">>}
    },

    {ok, format_final_state(CancelledState#{timeout_stage => ordering})}.

%% @doc Cancel an active order fulfillment orchestration
-spec cancel_order_fulfillment(orchestration_state(), term()) -> {ok, orchestration_state()}.
cancel_order_fulfillment(OrchestrationState, Reason) ->
    Now = erlang:system_time(millisecond),
    CancelledState = OrchestrationState#{
        current_stage => cancelled,
        status => cancelled,
        updated_at => Now,
        cancellation_reason => Reason
    },
    {ok, CancelledState}.

%% @doc Get orchestration state by ID
-spec get_orchestration_state(orchestration_id()) -> {ok, orchestration_state()} | {error, not_found}.
get_orchestration_state(_OrchestrationId) ->
    % In real implementation, would fetch from storage
    {error, not_found}.

%% @doc Update shared data in the orchestration state
-spec update_shared_data(orchestration_state(), atom(), map()) -> {ok, orchestration_state()}.
update_shared_data(OrchestrationState, Key, Data) ->
    SharedData = maps:get(shared_data, OrchestrationState),
    UpdatedSharedData = SharedData#{Key => Data},
    Now = erlang:system_time(millisecond),
    UpdatedState = OrchestrationState#{
        shared_data => UpdatedSharedData,
        updated_at => Now
    },
    {ok, UpdatedState}.

%%====================================================================
%%% Internal Helper Functions
%%====================================================================

%% @private
-spec generate_orchestration_id() -> binary().
generate_orchestration_id() ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    <<?ORCHESTRATION_ID_PREFIX/binary, Timestamp/binary, "_", Unique/binary>>.

%% @private
-spec create_transportation_quote(map(), map()) -> map().
create_transportation_quote(POOrder, AppointmentData) ->
    #{
        quote_id => generate_id(<<"quote">>),
        po_id => maps:get(po_id, POOrder, <<"unknown">>),
        weight => maps:get(weight, AppointmentData, 0),
        destination => maps:get(destination, AppointmentData, <<"unknown">>),
        carrier_type => determine_carrier_type(AppointmentData),
        estimated_cost => calculate_shipping_cost(AppointmentData),
        created_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_shipment_notice(map(), map()) -> map().
create_shipment_notice(TransportationQuote, TransitData) ->
    #{
        notice_id => generate_id(<<"notice">>),
        quote_id => maps:get(quote_id, TransportationQuote, <<"unknown">>),
        shipment_id => maps:get(shipment_id, TransitData, generate_id(<<"shipment">>)),
        carrier => maps:get(carrier, TransitData, <<"unknown">>),
        origin => maps:get(origin, TransitData, <<"unknown">>),
        destination => maps:get(destination, TransitData, <<"unknown">>),
        issued_at => erlang:system_time(millisecond)
    }.

%% @private
-spec create_acceptance_certificate(map(), map()) -> map().
create_acceptance_certificate(ShipmentNotice, DeliveryData) ->
    #{
        certificate_id => generate_id(<<"cert">>),
        shipment_id => maps:get(shipment_id, ShipmentNotice, <<"unknown">>),
        delivery_id => maps:get(delivery_id, DeliveryData, <<"unknown">>),
        issued_by => <<"Master's in SCLM">>,
        issued_at => erlang:system_time(millisecond),
        valid_until => erlang:system_time(millisecond) + (30 * 86400000)
    }.

%% @private
-spec create_delivery_confirmation(shared_data(), map()) -> map().
create_delivery_confirmation(SharedData, _PaymentData) ->
    #{
        confirmation_id => generate_id(<<"confirmation">>),
        shipment_id => case maps:get(shipment_notice, SharedData, #{}) of
            #{shipment_id := ShipmentId} -> ShipmentId;
            _ -> <<"unknown">>
        end,
        delivery_date => erlang:system_time(millisecond),
        status => delivered
    }.

%% @private
-spec merge_carrier_data(map(), map()) -> map().
merge_carrier_data(POOrder, AppointmentData) ->
    maps:merge(AppointmentData, #{
        po_id => maps:get(po_id, POOrder, <<"unknown">>),
        total_amount => maps:get(total_amount, POOrder, 0)
    }).

%% @private
-spec merge_transit_data(map(), map()) -> map().
merge_transit_data(TransportationQuote, TransitData) ->
    maps:merge(TransitData, #{
        quote_id => maps:get(quote_id, TransportationQuote, <<"unknown">>)
    }).

%% @private
-spec merge_delivery_data(map(), map()) -> map().
merge_delivery_data(ShipmentNotice, DeliveryData) ->
    maps:merge(DeliveryData, #{
        shipment_id => maps:get(shipment_id, ShipmentNotice, <<"unknown">>)
    }).

%% @private
-spec merge_payment_data(shared_data(), map()) -> map().
merge_payment_data(SharedData, PaymentData) ->
    BaseData = #{
        po_amount => case maps:get(po_order, SharedData, #{}) of
            #{total_amount := Amount} -> Amount;
            _ -> 0
        end,
        has_claim => maps:get(claim_data, SharedData) =/= undefined,
        has_return => maps:get(return_data, SharedData) =/= undefined
    },
    maps:merge(PaymentData, BaseData).

%% @private
-spec determine_carrier_type(map()) -> tl | ltl.
determine_carrier_type(AppointmentData) ->
    Weight = maps:get(weight, AppointmentData, 0),
    case Weight >= 10000 of
        true -> tl;
        false -> ltl
    end.

%% @private
-spec calculate_shipping_cost(map()) -> number().
calculate_shipping_cost(AppointmentData) ->
    Weight = maps:get(weight, AppointmentData, 0),
    case Weight >= 10000 of
        true -> Weight * 0.05;  % TL rate
        false -> Weight * 0.10  % LTL rate
    end.

%% @private
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    Random = integer_to_binary(rand:uniform(1000000)),
    <<Prefix/binary, "_", Timestamp/binary, "_", Random/binary>>.

%% @private
-spec format_final_state(map()) -> map().
format_final_state(State) ->
    #{
        orchestration_id => maps:get(orchestration_id, State),
        status => maps:get(status, State),
        current_stage => maps:get(current_stage, State),
        stages_completed => lists:reverse(maps:get(stages_completed, State, [])),
        started_at => maps:get(started_at, State),
        completed_at => maps:get(updated_at, State),
        duration_ms => maps:get(updated_at, State) - maps:get(started_at, State),
        shared_data_summary => #{
            has_po_order => maps:size(maps:get(po_order, maps:get(shared_data, State, #{}))) > 0,
            has_transportation_quote => maps:size(maps:get(transportation_quote, maps:get(shared_data, State, #{}))) > 0,
            has_shipment_notice => maps:size(maps:get(shipment_notice, maps:get(shared_data, State, #{}))) > 0,
            has_acceptance_certificate => maps:size(maps:get(acceptance_certificate, maps:get(shared_data, State, #{}))) > 0,
            has_delivery_confirmation => maps:size(maps:get(delivery_confirmation, maps:get(shared_data, State, #{}))) > 0,
            has_payment_details => maps:size(maps:get(payment_details, maps:get(shared_data, State, #{}))) > 0,
            has_claim => maps:get(claim_data, maps:get(shared_data, State, #{})) =/= undefined,
            has_return => maps:get(return_data, maps:get(shared_data, State, #{})) =/= undefined
        },
        cancellation_reason => maps:get(cancellation_reason, State, undefined)
    }.
