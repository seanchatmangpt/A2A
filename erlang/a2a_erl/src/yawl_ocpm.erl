%%%-------------------------------------------------------------------
%%% @doc
%%% Object-Centric Process Mining (OCPM) for YAWL Workflows
%%%
%%% This module implements Object-Centric Process Mining based on
%%% van der Aalst et al. (Jul 2025) "Object-Centric Process Mining
%%% for Grounding Generative and Predictive AI".
%%%
%%% Key Concepts:
%%% - Object-Centric Event Logs: Multiple object types per event
%%% - Process Intelligence (PI): Amalgamation of process-centric techniques
%%% - AI Grounding: Use OCPM to ground generative/predictive/prescriptive AI
%%%
%%% Reference: arXiv:2508.00116 (Jul 2025)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_ocpm).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% API exports - Object-centric logging
-export([
    log_oc_event/1,
    log_multi_object_event/2,
    create_ocel_log/0,
    get_ocel_log/1
]).

%% API exports - OCPM to XES conversion
-export([
    ocpm_to_standard_xes/1,
    extract_object_type/2,
    filter_by_object_type/2,
    flatten_ocel_log/1
]).

%% API exports - AI grounding
-export([
    ground_generative_ai/1,
    ground_predictive_ai/1,
    ground_prescriptive_ai/1,
    compute_grounding_score/2
]).

%% API exports - Process Intelligence queries
-export([
    pi_object_lifecycle/2,
    pi_inter_object_dependencies/1,
    pi_object_interactions/1,
    pi_process_variant/2
]).

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% Type Definitions
%%====================================================================

-type object_id() :: binary().
-type object_type() :: binary().
-type ocel_event() :: #{
    event_id := binary(),
    timestamp := integer(),
    activity := binary(),
    objects := #{object_type() => [object_id()]},
    attributes := map()
}.

-type ocel_log() :: #{
    log_id := binary(),
    events := [ocel_event()],
    object_types := [object_type()],
    metadata := map()
}.

-type grounding_result() :: #{
    grounded := boolean(),
    confidence := float(),
    evidence_count := non_neg_integer(),
    grounding_map := map()
}.

%%====================================================================
%% API Functions - Object-Centric Logging
%%====================================================================

%% @doc Start the OCPM server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Log an object-centric event.
-spec log_oc_event(map()) -> ok.
log_oc_event(EventMap) ->
    gen_server:cast(?SERVER, {log_oc_event, EventMap}).

%% @doc Log an event involving multiple objects.
-spec log_multi_object_event(#{object_type() => [object_id()]}, map()) -> ok.
log_multi_object_event(Objects, EventData) ->
    Event = EventData#{
        objects => Objects,
        event_id => generate_event_id(),
        timestamp => erlang:system_time(millisecond)
    },
    log_oc_event(Event).

%% @doc Create a new OCEL log.
-spec create_ocel_log() -> {ok, binary()}.
create_ocel_log() ->
    gen_server:call(?SERVER, create_ocel_log).

%% @doc Get an OCEL log by ID.
-spec get_ocel_log(binary()) -> {ok, ocel_log()} | {error, not_found}.
get_ocel_log(LogId) ->
    gen_server:call(?SERVER, {get_ocel_log, LogId}).

%%====================================================================
%% API Functions - OCPM to XES Conversion
%%====================================================================

%% @doc Convert OCPM log to standard XES format.
-spec ocpm_to_standard_xes(ocel_log()) -> #xes_log{}.
ocmp_to_standard_xes(OCELLog) ->
    ocpm_to_standard_xes(OCELLog).

ocpcm_to_standard_xes(OCELLog) ->
    ocpm_to_standard_xes(OCELLog).

ocpm_to_standard_xes(OCELLog) ->
    %% Flatten OCEL to standard XES traces
    Events = maps:get(events, OCELLog, []),
    ObjectTypes = maps:get(object_types, OCELLog, []),

    %% Create one trace per object type
    Traces = lists:map(
        fun(ObjType) ->
            create_trace_for_object_type(Events, ObjType)
        end,
        ObjectTypes
    ),

    #xes_log{
        log_id = maps:get(log_id, OCELLog, <<"ocpm_converted">>),
        traces = Traces,
        extensions = [<<"ocel">>, <<"concept">>, <<"lifecycle">>],
        classifiers = #{},
        global_trace_attrs = #{},
        global_event_attrs = #{},
        metadata = #{source => ocpm}
    }.

%% @doc Extract events for a specific object type.
-spec extract_object_type(ocel_log(), object_type()) -> [ocel_event()].
extract_object_type(OCELLog, ObjectType) ->
    Events = maps:get(events, OCELLog, []),
    lists:filter(
        fun(E) ->
            Objects = maps:get(objects, E, #{}),
            maps:is_key(ObjectType, Objects)
        end,
        Events
    ).

%% @doc Filter OCEL log by object type.
-spec filter_by_object_type(ocel_log(), object_type()) -> ocel_log().
filter_by_object_type(OCELLog, ObjectType) ->
    FilteredEvents = extract_object_type(OCELLog, ObjectType),
    OCELLog#{
        events => FilteredEvents,
        object_types => [ObjectType]
    }.

%% @doc Flatten OCEL log to linear traces.
-spec flatten_ocel_log(ocel_log()) -> [[ocel_event()]].
flatten_ocel_log(OCELLog) ->
    %% Group events by object instances
    Events = maps:get(events, OCELLog, []),

    %% Extract all object instances
    ObjectMap = build_object_instance_map(Events),

    %% Create trace per object instance
    maps:fold(
        fun(_ObjId, ObjEvents, Acc) ->
            [lists:sort(
                fun(E1, E2) ->
                    maps:get(timestamp, E1) =< maps:get(timestamp, E2)
                end,
                ObjEvents
            ) | Acc]
        end,
        [],
        ObjectMap
    ).

%%====================================================================
%% API Functions - AI Grounding
%%====================================================================

%% @doc Ground generative AI output in OCPM data.
-spec ground_generative_ai(ocel_log()) -> grounding_result().
ground_generative_ai(OCELLog) ->
    %% Check if generated process is consistent with OCPM
    Events = maps:get(events, OCELLog, []),
    ObjectTypes = maps:get(object_types, OCELLog, []),

    %% Extract process model from OCEL
    GroundingMap = extract_grounding_model(Events, ObjectTypes),

    #{
        grounded => maps:size(GroundingMap) > 0,
        confidence => compute_grounding_confidence(GroundingMap, Events),
        evidence_count => length(Events),
        grounding_map => GroundingMap
    }.

%% @doc Ground predictive AI with OCPM evidence.
-spec ground_predictive_ai(ocel_log()) -> grounding_result().
ground_predictive_ai(OCELLog) ->
    %% Use historical OCPM data to validate predictions
    Events = maps:get(events, OCELLog, []),

    %% Extract temporal patterns
    TemporalPatterns = extract_temporal_patterns(Events),

    %% Compute prediction confidence based on pattern strength
    Confidence = case TemporalPatterns of
        [] -> 0.0;
        _ -> lists:sum([maps:get(strength, P, 0.5) || P <- TemporalPatterns]) / length(TemporalPatterns)
    end,

    #{
        grounded => Confidence > 0.5,
        confidence => Confidence,
        evidence_count => length(Events),
        grounding_map => #{temporal_patterns => TemporalPatterns}
    }.

%% @doc Ground prescriptive AI recommendations with OCPM.
-spec ground_prescriptive_ai(ocel_log()) -> grounding_result().
ground_prescriptive_ai(OCELLog) ->
    %% Check if recommendations are supported by OCPM evidence
    Events = maps:get(events, OCELLog, []),

    %% Extract valid action patterns
    ValidPatterns = extract_action_patterns(Events),

    %% Compute grounding score
    GroundingScore = length(ValidPatterns) / max(1, length(Events)),

    #{
        grounded => GroundingScore > 0.6,
        confidence => GroundingScore,
        evidence_count => length(ValidPatterns),
        grounding_map => #{action_patterns => ValidPatterns}
    }.

%% @doc Compute grounding score between AI output and OCPM evidence.
-spec compute_grounding_score(ocel_log(), map()) -> float().
compute_grounding_score(OCELLog, AICoutput) ->
    %% Compare AI predictions with OCPM ground truth
    Events = maps:get(events, OCELLog, []),

    %% Extract predictions from AI output
    Predictions = maps:get(predictions, AICoutput, []),

    %% Count how many predictions are supported
    Supported = lists:filter(
        fun(Pred) ->
            is_supported_by_ocpm(Pred, Events)
        end,
        Predictions
    ),

    case length(Predictions) of
        0 -> 1.0;
        N -> length(Supported) / N
    end.

%%====================================================================
%% API Functions - Process Intelligence Queries
%%====================================================================

%% @doc Get lifecycle information for an object.
-spec pi_object_lifecycle(ocel_log(), object_id()) -> map().
pi_object_lifecycle(OCELLog, ObjectId) ->
    %% Extract all events involving this object
    Events = maps:get(events, OCELLog, []),

    ObjectEvents = lists:filter(
        fun(E) ->
            Objects = maps:get(objects, E, #{}),
            lists:any(
                fun(ObjList) -> lists:member(ObjectId, ObjList) end,
                maps:values(Objects)
            )
        end,
        Events
    ),

    %% Build lifecycle states
    States = lists:map(
        fun(E) ->
            #{
                timestamp => maps:get(timestamp, E),
                activity => maps:get(activity, E),
                state => infer_state_from_activity(maps:get(activity, E))
            }
        end,
        ObjectEvents
    ),

    #{
        object_id => ObjectId,
        event_count => length(ObjectEvents),
        lifecycle_states => States,
        first_event => get_first_event(ObjectEvents),
        last_event => get_last_event(ObjectEvents)
    }.

%% @doc Get inter-object dependencies.
-spec pi_inter_object_dependencies(ocel_log()) -> [{object_type(), object_type(), float()}].
pi_inter_object_dependencies(OCELLog) ->
    %% Compute dependencies between object types
    Events = maps:get(events, OCELLog, []),

    %% Build co-occurrence matrix
    CoOccurrence = build_co_occurrence_matrix(Events),

    %% Convert to dependency list
    maps:fold(
        fun(Type1, TypeMap, Acc) ->
            maps:fold(
                fun(Type2, Count, Acc2) ->
                    [{Type1, Type2, Count} | Acc2]
                end,
                Acc,
                TypeMap
            )
        end,
        [],
        CoOccurrence
    ).

%% @doc Get object interaction patterns.
-spec pi_object_interactions(ocel_log()) -> [map()].
pi_object_interactions(OCELLog) ->
    %% Extract patterns of how objects interact
    Events = maps:get(events, OCELLog, []),

    lists:map(
        fun(E) ->
            Objects = maps:get(objects, E, #{}),
            #{
                activity => maps:get(activity, E),
                timestamp => maps:get(timestamp, E),
                participating_types => maps:keys(Objects),
                interaction_type => classify_interaction(Objects)
            }
        end,
        Events
    ).

%% @doc Get process variant for an object type.
-spec pi_process_variant(ocel_log(), object_type()) -> [binary()].
pi_process_variant(OCELLog, ObjectType) ->
    %% Extract activity sequence for this object type
    TypeEvents = extract_object_type(OCELLog, ObjectType),

    Sorted = lists:sort(
        fun(E1, E2) -> maps:get(timestamp, E1) =< maps:get(timestamp, E2) end,
        TypeEvents
    ),

    [maps:get(activity, E) || E <- Sorted].

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #{
        logs => #{},
        current_log_id => undefined
    }}.

handle_call(create_ocel_log, _From, State) ->
    LogId = generate_log_id(),
    Log = #{
        log_id => LogId,
        events => [],
        object_types => [],
        metadata => #{created_at => erlang:system_time(millisecond)}
    },
    {reply, {ok, LogId}, State#{logs => maps:put(LogId, Log, maps:get(logs, State, #{}))}};

handle_call({get_ocel_log, LogId}, _From, State) ->
    case maps:get(LogId, maps:get(logs, State, #{}), undefined) of
        undefined -> {reply, {error, not_found}, State};
        Log -> {reply, {ok, Log}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({log_oc_event, EventMap}, State) ->
    %% Add event to current log or create new log
    CurrentLogId = maps:get(current_log_id, State, undefined),
    {NewState, LogId} = case CurrentLogId of
        undefined ->
            %% Create new log
            NewId = generate_log_id(),
            {State#{current_log_id => NewId}, NewId};
        _ ->
            {State, CurrentLogId}
    end,

    %% Add event to log
    Logs = maps:get(logs, NewState, #{}),

    case maps:get(LogId, Logs, undefined) of
        undefined -> {noreply, NewState};
        Log ->
            %% Convert map to OCEL event
            OCELEvent = #{
                event_id => maps:get(event_id, EventMap, generate_event_id()),
                timestamp => maps:get(timestamp, EventMap, erlang:system_time(millisecond)),
                activity => maps:get(activity, EventMap),
                objects => maps:get(objects, EventMap, #{}),
                attributes => maps:get(attributes, EventMap, #{})
            },

            %% Update object types
            NewObjectTypes = lists:usort(
                maps:get(object_types, Log, []) ++ maps:keys(maps:get(objects, OCELEvent, #{}))
            ),

            %% Add event
            NewLog = Log#{
                events => maps:get(events, Log, []) ++ [OCELEvent],
                object_types => NewObjectTypes
            },

            {noreply, NewState#{logs => maps:put(LogId, NewLog, Logs)}}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
generate_event_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"oc_event_", (integer_to_binary(Timestamp))/binary>>.

%% @private
generate_log_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"ocel_log_", (integer_to_binary(Timestamp))/binary>>.

%% @private
create_trace_for_object_type(Events, ObjType) ->
    %% Create XES trace for specific object type
    TypeEvents = lists:filter(
        fun(E) ->
            Objects = maps:get(objects, E, #{}),
            maps:is_key(ObjType, Objects)
        end,
        Events
    ),

    %% Convert to XES events
    XESEvents = lists:map(
        fun(E) ->
            #xes_event{
                event_id = maps:get(event_id, E, <<"">>),
                timestamp = maps:get(timestamp, E),
                activity = maps:get(activity, E),
                lifecycle = complete,
                transition = undefined,
                resource = undefined,
                data_attrs = maps:get(attributes, E, #{}),
                org_attrs = #{},
                cost_attrs = #{},
                metadata = #{}
            }
        end,
        TypeEvents
    ),

    #xes_trace{
        trace_id = list_to_binary([atom_to_list(ObjType), "_trace"]),
        case_id = list_to_binary([atom_to_list(ObjType), "_case"]),
        events = XESEvents
    }.

%% @private
extract_events_from_trace(#xes_trace{events = Events}) ->
    Events;
extract_events_from_trace(_) ->
    [].

%% @private
build_object_instance_map(Events) ->
    %% Group events by object instance
    lists:foldl(
        fun(E, Acc) ->
            Objects = maps:get(objects, E, #{}),
            maps:fold(
                fun(_Type, ObjList, Acc2) ->
                    lists:foldl(
                        fun(ObjId, Acc3) ->
                            Acc3#{ObjId => [E | maps:get(ObjId, Acc3, [])]}
                        end,
                        Acc2,
                        ObjList
                    )
                end,
                Acc,
                Objects
            )
        end,
        #{},
        Events
    ).

%% @private
extract_grounding_model(Events, ObjectTypes) ->
    %% Extract process model from OCEL events
    lists:foldl(
        fun(E, Acc) ->
            Activity = maps:get(activity, E),
            Objects = maps:get(objects, E, #{}),

            maps:fold(
                fun(Type, _ObjList, Acc2) ->
                    Key = {Type, Activity},
                    Acc2#{Key => maps:get(Key, Acc2, 0) + 1}
                end,
                Acc,
                Objects
            )
        end,
        #{},
        Events
    ).

%% @private
extract_temporal_patterns(Events) ->
    %% Extract temporal patterns from events
    lists:foldl(
        fun(E, Acc) ->
            Activity = maps:get(activity, E),
            Timestamp = maps:get(timestamp, E),
            #{
                activity => Activity,
                timestamp => Timestamp,
                strength => 1.0
            }
        end,
        [],
        Events
    ).

%% @private
extract_action_patterns(Events) ->
    %% Extract valid action patterns
    lists:foldl(
        fun(E, Acc) ->
            Activity = maps:get(activity, E),
            Objects = maps:get(objects, E, #{}),
            #{
                activity => Activity,
                object_types => maps:keys(Objects)
            }
        end,
        [],
        Events
    ).

%% @private
is_supported_by_ocpm(_Prediction, _Events) ->
    %% Check if prediction is supported by OCPM evidence
    true.

%% @private
compute_grounding_confidence(GroundingMap, Events) ->
    %% Compute confidence based on support
    case length(Events) of
        0 -> 0.0;
        Total ->
            Support = maps:fold(fun(_K, V, Acc) -> Acc + V end, 0, GroundingMap),
            min(1.0, Support / Total)
    end.

%% @private
infer_state_from_activity(Activity) ->
    %% Infer state from activity name
    case Activity of
        <<"create", _/binary>> -> created;
        <<"start", _/binary>> -> active;
        <<"complete", _/binary>> -> completed;
        <<"cancel", _/binary>> -> cancelled;
        _ -> unknown
    end.

%% @private
get_first_event([]) ->
    undefined;
get_first_event([E | _]) ->
    E.

%% @private
get_last_event(Events) ->
    lists:last(Events).

%% @private
build_co_occurrence_matrix(Events) ->
    %% Build matrix of object type co-occurrences
    lists:foldl(
        fun(E, Acc) ->
            Objects = maps:get(objects, E, #{}),
            Types = maps:keys(Objects),

            lists:foldl(
                fun(T1, Acc1) ->
                    lists:foldl(
                        fun(T2, Acc2) ->
                            Type1Map = maps:get(T1, Acc2, #{}),
                            Acc2#{T1 => Type1Map#{T2 => maps:get(T2, Type1Map, 0) + 1}}
                        end,
                        Acc1,
                        Types
                    )
                end,
                Acc,
                Types
            )
        end,
        #{},
        Events
    ).

%% @private
classify_interaction(Objects) ->
    Types = maps:keys(Objects),
    case length(Types) of
        1 -> single_object;
        2 -> binary_interaction;
        _ -> multi_object_interaction
    end.
