%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent Callbacks
%%%
%%% Defines the callback behaviour for agent observability. Modules
%%% implementing this behaviour receive notifications about agent
%%% lifecycle events: turn start/end/error, LLM calls, tool calls,
%%% and token streaming.
%%%
%%% All callbacks are optional. The default implementations provided
%%% here are no-ops. To use, create a module that implements this
%%% behaviour and pass it as the `callbacks' option when creating
%%% an agent.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_callbacks).

%% Behaviour definition
-callback on_turn_start(TurnNumber :: pos_integer(), Message :: map()) -> ok.
-callback on_turn_end(TurnNumber :: pos_integer(), Response :: map()) -> ok.
-callback on_turn_error(TurnNumber :: pos_integer(), Reason :: term()) -> ok.
-callback on_llm_call(Response :: term(), Metadata :: map()) -> ok.
-callback on_tool_call(ToolName :: binary(), Args :: map()) -> ok.
-callback on_token(Token :: binary(), Metadata :: map()) -> ok.

-optional_callbacks([
    on_turn_start/2,
    on_turn_end/2,
    on_turn_error/2,
    on_llm_call/2,
    on_tool_call/2,
    on_token/2
]).

%% Default implementations
-export([
    on_turn_start/2,
    on_turn_end/2,
    on_turn_error/2,
    on_llm_call/2,
    on_tool_call/2,
    on_token/2,
    notify/3
]).

%%====================================================================
%% Default callback implementations (no-ops)
%%====================================================================

%% @doc Called at the start of each conversation turn.
-spec on_turn_start(pos_integer(), map()) -> ok.
on_turn_start(_TurnNumber, _Message) ->
    ok.

%% @doc Called at the end of each conversation turn.
-spec on_turn_end(pos_integer(), map()) -> ok.
on_turn_end(_TurnNumber, _Response) ->
    ok.

%% @doc Called when an error occurs during a turn.
-spec on_turn_error(pos_integer(), term()) -> ok.
on_turn_error(_TurnNumber, _Reason) ->
    ok.

%% @doc Called after each LLM API call.
-spec on_llm_call(term(), map()) -> ok.
on_llm_call(_Response, _Metadata) ->
    ok.

%% @doc Called before each tool execution.
-spec on_tool_call(binary(), map()) -> ok.
on_tool_call(_ToolName, _Args) ->
    ok.

%% @doc Called for each streaming token received.
-spec on_token(binary(), map()) -> ok.
on_token(_Token, _Metadata) ->
    ok.

%%====================================================================
%% Helper functions
%%====================================================================

%% @doc Safely notify a callback module. If the module does not export
%% the given function, or if the call fails, the error is silently
%% ignored. This ensures that callback failures do not affect the
%% agent's operation.
-spec notify(module() | undefined, atom(), [term()]) -> ok.
notify(undefined, _Function, _Args) ->
    ok;
notify(Module, Function, Args) ->
    try
        Exports = Module:module_info(exports),
        Arity = length(Args),
        case lists:member({Function, Arity}, Exports) of
            true ->
                erlang:apply(Module, Function, Args),
                ok;
            false ->
                %% Function not exported, use default
                ok
        end
    catch
        Class:Reason:Stack ->
            logger:warning("Agent callback ~p:~p failed: ~p:~p~n~p",
                           [Module, Function, Class, Reason, Stack]),
            ok
    end.
