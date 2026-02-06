%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL XES Logger - IEEE 1849-2016 XES Standard Event Logging
%%%
%%% This module provides comprehensive event logging for YAWL workflows
%%% using the IEEE 1849-2016 XES (eXtensible Event Stream) standard.
%%%
%%% Features:
%%% - XES log creation and management
%%% - Pattern execution event logging
%%% - Work item lifecycle tracking
%%% - Case/event recording
%%% - XES XML export for process mining tools
%%%
%%% XES Standard Compliance:
%%% - concept:name - Event/activity names
%%% - concept:instance - Instance identifiers
%%% - lifecycle:transition - Lifecycle states (start, complete)
%%% - time:timestamp - ISO 8601 timestamps
%%% - case:id - Case identifiers for trace grouping
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_xes_logger).
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

%% API exports - Log lifecycle
-export([
    stop/0,
    new_log/0,
    new_log/1,
    get_log/1,
    list_logs/0,
    delete_log/1
]).

%% API exports - Pattern event logging
-export([
    log_pattern_start/3,
    log_pattern_complete/4
]).

%% API exports - Work item logging
-export([
    log_workitem_start/3,
    log_workitem_complete/4
]).

%% API exports - Case logging
-export([
    log_case_start/2,
    log_case_complete/3
]).

%% API exports - Generic event logging
-export([
    log_event/4,
    log_event/5
]).

%% API exports - XES export
-export([
    export_xes/1,
    export_xes/2,
    export_xes_to_string/1
]).

-include_lib("kernel/include/logger.hrl").

%%====================================================================
%% Constants
%%====================================================================

-define(DEFAULT_OUTPUT_DIR, "xes_logs").
-define(SERVER, ?MODULE).

%%====================================================================
%% Type Definitions
%%====================================================================

-type log_id() :: binary().
-type trace_id() :: binary().
-type case_id() :: binary().
-type event_id() :: binary().
-type timestamp() :: integer().

-record(xes_log, {
    log_id :: log_id(),
    trace_id :: trace_id(),
    started_at :: timestamp(),
    events :: list(),
    metadata :: map()
}).

-record(xes_event, {
    event_id :: event_id(),
    timestamp :: timestamp(),
    case_id :: case_id() | undefined,
    concept :: map(),
    lifecycle :: map(),
    data :: map()
}).

-record(state, {
    logs :: #{log_id() => #xes_log{}},
    traces :: #{trace_id() => log_id()},
    next_event_id :: non_neg_integer(),
    output_dir :: string()
}).

%%====================================================================
%% API Functions - Log Lifecycle
%%====================================================================

%% @doc Start the XES logger with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Start the XES logger with a custom name.
-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(Name) ->
    gen_server:start_link(Name, ?MODULE, [], []).

%% @doc Stop the XES logger.
-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

%% @doc Create a new XES log with default metadata.
-spec new_log() -> {ok, log_id()}.
new_log() ->
    new_log(#{}).

%% @doc Create a new XES log with custom metadata.
-spec new_log(map()) -> {ok, log_id()}.
new_log(Metadata) ->
    gen_server:call(?SERVER, {new_log, Metadata}).

%% @doc Get a log by ID.
-spec get_log(log_id()) -> {ok, #xes_log{}} | {error, not_found}.
get_log(LogId) ->
    gen_server:call(?SERVER, {get_log, LogId}).

%% @doc List all logs.
-spec list_logs() -> [{log_id(), #xes_log{}}].
list_logs() ->
    gen_server:call(?SERVER, list_logs).

%% @doc Delete a log.
-spec delete_log(log_id()) -> ok | {error, not_found}.
delete_log(LogId) ->
    gen_server:call(?SERVER, {delete_log, LogId}).

%%====================================================================
%% API Functions - Pattern Event Logging
%%====================================================================

%% @doc Log pattern execution start.
-spec log_pattern_start(log_id(), binary(), binary()) -> ok.
log_pattern_start(LogId, PatternType, PatternId) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        concept = #{
            <<"concept:name">> => to_binary(PatternType),
            <<"concept:instance">> => to_binary(PatternId)
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"start">>},
        data = #{}
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%% @doc Log pattern execution completion.
-spec log_pattern_complete(log_id(), binary(), binary(), term()) -> ok.
log_pattern_complete(LogId, PatternType, PatternId, Result) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        concept = #{
            <<"concept:name">> => to_binary(PatternType),
            <<"concept:instance">> => to_binary(PatternId)
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"complete">>},
        data = #{<<"result">> => format_result(Result)}
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%%====================================================================
%% API Functions - Work Item Logging
%%====================================================================

%% @doc Log work item start.
-spec log_workitem_start(log_id(), binary(), binary()) -> ok.
log_workitem_start(LogId, WorkitemId, TaskId) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        concept = #{
            <<"concept:name">> => <<"Workitem">>,
            <<"concept:instance">> => to_binary(WorkitemId)
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"start">>},
        data = #{<<"task">> => to_binary(TaskId)}
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%% @doc Log work item completion.
-spec log_workitem_complete(log_id(), binary(), binary(), term()) -> ok.
log_workitem_complete(LogId, WorkitemId, TaskId, Result) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        concept = #{
            <<"concept:name">> => <<"Workitem">>,
            <<"concept:instance">> => to_binary(WorkitemId)
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"complete">>},
        data = #{
            <<"task">> => to_binary(TaskId),
            <<"result">> => format_result(Result)
        }
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%%====================================================================
%% API Functions - Case Logging
%%====================================================================

%% @doc Log case start.
-spec log_case_start(log_id(), case_id()) -> ok.
log_case_start(LogId, CaseId) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        case_id = CaseId,
        concept = #{
            <<"concept:name">> => <<"CaseStart">>
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"start">>},
        data = #{}
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%% @doc Log case completion with statistics.
-spec log_case_complete(log_id(), case_id(), map()) -> ok.
log_case_complete(LogId, CaseId, Stats) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        case_id = CaseId,
        concept = #{
            <<"concept:name">> => <<"CaseComplete">>
        },
        lifecycle = #{<<"lifecycle:transition">> => <<"complete">>},
        data = Stats
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%%====================================================================
%% API Functions - Generic Event Logging
%%====================================================================

%% @doc Log a generic event (without case ID).
-spec log_event(log_id(), binary(), binary(), map()) -> ok.
log_event(LogId, ConceptName, LifecycleTransition, Data) ->
    log_event(LogId, ConceptName, LifecycleTransition, Data, undefined).

%% @doc Log a generic event with optional case ID.
-spec log_event(log_id(), binary(), binary(), map(), binary() | undefined) -> ok.
log_event(LogId, ConceptName, LifecycleTransition, Data, CaseId) ->
    Timestamp = erlang:system_time(millisecond),
    EventId = generate_event_id(),
    Event = #xes_event{
        event_id = EventId,
        timestamp = Timestamp,
        case_id = CaseId,
        concept = #{
            <<"concept:name">> => to_binary(ConceptName)
        },
        lifecycle = #{
            <<"lifecycle:transition">> => to_binary(LifecycleTransition)
        },
        data = Data
    },
    gen_server:cast(?SERVER, {add_event, LogId, Event}).

%%====================================================================
%% API Functions - XES Export
%%====================================================================

%% @doc Export log to XES XML format with default output directory.
-spec export_xes(log_id()) -> {ok, file:filename()} | {error, term()}.
export_xes(LogId) ->
    export_xes(LogId, ?DEFAULT_OUTPUT_DIR).

%% @doc Export log to XES XML format with specified output directory.
-spec export_xes(log_id(), string()) -> {ok, file:filename()} | {error, term()}.
export_xes(LogId, OutputDir) ->
    gen_server:call(?SERVER, {export_xes, LogId, OutputDir}).

%% @doc Export log to XES XML format as a string (in-memory).
-spec export_xes_to_string(log_id()) -> {ok, binary()} | {error, term()}.
export_xes_to_string(LogId) ->
    gen_server:call(?SERVER, {export_xes_string, LogId}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    OutputDir = application:get_env(a2a_erl, xes_output_dir, ?DEFAULT_OUTPUT_DIR),
    %% Ensure output directory exists
    ok = filelib:ensure_dir(filename:join([OutputDir, "dummy.log"])),
    {ok, #state{
        logs = #{},
        traces = #{},
        next_event_id = 1,
        output_dir = OutputDir
    }}.

%% @private
handle_call({new_log, Metadata}, _From, State) ->
    LogId = generate_log_id(),
    TraceId = generate_trace_id(),
    Log = #xes_log{
        log_id = LogId,
        trace_id = TraceId,
        started_at = erlang:system_time(millisecond),
        events = [],
        metadata = Metadata
    },
    State1 = State#state{
        logs = maps:put(LogId, Log, State#state.logs),
        traces = maps:put(TraceId, LogId, State#state.traces)
    },
    ?LOG(info, "Created new XES log: ~p", [LogId]),
    {reply, {ok, LogId}, State1};

handle_call({get_log, LogId}, _From, State) ->
    case maps:get(LogId, State#state.logs, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Log -> {reply, {ok, Log}, State}
    end;

handle_call(list_logs, _From, State) ->
    LogsList = maps:to_list(State#state.logs),
    {reply, LogsList, State};

handle_call({delete_log, LogId}, _From, State) ->
    case maps:get(LogId, State#state.logs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Log ->
            State1 = State#state{
                logs = maps:remove(LogId, State#state.logs),
                traces = maps:remove(Log#xes_log.trace_id, State#state.traces)
            },
            ?LOG(info, "Deleted XES log: ~p", [LogId]),
            {reply, ok, State1}
    end;

handle_call({export_xes, LogId, OutputDir}, _From, State) ->
    case maps:get(LogId, State#state.logs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Log ->
            XESContent = yawl_xes_formatter:format_log(Log),
            FileName = filename:join([OutputDir, binary_to_list(LogId) ++ ".xes"]),
            ok = filelib:ensure_dir(FileName),
            case file:write_file(FileName, XESContent) of
                ok ->
                    ?LOG(info, "Exported XES log to: ~p", [FileName]),
                    {reply, {ok, FileName}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({export_xes_string, LogId}, _From, State) ->
    case maps:get(LogId, State#state.logs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Log ->
            XESContent = yawl_xes_formatter:format_log(Log),
            {reply, {ok, XESContent}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, bad_msg}, State}.

%% @private
handle_cast({add_event, LogId, Event}, State) ->
    case maps:get(LogId, State#state.logs, undefined) of
        undefined ->
            ?LOG(warning, "Attempted to add event to non-existent log: ~p", [LogId]),
            {noreply, State};
        Log ->
            Log1 = Log#xes_log{events = Log#xes_log.events ++ [Event]},
            State1 = State#state{logs = maps:put(LogId, Log1, State#state.logs)},
            {noreply, State1}
    end;

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
%% Generate a unique log ID.
-spec generate_log_id() -> binary().
generate_log_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"log_", (integer_to_binary(Timestamp))/binary>>.

%% @private
%% Generate a unique trace ID.
-spec generate_trace_id() -> binary().
generate_trace_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"trace_", (integer_to_binary(Timestamp))/binary>>.

%% @private
%% Generate a unique event ID.
-spec generate_event_id() -> binary().
generate_event_id() ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<"event_", (integer_to_binary(Timestamp))/binary>>.

%% @private
%% Convert a term to binary.
-spec to_binary(term()) -> binary().
to_binary(Binary) when is_binary(Binary) -> Binary;
to_binary(Integer) when is_integer(Integer) -> integer_to_binary(Integer);
to_binary(Float) when is_float(Float) -> float_to_binary(Float, [{decimals, 6}, compact]);
to_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_binary(List) when is_list(List) -> list_to_binary(List);
to_binary(Term) -> list_to_binary(io_lib:format("~p", [Term])).

%% @private
%% Format a result term for storage in XES data.
-spec format_result(term()) -> binary().
format_result(ok) -> <<"ok">>;
format_result({ok, Result}) -> format_result(Result);
format_result({error, Reason}) -> <<"error:", (to_binary(Reason))/binary>>;
format_result(Result) -> to_binary(Result).
