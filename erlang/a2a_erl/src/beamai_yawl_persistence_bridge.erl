%%%-------------------------------------------------------------------
%%% @doc BeamAI YAWL Persistence Bridge
%%% gen_server that synchronizes YAWL Mnesia workflow state to
%%% beamai_memory. Checkpoints save YAWL state as beamai snapshots.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_persistence_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% API
-export([start_link/0, checkpoint/1, restore/1,
         get_timeline/1, sync_to_memory/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    memory    = undefined :: term(),
    snapshots = #{} :: #{binary() => [binary()]}
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec checkpoint(binary()) -> {ok, binary()} | {error, term()}.
checkpoint(WorkflowId) ->
    gen_server:call(?MODULE, {checkpoint, WorkflowId}).

-spec restore(binary()) -> {ok, map()} | {error, term()}.
restore(WorkflowId) ->
    gen_server:call(?MODULE, {restore, WorkflowId}).

-spec get_timeline(binary()) -> {ok, [map()]} | {error, term()}.
get_timeline(WorkflowId) ->
    gen_server:call(?MODULE, {get_timeline, WorkflowId}).

-spec sync_to_memory(binary(), map()) -> ok | {error, term()}.
sync_to_memory(WorkflowId, Data) ->
    gen_server:call(?MODULE, {sync_to_memory, WorkflowId, Data}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Memory = beamai_memory:new(#{namespace => <<"yawl_persistence">>}),
    {ok, #state{memory = Memory}}.

handle_call({checkpoint, WorkflowId}, _From, State) ->
    case yawl_persistence:load_workflow(WorkflowId) of
        {ok, Workflow} ->
            SnapshotId = make_snapshot_id(WorkflowId),
            YawlState = workflow_to_map(Workflow),
            %% Save to beamai_memory
            case beamai_memory:save_snapshot(
                   State#state.memory, SnapshotId, YawlState) of
                ok ->
                    %% Also save YAWL checkpoint
                    catch yawl_persistence:save_checkpoint(WorkflowId, YawlState),
                    %% Track snapshot for timeline
                    Existing = maps:get(WorkflowId, State#state.snapshots, []),
                    NewSnapshots = maps:put(WorkflowId,
                                            [SnapshotId | Existing],
                                            State#state.snapshots),
                    {reply, {ok, SnapshotId},
                     State#state{snapshots = NewSnapshots}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({restore, WorkflowId}, _From, State) ->
    SnapshotIds = maps:get(WorkflowId, State#state.snapshots, []),
    case SnapshotIds of
        [] ->
            {reply, {error, no_snapshots}, State};
        [LatestId | _] ->
            case beamai_memory:load_snapshot(State#state.memory, LatestId) of
                {ok, SnapshotData} ->
                    {reply, {ok, SnapshotData}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({get_timeline, WorkflowId}, _From, State) ->
    SnapshotIds = maps:get(WorkflowId, State#state.snapshots, []),
    Timeline = lists:filtermap(fun(SId) ->
        case beamai_memory:load_snapshot(State#state.memory, SId) of
            {ok, Data} -> {true, Data#{snapshot_id => SId}};
            _          -> false
        end
    end, lists:reverse(SnapshotIds)),
    {reply, {ok, Timeline}, State};

handle_call({sync_to_memory, WorkflowId, Data}, _From, State) ->
    Namespace = <<"yawl_wf_", WorkflowId/binary>>,
    Ts = erlang:system_time(millisecond),
    Key = integer_to_binary(Ts),
    case beamai_memory:put(State#state.memory, Namespace, Key, Data, #{}) of
        ok    -> {reply, ok, State};
        Error -> {reply, Error, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

make_snapshot_id(WorkflowId) ->
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<"snap_", WorkflowId/binary, "_", Ts/binary>>.

workflow_to_map(#yawl_workflow_persist{} = W) ->
    #{
        workflow_id => W#yawl_workflow_persist.workflow_id,
        pattern_type => W#yawl_workflow_persist.pattern_type,
        status => W#yawl_workflow_persist.status,
        marking => W#yawl_workflow_persist.marking,
        current_place => W#yawl_workflow_persist.current_place,
        data => W#yawl_workflow_persist.data,
        created_at => W#yawl_workflow_persist.created_at,
        updated_at => W#yawl_workflow_persist.updated_at,
        checkpointed_at => erlang:system_time(millisecond)
    }.
