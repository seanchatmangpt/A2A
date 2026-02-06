%%%-------------------------------------------------------------------
%%% @doc
%%% Claude Code Headless Integration Module
%%%
%%% This module integrates Claude Code's Agent SDK for programmatic
%%% LLM capabilities within YAWL workflows, enabling:
%%% - Headless LLM generation from CLI
%%% - Structured JSON output with schemas
%%% - Streaming responses
%%% - Tool approval workflows
%%% - Session management for multi-turn conversations
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_claude_headless).
-author("A2A Team").

-behaviour(gen_server).

%% API exports
-export([
    start_link/0,
    start_link/1,

    %% LLM Generation
    llm_generate/1,
    llm_generate/2,
    llm_generate_with_schema/2,

    %% Streaming
    llm_generate_streaming/2,

    %% Human-in-the-loop
    request_human_approval/2,
    submit_human_feedback/3,

    %% Session Management
    create_session/0,
    continue_session/1,
    get_session_history/1,

    %% Tool Control
    set_allowed_tools/1,

    %% System Prompt Control
    set_system_prompt/1,
    append_system_prompt/1
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
    claude_bin = "claude" :: string(),
    allowed_tools = [] :: [string()],
    system_prompt = <<>> :: binary(),
    sessions = #{} :: map(),
    default_timeout = 120000 :: integer()
}).

-record(session, {
    id :: binary(),
    created_at :: integer(),
    messages = [] :: list(),
    metadata = #{} :: map()
}).

-type option() :: {output_format, text | json | stream_json}
                | {allowed_tools, [string()]}
                | {timeout, integer()}
                | {session, binary()}
                | {system_prompt, binary()}
                | {append_system_prompt, binary()}
                | {json_schema, map()}.
-type options() :: [option()].

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the Claude headless server with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Start the Claude headless server with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

%% @doc Generate text using Claude Code headless mode.
-spec llm_generate(binary() | iodata()) -> {ok, binary()} | {error, term()}.
llm_generate(Prompt) ->
    llm_generate(Prompt, []).

%% @doc Generate text with options.
-spec llm_generate(binary() | iodata(), options()) -> {ok, binary()} | {error, term()}.
llm_generate(Prompt, Options) ->
    gen_server:call(?MODULE, {llm_generate, Prompt, Options}, infinity).

%% @doc Generate with JSON schema for structured output.
-spec llm_generate_with_schema(binary() | iodata(), map()) -> {ok, map()} | {error, term()}.
llm_generate_with_schema(Prompt, Schema) ->
    llm_generate(Prompt, [
        {output_format, json},
        {json_schema, Schema}
    ]).

%% @doc Generate with streaming callback.
-spec llm_generate_streaming(binary() | iodata(), function()) -> {ok, binary()} | {error, term()}.
llm_generate_streaming(Prompt, Callback) ->
    gen_server:call(?MODULE, {llm_generate_streaming, Prompt, Callback}, infinity).

%% @doc Request human approval for a workflow decision.
-spec request_human_approval(binary(), map()) -> {ok, binary()} | {pending, binary()}.
request_human_approval(DecisionPrompt, Context) ->
    gen_server:call(?MODULE, {human_approval, DecisionPrompt, Context}, infinity).

%% @doc Submit human feedback for approval request.
-spec submit_human_feedback(binary(), binary(), map()) -> ok.
submit_human_feedback(ApprovalId, Feedback, Context) ->
    gen_server:cast(?MODULE, {human_feedback, ApprovalId, Feedback, Context}).

%% @doc Create a new Claude session.
-spec create_session() -> {ok, binary()}.
create_session() ->
    gen_server:call(?MODULE, create_session, infinity).

%% @doc Continue an existing session.
-spec continue_session(binary()) -> {ok, binary()} | {error, term()}.
continue_session(SessionId) ->
    gen_server:call(?MODULE, {continue_session, SessionId}, infinity).

%% @doc Get session history.
-spec get_session_history(binary()) -> {ok, list()}.
get_session_history(SessionId) ->
    gen_server:call(?MODULE, {get_history, SessionId}, infinity).

%% @doc Set allowed tools for Claude.
-spec set_allowed_tools([string()]) -> ok.
set_allowed_tools(Tools) ->
    gen_server:cast(?MODULE, {set_allowed_tools, Tools}).

%% @doc Set system prompt.
-spec set_system_prompt(binary()) -> ok.
set_system_prompt(Prompt) ->
    gen_server:cast(?MODULE, {set_system_prompt, Prompt}).

%% @doc Append to system prompt.
-spec append_system_prompt(binary()) -> ok.
append_system_prompt(Prompt) ->
    gen_server:cast(?MODULE, {append_system_prompt, Prompt}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, init_state(#{})};
init([Options]) ->
    {ok, init_state(Options)}.

%% @private
init_state(Options) ->
    ClaudeBin = maps:get(claude_bin, Options, os:find_executable("claude")),
    AllowedTools = maps:get(allowed_tools, Options, []),
    SystemPrompt = maps:get(system_prompt, Options,
        <<"You are a workflow automation assistant. Help users create and optimize YAWL workflows.">>),
    #state{
        claude_bin = ClaudeBin,
        allowed_tools = AllowedTools,
        system_prompt = SystemPrompt
    }.

handle_call({llm_generate, Prompt, Options}, _From, State) ->
    Result = do_llm_generate(Prompt, Options, State),
    {reply, Result, State};

handle_call({llm_generate_streaming, Prompt, Callback}, _From, State) ->
    Result = do_llm_generate_streaming(Prompt, Callback, State),
    {reply, Result, State};

handle_call({human_approval, DecisionPrompt, Context}, _From, State) ->
    ApprovalId = generate_id(),
    Approval = #{
        id => ApprovalId,
        prompt => DecisionPrompt,
        context => Context,
        status => pending,
        created_at => erlang:monotonic_time(millisecond)
    },
    {reply, {pending, ApprovalId}, State#state{
        sessions = maps:put(ApprovalId, Approval, State#state.sessions)
    }};

handle_call(create_session, _From, State) ->
    SessionId = generate_id(),
    Session = #session{
        id = SessionId,
        created_at = erlang:monotonic_time(millisecond)
    },
    {reply, {ok, SessionId}, State#state{
        sessions = maps:put(SessionId, Session, State#state.sessions)
    }};

handle_call({continue_session, SessionId}, _From, State) ->
    case maps:get(SessionId, State#state.sessions) of
        undefined ->
            {reply, {error, session_not_found}, State};
        _Session ->
            {reply, {ok, SessionId}, State}
    end;

handle_call({get_history, SessionId}, _From, State) ->
    case maps:get(SessionId, State#state.sessions) of
        undefined ->
            {reply, {error, session_not_found}, State};
        Session ->
            {reply, {ok, Session#session.messages}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({set_allowed_tools, Tools}, State) ->
    {noreply, State#state{allowed_tools = Tools}};

handle_cast({set_system_prompt, Prompt}, State) ->
    {noreply, State#state{system_prompt = Prompt}};

handle_cast({append_system_prompt, Prompt}, State) ->
    Current = State#state.system_prompt,
    {noreply, State#state{system_prompt = <<Current/binary, "\n", Prompt/binary>>}};

handle_cast({human_feedback, ApprovalId, Feedback, Context}, State) ->
    case maps:get(ApprovalId, State#state.sessions) of
        undefined ->
            {noreply, State};
        Approval ->
            UpdatedApproval = Approval#{
                feedback => Feedback,
                context => Context,
                status => completed,
                completed_at => erlang:monotonic_time(millisecond)
            },
            {noreply, State#state{
                sessions = maps:put(ApprovalId, UpdatedApproval, State#state.sessions)
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
%% Execute Claude Code headless command.
do_llm_generate(Prompt, Options, State) ->
    ClaudeBin = State#state.claude_bin,
    AllowedTools = proplists:get_value(allowed_tools, Options, State#state.allowed_tools),
    OutputFormat = proplists:get_value(output_format, Options, text),
    Timeout = proplists:get_value(timeout, Options, State#state.default_timeout),

    Args = ["-p", quote_prompt(Prompt)],

    %% Add output format
    case OutputFormat of
        json -> Args ++ ["--output-format", "json"];
        stream_json -> Args ++ ["--output-format", "stream-json"];
        text -> Args
    end,

    %% Add allowed tools
    case AllowedTools of
        [] -> Args;
        _ -> Args ++ ["--allowedTools", string:join(AllowedTools, ",")]
    end,

    %% Add system prompt if specified
    AppendPrompt = proplists:get_value(append_system_prompt, Options, <<>>),
    FinalArgs = case AppendPrompt of
        <<>> -> Args;
        _ -> Args ++ ["--append-system-prompt", binary_to_list(AppendPrompt)]
    end,

    case os:find_executable(ClaudeBin) of
        false ->
            {error, claude_not_found};
        _ ->
            Port = open_port({spawn_executable, ClaudeBin},
                [{args, FinalArgs}, binary, exit_status, stderr_to_stdout]),
            try
                {Output, 0} = receive_port_output(Port, Timeout),
                {ok, parse_output(Output, OutputFormat)}
            catch
                {timeout, _} ->
                    port_close(Port),
                    {error, timeout}
            end
    end.

%% @private
do_llm_generate_streaming(Prompt, Callback, State) ->
    ClaudeBin = State#state.claude_bin,
    Args = ["-p", quote_prompt(Prompt),
        "--output-format", "stream-json",
        "--include-partial-messages"],

    Port = open_port({spawn_executable, ClaudeBin},
        [{args, Args}, binary, exit_status, {line, 100}, stderr_to_stdout, use_stdio]),

    spawn(fun() ->
        stream_port_output(Port, Callback, infinity)
    end),

    {ok, streaming}.

%% @private
quote_prompt(Prompt) when is_binary(Prompt) ->
    binary_to_list(Prompt);
quote_prompt(Prompt) when is_list(Prompt) ->
    Prompt.

%% @private
parse_output(Output, text) ->
    Output;
parse_output(Output, json) ->
    try jiffy:decode(Output, [return_maps]) of
        Result -> maps:get(<<"result">>, Result, Result)
    catch
        _:_ -> Output
    end.

%% @private
receive_port_output(Port, Timeout) ->
    receive
        {Port, {data, Data}} ->
            case receive_port_output(Port, Timeout - 100) of
                {Rest, 0} -> {<<Data/binary, Rest/binary>>, 0};
                {Rest, Code} -> {<<Data/binary, Rest/binary>>, Code}
            end;
        {Port, {exit_status, 0}} ->
            {<<>>, 0};
        {Port, {exit_status, Code}} ->
            {<<>>, Code}
    after Timeout ->
        port_close(Port),
        exit(timeout)
    end.

%% @private
stream_port_output(Port, Callback, Timeout) ->
    receive
        {Port, {data, {eol, Data}}} ->
            Callback(Data),
            stream_port_output(Port, Callback, Timeout);
        {Port, {data, {noeol, Data}}} ->
            Callback(Data),
            stream_port_output(Port, Callback, Timeout);
        {Port, {exit_status, 0}} ->
            Callback(eof);
        {Port, {exit_status, _}} ->
            Callback(eof)
    after Timeout ->
        port_close(Port),
        Callback(timeout)
    end.

%% @private
generate_id() ->
    Binary = term_to_binary({node(), erlang:monotonic_time(microsecond), erlang:unique_integer([positive])}),
    lists:flatten([io_lib:format("~2.16.0B", [B]) || <<B>> <= Binary]).
