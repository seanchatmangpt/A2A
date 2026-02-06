%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI-YAWL Bridge
%%%
%%% Main gen_server bridging the YAWL orchestrator to the beamai agent
%%% system. Registers YAWL workflow definitions and executes them as
%%% beamai agents with tools derived from YAWL work items.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% API
-export([start_link/0, register_workflow/2, execute_as_agent/2,
         map_workitem_to_tool/1, get_workflow_agent/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    workflows     = #{} :: #{binary() => map()},
    agents        = #{} :: #{binary() => term()},
    tool_mappings = #{} :: #{binary() => term()}
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec register_workflow(binary(), map()) -> ok | {error, term()}.
register_workflow(WorkflowId, WorkflowDef) ->
    gen_server:call(?MODULE, {register_workflow, WorkflowId, WorkflowDef}).

-spec execute_as_agent(binary(), map()) -> {ok, term()} | {error, term()}.
execute_as_agent(WorkflowId, Input) ->
    gen_server:call(?MODULE, {execute_as_agent, WorkflowId, Input}, infinity).

-spec map_workitem_to_tool(#yawl_workitem_persist{}) -> map().
map_workitem_to_tool(Workitem) ->
    Name = Workitem#yawl_workitem_persist.task_name,
    ToolName = <<"yawl_", Name/binary>>,
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,
    Handler = fun(Args) ->
        Data = maps:merge(Workitem#yawl_workitem_persist.data, Args),
        case yawl_orchestrator:complete_workitem(
               Workitem#yawl_workitem_persist.workflow_id,
               Workitem#yawl_workitem_persist.task_id,
               Data) of
            ok    -> #{status => completed, workitem_id => WorkitemId};
            Error -> #{status => failed, error => Error}
        end
    end,
    beamai_tool:new(ToolName, Handler, #{
        description => <<"YAWL work item: ", Name/binary>>
    }).

-spec get_workflow_agent(binary()) -> {ok, term()} | {error, not_found}.
get_workflow_agent(WorkflowId) ->
    gen_server:call(?MODULE, {get_workflow_agent, WorkflowId}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    {ok, #state{}}.

handle_call({register_workflow, WorkflowId, WorkflowDef}, _From, State) ->
    NewWorkflows = maps:put(WorkflowId, WorkflowDef, State#state.workflows),
    {reply, ok, State#state{workflows = NewWorkflows}};

handle_call({execute_as_agent, WorkflowId, Input}, _From, State) ->
    case maps:get(WorkflowId, State#state.workflows, undefined) of
        undefined ->
            {reply, {error, workflow_not_found}, State};
        WorkflowDef ->
            case do_execute(WorkflowId, WorkflowDef, Input, State) of
                {ok, Result, NewState} ->
                    {reply, {ok, Result}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({get_workflow_agent, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.agents, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Agent     -> {reply, {ok, Agent}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

do_execute(WorkflowId, WorkflowDef, Input, State) ->
    WorkItems = maps:get(work_items, WorkflowDef, []),
    Tools = [map_workitem_to_tool(WI) || WI <- WorkItems],
    Kernel = beamai_kernel:new(#{name => <<"yawl_", WorkflowId/binary>>}),
    Kernel1 = beamai_kernel:add_tools(Kernel, Tools),
    AgentOpts = #{
        kernel  => Kernel1,
        prompt  => build_prompt(WorkflowDef),
        tools   => Tools
    },
    case beamai_agent:new(AgentOpts) of
        {ok, AgentState} ->
            ToolMap = maps:from_list(
                [{T, beamai_tool:new(T, fun(_) -> ok end)} || T <- maps:get(transitions, WorkflowDef, [])]),
            case beamai_agent:run(AgentState, Input) of
                {ok, RunResult, NewAgentState} ->
                    NewAgents = maps:put(WorkflowId, NewAgentState, State#state.agents),
                    NewMappings = maps:put(WorkflowId, ToolMap, State#state.tool_mappings),
                    {ok, RunResult, State#state{agents = NewAgents, tool_mappings = NewMappings}};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

build_prompt(WorkflowDef) ->
    PatternType = maps:get(pattern_type, WorkflowDef, unknown),
    iolist_to_binary([
        <<"Execute YAWL workflow pattern: ">>,
        atom_to_binary(PatternType, utf8),
        <<". Use the provided tools to complete each work item in order.">>
    ]).
