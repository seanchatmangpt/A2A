%%%-------------------------------------------------------------------
%%% @doc YAWL Workflow Orchestrator
%%%
%%% This module is the central orchestrator for YAWL workflow execution.
%%% It manages workflow instances, delegates to workflow instance processes,
%%% and coordinates with the persistence layer.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_orchestrator).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
           handle_info/2, terminate/2, code_change/3]).

%% API exports
-export([create_workflow/2, execute_workflow/1, validate_pattern/2,
           get_status/1, list_patterns/0, list_workflows/0,
           cancel_workflow/1, cleanup_workflow/1, get_pattern_info/1,
           get_workflow_result/1, subscribe_to_workflow/2,
           unsubscribe_from_workflow/2, pause_workflow/1, resume_workflow/1,
           get_workflow_instance/1, complete_workitem/3]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% State record
-record(state, {
    workflows = #{},
    workflow_instances = #{},  %% workflow_id => {pid, monitor_ref}
    pattern_cache = #{},
    subscribers = #{},
    config = #{},
    statistics = #{total_workflows => 0, completed_workflows => 0, failed_workflows => 0}
}).

%% API Functions
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

create_workflow(PatternType, Config) ->
    gen_server:call(?MODULE, {create_workflow, PatternType, Config}).

execute_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {execute_workflow, WorkflowId}, infinity).

validate_pattern(PatternType, Config) ->
    gen_server:call(?MODULE, {validate_pattern, PatternType, Config}).

get_status(WorkflowId) ->
    gen_server:call(?MODULE, {get_status, WorkflowId}).

list_patterns() ->
    gen_server:call(?MODULE, list_patterns).

list_workflows() ->
    gen_server:call(?MODULE, list_workflows).

cancel_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {cancel_workflow, WorkflowId}).

cleanup_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {cleanup_workflow, WorkflowId}).

get_pattern_info(PatternType) ->
    gen_server:call(?MODULE, {get_pattern_info, PatternType}).

get_workflow_result(WorkflowId) ->
    gen_server:call(?MODULE, {get_workflow_result, WorkflowId}).

subscribe_to_workflow(WorkflowId, SubscriberPid) ->
    gen_server:call(?MODULE, {subscribe, WorkflowId, SubscriberPid}).

unsubscribe_from_workflow(WorkflowId, SubscriberPid) ->
    gen_server:call(?MODULE, {unsubscribe, WorkflowId, SubscriberPid}).

pause_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {pause_workflow, WorkflowId}, infinity).

resume_workflow(WorkflowId) ->
    gen_server:call(?MODULE, {resume_workflow, WorkflowId}, infinity).

get_workflow_instance(WorkflowId) ->
    gen_server:call(?MODULE, {get_workflow_instance, WorkflowId}).

complete_workitem(WorkflowId, TaskId, Result) ->
    gen_server:call(?MODULE, {complete_workitem, WorkflowId, TaskId, Result}, infinity).

%% gen_server callbacks
init([]) ->
    State = #state{
        workflows = #{},
        workflow_instances = #{},
        pattern_cache = initialize_pattern_cache(),
        subscribers = #{},
        config = get_default_config(),
        statistics = #{total_workflows => 0, completed_workflows => 0, failed_workflows => 0}
    },
    {ok, State}.

handle_call({create_workflow, PatternType, Config}, _From, State) ->
    {Reply, NewState} = do_create_workflow(PatternType, Config, State),
    {reply, Reply, NewState};

handle_call({execute_workflow, WorkflowId}, _From, State) ->
    {Reply, NewState} = do_execute_workflow(WorkflowId, State),
    {reply, Reply, NewState};

handle_call({validate_pattern, PatternType, Config}, _From, State) ->
    Reply = do_validate_pattern(PatternType, Config, State),
    {reply, Reply, State};

handle_call({get_status, WorkflowId}, _From, State) ->
    Reply = do_get_status(WorkflowId, State),
    {reply, Reply, State};

handle_call(list_patterns, _From, State) ->
    Patterns = maps:keys(State#state.pattern_cache),
    {reply, Patterns, State};

handle_call(list_workflows, _From, State) ->
    WorkflowIds = maps:keys(State#state.workflows),
    {reply, {ok, WorkflowIds}, State};

handle_call({cancel_workflow, WorkflowId}, _From, State) ->
    {Reply, NewState} = do_cancel_workflow(WorkflowId, State),
    {reply, Reply, NewState};

handle_call({cleanup_workflow, WorkflowId}, _From, State) ->
    {Reply, NewState} = do_cleanup_workflow(WorkflowId, State),
    {reply, Reply, NewState};

handle_call({get_pattern_info, PatternType}, _From, State) ->
    Reply = do_get_pattern_info(PatternType, State),
    {reply, Reply, State};

handle_call({get_workflow_result, WorkflowId}, _From, State) ->
    Reply = do_get_workflow_result(WorkflowId, State),
    {reply, Reply, State};

handle_call({subscribe, WorkflowId, SubscriberPid}, _From, State) ->
    {Reply, NewState} = do_subscribe(WorkflowId, SubscriberPid, State),
    {reply, Reply, NewState};

handle_call({unsubscribe, WorkflowId, SubscriberPid}, _From, State) ->
    {Reply, NewState} = do_unsubscribe(WorkflowId, SubscriberPid, State),
    {reply, Reply, NewState};

handle_call({pause_workflow, WorkflowId}, _From, State) ->
    {Reply, NewState} = do_pause_workflow(WorkflowId, State),
    {reply, Reply, NewState};

handle_call({resume_workflow, WorkflowId}, _From, State) ->
    {Reply, NewState} = do_resume_workflow(WorkflowId, State),
    {reply, Reply, NewState};

handle_call({get_workflow_instance, WorkflowId}, _From, State) ->
    Reply = do_get_workflow_instance(WorkflowId, State),
    {reply, Reply, State};

handle_call({complete_workitem, WorkflowId, TaskId, Result}, _From, State) ->
    Reply = do_complete_workitem(WorkflowId, TaskId, Result, State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', MonitorRef, process, _Pid, _Info}, State) ->
    %% Find the workflow with this monitor ref
    WorkflowId = lists:foldl(fun({Wid, {_InstPid, Ref}}, Acc) ->
        case Ref of
            MonitorRef -> Wid;
            _ -> Acc
        end
    end, undefined, maps:to_list(State#state.workflow_instances)),

    case WorkflowId of
        undefined ->
            {noreply, State};
        _ ->
            NewState = handle_instance_down(WorkflowId, State),
            {noreply, NewState}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal Functions
initialize_pattern_cache() ->
    lists:foldl(fun(Pattern, Acc) ->
        Acc#{Pattern => get_pattern_definition(Pattern)}
    end, #{}, ?YAWL_PATTERNS).

get_pattern_definition(basic_sequential) ->
    #{name => <<"Basic Sequential">>, complexity => low,
      places => [start, task1, task2, 'end'],
      transitions => [start, t1, t2, 'end'],
      required_params => [], optional_params => []};
get_pattern_definition(PatternType) ->
    #{name => atom_to_binary(PatternType, utf8), complexity => medium,
      places => [start, 'end'], transitions => [start, 'end'],
      required_params => [], optional_params => []}.

get_default_config() ->
    #{max_concurrent_workflows => 100, default_timeout => ?DEFAULT_TIMEOUT,
      enable_metrics => true, enable_logging => true}.

do_create_workflow(PatternType, Config, State) ->
    case maps:is_key(PatternType, State#state.pattern_cache) of
        false -> {{error, {unknown_pattern, PatternType}}, State};
        true ->
            WorkflowId = generate_workflow_id(),
            Timeout = maps:get(timeout, Config, ?DEFAULT_TIMEOUT),
            WorkflowConfig = #yawl_workflow_config{
                pattern_type = PatternType,
                parameters = Config,
                timeout = Timeout
            },
            Workflow = #yawl_workflow{
                workflow_id = WorkflowId,
                pattern_type = PatternType,
                status = pending,
                config = WorkflowConfig,
                marking = #{start => [workflow_token]},
                start_time = erlang:monotonic_time(millisecond),
                metadata = #{created_at => erlang:system_time(millisecond)}
            },
            NewWorkflows = maps:put(WorkflowId, Workflow, State#state.workflows),
            NewState = State#state{workflows = NewWorkflows},
            {{ok, WorkflowId}, NewState}
    end.

do_execute_workflow(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined -> {{error, workflow_not_found}, State};
        Workflow ->
            %% Start workflow instance if not already running
            case maps:get(WorkflowId, State#state.workflow_instances, undefined) of
                undefined ->
                    case create_and_start_instance(WorkflowId, Workflow, State) of
                        {ok, InstancePid, NewState} ->
                            %% Update workflow status to running
                            NewWorkflow = Workflow#yawl_workflow{status = running},
                            NewWorkflows = maps:put(WorkflowId, NewWorkflow, State#state.workflows),
                            UpdatedState = NewState#state{workflows = NewWorkflows},
                            {{ok, #{status => running, instance => InstancePid}}, UpdatedState};
                        {error, Reason} ->
                            {{error, Reason}, State}
                    end;
                {InstancePid, _Ref} ->
                    %% Instance already running
                    {ok, #{status => running, instance => InstancePid}}, State
            end
    end.

do_validate_pattern(PatternType, Config, _State) ->
    case lists:member(PatternType, ?YAWL_PATTERNS) of
        false -> {ok, false};
        true -> {ok, maps:size(Config) > 0}
    end.

do_get_status(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined -> {error, workflow_not_found};
        Workflow -> {ok, Workflow#yawl_workflow.status}
    end.

do_cancel_workflow(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined -> {error, workflow_not_found};
        Workflow ->
            CancelledWorkflow = Workflow#yawl_workflow{status = cancelled,
                end_time = erlang:monotonic_time(millisecond)},
            NewWorkflows = maps:put(WorkflowId, CancelledWorkflow, State#state.workflows),
            {ok, State#state{workflows = NewWorkflows}}
    end.

do_cleanup_workflow(WorkflowId, State) ->
    case maps:is_key(WorkflowId, State#state.workflows) of
        false -> {error, workflow_not_found};
        true ->
            NewWorkflows = maps:remove(WorkflowId, State#state.workflows),
            NewSubscribers = maps:remove(WorkflowId, State#state.subscribers),
            {ok, State#state{workflows = NewWorkflows, subscribers = NewSubscribers}}
    end.

do_get_pattern_info(PatternType, State) ->
    case maps:get(PatternType, State#state.pattern_cache, undefined) of
        undefined -> {error, pattern_not_found};
        Info -> {ok, Info}
    end.

do_get_workflow_result(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined -> {error, workflow_not_found};
        Workflow ->
            case Workflow#yawl_workflow.status of
                completed -> {ok, Workflow#yawl_workflow.result};
                _ -> {error, workflow_not_completed}
            end
    end.

do_subscribe(WorkflowId, SubscriberPid, State) ->
    case maps:is_key(WorkflowId, State#state.workflows) of
        false -> {error, workflow_not_found};
        true ->
            CurrentSubscribers = maps:get(WorkflowId, State#state.subscribers, []),
            case lists:member(SubscriberPid, CurrentSubscribers) of
                true -> {ok, State};
                false ->
                    NewSubscribers = maps:put(WorkflowId, [SubscriberPid | CurrentSubscribers],
                        State#state.subscribers),
                    {ok, State#state{subscribers = NewSubscribers}}
            end
    end.

do_unsubscribe(WorkflowId, SubscriberPid, State) ->
    case maps:get(WorkflowId, State#state.subscribers, undefined) of
        undefined -> {error, workflow_not_found};
        Subscribers ->
            NewSubscribersList = lists:delete(SubscriberPid, Subscribers),
            NewSubscribers = case NewSubscribersList of
                [] -> maps:remove(WorkflowId, State#state.subscribers);
                _ -> maps:put(WorkflowId, NewSubscribersList, State#state.subscribers)
            end,
            {ok, State#state{subscribers = NewSubscribers}}
    end.

do_pause_workflow(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflow_instances, undefined) of
        undefined ->
            {error, workflow_instance_not_found};
        {InstancePid, _Ref} ->
            case yawl_workflow_instance:suspend_workflow(InstancePid) of
                ok ->
                    %% Update workflow status in persistence
                    case yawl_persistence:load_workflow(WorkflowId) of
                        {ok, Workflow} ->
                            UpdatedWorkflow = Workflow#yawl_workflow_persist{
                                status = waiting,
                                updated_at = erlang:monotonic_time(millisecond)
                            },
                            yawl_persistence:save_workflow(UpdatedWorkflow);
                        {error, _} ->
                            ok
                    end,
                    {ok, State};
                {error, Reason} ->
                    {{error, Reason}, State}
            end
    end.

do_resume_workflow(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflow_instances, undefined) of
        undefined ->
            {error, workflow_instance_not_found};
        {InstancePid, _Ref} ->
            case yawl_workflow_instance:resume_workflow(InstancePid) of
                ok ->
                    %% Update workflow status in persistence
                    case yawl_persistence:load_workflow(WorkflowId) of
                        {ok, Workflow} ->
                            UpdatedWorkflow = Workflow#yawl_workflow_persist{
                                status = running,
                                updated_at = erlang:monotonic_time(millisecond)
                            },
                            yawl_persistence:save_workflow(UpdatedWorkflow);
                        {error, _} ->
                            ok
                    end,
                    {ok, State};
                {error, Reason} ->
                    {{error, Reason}, State}
            end
    end.

do_get_workflow_instance(WorkflowId, State) ->
    case maps:get(WorkflowId, State#state.workflow_instances, undefined) of
        undefined -> {error, workflow_instance_not_found};
        {InstancePid, _Ref} -> {ok, InstancePid}
    end.

do_complete_workitem(WorkflowId, TaskId, Result, State) ->
    case maps:get(WorkflowId, State#state.workflow_instances, undefined) of
        undefined ->
            {error, workflow_instance_not_found};
        {InstancePid, _Ref} ->
            case yawl_workflow_instance:complete_task(InstancePid, TaskId, Result) of
                ok ->
                    %% Update workitem status in persistence
                    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
                    CompletedWorkitem = lists:filter(fun(W) ->
                        W#yawl_workitem_persist.task_id =:= TaskId
                    end, Workitems),
                    lists:foreach(fun(W) ->
                        yawl_persistence:update_workitem_status(
                            W#yawl_workitem_persist.workitem_id, completed)
                    end, CompletedWorkitem),
                    ok;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

generate_workflow_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    <<UniqueId:64>>.

%%====================================================================
%% Workflow Instance Management
%%====================================================================

%% @private
create_and_start_instance(WorkflowId, Workflow, State) ->
    Config = #{
        workflow_id => WorkflowId,
        pattern_type => Workflow#yawl_workflow.pattern_type,
        workflow_data => maps:get(data, Workflow#yawl_workflow.metadata, #{}),
        metadata => Workflow#yawl_workflow.metadata
    },

    case yawl_workflow_instance_sup:start_child(WorkflowId, Config) of
        {ok, InstancePid} ->
            %% Monitor the instance
            MonitorRef = erlang:monitor(process, InstancePid),
            NewInstances = maps:put(WorkflowId, {InstancePid, MonitorRef}, State#state.workflow_instances),

            %% Persist the workflow (mandatory)
            PersistWorkflow = #yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = WorkflowId,
                pattern_type = Workflow#yawl_workflow.pattern_type,
                status = running,
                marking = Workflow#yawl_workflow.marking,
                current_place = Workflow#yawl_workflow.current_place,
                data = maps:get(data, Workflow#yawl_workflow.metadata, #{}),
                created_at = Workflow#yawl_workflow.start_time,
                updated_at = erlang:monotonic_time(millisecond)
            },
            case yawl_persistence:save_workflow(PersistWorkflow) of
                ok -> ok;
                {error, Reason} ->
                    error_logger:critical_msg("YAWL Orchestrator: Failed to persist workflow ~p: ~p~n",
                                           [WorkflowId, Reason]),
                    {error, persistence_failure}
            end,

            {ok, InstancePid, State#state{workflow_instances = NewInstances}};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
handle_instance_down(WorkflowId, State) ->
    %% Remove the instance reference
    NewInstances = maps:remove(WorkflowId, State#state.workflow_instances),

    %% Update workflow status based on instance exit reason
    NewWorkflows = case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined -> State#state.workflows;
        Workflow ->
            %% In a real implementation, we'd check the exit reason
            CompletedWorkflow = Workflow#yawl_workflow{status = completed},
            maps:put(WorkflowId, CompletedWorkflow, State#state.workflows)
    end,

    %% Update statistics
    NewStats = maps:put(completed_workflows,
                        maps:get(completed_workflows, State#state.statistics, 0) + 1,
                        State#state.statistics),

    State#state{workflow_instances = NewInstances, workflows = NewWorkflows, statistics = NewStats}.
