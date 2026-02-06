%%%-------------------------------------------------------------------
%%% @doc
%%% Freight in Transit Workflow - YAWL Pattern Example
%%%
%%% This module implements a freight in transit workflow based on the
%%% YAWL reference specification from the order fulfillment example.
%%%
%%% Workflow Description:
%%% 1. Acceptance Certificate - Generate certificate for shipment
%%% 2. Shipment Status Inquiry - Initiate tracking inquiry
%%% 3. Trackpoint Loop - Process multiple trackpoints (multi-instance)
%%% 4. Trackpoint Order Entry - Log each trackpoint
%%% 5. Complete Transit - Finalize shipment tracking
%%%
%%% Patterns Used:
%%% - Sequence: Acceptance → Inquiry → Trackpoints → Complete
%%% - Multi-Instance: Multiple trackpoints processed in parallel
%%% - Iterative Loop: Trackpoint loopback until all processed
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(freight_in_transit_workflow).
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
    simulate_single_trackpoint/0,
    simulate_three_trackpoints/0,
    simulate_five_trackpoints/0,
    simulate_ten_trackpoints/0,
    simulate_with_delay/1,
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

-define(WORKFLOW_ID, <<"freight_in_transit">>).
-define(DEFAULT_TRACKPOINTS, 3).
-define(MAX_TRACKPOINTS, 20).

%%====================================================================
%%% Types
%%====================================================================

-type acceptance_certificate() :: #{
    certificate_id => binary(),
    shipment_id => binary(),
    issued_by => binary(),
    issued_at => integer(),
    valid_until => integer(),
    items => [binary()]
}.

-type shipment_status_inquiry() :: #{
    inquiry_id => binary(),
    shipment_id => binary(),
    status => pending | in_transit | delivered,
    timestamp => integer()
}.

-type trackpoint_notice() :: #{
    trackpoint_id => binary(),
    shipment_id => binary(),
    location => binary(),
    timestamp => integer(),
    status => binary(),
    notes => binary()
}.

-type trackpoint_order_entry() :: #{
    entry_id => binary(),
    trackpoint_id => binary(),
    shipment_id => binary(),
    logged_at => integer()
}.

-type transit_data() :: #{
    shipment_id => binary(),
    origin => binary(),
    destination => binary(),
    carrier => binary(),
    estimated_departure => integer(),
    estimated_arrival => integer(),
    trackpoint_count => integer()
}.

%%====================================================================
%%% gen_pnet Behaviour Callbacks
%%====================================================================

place_lst() ->
    [
        start,
        transit_started,
        acceptance_ready,
        certificate_created,
        status_inquiry,
        trackpoint_loop,
        trackpoint_notices,
        trackpoint_entries,
        trackpoints_complete,
        'end'
    ].

trsn_lst() ->
    [
        initiate_transit,
        create_acceptance_certificate,
        initiate_status_inquiry,
        issue_trackpoint_notices,
        log_trackpoint_entry,
        check_more_trackpoints,
        complete_transit
    ].

init_marking(start, _UsrInfo) ->
    [workflow_token];
init_marking(_Place, _UsrInfo) ->
    [].

preset(Transition) ->
    case Transition of
        initiate_transit -> [start];
        create_acceptance_certificate -> [transit_started, acceptance_ready];
        initiate_status_inquiry -> [certificate_created];
        issue_trackpoint_notices -> [status_inquiry, trackpoint_loop];
        log_trackpoint_entry -> [trackpoint_notices];
        check_more_trackpoints -> [trackpoint_entries];
        complete_transit -> [trackpoints_complete]
    end.

postset(Transition) ->
    case Transition of
        initiate_transit -> [transit_started, acceptance_ready];
        create_acceptance_certificate -> [certificate_created];
        initiate_status_inquiry -> [status_inquiry];
        issue_trackpoint_notices -> [trackpoint_notices];
        log_trackpoint_entry -> [trackpoint_entries];
        check_more_trackpoints -> [trackpoint_loop, trackpoints_complete];
        complete_transit -> ['end']
    end.

is_enabled(Transition, Mode, _UsrInfo) ->
    case Transition of
        initiate_transit ->
            has_token(start, Mode);
        create_acceptance_certificate ->
            has_token(transit_started, Mode) andalso
            has_token(acceptance_ready, Mode);
        initiate_status_inquiry ->
            has_token(certificate_created, Mode);
        issue_trackpoint_notices ->
            has_token(status_inquiry, Mode) orelse
            has_token(trackpoint_loop, Mode);
        log_trackpoint_entry ->
            has_tokens(trackpoint_notices, Mode);
        check_more_trackpoints ->
            has_tokens(trackpoint_entries, Mode);
        complete_transit ->
            has_token(trackpoints_complete, Mode)
    end.

fire(Transition, Mode, UsrInfo) ->
    TransitData = get_transit_data(UsrInfo),

    % Log XES transition event if enabled
    ?XES_LOG_TRANSITION(?WORKFLOW_ID, Transition, start),

    case Transition of
        initiate_transit ->
            ShipmentId = maps:get(shipment_id, TransitData, generate_id(<<"shipment">>)),
            {produce, #{
                transit_started => [{transit, TransitData#{shipment_id => ShipmentId}}],
                acceptance_ready => [acceptance_pending]
            }};
        create_acceptance_certificate ->
            Certificate = create_certificate(TransitData),
            {produce, #{
                certificate_created => [{certificate, Certificate}]
            }};
        initiate_status_inquiry ->
            Inquiry = create_status_inquiry(TransitData),
            {produce, #{
                status_inquiry => [{inquiry, Inquiry}]
            }};
        issue_trackpoint_notices ->
            TrackpointCount = get_trackpoint_count(Mode, TransitData),
            Notices = create_trackpoint_notices(TrackpointCount, TransitData),
            {produce, #{
                trackpoint_notices => Notices,
                status_inquiry => [],
                trackpoint_loop => [continue_loop]
            }};
        log_trackpoint_entry ->
            Entries = create_trackpoint_entries(Mode, TransitData),
            {produce, #{
                trackpoint_entries => Entries,
                trackpoint_notices => []
            }};
        check_more_trackpoints ->
            TrackpointEntries = maps:get(trackpoint_entries, Mode, []),
            TransitData2 = get_transit_data_from_entries(TrackpointEntries, TransitData),
            ProcessedCount = length(TrackpointEntries),
            TotalCount = maps:get(trackpoint_count, TransitData2, ?DEFAULT_TRACKPOINTS),
            case ProcessedCount >= TotalCount of
                true ->
                    {produce, #{
                        trackpoints_complete => [all_complete],
                        trackpoint_entries => []
                    }};
                false ->
                    {produce, #{
                        trackpoint_loop => [continue],
                        trackpoint_entries => []
                    }}
            end;
        complete_transit ->
            ?XES_LOG_TRANSITION(?WORKFLOW_ID, complete_transit, complete),
            FinalStatus = create_final_status(TransitData),
            {produce, #{
                'end' => [FinalStatus]
            }}
    end.

trigger(Place, Token, _UsrInfo) ->
    case Place of
        start ->
            case Token of
                workflow_token -> pass;
                _ -> pass
            end;
        trackpoint_loop ->
            case Token of
                continue -> pass;
                continue_loop -> pass;
                _ -> pass
            end;
        trackpoints_complete ->
            case Token of
                all_complete -> pass;
                _ -> pass
            end;
        _ ->
            pass
    end.

%%====================================================================
%%% API Functions
%%====================================================================

%% @doc Create a new freight in transit workflow
-spec create_workflow(map()) -> {ok, map()} | {error, term()}.
create_workflow(TransitData) ->
    WorkflowId = maps:get(shipment_id, TransitData, ?WORKFLOW_ID),
    Spec = get_workflow_spec(),
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => composite,
        transit_data => TransitData,
        trackpoint_count => maps:get(trackpoint_count, TransitData, ?DEFAULT_TRACKPOINTS),
        max_trackpoints => maps:get(max_trackpoints, TransitData, ?MAX_TRACKPOINTS)
    },
    {ok, Spec#{config => Config}}.

%% @doc Get the workflow specification
-spec get_workflow_spec() -> map().
get_workflow_spec() ->
    #{
        workflow_id => ?WORKFLOW_ID,
        workflow_name => <<"Freight in Transit Workflow">>,
        version => <<"1.0.0">>,
        description => <<"Track freight through acceptance certificate and multiple trackpoints">>,
        places => place_lst(),
        transitions => trsn_lst(),
        initial_marking => #{start => [workflow_token]},
        patterns_used => [
            basic_sequential,
            multi_instance,
            iterative_loop
        ]
    }.

%% @doc Get initial marking for simulation
-spec get_initial_marking() -> map().
get_initial_marking() ->
    lists:foldl(fun(P, Acc) ->
        Acc#{P => init_marking(P, [])}
    end, #{}, place_lst()).

%% @doc Simulate single trackpoint workflow
-spec simulate_single_trackpoint() -> {ok, map()}.
simulate_single_trackpoint() ->
    % Initialize XES logging for this workflow instance
    CaseId = generate_id(<<"case">>),
    ?XES_LOG_WORKFLOW_START(?WORKFLOW_ID, CaseId),

    TransitData = create_transit_data(1),

    try
        Result = run_simulation(TransitData),
        ?XES_LOG_WORKFLOW_COMPLETE(?WORKFLOW_ID, CaseId),
        Result
    catch
        _:_ ->
            ?XES_LOG_WORKFLOW_FAIL(?WORKFLOW_ID, CaseId),
            {ok, #{}}
    end.

%% @doc Simulate three trackpoint workflow
-spec simulate_three_trackpoints() -> {ok, map()}.
simulate_three_trackpoints() ->
    TransitData = create_transit_data(3),
    run_simulation(TransitData).

%% @doc Simulate five trackpoint workflow
-spec simulate_five_trackpoints() -> {ok, map()}.
simulate_five_trackpoints() ->
    TransitData = create_transit_data(5),
    run_simulation(TransitData).

%% @doc Simulate ten trackpoint workflow
-spec simulate_ten_trackpoints() -> {ok, map()}.
simulate_ten_trackpoints() ->
    TransitData = create_transit_data(10),
    run_simulation(TransitData).

%% @doc Simulate workflow with custom delay between trackpoints
-spec simulate_with_delay(integer()) -> {ok, map()}.
simulate_with_delay(DelayMinutes) ->
    TransitData = create_transit_data(3, DelayMinutes),
    run_simulation(TransitData).

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
-spec create_transit_data(integer()) -> transit_data().
create_transit_data(TrackpointCount) ->
    create_transit_data(TrackpointCount, 60).

%% @private
-spec create_transit_data(integer(), integer()) -> transit_data().
create_transit_data(TrackpointCount, DelayMinutes) ->
    Now = erlang:system_time(millisecond),
    #{
        shipment_id => generate_id(<<"shipment">>),
        origin => <<"Los Angeles, CA">>,
        destination => <<"New York, NY">>,
        carrier => <<"FedEx Freight">>,
        estimated_departure => Now,
        estimated_arrival => Now + (5 * 86400000), % 5 days
        trackpoint_count => TrackpointCount,
        delay_minutes => DelayMinutes
    }.

%% @private
-spec run_simulation(transit_data()) -> {ok, map()}.
run_simulation(TransitData) ->
    TrackpointCount = maps:get(trackpoint_count, TransitData, ?DEFAULT_TRACKPOINTS),
    InitialMarking = get_initial_marking(),
    UpdatedMarking = InitialMarking#{
        transit_started => [{transit, TransitData}],
        acceptance_ready => [acceptance_pending]
    },
    % Build transition sequence for the workflow
    BaseSequence = [
        initiate_transit,
        create_acceptance_certificate,
        initiate_status_inquiry
    ],
    % Add trackpoint iterations
    TrackpointSequence = build_trackpoint_sequence(TrackpointCount),
    FullSequence = BaseSequence ++ TrackpointSequence ++ [complete_transit],
    fire_transition_sequence(UpdatedMarking, FullSequence).

%% @private
-spec build_trackpoint_sequence(integer()) -> [atom()].
build_trackpoint_sequence(Count) when Count > 0 ->
    lists:flatmap(fun(_) ->
        [issue_trackpoint_notices, log_trackpoint_entry, check_more_trackpoints]
    end, lists:seq(1, Count));
build_trackpoint_sequence(_) ->
    [].

%% @private
-spec create_certificate(transit_data()) -> acceptance_certificate().
create_certificate(TransitData) ->
    ShipmentId = maps:get(shipment_id, TransitData, generate_id(<<"shipment">>)),
    Now = erlang:system_time(millisecond),
    #{
        certificate_id => generate_id(<<"cert">>),
        shipment_id => ShipmentId,
        issued_by => <<"Master's in SCLM">>,
        issued_at => Now,
        valid_until => Now + (30 * 86400000), % 30 days
        items => [
            <<"Electronics">>,
            <<"Auto Parts">>,
            <<"Industrial Equipment">>
        ]
    }.

%% @private
-spec create_status_inquiry(transit_data()) -> shipment_status_inquiry().
create_status_inquiry(TransitData) ->
    ShipmentId = maps:get(shipment_id, TransitData, generate_id(<<"shipment">>)),
    #{
        inquiry_id => generate_id(<<"inquiry">>),
        shipment_id => ShipmentId,
        status => in_transit,
        timestamp => erlang:system_time(millisecond)
    }.

%% @private
-spec create_trackpoint_notices(integer(), transit_data()) -> [{trackpoint, trackpoint_notice()}].
create_trackpoint_notices(Count, TransitData) ->
    ShipmentId = maps:get(shipment_id, TransitData, generate_id(<<"shipment">>)),
    Now = erlang:system_time(millisecond),
    Delay = maps:get(delay_minutes, TransitData, 60) * 60000,
    Locations = [
        {<<"Phoenix, AZ">>, <<"Departed facility">>},
        {<<"Albuquerque, NM">>, <<"In transit">>},
        {<<"Amarillo, TX">>, <<"In transit">>},
        {<<"Oklahoma City, OK">>, <<"Arrived at hub">>},
        {<<"Kansas City, MO">>, <<"Departed hub">>},
        {<<"Des Moines, IA">>, <<"In transit">>},
        {<<"Chicago, IL">>, <<"At distribution center">>},
        {<<"Cleveland, OH">>, <<"In transit">>},
        {<<"Pittsburgh, PA">>, <<"In transit">>},
        {<<"New York, NY">>, <<"Out for delivery">>}
    ],
    lists:map(fun(I) ->
        {Location, Status} = lists:nth((I rem length(Locations)) + 1, Locations),
        #{
            trackpoint_id => generate_id(<<"trackpoint">>),
            shipment_id => ShipmentId,
            location => Location,
            timestamp => Now + (I * Delay),
            status => Status,
            notes => <<"Trackpoint ", (integer_to_binary(I))/binary>>
        }
    end, lists:seq(1, Count)).

%% @private
-spec create_trackpoint_entries(map(), transit_data()) -> [{entry, trackpoint_order_entry()}].
create_trackpoint_entries(Mode, _TransitData) ->
    Notices = maps:get(trackpoint_notices, Mode, []),
    Now = erlang:system_time(millisecond),
    lists:map(fun({trackpoint, Notice}) ->
        TrackpointId = maps:get(trackpoint_id, Notice, <<>>),
        ShipmentId = maps:get(shipment_id, Notice, <<>>),
        #{
            entry_id => generate_id(<<"entry">>),
            trackpoint_id => TrackpointId,
            shipment_id => ShipmentId,
            logged_at => Now
        }
    end, Notices).

%% @private
-spec get_trackpoint_count(map(), transit_data()) -> integer().
get_trackpoint_count(Mode, TransitData) ->
    case maps:get(trackpoint_count, TransitData, undefined) of
        undefined -> ?DEFAULT_TRACKPOINTS;
        Count when is_integer(Count) -> Count;
        _ -> ?DEFAULT_TRACKPOINTS
    end.

%% @private
-spec get_transit_data(term()) -> transit_data().
get_transit_data([]) -> #{};
get_transit_data(UsrInfo) when is_map(UsrInfo) ->
    maps:get(transit_data, UsrInfo, #{});
get_transit_data(_) -> #{}.

%% @private
-spec get_transit_data_from_entries([term()], transit_data()) -> transit_data().
get_transit_data_from_entries([], TransitData) ->
    TransitData;
get_transit_data_from_entries(_Entries, TransitData) ->
    TransitData.

%% @private
-spec create_final_status(transit_data()) -> map().
create_final_status(TransitData) ->
    ShipmentId = maps:get(shipment_id, TransitData, <<>>),
    Now = erlang:system_time(millisecond),
    #{
        status => completed,
        shipment_id => ShipmentId,
        completed_at => Now,
        message => <<"Freight transit completed successfully">>
    }.

%% @private
-spec has_token(atom(), map()) -> boolean().
has_token(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        [_|_] -> true
    end.

%% @private
-spec has_tokens(atom(), map()) -> boolean().
has_tokens(Place, Mode) ->
    case maps:get(Place, Mode, []) of
        [] -> false;
        Tokens when length(Tokens) > 0 -> true
    end.

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
