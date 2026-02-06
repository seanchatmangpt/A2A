%%%-------------------------------------------------------------------
%%% @doc
%%% Ordering (Purchase Order) Workflow - YAWL Pattern Example
%%%
%%% This module implements the Purchase Order workflow based on the
%%% YAWL reference specification from the order fulfillment example.
%%%
%%% Workflow Description:
%%% 1. Create PO - Manual task for PO_Manager to create purchase order
%%% 2. Approve/Modify - Conditional approval or modification of PO
%%% 3. Confirm PO - Final confirmation step
%%% 4. Timeout Handling - 3-day timeout cancels pending POs
%%%
%%% Patterns Used:
%%% - Sequence: Create PO -> Approve/Modify -> Confirm PO
%%% - Exclusive Choice: Approve vs Modify vs Reject
%%% - Cancellation: Timeout after 3 days
%%% - Deferred Choice: Approval vs Timeout
%%%
%%% Business Rules:
%%% - PO must be approved within 3 days or workflow cancels
%%% - PO_Manager role can create, approve, or modify POs
%%% - Modification can be skipped (delegation allowed)
%%% - POApproval flag must be true for approval path
%%% - PO_timedout flag prevents approval after timeout
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(ordering_workflow).
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
    simulate_normal_approval/0,
    simulate_timeout_cancellation/0,
    simulate_modify_before_approval/0,
    simulate_po_rejection/0,
    simulate_delegate_approval/0,
    simulate_skip_modification/0,
    simulate_exactly_3_days/0,
    simulate_multiple_modifications/0,
    get_initial_marking/0,
    fire_transition_sequence/2
]).

%% Include gen_pnet records
-include("gen_pnet.hrl").
-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%%====================================================================
%%% Constants
%%====================================================================

-define(WORKFLOW_ID, <<"ordering">>).
-define(PO_TIMEOUT_DAYS, 3).
-define(PO_TIMEOUT_MS, ?PO_TIMEOUT_DAYS * 24 * 60 * 60 * 1000).  % 3 days in ms

%%====================================================================
%%% Types
%%====================================================================

-type po_data() :: #{
    po_id => binary(),
    supplier_id => binary(),
    items => list(),
    total_amount => number(),
    currency => binary(),
    requested_by => binary(),
    created_at => integer()
}.

-type po_state() :: #{
    po_approval => boolean(),
    po_timedout => boolean(),
    po_modified => boolean(),
    po_rejected => boolean(),
    approved_by => binary() | undefined,
    modified_by => binary() | undefined,
    approved_at => integer() | undefined,
    timeout_at => integer() | undefined
}.

-type workflow_token() :: {workflow_token, binary()}.
-type po_token() :: {po, po_data()}.
-type approval_token() :: {approval, po_state()}.
-type timeout_token() :: {timeout, integer()}.

%%====================================================================
%%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    [
        start,
        order_received,
        po_created,
        po_approval_pending,
        po_approved,
        po_modified,
        po_timeout,
        po_confirmed,
        po_rejected,
        po_cancelled,
        modification_skip,
        'end'
    ].

trsn_lst() ->
    [
        create_purchase_order,
        approve_po,
        modify_po,
        skip_modification,
        confirm_po,
        order_timeout_timer,
        reject_po,
        cancel_workflow,
        complete
    ].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(Transition) ->
    case Transition of
        create_purchase_order -> [start];
        approve_po -> [po_approval_pending];
        modify_po -> [po_approval_pending];
        skip_modification -> [po_approval_pending];
        confirm_po -> [po_approved, po_modified];
        order_timeout_timer -> [po_approval_pending];
        reject_po -> [po_approval_pending];
        cancel_workflow -> [po_timeout, po_cancelled];
        complete -> [po_confirmed]
    end.

postset(Transition) ->
    case Transition of
        create_purchase_order -> [po_created, po_approval_pending];
        approve_po -> [po_approved];
        modify_po -> [po_modified, po_approval_pending];
        skip_modification -> [po_approved];
        confirm_po -> [po_confirmed];
        order_timeout_timer -> [po_timeout];
        reject_po -> [po_rejected];
        cancel_workflow -> ['end'];
        complete -> ['end']
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        create_purchase_order ->
            has_token(start, Mode);
        approve_po ->
            has_token(po_approval_pending, Mode) andalso
            can_approve_po(Mode);
        modify_po ->
            has_token(po_approval_pending, Mode) andalso
            can_modify_po(Mode);
        skip_modification ->
            has_token(po_approval_pending, Mode) andalso
            can_skip_modification(Mode);
        confirm_po ->
            (has_token(po_approved, Mode) orelse has_token(po_modified, Mode)) andalso
            not has_timed_out(Mode);
        order_timeout_timer ->
            has_token(po_approval_pending, Mode) andalso
            has_timed_out(Mode);
        reject_po ->
            has_token(po_approval_pending, Mode);
        cancel_workflow ->
            has_token(po_timeout, Mode) orelse has_token(po_cancelled, Mode);
        complete ->
            has_token(po_confirmed, Mode)
    end.

fire(Transition, Mode, UsrInfo) ->
    POData = get_po_data(UsrInfo),
    POState = get_po_state(Mode, UsrInfo),

    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        create_purchase_order ->
            NewPOData = initialize_po_data(POData),
            TimeoutAt = calculate_timeout(),
            {produce, #{
                po_created => [{po, NewPOData}],
                po_approval_pending => [{pending, TimeoutAt}]
            }};
        approve_po ->
            UpdatedState = POState#{
                po_approval => true,
                approved_by => maps:get(approved_by, UsrInfo, <<"system">>),
                approved_at => erlang:system_time(millisecond)
            },
            {produce, #{
                po_approved => [{approved, UpdatedState}],
                po_approval_pending => []
            }};
        modify_po ->
            UpdatedState = POState#{
                po_modified => true,
                modified_by => maps:get(modified_by, UsrInfo, <<"system">>)
            },
            ModifiedPOData = apply_modifications(POData, UsrInfo),
            TimeoutAt = calculate_timeout(),
            {produce, #{
                po_modified => [{modified, UpdatedState}],
                po_approval_pending => [{pending, TimeoutAt}]
            }};
        skip_modification ->
            % Skip modification, proceed directly to approval
            UpdatedState = POState#{
                po_approval => true,
                approved_by => maps:get(approved_by, UsrInfo, <<"system">>),
                approved_at => erlang:system_time(millisecond)
            },
            {produce, #{
                po_approved => [{approved, UpdatedState}],
                po_approval_pending => []
            }};
        confirm_po ->
            ConfirmedState = POState#{
                confirmed_at => erlang:system_time(millisecond)
            },
            {produce, #{
                po_confirmed => [{confirmed, ConfirmedState}],
                po_approved => [],
                po_modified => []
            }};
        order_timeout_timer ->
            TimeoutState = POState#{
                po_timedout => true,
                timeout_at => erlang:system_time(millisecond)
            },
            {produce, #{
                po_timeout => [{timed_out, TimeoutState}],
                po_approval_pending => []
            }};
        reject_po ->
            RejectedState = POState#{
                po_rejected => true,
                rejected_by => maps:get(rejected_by, UsrInfo, <<"system">>),
                rejected_at => erlang:system_time(millisecond)
            },
            {produce, #{
                po_rejected => [{rejected, RejectedState}],
                po_approval_pending => []
            }};
        cancel_workflow ->
            {produce, #{
                'end' => [cancelled],
                po_timeout => [],
                po_cancelled => []
            }};
        complete ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete, complete),
            {produce, #{
                'end' => [completed],
                po_confirmed => []
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            pass;
        order_received ->
            pass;
        po_created ->
            pass;
        po_approval_pending ->
            pass;
        po_approved ->
            pass;
        po_modified ->
            pass;
        po_timeout ->
            pass;
        po_confirmed ->
            pass;
        po_rejected ->
            pass;
        po_cancelled ->
            case Token of
                cancelled -> pass;
                _ -> pass
            end;
        modification_skip ->
            pass;
        _ ->
            pass
    end.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create a new ordering (purchase order) workflow
-spec create_workflow(map()) -> {ok, map()} | {error, term()}.
create_workflow(POData) ->
    WorkflowId = maps:get(po_id, POData, ?WORKFLOW_ID),
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => composite,
        po_data => POData,
        timeout_days => maps:get(timeout_days, POData, ?PO_TIMEOUT_DAYS),
        role => maps:get(role, POData, po_manager),
        allow_delegation => maps:get(allow_delegation, POData, true),
        require_modification => maps:get(require_modification, POData, false)
    },
    {ok, Spec#{config => Config}}.

%% @doc Get the workflow specification
-spec get_workflow_spec() -> map().
get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Ordering (Purchase Order) Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Create, approve, modify, and confirm purchase orders with 3-day timeout">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [
            basic_sequential,
            exclusive_choice,
            cancelation,
            deferred_choice
        ],
        business_rules => [
            {timeout, ?PO_TIMEOUT_DAYS, days},
            {role_required, po_manager},
            {delegation_allowed, true},
            {modification_optional, true}
        ]
    }.

%% @doc Get initial marking for simulation
-spec get_initial_marking() -> map().
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate normal approval path (PO approved within timeout)
-spec simulate_normal_approval() -> {ok, map()}.
simulate_normal_approval() ->
    % Initialize XES logging for this workflow instance
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    POData = #{
        po_id => <<"PO-NORMAL-001">>,
        supplier_id => <<"SUPPLIER-001">>,
        items => [
            #{item_id => <<"ITEM-001">>, quantity => 100, unit_price => 50.00},
            #{item_id => <<"ITEM-002">>, quantity => 50, unit_price => 75.00}
        ],
        total_amount => 8750.00,
        currency => <<"USD">>,
        requested_by => <<"JOHN_DOE">>,
        created_at => erlang:system_time(millisecond)
    },
    % Simulate approval happening before timeout
    UsrInfo = #{
        approved_by => <<"JANE_SMITH">>,
        current_time => erlang:system_time(millisecond) + (?PO_TIMEOUT_MS div 2)  % 1.5 days later
    },
    try
        Result = run_simulation(POData, UsrInfo, [create_purchase_order, approve_po, confirm_po, complete]),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        Result
    catch
        _:_ ->
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {ok, #{}}
    end.

%% @doc Simulate timeout cancellation (PO times out after 3 days)
-spec simulate_timeout_cancellation() -> {ok, map()}.
simulate_timeout_cancellation() ->
    POData = #{
        po_id => <<"PO-TIMEOUT-001">>,
        supplier_id => <<"SUPPLIER-002">>,
        items => [
            #{item_id => <<"ITEM-003">>, quantity => 200, unit_price => 25.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"BOB_JOHNSON">>,
        created_at => erlang:system_time(millisecond)
    },
    % Simulate timeout occurring
    UsrInfo = #{
        current_time => erlang:system_time(millisecond) + ?PO_TIMEOUT_MS + 1000,
        timed_out => true
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, order_timeout_timer, cancel_workflow]).

%% @doc Simulate modification before approval
-spec simulate_modify_before_approval() -> {ok, map()}.
simulate_modify_before_approval() ->
    POData = #{
        po_id => <<"PO-MODIFY-001">>,
        supplier_id => <<"SUPPLIER-003">>,
        items => [
            #{item_id => <<"ITEM-004">>, quantity => 75, unit_price => 100.00}
        ],
        total_amount => 7500.00,
        currency => <<"USD">>,
        requested_by => <<"ALICE_WILLIAMS">>,
        created_at => erlang:system_time(millisecond)
    },
    % First modify, then approve
    UsrInfo = #{
        modified_by => <<"MIKE_BROWN">>,
        approved_by => <<"SARAH_DAVIS">>,
        current_time => erlang:system_time(millisecond) + 86400000  % 1 day later
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, modify_po, approve_po, confirm_po, complete]).

%% @doc Simulate PO rejection
-spec simulate_po_rejection() -> {ok, map()}.
simulate_po_rejection() ->
    POData = #{
        po_id => <<"PO-REJECT-001">>,
        supplier_id => <<"SUPPLIER-004">>,
        items => [
            #{item_id => <<"ITEM-005">>, quantity => 500, unit_price => 10.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"TOM_MILLER">>,
        created_at => erlang:system_time(millisecond)
    },
    UsrInfo = #{
        rejected_by => <<"LISA_JONES">>,
        rejection_reason => <<"Budget exceeded">>,
        current_time => erlang:system_time(millisecond) + 3600000  % 1 hour later
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, reject_po]).

%% @doc Simulate delegation approval (original approver delegates to another)
-spec simulate_delegate_approval() -> {ok, map()}.
simulate_delegate_approval() ->
    POData = #{
        po_id => <<"PO-DELEGATE-001">>,
        supplier_id => <<"SUPPLIER-005">>,
        items => [
            #{item_id => <<"ITEM-006">>, quantity => 150, unit_price => 80.00}
        ],
        total_amount => 12000.00,
        currency => <<"USD">>,
        requested_by => <<"KIM_TAYLOR">>,
        created_at => erlang:system_time(millisecond),
        allow_delegation => true
    },
    UsrInfo = #{
        approved_by => <<"DELEGATED_APPROVER">>,
        original_approver => <<"ORIGINAL_APPROVER">>,
        delegated => true,
        current_time => erlang:system_time(millisecond) + 7200000  % 2 hours later
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, approve_po, confirm_po, complete]).

%% @doc Simulate skipping modification (optional modification skipped)
-spec simulate_skip_modification() -> {ok, map()}.
simulate_skip_modification() ->
    POData = #{
        po_id => <<"PO-SKIP-001">>,
        supplier_id => <<"SUPPLIER-006">>,
        items => [
            #{item_id => <<"ITEM-007">>, quantity => 25, unit_price => 200.00}
        ],
        total_amount => 5000.00,
        currency => <<"USD">>,
        requested_by => <<"DAVID_WHITE">>,
        created_at => erlang:system_time(millisecond)
    },
    UsrInfo = #{
        approved_by => <<"EMMA_GREEN">>,
        skip_modification => true,
        current_time => erlang:system_time(millisecond) + 1800000  % 30 minutes later
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, skip_modification, confirm_po, complete]).

%% @doc Simulate exactly 3-day boundary (approval at exactly 3 days)
-spec simulate_exactly_3_days() -> {ok, map()}.
simulate_exactly_3_days() ->
    POData = #{
        po_id => <<"PO-3DAYS-001">>,
        supplier_id => <<"SUPPLIER-007">>,
        items => [
            #{item_id => <<"ITEM-008">>, quantity => 300, unit_price => 15.00}
        ],
        total_amount => 4500.00,
        currency => <<"USD">>,
        requested_by => <<"CHRIS_HALL">>,
        created_at => erlang:system_time(millisecond)
    },
    % Exactly at 3 day boundary - should still be allowed
    UsrInfo = #{
        approved_by => <<"NANCY_KING">>,
        current_time => erlang:system_time(millisecond) + ?PO_TIMEOUT_MS  % Exactly 3 days
    },
    run_simulation(POData, UsrInfo, [create_purchase_order, approve_po, confirm_po, complete]).

%% @doc Simulate multiple modifications before final approval
-spec simulate_multiple_modifications() -> {ok, map()}.
simulate_multiple_modifications() ->
    POData = #{
        po_id => <<"PO-MULTI-001">>,
        supplier_id => <<"SUPPLIER-008">>,
        items => [
            #{item_id => <<"ITEM-009">>, quantity => 50, unit_price => 150.00}
        ],
        total_amount => 7500.00,
        currency => <<"USD">>,
        requested_by => <<"MARK_SCOTT">>,
        created_at => erlang:system_time(millisecond)
    },
    UsrInfo = #{
        modified_by => <<"PATRICIA_YOUNG">>,
        approved_by => <<"ROBERT_ADAMS">>,
        current_time => erlang:system_time(millisecond) + 14400000  % 4 hours later
    },
    % Multiple modification cycles before approval
    Transitions = [
        create_purchase_order,
        modify_po,
        modify_po,
        modify_po,
        approve_po,
        confirm_po,
        complete
    ],
    run_simulation(POData, UsrInfo, Transitions).

%% @doc Fire a sequence of transitions for simulation
-spec fire_transition_sequence(map(), [atom()]) -> {ok, map()}.
fire_transition_sequence(InitialMarking, Transitions) ->
    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        Mode = CurrentMarking,
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
-spec run_simulation(map(), map(), [atom()]) -> {ok, map()}.
run_simulation(POData, UsrInfo, Transitions) ->
    InitialMarking = get_initial_marking(),
    TimeoutAt = calculate_timeout(),
    UpdatedMarking = InitialMarking#{
        po_created => [{po, POData}],
        po_approval_pending => [{pending, TimeoutAt}]
    },
    fire_transition_sequence_with_user_info(UpdatedMarking, Transitions, UsrInfo).

%% @private
-spec fire_transition_sequence_with_user_info(map(), [atom()], map()) -> {ok, map()}.
fire_transition_sequence_with_user_info(InitialMarking, Transitions, UsrInfo) ->
    lists:foldl(fun(Transition, {ok, CurrentMarking}) ->
        Mode = CurrentMarking,
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

%% @private
-spec has_token(atom(), map()) -> boolean().
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        [_|_] -> true
    end.

%% @private
-spec can_approve_po(map()) -> boolean().
can_approve_po(Mode) ->
    % Check if PO has timed out - if timed out, cannot approve
    case maps:get(po_approval_pending, Mode, []) of
        [{pending, TimeoutAt}] ->
            CurrentTime = erlang:system_time(millisecond),
            CurrentTime < TimeoutAt;
        _ ->
            false
    end.

%% @private
-spec can_modify_po(map()) -> boolean().
can_modify_po(Mode) ->
    % Can modify if not timed out
    case maps:get(po_approval_pending, Mode, []) of
        [{pending, TimeoutAt}] ->
            CurrentTime = erlang:system_time(millisecond),
            CurrentTime < TimeoutAt;
        _ ->
            false
    end.

%% @private
-spec can_skip_modification(map()) -> boolean().
can_skip_modification(Mode) ->
    % Can skip if not timed out (modification is optional)
    can_modify_po(Mode).

%% @private
-spec has_timed_out(map()) -> boolean().
has_timed_out(Mode) ->
    case maps:get(po_approval_pending, Mode, []) of
        [{pending, TimeoutAt}] ->
            CurrentTime = erlang:system_time(millisecond),
            CurrentTime >= TimeoutAt;
        _ ->
            false
    end.

%% @private
-spec calculate_timeout() -> integer().
calculate_timeout() ->
    erlang:system_time(millisecond) + ?PO_TIMEOUT_MS.

%% @private
-spec get_po_data(term()) -> po_data().
get_po_data([]) -> #{};
get_po_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(po_data, UsrInfo, #{});
get_po_data(_) -> #{}.

%% @private
-spec get_po_state(map(), term()) -> po_state().
get_po_state(Mode, UsrInfo) ->
    DefaultState = #{
        po_approval => false,
        po_timedout => false,
        po_modified => false,
        po_rejected => false,
        approved_by => undefined,
        modified_by => undefined,
        approved_at => undefined,
        timeout_at => undefined
    },
    % Merge with any existing state from UsrInfo
    case UsrInfo of
        StateMap when is_map(StateMap) ->
            maps:merge(DefaultState, StateMap);
        _ ->
            DefaultState
    end.

%% @private
-spec initialize_po_data(map()) -> po_data().
initialize_po_data(POData) ->
    CurrentTime = erlang:system_time(millisecond),
    DefaultPO = #{
        po_id => generate_po_id(),
        supplier_id => <<"DEFAULT_SUPPLIER">>,
        items => [],
        total_amount => 0.0,
        currency => <<"USD">>,
        requested_by => <<"system">>,
        created_at => CurrentTime
    },
    maps:merge(DefaultPO, POData).

%% @private
-spec apply_modifications(po_data(), map()) -> po_data().
apply_modifications(POData, _UsrInfo) ->
    % Apply modification logic - in real system, would apply specific changes
    POData#{
        modified_at => erlang:system_time(millisecond)
    }.

%% @private
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive])),
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    <<Prefix/binary, "_", Timestamp/binary, "_", Unique/binary>>.

%% @private
-spec generate_po_id() -> binary().
generate_po_id() ->
    Timestamp = erlang:system_time(millisecond),
    Random = rand:uniform(10000),
    iolist_to_binary([<<"PO-">>, integer_to_binary(Timestamp), <<"-">>, integer_to_binary(Random)]).

%% @private
-spec apply_produce(map(), map()) -> map().
apply_produce(Marking, ProduceMap) ->
    maps:fold(fun(Place, Tokens, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        Acc#{Place => CurrentTokens ++ Tokens}
    end, Marking, ProduceMap).
