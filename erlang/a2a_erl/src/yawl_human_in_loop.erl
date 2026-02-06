%%%-------------------------------------------------------------------
%%% @doc
%%% Human-in-the-Loop Workflow Module
%%%
%%% This module implements human-in-the-loop workflows using Claude Code
%%% headless integration for:
%%% - Human approval gates in workflows
%%% - LLM-assisted decision making
%%% - Feedback collection and incorporation
%%% - Session-based multi-turn interactions
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_human_in_loop).
-author("A2A Team").

-behaviour(gen_server).

%% API exports
-export([
    start_link/0,
    start_link/1,

    %% Workflow Gates
    create_approval_gate/3,
    check_approval_status/1,
    submit_approval/3,

    %% LLM-Assisted Decisions
    request_decision_with_llm/2,
    request_decision_with_llm/3,

    %% Feedback Collection
    collect_feedback/2,
    analyze_feedback_with_llm/1,

    %% Multi-turn Sessions
    start_collaborative_session/2,
    continue_session/2,
    end_session/1,

    %% Query
    get_pending_approvals/0,
    get_approval_history/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-include("yawl_types.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    pending_approvals = #{} :: map(),
    approval_history = [] :: list(),
    sessions = #{} :: map(),
    feedback_store = #{} :: map()
}).

-record(approval_gate, {
    id :: binary(),
    workflow_id :: binary(),
    task_id :: binary(),
    decision_prompt :: binary(),
    context :: map(),
    llm_assist = false :: boolean(),
    status = pending :: pending | approved | rejected,
    created_at :: integer(),
    llm_suggestion :: binary() | undefined
}).

-record(collab_session, {
    id :: binary(),
    workflow_id :: binary(),
    participants = [] :: [binary()],
    messages = [] :: list(),
    status = active :: active | completed | cancelled,
    created_at :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the human-in-the-loop server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Start with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

%% @doc Create an approval gate for a workflow task.
-spec create_approval_gate(binary(), binary(), binary()) -> {ok, binary()}.
create_approval_gate(WorkflowId, TaskId, DecisionPrompt) ->
    create_approval_gate(WorkflowId, TaskId, DecisionPrompt, #{}).

%% @doc Create an approval gate with options.
-spec create_approval_gate(binary(), binary(), binary(), map()) -> {ok, binary()}.
create_approval_gate(WorkflowId, TaskId, DecisionPrompt, Options) ->
    gen_server:call(?MODULE, {create_gate, WorkflowId, TaskId, DecisionPrompt, Options}, infinity).

%% @doc Check approval status.
-spec check_approval_status(binary()) -> {ok, map()}.
check_approval_status(ApprovalId) ->
    gen_server:call(?MODULE, {check_status, ApprovalId}, infinity).

%% @doc Submit approval/rejection decision.
-spec submit_approval(binary(), approved | rejected, map()) -> ok.
submit_approval(ApprovalId, Decision, Feedback) ->
    gen_server:call(?MODULE, {submit_approval, ApprovalId, Decision, Feedback}, infinity).

%% @doc Request decision with LLM assistance.
-spec request_decision_with_llm(binary(), binary()) -> {ok, map()}.
request_decision_with_llm(DecisionPrompt, Context) ->
    request_decision_with_llm(DecisionPrompt, Context, []).

%% @doc Request decision with LLM and options.
-spec request_decision_with_llm(binary(), binary(), map()) -> {ok, map()}.
request_decision_with_llm(DecisionPrompt, Context, Options) ->
    gen_server:call(?MODULE, {llm_decision, DecisionPrompt, Context, Options}, infinity).

%% @doc Collect feedback from human.
-spec collect_feedback(binary(), map()) -> ok.
collect_feedback(WorkflowId, Feedback) ->
    gen_server:cast(?MODULE, {collect_feedback, WorkflowId, Feedback}).

%% @doc Analyze feedback with LLM.
-spec analyze_feedback_with_llm(binary()) -> {ok, binary()}.
analyze_feedback_with_llm(WorkflowId) ->
    gen_server:call(?MODULE, {analyze_feedback, WorkflowId}, infinity).

%% @doc Start collaborative session.
-spec start_collaborative_session(binary(), [binary()]) -> {ok, binary()}.
start_collaborative_session(WorkflowId, Participants) ->
    gen_server:call(?MODULE, {start_session, WorkflowId, Participants}, infinity).

%% @doc Continue collaborative session.
-spec continue_session(binary(), binary()) -> {ok, map()}.
continue_session(SessionId, Message) ->
    gen_server:call(?MODULE, {continue_session, SessionId, Message}, infinity).

%% @doc End collaborative session.
-spec end_session(binary()) -> ok.
end_session(SessionId) ->
    gen_server:cast(?MODULE, {end_session, SessionId}).

%% @doc Get pending approvals.
-spec get_pending_approvals() -> {ok, [map()]}.
get_pending_approvals() ->
    gen_server:call(?MODULE, get_pending, infinity).

%% @doc Get approval history.
-spec get_approval_history(binary()) -> {ok, [map()]}.
get_approval_history(WorkflowId) ->
    gen_server:call(?MODULE, {get_history, WorkflowId}, infinity).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #state{}};
init([Options]) ->
    {ok, #state{}}.

handle_call({create_gate, WorkflowId, TaskId, DecisionPrompt, Options}, _From, State) ->
    ApprovalId = generate_id(),
    LLMAssist = maps:get(llm_assist, Options, false),

    Gate = #approval_gate{
        id = ApprovalId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        decision_prompt = DecisionPrompt,
        context = maps:get(context, Options, #{}),
        llm_assist = LLMAssist,
        created_at = erlang:monotonic_time(millisecond)
    },

    %% Get LLM suggestion if enabled
    FinalGate = case LLMAssist of
        true ->
            case get_llm_suggestion(DecisionPrompt, maps:get(context, Options, #{})) of
                {ok, Suggestion} ->
                    Gate#approval_gate{llm_suggestion = Suggestion};
                _ ->
                    Gate
            end;
        false ->
            Gate
    end,

    {reply, {ok, ApprovalId}, State#state{
        pending_approvals = maps:put(ApprovalId, FinalGate, State#state.pending_approvals)
    }};

handle_call({check_status, ApprovalId}, _From, State) ->
    case maps:get(ApprovalId, State#state.pending_approvals) of
        undefined ->
            {reply, {error, not_found}, State};
        Gate ->
            {reply, {ok, gate_to_map(Gate)}, State}
    end;

handle_call({submit_approval, ApprovalId, Decision, Feedback}, _From, State) ->
    case maps:get(ApprovalId, State#state.pending_approvals) of
        undefined ->
            {reply, {error, not_found}, State};
        Gate ->
            UpdatedGate = Gate#approval_gate{
                status = Decision,
                context = maps:merge(Gate#approval_gate.context, Feedback)
            },
            {reply, ok, State#state{
                pending_approvals = maps:remove(ApprovalId, State#state.pending_approvals),
                approval_history = [gate_to_map(UpdatedGate) | State#state.approval_history]
            }};
        _ ->
            {reply, {error, not_found}, State}
    end;

handle_call({llm_decision, DecisionPrompt, Context, Options}, _From, State) ->
    %% Get LLM decision with structured output
    Schema = #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"decision">> => #{<<"type">> => <<"string">>, <<"enum">> => [<<"approve">>, <<"reject">>, <<"escalate">>]},
            <<"reasoning">> => #{<<"type">> => <<"string">>},
            <<"confidence">> => #{<<"type">> => <<"number">>}
        },
        <<"required">> => [<<"decision">>, <<"reasoning">>]
    },

    FullPrompt = <<"
    Decision needed for workflow task.

    Prompt: ", DecisionPrompt/binary, "

    Context: ", (jiffy:encode(Context))/binary, "

    Provide your decision as JSON with:
    - decision: \"approve\", \"reject\", or \"escalate\"
    - reasoning: explanation for your decision
    - confidence: 0.0 to 1.0
    ">>,

    case yawl_claude_headless:llm_generate_with_schema(FullPrompt, Schema) of
        {ok, Result} ->
            {reply, {ok, Result}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({analyze_feedback, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.feedback_store) of
        undefined ->
            {reply, {error, no_feedback}, State};
        Feedback ->
            %% Analyze with LLM
            Prompt = <<"
            Analyze the following workflow feedback and provide:

            1. Summary of key issues raised
            2. Suggested improvements
            3. Priority ranking of issues

            Feedback:
            ", (jiffy:encode(Feedback))/binary, "\n">>,

            case yawl_claude_headless:llm_generate(Prompt, []) of
                {ok, Analysis} ->
                    {reply, {ok, Analysis}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({start_session, WorkflowId, Participants}, _From, State) ->
    SessionId = generate_id(),
    Session = #collab_session{
        id = SessionId,
        workflow_id = WorkflowId,
        participants = Participants,
        created_at = erlang:monotonic_time(millisecond)
    },
    {reply, {ok, SessionId}, State#state{
        sessions = maps:put(SessionId, Session, State#state.sessions)
    }};

handle_call({continue_session, SessionId, Message}, _From, State) ->
    case maps:get(SessionId, State#state.sessions) of
        undefined ->
            {reply, {error, session_not_found}, State};
        Session ->
            UpdatedSession = Session#collab_session{
                messages = [Message | Session#collab_session.messages]
            },
            %% Notify participants
            notify_participants(Session#collab_session.participants, Message),
            {reply, {ok, session_to_map(UpdatedSession)}, State#state{
                sessions = maps:put(SessionId, UpdatedSession, State#state.sessions)
            }}
    end;

handle_call(get_pending, _From, State) ->
    Pending = [gate_to_map(G) || G <- maps:values(State#state.pending_approvals)],
    {reply, {ok, Pending}, State};

handle_call({get_history, WorkflowId}, _From, State) ->
    History = [G || G <- State#state.approval_history,
        maps:get(workflow_id, G, undefined) =:= WorkflowId],
    {reply, {ok, History}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({collect_feedback, WorkflowId, Feedback}, State) ->
    Current = maps:get(WorkflowId, State#state.feedback_store, []),
    {noreply, State#state{
        feedback_store = maps:put(WorkflowId, [Feedback | Current], State#state.feedback_store)
    }};

handle_cast({end_session, SessionId}, State) ->
    case maps:get(SessionId, State#state.sessions) of
        undefined ->
            {noreply, State};
        Session ->
            UpdatedSession = Session#collab_session{status = completed},
            {noreply, State#state{
                sessions = maps:put(SessionId, UpdatedSession, State#state.sessions)
            }}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Private Functions
%%====================================================================

%% @private
get_llm_suggestion(DecisionPrompt, Context) ->
    Prompt = <<"
    As an expert in workflow automation, provide a suggested decision for:

    ", DecisionPrompt/binary, "

    Context: ", (jiffy:encode(Context))/binary, "

    Provide:
    1. Your recommended decision (approve/reject)
    2. Reasoning for your decision
    3. Any conditions or concerns
    ">>,
    yawl_claude_headless:llm_generate(Prompt, []).

%% @private
gate_to_map(#approval_gate{id = Id, workflow_id = WfId, task_id = TaskId,
    decision_prompt = Prompt, context = Ctx, status = Status,
    created_at = Created, llm_suggestion = Suggestion}) ->
    #{
        id => Id,
        workflow_id => WfId,
        task_id => TaskId,
        decision_prompt => Prompt,
        context => Ctx,
        status => Status,
        created_at => Created,
        llm_suggestion => Suggestion
    }.

%% @private
session_to_map(#collab_session{id = Id, workflow_id = WfId,
    participants = Parts, messages = Msgs, status = Status, created_at = Created}) ->
    #{
        id => Id,
        workflow_id => WfId,
        participants => Parts,
        message_count => length(Msgs),
        status => Status,
        created_at => Created
    }.

%% @private
notify_participants(Participants, Message) ->
    %% In production, this would send notifications via SSE, email, etc.
    lists:foreach(fun(P) ->
        io:format("Notifying participant ~p: ~p~n", [P, Message])
    end, Participants).

%% @private
generate_id() ->
    Binary = term_to_binary({node(), erlang:monotonic_time(microsecond), erlang:unique_integer([positive])}),
    lists:flatten([io_lib:format("~2.16.0B", [B]) || <<B>> <= Binary]).
