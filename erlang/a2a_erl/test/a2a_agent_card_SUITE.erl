%%% @doc A2A Agent Card Test Suite
%%%
%%% Common Test suite for testing the agent card gen_server implementation.
%%% Tests cover card creation, retrieval, modification, and skill management.
-module(a2a_agent_card_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/a2a.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_default_card/1,
    test_custom_card/1,
    test_get_card/1,
    test_get_extended_card/1,
    test_set_card/1,
    test_add_skill/1,
    test_remove_skill/1,
    test_update_capabilities/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_default_card,
        test_custom_card,
        test_get_card,
        test_get_extended_card,
        test_set_card,
        test_add_skill,
        test_remove_skill,
        test_update_capabilities
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),

    %% Start the application properly
    case application:ensure_all_started(a2a_erl) of
        {ok, _} ->
            Config;
        {error, {already_started, _}} ->
            Config;
        Error ->
            ct:fail("Failed to start a2a_erl application: ~p", [Error])
    end.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Ensure a fresh agent card server for each test
    case whereis(a2a_agent_card) of
        undefined ->
            {ok, _Pid} = a2a_agent_card:start_link(),
            Config;
        _Pid ->
            %% Already started, unregister to restart fresh
            catch unregister(a2a_agent_card),
            {ok, _NewPid} = a2a_agent_card:start_link(),
            Config
    end.

end_per_testcase(_TestCase, _Config) ->
    %% Stop the agent card server after each test
    case whereis(a2a_agent_card) of
        undefined ->
            ok;
        Pid ->
            gen_server:stop(Pid),
            ok
    end.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% @doc Test that start_link/0 creates a default agent card
test_default_card(_Config) ->
    Card = a2a_agent_card:get_card(),

    %% Verify required fields are present
    ?assert(is_binary(Card#agent_card.name)),
    ?assertEqual(<<"A2A Erlang Agent">>, Card#agent_card.name),

    ?assert(is_binary(Card#agent_card.description)),
    ?assert(is_binary(Card#agent_card.version)),

    %% Verify supported interfaces
    ?assert(length(Card#agent_card.supported_interfaces) > 0),

    %% Verify provider
    ?assert(is_record(Card#agent_card.provider, agent_provider)),

    %% Verify capabilities
    Capabilities = Card#agent_card.capabilities,
    ?assert(is_record(Capabilities, agent_capabilities)),
    ?assertEqual(true, Capabilities#agent_capabilities.streaming),
    ?assertEqual(true, Capabilities#agent_capabilities.push_notifications),
    ?assertEqual(true, Capabilities#agent_capabilities.extended_agent_card),

    %% Verify default input/output modes
    ?assert(length(Card#agent_card.default_input_modes) > 0),
    ?assert(length(Card#agent_card.default_output_modes) > 0),

    %% Verify default skills
    ?assert(length(Card#agent_card.skills) > 0),
    [DefaultSkill | _] = Card#agent_card.skills,
    ?assertEqual(<<"echo">>, DefaultSkill#agent_skill.id),

    ok.

%% @doc Test start_link/1 with a custom agent card
test_custom_card(_Config) ->
    %% Stop the default server
    Pid = whereis(a2a_agent_card),
    gen_server:stop(Pid),

    %% Create a custom card
    CustomCard = create_custom_card(),

    %% Start with custom card
    {ok, _NewPid} = a2a_agent_card:start_link(CustomCard),

    %% Retrieve and verify
    RetrievedCard = a2a_agent_card:get_card(),

    ?assertEqual(<<"Test Agent">>, RetrievedCard#agent_card.name),
    ?assertEqual(<<"A test agent for unit testing">>, RetrievedCard#agent_card.description),
    ?assertEqual(<<"2.0.0">>, RetrievedCard#agent_card.version),

    %% Verify custom skill
    [CustomSkill | _] = RetrievedCard#agent_card.skills,
    ?assertEqual(<<"test-skill">>, CustomSkill#agent_skill.id),

    ok.

%% @doc Test get_card/0 returns the public agent card
test_get_card(_Config) ->
    Card = a2a_agent_card:get_card(),

    %% Verify card structure
    verify_card_structure(Card),

    %% Check specific fields
    ?assert(is_binary(Card#agent_card.name)),
    ?assert(is_binary(Card#agent_card.description)),
    ?assert(is_binary(Card#agent_card.version)),

    %% Verify supported interfaces is a non-empty list
    ?assert(is_list(Card#agent_card.supported_interfaces)),
    ?assert(length(Card#agent_card.supported_interfaces) > 0),

    %% Verify first interface
    [Interface | _] = Card#agent_card.supported_interfaces,
    ?assert(is_record(Interface, agent_interface)),
    ?assert(is_binary(Interface#agent_interface.url)),
    ?assert(is_binary(Interface#agent_interface.protocol_binding)),
    ?assert(is_binary(Interface#agent_interface.protocol_version)),

    ok.

%% @doc Test get_extended_card/0 behavior
test_get_extended_card(_Config) ->
    %% Initially, extended card should be same as public card (undefined -> default)
    ExtendedCard = a2a_agent_card:get_extended_card(),
    PublicCard = a2a_agent_card:get_card(),

    %% When extended_card is undefined, should return public card
    ?assertEqual(PublicCard#agent_card.name, ExtendedCard#agent_card.name),
    ?assertEqual(PublicCard#agent_card.version, ExtendedCard#agent_card.version),

    ok.

%% @doc Test set_card/1 updates the agent card
test_set_card(_Config) ->
    %% Create a new card
    NewCard = #agent_card{
        name = <<"Updated Agent">>,
        description = <<"Updated description">>,
        version = <<"3.0.0">>,
        supported_interfaces = [
            #agent_interface{
                url = <<"https://updated.example.com/a2a">>,
                protocol_binding = <<"JSONRPC">>,
                protocol_version = <<"0.4">>
            }
        ],
        provider = #agent_provider{
            url = <<"https://updated.example.com">>,
            organization = <<"Updated Organization">>
        },
        capabilities = #agent_capabilities{
            streaming = false,
            push_notifications = false,
            extended_agent_card = false,
            extensions = []
        },
        default_input_modes = [<<"text/plain">>],
        default_output_modes = [<<"text/plain">>],
        skills = []
    },

    %% Set the new card
    ok = a2a_agent_card:set_card(NewCard),

    %% Retrieve and verify
    RetrievedCard = a2a_agent_card:get_card(),

    ?assertEqual(<<"Updated Agent">>, RetrievedCard#agent_card.name),
    ?assertEqual(<<"Updated description">>, RetrievedCard#agent_card.description),
    ?assertEqual(<<"3.0.0">>, RetrievedCard#agent_card.version),
    ?assertEqual(<<"Updated Organization">>, (RetrievedCard#agent_card.provider)#agent_provider.organization),

    ok.

%% @doc Test add_skill/1 adds a new skill to the card
test_add_skill(_Config) ->
    %% Get initial skill count
    InitialCard = a2a_agent_card:get_card(),
    InitialCount = length(InitialCard#agent_card.skills),

    %% Create and add a new skill
    TestSkill = #agent_skill{
        id = <<"test-add">>,
        name = <<"Test Add Skill">>,
        description = <<"A skill for testing add functionality">>,
        tags = [<<"test">>, <<"add">>],
        examples = [<<"Test add example">>]
    },
    ok = a2a_agent_card:add_skill(TestSkill),

    %% Verify skill was added
    UpdatedCard = a2a_agent_card:get_card(),
    ?assertEqual(InitialCount + 1, length(UpdatedCard#agent_card.skills)),

    %% Verify the new skill is at the front of the list
    [FirstSkill | _] = UpdatedCard#agent_card.skills,
    ?assertEqual(<<"test-add">>, FirstSkill#agent_skill.id),

    %% Add another skill
    TestSkill2 = #agent_skill{
        id = <<"test-add-2">>,
        name = <<"Test Add Skill 2">>,
        description = <<"Another test skill">>,
        tags = [<<"test">>],
        examples = []
    },
    ok = a2a_agent_card:add_skill(TestSkill2),

    %% Verify both skills are present
    FinalCard = a2a_agent_card:get_card(),
    ?assertEqual(InitialCount + 2, length(FinalCard#agent_card.skills)),

    %% Verify order (most recently added first)
    [Skill1, Skill2 | _] = FinalCard#agent_card.skills,
    ?assertEqual(<<"test-add-2">>, Skill1#agent_skill.id),
    ?assertEqual(<<"test-add">>, Skill2#agent_skill.id),

    ok.

%% @doc Test remove_skill/1 removes a skill by ID
test_remove_skill(_Config) ->
    %% Add some test skills
    Skill1 = #agent_skill{
        id = <<"remove-test-1">>,
        name = <<"Remove Test 1">>,
        description = <<"Skill to be removed">>,
        tags = [<<"test">>],
        examples = []
    },
    Skill2 = #agent_skill{
        id = <<"remove-test-2">>,
        name = <<"Remove Test 2">>,
        description = <<"Another skill to test removal">>,
        tags = [<<"test">>],
        examples = []
    },

    ok = a2a_agent_card:add_skill(Skill1),
    ok = a2a_agent_card:add_skill(Skill2),

    %% Get current skill count
    CardBeforeRemoval = a2a_agent_card:get_card(),
    CountBefore = length(CardBeforeRemoval#agent_card.skills),

    %% Remove the first skill
    ok = a2a_agent_card:remove_skill(<<"remove-test-1">>),

    %% Verify skill was removed
    CardAfterRemoval = a2a_agent_card:get_card(),
    ?assertEqual(CountBefore - 1, length(CardAfterRemoval#agent_card.skills)),

    %% Verify the removed skill is no longer in the list
    SkillIds = [S#agent_skill.id || S <- CardAfterRemoval#agent_card.skills],
    ?assertNot(lists:member(<<"remove-test-1">>, SkillIds)),

    %% Verify the second skill is still present
    ?assert(lists:member(<<"remove-test-2">>, SkillIds)),

    %% Test removing non-existent skill (should not error)
    ok = a2a_agent_card:remove_skill(<<"non-existent-skill">>),

    %% Verify count unchanged
    CardFinal = a2a_agent_card:get_card(),
    ?assertEqual(CountBefore - 1, length(CardFinal#agent_card.skills)),

    ok.

%% @doc Test update_capabilities/1 updates the capabilities
test_update_capabilities(_Config) ->
    %% Get initial capabilities
    InitialCard = a2a_agent_card:get_card(),
    InitialCaps = InitialCard#agent_card.capabilities,

    %% Update capabilities
    NewCaps = #agent_capabilities{
        streaming = false,
        push_notifications = false,
        extended_agent_card = false,
        extensions = [
            #agent_extension{
                uri = <<"https://example.com/ext/test">>,
                description = <<"Test extension">>,
                required = false,
                params = #{}
            }
        ]
    },

    ok = a2a_agent_card:update_capabilities(NewCaps),

    %% Verify capabilities were updated
    UpdatedCard = a2a_agent_card:get_card(),
    UpdatedCaps = UpdatedCard#agent_card.capabilities,

    ?assertEqual(false, UpdatedCaps#agent_capabilities.streaming),
    ?assertEqual(false, UpdatedCaps#agent_capabilities.push_notifications),
    ?assertEqual(false, UpdatedCaps#agent_capabilities.extended_agent_card),

    %% Verify extension was added
    ?assertEqual(1, length(UpdatedCaps#agent_capabilities.extensions)),
    [Ext | _] = UpdatedCaps#agent_capabilities.extensions,
    ?assertEqual(<<"https://example.com/ext/test">>, Ext#agent_extension.uri),

    %% Update back to original values
    ok = a2a_agent_card:update_capabilities(InitialCaps),

    %% Verify restored
    RestoredCard = a2a_agent_card:get_card(),
    RestoredCaps = RestoredCard#agent_card.capabilities,

    ?assertEqual(true, RestoredCaps#agent_capabilities.streaming),
    ?assertEqual(true, RestoredCaps#agent_capabilities.push_notifications),
    ?assertEqual(true, RestoredCaps#agent_capabilities.extended_agent_card),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% @doc Create a custom agent card for testing
-spec create_custom_card() -> agent_card().
create_custom_card() ->
    #agent_card{
        name = <<"Test Agent">>,
        description = <<"A test agent for unit testing">>,
        version = <<"2.0.0">>,
        supported_interfaces = [
            #agent_interface{
                url = <<"https://test.example.com/a2a">>,
                protocol_binding = <<"JSONRPC">>,
                protocol_version = <<"0.4">>
            }
        ],
        provider = #agent_provider{
            url = <<"https://test.example.com">>,
            organization = <<"Test Organization">>
        },
        capabilities = #agent_capabilities{
            streaming = true,
            push_notifications = false,
            extended_agent_card = true,
            extensions = []
        },
        default_input_modes = [<<"text/plain">>, <<"application/json">>],
        default_output_modes = [<<"text/plain">>],
        skills = [
            #agent_skill{
                id = <<"test-skill">>,
                name = <<"Test Skill">>,
                description = <<"A test skill">>,
                tags = [<<"test">>],
                examples = [<<"Test example">>]
            }
        ],
        security_schemes = #{},
        security_requirements = []
    }.

%% @doc Verify the structure of an agent card
-spec verify_card_structure(agent_card()) -> ok.
verify_card_structure(Card) ->
    ?assert(is_record(Card, agent_card)),
    ?assert(is_binary(Card#agent_card.name)),
    ?assert(is_binary(Card#agent_card.description)),
    ?assert(is_binary(Card#agent_card.version)),
    ?assert(is_list(Card#agent_card.supported_interfaces)),
    ?assert(length(Card#agent_card.supported_interfaces) > 0),
    ?assert(is_list(Card#agent_card.default_input_modes)),
    ?assert(length(Card#agent_card.default_input_modes) > 0),
    ?assert(is_list(Card#agent_card.default_output_modes)),
    ?assert(length(Card#agent_card.default_output_modes) > 0),
    ?assert(is_list(Card#agent_card.skills)),
    ?assert(is_record(Card#agent_card.capabilities, agent_capabilities)),
    ok.
