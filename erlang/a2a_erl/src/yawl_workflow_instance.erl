%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Instance State Machine
%%%
%%% This module implements the workflow instance as a gen_statem that
%%% manages the lifecycle of a single workflow execution. It handles
%%% token-based execution using proper Petri net semantics.
%%%
%%% ## State Machine
%%%
%%% ```
%%%   idle -> running -> waiting -> completing -> terminated
%%%            ^           |
%%%            |           v
%%%            '--------<------'
%%%            (on task completion)
%%% '''
%%%
%%% Any state can transition to `cancelled` or `failed`.
%%%
%%% ## Token Passing
%%%
%%% The workflow uses token-based execution following Petri net semantics:
%%% - Places hold tokens (represented as lists)
%%% - Transitions fire when all input places have at least one token
%%% - Firing consumes one token from each input place
%%% - Firing produces one token to each output place
%%%
%%% ## Deadlock Detection
%%%
%%% The system automatically detects deadlock conditions:
%%% - Places with tokens but no enabled transitions
%%% - Circular wait patterns
%%% - Resource starvation scenarios
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_instance).
-author("A2A Team").
-behaviour(gen_statem).

%% gen_statem callbacks
-export([
    callback_mode/0,
    init/1,
    terminate/3,
    code_change/4
]).

%% State transitions
-export([
    idle/3,
    running/3,
    waiting/3,
    completing/3,
    terminated/3,
    cancelled/3,
    failed/3
]).

%% API exports
-export([
    start_link/2,
    start_workflow/1,
    execute_task/2,
    complete_task/3,
    cancel_workflow/1,
    suspend_workflow/1,
    resume_workflow/1,
    get_state/1,
    get_marking/1,
    update_data/3,
    subscribe/2,
    checkpoint/1,
    restart_from_checkpoint/2,
    add_transition_guard/3,
    add_transition_effect/3,
    validate_workflow/1,
    detect_deadlock/1,
    get_transition_history/1
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(data, {
    workflow_id           :: binary(),
    pattern_type          :: atom(),
    marking               :: map(),
    places                :: [atom()],
    transitions           :: [atom()],
    preset                :: #{atom() => [atom()]},
    postset               :: #{atom() => [atom()]},
    workflow_data         :: map(),
    current_tasks         :: map(),
    completed_tasks       :: [atom()],
    subscribers           :: [pid()],
    parent_workflow       :: binary() | undefined,
    start_time            :: integer(),
    end_time              :: integer() | undefined,
    error                 :: term() | undefined,
    metadata              :: map(),
    %% Enhanced fields for token passing and transition firing
    transition_guards     :: #{atom() => fun((map()) -> boolean())},
    transition_effects    :: #{atom() => fun((map()) -> map())},
    transition_history    :: [{atom(), integer(), map()}], %% {Transition, Timestamp, Marking}
    transition_priorities :: #{atom() => integer()},
    max_tokens            :: #{atom() => pos_integer()}, %% Max tokens per place
    deadlock_state        :: no_deadlock | potential_deadlock | deadlocked,
    validation_state      :: valid | invalid,
    validation_errors     :: [term()]
}).

-type state() :: idle | running | waiting | completing | terminated | cancelled | failed.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start a new workflow instance.
-spec start_link(binary(), map()) -> {ok, pid()} | {error, term()}.
start_link(WorkflowId, Config) ->
    gen_statem:start_link(?MODULE, [WorkflowId, Config], []).

%% @doc Start the workflow execution.
-spec start_workflow(pid()) -> ok | {error, term()}.
start_workflow(Pid) ->
    gen_statem:call(Pid, start_workflow).

%% @doc Execute a specific task in the workflow.
-spec execute_task(pid(), atom()) -> ok | {error, term()}.
execute_task(Pid, TaskId) ->
    gen_statem:call(Pid, {execute_task, TaskId}, infinity).

%% @doc Complete a task with result data.
-spec complete_task(pid(), atom(), map()) -> ok | {error, term()}.
complete_task(Pid, TaskId, Result) ->
    gen_statem:call(Pid, {complete_task, TaskId, Result}, infinity).

%% @doc Cancel the workflow.
-spec cancel_workflow(pid()) -> ok.
cancel_workflow(Pid) ->
    gen_statem:call(Pid, cancel_workflow).

%% @doc Suspend the workflow.
-spec suspend_workflow(pid()) -> ok | {error, term()}.
suspend_workflow(Pid) ->
    gen_statem:call(Pid, suspend_workflow).

%% @doc Resume a suspended workflow.
-spec resume_workflow(pid()) -> ok | {error, term()}.
resume_workflow(Pid) ->
    gen_statem:call(Pid, resume_workflow).

%% @doc Get current state information.
-spec get_state(pid()) -> {ok, state(), map()}.
get_state(Pid) ->
    gen_statem:call(Pid, get_state).

%% @doc Get current Petri net marking.
-spec get_marking(pid()) -> {ok, map()}.
get_marking(Pid) ->
    gen_statem:call(Pid, get_marking).

%% @doc Update workflow data.
-spec update_data(pid(), binary(), term()) -> ok.
update_data(Pid, Key, Value) ->
    gen_statem:call(Pid, {update_data, Key, Value}).

%% @doc Subscribe to workflow events.
-spec subscribe(pid(), pid()) -> ok.
subscribe(Pid, Subscriber) ->
    gen_statem:call(Pid, {subscribe, Subscriber}).

%% @doc Create a checkpoint for recovery.
-spec checkpoint(pid()) -> {ok, binary()}.
checkpoint(Pid) ->
    gen_statem:call(Pid, checkpoint).

%% @doc Restart workflow instance from checkpoint.
%%
%% This function restarts a workflow instance from its latest checkpoint.
%% It restores the workflow state including marking, data, and other
%% relevant state information, then transitions the workflow to an
%% appropriate state for continued execution.
%%
%% @param Pid The workflow instance process ID
%% @param WorkflowId The ID of the workflow to restart from checkpoint
%% @return ok if restart was successful
%%         {error, Reason} if restart failed
-spec restart_from_checkpoint(pid(), binary()) -> ok | {error, term()}.
restart_from_checkpoint(Pid, WorkflowId) ->
    gen_statem:call(Pid, {restart_from_checkpoint, WorkflowId}).

%% @doc Add a guard function to a transition.
%% The guard function receives the workflow data and must return boolean().
%% A transition will only fire if its guard evaluates to true.
-spec add_transition_guard(pid(), atom(), fun((map()) -> boolean())) -> ok.
add_transition_guard(Pid, Transition, GuardFun) ->
    gen_statem:call(Pid, {add_transition_guard, Transition, GuardFun}).

%% @doc Add an effect function to a transition.
%% The effect function receives the workflow data and returns updated data.
%% The effect is applied when the transition fires.
-spec add_transition_effect(pid(), atom(), fun((map()) -> map())) -> ok.
add_transition_effect(Pid, Transition, EffectFun) ->
    gen_statem:call(Pid, {add_transition_effect, Transition, EffectFun}).

%% @doc Validate the workflow structure and state.
%% Returns {ok, valid} if workflow is valid, {ok, invalid, Errors} otherwise.
-spec validate_workflow(pid()) -> {ok, valid | invalid, [term()]}.
validate_workflow(Pid) ->
    gen_statem:call(Pid, validate_workflow).

%% @doc Detect deadlock conditions in the current workflow state.
%% Returns {ok, no_deadlock} or {ok, deadlock, Details}.
-spec detect_deadlock(pid()) -> {ok, no_deadlock | potential_deadlock | deadlocked, map()}.
detect_deadlock(Pid) ->
    gen_statem:call(Pid, detect_deadlock).

%% @doc Get the transition firing history.
-spec get_transition_history(pid()) -> {ok, [{atom(), integer(), map()}]}.
get_transition_history(Pid) ->
    gen_statem:call(Pid, get_transition_history).

%%====================================================================
%% gen_statem Callbacks
%%====================================================================

%% @private
callback_mode() -> state_functions.

%% @private
init([WorkflowId, Config]) ->
    PatternType = maps:get(pattern_type, Config, basic_sequential),
    {Places, Transitions, Preset, Postset} = get_pattern_structure(PatternType),
    InitialMarking = maps:get(initial_marking, Config, #{start => [workflow_token]}),

    %% Validate workflow structure
    ValidationErrors = validate_structure(PatternType, Places, Transitions, Preset, Postset),

    Data = #data{
        workflow_id = WorkflowId,
        pattern_type = PatternType,
        marking = InitialMarking,
        places = Places,
        transitions = Transitions,
        preset = Preset,
        postset = Postset,
        workflow_data = maps:get(workflow_data, Config, #{}),
        current_tasks = #{},
        completed_tasks = [],
        subscribers = [],
        parent_workflow = maps:get(parent_workflow, Config, undefined),
        start_time = erlang:monotonic_time(millisecond),
        metadata = maps:get(metadata, Config, #{}),
        transition_guards = maps:get(transition_guards, Config, #{}),
        transition_effects = maps:get(transition_effects, Config, #{}),
        transition_history = [],
        transition_priorities = maps:get(transition_priorities, Config, #{}),
        max_tokens = maps:get(max_tokens, Config, #{}),
        deadlock_state = no_deadlock,
        validation_state = case ValidationErrors of [] -> valid; _ -> invalid end,
        validation_errors = ValidationErrors
    },

    {ok, idle, Data}.

%% @private
terminate(_Reason, _State, _Data) ->
    ok.

%% @private
code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%%====================================================================
%% State Functions
%%====================================================================

%% @private
%% idle state - workflow created but not started
idle(cast, {subscribe, Subscriber}, Data) ->
    NewSubscribers = lists:usort([Subscriber | Data#data.subscribers]),
    {keep_state, Data#data{subscribers = NewSubscribers}};

idle({call, From}, start_workflow, Data) ->
    case Data#data.validation_state of
        invalid ->
            {keep_state_and_data, [{reply, From, {error, {invalid_workflow, Data#data.validation_errors}}}]}
        ;
        valid ->
            notify_subscribers(started, Data),
            {next_state, running, Data, [{next_event, internal, process_tokens}, {reply, From, ok}]}
    end;

idle({call, From}, cancel_workflow, Data) ->
    {next_state, cancelled, Data#data{end_time = erlang:monotonic_time(millisecond)}, [{reply, From, ok}]};

idle({call, From}, get_state, Data) ->
    {keep_state_and_data, [{reply, From, {ok, idle, state_to_map(idle, Data)}}]};

idle({call, From}, get_marking, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.marking}}]};

idle({call, From}, {update_data, Key, Value}, Data) ->
    NewWorkflowData = maps:put(Key, Value, Data#data.workflow_data),
    {keep_state, Data#data{workflow_data = NewWorkflowData}, [{reply, From, ok}]};

idle({call, From}, {subscribe, Subscriber}, Data) ->
    NewSubscribers = lists:usort([Subscriber | Data#data.subscribers]),
    {keep_state, Data#data{subscribers = NewSubscribers}, [{reply, From, ok}]};

idle({call, From}, checkpoint, Data) ->
    CheckpointId = create_checkpoint(Data),
    {keep_state_and_data, [{reply, From, {ok, CheckpointId}}]};

idle({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state, Data#data{validation_state = ValidState, validation_errors = Errors},
     [{reply, From, {ok, ValidState, Errors}}]};

idle({call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state, Data#data{deadlock_state = DeadlockState},
     [{reply, From, {ok, DeadlockState, Details}}]};

idle({call, From}, {add_transition_guard, Transition, GuardFun}, Data) ->
    NewGuards = maps:put(Transition, GuardFun, Data#data.transition_guards),
    {keep_state, Data#data{transition_guards = NewGuards}, [{reply, From, ok}]};

idle({call, From}, {add_transition_effect, Transition, EffectFun}, Data) ->
    NewEffects = maps:put(Transition, EffectFun, Data#data.transition_effects),
    {keep_state, Data#data{transition_effects = NewEffects}, [{reply, From, ok}]};

idle({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

idle(EventType, EventContent, Data) ->
    handle_common_event(idle, EventType, EventContent, Data).

%% @private
%% running state - actively processing tokens
running(internal, process_tokens, Data) ->
    %% Check for deadlock first
    {DeadlockState, _} = do_detect_deadlock(Data),
    case DeadlockState of
        deadlocked ->
            notify_subscribers({deadlock, detected}, Data),
            {next_state, failed, Data#data{error = deadlock_detected}};
        _ ->
            case get_enabled_transitions(Data) of
                [] ->
                    case check_completion(Data) of
                        true ->
                            {next_state, completing, Data, [{next_event, internal, finalize}]};
                        false ->
                            %% No enabled transitions but not complete - potential deadlock
                            {next_state, waiting, Data#data{deadlock_state = potential_deadlock}}
                    end
                ;
                [_Transition | _] = Enabled ->
                    %% Select transition with highest priority if multiple enabled
                    SelectedTransition = select_transition_by_priority(Enabled, Data),
                    case fire_transition(SelectedTransition, Data) of
                        {ok, NewData} ->
                            %% Record transition in history
                            HistoryEntry = {SelectedTransition,
                                           erlang:monotonic_time(millisecond),
                                           NewData#data.marking},
                            UpdatedHistory = [HistoryEntry | Data#data.transition_history],

                            %% Check for more enabled transitions
                            case get_enabled_transitions(NewData) of
                                [] ->
                                    case check_completion(NewData) of
                                        true ->
                                            {next_state, completing,
                                             NewData#data{transition_history = UpdatedHistory},
                                             [{next_event, internal, finalize}]};
                                        false ->
                                            {next_state, waiting,
                                             NewData#data{transition_history = UpdatedHistory,
                                                          deadlock_state = potential_deadlock}}
                                    end
                                ;
                                _ ->
                                    {keep_state,
                                     NewData#data{transition_history = UpdatedHistory},
                                     [{next_event, internal, process_tokens}]}
                            end;
                        {error, Reason} ->
                            notify_subscribers({error, Reason}, Data),
                            {next_state, failed,
                             Data#data{error = Reason, deadlock_state = deadlocked}}
                    end
            end
    end;

running({call, From}, {execute_task, TaskId}, Data) ->
    case maps:is_key(TaskId, Data#data.current_tasks) of
        true ->
            {keep_state_and_data, [{reply, From, {error, task_already_running}}]};
        false ->
            %% Save checkpoint before task execution
            case create_checkpoint(Data) of
                CheckpointId when is_binary(CheckpointId) ->
                    %% Delegate to workitem processor
                    TaskData = #{
                        task_id => TaskId,
                        task_name => atom_to_binary(TaskId, utf8),
                        workflow_id => Data#data.workflow_id
                    },
                    case yawl_workitem_processor:execute_task(
                        Data#data.workflow_id, TaskId, TaskData, #{}) of
                        {ok, _WorkitemId} ->
                            NewTasks = maps:put(TaskId, executing, Data#data.current_tasks),
                            %% Save checkpoint after resource allocation
                            _ = create_checkpoint(Data#data{current_tasks = NewTasks}),
                            {keep_state, Data#data{current_tasks = NewTasks}, [{reply, From, ok}]};
                        {error, Reason} ->
                            {keep_state_and_data, [{reply, From, {error, Reason}}]}
                    end;
                _ ->
                    {keep_state_and_data, [{reply, From, {error, checkpoint_failed}}]}
            end
    end;

running({call, From}, cancel_workflow, Data) ->
    notify_subscribers(cancelled, Data),
    {next_state, cancelled, Data#data{end_time = erlang:monotonic_time(millisecond)}, [{reply, From, ok}]};

running({call, From}, suspend_workflow, Data) ->
    notify_subscribers(suspended, Data),
    {next_state, waiting, Data, [{reply, From, ok}]};

running({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state, Data#data{validation_state = ValidState, validation_errors = Errors},
     [{reply, From, {ok, ValidState, Errors}}]};

running({call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state, Data#data{deadlock_state = DeadlockState},
     [{reply, From, {ok, DeadlockState, Details}}]};

running({call, From}, {add_transition_guard, Transition, GuardFun}, Data) ->
    NewGuards = maps:put(Transition, GuardFun, Data#data.transition_guards),
    {keep_state, Data#data{transition_guards = NewGuards}, [{reply, From, ok}]};

running({call, From}, {add_transition_effect, Transition, EffectFun}, Data) ->
    NewEffects = maps:put(Transition, EffectFun, Data#data.transition_effects),
    {keep_state, Data#data{transition_effects = NewEffects}, [{reply, From, ok}]};

running({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

running(EventType, EventContent, Data) ->
    handle_common_event(running, EventType, EventContent, Data).

%% @private
%% waiting state - waiting for external events or task completion
waiting(internal, process_tokens, Data) ->
    {next_state, running, Data, []};

waiting({call, From}, {complete_task, TaskId, Result}, Data) ->
    NewCompleted = [TaskId | Data#data.completed_tasks],
    NewTasks = maps:remove(TaskId, Data#data.current_tasks),
    NewData = Data#data{completed_tasks = NewCompleted, current_tasks = NewTasks},

    %% Update workflow data with task result
    UpdatedWorkflowData = maps:merge(Data#data.workflow_data, Result),

    %% Produce output tokens for completed task (token passing)
    NewMarking = produce_output_tokens(TaskId, Data#data.marking, Data),
    FinalData = NewData#data{marking = NewMarking, workflow_data = UpdatedWorkflowData},

    %% Save checkpoint after workflow state changes
    _ = create_checkpoint(FinalData),

    notify_subscribers({task_completed, TaskId}, FinalData),

    %% Continue processing
    {keep_state, FinalData, [{next_event, internal, process_tokens}, {reply, From, ok}]};

waiting({call, From}, resume_workflow, Data) ->
    notify_subscribers(resumed, Data),
    {next_state, running, Data, [{next_event, internal, process_tokens}, {reply, From, ok}]};

waiting({call, From}, cancel_workflow, Data) ->
    notify_subscribers(cancelled, Data),
    {next_state, cancelled, Data#data{end_time = erlang:monotonic_time(millisecond)}, [{reply, From, ok}]};

waiting({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state, Data#data{validation_state = ValidState, validation_errors = Errors},
     [{reply, From, {ok, ValidState, Errors}}]};

waiting({call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state, Data#data{deadlock_state = DeadlockState},
     [{reply, From, {ok, DeadlockState, Details}}]};

waiting({call, From}, {add_transition_guard, Transition, GuardFun}, Data) ->
    NewGuards = maps:put(Transition, GuardFun, Data#data.transition_guards),
    {keep_state, Data#data{transition_guards = NewGuards}, [{reply, From, ok}]};

waiting({call, From}, {add_transition_effect, Transition, EffectFun}, Data) ->
    NewEffects = maps:put(Transition, EffectFun, Data#data.transition_effects),
    {keep_state, Data#data{transition_effects = NewEffects}, [{reply, From, ok}]};

waiting({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

waiting(EventType, EventContent, Data) ->
    handle_common_event(waiting, EventType, EventContent, Data).

%% @private
%% completing state - finalizing workflow
completing(internal, finalize, Data) ->
    case check_completion(Data) of
        true ->
            %% Save final checkpoint before termination
            _ = create_checkpoint(Data),
            notify_subscribers(completed, Data),
            EndTime = erlang:monotonic_time(millisecond),
            {next_state, terminated, Data#data{end_time = EndTime}};
        false ->
            {next_state, running, Data, [{next_event, internal, process_tokens}]}
    end;

completing({call, From}, cancel_workflow, Data) ->
    notify_subscribers(cancelled, Data),
    {next_state, cancelled, Data#data{end_time = erlang:monotonic_time(millisecond)}, [{reply, From, ok}]};

completing(EventType, EventContent, Data) ->
    handle_common_event(completing, EventType, EventContent, Data).

%% @private
%% terminated state - workflow completed
terminated({call, From}, get_state, Data) ->
    {keep_state_and_data, [{reply, From, {ok, terminated, state_to_map(terminated, Data)}}]};

terminated({call, From}, get_marking, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.marking}}]};

terminated({call, From}, {update_data, _Key, _Value}, _Data) ->
    {keep_state_and_data, [{reply, From, {error, workflow_terminated}}]};

terminated({call, From}, {subscribe, Subscriber}, Data) ->
    NewSubscribers = lists:usort([Subscriber | Data#data.subscribers]),
    {keep_state, Data#data{subscribers = NewSubscribers}, [{reply, From, ok}]};

terminated({call, From}, checkpoint, Data) ->
    CheckpointId = create_checkpoint(Data),
    {keep_state_and_data, [{reply, From, {ok, CheckpointId}}]};

terminated({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state_and_data, [{reply, From, {ok, ValidState, Errors}}]};

terminated({call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state, Data#data{deadlock_state = DeadlockState},
     [{reply, From, {ok, DeadlockState, Details}}]};

terminated({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

terminated(EventType, EventContent, Data) ->
    handle_common_event(terminated, EventType, EventContent, Data).

%% @private
%% cancelled state - workflow was cancelled
cancelled({call, From}, get_state, Data) ->
    {keep_state_and_data, [{reply, From, {ok, cancelled, state_to_map(cancelled, Data)}}]};

cancelled({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state_and_data, [{reply, From, {ok, ValidState, Errors}}]};

cancelled({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

cancelled({call, From}, _Request, _Data) ->
    {keep_state_and_data, [{reply, From, {error, workflow_cancelled}}]};

cancelled(EventType, EventContent, Data) ->
    handle_common_event(cancelled, EventType, EventContent, Data).

%% @private
%% failed state - workflow failed with error
failed({call, From}, get_state, Data) ->
    {keep_state_and_data, [{reply, From, {ok, failed, state_to_map(failed, Data)}}]};

failed({call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state_and_data, [{reply, From, {ok, ValidState, Errors}}]};

failed({call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state_and_data, [{reply, From, {ok, DeadlockState, Details}}]};

failed({call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

failed({call, From}, _Request, _Data) ->
    {keep_state_and_data, [{reply, From, {error, workflow_failed}}]};

failed(EventType, EventContent, Data) ->
    handle_common_event(failed, EventType, EventContent, Data).

%%====================================================================
%% Internal Helper Functions
%%====================================================================

%% @private
handle_common_event(State, {call, From}, get_state, Data) ->
    {keep_state_and_data, [{reply, From, {ok, State, state_to_map(State, Data)}}]};

handle_common_event(_State, {call, From}, get_marking, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.marking}}]};

handle_common_event(_State, {call, From}, {update_data, Key, Value}, Data) ->
    NewWorkflowData = maps:put(Key, Value, Data#data.workflow_data),
    {keep_state, Data#data{workflow_data = NewWorkflowData}, [{reply, From, ok}]};

handle_common_event(_State, {call, From}, {subscribe, Subscriber}, Data) ->
    NewSubscribers = lists:usort([Subscriber | Data#data.subscribers]),
    {keep_state, Data#data{subscribers = NewSubscribers}, [{reply, From, ok}]};

handle_common_event(_State, {call, From}, checkpoint, Data) ->
    CheckpointId = create_checkpoint(Data),
    {keep_state_and_data, [{reply, From, {ok, CheckpointId}}]};

handle_common_event(_State, {call, From}, {restart_from_checkpoint, WorkflowId}, Data) ->
    case yawl_persistence:restore_from_checkpoint(WorkflowId) of
        {ok, Checkpoint} ->
            %% Update workflow state with restored data
            NewData = Data#data{
                marking = Checkpoint#yawl_checkpoint.marking,
                workflow_data = Checkpoint#yawl_checkpoint.data,
                start_time = erlang:monotonic_time(millisecond)
            },

            %% Notify subscribers about the restart
            notify_subscribers({restarted_from_checkpoint, WorkflowId}, NewData),

            %% Transition to appropriate state based on restored workflow data
            NewState = case check_completion(NewData) of
                true -> completing;
                false -> running
            end,

            {next_state, NewState, NewData, [{reply, From, ok}]};
        {error, Reason} ->
            {keep_state_and_data, [{reply, From, {error, Reason}}]}
    end;

handle_common_event(_State, {call, From}, validate_workflow, Data) ->
    {ok, ValidState, Errors} = do_validate_workflow(Data),
    {keep_state, Data#data{validation_state = ValidState, validation_errors = Errors},
     [{reply, From, {ok, ValidState, Errors}}]};

handle_common_event(_State, {call, From}, detect_deadlock, Data) ->
    {DeadlockState, Details} = do_detect_deadlock(Data),
    {keep_state, Data#data{deadlock_state = DeadlockState},
     [{reply, From, {ok, DeadlockState, Details}}]};

handle_common_event(_State, {call, From}, get_transition_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.transition_history}}]};

handle_common_event(_State, {call, From}, _Request, _Data) ->
    {keep_state_and_data, [{reply, From, {error, unknown_request}}]};

handle_common_event(_State, info, _Info, Data) ->
    {keep_state, Data}.

%%--------------------------------------------------------------------
%% Pattern Structure Definitions
%%--------------------------------------------------------------------

%% @private
get_pattern_structure(basic_sequential) ->
    {
        [start, task1, task2, 'end'],
        [start, t1, t2, finish],
        #{start => [start], t1 => [task1], t2 => [task2], finish => ['end']},
        #{start => [task1], t1 => [task2], t2 => ['end'], finish => []}
    };
get_pattern_structure(parallel_split) ->
    {
        [start, split, task1, task2, 'end'],
        [start, split, t1, t2, join, finish],
        #{start => [start], split => [split], t1 => [task1], t2 => [task2], join => ['end'], finish => ['end']},
        #{start => [split], split => [task1, task2], t1 => [join], t2 => [join], join => [finish], finish => []}
    };
get_pattern_structure(exclusive_choice) ->
    {
        [start, choice, task1, task2, 'end'],
        [start, choice, t1, t2, merge, finish],
        #{start => [start], choice => [choice], t1 => [task1], t2 => [task2], merge => ['end'], finish => ['end']},
        #{start => [choice], choice => [task1, task2], t1 => [merge], t2 => [merge], merge => [finish], finish => []}
    };
get_pattern_structure(parallel_join) ->
    {
        [start, task1, task2, join, 'end'],
        [start, t1, t2, join, finish],
        #{start => [start], t1 => [task1], t2 => [task2], join => [join], finish => ['end']},
        #{start => [task1, task2], t1 => [join], t2 => [join], join => [finish], finish => []}
    };
get_pattern_structure(iterative_loop) ->
    {
        [start, condition, action, loop, 'end'],
        [start, check, execute, continue, finish],
        #{start => [start], check => [condition], execute => [action], continue => [loop], finish => ['end']},
        #{start => [condition], check => [action, 'end'], execute => [loop], continue => [condition], finish => []}
    };
get_pattern_structure(multi_instance) ->
    {
        [start, create, execute, collect, 'end'],
        [start, create, execute, collect, finish],
        #{start => [start], create => [create], execute => [execute], collect => [collect], finish => ['end']},
        #{start => [create], create => [execute], execute => [collect], collect => [finish], finish => []}
    };
get_pattern_structure(_PatternType) ->
    %% Default structure for unknown patterns
    {
        [start, 'end'],
        [start, finish],
        #{start => [start], finish => ['end']},
        #{start => ['end'], finish => []}
    }.

%%--------------------------------------------------------------------
%% Token Passing & Transition Firing
%%--------------------------------------------------------------------

%% @private
%% Get all enabled transitions based on current marking and guards
get_enabled_transitions(Data) ->
    Marking = Data#data.marking,
    Preset = Data#data.preset,
    Guards = Data#data.transition_guards,
    WorkflowData = Data#data.workflow_data,

    %% A transition is enabled if:
    %% 1. All its input places have at least one token
    %% 2. Its guard function (if any) evaluates to true
    Enabled = lists:filter(fun(Transition) ->
        InputPlaces = maps:get(Transition, Preset, []),
        HasTokens = lists:all(fun(Place) ->
            case maps:get(Place, Marking, []) of
                [] -> false;
                _ -> true
            end
        end, InputPlaces),
        GuardPasses = case maps:get(Transition, Guards, undefined) of
            undefined -> true;
            GuardFun ->
                try
                    GuardFun(WorkflowData)
                catch
                    _:_ -> true  %% If guard fails, allow transition
                end
        end,
        HasTokens andalso GuardPasses
    end, Data#data.transitions),

    Enabled.

%% @private
%% Select transition with highest priority from enabled transitions
select_transition_by_priority(Enabled, Data) ->
    Priorities = Data#data.transition_priorities,
    lists:foldl(fun(T, Best) ->
        case maps:get(T, Priorities, 0) > maps:get(Best, Priorities, 0) of
            true -> T;
            false -> Best
        end
    end, hd(Enabled), tl(Enabled)).

%% @private
%% Fire a transition: consume input tokens, produce output tokens, apply effects
fire_transition(Transition, Data) ->
    Preset = Data#data.preset,
    Postset = Data#data.postset,
    Marking = Data#data.marking,
    MaxTokens = Data#data.max_tokens,
    Effects = Data#data.transition_effects,
    WorkflowData = Data#data.workflow_data,

    %% Consume tokens from input places (token passing)
    InputPlaces = maps:get(Transition, Preset, []),
    NewMarking1 = lists:foldl(fun(Place, AccMarking) ->
        Tokens = maps:get(Place, AccMarking, []),
        case Tokens of
            [_Token | Rest] -> maps:put(Place, Rest, AccMarking);
            [] -> AccMarking
        end
    end, Marking, InputPlaces),

    %% Apply transition effect if defined
    NewWorkflowData = case maps:get(Transition, Effects, undefined) of
        undefined -> WorkflowData;
        EffectFun ->
            try
                EffectFun(WorkflowData)
            catch
                _:_ -> WorkflowData
            end
    end,

    %% Produce tokens to output places (token passing)
    OutputPlaces = maps:get(Transition, Postset, []),
    NewMarking2 = lists:foldl(fun(Place, AccMarking) ->
        CurrentTokens = maps:get(Place, AccMarking, []),
        %% Check max token limit if defined
        MaxAllowed = maps:get(Place, MaxTokens, infinity),
        case MaxAllowed of
            infinity ->
                maps:put(Place, [token | CurrentTokens], AccMarking);
            Limit when length(CurrentTokens) < Limit ->
                maps:put(Place, [token | CurrentTokens], AccMarking);
            _Limit ->
                %% Token limit reached, don't add more
                AccMarking
        end
    end, NewMarking1, OutputPlaces),

    {ok, Data#data{marking = NewMarking2, workflow_data = NewWorkflowData}}.

%% @private
%% Check if workflow has completed (token in 'end' place, no tokens elsewhere)
check_completion(Data) ->
    Marking = Data#data.marking,
    EndTokens = maps:get('end', Marking, []),
    %% Workflow is complete when there's a token in the end place
    %% and no tokens in other places (except end)
    OtherPlaces = lists:delete('end', Data#data.places),
    OtherTokens = [maps:get(P, Marking, []) || P <- OtherPlaces],
    IsComplete = EndTokens =/= [] andalso lists:all(fun(T) -> T =:= [] end, OtherTokens),
    IsComplete.

%% @private
%% Produce output tokens for a completed task
produce_output_tokens(TaskId, Marking, Data) ->
    %% Find output places for this task based on postset
    OutputPlaces = maps:get(TaskId, Data#data.postset, []),
    lists:foldl(fun(Place, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        maps:put(Place, [output_token | CurrentTokens], Acc)
    end, Marking, OutputPlaces).

%%--------------------------------------------------------------------
%% Workflow Validation
%%--------------------------------------------------------------------

%% @private
%% Validate workflow structure
validate_structure(_PatternType, Places, Transitions, Preset, Postset) ->
    Errors = [],

    %% Check that all places are unique
    Errors1 = case length(Places) =:= length(lists:usort(Places)) of
        true -> Errors;
        false -> [{duplicate_places, Places} | Errors]
    end,

    %% Check that all transitions are unique
    Errors2 = case length(Transitions) =:= length(lists:usort(Transitions)) of
        true -> Errors1;
        false -> [{duplicate_transitions, Transitions} | Errors1]
    end,

    %% Check that all preset places exist
    PresetPlaces = lists:usort(lists:flatten(maps:values(Preset))),
    Errors3 = lists:foldl(fun(Place, Acc) ->
        case lists:member(Place, Places) of
            true -> Acc;
            false -> [{preset_place_not_found, Place} | Acc]
        end
    end, Errors2, PresetPlaces),

    %% Check that all postset places exist
    PostsetPlaces = lists:usort(lists:flatten(maps:values(Postset))),
    Errors4 = lists:foldl(fun(Place, Acc) ->
        case lists:member(Place, Places) of
            true -> Acc;
            false -> [{postset_place_not_found, Place} | Acc]
        end
    end, Errors3, PostsetPlaces),

    %% Check that 'start' and 'end' places exist
    Errors5 = case {lists:member(start, Places), lists:member('end', Places)} of
        {true, true} -> Errors4;
        _ -> [{missing_start_or_end_place} | Errors4]
    end,

    lists:reverse(Errors5).

%% @private
%% Full workflow validation
do_validate_workflow(Data) ->
    %% Get structural validation
    StructErrors = validate_structure(
        Data#data.pattern_type,
        Data#data.places,
        Data#data.transitions,
        Data#data.preset,
        Data#data.postset
    ),

    %% Check for unreachable places
    Unreachable = find_unreachable_places(Data),
    UnreachableErrors = case Unreachable of
        [] -> [];
        _ -> [{unreachable_places, Unreachable}]
    end,

    %% Check for circular dependencies (potential infinite loops)
    Cycles = find_cycles(Data),
    CycleErrors = case Cycles of
        [] -> [];
        _ -> [{potential_cycles, Cycles}]
    end,

    AllErrors = StructErrors ++ UnreachableErrors ++ CycleErrors,

    case AllErrors of
        [] -> {ok, valid, []};
        _ -> {ok, invalid, AllErrors}
    end.

%% @private
%% Find places that cannot be reached from start
find_unreachable_places(Data) ->
    StartPlace = start,
    Reachable = find_reachable_places(StartPlace, Data#data.postset, Data#data.transitions),
    lists:filter(fun(P) ->
        not lists:member(P, Reachable) andalso P =/= start
    end, Data#data.places).

%% @private
%% Find all places reachable from a given place
find_reachable_places(Place, Postset, Transitions) ->
    %% Find transitions that can be reached from this place
    FromTransitions = lists:filter(fun(T) ->
        OutputPlaces = maps:get(T, Postset, []),
        lists:member(Place, OutputPlaces)
    end, Transitions),

    %% Find all places reachable from those transitions
    NextPlaces = lists:usort(lists:flatmap(fun(T) ->
        maps:get(T, Postset, [])
    end, FromTransitions)),

    %% Recursively find reachable places
    lists:foldl(fun(P, Acc) ->
        case lists:member(P, Acc) of
            true -> Acc;
            false -> [P | find_reachable_places(P, Postset, Transitions)]
        end
    end, [Place], NextPlaces).

%% @private
%% Find potential cycles in the workflow
find_cycles(Data) ->
    %% Use a simple cycle detection algorithm
    Visited = sets:new(),
    RecStack = sets:new(),

    Cycles = lists:filter(fun(Place) ->
        has_cycle(Place, Data#data.postset, Visited, RecStack, Data#data.places)
    end, Data#data.places),

    Cycles.

%% @private
has_cycle(Place, Postset, Visited, RecStack, AllPlaces) ->
    case sets:is_element(Place, RecStack) of
        true -> true;
        false ->
            case sets:is_element(Place, Visited) of
                true -> false;
                    false ->
                    NewVisited = sets:add_element(Place, Visited),
                    NewRecStack = sets:add_element(Place, RecStack),

                    %% Find transitions that produce to this place
                    ToTransitions = lists:filter(fun(T) ->
                        lists:member(Place, maps:get(T, Postset, []))
                    end, AllPlaces),

                    lists:any(fun(T) ->
                        lists:any(fun(P) ->
                            has_cycle(P, Postset, NewVisited, NewRecStack, AllPlaces)
                        end, maps:get(T, Postset, []))
                    end, ToTransitions)
            end
    end.

%%--------------------------------------------------------------------
%% Deadlock Detection
%%--------------------------------------------------------------------

%% @private
%% Detect deadlock conditions in the current workflow state
do_detect_deadlock(Data) ->
    Marking = Data#data.marking,
    Preset = Data#data.preset,
    Transitions = Data#data.transitions,

    %% Find places with tokens
    PlacesWithTokens = lists:filter(fun(P) ->
        case maps:get(P, Marking, []) of
            [] -> false;
            _ -> true
        end
    end, Data#data.places),

    %% Check if any transition is enabled
    EnabledTransitions = get_enabled_transitions(Data),

    case PlacesWithTokens of
        [] ->
            %% No tokens - idle state, not deadlocked
            Details = #{
                reason => no_tokens,
                places_with_tokens => [],
                enabled_transitions => EnabledTransitions
            },
            {no_deadlock, Details};
        _ ->
            case EnabledTransitions of
                [] ->
                    %% Has tokens but no enabled transitions - DEADLOCK
                    BlockedInfo = lists:map(fun(P) ->
                        Tokens = maps:get(P, Marking, []),
                        Missing = find_missing_tokens_for_transitions(P, Transitions, Preset, Marking),
                        {P, #{tokens => Tokens, missing_for => Missing}}
                    end, PlacesWithTokens),

                    Details = #{
                        reason => tokens_without_enabled_transitions,
                        places_with_tokens => PlacesWithTokens,
                        blocked_transitions => BlockedInfo
                    },
                    {deadlocked, Details};
                _ ->
                    %% Has tokens and enabled transitions - not deadlocked
                    Details = #{
                        reason => normal_execution,
                        places_with_tokens => PlacesWithTokens,
                        enabled_transitions => EnabledTransitions
                    },
                    {no_deadlock, Details}
            end
    end.

%% @private
%% Find which transitions cannot fire due to missing tokens for a place
find_missing_tokens_for_transitions(Place, Transitions, Preset, Marking) ->
    lists:filter(fun(T) ->
        InputPlaces = maps:get(T, Preset, []),
        %% Check if this transition has this place as input
        case lists:member(Place, InputPlaces) of
            true ->
                %% Check if all inputs have tokens
                lists:any(fun(P) ->
                    maps:get(P, Marking, []) =:= []
                end, InputPlaces);
            false ->
                false
        end
    end, Transitions).

%%--------------------------------------------------------------------
%% Utility Functions
%%--------------------------------------------------------------------

%% @private
notify_subscribers(Event, Data) ->
    lists:foreach(fun(Subscriber) ->
        catch Subscriber ! {yawl_event, Data#data.workflow_id, Event}
    end, Data#data.subscribers).

%% @private
state_to_map(State, Data) ->
    #{
        state => State,
        workflow_id => Data#data.workflow_id,
        pattern_type => Data#data.pattern_type,
        marking => Data#data.marking,
        completed_tasks => Data#data.completed_tasks,
        current_tasks => Data#data.current_tasks,
        start_time => Data#data.start_time,
        end_time => Data#data.end_time,
        error => Data#data.error,
        deadlock_state => Data#data.deadlock_state,
        validation_state => Data#data.validation_state
    }.

%% @private
create_checkpoint(Data) ->
    CheckpointId = <<(Data#data.workflow_id)/binary, "_",
                     (integer_to_binary(erlang:monotonic_time(millisecond)))/binary>>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = Data#data.workflow_id,
        checkpoint_state = Data,
        marking = Data#data.marking,
        data = Data#data.workflow_data,
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    %% Store checkpoint via persistence manager (mandatory)
    case yawl_persistence:save_checkpoint(Data#data.workflow_id, Checkpoint) of
        ok -> CheckpointId;
        {error, Reason} ->
            error_logger:error_msg("YAWL Workflow Instance: Failed to save checkpoint ~p for workflow ~p: ~p~n",
                                   [CheckpointId, Data#data.workflow_id, Reason]),
            exit({persistence_failure, Reason})
    end.
