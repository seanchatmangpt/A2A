%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Adapter
%%%
%%% This module provides a high-level adapter interface for configuring
%%% and managing XES logging for YAWL workflow events. It serves as the
%%% main API for integrating XES logging into the YAWL-A2A system.
%%%
%%% ## Features
%%%
%%% - Simple start_link initialization
%%% - Workflow-specific event subscription
%%% - Event to XES format conversion
%%% - Configurable output destinations (file, stdio, callback)
%%% - Integration with yawl_event_bridge
%%%
%%% ## Usage
%%%
%%% ### Basic Usage
%%%
%%% ```erlang
%%% %% Start the adapter
%%% {ok, Pid} = yawl_xes_adapter:start_link().
%%%
%%% %% Subscribe to a specific workflow
%%% ok = yawl_xes_adapter:subscribe_to_workflow(<<"order_wf_123">>).
%%%
%%% %% Configure XES output to file
%%% ok = yawl_xes_adapter:configure_xes_output(#{
%%%     type => file,
%%%     path => "/var/log/yawl/traces.xes"
%%% }).
%%%
%%% %% Convert an event to XES format
%%% XES = yawl_xes_adapter:convert_event_to_xes(#{
%%%     event_type => workitem_created,
%%%     workitem_id => <<"wi_123">>,
%%%     timestamp => erlang:monotonic_time(millisecond)
%%% }).
%%% '''
%%%
%%% ### Advanced Usage
%%%
%%% ```erlang
%%% %% Start with custom configuration
%%% {ok, Pid} = yawl_xes_adapter:start_link(#{
%%%     output_type => file,
%%%     output_path => "/var/log/yawl/traces.xes",
%%%     buffer_size => 500,
%%%     filter => fun(EventType, _Data) ->
%%%         %% Only log workitem events
%%%         lists:prefix(<<"workitem_">>, atom_to_binary(EventType))
%%%     end
%%% }).
%%%
%%% %% Subscribe to multiple workflows
%%% lists:foreach(fun(WfId) ->
%%%     yawl_xes_adapter:subscribe_to_workflow(WfId)
%%% end, [<<"wf1">>, <<"wf2">>, <<"wf3">>]).
%%%
%%% %% Export a completed trace
%%% {ok, XESXml} = yawl_xes_adapter:export_trace(<<"wf1">>).
%%% '''
%%%
%%% ## Integration Instructions
%%%
%%% To integrate the XES adapter into your application:
%%%
%%% 1. **Add to supervision tree** (in a2a_erl_sup.erl):
%%%
%%% ```erlang
%%% %% After yawl_a2a_events
%%% #{
%%%     id => yawl_xes_adapter,
%%%     start => {yawl_xes_adapter, start_link, []},
%%%     restart => permanent,
%%%     shutdown => 5000,
%%%     type => worker,
%%%     modules => [yawl_xes_adapter]
%%% }
%%% '''
%%%
%%% 2. **Add to application file** (in a2a_erl.app.src):
%%%
%%% ```erlang
%%% {applications, [kernel, stdlib, ...]},
%%% {mod, {a2a_erl_app, []}},
%%% {modules, [
%%%     ...,
%%%     yawl_event_bridge,
%%%     yawl_xes_adapter
%%% ]}
%%% '''
%%%
%%% 3. **Configure output** (optional, in app.config):
%%%
%%% ```erlang
%%% {yawl_xes_adapter, [
%%%     {output_type, file},
%%%     {output_path, "/var/log/yawl/traces.xes"},
%%%     {buffer_size, 100},
%%%     {auto_flush, true}
%%% ]}
%%% '''
%%%
%%% ## XES Format Compliance
%%%
%%% The adapter generates XES-compliant XML following the XES 1.0 standard:
%%% - Uses standard XES extensions (Lifecycle, Concept, Time)
%%% - Proper trace and event hierarchy
%%% - ISO 8601 timestamp formatting
%%% - String, integer, and date attribute types
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_adapter).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    start_link/1,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% Internal exports
-export([
    xml_header/0
]).

%% API - Lifecycle
-export([
    stop/0,
    get_status/0,
    reset/0
]).

%% API - Subscription
-export([
    subscribe_to_workflow/1,
    subscribe_to_workflows/1,
    unsubscribe_from_workflow/1,
    unsubscribe_from_all/0,
    list_subscriptions/0
]).

%% API - Configuration
-export([
    configure_xes_output/1,
    set_output_type/2,
    set_output_path/1,
    set_buffer_size/1,
    set_event_filter/1,
    get_configuration/0
]).

%% API - Event conversion
-export([
    convert_event_to_xes/1,
    convert_event_to_xes/2,
    convert_events_to_xes/1,
    batch_convert_events/1
]).

%% API - Export
-export([
    export_trace/1,
    export_trace/2,
    export_all_traces/0,
    export_all_traces/1,
    export_to_file/2,
    flush_buffer/0
]).

%% API - Query
-export([
    get_trace_summary/1,
    list_traces/0,
    get_statistics/0,
    get_trace_count/0
]).

-include("yawl_types.hrl").
-include("a2a.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    %% Bridge process
    bridge_pid :: pid() | undefined,
    %% Current subscriptions
    subscriptions :: [binary()],
    %% Output configuration
    output_type :: file | stdio | callback,
    output_path :: binary() | undefined,
    callback_function :: function() | undefined,
    buffer_size :: integer(),
    event_filter :: function() | undefined,
    %% Statistics
    stats :: map()
}).

-type state() :: #state{}.
-type config() :: #{
    output_type => file | stdio | callback,
    output_path => binary(),
    buffer_size => integer(),
    filter => function()
}.
-type event_data() :: #{
    event_type => atom(),
    timestamp => integer(),
    workflow_id => binary(),
    workitem_id => binary(),
    resource => binary() | undefined
}.

%%====================================================================
%% API Functions - Lifecycle
%%====================================================================

%% @doc Start the adapter with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the adapter with custom configuration.
-spec start_link(config()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Stop the adapter.
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Get the current adapter status.
-spec get_status() -> map().
get_status() ->
    gen_server:call(?MODULE, get_status).

%% @doc Reset the adapter (clear all subscriptions and traces).
-spec reset() -> ok.
reset() ->
    gen_server:call(?MODULE, reset).

%%====================================================================
%% API Functions - Subscription
%%====================================================================

%% @doc Subscribe to events for a specific workflow.
-spec subscribe_to_workflow(binary()) -> ok | {error, term()}.
subscribe_to_workflow(WorkflowId) when is_binary(WorkflowId) ->
    gen_server:call(?MODULE, {subscribe, WorkflowId}).

%% @doc Subscribe to multiple workflows.
-spec subscribe_to_workflows([binary()]) -> {ok, [binary()]} | {error, term()}.
subscribe_to_workflows(WorkflowIds) when is_list(WorkflowIds) ->
    gen_server:call(?MODULE, {subscribe_many, WorkflowIds}).

%% @doc Unsubscribe from a specific workflow.
-spec unsubscribe_from_workflow(binary()) -> ok.
unsubscribe_from_workflow(WorkflowId) when is_binary(WorkflowId) ->
    gen_server:cast(?MODULE, {unsubscribe, WorkflowId}).

%% @doc Unsubscribe from all workflows.
-spec unsubscribe_from_all() -> ok.
unsubscribe_from_all() ->
    gen_server:cast(?MODULE, unsubscribe_all).

%% @doc List all active subscriptions.
-spec list_subscriptions() -> [binary()].
list_subscriptions() ->
    gen_server:call(?MODULE, list_subscriptions).

%%====================================================================
%% API Functions - Configuration
%%====================================================================

%% @doc Configure XES output destination.
-spec configure_xes_output(config()) -> ok | {error, term()}.
configure_xes_output(Config) when is_map(Config) ->
    gen_server:call(?MODULE, {configure_output, Config}).

%% @doc Set output type (file, stdio, or callback).
-spec set_output_type(atom(), binary() | function()) -> ok | {error, term()}.
set_output_type(Type, Param) ->
    gen_server:call(?MODULE, {set_output_type, Type, Param}).

%% @doc Set output file path.
-spec set_output_path(binary()) -> ok | {error, term()}.
set_output_path(Path) when is_binary(Path) ->
    gen_server:call(?MODULE, {set_output_path, Path}).

%% @doc Set buffer size for batch writing.
-spec set_buffer_size(integer()) -> ok | {error, term()}.
set_buffer_size(Size) when is_integer(Size), Size > 0 ->
    gen_server:call(?MODULE, {set_buffer_size, Size}).

%% @doc Set event filter function.
-spec set_event_filter(function()) -> ok | {error, term()}.
set_event_filter(FilterFun) when is_function(FilterFun, 2) ->
    gen_server:call(?MODULE, {set_filter, FilterFun}).

%% @doc Get current configuration.
-spec get_configuration() -> map().
get_configuration() ->
    gen_server:call(?MODULE, get_configuration).

%%====================================================================
%% API Functions - Event Conversion
%%====================================================================

%% @doc Convert an event map to XES format (uses bridge configuration).
-spec convert_event_to_xes(event_data()) -> {ok, binary()} | {error, term()}.
convert_event_to_xes(EventData) when is_map(EventData) ->
    gen_server:call(?MODULE, {convert_event, EventData}).

%% @doc Convert an event to XES with custom options.
-spec convert_event_to_xes(event_data(), map()) -> {ok, binary()} | {error, term()}.
convert_event_to_xes(EventData, Options) when is_map(EventData), is_map(Options) ->
    EventType = maps:get(event_type, EventData),
    Timestamp = maps:get(timestamp, EventData, erlang:monotonic_time(millisecond)),
    Activity = event_type_to_activity(EventType),
    Lifecycle = event_type_to_lifecycle(EventType),
    TimestampStr = format_timestamp_xes(Timestamp),
    Resource = case maps:get(resource, EventData, maps_get(resource_id, EventData, undefined)) of
        undefined -> <<>>;
        R -> <<" <string key=\"org:resource\" value=\"", R/binary, "\"/>">>
    end,

    XES = <<"
        <event>
            <string key=\"concept:name\" value=\"", Activity/binary, "\"/>
            <string key=\"lifecycle:transition\" value=\"", Lifecycle/binary, "\"/>
            <date key=\"time:timestamp\" value=\"", TimestampStr/binary, "\"/>",
            Resource/binary, "
        </event>
    ">>,
    {ok, XES}.

%% @doc Convert multiple events to XES format.
-spec convert_events_to_xes([event_data()]) -> {ok, binary()} | {error, term()}.
convert_events_to_xes(Events) when is_list(Events) ->
    gen_server:call(?MODULE, {convert_events, Events}).

%% @doc Batch convert events with progress callback.
-spec batch_convert_events([event_data()]) -> {ok, [binary()], map()} | {error, term()}.
batch_convert_events(Events) when is_list(Events) ->
    gen_server:call(?MODULE, {batch_convert, Events}).

%%====================================================================
%% API Functions - Export
%%====================================================================

%% @doc Export a specific workflow trace.
-spec export_trace(binary()) -> {ok, binary()} | {error, term()}.
export_trace(WorkflowId) ->
    gen_server:call(?MODULE, {export_trace, WorkflowId}).

%% @doc Export a trace with custom format options.
-spec export_trace(binary(), map()) -> {ok, binary()} | {error, term()}.
export_trace(WorkflowId, Options) when is_map(Options) ->
    gen_server:call(?MODULE, {export_trace, WorkflowId, Options}).

%% @doc Export all traces.
-spec export_all_traces() -> {ok, binary()} | {error, term()}.
export_all_traces() ->
    gen_server:call(?MODULE, export_all_traces).

%% @doc Export all traces with custom options.
-spec export_all_traces(map()) -> {ok, binary()} | {error, term()}.
export_all_traces(Options) when is_map(Options) ->
    gen_server:call(?MODULE, {export_all_traces, Options}).

%% @doc Export trace directly to a file.
-spec export_to_file(binary(), binary()) -> ok | {error, term()}.
export_to_file(WorkflowId, FilePath) ->
    gen_server:call(?MODULE, {export_to_file, WorkflowId, FilePath}).

%% @doc Flush the event buffer.
-spec flush_buffer() -> ok | {error, term()}.
flush_buffer() ->
    gen_server:call(?MODULE, flush_buffer).

%%====================================================================
%% API Functions - Query
%%====================================================================

%% @doc Get summary statistics for a trace.
-spec get_trace_summary(binary()) -> {ok, map()} | {error, term()}.
get_trace_summary(WorkflowId) ->
    gen_server:call(?MODULE, {trace_summary, WorkflowId}).

%% @doc List all available traces.
-spec list_traces() -> {ok, [binary()]}.
list_traces() ->
    gen_server:call(?MODULE, list_traces).

%% @doc Get overall XES adapter statistics.
-spec get_statistics() -> map().
get_statistics() ->
    gen_server:call(?MODULE, get_statistics).

%% @doc Get the number of active traces.
-spec get_trace_count() -> non_neg_integer().
get_trace_count() ->
    gen_server:call(?MODULE, get_trace_count).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Config) ->
    %% Start or find the event bridge
    BridgePid = case whereis(yawl_event_bridge) of
        undefined ->
            case yawl_event_bridge:start_link(Config) of
                {ok, Pid} -> Pid;
                {error, {already_started, Pid}} -> Pid
            end;
        Pid ->
            Pid
    end,

    State = #state{
        bridge_pid = BridgePid,
        subscriptions = [],
        output_type = maps_get(output_type, Config, stdio),
        output_path = maps_get(output_path, Config, undefined),
        callback_function = maps_get(callback, Config, undefined),
        buffer_size = maps_get(buffer_size, Config, 100),
        event_filter = maps_get(filter, Config, undefined),
        stats = init_adapter_stats()
    },

    %% Apply initial configuration
    case maps_get(output_type, Config, undefined) of
        undefined ->
            ok;
        Type ->
            OutputConfig = build_output_config(Type, State),
            yawl_event_bridge:configure_output(OutputConfig)
    end,

    %% Set filter if provided
    case maps_get(filter, Config, undefined) of
        undefined -> ok;
        FilterFun -> yawl_event_bridge:configure_filter(FilterFun)
    end,

    {ok, State}.

%% @private
handle_call(get_status, _From, State) ->
    BridgeAlive = case State#state.bridge_pid of
        undefined -> false;
        Pid -> is_process_alive(Pid)
    end,
    Status = #{
        bridge_alive => BridgeAlive,
        subscriptions => length(State#state.subscriptions),
        output_type => State#state.output_type,
        output_path => State#state.output_path,
        buffer_size => State#state.buffer_size,
        has_filter => State#state.event_filter =/= undefined
    },
    {reply, Status, State};

handle_call(reset, _From, State) ->
    %% Unsubscribe from all workflows
    lists:foreach(fun(WfId) ->
        yawl_event_bridge:unsubscribe_from_workflow(WfId)
    end, State#state.subscriptions),

    NewState = State#state{
        subscriptions = [],
        stats = init_adapter_stats()
    },
    {reply, ok, NewState};

handle_call({subscribe, WorkflowId}, _From, State) ->
    case yawl_event_bridge:subscribe_to_workflow(WorkflowId) of
        ok ->
            NewSubs = ordsets:add_element(WorkflowId, State#state.subscriptions),
            {reply, ok, State#state{subscriptions = NewSubs}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({subscribe_many, WorkflowIds}, _From, State) ->
    Results = lists:map(fun(WfId) ->
        case yawl_event_bridge:subscribe_to_workflow(WfId) of
            ok -> {ok, WfId};
            {error, Reason} -> {error, WfId, Reason}
        end
    end, WorkflowIds),

    {Success, Failures} = lists:partition(fun
        ({ok, _}) -> true;
        (_) -> false
    end, Results),

    SuccessIds = [Id || {ok, Id} <- Success],
    NewSubs = lists:foldl(fun ordsets:add_element/2, State#state.subscriptions, SuccessIds),

    case Failures of
        [] ->
            {reply, {ok, SuccessIds}, State#state{subscriptions = NewSubs}};
        _ ->
            {reply, {error, {partial_success, SuccessIds, Failures}}, State#state{subscriptions = NewSubs}}
    end;

handle_call(list_subscriptions, _From, State) ->
    {reply, State#state.subscriptions, State};

handle_call({configure_output, Config}, _From, State) ->
    OutputType = maps_get(type, Config, State#state.output_type),
    NewState = case OutputType of
        file ->
            Path = maps_get(path, Config, State#state.output_path),
            State#state{output_type = file, output_path = Path};
        stdio ->
            State#state{output_type = stdio};
        callback ->
            Callback = maps_get(callback, Config, State#state.callback_function),
            State#state{output_type = callback, callback_function = Callback}
    end,

    OutputConfig = build_output_config(OutputType, NewState),
    case yawl_event_bridge:configure_output(OutputConfig) of
        ok ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({set_output_type, Type, Param}, _From, State) ->
    OutputConfig = case Type of
        file when is_binary(Param) ->
            State#state{output_type = file, output_path = Param};
        stdio ->
            State#state{output_type = stdio};
        callback when is_function(Param, 1) ->
            State#state{output_type = callback, callback_function = Param};
        _ ->
            State
    end,
    NewConfig = build_output_config(Type, OutputConfig),
    case yawl_event_bridge:configure_output(NewConfig) of
        ok ->
            {reply, ok, OutputConfig};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({set_output_path, Path}, _From, State) ->
    OutputConfig = #{
        type => file,
        path => Path,
        buffer_size => State#state.buffer_size,
        auto_flush => true
    },
    case yawl_event_bridge:configure_output(OutputConfig) of
        ok ->
            {reply, ok, State#state{output_type = file, output_path = Path}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({set_buffer_size, Size}, _From, State) ->
    OutputConfig = build_output_config(State#state.output_type, State),
    NewConfig = OutputConfig#{buffer_size => Size},
    case yawl_event_bridge:configure_output(NewConfig) of
        ok ->
            {reply, ok, State#state{buffer_size = Size}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({set_filter, FilterFun}, _From, State) ->
    case yawl_event_bridge:configure_filter(FilterFun) of
        ok ->
            {reply, ok, State#state{event_filter = FilterFun}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_configuration, _From, State) ->
    Config = #{
        output_type => State#state.output_type,
        output_path => State#state.output_path,
        buffer_size => State#state.buffer_size,
        has_callback => State#state.callback_function =/= undefined,
        has_filter => State#state.event_filter =/= undefined
    },
    {reply, Config, State};

handle_call({convert_event, EventData}, _From, State) ->
    {ok, XES} = convert_event_to_xes(EventData, #{}),
    {reply, {ok, XES}, State};

handle_call({convert_events, Events}, _From, State) ->
    XESList = [case convert_event_to_xes(E, #{}) of
        {ok, X} -> X;
        {error, _} -> <<>>
    end || E <- Events],
    XmlHeader = xml_header(),
    Combined = <<XmlHeader/binary, "<log>", (binary:list_to_bin(XESList))/binary, "</log>">>,
    {reply, {ok, Combined}, State};

handle_call({batch_convert, Events}, _From, State) ->
    {XESList, Stats} = lists:mapfoldl(fun(E, AccStats) ->
        case convert_event_to_xes(E, #{}) of
            {ok, X} ->
                {X, AccStats#{converted => maps:get(converted, AccStats, 0) + 1}};
            {error, _} ->
                {<<>>, AccStats#{failed => maps:get(failed, AccStats, 0) + 1}}
        end
    end, #{}, Events),
    {reply, {ok, XESList, Stats}, State};

handle_call({export_trace, WorkflowId}, _From, State) ->
    case yawl_event_bridge:export_trace(WorkflowId) of
        {ok, XES} ->
            {reply, {ok, XES}, update_stats(export, State)};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({export_trace, WorkflowId, Options}, _From, State) ->
    Format = maps_get(format, Options, xml),
    case yawl_event_bridge:export_trace(WorkflowId) of
        {ok, XES} when Format =:= xml ->
            {reply, {ok, XES}, update_stats(export, State)};
        {ok, _XES} when Format =:= json ->
            %% JSON conversion not yet implemented, return error
            {reply, {error, json_format_not_supported}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(export_all_traces, _From, State) ->
    case yawl_event_bridge:export_all_traces() of
        {ok, XES} ->
            {reply, {ok, XES}, update_stats(export_all, State)};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({export_all_traces, Options}, _From, State) ->
    Format = maps_get(format, Options, xml),
    case yawl_event_bridge:export_all_traces() of
        {ok, XES} when Format =:= xml ->
            {reply, {ok, XES}, update_stats(export_all, State)};
        {ok, _XES} when Format =:= json ->
            %% JSON conversion not yet implemented, return error
            {reply, {error, json_format_not_supported}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({export_to_file, WorkflowId, FilePath}, _From, State) ->
    case yawl_event_bridge:export_trace(WorkflowId) of
        {ok, XES} ->
            case file:write_file(FilePath, XES) of
                ok ->
                    {reply, ok, update_stats(export, State)};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(flush_buffer, _From, State) ->
    %% Force flush via bridge
    case yawl_event_bridge:export_all_traces() of
        {ok, _} ->
            {reply, ok, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({trace_summary, WorkflowId}, _From, State) ->
    case yawl_event_bridge:get_trace_summary(WorkflowId) of
        {ok, Summary} ->
            {reply, {ok, Summary}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(list_traces, _From, State) ->
    {reply, {ok, State#state.subscriptions}, State};

handle_call(get_statistics, _From, State) ->
    BridgeStats = yawl_event_bridge:get_statistics(),
    CombinedStats = maps:merge(State#state.stats, BridgeStats),
    {reply, CombinedStats, State};

handle_call(get_trace_count, _From, State) ->
    {reply, length(State#state.subscriptions), State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({unsubscribe, WorkflowId}, State) ->
    yawl_event_bridge:unsubscribe_from_workflow(WorkflowId),
    NewSubs = lists:delete(WorkflowId, State#state.subscriptions),
    {noreply, State#state{subscriptions = NewSubs}};

handle_cast(unsubscribe_all, State) ->
    lists:foreach(fun(WfId) ->
        yawl_event_bridge:unsubscribe_from_workflow(WfId)
    end, State#state.subscriptions),
    {noreply, State#state{subscriptions = []}};

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
event_type_to_activity(workflow_started) -> <<"WorkflowStarted">>;
event_type_to_activity(workflow_completed) -> <<"WorkflowCompleted">>;
event_type_to_activity(workflow_failed) -> <<"WorkflowFailed">>;
event_type_to_activity(workflow_cancelled) -> <<"WorkflowCancelled">>;
event_type_to_activity(workitem_created) -> <<"WorkitemCreated">>;
event_type_to_activity(workitem_allocated) -> <<"WorkitemAllocated">>;
event_type_to_activity(workitem_started) -> <<"WorkitemStarted">>;
event_type_to_activity(workitem_completed) -> <<"WorkitemCompleted">>;
event_type_to_activity(workitem_failed) -> <<"WorkitemFailed">>;
event_type_to_activity(workitem_cancelled) -> <<"WorkitemCancelled">>;
event_type_to_activity(task_created) -> <<"TaskCreated">>;
event_type_to_activity(task_updated) -> <<"TaskUpdated">>;
event_type_to_activity(task_completed) -> <<"TaskCompleted">>;
event_type_to_activity(task_failed) -> <<"TaskFailed">>;
event_type_to_activity(task_cancelled) -> <<"TaskCancelled">>;
event_type_to_activity(state_changed) -> <<"StateChanged">>;
event_type_to_activity(checkpoint_created) -> <<"CheckpointCreated">>;
event_type_to_activity(checkpoint_restored) -> <<"CheckpointRestored">>;
event_type_to_activity(artifact_update) -> <<"ArtifactUpdated">>;
event_type_to_activity(mapping_created) -> <<"MappingCreated">>;
event_type_to_activity(mapping_removed) -> <<"MappingRemoved">>;
event_type_to_activity(sync_completed) -> <<"SyncCompleted">>;
event_type_to_activity(sync_failed) -> <<"SyncFailed">>;
event_type_to_activity(_) -> <<"Unknown">>.

%% @private
event_type_to_lifecycle(EventType) ->
    case EventType of
        workflow_started -> <<"start">>;
        workflow_completed -> <<"complete">>;
        workflow_failed -> <<"complete">>;
        workflow_cancelled -> <<"withdraw">>;
        workitem_created -> <<"schedule">>;
        workitem_allocated -> <<"assign">>;
        workitem_started -> <<"start">>;
        workitem_completed -> <<"complete">>;
        workitem_failed -> <<"complete">>;
        workitem_cancelled -> <<"withdraw">>;
        task_created -> <<"schedule">>;
        task_completed -> <<"complete">>;
        task_failed -> <<"complete">>;
        task_cancelled -> <<"withdraw">>;
        _ -> <<"unknown">>
    end.

%% @private
format_timestamp_xes(Millis) ->
    Seconds = Millis div 1000,
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:system_time_to_universal_time(Seconds, second),
    Ms = Millis rem 1000,
    lists:flatten(io_lib:format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.~3.10.0BZ",
        [Year, Month, Day, Hour, Minute, Second, Ms])).

%% @private
build_output_config(stdio, _State) ->
    #{type => stdio, buffer_size => 100, auto_flush => true};
build_output_config(file, State) ->
    #{type => file, path => State#state.output_path, buffer_size => State#state.buffer_size, auto_flush => true};
build_output_config(callback, State) ->
    #{type => callback, callback => State#state.callback_function, buffer_size => State#state.buffer_size, auto_flush => true}.

%% @private
init_adapter_stats() ->
    #{
        started_at => erlang:monotonic_time(millisecond),
        exports => 0,
        conversions => 0
    }.

%% @private
update_stats(export, State) ->
    Stats = State#state.stats,
    State#state{stats = Stats#{exports => maps_get(exports, Stats, 0) + 1}};
update_stats(export_all, State) ->
    Stats = State#state.stats,
    State#state{stats = Stats#{exports => maps_get(exports, Stats, 0) + 1}};
update_stats(_, State) ->
    State.

%% @private
xml_header() ->
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>">>.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
