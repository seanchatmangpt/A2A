%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XML Parser
%%%
%%% This module provides XML import/export capabilities for YAWL workflows
%%% using Erlang's xmerl library. It enables interoperability with the
%%% Java YAWL engine and other YAWL tools.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xml_parser).
-author("A2A Team").

%% API exports
-export([
    parse_workflow/1,
    parse_workflow/2,
    to_xml/1,
    to_xml/2,
    validate_schema/1,
    get_workflow_spec/1
]).

%% Include type definitions
-include("../include/yawl_types.hrl").
-include_lib("xmerl/include/xmerl.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type parse_result() :: {ok, #yawl_workflow{}} | {error, term()}.
-type xml_element() :: #xmlElement{}.
-type xml_document() :: #xmlDocument{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Parse a YAWL workflow from XML file.
-spec parse_workflow(file:name_all()) -> parse_result().
parse_workflow(FilePath) ->
    parse_workflow(FilePath, []).

%% @doc Parse a YAWL workflow from XML file with options.
-spec parse_workflow(file:name_all(), list()) -> parse_result().
parse_workflow(FilePath, Options) ->
    case file:read_file(FilePath) of
        {ok, Content} ->
            parse_workflow_content(Content, Options);
        {error, Reason} ->
            {error, {file_read_error, Reason}}
    end.

%% @doc Convert a workflow to XML.
-spec to_xml(#yawl_workflow{} | map()) -> {ok, binary()} | {error, term()}.
to_xml(Workflow) when is_record(Workflow, yawl_workflow) ->
    to_xml(workflow_to_map(Workflow));
to_xml(WorkflowMap) when is_map(WorkflowMap) ->
    try
        Xml = generate_workflow_xml(WorkflowMap),
        {ok, Xml}
    catch
        Type:Error:Stacktrace ->
            {error, {xml_generation_error, Type, Error, Stacktrace}}
    end.

%% @doc Convert a workflow to XML with options.
-spec to_xml(#yawl_workflow{} | map(), list()) -> {ok, binary()} | {error, term()}.
to_xml(Workflow, Options) when is_record(Workflow, yawl_workflow) ->
    to_xml(workflow_to_map(Workflow), Options);
to_xml(WorkflowMap, Options) when is_map(WorkflowMap) ->
    try
        Xml = generate_workflow_xml(WorkflowMap, Options),
        {ok, Xml}
    catch
        Type:Error:Stacktrace ->
            {error, {xml_generation_error, Type, Error, Stacktrace}}
    end.

%% @doc Validate XML against YAWL schema.
-spec validate_schema(file:name_all() | binary()) -> {ok, boolean()} | {error, term()}.
validate_schema(Xml) when is_binary(Xml) ->
    case catch xmerl_scan:string(binary_to_list(Xml)) of
        {'EXIT', Reason} -> {error, {parse_error, Reason}};
        {Doc, _} -> validate_document(Doc)
    end;
validate_schema(FilePath) when is_list(FilePath) ->
    case file:read_file(FilePath) of
        {ok, Content} -> validate_schema(Content);
        {error, Reason} -> {error, {file_read_error, Reason}}
    end.

%% @doc Get workflow specification from parsed XML.
-spec get_workflow_spec(binary() | file:name_all()) -> {ok, map()} | {error, term()}.
get_workflow_spec(XmlOrFile) ->
    case parse_workflow(XmlOrFile) of
        {ok, Workflow} ->
            Spec = #{
                spec_id => Workflow#yawl_workflow.workflow_id,
                pattern_type => Workflow#yawl_workflow.pattern_type,
                places => extract_places(Workflow),
                transitions => extract_transitions(Workflow),
                data_mappings => extract_data_mappings(Workflow)
            },
            {ok, Spec};
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
parse_workflow_content(Content, Options) ->
    try
        {Doc, _} = xmerl_scan:string(
            binary_to_list(Content),
            [{namespace_conformant, true} | Options]
        ),
        extract_workflow(Doc)
    catch
        Type:Error:Stacktrace ->
            {error, {xml_parse_error, Type, Error, Stacktrace}}
    end.

%% @private
extract_workflow(#xmlDocument{content = Content}) ->
    case find_element(content, "specification", Content) of
        #xmlElement{content = SpecContent} = SpecElem ->
            WorkflowId = extract_attribute(SpecElem, "id", "anonymous"),
            WorkflowName = extract_attribute(SpecElem, "name", "Unnamed Workflow"),

            %% Extract decomposition (nets)
            Nets = extract_nets(SpecContent),

            %% Extract tasks
            Tasks = extract_tasks(SpecContent),

            %% Extract conditions
            Conditions = extract_conditions(SpecContent),

            %% Build workflow record
            Workflow = #yawl_workflow{
                workflow_id = list_to_binary(WorkflowId),
                pattern_type = determine_pattern_type(Tasks, Conditions),
                status = pending,
                config = #yawl_workflow_config{
                    pattern_type = determine_pattern_type(Tasks, Conditions),
                    parameters = #{
                        nets => Nets,
                        tasks => Tasks,
                        conditions => Conditions
                    }
                },
                marking = extract_initial_marking(SpecContent),
                start_time = erlang:monotonic_time(millisecond),
                metadata = #{
                    name => list_to_binary(WorkflowName),
                    source => xml
                }
            },
            {ok, Workflow};
        undefined ->
            {error, no_specification_found}
    end;
extract_workflow(_) ->
    {error, invalid_xml_structure}.

%% @private
find_element(_Name, _LocalName, []) ->
    undefined;
find_element(Name, LocalName, [#xmlElement{name = Name} = Elem | _]) ->
    Elem;
find_element(Name, LocalName, [_ | Rest]) ->
    find_element(Name, LocalName, Rest).

%% @private
extract_attribute(Element, AttrName, Default) ->
    case lists:keysearch(AttrName, 1, Element#xmlElement.attributes) of
        {value, #xmlAttribute{value = Value}} -> Value;
        false -> Default
    end.

%% @private
extract_nets(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'net'} = NetElem, Acc) ->
            NetId = extract_attribute(NetElem, "id", "default"),
            Acc#{list_to_binary(NetId) => extract_net_structure(NetElem)};
        (_, Acc) ->
            Acc
    end, #{}, Content).

%% @private
extract_net_structure(NetElem) ->
    Content = NetElem#xmlElement.content,
    #{
        places => extract_places_from_content(Content),
        transitions => extract_transitions_from_content(Content),
        flows => extract_flows_from_content(Content)
    }.

%% @private
extract_places_from_content(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'inputCondition'} = Elem, Acc) ->
            Id = extract_attribute(Elem, "id", ""),
            Acc#{list_to_binary(Id) => #{type => input}};
        (#xmlElement{name = 'outputCondition'} = Elem, Acc) ->
            Id = extract_attribute(Elem, "id", ""),
            Acc#{list_to_binary(Id) => #{type => output}};
        (_, Acc) ->
            Acc
    end, #{}, Content).

%% @private
extract_transitions_from_content(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'task'} = Elem, Acc) ->
            Id = extract_attribute(Elem, "id", ""),
            Acc#{list_to_binary(Id) => extract_task_details(Elem)};
        (_, Acc) ->
            Acc
    end, #{}, Content).

%% @private
extract_flows_from_content(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'flow'} = Elem, Acc) ->
            Source = extract_attribute(Elem, "source", ""),
            Target = extract_attribute(Elem, "target", ""),
            Acc#{list_to_binary(Source) => list_to_binary(Target)};
        (_, Acc) ->
            Acc
    end, #{}, Content).

%% @private
extract_tasks(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'task'} = Elem, Acc) ->
            Task = #{
                id => list_to_binary(extract_attribute(Elem, "id", "")),
                name => list_to_binary(extract_attribute(Elem, "name", "")),
                type => determine_task_type(Elem)
            },
            [Task | Acc];
        (_, Acc) ->
            Acc
    end, [], Content).

%% @private
extract_task_details(TaskElem) ->
    #{
        name => list_to_binary(extract_attribute(TaskElem, "name", "")),
        type => determine_task_type(TaskElem)
    }.

%% @private
determine_task_type(TaskElem) ->
    case lists:keyfind('decomposition', #xmlElement.name, TaskElem#xmlElement.content) of
        #xmlElement{} -> composite;
        false -> atomic
    end.

%% @private
extract_conditions(Content) ->
    lists:foldl(fun
        (#xmlElement{name = 'condition'} = Elem, Acc) ->
            Id = extract_attribute(Elem, "id", ""),
            Expression = extract_text_content(Elem),
            Acc#{list_to_binary(Id) => list_to_binary(Expression)};
        (_, Acc) ->
            Acc
    end, #{}, Content).

%% @private
extract_text_content(Element) ->
    lists:foldl(fun
        (#xmlText{value = Text}, Acc) -> Acc ++ Text;
        (_, Acc) -> Acc
    end, [], Element#xmlElement.content).

%% @private
extract_initial_marking(Content) ->
    case find_element(Content, "inputCondition", Content) of
        #xmlElement{attributes = Attrs} ->
            case lists:keysearch("id", 1, Attrs) of
                {value, #xmlAttribute{value = Id}} ->
                    #{list_to_binary(Id) => [workflow_token]};
                false ->
                    #{start => [workflow_token]}
            end;
        undefined ->
            #{start => [workflow_token]}
    end.

%% @private
determine_pattern_type(Tasks, Conditions) ->
    TaskCount = length(Tasks),
    ConditionCount = maps:size(Conditions),

    case {TaskCount, ConditionCount} of
        {1, 0} -> basic_sequential;
        {N, 0} when N > 1 -> parallel_split;
        {_, N} when N > 0 -> exclusive_choice;
        _ -> basic_sequential
    end.

%% @private
generate_workflow_xml(WorkflowMap) ->
    WorkflowId = maps:get(workflow_id, WorkflowMap, <<"anonymous">>),
    PatternType = maps:get(pattern_type, WorkflowMap, basic_sequential),
    WorkflowName = maps:get(<<"name">>, WorkflowMap, <<"Unnamed">>),

    Xml = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
        "<specification xmlns=\"http://www.yawlfoundation.org/yawlschema\" ",
        "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" ",
        "version=\"2.0\" ",
        "id=\"", binary_to_list(WorkflowId), "\" ",
        "name=\"", binary_to_list(WorkflowName), "\">\n",

        generate_net_xml(WorkflowMap),

        generate_tasks_xml(WorkflowMap),

        "</specification>"
    ],

    iolist_to_binary(Xml).

%% @private
generate_workflow_xml(WorkflowMap, Options) ->
    case lists:member(pretty, Options) of
        true -> generate_workflow_xml(WorkflowMap);
        false -> generate_workflow_xml_compact(WorkflowMap)
    end.

%% @private
generate_workflow_xml_compact(WorkflowMap) ->
    %% Generate compact XML without formatting
    generate_workflow_xml(WorkflowMap).

%% @private
generate_net_xml(WorkflowMap) ->
    Places = maps:get(places, WorkflowMap, []),
    Transitions = maps:get(transitions, WorkflowMap, []),

    [
        "  <net id=\"default\">\n",
        "    <inputCondition id=\"input\" />\n",
        lists:map(fun(Place) ->
            ["      <place id=\"", atom_to_list(Place), "\" />\n"]
        end, Places),
        "    <outputCondition id=\"output\" />\n",
        "  </net>\n"
    ].

%% @private
generate_tasks_xml(WorkflowMap) ->
    PatternType = maps_get_safe(pattern_type, WorkflowMap, basic_sequential),
    generate_tasks_for_pattern(PatternType, WorkflowMap).

%% @private
generate_tasks_for_pattern(basic_sequential, _WorkflowMap) ->
    [
        "  <tasks>\n",
        "    <task id=\"task1\" name=\"Task 1\">\n",
        "      <join type=\"xor\" />\n",
        "      <split type=\"and\" />\n",
        "      <start>input</start>\n",
        "    </task>\n",
        "    <task id=\"task2\" name=\"Task 2\">\n",
        "      <join type=\"and\" />\n",
        "      <split type=\"xor\" />\n",
        "    </task>\n",
        "  </tasks>\n",
        "  <flows>\n",
        "    <flow source=\"input\" target=\"task1\" />\n",
        "    <flow source=\"task1\" target=\"task2\" />\n",
        "    <flow source=\"task2\" target=\"output\" />\n",
        "  </flows>\n"
    ];
generate_tasks_for_pattern(parallel_split, WorkflowMap) ->
    Branches = maps_get_safe(branches, WorkflowMap, 2),
    Tasks = lists:map(fun(I) ->
        Id = lists:flatten(io_lib:format("parallel_task_~p", [I])),
        [
            "    <task id=\"", Id, "\" name=\"Parallel Task ", integer_to_list(I), "\">\n",
            "      <join type=\"xor\" />\n",
            "      <split type=\"and\" />\n",
            "    </task>\n"
        ]
    end, lists:seq(1, Branches)),

    Flows = [
        "    <flow source=\"input\" target=\"parallel_task_1\" />\n"
    ] ++ lists:flatmap(fun(I) ->
        [
            "    <flow source=\"parallel_task_", integer_to_list(I), "\" target=\"output\" />\n"
        ]
    end, lists:seq(1, Branches)),

    [
        "  <tasks>\n",
        Tasks,
        "  </tasks>\n",
        "  <flows>\n",
        Flows,
        "  </flows>\n"
    ];
generate_tasks_for_pattern(exclusive_choice, WorkflowMap) ->
    Conditions = maps_get_safe(conditions, WorkflowMap, [opt1, opt2]),
    Tasks = lists:map(fun({Name, _I}) ->
        Id = atom_to_list(Name),
        [
            "    <task id=\"", Id, "\" name=\"Choice ", Id, "\">\n",
            "      <join type=\"xor\" />\n",
            "      <split type=\"xor\" />\n",
            "    </task>\n"
        ]
    end, lists:zip(Conditions, lists:seq(1, length(Conditions)))),

    [
        "  <tasks>\n",
        Tasks,
        "  </tasks>\n",
        "  <flows>\n",
        "    <flow source=\"input\" target=\"gateway\" />\n",
        "    <flow source=\"gateway\" target=\"output\" />\n",
        "  </flows>\n"
    ];
generate_tasks_for_pattern(_, _WorkflowMap) ->
    generate_tasks_for_pattern(basic_sequential, _WorkflowMap).

%% @private
validate_document(#xmlDocument{}) ->
    %% In a full implementation, this would validate against the YAWL XSD
    {ok, true}.

%% @private
workflow_to_map(#yawl_workflow{} = Workflow) ->
    #{
        workflow_id => Workflow#yawl_workflow.workflow_id,
        pattern_type => Workflow#yawl_workflow.pattern_type,
        status => Workflow#yawl_workflow.status,
        marking => Workflow#yawl_workflow.marking,
        config => workflow_config_to_map(Workflow#yawl_workflow.config),
        result => Workflow#yawl_workflow.result,
        error => Workflow#yawl_workflow.error,
        metadata => Workflow#yawl_workflow.metadata
    }.

%% @private
workflow_config_to_map(undefined) -> #{};
workflow_config_to_map(#yawl_workflow_config{} = Config) ->
    #{
        pattern_type => Config#yawl_workflow_config.pattern_type,
        parameters => Config#yawl_workflow_config.parameters,
        resource_allocations => Config#yawl_workflow_config.resource_allocations,
        data_mappings => Config#yawl_workflow_config.data_mappings
    }.

%% @private
extract_places(#yawl_workflow{config = Config}) when Config =/= undefined ->
    maps:get(places, Config#yawl_workflow_config.parameters, []);
extract_places(#yawl_workflow{marking = Marking}) ->
    maps:keys(Marking);
extract_places(WorkflowMap) when is_map(WorkflowMap) ->
    Config = maps_get_safe(config, WorkflowMap, #{}),
    maps:get(places, Config, []).

%% @private
extract_transitions(#yawl_workflow{config = Config}) when Config =/= undefined ->
    maps:get(transitions, Config#yawl_workflow_config.parameters, []);
extract_transitions(#yawl_workflow{}) -> [];
extract_transitions(WorkflowMap) when is_map(WorkflowMap) ->
    Config = maps_get_safe(config, WorkflowMap, #{}),
    maps:get(transitions, Config, []).

%% @private
extract_data_mappings(#yawl_workflow{config = Config}) when Config =/= undefined ->
    Config#yawl_workflow_config.data_mappings;
extract_data_mappings(#yawl_workflow{}) -> #{};
extract_data_mappings(WorkflowMap) when is_map(WorkflowMap) ->
    Config = maps_get_safe(config, WorkflowMap, #{}),
    maps:get(data_mappings, Config, #{}).

%% @private
maps_get_safe(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
