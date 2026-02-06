%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL XML Parser
%%%
%%% Tests XML parsing and generation for YAWL workflows.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xml_parser_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

xml_parser_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Parse valid YAWL XML", fun test_parse_valid_xml/0},
      {"Generate XML from workflow", fun test_generate_xml/0},
      {"Round-trip XML conversion", fun test_xml_roundtrip/0},
      {"Validate YAWL schema", fun test_schema_validation/0},
      {"Extract workflow spec", fun test_extract_spec/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    ok.

cleanup(_State) ->
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

test_parse_valid_xml() ->
    %% Create a minimal YAWL XML document
    Xml = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
            <specification xmlns=\"http://www.yawlfoundation.org/yawlschema\" version=\"2.0\" id=\"test_spec\">
              <net id=\"default\">
                <inputCondition id=\"input\" />
                <outputCondition id=\"output\" />
              </net>
            </specification>">>,

    {ok, Workflow} = yawl_xml_parser:parse_workflow(Xml),
    ?assertEqual(<<"test_spec">>, Workflow#yawl_workflow.workflow_id),
    ok.

test_generate_xml() ->
    Workflow = #yawl_workflow{
        workflow_id = <<"gen_test_wf">>,
        pattern_type = basic_sequential,
        status = pending,
        config = #yawl_workflow_config{
            pattern_type = basic_sequential,
            parameters = #{},
            data_mappings = #{}
        },
        marking = #{start => [workflow_token]},
        start_time = erlang:monotonic_time(millisecond),
        metadata = #{
            name => <<"Test Workflow">>,
            source => xml
        }
    },

    {ok, Xml} = yawl_xml_parser:to_xml(Workflow),
    ?assert(is_binary(Xml)),
    ?assert(binary:match(Xml, <<"specification">>) =/= nomatch),
    ok.

test_xml_roundtrip() ->
    %% Create workflow, convert to XML, parse back
    OriginalWorkflow = #yawl_workflow{
        workflow_id = <<"roundtrip_wf">>,
        pattern_type = parallel_split,
        status = pending,
        config = #yawl_workflow_config{
            pattern_type = parallel_split,
            parameters = #{branches => 3},
            data_mappings = #{}
        },
        marking = #{start => [workflow_token]},
        start_time = erlang:monotonic_time(millisecond),
        metadata = #{
            name => <<"Parallel Test Workflow">>,
            source => xml
        }
    },

    {ok, Xml} = yawl_xml_parser:to_xml(OriginalWorkflow),
    {ok, ParsedWorkflow} = yawl_xml_parser:parse_workflow(Xml),

    ?assertEqual(OriginalWorkflow#yawl_workflow.workflow_id,
                 ParsedWorkflow#yawl_workflow.workflow_id),
    ?assertEqual(OriginalWorkflow#yawl_workflow.pattern_type,
                 ParsedWorkflow#yawl_workflow.pattern_type),
    ok.

test_schema_validation() ->
    ValidXml = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
                  <specification xmlns=\"http://www.yawlfoundation.org/yawlschema\" version=\"2.0\" id=\"valid_spec\" />">>,

    {ok, IsValid} = yawl_xml_parser:validate_schema(ValidXml),
    ?assert(IsValid),
    ok.

test_extract_spec() ->
    WorkflowXml = <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
                    <specification xmlns=\"http://www.yawlfoundation.org/yawlschema\" version=\"2.0\" id=\"extract_spec\" />">>,

    {ok, Spec} = yawl_xml_parser:get_workflow_spec(WorkflowXml),
    ?assertEqual(<<"extract_spec">>, maps:get(spec_id, Spec)),
    ?assert(maps:is_key(pattern_type, Spec)),
    ok.

