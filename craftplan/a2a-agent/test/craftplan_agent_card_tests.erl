%% @doc Unit tests for craftplan_agent_card module
%% Tests agent discovery, capability registration, and metadata handling

-module(craftplan_agent_card_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_AGENT_ID, <<"craftplan-mcp">>).
-define(TEST_AGENT_NAME, <<"Craftplan MCP Server">>).
-define(TEST_AGENT_VERSION, <<"1.0.0">>).
-define(TEST_AGENT_CAPABILITIES, #{
    tools => [
        #{
            name => <<"build">>,
            description => <<"Build project with craftplan">>,
            inputSchema => #{
                type => <<"object">>,
                properties => #{
                    target => #{
                        type => <<"string">>,
                        enum => [<<"dev">>, <<"prod">>],
                        description => <<"Build target environment">>
                    }
                },
                required => [<<"target">>]
            }
        },
        #{
            name => <<"deploy">>,
            description => <<"Deploy to production">>,
            inputSchema => #{
                type => <<"object">>,
                properties => #{
                    environment => #{
                        type => <<"string">>,
                        description => <<"Target environment">>
                    }
                },
                required => [<<"environment">>]
            }
        }
    ]
}).
-define(TEST_AGENT_METADATA, #{
    name => ?TEST_AGENT_NAME,
    version => ?TEST_AGENT_VERSION,
    description => <<"Craftplan MCP Server for A2A integration">>,
    author => <<"Craftplan Team">>,
    tags => [<<"mcp">>, <<"craftplan">>, <<"a2a">>]
}).

%% Test suite
agent_card_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_agent_card_creation/0,
            fun test_capability_registration/0,
            fun test_agent_discovery/0,
            fun test_metadata_management/0,
            fun test_validation/0,
            fun test_serialization/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock dependencies
    meck:new(gen_server, [passthrough]),
    meck:new(a2a_handler, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(),
    ok.

%% Test agent card creation
test_agent_card_creation() ->
    % Mock gen_server:start_link
    meck:expect(gen_server, start_link,
        fun(module, Args, Options) ->
            {ok, self()}
        end
    ),

    % Test agent card creation
    {ok, Pid} = craftplan_agent_card:start_link(?TEST_AGENT_ID, ?TEST_AGENT_CAPABILITIES),
    ?_assert(is_pid(Pid)).

%% Test capability registration
test_capability_registration() ->
    % Mock successful registration
    meck:expect(a2a_handler, register_agent,
        fun(AgentId, Capabilities) ->
            case AgentId of
                ?TEST_AGENT_ID ->
                    {ok, registered};
                _ ->
                    {error, <<"Invalid agent ID">>}
            end
        end
    ),

    % Test capability registration
    {ok, registered} = craftplan_agent_card:register_capabilities(?TEST_AGENT_ID, ?TEST_AGENT_CAPABILITIES),

    % Verify capabilities were registered
    {ok, RegisteredCapabilities} = craftplan_agent_card:get_capabilities(?TEST_AGENT_ID),
    ?_assertEqual(?TEST_AGENT_CAPABILITIES, RegisteredCapabilities).

%% Test agent discovery
test_agent_discovery() ->
    % Mock agent discovery
    meck:expect(a2a_handler, discover_agents,
        fun() ->
            [
                #{
                    id => ?TEST_AGENT_ID,
                    capabilities => ?TEST_AGENT_CAPABILITIES,
                    status => <<"online">>
                },
                #{
                    id => <<"other-agent">>,
                    capabilities => #{tools => []},
                    status => <<"offline">>
                }
            ]
        end
    ),

    % Test agent discovery
    Agents = craftplan_agent_card:discover_agents(),

    % Verify discovery results
    ?_assertEqual(2, length(Agents)),
    ?_assertEqual(?TEST_AGENT_ID, maps:get(id, lists:nth(1, Agents))),
    ?_assertEqual(<<"online">>, maps:get(status, lists:nth(1, Agents))).

%% Test metadata management
test_metadata_management() ->
    % Test metadata update
    ?_assertEqual(ok, craftplan_agent_card:update_metadata(
        ?TEST_AGENT_ID, ?TEST_AGENT_METADATA
    )),

    % Test metadata retrieval
    {ok, Metadata} = craftplan_agent_card:get_metadata(?TEST_AGENT_ID),

    % Verify metadata
    ?_assertEqual(?TEST_AGENT_NAME, maps:get(name, Metadata)),
    ?_assertEqual(?TEST_AGENT_VERSION, maps:get(version, Metadata)).

%% Test validation
test_validation() ->
    % Test valid agent card
    ValidAgentCard = #{
        id => ?TEST_AGENT_ID,
        name => ?TEST_AGENT_NAME,
        version => ?TEST_AGENT_VERSION,
        capabilities => ?TEST_AGENT_CAPABILITIES
    },

    ?_assertEqual({ok, ValidAgentCard}, craftplan_agent_card:validate_agent_card(ValidAgentCard)),

    % Test invalid agent cards
    InvalidAgentCard1 = ValidAgentCard#{id := undefined},
    ?_assertEqual({error, <<"Missing agent ID">>}, craftplan_agent_card:validate_agent_card(InvalidAgentCard1)),

    InvalidAgentCard2 = ValidAgentCard#{capabilities := undefined},
    ?_assertEqual({error, <<"Missing capabilities">>}, craftplan_agent_card:validate_agent_card(InvalidAgentCard2)).

%% Test serialization
test_serialization() ->
    % Test JSON serialization
    AgentCard = #{
        id => ?TEST_AGENT_ID,
        name => ?TEST_AGENT_NAME,
        version => ?TEST_AGENT_VERSION,
        capabilities => ?TEST_AGENT_CAPABILITIES,
        metadata => ?TEST_AGENT_METADATA
    },

    % Test serialization to JSON
    JsonData = craftplan_agent_card:to_json(AgentCard),
    ?_assert(is_binary(JsonData)),

    % Test deserialization from JSON
    DeserializedCard = craftplan_agent_card:from_json(JsonData),
    ?_assertEqual(AgentCard, DeserializedCard).

%% Helper functions
create_test_agent_card() ->
    #{
        id => ?TEST_AGENT_ID,
        name => ?TEST_AGENT_NAME,
        version => ?TEST_AGENT_VERSION,
        capabilities => ?TEST_AGENT_CAPABILITIES,
        metadata => ?TEST_AGENT_METADATA
    }.

serialize_and_deserialize(Card) ->
    Json = craftplan_agent_card:to_json(Card),
    craftplan_agent_card:from_json(Json).