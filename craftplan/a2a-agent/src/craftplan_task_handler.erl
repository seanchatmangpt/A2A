%%% @doc Craftplan A2A Task Handler
%%% Handles individual task execution using a2a_handler behaviour

-module(craftplan_task_handler).
-behaviour(a2a_handler).

%% API
-export([start/3, cancel/1, send_message/2]).
-export([init/2, process/2, handle_message/2, terminate/2]).

-include("a2a.hrl").

-record(state, {
    task_id :: binary(),
    task_type :: binary(),
    params :: map(),
    bridge :: pid() | undefined,
    artifacts :: list(map()),
    messages :: list(map()),
    a2a_server :: pid()
}).

%%====================================================================
%% API
%%====================================================================

start(TaskId, TaskType, Params) ->
    {ok, Pid} = a2a_task_sup:start_child(?MODULE, [TaskId, TaskType, Params]),
    Pid.

cancel(Pid) ->
    gen_server:call(Pid, cancel).

send_message(Pid, Message) ->
    gen_server:call(Pid, {message, Message}).

%%====================================================================
%% a2a_handler callbacks
%%====================================================================

init(_Task, Message) ->
    %% Parse task from message
    #{<<"task_id">> := TaskId, <<"task_type">> := TaskType, <<"params">> := Params} = Message,

    %% Get A2A bridge for skill invocation
    {ok, Bridge} = craftplan_a2a_bridge:start_link(),

    State = #state{
        task_id = TaskId,
        task_type = TaskType,
        params = Params,
        bridge = Bridge,
        artifacts = [],
        messages = [],
        a2a_server = whereis(craftplan_a2a_server)
    },

    {ok, State}.

process(Task, State) ->
    TaskType = State#state.task_type,
    Params = State#state.params,

    io:format("Processing task ~p of type ~p~n", [State#state.task_id, TaskType]),

    %% Route task to appropriate handler based on type
    Result = case TaskType of
        <<"customer_management">> -> handle_customer_task(Params, State);
        <<"order_management">> -> handle_order_task(Params, State);
        <<"inventory_management">> -> handle_inventory_task(Params, State);
        <<"production_planning">> -> handle_production_task(Params, State);
        <<"analytics">> -> handle_analytics_task(Params, State);
        <<"shipping">> -> handle_shipping_task(Params, State);
        _ -> {error, {unknown_task_type, TaskType}}
    end,

    case Result of
        {ok, Artifacts} ->
            NewState = State#state{artifacts = Artifacts},
            {ok, #{artifacts => Artifacts}, NewState};
        {input_required, Prompt} ->
            {input_required, Prompt, State};
        {error, Reason} ->
            {error, Reason, State}
    end.

handle_message(Message, State) ->
    %% Handle incoming messages during task execution
    NewMessages = [Message | State#state.messages],
    {continue, State#state{messages = NewMessages}}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Task Handlers
%%====================================================================

%% Handle customer management tasks
handle_customer_task(Params, _State) ->
    Operation = maps:get(<<"operation">>, Params, <<"list">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"customer_management">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"customer_result">>,
                <<"operation">> => Operation,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.

%% Handle order management tasks
handle_order_task(Params, _State) ->
    Operation = maps:get(<<"operation">>, Params, <<"list">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"order_management">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"order_result">>,
                <<"operation">> => Operation,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.

%% Handle inventory management tasks
handle_inventory_task(Params, _State) ->
    Operation = maps:get(<<"operation">>, Params, <<"list_products">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"inventory_management">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"inventory_result">>,
                <<"operation">> => Operation,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.

%% Handle production planning tasks
handle_production_task(Params, _State) ->
    Operation = maps:get(<<"operation">>, Params, <<"list_orders">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"production_planning">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"production_result">>,
                <<"operation">> => Operation,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.

%% Handle analytics tasks
handle_analytics_task(Params, _State) ->
    ReportType = maps:get(<<"report_type">>, Params, <<"sales_summary">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"analytics">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"analytics_result">>,
                <<"report_type">> => ReportType,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.

%% Handle shipping tasks
handle_shipping_task(Params, _State) ->
    Operation = maps:get(<<"operation">>, Params, <<"track">>),
    case craftplan_a2a_bridge:handle_a2a_task(<<"shipping">>, Params) of
        {ok, Result} ->
            {ok, [#{
                <<"type">> => <<"shipping_result">>,
                <<"operation">> => Operation,
                <<"data">> => Result
            }]};
        {error, Reason} ->
            {error, Reason}
    end.
