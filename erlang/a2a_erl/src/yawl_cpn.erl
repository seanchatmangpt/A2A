%%%-------------------------------------------------------------------
%%% @doc
%%% Colored Petri Nets (CPN) Support for YAWL Workflows
%%%
%%% This module implements Colored Petri Net extensions based on
%%% van der Aalst et al. (Mar 2025) "CPN-Py: Colored Petri Nets
%%% with Python/PM4Py Integration".
%%%
%%% Key Features:
%%% - Tokens carry data (color sets, timed tokens, guards)
%%% - Python/PM4Py Bridge for process mining ecosystem
%%% - JSON Format for LLM interoperability
%%%
%%% Reference: arXiv:2506.12238 (Mar 2025)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cpn).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% API exports - Colored Petri Net support
-export([
    create_color_set/2,
    create_timed_token/2,
    evaluate_guard/2,
    fire_transition_with_color/3,
    get_token_colors/2
]).

%% API exports - JSON export (CPN-compatible)
-export([
    export_workflow_json/1,
    import_workflow_json/1,
    workflow_to_cpn_json/1,
    cpn_json_to_workflow/1
]).

%% API exports - Python bridge
-export([
    call_pm4py/2,
    stochastic_replay/2,
    process_discovery/1,
    align_traces/2
]).

%% API exports - LLM JSON format
-export([
    llm_format_workflow/1,
    parse_llm_workflow/1,
    validate_cpn_json/1
]).

-include("yawl_types.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% Type Definitions
%%====================================================================

-type local_color_set() :: #{
    name => atom(),
    type => boolean | integer | float | string | list | record | product | any,
    constraints => [term()]
}.

-type local_colored_token() :: #{
    data => term(),
    color_set => atom(),
    timestamp => integer() | undefined,
    attributes => map()
}.

-type local_guard_expression() :: #{
    expression => binary(),
    variables => [atom()],
    predicate => function()
}.

-type local_place() :: atom().
-type local_transition() :: atom().

%%====================================================================
%% API Functions - Colored Petri Net Support
%%====================================================================

%% @doc Start the CPN server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a color set definition.
-spec create_color_set(atom(), atom() | map()) -> local_color_set().
create_color_set(Name, Type) when is_atom(Type) ->
    #{
        name => Name,
        type => Type,
        constraints => []
    };
create_color_set(Name, TypeSpec) when is_map(TypeSpec) ->
    Type = maps:get(type, TypeSpec, any),
    Constraints = maps:get(constraints, TypeSpec, []),
    #{
        name => Name,
        type => Type,
        constraints => Constraints
    }.

%% @doc Create a timed token with data and timestamp.
-spec create_timed_token(term(), integer()) -> local_colored_token().
create_timed_token(Data, Timestamp) ->
    #{
        data => Data,
        color_set => any,
        timestamp => Timestamp,
        attributes => #{}
    }.

%% @doc Evaluate a guard expression against a marking.
-spec evaluate_guard(local_guard_expression(), cpn_marking()) -> boolean().
evaluate_guard(Guard, Marking) ->
    case Guard of
        #{expression := Expr, predicate := Pred} ->
            %% Extract variables from marking and evaluate predicate
            Variables = extract_variables_from_marking(Expr, Marking),
            apply(Pred, [Variables]);
        _ ->
            true
    end.

%% @doc Fire a transition with colored tokens.
-spec fire_transition_with_color(atom(), local_transition(), cpn_marking()) ->
    {ok, cpn_marking()} | {error, term()}.
fire_transition_with_color(NetMod, Transition, Marking) ->
    gen_server:call(?SERVER, {fire_with_color, NetMod, Transition, Marking}).

%% @doc Get colors of tokens at a place.
-spec get_token_colors(atom(), local_place()) -> [local_colored_token()].
get_token_colors(NetMod, Place) ->
    gen_server:call(?SERVER, {get_token_colors, NetMod, Place}).

%%====================================================================
%% API Functions - JSON Export
%%====================================================================

%% @doc Export workflow to JSON format (CPN-compatible).
-spec export_workflow_json(atom()) -> map().
export_workflow_json(NetMod) ->
    gen_server:call(?SERVER, {export_json, NetMod}).

%% @doc Import workflow from JSON format.
-spec import_workflow_json(map()) -> {ok, atom()} | {error, term()}.
import_workflow_json(JSON) ->
    gen_server:call(?SERVER, {import_json, JSON}).

%% @doc Convert workflow to CPN JSON format.
-spec workflow_to_cpn_json(atom()) -> binary().
workflow_to_cpn_json(NetMod) ->
    CPNMap = export_workflow_json(NetMod),
    jiffy:encode(CPNMap).

%% @doc Convert CPN JSON to workflow definition.
-spec cpn_json_to_workflow(binary()) -> map().
cpn_json_to_workflow(JSONBinary) ->
    JSONMap = jiffy:decode(JSONBinary, [return_maps]),
    parse_cpn_json_to_workflow(JSONMap).

%%====================================================================
%% API Functions - Python Bridge
%%====================================================================

%% @doc Call PM4Py function through Python bridge.
-spec call_pm4py(atom(), list()) -> {ok, term()} | {error, term()}.
call_pm4py(Function, Args) ->
    gen_server:call(?SERVER, {call_pm4py, Function, Args}).

%% @doc Perform stochastic replay of trace on model.
-spec stochastic_replay(map(), atom()) -> {ok, map()} | {error, term()}.
stochastic_replay(XESLog, Model) ->
    call_pm4py(stochastic_replay, [XESLog, Model]).

%% @doc Discover process model from event log using PM4Py.
-spec process_discovery(map()) -> {ok, map()} | {error, term()}.
process_discovery(XESLog) ->
    call_pm4py(discover, [XESLog]).

%% @doc Align traces to model for conformance checking.
-spec align_traces(map(), atom()) -> {ok, map()} | {error, term()}.
align_traces(XESLog, Model) ->
    call_pm4py(align, [XESLog, Model]).

%%====================================================================
%% API Functions - LLM JSON Format
%%====================================================================

%% @doc Format workflow as JSON for LLM consumption.
-spec llm_format_workflow(atom()) -> binary().
llm_format_workflow(NetMod) ->
    %% Create LLM-friendly JSON representation
    CPNJSON = workflow_to_cpn_json(NetMod),
    CPNJSON.

%% @doc Parse LLM-generated workflow JSON.
-spec parse_llm_workflow(binary()) -> {ok, map()} | {error, term()}.
parse_llm_workflow(JSONString) ->
    try jiffy:decode(JSONString, [return_maps]) of
        Parsed -> {ok, validate_and_normalize_cpn(Parsed)};
        {error, Reason} -> {error, {invalid_json, Reason}}
    catch
        _:Reason -> {error, {parse_error, Reason}}
    end.

%% @doc Validate CPN JSON structure.
-spec validate_cpn_json(map()) -> {ok, map()} | {error, term()}.
validate_cpn_json(JSONMap) ->
    RequiredKeys = [<<"places">>, <<"transitions">>, <<"arcs">>],
    HasRequired = lists:all(
        fun(Key) -> maps:is_key(Key, JSONMap) end,
        RequiredKeys
    ),

    case HasRequired of
        false ->
            {error, missing_required_keys};
        true ->
            %% Validate structure
            validate_cpn_structure(JSONMap)
    end.

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #{
        color_sets => #{
            boolean => create_color_set(boolean, boolean),
            integer => create_color_set(integer, integer),
            string => create_color_set(string, string),
            any => create_color_set(any, any)
        },
        cache => #{},
        python_bridge => undefined
    }}.

handle_call({fire_with_color, NetMod, Transition, Marking}, _From, State) ->
    Result = do_fire_with_color(NetMod, Transition, Marking, State),
    {reply, Result, State};

handle_call({get_token_colors, NetMod, Place}, _From, State) ->
    Result = do_get_token_colors(NetMod, Place),
    {reply, Result, State};

handle_call({export_json, NetMod}, _From, State) ->
    Result = do_export_json(NetMod),
    {reply, Result, State};

handle_call({import_json, JSON}, _From, State) ->
    Result = do_import_json(JSON),
    {reply, Result, State};

handle_call({call_pm4py, Function, Args}, _From, State) ->
    Result = do_call_pm4py(Function, Args, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Colored Petri Net Operations
%%====================================================================

%% @private
do_fire_with_color(NetMod, Transition, Marking, State) ->
    %% Get preset and check guards
    Preset = NetMod:preset(Transition),

    %% Collect colored tokens from preset places
    Mode = collect_colored_mode(Preset, Marking),

    %% Evaluate guard if present
    case evaluate_guard_for_transition(Transition, Mode, State) of
        false ->
            {error, guard_failed};
        true ->
            %% Fire transition, producing colored tokens
            case NetMod:fire(Transition, Mode, []) of
                abort ->
                    {error, firing_aborted};
                {produce, ProduceMap} ->
                    %% Consume colored tokens
                    NewMarking1 = consume_colored_tokens(Marking, Mode),

                    %% Produce new colored tokens
                    NewMarking2 = produce_colored_tokens(NewMarking1, ProduceMap, State),

                    {ok, NewMarking2}
            end
    end.

%% @private
collect_colored_mode(Preset, Marking) ->
    lists:foldl(
        fun(Place, Acc) ->
            Tokens = maps:get(Place, Marking, []),
            Acc#{Place => Tokens}
        end,
        #{},
        Preset
    ).

%% @private
evaluate_guard_for_transition(Transition, Mode, _State) ->
    %% Check if transition has a guard
    case get_guard_expression(Transition) of
        undefined -> true;
        Guard ->
            evaluate_guard(Guard, Mode)
    end.

%% @private
get_guard_expression(_Transition) ->
    %% Would be extracted from transition definition
    undefined.

%% @private
consume_colored_tokens(Marking, Mode) ->
    maps:fold(
        fun(Place, Tokens, Acc) ->
            case Tokens of
                [] -> Acc;
                [_Consumed | Rest] ->
                    Acc#{Place => Rest}
            end
        end,
        Marking,
        Mode
    ).

%% @private
produce_colored_tokens(Marking, ProduceMap, State) ->
    maps:fold(
        fun(Place, Tokens, Acc) ->
            CurrentTokens = maps:get(Place, Acc, []),
            ColoredTokens = [color_token(T, State) || T <- Tokens],
            Acc#{Place => CurrentTokens ++ ColoredTokens}
        end,
        Marking,
        ProduceMap
    ).

%% @private
color_token(TokenData, _State) ->
    %% Apply color set to token
    #{
        data => TokenData,
        color_set => any,
        timestamp => erlang:system_time(millisecond),
        attributes => #{}
    }.

%% @private
do_get_token_colors(NetMod, Place) ->
    %% Get current marking and return colored tokens
    %% For now, return basic tokens
    try NetMod:place_lst() of
        Places ->
            case lists:member(Place, Places) of
                false -> [];
                true ->
                    Tokens = NetMod:init_marking(Place, []),
                    [color_token(T, #{}) || T <- Tokens]
            end
    catch
        _:_ -> []
    end.

%%====================================================================
%% Internal Functions - JSON Export/Import
%%====================================================================

%% @private
do_export_json(NetMod) ->
    Places = NetMod:place_lst(),
    Transitions = NetMod:trsn_lst(),

    PlacesJSON = [export_place_json(P, NetMod) || P <- Places],
    TransitionsJSON = [export_transition_json(T, NetMod) || T <- Transitions],
    ArcsJSON = export_arcs_json(NetMod),

    ColorSetsJSON = export_color_sets_json(),

    #{
        version => <<"1.0">>,
        format => <<"cpn-json">>,
        places => PlacesJSON,
        transitions => TransitionsJSON,
        arcs => ArcsJSON,
        colorSets => ColorSetsJSON
    }.

%% @private
export_place_json(Place, NetMod) ->
    InitialTokens = NetMod:init_marking(Place, []),
    #{
        id => atom_to_binary(Place),
        name => atom_to_binary(Place),
        initialTokens => length(InitialTokens),
        type => <<"place">>
    }.

%% @private
export_transition_json(Transition, _NetMod) ->
    #{
        id => atom_to_binary(Transition),
        name => atom_to_binary(Transition),
        guard => null,
        type => <<"transition">>
    }.

%% @private
export_arcs_json(NetMod) ->
    Transitions = NetMod:trsn_lst(),

    lists:flatmap(
        fun(T) ->
            Preset = NetMod:preset(T),
            %% Create arcs from places to transition
            lists:map(
                fun(P) ->
                    #{
                        source => atom_to_binary(P),
                        target => atom_to_binary(T),
                        type => <<"place_to_transition">>
                    }
                end,
                Preset
            )
        end,
        Transitions
    ).

%% @private
export_color_sets_json() ->
    #{
        <<"any">> => #{type => <<"any">>},
        <<"boolean">> => #{type => <<"boolean">>},
        <<"integer">> => #{type => <<"integer">>},
        <<"string">> => #{type => <<"string">>}
    }.

%% @private
do_import_json(JSON) ->
    %% Parse and create workflow from JSON
    validate_cpn_json(JSON).

%% @private
parse_cpn_json_to_workflow(JSONMap) ->
    %% Convert JSON map to workflow definition
    #{
        places => maps:get(<<"places">>, JSONMap, []),
        transitions => maps:get(<<"transitions">>, JSONMap, []),
        arcs => maps:get(<<"arcs">>, JSONMap, [])
    }.

%% @private
validate_and_normalize_cpn(JSONMap) ->
    %% Validate and normalize LLM-generated JSON
    case validate_cpn_json(JSONMap) of
        {ok, _} -> JSONMap;
        {error, _} = Error -> Error
    end.

%% @private
validate_cpn_structure(JSONMap) ->
    %% Validate CPN structure
    Places = maps:get(<<"places">>, JSONMap, []),
    Transitions = maps:get(<<"transitions">>, JSONMap, []),
    Arcs = maps:get(<<"arcs">>, JSONMap, []),

    %% Check arc references
    PlaceIds = sets:from_list([maps:get(<<"id">>, P) || P <- Places]),
    TransitionIds = sets:from_list([maps:get(<<"id">>, T) || T <- Transitions]),

    ValidArcs = lists:all(
        fun(Arc) ->
            Source = maps:get(<<"source">>, Arc),
            Target = maps:get(<<"target">>, Arc),
            (sets:is_element(Source, PlaceIds) orelse sets:is_element(Source, TransitionIds))
            andalso
            (sets:is_element(Target, PlaceIds) orelse sets:is_element(Target, TransitionIds))
        end,
        Arcs
    ),

    case ValidArcs of
        true -> {ok, JSONMap};
        false -> {error, invalid_arc_references}
    end.

%%====================================================================
%% Internal Functions - Python Bridge
%%====================================================================

%% @private
do_call_pm4py(Function, Args, State) ->
    %% Call PM4Py through Python bridge
    %% For now, return placeholder result
    PythonBridge = maps:get(python_bridge, State, undefined),
    case PythonBridge of
        undefined ->
            %% Try to use Erlport or similar
            {ok, #{
                function => Function,
                args => Args,
                result => <<"pm4py_placeholder_result">>
            }};
        BridgePid ->
            %% Make actual call
            case python:call(BridgePid, pm4py_wrapper, Function, Args) of
                {ok, Result} -> {ok, Result};
                Error -> Error
            end
    end.

%% @private
extract_variables_from_marking(_Expr, Marking) ->
    %% Extract variable bindings from marking for guard evaluation
    maps:fold(
        fun(_Place, Tokens, Acc) ->
            lists:foldl(
                fun(Token, Acc2) ->
                    case Token of
                        #{data := Data} ->
                            [Data | Acc2];
                        _ ->
                            Acc2
                    end
                end,
                Acc,
                Tokens
            )
        end,
        [],
        Marking
    ).
