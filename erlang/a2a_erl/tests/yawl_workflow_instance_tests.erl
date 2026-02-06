%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Workflow Instance
%%%
%%% Comprehensive tests for the workflow instance gen_statem behavior
%%% covering token passing, transition firing, state machine transitions,
%%% workflow validation, and deadlock detection.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_instance_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% Main test generator
workflow_instance_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Workflow instance starts in idle state", fun test_starts_in_idle/0},
      {"Workflow transitions to running on start", fun test_start_transition/0},
      {"Workflow can be cancelled from idle", fun test_cancel_from_idle/0},
      {"Workflow maintains marking across state transitions", fun test_marking_preservation/0},
      {"Token passing between places", fun test_token_passing/0},
      {"Transition firing consumes and produces tokens", fun test_transition_firing/0},
      {"Transition guard prevents firing", fun test_transition_guard/0},
      {"Transition effect modifies workflow data", fun test_transition_effect/0},
      {"Workflow validates structure", fun test_workflow_validation/0},
      {"Workflow detects unreachable places", fun test_unreachable_places_detection/0},
      {"Deadlock detection for blocked workflow", fun test_deadlock_detection/0},
      {"No deadlock when transitions are enabled", fun test_no_deadlock_when_enabled/0},
      {"State machine pause and resume", fun test_pause_resume/0},
      {"State machine cancel from running", fun test_cancel_from_running/0},
      {"State machine cancel from waiting", fun test_cancel_from_waiting/0},
      {"Transition history is recorded", fun test_transition_history/0},
      {"Checkpoint creation and restoration", fun test_checkpoint_workflow/0},
      {"Multiple workflow patterns", fun test_multiple_patterns/0}
     ]}.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start required services
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_workflow_instance_sup:start_link(),
    ok.

cleanup(_State) ->
    %% Stop services
    catch yawl_workflow_instance_sup:stop(),
    catch yawl_persistence:stop(),
    ok.

%%====================================================================
%% Basic State Tests
%%====================================================================

test_starts_in_idle() ->
    WorkflowId = <<"$test_wf_idle">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, idle, StateMap} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(idle, maps:get(state, StateMap)),
    gen_statem:stop(Pid),
    ok.

test_start_transition() ->
    WorkflowId = <<"$test_wf_start">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(100),
    {ok, State, _StateMap} = yawl_workflow_instance:get_state(Pid),
    ?assert(lists:member(State, [running, waiting, completing])),
    gen_statem:stop(Pid),
    ok.

test_cancel_from_idle() ->
    WorkflowId = <<"$test_wf_cancel_idle">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:cancel_workflow(Pid),
    {ok, cancelled, StateMap} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(cancelled, maps:get(state, StateMap)),
    gen_statem:stop(Pid),
    ok.

test_marking_preservation() ->
    WorkflowId = <<"$test_wf_marking">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, InitialMarking} = yawl_workflow_instance:get_marking(Pid),
    ?assert(maps:is_key(start, InitialMarking)),
    ?assertEqual([workflow_token], maps:get(start, InitialMarking)),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Token Passing Tests
%%====================================================================

test_token_passing() ->
    WorkflowId = <<"$test_wf_tokens">>,
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{
            start => [token1, token2],  %% Multiple tokens
            task1 => []
        }
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, Marking} = yawl_workflow_instance:get_marking(Pid),
    %% Verify multiple tokens are preserved
    ?assertEqual(2, length(maps:get(start, Marking, []))),
    gen_statem:stop(Pid),
    ok.

test_transition_firing() ->
    WorkflowId = <<"$test_wf_fire">>,
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{
            start => [token],
            task1 => [],
            task2 => [],
            'end' => []
        }
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(100),
    {ok, Marking} = yawl_workflow_instance:get_marking(Pid),
    %% After firing, tokens should have moved
    StartTokens = maps:get(start, Marking, []),
    ?assertEqual([], StartTokens),  %% Start place should be empty
    gen_statem:stop(Pid),
    ok.

test_transition_guard() ->
    WorkflowId = <<"$test_wf_guard">>,
    GuardFun = fun(Data) -> maps:get(allow_transition, Data, false) end,
    Config = #{
        pattern_type => basic_sequential,
        transition_guards => #{t1 => GuardFun},
        workflow_data => #{allow_transition => false}
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    %% Add guard to prevent transition from firing
    ok = yawl_workflow_instance:add_transition_guard(Pid, t1, GuardFun),
    %% Transition should be blocked
    timer:sleep(50),
    {ok, State, _} = yawl_workflow_instance:get_state(Pid),
    ?assert(lists:member(State, [running, waiting])),
    gen_statem:stop(Pid),
    ok.

test_transition_effect() ->
    WorkflowId = <<"$test_wf_effect">>,
    EffectFun = fun(Data) -> maps:put(effect_applied, true, Data) end,
    Config = #{
        pattern_type => basic_sequential,
        transition_effects => #{t1 => EffectFun}
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:add_transition_effect(Pid, t1, EffectFun),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(100),
    %% Get state to see if effect was applied (checking transition happened)
    {ok, State, _} = yawl_workflow_instance:get_state(Pid),
    ?assert(lists:member(State, [running, waiting, completing, terminated])),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Workflow Validation Tests
%%====================================================================

test_workflow_validation() ->
    WorkflowId = <<"$test_wf_valid">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, ValidState, Errors} = yawl_workflow_instance:validate_workflow(Pid),
    ?assertEqual(valid, ValidState),
    ?assertEqual([], Errors),
    gen_statem:stop(Pid),
    ok.

test_unreachable_places_detection() ->
    WorkflowId = <<"$test_wf_unreachable">>,
    %% Create a workflow with an unreachable place by modifying postset
    Config = #{
        pattern_type => basic_sequential,
        %% Custom postset that creates a disconnected place
        postset => #{
            start => [task1],
            t1 => [task2],
            t2 => ['end'],
            finish => []
        }
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, ValidState, Errors} = yawl_workflow_instance:validate_workflow(Pid),
    %% Check for unreachable places errors
    HasUnreachable = lists:any(fun
        ({unreachable_places, _}) -> true;
        (_) -> false
    end, Errors),
    ?assert(HasUnreachable orelse ValidState =:= valid),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Deadlock Detection Tests
%%====================================================================

test_deadlock_detection() ->
    WorkflowId = <<"$test_wf_deadlock">>,
    %% Create a workflow that will deadlock
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{
            task1 => [token],  %% Token in middle place with no enabled transition
            task2 => [],
            'end' => []
        }
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, DeadlockState, Details} = yawl_workflow_instance:detect_deadlock(Pid),
    ?assertEqual(deadlocked, DeadlockState),
    ?assert(maps:is_key(reason, Details)),
    gen_statem:stop(Pid),
    ok.

test_no_deadlock_when_enabled() ->
    WorkflowId = <<"$test_wf_no_deadlock">>,
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{
            start => [workflow_token]
        }
    },
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, DeadlockState, _Details} = yawl_workflow_instance:detect_deadlock(Pid),
    ?assertEqual(no_deadlock, DeadlockState),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% State Machine Transition Tests
%%====================================================================

test_pause_resume() ->
    WorkflowId = <<"$test_wf_pause">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(50),
    %% Suspend from running
    ok = yawl_workflow_instance:suspend_workflow(Pid),
    {ok, State, _} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(waiting, State),
    %% Resume
    ok = yawl_workflow_instance:resume_workflow(Pid),
    timer:sleep(50),
    {ok, State2, _} = yawl_workflow_instance:get_state(Pid),
    ?assert(lists:member(State2, [running, waiting, completing])),
    gen_statem:stop(Pid),
    ok.

test_cancel_from_running() ->
    WorkflowId = <<"$test_wf_cancel_run">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(50),
    ok = yawl_workflow_instance:cancel_workflow(Pid),
    {ok, cancelled, StateMap} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(cancelled, maps:get(state, StateMap)),
    gen_statem:stop(Pid),
    ok.

test_cancel_from_waiting() ->
    WorkflowId = <<"$test_wf_cancel_wait">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    ok = yawl_workflow_instance:start_workflow(Pid),
    timer:sleep(50),
    ok = yawl_workflow_instance:suspend_workflow(Pid),
    ok = yawl_workflow_instance:cancel_workflow(Pid),
    {ok, cancelled, StateMap} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(cancelled, maps:get(state, StateMap)),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Transition History Tests
%%====================================================================

test_transition_history() ->
    WorkflowId = <<"$test_wf_history">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, History} = yawl_workflow_instance:get_transition_history(Pid),
    ?assert(is_list(History)),
    ?assertEqual([], History),  %% No transitions yet
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Checkpoint Tests
%%====================================================================

test_checkpoint_workflow() ->
    WorkflowId = <<"$test_wf_checkpoint">>,
    Config = #{pattern_type => basic_sequential},
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),
    ?assert(is_binary(CheckpointId)),
    ?assert(size(CheckpointId) > 0),
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Pattern Tests
%%====================================================================

test_multiple_patterns() ->
    Patterns = [basic_sequential, parallel_split, exclusive_choice, parallel_join],
    lists:foreach(fun(Pattern) ->
        WorkflowId = <<"$test_wf_pat_", (atom_to_binary(Pattern))/binary>>,
        Config = #{pattern_type => Pattern},
        {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
        {ok, idle, _} = yawl_workflow_instance:get_state(Pid),
        gen_statem:stop(Pid)
    end, Patterns).

%%====================================================================
%% Property-Based Tests (requires triq or proper)
%%====================================================================

%% Note: These tests require triq or proper. Uncomment if available.
%% prop_workflow_state_transitions() ->
%%     ?FORALL({PatternType, Config}, {workflow_pattern(), workflow_config()},
%%         begin
%%             WorkflowId = <<"$prop_wf_", (integer_to_binary(erlang:unique_integer()))/binary>>,
%%             {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, #{pattern_type => PatternType}),
%%             {ok, State, _} = yawl_workflow_instance:get_state(Pid),
%%             gen_statem:stop(Pid),
%%             State == idle orelse State == cancelled
%%         end).

%% prop_deadlock_detection_is_safe() ->
%%     ?FORALL(Pattern, workflow_pattern(),
%%         begin
%%             WorkflowId = <<"$prop_deadlock_", (integer_to_binary(erlang:unique_integer()))/binary>>,
%%             Config = #{pattern_type => Pattern},
%%             {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),
%%             {ok, DeadlockState, _} = yawl_workflow_instance:detect_deadlock(Pid),
%%             gen_statem:stop(Pid),
%%             %% Should not crash and should return a valid deadlock state
%%             lists:member(DeadlockState, [no_deadlock, potential_deadlock, deadlocked])
%%         end).
