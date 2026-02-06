%%%-------------------------------------------------------------------
%%% @doc
%%% Freight Delivered Workflow - YAWL Pattern Example
%%%
%%% This module implements a freight delivered workflow based on the
%%% YAWL reference specification from the order fulfillment example.
%%%
%%% Workflow Description:
%%% 1. Freight Delivered - Trigger when freight reaches destination
%%% 2. Claims Timer - Start deadline timer for claims/returns
%%% 3. Loss/Damage OR Return - Exclusive choice for claim type
%%% 4. Authorization - Approve or reject claim/return
%%% 5. Complete - Finalize workflow
%%%
%%% Patterns Used:
%%% - Sequence: Freight → Timer → (Claim/Return) → Authorization → Complete
%%% - Exclusive Choice: Loss/Damage OR Return path
%%% - Deferred Choice: Customer chooses claim type after timer
%%% - Cancellation: Timer cancels claim opportunity
%%% - Discriminator: Single completion point
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(freight_delivered_workflow).
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
    simulate_loss_damage_claim_approved/0,
    simulate_loss_damage_claim_rejected/0,
    simulate_return_merchandise_approved/0,
    simulate_return_merchandise_rejected/0,
    simulate_deadline_expired_no_claim/0,
    simulate_claim_filed_before_deadline/0,
    simulate_claim_after_deadline/0,
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

-define(WORKFLOW_ID, <<"freight_delivered">>).
-define(DEFAULT_CLAIMS_DEADLINE_MS, 1209600000). % 14 days in milliseconds
-define(MAX_CLAIM_AMOUNT, 100000). % $100,000 max claim

%%====================================================================
%%% Types
%%====================================================================

-type delivery_data() :: #{
    delivery_id => binary(),
    order_id => binary(),
    delivery_date => integer(),
    customer_id => binary()
}.

-type loss_damage_claim() :: #{
    claim_id => binary(),
    delivery_id => binary(),
    claim_type => loss | damage,
    description => binary(),
    amount => number(),
    evidence => [binary()],
    filed_date => integer()
}.

-type return_merchandise() :: #{
    return_id => binary(),
    delivery_id => binary(),
    reason => binary(),
    items => [{binary(), integer()}], % {item_id, quantity}
    return_fee => number(),
    filed_date => integer()
}.

-type claim_approval() :: #{
    claim_id => binary(),
    approved => boolean(),
    approved_by => binary(),
    approved_date => integer(),
    notes => binary()
}.

-type return_approval() :: #{
    return_id => binary(),
    approved => boolean(),
    approved_by => binary(),
    approved_date => integer(),
    rma_number => binary() | undefined,
    notes => binary()
}.

%%====================================================================
%%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    [
        start,
        freight_delivered,
        claims_timer_started,
        deadline_expired,
        loss_damage_claim,
        return_merchandise,
        claim_pending,
        return_pending,
        claim_authorized,
        return_authorized,
        claim_rejected,
        return_rejected,
        no_claim_filed,
        'end'
    ].

trsn_lst() ->
    [
        start_claims_timer,
        claims_deadline_reached,
        lodge_loss_damage_claim,
        lodge_return_merchandise,
        authorize_claim,
        authorize_return,
        reject_claim,
        reject_return,
        complete_workflow
    ].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(Transition) ->
    case Transition of
        start_claims_timer -> [start];
        claims_deadline_reached -> [claims_timer_started];
        lodge_loss_damage_claim -> [freight_delivered];
        lodge_return_merchandise -> [freight_delivered];
        authorize_claim -> [claim_pending];
        authorize_return -> [return_pending];
        reject_claim -> [claim_pending];
        reject_return -> [return_pending];
        complete_workflow -> [claim_authorized, return_authorized, no_claim_filed]
    end.

postset(Transition) ->
    case Transition of
        start_claims_timer -> [freight_delivered, claims_timer_started];
        claims_deadline_reached -> [deadline_expired];
        lodge_loss_damage_claim -> [claim_pending];
        lodge_return_merchandise -> [return_pending];
        authorize_claim -> [claim_authorized];
        authorize_return -> [return_authorized];
        reject_claim -> [claim_rejected];
        reject_return -> [return_rejected];
        complete_workflow -> ['end']
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        start_claims_timer ->
            has_token(start, Mode);
        claims_deadline_reached ->
            has_token(claims_timer_started, Mode) andalso
            timer_expired(Mode);
        lodge_loss_damage_claim ->
            has_token(freight_delivered, Mode) andalso
            not deadline_expired(Mode) andalso
            not claim_or_return_pending(Mode);
        lodge_return_merchandise ->
            has_token(freight_delivered, Mode) andalso
            not deadline_expired(Mode) andalso
            not claim_or_return_pending(Mode);
        authorize_claim ->
            has_token(claim_pending, Mode) andalso
            claim_meets_criteria(Mode);
        authorize_return ->
            has_token(return_pending, Mode) andalso
            return_meets_criteria(Mode);
        reject_claim ->
            has_token(claim_pending, Mode) andalso
            not claim_meets_criteria(Mode);
        reject_return ->
            has_token(return_pending, Mode) andalso
            not return_meets_criteria(Mode);
        complete_workflow ->
            (has_token(claim_authorized, Mode) orelse
             has_token(return_authorized, Mode) orelse
             has_token(no_claim_filed, Mode)) andalso
             workflow_complete(Mode)
    end.

fire(Transition, Mode, UsrInfo) ->
    DeliveryData = get_delivery_data(UsrInfo),
    ClaimData = get_claim_data(UsrInfo),
    ReturnData = get_return_data(UsrInfo),

    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        start_claims_timer ->
            TimerToken = create_timer_token(DeliveryData),
            {produce, #{
                freight_delivered => [delivered_token],
                claims_timer_started => [TimerToken]
            }};
        claims_deadline_reached ->
            % Deadline expired - no claims can be filed
            {produce, #{
                deadline_expired => [expired_token],
                no_claim_filed => [no_claim],
                claims_timer_started => []
            }};
        lodge_loss_damage_claim ->
            ClaimToken = create_claim_token(ClaimData),
            {produce, #{
                claim_pending => [ClaimToken],
                freight_delivered => []
            }};
        lodge_return_merchandise ->
            ReturnToken = create_return_token(ReturnData),
            {produce, #{
                return_pending => [ReturnToken],
                freight_delivered => []
            }};
        authorize_claim ->
            Approval = create_claim_approval(ClaimData),
            {produce, #{
                claim_authorized => [Approval],
                claim_pending => []
            }};
        authorize_return ->
            Approval = create_return_approval(ReturnData),
            {produce, #{
                return_authorized => [Approval],
                return_pending => []
            }};
        reject_claim ->
            Rejection = create_claim_rejection(ClaimData),
            {produce, #{
                claim_rejected => [Rejection],
                claim_pending => []
            }};
        reject_return ->
            Rejection = create_return_rejection(ReturnData),
            {produce, #{
                return_rejected => [Rejection],
                return_pending => []
            }};
        complete_workflow ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete_workflow, complete),
            Result = create_completion_result(Mode, UsrInfo),
            {produce, #{
                'end' => [Result],
                claim_authorized => [],
                return_authorized => [],
                no_claim_filed => []
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            case Token of
                workflow_token -> pass;
                _ -> pass
            end;
        claims_timer_started ->
            case Token of
                {timer, _} -> pass;
                _ -> pass
            end;
        claim_pending ->
            case Token of
                {claim, _} -> pass;
                _ -> pass
            end;
        return_pending ->
            case Token of
                {return, _} -> pass;
                _ -> pass
            end;
        deadline_expired ->
            case Token of
                expired_token -> drop;
                _ -> pass
            end;
        _ ->
            pass
    end.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create a new freight delivered workflow
-spec create_workflow(map()) -> {ok, map()} | {error, term()}.
create_workflow(DeliveryData) ->
    WorkflowId = maps:get(delivery_id, DeliveryData, ?WORKFLOW_ID),
    Spec = get_workflow_spec(),
    Deadline = maps:get(claims_deadline_ms, DeliveryData, ?DEFAULT_CLAIMS_DEADLINE_MS),
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => composite,
        delivery_data => DeliveryData,
        claims_deadline_ms => Deadline,
        max_claim_amount => maps:get(max_claim_amount, DeliveryData, ?MAX_CLAIM_AMOUNT)
    },
    {ok, Spec#{config => Config}}.

%% @doc Get the workflow specification
-spec get_workflow_spec() -> map().
get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Freight Delivered Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Handle claims and returns after freight delivery">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [
            basic_sequential,
            exclusive_choice,
            deferred_choice,
            cancelation,
            discriminator
        ]
    }.

%% @doc Get initial marking for simulation
-spec get_initial_marking() -> map().
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate loss/damage claim that is approved
-spec simulate_loss_damage_claim_approved() -> {ok, map()}.
simulate_loss_damage_claim_approved() ->
    % Initialize XES logging for this workflow instance
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    DeliveryData = #{
        delivery_id => <<"delivery_001">>,
        order_id => <<"order_001">>,
        customer_id => <<"customer_123">>,
        delivery_date => erlang:system_time(millisecond)
    },
    ClaimData = #{
        claim_id => <<"claim_001">>,
        delivery_id => <<"delivery_001">>,
        claim_type => damage,
        description => <<"Package arrived with visible damage">>,
        amount => 5000,
        evidence => [<<"photo1.jpg">>, <<"photo2.jpg">>],
        filed_date => erlang:system_time(millisecond),
        approved => true
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        claim_data => ClaimData
    },
    InitialMarking = get_initial_marking(),
    try
        Result = run_simulation(InitialMarking, UsrInfo, [
            start_claims_timer,
            lodge_loss_damage_claim,
            authorize_claim,
            complete_workflow
        ]),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        Result
    catch
        _:_ ->
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {ok, #{}}
    end.

%% @doc Simulate loss/damage claim that is rejected
-spec simulate_loss_damage_claim_rejected() -> {ok, map()}.
simulate_loss_damage_claim_rejected() ->
    DeliveryData = #{
        delivery_id => <<"delivery_002">>,
        order_id => <<"order_002">>,
        customer_id => <<"customer_456">>,
        delivery_date => erlang:system_time(millisecond)
    },
    ClaimData = #{
        claim_id => <<"claim_002">>,
        delivery_id => <<"delivery_002">>,
        claim_type => loss,
        description => <<"Package reported missing but signature on file">>,
        amount => 15000,
        evidence => [],
        filed_date => erlang:system_time(millisecond),
        approved => false,
        rejection_reason => <<"Proof of delivery available">>
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        claim_data => ClaimData
    },
    InitialMarking = get_initial_marking(),
    run_simulation(InitialMarking, UsrInfo, [
        start_claims_timer,
        lodge_loss_damage_claim,
        reject_claim
    ]).

%% @doc Simulate return merchandise request that is approved
-spec simulate_return_merchandise_approved() -> {ok, map()}.
simulate_return_merchandise_approved() ->
    DeliveryData = #{
        delivery_id => <<"delivery_003">>,
        order_id => <<"order_003">>,
        customer_id => <<"customer_789">>,
        delivery_date => erlang:system_time(millisecond)
    },
    ReturnData = #{
        return_id => <<"return_001">>,
        delivery_id => <<"delivery_003">>,
        reason => <<"Product not as described">>,
        items => [{<<"item_001">>, 2}, {<<"item_002">>, 1}],
        return_fee => 0,
        filed_date => erlang:system_time(millisecond),
        approved => true
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        return_data => ReturnData
    },
    InitialMarking = get_initial_marking(),
    run_simulation(InitialMarking, UsrInfo, [
        start_claims_timer,
        lodge_return_merchandise,
        authorize_return,
        complete_workflow
    ]).

%% @doc Simulate return merchandise request that is rejected
-spec simulate_return_merchandise_rejected() -> {ok, map()}.
simulate_return_merchandise_rejected() ->
    DeliveryData = #{
        delivery_id => <<"delivery_004">>,
        order_id => <<"order_004">>,
        customer_id => <<"customer_101">>,
        delivery_date => erlang:system_time(millisecond)
    },
    ReturnData = #{
        return_id => <<"return_002">>,
        delivery_id => <<"delivery_004">>,
        reason => <<"Changed mind">>,
        items => [{<<"item_003">>, 1}],
        return_fee => 50,
        filed_date => erlang:system_time(millisecond),
        approved => false,
        rejection_reason => <<"Return window expired">>
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        return_data => ReturnData
    },
    InitialMarking = get_initial_marking(),
    run_simulation(InitialMarking, UsrInfo, [
        start_claims_timer,
        lodge_return_merchandise,
        reject_return
    ]).

%% @doc Simulate deadline expiration with no claim filed
-spec simulate_deadline_expired_no_claim() -> {ok, map()}.
simulate_deadline_expired_no_claim() ->
    DeliveryData = #{
        delivery_id => <<"delivery_005">>,
        order_id => <<"order_005">>,
        customer_id => <<"customer_202">>,
        delivery_date => erlang:system_time(millisecond) - ?DEFAULT_CLAIMS_DEADLINE_MS - 1000000
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        timer_expired => true
    },
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        claims_timer_started => [{timer, expired}]
    },
    run_simulation(UpdatedMarking, UsrInfo, [
        claims_deadline_reached,
        complete_workflow
    ]).

%% @doc Simulate claim filed before deadline
-spec simulate_claim_filed_before_deadline() -> {ok, map()}.
simulate_claim_filed_before_deadline() ->
    DeliveryData = #{
        delivery_id => <<"delivery_006">>,
        order_id => <<"order_006">>,
        customer_id => <<"customer_303">>,
        delivery_date => erlang:system_time(millisecond) - 86400000 % 1 day ago
    },
    ClaimData = #{
        claim_id => <<"claim_003">>,
        delivery_id => <<"delivery_006">>,
        claim_type => damage,
        description => <<"Item damaged during transit">>,
        amount => 2500,
        evidence => [<<"damage_photo.jpg">>],
        filed_date => erlang:system_time(millisecond),
        approved => true
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        claim_data => ClaimData,
        timer_expired => false
    },
    InitialMarking = get_initial_marking(),
    run_simulation(InitialMarking, UsrInfo, [
        start_claims_timer,
        lodge_loss_damage_claim,
        authorize_claim,
        complete_workflow
    ]).

%% @doc Simulate attempt to file claim after deadline (rejected)
-spec simulate_claim_after_deadline() -> {ok, map()}.
simulate_claim_after_deadline() ->
    DeliveryData = #{
        delivery_id => <<"delivery_007">>,
        order_id => <<"order_007">>,
        customer_id => <<"customer_404">>,
        delivery_date => erlang:system_time(millisecond) - ?DEFAULT_CLAIMS_DEADLINE_MS - 100000
    },
    ClaimData = #{
        claim_id => <<"claim_004">>,
        delivery_id => <<"delivery_007">>,
        claim_type => loss,
        description => <<"Item missing - late claim">>,
        amount => 10000,
        evidence => [],
        filed_date => erlang:system_time(millisecond),
        approved => false
    },
    UsrInfo = #{
        delivery_data => DeliveryData,
        claim_data => ClaimData,
        timer_expired => true
    },
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        deadline_expired => [expired_token]
    },
    run_simulation(UpdatedMarking, UsrInfo, [
        claims_deadline_reached
    ]).

%% @doc Fire a sequence of transitions for simulation
-spec fire_transition_sequence(map(), [atom()]) -> {ok, map()}.
fire_transition_sequence(InitialMarking, Transitions) ->
    fire_transition_sequence_with_usr(InitialMarking, Transitions, #{}).

%% @private
-spec fire_transition_sequence_with_usr(map(), [atom()], map()) -> {ok, map()}.
fire_transition_sequence_with_usr(InitialMarking, Transitions, UsrInfo) ->
    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        Preset = preset(Transition),
        Mode = build_mode(Preset, CurrentMarking),
        case is_enabled(Transition, Mode, UsrInfo) of
            true ->
                case fire(Transition, Mode, UsrInfo) of
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
-spec run_simulation(map(), map(), [atom()]) -> {ok, map()}.
run_simulation(InitialMarking, UsrInfo, Transitions) ->
    fire_transition_sequence_with_usr(InitialMarking, Transitions, UsrInfo).

%% @private
-spec has_token(atom(), map()) -> boolean().
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        _ -> true
    end.

%% @private
-spec timer_expired(map()) -> boolean().
timer_expired(Mode) ->
    case maps:get(claims_timer_started, Mode, []) of
        [{timer, expired}] -> true;
        _ -> false
    end.

%% @private
-spec deadline_expired(map()) -> boolean().
deadline_expired(Mode) ->
    has_token(deadline_expired, Mode).

%% @private
-spec claim_or_return_pending(map()) -> boolean().
claim_or_return_pending(Mode) ->
    has_token(claim_pending, Mode) orelse has_token(return_pending, Mode).

%% @private
-spec claim_meets_criteria(map()) -> boolean().
claim_meets_criteria(Mode) ->
    case maps:get(claim_pending, Mode, []) of
        [{claim, ClaimData}] ->
            Amount = maps:get(amount, ClaimData, 0),
            Evidence = maps:get(evidence, ClaimData, []),
            Approved = maps:get(approved, ClaimData, true),
            Amount =< ?MAX_CLAIM_AMOUNT andalso
            length(Evidence) > 0 andalso
            Approved;
        _ ->
            false
    end.

%% @private
-spec return_meets_criteria(map()) -> boolean().
return_meets_criteria(Mode) ->
    case maps:get(return_pending, Mode, []) of
        [{return, ReturnData}] ->
            Items = maps:get(items, ReturnData, []),
            Approved = maps:get(approved, ReturnData, true),
            length(Items) > 0 andalso Approved;
        _ ->
            false
    end.

%% @private
-spec workflow_complete(map()) -> boolean().
workflow_complete(_Mode) ->
    true.

%% @private
-spec get_delivery_data(term()) -> map().
get_delivery_data([]) -> #{};
get_delivery_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(delivery_data, UsrInfo, #{});
get_delivery_data(_) -> #{}.

%% @private
-spec get_claim_data(term()) -> map().
get_claim_data([]) -> #{};
get_claim_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(claim_data, UsrInfo, #{});
get_claim_data(_) -> #{}.

%% @private
-spec get_return_data(term()) -> map().
get_return_data([]) -> #{};
get_return_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(return_data, UsrInfo, #{});
get_return_data(_) -> #{}.

%% @private
-spec create_timer_token(map()) -> {timer, term()}.
create_timer_token(DeliveryData) ->
    DeliveryDate = maps:get(delivery_date, DeliveryData, erlang:system_time(millisecond)),
    Deadline = DeliveryDate + ?DEFAULT_CLAIMS_DEADLINE_MS,
    {timer, Deadline}.

%% @private
-spec create_claim_token(map()) -> {claim, map()}.
create_claim_token(ClaimData) ->
    {claim, ClaimData}.

%% @private
-spec create_return_token(map()) -> {return, map()}.
create_return_token(ReturnData) ->
    {return, ReturnData}.

%% @private
-spec create_claim_approval(map()) -> map().
create_claim_approval(ClaimData) ->
    ClaimId = maps:get(claim_id, ClaimData, <<"unknown">>),
    #{
        claim_id => ClaimId,
        approved => true,
        approved_by => <<"system">>,
        approved_date => erlang:system_time(millisecond),
        notes => <<"Claim approved automatically">>
    }.

%% @private
-spec create_claim_rejection(map()) -> map().
create_claim_rejection(ClaimData) ->
    ClaimId = maps:get(claim_id, ClaimData, <<"unknown">>),
    Reason = maps:get(rejection_reason, ClaimData, <<"Claim does not meet criteria">>),
    #{
        claim_id => ClaimId,
        approved => false,
        rejected_by => <<"system">>,
        rejected_date => erlang:system_time(millisecond),
        notes => Reason
    }.

%% @private
-spec create_return_approval(map()) -> map().
create_return_approval(ReturnData) ->
    ReturnId = maps:get(return_id, ReturnData, <<"unknown">>),
    RMA = generate_rma_number(),
    #{
        return_id => ReturnId,
        approved => true,
        approved_by => <<"system">>,
        approved_date => erlang:system_time(millisecond),
        rma_number => RMA,
        notes => <<"Return approved">>
    }.

%% @private
-spec create_return_rejection(map()) -> map().
create_return_rejection(ReturnData) ->
    ReturnId = maps:get(return_id, ReturnData, <<"unknown">>),
    Reason = maps:get(rejection_reason, ReturnData, <<"Return does not meet criteria">>),
    #{
        return_id => ReturnId,
        approved => false,
        rejected_by => <<"system">>,
        rejected_date => erlang:system_time(millisecond),
        rma_number => undefined,
        notes => Reason
    }.

%% @private
-spec create_completion_result(map(), term()) -> map().
create_completion_result(Mode, _UsrInfo) ->
    Result = case {maps:get(claim_authorized, Mode, []), maps:get(return_authorized, Mode, []), maps:get(no_claim_filed, Mode, [])} of
        {[_], [], []} -> #{status => claim_approved, type => loss_damage};
        {[], [_], []} -> #{status => return_approved, type => merchandise_return};
        {[], [], [_]} -> #{status => no_claim, type => deadline_expired};
        _ -> #{status => completed, type => unknown}
    end,
    Result#{
        completed_at => erlang:system_time(millisecond),
        workflow_id => ?WORKFLOW_ID
    }.

%% @private
-spec generate_rma_number() -> binary().
generate_rma_number() ->
    Timestamp = erlang:system_time(millisecond),
    Random = rand:uniform(10000),
    RmaBin = io_lib:format("RMA-~b-~4.10.0B", [Timestamp, Random]),
    list_to_binary(RmaBin).

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
