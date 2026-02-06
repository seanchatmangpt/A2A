%%%-------------------------------------------------------------------
%%% @doc BeamAI YAWL Human Bridge
%%% gen_server bridging YAWL human tasks to beamai agent interrupts.
%%% Creates beamai_a2a_tasks with input_required state for human tasks;
%%% resumes agents via beamai_agent:resume/2 when humans respond.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_human_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").
-include("a2a.hrl").

-export([start_link/0, request_human_input/2, submit_response/2, get_pending/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    pending = #{} :: #{binary() => map()},
    agents  = #{} :: #{binary() => term()}
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

request_human_input(WorkitemId, TaskInfo) ->
    gen_server:call(?MODULE, {request_human_input, WorkitemId, TaskInfo}).

submit_response(TaskId, Response) ->
    gen_server:call(?MODULE, {submit_response, TaskId, Response}, infinity).

get_pending() ->
    gen_server:call(?MODULE, get_pending).

init([]) -> {ok, #state{}}.

handle_call({request_human_input, WorkitemId, TaskInfo}, _From, State) ->
    TaskId = <<"human_", WorkitemId/binary, "_",
               (integer_to_binary(erlang:system_time(millisecond)))/binary>>,
    Prompt = maps:get(prompt, TaskInfo, <<"Please provide input">>),
    Cfg = maps:merge(#{prompt => Prompt, tools => []},
                     maps:get(agent_opts, TaskInfo, #{})),
    Entry = #{task_id => TaskId, workitem_id => WorkitemId,
              prompt => Prompt, state => input_required,
              created_at => erlang:system_time(millisecond)},
    NewPending = maps:put(TaskId, Entry, State#state.pending),
    NewAgents = case beamai_agent:new(Cfg) of
        {ok, AS}   -> maps:put(TaskId, AS, State#state.agents);
        {error, _} -> State#state.agents
    end,
    catch notify_input_required(TaskId, Prompt),
    {reply, {ok, TaskId}, State#state{pending = NewPending, agents = NewAgents}};

handle_call({submit_response, TaskId, Response}, _From, State) ->
    case maps:get(TaskId, State#state.pending, undefined) of
        undefined ->
            {reply, {error, task_not_found}, State};
        #{workitem_id := WId} = Entry ->
            {Reply, S2} = do_submit(TaskId, WId, Response, Entry, State),
            {reply, Reply, S2}
    end;

handle_call(get_pending, _From, State) ->
    Pending = [E || {_, #{state := input_required} = E} <- maps:to_list(State#state.pending)],
    {reply, {ok, Pending}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% Internal
do_submit(TaskId, WId, Response, Entry, State) ->
    Updated = Entry#{state => completed, response => Response},
    NewPending = maps:put(TaskId, Updated, State#state.pending),
    case maps:get(TaskId, State#state.agents, undefined) of
        undefined ->
            complete_workitem(WId, Response),
            {ok, State#state{pending = NewPending}};
        AgentState ->
            case beamai_agent:resume(AgentState, Response) of
                {ok, _Result, NewAS} ->
                    complete_workitem(WId, Response),
                    NewAgents = maps:put(TaskId, NewAS, State#state.agents),
                    {ok, State#state{pending = NewPending, agents = NewAgents}};
                {error, Reason} ->
                    {{error, Reason}, State}
            end
    end.

notify_input_required(TaskId, Prompt) ->
    case beamai_a2a_types:is_terminal_state(input_required) of
        false -> yawl_a2a_events:publish(input_required,
                     #{task_id => TaskId, prompt => Prompt});
        true  -> ok
    end.

complete_workitem(WId, Response) ->
    catch yawl_persistence:update_workitem_status(WId, completed),
    catch yawl_a2a_events:publish(workitem_completed,
              #{workitem_id => WId, result => Response}).
