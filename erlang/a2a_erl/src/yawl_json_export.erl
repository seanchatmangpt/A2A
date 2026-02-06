%%%-------------------------------------------------------------------
%%% @doc
%%% JSON Model Export for LLM Interoperability
%%%
%%% This module provides JSON export/import functionality for YAWL
%%% workflow models, enabling LLM-based generation and modification.
%%%
%%% Features:
%%% - JSON Schema compatible with LLM prompting
%%% - Workflow model serialization/deserialization
%%% - Validation and normalization
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_json_export).
-author("A2A Team").

%% API exports - JSON export
-export([
    export_to_json/1,
    import_from_json/1,
    export_pattern_to_json/2,
    import_pattern_from_json/1
]).

%% API exports - JSON Schema
-export([
    get_json_schema/0,
    validate_json_schema/1,
    generate_schema_example/0
]).

%% API exports - LLM compatibility
-export([
    format_for_llm/1,
    parse_from_llm/1,
    create_llm_prompt/1
]).

-include("yawl_types.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type workflow_json() :: #{
    workflow_id => binary(),
    pattern_type => binary(),
    places => [map()],
    transitions => [map()],
    arcs => [map()],
    metadata => map()
}.

%%====================================================================
%% API Functions - JSON Export
%%====================================================================

%% @doc Export workflow to JSON format.
-spec export_to_json(atom() | map()) -> workflow_json().
export_to_json(NetMod) when is_atom(NetMod) ->
    %% Export from gen_pnet module
    Places = NetMod:place_lst(),
    Transitions = NetMod:trsn_lst(),

    #{
        workflow_id => generate_workflow_id(),
        pattern_type => atom_to_binary(NetMod, utf8),
        places => [export_place(NetMod, P) || P <- Places],
        transitions => [export_transition(NetMod, T) || T <- Transitions],
        arcs => export_arcs(NetMod, Places, Transitions),
        metadata => #{
            exported_at => erlang:system_time(millisecond),
            format => <<"yawl-json">>,
            version => <<"1.0">>
        }
    };
export_to_json(WorkflowMap) when is_map(WorkflowMap) ->
    %% Already a map, just normalize
    normalize_workflow_json(WorkflowMap).

%% @doc Import workflow from JSON format.
-spec import_from_json(workflow_json()) -> {ok, map()} | {error, term()}.
import_from_json(JSON) ->
    try
        Normalized = normalize_workflow_json(JSON),
        validate_workflow_json(Normalized)
    catch
        _:Reason -> {error, {import_failed, Reason}}
    end.

%% @doc Export a specific pattern to JSON.
-spec export_pattern_to_json(atom(), map()) -> workflow_json().
export_pattern_to_json(PatternType, Config) ->
    %% Get pattern structure
    case yawl_patterns:get_pattern_structure(PatternType) of
        {Places, Transitions, Preset, Postset} ->
            #{
                workflow_id => generate_workflow_id(),
                pattern_type => atom_to_binary(PatternType, utf8),
                config => Config,
                places => [#{id => atom_to_binary(P)} || P <- Places],
                transitions => [#{id => atom_to_binary(T)} || T <- Transitions],
                preset => [{atom_to_binary(T), [atom_to_binary(P) || P <- Preset]} || T <- Transitions],
                postset => [{atom_to_binary(P), [atom_to_binary(T) || T <- Postset]} || P <- Places],
                metadata => #{
                    created_at => erlang:system_time(millisecond)
                }
            }
    end.

%% @doc Import pattern from JSON.
-spec import_pattern_from_json(workflow_json()) -> {ok, map()} | {error, term()}.
import_pattern_from_json(JSON) ->
    PatternType = maps:get(pattern_type, JSON, <<"unknown">>),
    Config = maps:get(config, JSON, #{}),
    {ok, #{
        pattern_type => binary_to_existing_atom(PatternType),
        config => Config,
        structure => JSON
    }}.

%%====================================================================
%% API Functions - JSON Schema
%%====================================================================

%% @doc Get JSON schema for YAWL workflow.
-spec get_json_schema() -> map().
get_json_schema() ->
    #{
        <<"$schema">> => <<"https://json-schema.org/draft/2020-12/schema">>,
        <<"$id">> => <<"https://yawl.org/schema/workflow.json">>,
        title => <<"YAWL Workflow">>,
        description => <<"JSON schema for YAWL workflow models">>,
        type => <<"object">>,
        required => [<<"workflow_id">>, <<"pattern_type">>],
        properties => #{
            <<"workflow_id">> => #{
                type => <<"string">>,
                description => <<"Unique identifier for the workflow">>
            },
            <<"pattern_type">> => #{
                type => <<"string">>,
                description => <<"Type of YAWL pattern">>,
                enum => pattern_type_list()
            },
            <<"places">> => #{
                type => <<"array">>,
                description => <<"List of places in the Petri net">>,
                items => #{
                    type => <<"object">>,
                    required => [<<"id">>],
                    properties => #{
                        <<"id">> => #{type => <<"string">>},
                        <<"name">> => #{type => <<"string">>},
                        <<"initialTokens">> => #{type => <<"integer">>}
                    }
                }
            },
            <<"transitions">> => #{
                type => <<"array">>,
                description => <<"List of transitions in the Petri net">>,
                items => #{
                    type => <<"object">>,
                    required => [<<"id">>],
                    properties => #{
                        <<"id">> => #{type => <<"string">>},
                        <<"name">> => #{type => <<"string">>},
                        <<"guard">> => #{type => <<"string">>}
                    }
                }
            },
            <<"arcs">> => #{
                type => <<"array">>,
                description => <<"Arcs connecting places and transitions">>,
                items => #{
                    type => <<"object">>,
                    required => [<<"source">>, <<"target">>],
                    properties => #{
                        <<"source">> => #{type => <<"string">>},
                        <<"target">> => #{type => <<"string">>},
                        <<"expression">> => #{type => <<"string">>}
                    }
                }
            }
        }
    }.

%% @doc Validate JSON against schema.
-spec validate_json_schema(workflow_json()) -> {ok, map()} | {error, term()}.
validate_json_schema(JSON) ->
    RequiredFields = [<<"workflow_id">>, <<"pattern_type">>],
    HasRequired = lists:all(
        fun(Field) -> maps:is_key(Field, JSON) end,
        RequiredFields
    ),

    case HasRequired of
        false ->
            {error, {missing_required_fields, RequiredFields}};
        true ->
            %% Validate structure
            validate_workflow_structure(JSON)
    end.

%% @doc Generate schema example for documentation.
-spec generate_schema_example() -> workflow_json().
generate_schema_example() ->
    #{
        workflow_id => <<"example_sequential_workflow">>,
        pattern_type => <<"basic_sequential">>,
        places => [
            #{id => <<"start">>, name => <<"Start">>, initialTokens => 1},
            #{id => <<"task1">>, name => <<"Task 1">>, initialTokens => 0},
            #{id => <<"task2">>, name => <<"Task 2">>, initialTokens => 0},
            #{id => <<"end">>, name => <<"End">>, initialTokens => 0}
        ],
        transitions => [
            #{id => <<"t1">>, name => <<"Start to Task 1">>},
            #{id => <<"t2">>, name => <<"Task 1 to Task 2">>},
            #{id => <<"t3">>, name => <<"Task 2 to End">>}
        ],
        arcs => [
            #{source => <<"start">>, target => <<"t1">>},
            #{source => <<"t1">>, target => <<"task1">>},
            #{source => <<"task1">>, target => <<"t2">>},
            #{source => <<"t2">>, target => <<"task2">>},
            #{source => <<"task2">>, target => <<"t3">>},
            #{source => <<"t3">>, target => <<"end">>}
        ],
        metadata => #{
            description => <<"Example basic sequential workflow">>
        }
    }.

%%====================================================================
%% API Functions - LLM Compatibility
%%====================================================================

%% @doc Format workflow for LLM consumption.
-spec format_for_llm(atom() | workflow_json()) -> binary().
format_for_llm(NetMod) when is_atom(NetMod) ->
    JSON = export_to_json(NetMod),
    format_for_llm(JSON);
format_for_llm(JSON) ->
    %% Pretty print JSON with explanation
    JSONBin = jiffy:encode(JSON, [pretty]),
    <<"\n--- YAWL Workflow Definition ---\n\n",
      (JSONBin)/binary,
      "\n--- End Workflow Definition ---\n">>.

%% @doc Parse workflow from LLM output.
-spec parse_from_llm(binary()) -> {ok, workflow_json()} | {error, term()}.
parse_from_llm(LLMOutput) ->
    %% Extract JSON from LLM output
    case extract_json_from_text(LLMOutput) of
        {ok, JSONBin} ->
            try jiffy:decode(JSONBin, [return_maps]) of
                JSONMap ->
                    validate_json_schema(JSONMap);
                {error, Reason} ->
                    {error, {invalid_json, Reason}}
            catch
                _:Reason ->
                    {error, {parse_error, Reason}}
            end;
        {error, Reason} ->
            {error, {json_extraction_failed, Reason}}
    end.

%% @doc Create LLM prompt for workflow generation.
-spec create_llm_prompt(map()) -> binary().
create_llm_prompt(Options) ->
    Task = maps:get(task, Options, <<"Generate a YAWL workflow">>),
    Constraints = maps:get(constraints, Options, <<"">>),
    Schema = get_json_schema(),

    Prompt = <<"You are a workflow modeling expert. ",
                (Task)/binary, ".\n\n",
                "Constraints:\n",
                (Constraints)/binary,
                "\n\nJSON Schema for the workflow:\n",
                (jiffy:encode(Schema, [pretty]))/binary,
                "\n\nPlease provide the workflow in JSON format.">>,

    Prompt.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
export_place(NetMod, Place) ->
    InitialTokens = length(NetMod:init_marking(Place, [])),
    #{
        id => atom_to_binary(Place),
        name => atom_to_binary(Place),
        initialTokens => InitialTokens,
        type => <<"place">>
    }.

%% @private
export_transition(_NetMod, Transition) ->
    #{
        id => atom_to_binary(Transition),
        name => atom_to_binary(Transition),
        type => <<"transition">>
    }.

%% @private
export_arcs(NetMod, Places, Transitions) ->
    lists:flatmap(
        fun(T) ->
            Preset = NetMod:preset(T),
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
    ) ++ lists:flatmap(
        fun(T) ->
            %% Find postset places
            lists:flatmap(
                fun(P) ->
                    case lists:member(P, NetMod:preset(T)) of
                        true ->
                            [#{
                                source => atom_to_binary(T),
                                target => atom_to_binary(P),
                                type => <<"transition_to_place">>
                            }];
                        false ->
                            []
                    end
                end,
                Places
            )
        end,
        Transitions
    ).

%% @private
normalize_workflow_json(JSON) ->
    %% Ensure all required fields are present
    WorkflowId = case maps:get(<<"workflow_id">>, JSON) of
        undefined -> generate_workflow_id();
        Id -> Id
    end,

    JSON#{<<"workflow_id">> => WorkflowId}.

%% @private
validate_workflow_json(JSON) ->
    %% Validate JSON workflow structure
    case validate_json_schema(JSON) of
        {ok, _} -> {ok, JSON};
        {error, _} = Error -> Error
    end.

%% @private
validate_workflow_structure(JSON) ->
    %% Check structural validity
    Places = maps:get(<<"places">>, JSON, []),
    Transitions = maps:get(<<"transitions">>, JSON, []),
    Arcs = maps:get(<<"arcs">>, JSON, []),

    PlaceIds = sets:from_list([maps:get(<<"id">>, P) || P <- Places]),
    TransitionIds = sets:from_list([maps:get(<<"id">>, T) || T <- Transitions]),

    %% Validate arcs reference existing nodes
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
        true -> {ok, JSON};
        false -> {error, invalid_arc_references}
    end.

%% @private
extract_json_from_text(Text) ->
    %% Extract JSON from markdown code block or plain text
    Trimmed = string:trim(binary_to_list(Text)),
    case find_json_block(Trimmed) of
        {ok, JSONString} -> {ok, list_to_binary(JSONString)};
        false -> {error, no_json_found}
    end.

%% @private
find_json_block(Text) ->
    %% Look for ```json...``` block
    case re:run(Text, "```json\\s*([\\s\\S]*?)\\s*```") of
        {match, [_, JSON]} ->
            {ok, JSON};
        nomatch ->
            %% Look for plain JSON object
            case re:run(Text, "\\{[\\s\\S]*\\}") of
                {match, [{Start, Length}]} ->
                    JSONString = string:slice(Text, Start, Length),
                    {ok, JSONString};
                nomatch ->
                    false
            end
    end.

%% @private
generate_workflow_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"workflow_", (integer_to_binary(Timestamp))/binary>>.

%% @private
pattern_type_list() ->
    %% List of all valid pattern types
    [<<"basic_sequential">>, <<"parallel_split">>, <<"parallel_join">>,
     <<"exclusive_choice">>, <<"simple_merge">>, <<"iterative_loop">>,
     <<"multi_instance">>, <<"interleaved_parallelism">>, <<"implicit_merge">>,
     <<"multiple_merge">>, <<"deferred_choice">>, <<"milestone">>].

%% @private
binary_to_existing_atom(Binary) ->
    %% Convert binary to atom, defaulting to unknown if not found
    try list_to_existing_atom(binary_to_list(Binary)) of
        Atom -> Atom
    catch
        error:badarg -> unknown
    end.
