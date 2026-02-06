%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Human-in-the-Loop Bridge
%%%
%%% Bridges human task management between YAWL (yawl_human_task,
%%% yawl_human_in_loop) and the BeamAI agent system. This module:
%%%
%%% - Connects YAWL human tasks to BeamAI agent interrupts
%%% - Supports human approval workflows via BeamAI input_required
%%% - Maps YAWL human task forms to BeamAI input specifications
%%% - Handles timeouts and escalation across both systems
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_human_bridge).
-behaviour(gen_server).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%% API
-export([
    start_link/0,
    request_human_input/2,
    submit_response/2,
    get_pending/0,
    timeout_handler/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 300000). %% 5 minutes

-record(pending_request, {
    request_id :: binary(),
    workflow_id :: binary(),
    task_id :: binary(),
    prompt :: binary(),
    context :: map(),
    form_schema :: map(),
    source :: yawl | beamai,
    requested_at :: integer(),
    timeout_ms :: non_neg_integer(),
    timeout_ref :: reference() | undefined,
    callback_pid :: pid() | undefined,
    status :: pending | responded | timed_out | escalated
}).

-record(state, {
    pending = #{} :: #{binary() => #pending_request{}},
    response_history = [] :: [map()],
    escalation_rules = #{} :: #{atom() => fun()},
    max_history :: non_neg_integer()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the human bridge server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Request human input for a workflow task.
%% Creates a pending request in both YAWL and BeamAI systems.
%% TaskSpec must contain: workflow_id, task_id, prompt.
%% Optional: form_schema, timeout_ms, context, callback_pid.
-spec request_human_input(binary(), map()) ->
    {ok, binary()} | {error, term()}.
request_human_input(WorkflowId, TaskSpec) ->
    gen_server:call(?SERVER, {request_human_input, WorkflowId, TaskSpec}).

%% @doc Submit a human response for a pending request.
%% Forwards the response to both YAWL and BeamAI systems.
-spec submit_response(binary(), map()) -> ok | {error, term()}.
submit_response(RequestId, Response) ->
    gen_server:call(?SERVER, {submit_response, RequestId, Response}).

%% @doc Get all pending human input requests across both systems.
-spec get_pending() -> {ok, [map()]}.
get_pending() ->
    gen_server:call(?SERVER, get_pending).

%% @doc Handle a timeout for a pending request.
%% Action can be: escalate | cancel | extend.
-spec timeout_handler(binary(), atom()) -> ok | {error, term()}.
timeout_handler(RequestId, Action) ->
    gen_server:call(?SERVER, {timeout_handler, RequestId, Action}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("YAWL-BeamAI human bridge started"),
    {ok, #state{max_history = 1000}}.

%% @private
handle_call({request_human_input, WorkflowId, TaskSpec}, _From, State) ->
    #state{pending = Pending} = State,
    RequestId = generate_request_id(),
    TaskId = maps:get(task_id, TaskSpec, <<"unknown">>),
    Prompt = maps:get(prompt, TaskSpec, <<"Please provide input">>),
    FormSchema = maps:get(form_schema, TaskSpec, #{}),
    TimeoutMs = maps:get(timeout_ms, TaskSpec, ?DEFAULT_TIMEOUT),
    Context = maps:get(context, TaskSpec, #{}),
    CallbackPid = maps:get(callback_pid, TaskSpec, undefined),

    %% Set up the timeout timer
    TimeoutRef = erlang:send_after(TimeoutMs, self(), {request_timeout, RequestId}),

    Request = #pending_request{
        request_id = RequestId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        prompt = Prompt,
        context = Context,
        form_schema = FormSchema,
        source = maps:get(source, TaskSpec, yawl),
        requested_at = erlang:system_time(millisecond),
        timeout_ms = TimeoutMs,
        timeout_ref = TimeoutRef,
        callback_pid = CallbackPid,
        status = pending
    },

    %% Register with YAWL human task system
    register_with_yawl(WorkflowId, TaskId, RequestId, Prompt, FormSchema),

    %% Create BeamAI input_required state
    notify_beamai_input_required(WorkflowId, RequestId, Prompt, FormSchema),

    NewPending = Pending#{RequestId => Request},
    NewState = State#state{pending = NewPending},
    {reply, {ok, RequestId}, NewState};

handle_call({submit_response, RequestId, Response}, _From, State) ->
    #state{pending = Pending, response_history = History} = State,
    case maps:find(RequestId, Pending) of
        {ok, #pending_request{status = pending} = Request} ->
            %% Cancel the timeout timer
            cancel_timeout(Request#pending_request.timeout_ref),

            %% Forward response to YAWL
            forward_response_to_yawl(Request, Response),

            %% Forward response to BeamAI agent
            forward_response_to_beamai(Request, Response),

            %% Notify callback if registered
            notify_callback(Request#pending_request.callback_pid, RequestId, Response),

            %% Record in history and remove from pending
            HistoryEntry = #{
                request_id => RequestId,
                workflow_id => Request#pending_request.workflow_id,
                task_id => Request#pending_request.task_id,
                response => Response,
                responded_at => erlang:system_time(millisecond),
                latency_ms => erlang:system_time(millisecond) -
                              Request#pending_request.requested_at
            },
            NewHistory = trim_history([HistoryEntry | History], State#state.max_history),
            NewPending = maps:remove(RequestId, Pending),
            NewState = State#state{pending = NewPending, response_history = NewHistory},
            {reply, ok, NewState};
        {ok, #pending_request{status = Status}} ->
            {reply, {error, {request_not_pending, Status}}, State};
        error ->
            {reply, {error, request_not_found}, State}
    end;

handle_call(get_pending, _From, #state{pending = Pending} = State) ->
    %% Merge with YAWL pending approvals
    YawlPending = fetch_yawl_pending(),
    BridgePending = maps:fold(fun(_Id, Req, Acc) ->
        case Req#pending_request.status of
            pending ->
                [pending_request_to_map(Req) | Acc];
            _ ->
                Acc
        end
    end, [], Pending),
    %% Deduplicate by request_id
    AllPending = deduplicate_pending(BridgePending ++ YawlPending),
    {reply, {ok, AllPending}, State};

handle_call({timeout_handler, RequestId, Action}, _From, State) ->
    #state{pending = Pending} = State,
    case maps:find(RequestId, Pending) of
        {ok, #pending_request{status = pending} = Request} ->
            case Action of
                escalate ->
                    do_escalate(Request, State);
                cancel ->
                    cancel_timeout(Request#pending_request.timeout_ref),
                    UpdatedReq = Request#pending_request{status = timed_out},
                    NewPending = Pending#{RequestId => UpdatedReq},
                    notify_timeout_to_yawl(Request),
                    notify_timeout_to_beamai(Request),
                    {reply, ok, State#state{pending = NewPending}};
                extend ->
                    %% Extend timeout by the original duration
                    cancel_timeout(Request#pending_request.timeout_ref),
                    NewRef = erlang:send_after(
                        Request#pending_request.timeout_ms, self(),
                        {request_timeout, RequestId}
                    ),
                    UpdatedReq = Request#pending_request{timeout_ref = NewRef},
                    NewPending = Pending#{RequestId => UpdatedReq},
                    {reply, ok, State#state{pending = NewPending}};
                _ ->
                    {reply, {error, {invalid_action, Action}}, State}
            end;
        {ok, _} ->
            {reply, {error, request_already_resolved}, State};
        error ->
            {reply, {error, request_not_found}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({request_timeout, RequestId}, State) ->
    #state{pending = Pending, escalation_rules = Rules} = State,
    case maps:find(RequestId, Pending) of
        {ok, #pending_request{status = pending} = Request} ->
            %% Check if there's an escalation rule for this task type
            TaskId = Request#pending_request.task_id,
            case maps:find(TaskId, Rules) of
                {ok, EscalationFun} ->
                    try EscalationFun(Request)
                    catch _:_ -> ok
                    end,
                    UpdatedReq = Request#pending_request{status = escalated},
                    NewPending = Pending#{RequestId => UpdatedReq},
                    {noreply, State#state{pending = NewPending}};
                error ->
                    %% Default: mark as timed out
                    UpdatedReq = Request#pending_request{status = timed_out},
                    NewPending = Pending#{RequestId => UpdatedReq},
                    notify_timeout_to_yawl(Request),
                    notify_timeout_to_beamai(Request),
                    logger:warning("Human input request ~s timed out", [RequestId]),
                    {noreply, State#state{pending = NewPending}}
            end;
        _ ->
            %% Already resolved, ignore
            {noreply, State}
    end;

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{pending = Pending}) ->
    %% Cancel all pending timers
    maps:foreach(fun(_Id, Req) ->
        cancel_timeout(Req#pending_request.timeout_ref)
    end, Pending),
    ok.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Register a human input request with the YAWL human task system.
-spec register_with_yawl(binary(), binary(), binary(), binary(), map()) -> ok.
register_with_yawl(WorkflowId, TaskId, RequestId, Prompt, FormSchema) ->
    case whereis(yawl_human_in_loop) of
        undefined -> ok;
        _Pid ->
            try
                Context = #{
                    bridge_request_id => RequestId,
                    form_schema => FormSchema
                },
                yawl_human_in_loop:create_approval_gate(
                    WorkflowId, TaskId,
                    #{decision_prompt => Prompt, context => Context}
                )
            catch
                _:_ -> ok
            end
    end.

%% @private Notify BeamAI system that input is required.
-spec notify_beamai_input_required(binary(), binary(), binary(), map()) -> ok.
notify_beamai_input_required(WorkflowId, RequestId, Prompt, FormSchema) ->
    case whereis(beamai_yawl_bridge) of
        undefined -> ok;
        _Pid ->
            try
                beamai_yawl_bridge ! {human_input_required, #{
                    workflow_id => WorkflowId,
                    request_id => RequestId,
                    prompt => Prompt,
                    form_schema => FormSchema
                }}
            catch
                _:_ -> ok
            end
    end.

%% @private Forward a human response to the YAWL system.
-spec forward_response_to_yawl(#pending_request{}, map()) -> ok.
forward_response_to_yawl(Request, Response) ->
    case whereis(yawl_human_in_loop) of
        undefined -> ok;
        _Pid ->
            try
                Decision = maps:get(decision, Response, maps:get(approved, Response, true)),
                ApprovalDecision = case Decision of
                    true -> approved;
                    false -> rejected;
                    approved -> approved;
                    rejected -> rejected;
                    Other -> Other
                end,
                yawl_human_in_loop:submit_approval(
                    Request#pending_request.request_id,
                    ApprovalDecision,
                    Response
                )
            catch
                _:_ -> ok
            end
    end,
    %% Also notify the human task service for work list updates
    case whereis(yawl_human_task) of
        undefined -> ok;
        _Pid2 ->
            try
                yawl_human_task:complete_task(
                    Request#pending_request.task_id,
                    Request#pending_request.workflow_id,
                    Response
                )
            catch
                _:_ -> ok
            end
    end.

%% @private Forward a human response to the BeamAI agent system.
-spec forward_response_to_beamai(#pending_request{}, map()) -> ok.
forward_response_to_beamai(Request, Response) ->
    case whereis(beamai_yawl_bridge) of
        undefined -> ok;
        _Pid ->
            try
                case beamai_yawl_bridge:get_workflow_agent(
                    Request#pending_request.workflow_id) of
                    {ok, AgentPid} ->
                        AgentPid ! {human_response, #{
                            request_id => Request#pending_request.request_id,
                            task_id => Request#pending_request.task_id,
                            response => Response
                        }};
                    _ ->
                        ok
                end
            catch
                _:_ -> ok
            end
    end.

%% @private Notify a callback process of the response.
-spec notify_callback(pid() | undefined, binary(), map()) -> ok.
notify_callback(undefined, _RequestId, _Response) -> ok;
notify_callback(Pid, RequestId, Response) ->
    case is_process_alive(Pid) of
        true -> Pid ! {human_input_response, RequestId, Response};
        false -> ok
    end,
    ok.

%% @private Fetch pending approvals from the YAWL system.
-spec fetch_yawl_pending() -> [map()].
fetch_yawl_pending() ->
    case whereis(yawl_human_in_loop) of
        undefined -> [];
        _Pid ->
            try
                case yawl_human_in_loop:get_pending_approvals() of
                    {ok, Approvals} ->
                        [#{
                            request_id => maps:get(id, A, <<"unknown">>),
                            workflow_id => maps:get(workflow_id, A, <<"unknown">>),
                            task_id => maps:get(task_id, A, <<"unknown">>),
                            prompt => maps:get(decision_prompt, A, <<>>),
                            source => yawl,
                            status => pending
                        } || A <- Approvals];
                    _ -> []
                end
            catch
                _:_ -> []
            end
    end.

%% @private Convert a pending request record to a map.
-spec pending_request_to_map(#pending_request{}) -> map().
pending_request_to_map(#pending_request{} = Req) ->
    #{
        request_id => Req#pending_request.request_id,
        workflow_id => Req#pending_request.workflow_id,
        task_id => Req#pending_request.task_id,
        prompt => Req#pending_request.prompt,
        context => Req#pending_request.context,
        form_schema => Req#pending_request.form_schema,
        source => Req#pending_request.source,
        requested_at => Req#pending_request.requested_at,
        timeout_ms => Req#pending_request.timeout_ms,
        status => Req#pending_request.status,
        age_ms => erlang:system_time(millisecond) - Req#pending_request.requested_at
    }.

%% @private Deduplicate pending requests by request_id.
-spec deduplicate_pending([map()]) -> [map()].
deduplicate_pending(PendingList) ->
    Map = lists:foldl(fun(Item, Acc) ->
        Id = maps:get(request_id, Item, <<"unknown">>),
        case maps:is_key(Id, Acc) of
            true -> Acc;
            false -> Acc#{Id => Item}
        end
    end, #{}, PendingList),
    maps:values(Map).

%% @private Escalate a timed-out request.
-spec do_escalate(#pending_request{}, #state{}) ->
    {reply, ok, #state{}}.
do_escalate(Request, #state{pending = Pending} = State) ->
    RequestId = Request#pending_request.request_id,
    cancel_timeout(Request#pending_request.timeout_ref),
    %% Try YAWL escalation
    case whereis(yawl_human_task) of
        undefined -> ok;
        _Pid ->
            try
                yawl_human_task:escalate_task(
                    Request#pending_request.task_id,
                    Request#pending_request.workflow_id,
                    #{reason => timeout, request_id => RequestId}
                )
            catch _:_ -> ok
            end
    end,
    UpdatedReq = Request#pending_request{status = escalated},
    NewPending = Pending#{RequestId => UpdatedReq},
    logger:info("Escalated human input request ~s", [RequestId]),
    {reply, ok, State#state{pending = NewPending}}.

%% @private Notify YAWL about a timed-out request.
-spec notify_timeout_to_yawl(#pending_request{}) -> ok.
notify_timeout_to_yawl(Request) ->
    case whereis(yawl_human_in_loop) of
        undefined -> ok;
        _Pid ->
            try
                yawl_human_in_loop:submit_approval(
                    Request#pending_request.request_id,
                    rejected,
                    #{reason => timeout}
                )
            catch _:_ -> ok
            end
    end.

%% @private Notify BeamAI about a timed-out request.
-spec notify_timeout_to_beamai(#pending_request{}) -> ok.
notify_timeout_to_beamai(Request) ->
    case whereis(beamai_yawl_bridge) of
        undefined -> ok;
        _Pid ->
            try
                case beamai_yawl_bridge:get_workflow_agent(
                    Request#pending_request.workflow_id) of
                    {ok, AgentPid} ->
                        AgentPid ! {human_input_timeout, #{
                            request_id => Request#pending_request.request_id,
                            task_id => Request#pending_request.task_id
                        }};
                    _ -> ok
                end
            catch _:_ -> ok
            end
    end.

%% @private Cancel a timeout timer safely.
-spec cancel_timeout(reference() | undefined) -> ok.
cancel_timeout(undefined) -> ok;
cancel_timeout(Ref) ->
    erlang:cancel_timer(Ref),
    ok.

%% @private Trim history list to max size.
-spec trim_history([map()], non_neg_integer()) -> [map()].
trim_history(History, MaxSize) when length(History) > MaxSize ->
    lists:sublist(History, MaxSize);
trim_history(History, _MaxSize) ->
    History.

%% @private Generate a unique request identifier.
-spec generate_request_id() -> binary().
generate_request_id() ->
    Rand = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<"hreq_", Ts/binary, "_", Rand/binary>>.
