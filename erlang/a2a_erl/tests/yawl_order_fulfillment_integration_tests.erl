%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Order Fulfillment Integration Tests
%%%
%%% EUnit integration tests for the complete order fulfillment orchestration
%%% that chains all 5 YAWL workflows:
%%% 1. Ordering (Purchase Order) - ordering_workflow
%%% 2. Carrier Appointment - carrier_appointment_workflow
%%% 3. Freight in Transit - freight_in_transit_workflow
%%% 4. Freight Delivered - freight_delivered_workflow
%%% 5. Payment - payment_workflow
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_order_fulfillment_integration_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_order_fulfillment_integration_test_() ->
    [
        {"Full order fulfillment from order to payment",
         fun test_full_order_fulfillment/0},
        {"Ordering to carrier appointment handoff",
         fun test_ordering_to_carrier_handoff/0},
        {"Carrier appointment to freight transit handoff",
         fun test_carrier_to_transit_handoff/0},
        {"Freight transit to freight delivered handoff",
         fun test_transit_to_delivered_handoff/0},
        {"Freight delivered to payment handoff with claim",
         fun test_delivered_to_payment_handoff/0},
        {"Freight delivered to payment handoff with return",
         fun test_delivered_to_payment_with_return/0},
        {"Timeout cancellation at ordering stage",
         fun test_timeout_cancellation_ordering_stage/0},
        {"Timeout cancellation at carrier stage",
         fun test_timeout_cancellation_carrier_stage/0},
        {"Timeout cancellation at transit stage",
         fun test_timeout_cancellation_transit_stage/0},
        {"Timeout cancellation at delivery stage",
         fun test_timeout_cancellation_delivery_stage/0},
        {"Shared data propagation across stages",
         fun test_shared_data_propagation/0},
        {"Orchestration state management",
         fun test_orchestration_state_management/0},
        {"Cancellation propagation across all stages",
         fun test_cancellation_propagation/0}
    ].

%%====================================================================
%%% Test Cases
%%====================================================================

%% @doc Test complete order fulfillment flow from order to payment
test_full_order_fulfillment() ->
    % Start the orchestration
    POData = #{
        po_id => <<"PO-INTEGRATION-001">>,
        supplier_id => <<"SUPPLIER-INTEGRATION-001">>,
        items => [
            #{item_id => <<"ITEM-INT-001">>, quantity => 100, unit_price => 50.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-INT-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),
    ?assertEqual(ordering, maps:get(current_stage, OrderState)),
    ?assertEqual(running, maps:get(status, OrderState)),
    ?assertEqual([], maps:get(stages_completed, OrderState)),

    % Transition to carrier appointment
    CarrierData = #{
        order_id => <<"ORDER-INTEGRATION-001">>,
        weight => 12000,
        destination => <<"New York, NY">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),
    ?assertEqual(carrier_appointment, maps:get(current_stage, CarrierState)),
    ?assert(lists:member(ordering, maps:get(stages_completed, CarrierState))),

    % Transition to freight transit
    TransitData = #{
        shipment_id => <<"SHIPMENT-INTEGRATION-001">>,
        origin => <<"Los Angeles, CA">>,
        destination => <<"New York, NY">>,
        carrier => <<"FedEx Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (5 * 86400000),
        trackpoint_count => 3
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),
    ?assertEqual(freight_transit, maps:get(current_stage, TransitState)),
    ?assert(lists:member(carrier_appointment, maps:get(stages_completed, TransitState))),

    % Transition to freight delivered
    DeliveryData = #{
        delivery_id => <<"DELIVERY-INTEGRATION-001">>,
        order_id => <<"ORDER-INTEGRATION-001">>,
        customer_id => <<"CUSTOMER-INT-001">>,
        delivery_date => erlang:system_time(millisecond)
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),
    ?assertEqual(freight_delivered, maps:get(current_stage, DeliveredState)),
    ?assert(lists:member(freight_transit, maps:get(stages_completed, DeliveredState))),

    % Transition to payment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-INTEGRATION-001">>,
        invoice_required => true,
        prepaid => true,
        amount => 5000.00,
        balance => 0
    },
    {ok, PaymentState} = order_fulfillment_orchestration:transition_to_payment(DeliveredState, PaymentData),
    ?assertEqual(payment, maps:get(current_stage, PaymentState)),
    ?assert(lists:member(freight_delivered, maps:get(stages_completed, PaymentState))),

    % Verify shared data is populated
    SharedData = maps:get(shared_data, PaymentState),
    ?assert(maps:is_key(po_order, SharedData)),
    ?assert(maps:is_key(transportation_quote, SharedData)),
    ?assert(maps:is_key(shipment_notice, SharedData)),
    ?assert(maps:is_key(acceptance_certificate, SharedData)),
    ?assert(maps:is_key(delivery_confirmation, SharedData)).

%% @doc Test ordering to carrier appointment handoff with data passing
test_ordering_to_carrier_handoff() ->
    POData = #{
        po_id => <<"PO-HANDOFF-001">>,
        supplier_id => <<"SUPPLIER-HANDOFF-001">>,
        items => [
            #{item_id => <<"ITEM-HANDOFF-001">>, quantity => 50, unit_price => 100.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-HANDOFF-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    % Verify initial shared data
    InitialSharedData = maps:get(shared_data, OrderState),
    ?assertEqual(POData, maps:get(po_order, InitialSharedData)),

    % Transition to carrier
    CarrierData = #{
        order_id => <<"ORDER-HANDOFF-001">>,
        weight => 8000,
        destination => <<"Chicago, IL">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    % Verify transportation quote was created
    CarrierSharedData = maps:get(shared_data, CarrierState),
    TransportationQuote = maps:get(transportation_quote, CarrierSharedData),
    ?assert(maps:is_key(quote_id, TransportationQuote)),
    ?assertEqual(<<"PO-HANDOFF-001">>, maps:get(po_id, TransportationQuote)),
    ?assertEqual(ltl, maps:get(carrier_type, TransportationQuote)),

    % Verify stage completion tracking
    ?assert(lists:member(ordering, maps:get(stages_completed, CarrierState))).

%% @doc Test carrier appointment to freight transit handoff
test_carrier_to_transit_handoff() ->
    % Start with ordering complete
    POData = #{
        po_id => <<"PO-TRANSIT-001">>,
        supplier_id => <<"SUPPLIER-TRANSIT-001">>,
        items => [],
        total_amount => 3000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TRANSIT-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-TRANSIT-001">>,
        weight => 7000,
        destination => <<"Boston, MA">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    % Transition to transit
    TransitData = #{
        shipment_id => <<"SHIPMENT-TRANSIT-001">>,
        origin => <<"Miami, FL">>,
        destination => <<"Boston, MA">>,
        carrier => <<"Estes Express">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (4 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    % Verify shipment notice was created
    TransitSharedData = maps:get(shared_data, TransitState),
    ShipmentNotice = maps:get(shipment_notice, TransitSharedData),
    ?assert(maps:is_key(notice_id, ShipmentNotice)),
    ?assertEqual(<<"SHIPMENT-TRANSIT-001">>, maps:get(shipment_id, ShipmentNotice)),
    ?assertEqual(<<"Estes Express">>, maps:get(carrier, ShipmentNotice)),

    % Verify stage completions
    CompletedStages = maps:get(stages_completed, TransitState),
    ?assert(lists:member(ordering, CompletedStages)),
    ?assert(lists:member(carrier_appointment, CompletedStages)).

%% @doc Test freight transit to freight delivered handoff
test_transit_to_delivered_handoff() ->
    % Run through first three stages
    POData = #{
        po_id => <<"PO-DELIVERED-001">>,
        supplier_id => <<"SUPPLIER-DELIVERED-001">>,
        items => [],
        total_amount => 4000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-DELIVERED-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-DELIVERED-001">>,
        weight => 9000,
        destination => <<"Denver, CO">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-DELIVERED-001">>,
        origin => <<"Phoenix, AZ">>,
        destination => <<"Denver, CO">>,
        carrier => <<"ABF Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (3 * 86400000),
        trackpoint_count => 3
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    % Transition to delivered
    DeliveryData = #{
        delivery_id => <<"DELIVERY-DELIVERED-001">>,
        order_id => <<"ORDER-DELIVERED-001">>,
        customer_id => <<"CUSTOMER-DELIVERED-001">>,
        delivery_date => erlang:system_time(millisecond)
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),

    % Verify acceptance certificate was created
    DeliveredSharedData = maps:get(shared_data, DeliveredState),
    AcceptanceCertificate = maps:get(acceptance_certificate, DeliveredSharedData),
    ?assert(maps:is_key(certificate_id, AcceptanceCertificate)),
    ?assertEqual(<<"SHIPMENT-DELIVERED-001">>, maps:get(shipment_id, AcceptanceCertificate)),
    ?assertEqual(<<"DELIVERY-DELIVERED-001">>, maps:get(delivery_id, AcceptanceCertificate)),
    ?assertEqual(<<"Master's in SCLM">>, maps:get(issued_by, AcceptanceCertificate)),

    % Verify all previous stages completed
    CompletedStages = maps:get(stages_completed, DeliveredState),
    ?assert(lists:member(ordering, CompletedStages)),
    ?assert(lists:member(carrier_appointment, CompletedStages)),
    ?assert(lists:member(freight_transit, CompletedStages)).

%% @doc Test freight delivered to payment handoff with claim scenario
test_delivered_to_payment_handoff() ->
    % Run through first four stages with a claim
    POData = #{
        po_id => <<"PO-PAYMENT-001">>,
        supplier_id => <<"SUPPLIER-PAYMENT-001">>,
        items => [],
        total_amount => 6000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-PAYMENT-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-PAYMENT-001">>,
        weight => 11000,
        destination => <<"Portland, OR">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-PAYMENT-001">>,
        origin => <<"Dallas, TX">>,
        destination => <<"Portland, OR">>,
        carrier => <<"FedEx Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (5 * 86400000),
        trackpoint_count => 3
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    DeliveryData = #{
        delivery_id => <<"DELIVERY-PAYMENT-001">>,
        order_id => <<"ORDER-PAYMENT-001">>,
        customer_id => <<"CUSTOMER-PAYMENT-001">>,
        delivery_date => erlang:system_time(millisecond)
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),

    % Add claim data
    ClaimData = #{
        claim_id => <<"CLAIM-PAYMENT-001">>,
        delivery_id => <<"DELIVERY-PAYMENT-001">>,
        claim_type => damage,
        description => <<"Items damaged in transit">>,
        amount => 500,
        evidence => [<<"photo1.jpg">>],
        filed_date => erlang:system_time(millisecond),
        approved => true
    },
    {ok, UpdatedDeliveredState} = order_fulfillment_orchestration:update_shared_data(
        DeliveredState, claim_data, ClaimData
    ),

    % Transition to payment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-PAYMENT-001">>,
        invoice_required => true,
        prepaid => false,
        amount => 5500.00,  % Reduced after claim
        balance => 0
    },
    {ok, PaymentState} = order_fulfillment_orchestration:transition_to_payment(UpdatedDeliveredState, PaymentData),

    % Verify delivery confirmation and payment details
    PaymentSharedData = maps:get(shared_data, PaymentState),
    DeliveryConfirmation = maps:get(delivery_confirmation, PaymentSharedData),
    ?assert(maps:is_key(confirmation_id, DeliveryConfirmation)),
    ?assertEqual(delivered, maps:get(status, DeliveryConfirmation)),

    % Verify claim is tracked in shared data
    ?assertEqual(ClaimData, maps:get(claim_data, PaymentSharedData)).

%% @doc Test freight delivered to payment handoff with return scenario
test_delivered_to_payment_with_return() ->
    % Run through first four stages with a return
    POData = #{
        po_id => <<"PO-RETURN-INT-001">>,
        supplier_id => <<"SUPPLIER-RETURN-INT-001">>,
        items => [],
        total_amount => 3500.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-RETURN-INT-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-RETURN-INT-001">>,
        weight => 6500,
        destination => <<"San Francisco, CA">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-RETURN-INT-001">>,
        origin => <<"Seattle, WA">>,
        destination => <<"San Francisco, CA">>,
        carrier => <<"UPS Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (3 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    DeliveryData = #{
        delivery_id => <<"DELIVERY-RETURN-INT-001">>,
        order_id => <<"ORDER-RETURN-INT-001">>,
        customer_id => <<"CUSTOMER-RETURN-INT-001">>,
        delivery_date => erlang:system_time(millisecond)
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),

    % Add return data
    ReturnData = #{
        return_id => <<"RETURN-INT-001">>,
        delivery_id => <<"DELIVERY-RETURN-INT-001">>,
        reason => <<"Product not as described">>,
        items => [{<<"ITEM-RETURN-INT-001">>, 3}],
        return_fee => 25,
        filed_date => erlang:system_time(millisecond),
        approved => true
    },
    {ok, UpdatedDeliveredState} = order_fulfillment_orchestration:update_shared_data(
        DeliveredState, return_data, ReturnData
    ),

    % Transition to payment
    PaymentData = #{
        shipment_id => <<"SHIPMENT-RETURN-INT-001">>,
        invoice_required => true,
        prepaid => true,
        amount => 3500.00,
        balance => -500.00  % Credit for returned items
    },
    {ok, PaymentState} = order_fulfillment_orchestration:transition_to_payment(UpdatedDeliveredState, PaymentData),

    % Verify return is tracked in shared data
    PaymentSharedData = maps:get(shared_data, PaymentState),
    ?assertEqual(ReturnData, maps:get(return_data, PaymentSharedData)).

%% @doc Test timeout cancellation at ordering stage
test_timeout_cancellation_ordering_stage() ->
    % Create PO that will timeout
    POData = #{
        po_id => <<"PO-TIMEOUT-ORDER-001">>,
        supplier_id => <<"SUPPLIER-TIMEOUT-ORDER-001">>,
        items => [],
        total_amount => 2000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TIMEOUT-ORDER-001">>,
        created_at => erlang:system_time(millisecond) - (4 * 86400000)  % 4 days ago
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    % Simulate timeout
    {ok, CancelledState} = order_fulfillment_orchestration:cancel_order_fulfillment(
        OrderState, {po_timeout, <<"PO timed out after 3 days">>}
    ),

    ?assertEqual(cancelled, maps:get(current_stage, CancelledState)),
    ?assertEqual(cancelled, maps:get(status, CancelledState)),
    ?assertMatch({po_timeout, _}, maps:get(cancellation_reason, CancelledState)).

%% @doc Test timeout cancellation at carrier stage
test_timeout_cancellation_carrier_stage() ->
    % Progress through ordering, then timeout at carrier
    POData = #{
        po_id => <<"PO-TIMEOUT-CARRIER-001">>,
        supplier_id => <<"SUPPLIER-TIMEOUT-CARRIER-001">>,
        items => [],
        total_amount => 3000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TIMEOUT-CARRIER-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-TIMEOUT-CARRIER-001">>,
        weight => 5000,
        destination => <<"Remote Location">>,
        deadline => erlang:system_time(millisecond) + 3600000,
        no_carrier_available => true
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    % Simulate no carrier available cancellation
    {ok, CancelledState} = order_fulfillment_orchestration:cancel_order_fulfillment(
        CarrierState, {no_carrier_available, <<"No carrier available for route">>}
    ),

    ?assertEqual(cancelled, maps:get(current_stage, CancelledState)),
    ?assertEqual(cancelled, maps:get(status, CancelledState)),
    ?assertMatch({no_carrier_available, _}, maps:get(cancellation_reason, CancelledState)).

%% @doc Test timeout cancellation at transit stage
test_timeout_cancellation_transit_stage() ->
    % Progress through ordering and carrier, then timeout at transit
    POData = #{
        po_id => <<"PO-TIMEOUT-TRANSIT-001">>,
        supplier_id => <<"SUPPLIER-TIMEOUT-TRANSIT-001">>,
        items => [],
        total_amount => 4000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TIMEOUT-TRANSIT-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-TIMEOUT-TRANSIT-001">>,
        weight => 8000,
        destination => <<"Minneapolis, MN">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-TIMEOUT-TRANSIT-001">>,
        origin => <<"Austin, TX">>,
        destination => <<"Minneapolis, MN">>,
        carrier => <<"Roadrunner Transit">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (7 * 86400000),
        trackpoint_count => 5,
        lost_shipment => true
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    % Simulate lost shipment cancellation
    {ok, CancelledState} = order_fulfillment_orchestration:cancel_order_fulfillment(
        TransitState, {shipment_lost, <<"Shipment lost in transit">>}
    ),

    ?assertEqual(cancelled, maps:get(current_stage, CancelledState)),
    ?assertEqual(cancelled, maps:get(status, CancelledState)),
    ?assertMatch({shipment_lost, _}, maps:get(cancellation_reason, CancelledState)).

%% @doc Test timeout cancellation at delivery stage
test_timeout_cancellation_delivery_stage() ->
    % Progress through first three stages, then timeout at delivery
    POData = #{
        po_id => <<"PO-TIMEOUT-DELIVERY-001">>,
        supplier_id => <<"SUPPLIER-TIMEOUT-DELIVERY-001">>,
        items => [],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-TIMEOUT-DELIVERY-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    CarrierData = #{
        order_id => <<"ORDER-TIMEOUT-DELIVERY-001">>,
        weight => 10000,
        destination => <<"Las Vegas, NV">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    TransitData = #{
        shipment_id => <<"SHIPMENT-TIMEOUT-DELIVERY-001">>,
        origin => <<"Salt Lake City, UT">>,
        destination => <<"Las Vegas, NV">>,
        carrier => <<"Central Transport">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (2 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    DeliveryData = #{
        delivery_id => <<"DELIVERY-TIMEOUT-DELIVERY-001">>,
        order_id => <<"ORDER-TIMEOUT-DELIVERY-001">>,
        customer_id => <<"CUSTOMER-TIMEOUT-DELIVERY-001">>,
        delivery_date => erlang:system_time(millisecond) - (15 * 86400000),  % 15 days ago - claims expired
        claims_expired => true
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),

    % Simulate claims expired cancellation
    {ok, CancelledState} = order_fulfillment_orchestration:cancel_order_fulfillment(
        DeliveredState, {claims_expired, <<"Claims period expired with no resolution">>}
    ),

    ?assertEqual(cancelled, maps:get(current_stage, CancelledState)),
    ?assertEqual(cancelled, maps:get(status, CancelledState)),
    ?assertMatch({claims_expired, _}, maps:get(cancellation_reason, CancelledState)).

%% @doc Test shared data propagation across all stages
test_shared_data_propagation() ->
    POData = #{
        po_id => <<"PO-SHARED-001">>,
        supplier_id => <<"SUPPLIER-SHARED-001">>,
        items => [],
        total_amount => 2500.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-SHARED-001">>,
        custom_field => <<"preserved_data">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    % Verify PO data is in shared data
    InitialSharedData = maps:get(shared_data, OrderState),
    ?assertEqual(<<"preserved_data">>, maps:get(custom_field, maps:get(po_order, InitialSharedData))),

    CarrierData = #{order_id => <<"ORDER-SHARED-001">>, weight => 7000, destination => <<"Miami, FL">>},
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    % Verify transportation quote added but PO data preserved
    CarrierSharedData = maps:get(shared_data, CarrierState),
    ?assert(maps:is_key(transportation_quote, CarrierSharedData)),
    ?assertEqual(<<"preserved_data">>, maps:get(custom_field, maps:get(po_order, CarrierSharedData))),

    TransitData = #{
        shipment_id => <<"SHIPMENT-SHARED-001">>,
        origin => <<"Atlanta, GA">>,
        destination => <<"Miami, FL">>,
        carrier => <<"Saia">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (3 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    % Verify shipment notice added but previous data preserved
    TransitSharedData = maps:get(shared_data, TransitState),
    ?assert(maps:is_key(shipment_notice, TransitSharedData)),
    ?assert(maps:is_key(transportation_quote, TransitSharedData)),
    ?assertEqual(<<"preserved_data">>, maps:get(custom_field, maps:get(po_order, TransitSharedData))),

    DeliveryData = #{
        delivery_id => <<"DELIVERY-SHARED-001">>,
        order_id => <<"ORDER-SHARED-001">>,
        customer_id => <<"CUSTOMER-SHARED-001">>,
        delivery_date => erlang:system_time(millisecond)
    },
    {ok, DeliveredState} = order_fulfillment_orchestration:transition_to_freight_delivered(TransitState, DeliveryData),

    % Verify all shared data accumulated
    DeliveredSharedData = maps:get(shared_data, DeliveredState),
    ?assert(maps:is_key(acceptance_certificate, DeliveredSharedData)),
    ?assert(maps:is_key(shipment_notice, DeliveredSharedData)),
    ?assert(maps:is_key(transportation_quote, DeliveredSharedData)),
    ?assertEqual(<<"preserved_data">>, maps:get(custom_field, maps:get(po_order, DeliveredSharedData))).

%% @doc Test orchestration state management
test_orchestration_state_management() ->
    POData = #{
        po_id => <<"PO-STATE-001">>,
        supplier_id => <<"SUPPLIER-STATE-001">>,
        items => [],
        total_amount => 1500.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-STATE-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    % Verify initial state structure
    ?assert(maps:is_key(orchestration_id, OrderState)),
    ?assert(maps:is_key(current_stage, OrderState)),
    ?assert(maps:is_key(stages_completed, OrderState)),
    ?assert(maps:is_key(shared_data, OrderState)),
    ?assert(maps:is_key(status, OrderState)),
    ?assert(maps:is_key(started_at, OrderState)),
    ?assert(maps:is_key(updated_at, OrderState)),
    ?assert(maps:is_key(errors, OrderState)),
    ?assert(maps:is_key(cancellation_reason, OrderState)),

    % Verify state transitions
    CarrierData = #{order_id => <<"ORDER-STATE-001">>, weight => 6000, destination => <<"Detroit, MI">>},
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    ?assertEqual(carrier_appointment, maps:get(current_stage, CarrierState)),
    ?assert(maps:get(updated_at, CarrierState) >= maps:get(started_at, CarrierState)),
    ?assertEqual([], maps:get(errors, CarrierState)),

    % Verify updated_at increments with each transition
    TransitData = #{
        shipment_id => <<"SHIPMENT-STATE-001">>,
        origin => <<"Cleveland, OH">>,
        destination => <<"Detroit, MI">>,
        carrier => <<"Pitt Ohio">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (2 * 86400000),
        trackpoint_count => 1
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    ?assert(maps:get(updated_at, TransitState) > maps:get(updated_at, CarrierState)).

%% @doc Test cancellation propagation across all stages
test_cancellation_propagation() ->
    POData = #{
        po_id => <<"PO-CANCEL-PROP-001">>,
        supplier_id => <<"SUPPLIER-CANCEL-PROP-001">>,
        items => [],
        total_amount => 7500.00,
        currency => <<"USD">>,
        requested_by => <<"CUSTOMER-CANCEL-PROP-001">>,
        created_at => erlang:system_time(millisecond)
    },

    {ok, OrderState} = order_fulfillment_orchestration:start_order_fulfillment(POData),

    % Cancel at ordering stage
    {ok, CancelledAtOrdering} = order_fulfillment_orchestration:cancel_order_fulfillment(
        OrderState, customer_cancellation
    ),
    ?assertEqual(cancelled, maps:get(status, CancelledAtOrdering)),
    ?assertEqual(customer_cancellation, maps:get(cancellation_reason, CancelledAtOrdering)),

    % Progress to carrier and cancel
    CarrierData = #{order_id => <<"ORDER-CANCEL-PROP-001">>, weight => 9000, destination => <<"Milwaukee, WI">>},
    {ok, CarrierState} = order_fulfillment_orchestration:transition_to_carrier_appointment(OrderState, CarrierData),

    {ok, CancelledAtCarrier} = order_fulfillment_orchestration:cancel_order_fulfillment(
        CarrierState, carrier_unavailable
    ),
    ?assertEqual(cancelled, maps:get(status, CancelledAtCarrier)),
    ?assertEqual(carrier_unavailable, maps:get(cancellation_reason, CancelledAtCarrier)),

    % Progress to transit and cancel
    TransitData = #{
        shipment_id => <<"SHIPMENT-CANCEL-PROP-001">>,
        origin => <<"Kansas City, MO">>,
        destination => <<"Milwaukee, WI">>,
        carrier => <<"Dayton Freight">>,
        estimated_departure => erlang:system_time(millisecond),
        estimated_arrival => erlang:system_time(millisecond) + (3 * 86400000),
        trackpoint_count => 2
    },
    {ok, TransitState} = order_fulfillment_orchestration:transition_to_freight_transit(CarrierState, TransitData),

    {ok, CancelledAtTransit} = order_fulfillment_orchestration:cancel_order_fulfillment(
        TransitState, weather_delay
    ),
    ?assertEqual(cancelled, maps:get(status, CancelledAtTransit)),
    ?assertEqual(weather_delay, maps:get(cancellation_reason, CancelledAtTransit)).
