%%%-------------------------------------------------------------------
%%% @doc
%%% Carrier Appointment Workflow - YAWL Pattern Example
%%%
%%% This module implements a carrier appointment workflow based on the
%%% YAWL reference specification from the order fulfillment example.
%%%
%%% Workflow Description:
%%% 1. Order Receiving - Trigger when new order arrives
%%% 2. Carrier Selection - Choose TL (truckload) vs LTL (less-than-truckload)
%%% 3. Carrier Appointment - Schedule appointment with selected carrier
%%% 4. Confirmation - Confirm appointment details
%%% 5. Exception Handling - Handle failures, retries
%%%
%%% Patterns Used:
%%% - Sequence: Order → Selection → Appointment → Confirmation
%%% - Exclusive Choice: TL vs LTL path
%%% - Parallel Split: Multiple carriers contacted simultaneously
%%% - Simple Merge: Single carrier selected
%%% - Cancellation: Cancel if no carrier available
%%% - Multi-Instance: Multiple carrier offers
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(carrier_appointment_workflow).
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
    simulate_tl_path/0,
    simulate_ltl_path/0,
    simulate_no_carrier_available/0,
    simulate_parallel_carrier_selection/0,
    simulate_carrier_timeout/0,
    simulate_retry_after_failure/0,
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

-define(WORKFLOW_ID, <<"carrier_appointment">>).
-define(MAX_CARRIER_OFFERS, 3).
-define(APPOINTMENT_TIMEOUT_MS, 300000). % 5 minutes

%%====================================================================
%%% Types
%%====================================================================

-type order_data() :: #{
    order_id => binary(),
    weight => number(),
    destination => binary(),
    deadline => integer()
}.

-type carrier_data() :: #{
    carrier_id => binary(),
    carrier_type => tl | ltl,
    rate => number(),
    estimated_delivery => integer()
}.

-type appointment_result() :: #{
    status => scheduled | failed | cancelled,
    carrier_id => binary() | undefined,
    appointment_time => integer() | undefined
}.

%%====================================================================
%%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    [
        start,
        order_received,
        carrier_selection,
        tl_path,
        ltl_path,
        parallel_carriers,
        carrier_appointment,
        confirmation,
        no_carrier_available,
        error_handler,
        retry_state,
        'end'
    ].

trsn_lst() ->
    [
        receive_order,
        evaluate_order,
        select_tl,
        select_ltl,
        contact_carriers,
        make_appointment,
        confirm_appointment,
        handle_no_carrier,
        handle_error,
        retry,
        cancel_workflow,
        complete
    ].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(Transition) ->
    case Transition of
        receive_order -> [start];
        evaluate_order -> [order_received];
        select_tl -> [carrier_selection];
        select_ltl -> [carrier_selection];
        contact_carriers -> [carrier_selection];
        make_appointment -> [parallel_carriers];
        confirm_appointment -> [carrier_appointment];
        handle_no_carrier -> [parallel_carriers];
        handle_error -> [error_handler];
        retry -> [retry_state];
        cancel_workflow -> [no_carrier_available];
        complete -> [confirmation]
    end.

postset(Transition) ->
    case Transition of
        receive_order -> [order_received];
        evaluate_order -> [tl_path, ltl_path, carrier_selection];
        select_tl -> [tl_path, carrier_appointment];
        select_ltl -> [ltl_path, carrier_appointment];
        contact_carriers -> [parallel_carriers];
        make_appointment -> [carrier_appointment];
        confirm_appointment -> [confirmation];
        handle_no_carrier -> [no_carrier_available];
        handle_error -> [retry_state];
        retry -> [carrier_selection];
        cancel_workflow -> ['end'];
        complete -> ['end']
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        receive_order ->
            case maps:get(start, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        evaluate_order ->
            case maps:get(order_received, Mode, []) of
                [_] -> true;
                _ -> false
            end;
        select_tl ->
            has_token(carrier_selection, Mode) andalso
            meets_tl_criteria(Mode);
        select_ltl ->
            has_token(carrier_selection, Mode) andalso
            not meets_tl_criteria(Mode);
        contact_carriers ->
            has_token(carrier_selection, Mode);
        make_appointment ->
            case maps:get(parallel_carriers, Mode, []) of
                [_|_] -> true;
                _ -> false
            end;
        confirm_appointment ->
            has_token(carrier_appointment, Mode);
        handle_no_carrier ->
            case maps:get(parallel_carriers, Mode, []) of
                [] -> false;
                Carriers when length(Carriers) > 0 -> true
            end;
        handle_error ->
            has_token(error_handler, Mode);
        retry ->
            has_token(retry_state, Mode) andalso
            retry_count_below_max(Mode);
        cancel_workflow ->
            has_token(no_carrier_available, Mode) andalso
            not retry_count_below_max(Mode);
        complete ->
            has_token(confirmation, Mode)
    end.

fire(Transition, _Mode, UsrInfo) ->
    OrderData = get_order_data(UsrInfo),
    CarrierData = get_carrier_data(UsrInfo),

    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        receive_order ->
            {produce, #{
                order_received => [{order, OrderData}]
            }};
        evaluate_order ->
            Weight = maps:get(weight, OrderData, 0),
            DecisionPlace = case Weight >= 10000 of
                true -> tl_path;
                false -> carrier_selection  % Will go through LTL or parallel
            end,
            {produce, #{
                DecisionPlace => [evaluate_result],
                carrier_selection => [selection_token]
            }};
        select_tl ->
            {produce, #{
                tl_path => [tl_selected],
                carrier_appointment => [tl_appointment]
            }};
        select_ltl ->
            {produce, #{
                ltl_path => [ltl_selected],
                carrier_appointment => [ltl_appointment]
            }};
        contact_carriers ->
            % Multi-instance: contact multiple carriers in parallel
            Carriers = lists:map(fun(I) ->
                {carrier, I}
            end, lists:seq(1, ?MAX_CARRIER_OFFERS)),
            {produce, #{
                parallel_carriers => Carriers
            }};
        make_appointment ->
            BestCarrier = select_best_carrier(CarrierData),
            {produce, #{
                carrier_appointment => [BestCarrier],
                parallel_carriers => []
            }};
        confirm_appointment ->
            AppointmentResult = create_appointment_result(CarrierData),
            {produce, #{
                confirmation => [AppointmentResult]
            }};
        handle_no_carrier ->
            {produce, #{
                no_carrier_available => [no_carrier],
                parallel_carriers => []
            }};
        handle_error ->
            {produce, #{
                retry_state => [retry_token]
            }};
        retry ->
            {produce, #{
                carrier_selection => [retry_selection]
            }};
        cancel_workflow ->
            {produce, #{
                'end' => [cancelled]
            }};
        complete ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete, complete),
            {produce, #{
                'end' => [completed]
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            case Token of
                workflow_token -> pass;
                _ -> pass
            end;
        order_received ->
            pass;
        error_handler ->
            case Token of
                error_token -> drop;
                _ -> pass
            end;
        no_carrier_available ->
            case Token of
                no_carrier -> pass;
                _ -> pass
            end;
        _ ->
            pass
    end.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create a new carrier appointment workflow
-spec create_workflow(map()) -> {ok, map()} | {error, term()}.
create_workflow(OrderData) ->
    WorkflowId = maps:get(order_id, OrderData, ?WORKFLOW_ID),
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => composite,
        order_data => OrderData,
        max_carrier_offers => maps:get(max_carrier_offers, OrderData, ?MAX_CARRIER_OFFERS),
        timeout => maps:get(timeout, OrderData, ?APPOINTMENT_TIMEOUT_MS)
    },
    {ok, Spec#{config => Config}}.

%% @doc Get the workflow specification
-spec get_workflow_spec() -> map().
get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Carrier Appointment Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Select and appoint carrier for order fulfillment">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [
            basic_sequential,
            exclusive_choice,
            parallel_split,
            simple_merge,
            cancelation,
            multi_instance
        ]
    }.

%% @doc Get initial marking for simulation
-spec get_initial_marking() -> map().
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate TL (truckload) carrier path
-spec simulate_tl_path() -> {ok, map()}.
simulate_tl_path() ->
    % Initialize XES logging for this workflow instance
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    OrderData = #{
        order_id => <<"order_tl_001">>,
        weight => 15000,  % Triggers TL path
        destination => <<"New York, NY">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    try
        Result = run_simulation(OrderData, [receive_order, evaluate_order, select_tl, confirm_appointment, complete]),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        Result
    catch
        _:_ ->
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {ok, #{}}
    end.

%% @doc Simulate LTL (less-than-truckload) carrier path
-spec simulate_ltl_path() -> {ok, map()}.
simulate_ltl_path() ->
    OrderData = #{
        order_id => <<"order_ltl_001">>,
        weight => 5000,  % Triggers LTL path
        destination => <<"Boston, MA">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    run_simulation(OrderData, [receive_order, evaluate_order, select_ltl, confirm_appointment, complete]).

%% @doc Simulate no carrier available scenario (cancellation)
-spec simulate_no_carrier_available() -> {ok, map()}.
simulate_no_carrier_available() ->
    OrderData = #{
        order_id => <<"order_fail_001">>,
        weight => 5000,
        destination => <<"Remote Location">>,
        deadline => erlang:system_time(millisecond) + 3600000,
        retry_count => 0,
        max_retries => 0  % No retries allowed
    },
    run_simulation(OrderData, [receive_order, evaluate_order, contact_carriers, handle_no_carrier, cancel_workflow]).

%% @doc Simulate parallel carrier selection
-spec simulate_parallel_carrier_selection() -> {ok, map()}.
simulate_parallel_carrier_selection() ->
    OrderData = #{
        order_id => <<"order_parallel_001">>,
        weight => 3000,
        destination => <<"Chicago, IL">>,
        deadline => erlang:system_time(millisecond) + 86400000
    },
    Carriers = [
        #{carrier_id => <<"carrier_1">>, rate => 500, estimated_delivery => 2},
        #{carrier_id => <<"carrier_2">>, rate => 450, estimated_delivery => 3},
        #{carrier_id => <<"carrier_3">>, rate => 475, estimated_delivery => 2}
    ],
    run_simulation_with_carriers(OrderData, Carriers, [receive_order, evaluate_order, contact_carriers, make_appointment, confirm_appointment, complete]).

%% @doc Simulate carrier timeout scenario
-spec simulate_carrier_timeout() -> {ok, map()}.
simulate_carrier_timeout() ->
    OrderData = #{
        order_id => <<"order_timeout_001">>,
        weight => 5000,
        destination => <<"Los Angeles, CA">>,
        deadline => erlang:system_time(millisecond) + 3600000,
        timeout => true
    },
    run_simulation(OrderData, [receive_order, evaluate_order, contact_carriers, handle_error, retry]).

%% @doc Simulate retry after failure
-spec simulate_retry_after_failure() -> {ok, map()}.
simulate_retry_after_failure() ->
    OrderData = #{
        order_id => <<"order_retry_001">>,
        weight => 5000,
        destination => <<"Seattle, WA">>,
        deadline => erlang:system_time(millisecond) + 86400000,
        retry_count => 1,
        max_retries => 3
    },
    run_simulation(OrderData, [receive_order, evaluate_order, contact_carriers, handle_error, retry, contact_carriers, make_appointment, complete]).

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
run_simulation(OrderData, Transitions) ->
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        order_received => [{order, OrderData}]
    },
    fire_transition_sequence(UpdatedMarking, Transitions).

%% @private
-spec run_simulation_with_carriers(map(), [map()], [atom()]) -> {ok, map()}.
run_simulation_with_carriers(OrderData, Carriers, Transitions) ->
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        order_received => [{order, OrderData}],
        carrier_data => Carriers
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
-spec meets_tl_criteria(map()) -> boolean().
meets_tl_criteria(Mode) ->
    OrderData = case maps:get(order_received, Mode, []) of
        [{order, Data}] -> Data;
        _ -> #{}
    end,
    Weight = maps:get(weight, OrderData, 0),
    Weight >= 10000.  % TL threshold: 10,000 lbs

%% @private
-spec retry_count_below_max(map()) -> boolean().
retry_count_below_max(Mode) ->
    OrderData = case maps:get(order_received, Mode, []) of
        [{order, Data}] -> Data;
        _ -> #{}
    end,
    RetryCount = maps:get(retry_count, OrderData, 0),
    MaxRetries = maps:get(max_retries, OrderData, 3),
    RetryCount < MaxRetries.

%% @private
-spec get_order_data(term()) -> map().
get_order_data([]) -> #{};
get_order_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(order_data, UsrInfo, #{});
get_order_data(_) -> #{}.

%% @private
-spec get_carrier_data(term()) -> [map()].
get_carrier_data([]) -> [];
get_carrier_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(carrier_data, UsrInfo, []);
get_carrier_data(_) -> [].

%% @private
-spec select_best_carrier([map()]) -> map().
select_best_carrier([]) ->
    #{carrier_id => <<"default_carrier">>, rate => 0, estimated_delivery => 0};
select_best_carrier(Carriers) ->
    % Select carrier with best rate (lowest) that meets delivery criteria
    Sorted = lists:sort(fun(A, B) ->
        maps:get(rate, A, 999999) =< maps:get(rate, B, 999999)
    end, Carriers),
    hd(Sorted).

%% @private
-spec create_appointment_result([map()]) -> map().
create_appointment_result([]) ->
    #{status => failed, carrier_id => undefined, appointment_time => undefined};
create_appointment_result(Carriers) ->
    BestCarrier = select_best_carrier(Carriers),
    #{
        status => scheduled,
        carrier_id => maps:get(carrier_id, BestCarrier),
        appointment_time => erlang:system_time(millisecond) + 86400000
    }.

%% @private
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.

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
