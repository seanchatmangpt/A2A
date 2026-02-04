%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Human Task Service
%%%
%%% This module handles human task allocation and worklist management.
%%% It provides:
%%%
%%% - Task allocation to users/groups
%%% - Worklist management
%%% - Task claiming and completion
%%% - Task routing and escalation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_human_task).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Task allocation
-export([
    allocate_task/2,
    allocate_task_to_user/3,
    allocate_task_to_group/3,
    claim_task/2,
    release_task/2,
    complete_task/3,
    notify_allocation/2
]).

%% API exports - Worklist management
-export([
    get_user_worklist/1,
    get_group_worklist/1,
    get_task/2,
    list_queues/0,
    create_queue/2
]).

%% API exports - Task lifecycle
-export([
    start_task/2,
    suspend_task/2,
    resume_task/2,
    delegate_task/3,
    escalate_task/3
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    worklists :: #{binary() => [binary()]},  %% user_id => [task_ids]
    group_members :: #{binary() => [binary()]},  %% group_id => [user_ids]
    user_groups :: #{binary() => [binary()]},  %% user_id => [group_ids]
    task_queues :: #{binary() => queue:queue()},  %% queue_name => task_queue
    allocations :: #{binary() => #yawl_task_queue{}},
    task_data :: #{binary() => map()}
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the human task service.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Allocate a task (automatically finds suitable user).
-spec allocate_task(#yawl_workitem_persist{}, map()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
allocate_task(Workitem, Options) ->
    gen_server:call(?MODULE, {allocate_task, Workitem, Options}).

%% @doc Allocate a task to a specific user.
-spec allocate_task_to_user(binary(), #yawl_workitem_persist{}, map()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
allocate_task_to_user(UserId, Workitem, Options) ->
    gen_server:call(?MODULE, {allocate_task_to_user, UserId, Workitem, Options}).

%% @doc Allocate a task to a group.
-spec allocate_task_to_group(binary(), #yawl_workitem_persist{}, map()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
allocate_task_to_group(GroupId, Workitem, Options) ->
    gen_server:call(?MODULE, {allocate_task_to_group, GroupId, Workitem, Options}).

%% @doc Claim a task from a group queue.
-spec claim_task(binary(), binary()) -> {ok, #yawl_task_queue{}} | {error, term()}.
claim_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {claim_task, UserId, TaskId}).

%% @doc Release a claimed task.
-spec release_task(binary(), binary()) -> ok | {error, term()}.
release_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {release_task, UserId, TaskId}).

%% @doc Complete a task with result.
-spec complete_task(binary(), binary(), map()) -> ok | {error, term()}.
complete_task(UserId, TaskId, Result) ->
    gen_server:call(?MODULE, {complete_task, UserId, TaskId, Result}).

%% @doc Get user's worklist.
-spec get_user_worklist(binary()) -> {ok, [map()]}.
get_user_worklist(UserId) ->
    gen_server:call(?MODULE, {get_user_worklist, UserId}).

%% @doc Get group's worklist.
-spec get_group_worklist(binary()) -> {ok, [map()]}.
get_group_worklist(GroupId) ->
    gen_server:call(?MODULE, {get_group_worklist, GroupId}).

%% @doc Get a specific task.
-spec get_task(binary(), binary()) -> {ok, map()} | {error, term()}.
get_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {get_task, UserId, TaskId}).

%% @doc List all task queues.
-spec list_queues() -> {ok, [binary()]}.
list_queues() ->
    gen_server:call(?MODULE, list_queues).

%% @doc Create a new task queue.
-spec create_queue(binary(), map()) -> ok | {error, term()}.
create_queue(QueueName, Options) ->
    gen_server:call(?MODULE, {create_queue, QueueName, Options}).

%% @doc Start a task (mark as in progress).
-spec start_task(binary(), binary()) -> ok | {error, term()}.
start_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {start_task, UserId, TaskId}).

%% @doc Suspend a task.
-spec suspend_task(binary(), binary()) -> ok | {error, term()}.
suspend_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {suspend_task, UserId, TaskId}).

%% @doc Resume a suspended task.
-spec resume_task(binary(), binary()) -> ok | {error, term()}.
resume_task(UserId, TaskId) ->
    gen_server:call(?MODULE, {resume_task, UserId, TaskId}).

%% @doc Delegate a task to another user.
-spec delegate_task(binary(), binary(), binary()) -> ok | {error, term()}.
delegate_task(FromUserId, TaskId, ToUserId) ->
    gen_server:call(?MODULE, {delegate_task, FromUserId, TaskId, ToUserId}).

%% @doc Escalate a task to a group.
-spec escalate_task(binary(), binary(), binary()) -> ok | {error, term()}.
escalate_task(UserId, TaskId, GroupId) ->
    gen_server:call(?MODULE, {escalate_task, UserId, TaskId, GroupId}).

%% @doc Notify human task service of resource allocation.
-spec notify_allocation(#yawl_workitem_persist{}, binary()) -> ok | {error, term()}.
notify_allocation(Workitem, ResourceId) ->
    gen_server:call(?MODULE, {notify_allocation, Workitem, ResourceId}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        worklists = #{},
        group_members = #{},
        user_groups = #{},
        task_queues = #{
            <<"default">> => queue:new()
        },
        allocations = #{},
        task_data = #{}
    },
    {ok, State}.

%% @private
handle_call({allocate_task, Workitem, Options}, _From, State) ->
    %% Find suitable user based on capabilities
    RequiredSkills = maps:get(required_skills, Options, []),
    Priority = maps:get(priority, Options, normal),

    case find_suitable_user(RequiredSkills, State) of
        {ok, UserId} ->
            TaskQueueId = generate_task_queue_id(),
            TaskQueue = #yawl_task_queue{
                queue_id = TaskQueueId,
                task_id = Workitem#yawl_workitem_persist.workitem_id,
                queue_name = maps_get_safe(queue_name, Options, <<"default">>),
                assigned_user = UserId,
                priority = Priority,
                due_date = maps_get_safe(due_date, Options, undefined),
                created_at = erlang:monotonic_time(millisecond),
                claimed_at = erlang:monotonic_time(millisecond)
            },

            NewAllocations = maps:put(TaskQueueId, TaskQueue, State#state.allocations),
            NewWorklists = update_worklist(UserId, TaskQueueId, State#state.worklists),

            UpdatedWorkitem = Workitem#yawl_workitem_persist{
                status = allocated,
                allocated_to = {self(), UserId}
            },

            NewState = State#state{
                allocations = NewAllocations,
                worklists = NewWorklists
            },
            {reply, {ok, UpdatedWorkitem}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({allocate_task_to_user, UserId, Workitem, Options}, _From, State) ->
    TaskQueueId = generate_task_queue_id(),
    Priority = maps_get_safe(priority, Options, normal),

    TaskQueue = #yawl_task_queue{
        queue_id = TaskQueueId,
        task_id = Workitem#yawl_workitem_persist.workitem_id,
        queue_name = maps_get_safe(queue_name, Options, <<"default">>),
        assigned_user = UserId,
        priority = Priority,
        due_date = maps_get_safe(due_date, Options, undefined),
        created_at = erlang:monotonic_time(millisecond),
        claimed_at = erlang:monotonic_time(millisecond)
    },

    NewAllocations = maps:put(TaskQueueId, TaskQueue, State#state.allocations),
    NewWorklists = update_worklist(UserId, TaskQueueId, State#state.worklists),

    UpdatedWorkitem = Workitem#yawl_workitem_persist{
        status = allocated,
        allocated_to = {self(), UserId}
    },

    NewState = State#state{
        allocations = NewAllocations,
        worklists = NewWorklists
    },
    {reply, {ok, UpdatedWorkitem}, NewState};

handle_call({allocate_task_to_group, GroupId, Workitem, Options}, _From, State) ->
    TaskQueueId = generate_task_queue_id(),
    Priority = maps_get_safe(priority, Options, normal),

    TaskQueue = #yawl_task_queue{
        queue_id = TaskQueueId,
        task_id = Workitem#yawl_workitem_persist.workitem_id,
        queue_name = maps_get_safe(queue_name, Options, <<"default">>),
        assigned_group = GroupId,
        priority = Priority,
        due_date = maps_get_safe(due_date, Options, undefined),
        created_at = erlang:monotonic_time(millisecond)
    },

    NewAllocations = maps:put(TaskQueueId, TaskQueue, State#state.allocations),

    %% Add to queue
    QueueName = TaskQueue#yawl_task_queue.queue_name,
    TaskQueue0 = maps_get_safe(QueueName, State#state.task_queues, queue:new()),
    NewTaskQueues = maps:put(QueueName, queue:in(TaskQueueId, TaskQueue0), State#state.task_queues),

    UpdatedWorkitem = Workitem#yawl_workitem_persist{
        status = allocated
    },

    NewState = State#state{
        allocations = NewAllocations,
        task_queues = NewTaskQueues
    },
    {reply, {ok, UpdatedWorkitem}, NewState};

handle_call({claim_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_group = GroupId} = Allocation} when GroupId =/= undefined ->
            %% Task is assigned to a group, claim it
            ClaimedAllocation = Allocation#yawl_task_queue{
                assigned_user = UserId,
                claimed_at = erlang:monotonic_time(millisecond)
            },
            NewAllocations = maps:put(AllocationId, ClaimedAllocation, State#state.allocations),
            NewWorklists = update_worklist(UserId, AllocationId, State#state.worklists),
            NewState = State#state{allocations = NewAllocations, worklists = NewWorklists},
            {reply, {ok, ClaimedAllocation}, NewState};
        {ok, AllocationId, #yawl_task_queue{assigned_user = UserId} = Allocation} ->
            %% Already claimed by this user
            {reply, {ok, Allocation}, State};
        {ok, _AllocationId, #yawl_task_queue{assigned_user = OtherUserId}} when OtherUserId =/= undefined ->
            %% Already claimed by another user
            {reply, {error, already_claimed}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({release_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_user = UserId}} ->
            %% Remove from worklist
            NewWorklists = remove_from_worklist(UserId, AllocationId, State#state.worklists),

            %% Update allocation to unclaimed
            Allocation = maps:get(AllocationId, State#state.allocations),
            ReleasedAllocation = Allocation#yawl_task_queue{
                assigned_user = undefined,
                claimed_at = undefined
            },
            NewAllocations = maps:put(AllocationId, ReleasedAllocation, State#state.allocations),
            NewState = State#state{worklists = NewWorklists, allocations = NewAllocations},
            {reply, ok, NewState};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({complete_task, UserId, TaskId, Result}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_user = UserId}} ->
            %% Remove from worklist
            NewWorklists = remove_from_worklist(UserId, AllocationId, State#state.worklists),

            %% Remove from allocations
            NewAllocations = maps:remove(AllocationId, State#state.allocations),

            %% Store result
            NewTaskData = maps:put(TaskId, Result, State#state.task_data),

            %% Update workitem status via persistence (mandatory)
            case yawl_persistence:update_workitem_status(TaskId, completed) of
                ok -> ok;
                {error, Reason} ->
                    error_logger:error_msg("YAWL Human Task: Failed to update workitem ~p status: ~p~n",
                                         [TaskId, Reason])
            end,

            NewState = State#state{worklists = NewWorklists, allocations = NewAllocations, task_data = NewTaskData},
            {reply, ok, NewState};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({get_user_worklist, UserId}, _From, State) ->
    TaskIds = maps_get_safe(UserId, State#state.worklists, []),
    Tasks = lists:filter_map(fun(TaskId) ->
        case find_allocation_by_task(TaskId, State) of
            {ok, _AllocationId, Allocation} -> {true, task_queue_to_map(Allocation)};
            {error, _} -> false
        end
    end, TaskIds),
    {reply, {ok, Tasks}, State};

handle_call({get_group_worklist, GroupId}, _From, State) ->
    %% Find all tasks assigned to this group but not yet claimed
    Tasks = lists:filter_map(fun(_AllocationId, #yawl_task_queue{assigned_group = G, assigned_user = undefined} = Allocation) when G =:= GroupId ->
        {true, task_queue_to_map(Allocation)};
        (_, _) -> false
    end, maps:to_list(State#state.allocations)),
    {reply, {ok, Tasks}, State};

handle_call({get_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, _AllocationId, #yawl_task_queue{assigned_user = UserId} = Allocation} ->
            {reply, {ok, task_queue_to_map(Allocation)}, State};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call(list_queues, _From, State) ->
    QueueNames = maps:keys(State#state.task_queues),
    {reply, {ok, QueueNames}, State};

handle_call({create_queue, QueueName, _Options}, _From, State) ->
    case maps:is_key(QueueName, State#state.task_queues) of
        true ->
            {reply, {error, queue_exists}, State};
        false ->
            NewTaskQueues = maps:put(QueueName, queue:new(), State#state.task_queues),
            NewState = State#state{task_queues = NewTaskQueues},
            {reply, ok, NewState}
    end;

handle_call({start_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_user = UserId} = Allocation} ->
            %% Update workitem status
            case whereis(yawl_workitem_processor) of
                undefined -> ok;
                _Pid ->
                    %% Notify workitem processor
                    catch yawl_workitem_processor:execute_task(UserId, TaskId, #{})
            end,
            {reply, ok, State};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({suspend_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, _AllocationId, #yawl_task_queue{assigned_user = UserId}} ->
            %% Update workitem status via persistence (mandatory)
            case yawl_persistence:update_workitem_status(TaskId, suspended) of
                ok -> ok;
                {error, Reason} ->
                    error_logger:error_msg("YAWL Human Task: Failed to update workitem ~p status: ~p~n",
                                         [TaskId, Reason])
            end,
            {reply, ok, State};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({resume_task, UserId, TaskId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, _AllocationId, #yawl_task_queue{assigned_user = UserId}} ->
            {reply, ok, State};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({delegate_task, FromUserId, TaskId, ToUserId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_user = FromUserId}} ->
            %% Remove from source user's worklist
            NewWorklists1 = remove_from_worklist(FromUserId, AllocationId, State#state.worklists),

            %% Add to target user's worklist
            NewWorklists2 = update_worklist(ToUserId, AllocationId, NewWorklists1),

            %% Update allocation
            Allocation = maps:get(AllocationId, State#state.allocations),
            DelegatedAllocation = Allocation#yawl_task_queue{
                assigned_user = ToUserId,
                claimed_at = erlang:monotonic_time(millisecond)
            },
            NewAllocations = maps:put(AllocationId, DelegatedAllocation, State#state.allocations),
            NewState = State#state{worklists = NewWorklists2, allocations = NewAllocations},
            {reply, ok, NewState};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({escalate_task, UserId, TaskId, GroupId}, _From, State) ->
    case find_allocation_by_task(TaskId, State) of
        {ok, AllocationId, #yawl_task_queue{assigned_user = UserId}} ->
            %% Remove from user's worklist
            NewWorklists = remove_from_worklist(UserId, AllocationId, State#state.worklists),

            %% Update allocation to group
            Allocation = maps:get(AllocationId, State#state.allocations),
            EscalatedAllocation = Allocation#yawl_task_queue{
                assigned_user = undefined,
                assigned_group = GroupId,
                claimed_at = undefined
            },
            NewAllocations = maps:put(AllocationId, EscalatedAllocation, State#state.allocations),
            NewState = State#state{worklists = NewWorklists, allocations = NewAllocations},
            {reply, ok, NewState};
        {ok, _AllocationId, _} ->
            {reply, {error, not_assigned_to_user}, State};
        {error, not_found} ->
            {reply, {error, task_not_found}, State}
    end;

handle_call({notify_allocation, Workitem, ResourceId}, _From, State) ->
    %% Handle resource allocation notification from workitem processor
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,

    %% Create task queue entry for the allocated resource
    TaskQueueId = generate_task_queue_id(),
    TaskQueue = #yawl_task_queue{
        queue_id = TaskQueueId,
        task_id = WorkitemId,
        queue_name = maps_get_safe(queue_name, Workitem#yawl_workitem_persist.data, <<"default">>),
        assigned_user = ResourceId,  %% Treat resource as assigned user
        priority = Workitem#yawl_workitem_persist.priority,
        due_date = maps_get_safe(due_date, Workitem#yawl_workitem_persist.data, undefined),
        created_at = erlang:monotonic_time(millisecond),
        claimed_at = erlang:monotonic_time(millisecond)
    },

    %% Store allocation
    NewAllocations = maps:put(TaskQueueId, TaskQueue, State#state.allocations),
    NewWorklists = update_worklist(ResourceId, TaskQueueId, State#state.worklists),
    NewTaskData = maps:put(WorkitemId, Workitem#yawl_workitem_persist.data, State#state.task_data),

    %% Update workitem status to allocated via persistence
    case yawl_persistence:update_workitem_status(WorkitemId, allocated) of
        ok -> ok;
        {error, Reason} ->
            error_logger:error_msg("YAWL Human Task: Failed to update workitem ~p status: ~p~n",
                                 [WorkitemId, Reason])
    end,

    NewState = State#state{
        allocations = NewAllocations,
        worklists = NewWorklists,
        task_data = NewTaskData
    },
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
find_suitable_user(RequiredSkills, State) ->
    %% Use resource manager for skill-based user discovery
    case find_users_by_skills(RequiredSkills, State) of
        [] -> {error, no_suitable_user};
        MatchingUsers ->
            %% Select user based on least loaded strategy
            BestUser = select_least_loaded_user(MatchingUsers, State),
            {ok, BestUser}
    end.

%% @private
%% Find users with all required skills using resource manager
find_users_by_skills([], _State) ->
    %% If no skills required, return all available users
    case yawl_resource_manager:list_available_resources() of
        {ok, Resources} ->
            [maps:get(resource_id, R) || R <- Resources,
             maps:get(resource_type, R) =:= human];
        {error, _} -> []
    end;
find_users_by_skills(RequiredSkills, _State) ->
    %% Find human resources with all required skills
    case yawl_resource_manager:find_resources_by_capabilities(RequiredSkills) of
        {ok, Resources} ->
            [maps:get(resource_id, R) || R <- Resources,
             maps:get(resource_type, R) =:= human,
             lists:all(fun(Skill) -> lists:member(Skill, maps:get(capabilities, R, [])) end, RequiredSkills)];
        {error, not_found} ->
            %% Try to find resources with at least some required skills
            find_users_with_partial_skills(RequiredSkills);
        {error, _} ->
            []
    end.

%% @private
%% Find users with at least some required skills (fallback)
find_users_with_partial_skills(RequiredSkills) ->
    %% Get all human resources and filter by skill matching
    case yawl_resource_manager:list_resources_by_type(human) of
        {ok, Resources} ->
            MatchingResources = lists:filter(fun(Resource) ->
                UserSkills = maps:get(capabilities, Resource, []),
                %% Count how many required skills the user has
                SkillMatches = lists:foldl(fun(Skill, Acc) ->
                    case lists:member(Skill, UserSkills) of
                        true -> Acc + 1;
                        false -> Acc
                    end
                end, 0, RequiredSkills),
                %% Return users with at least one matching skill
                SkillMatches > 0
            end, Resources),
            lists:map(fun(Resource) -> maps:get(resource_id, Resource) end, MatchingResources);
        {error, _} -> []
    end.

%% @private
%% Select the least loaded user from matching candidates
select_least_loaded_user(MatchingUsers, _State) ->
    case MatchingUsers of
        [User] -> User;
        _ ->
            %% For now, just return the first user - in a real implementation,
            %% we would check user load, skill proficiency, availability, etc.
            %% This should be enhanced with proper user load tracking
            hd(MatchingUsers)
    end.

%% @private
%% Get current task load for a user
get_user_current_load(UserId, State) ->
    UserTasks = maps:get(UserId, State#state.worklists, []),
    length(UserTasks).

%% @private
%% Check if user has all required skills
user_has_required_skills(UserId, RequiredSkills, State) ->
    %% Get user from resource manager
    case yawl_resource_manager:get_resource(UserId) of
        {ok, Resource} ->
            UserSkills = maps:get(capabilities, Resource, []),
            %% Check if user has ALL required skills
            lists:all(fun(Skill) -> lists:member(Skill, UserSkills) end, RequiredSkills);
        {error, _} ->
            false
    end.

%% @private
%% Check user availability and capacity
is_user_available(UserId, _State) ->
    case yawl_resource_manager:get_resource(UserId) of
        {ok, #yawl_resource_persist{status = available, current_load = CurrentLoad, max_capacity = MaxCapacity}} when CurrentLoad < MaxCapacity ->
            true;
        {ok, _} ->
            false;
        {error, _} ->
            false
    end.

%% @private
find_allocation_by_task(TaskId, State) ->
    lists:foldl(fun(AllocationId, Acc) ->
        case Acc of
            {ok, _, _} -> Acc;
            error ->
                Allocation = maps:get(AllocationId, State#state.allocations, undefined),
                case Allocation of
                    #yawl_task_queue{task_id = TaskId} ->
                        {ok, AllocationId, Allocation};
                    _ ->
                        error
                end
        end
    end, error, maps:keys(State#state.allocations)).

%% @private
update_worklist(UserId, TaskId, Worklists) ->
    CurrentList = maps_get_safe(UserId, Worklists, []),
    Worklists#{UserId => [TaskId | CurrentList]}.

%% @private
remove_from_worklist(UserId, TaskId, Worklists) ->
    CurrentList = maps_get_safe(UserId, Worklists, []),
    NewList = lists:delete(TaskId, CurrentList),
    Worklists#{UserId => NewList}.

%% @private
generate_task_queue_id() ->
    Timestamp = erlang:monotonic_time(millisecond),
    UniqueId = erlang:unique_integer([positive, monotonic]),
    <<"taskq_", (integer_to_binary(Timestamp))/binary, "_", (integer_to_binary(UniqueId))/binary>>.

%% @private
task_queue_to_map(#yawl_task_queue{} = Queue) ->
    #{
        queue_id => Queue#yawl_task_queue.queue_id,
        task_id => Queue#yawl_task_queue.task_id,
        queue_name => Queue#yawl_task_queue.queue_name,
        assigned_user => Queue#yawl_task_queue.assigned_user,
        assigned_group => Queue#yawl_task_queue.assigned_group,
        priority => Queue#yawl_task_queue.priority,
        due_date => Queue#yawl_task_queue.due_date,
        created_at => Queue#yawl_task_queue.created_at,
        claimed_at => Queue#yawl_task_queue.claimed_at
    }.

%% @private
maps_get_safe(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
