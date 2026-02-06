%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Application
%%%
%%% Application entry point managing the BeamAI memory system which
%%% provides short-term (Checkpointer) and long-term (Store) memory
%%% with pluggable backends (ETS/SQLite), checkpoint-based recovery,
%%% timeline/time-travel support, importance scoring, forgetting
%%% curves, and buffer management.
%%%
%%% Configuration options (set in app env):
%%%   - backend: ets | sqlite (default: ets)
%%%   - sqlite_db_path: path to SQLite database file
%%%   - checkpoint_interval: ms between auto-checkpoints (default: 60000)
%%%   - auto_checkpoint: true | false (default: true)
%%%   - default_ttl: integer() | infinity (default: infinity)
%%%   - max_buffer_size: max items in conversation buffer (default: 1000)
%%%   - forgetting_policy: ebbinghaus | linear | none (default: ebbinghaus)
%%%   - decay_interval: ms between decay passes (default: 300000)
%%%   - importance_threshold: float 0.0-1.0 for forget cutoff (default: 0.3)
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% Convenience API
-export([
    get_config/1,
    get_config/2
]).

%%====================================================================
%% Application Callbacks
%%====================================================================

%% @doc Start the beamai_memory application.
%% Initializes configuration and starts the supervision tree containing
%% the memory store, checkpoint manager, and timeline tracker.
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    logger:info("BeamAI Memory System starting (backend=~p)", [get_config(backend, ets)]),
    case beamai_memory_sup:start_link() of
        {ok, Pid} ->
            logger:info("BeamAI Memory System started successfully"),
            {ok, Pid};
        {error, Reason} ->
            logger:error("BeamAI Memory System failed to start: ~p", [Reason]),
            {error, Reason}
    end.

%% @doc Stop the beamai_memory application.
-spec stop(term()) -> ok.
stop(_State) ->
    logger:info("BeamAI Memory System stopping"),
    ok.

%%====================================================================
%% Convenience API
%%====================================================================

%% @doc Get a configuration value from the beamai_memory application env.
-spec get_config(atom()) -> term() | undefined.
get_config(Key) ->
    get_config(Key, undefined).

%% @doc Get a configuration value with a default fallback.
-spec get_config(atom(), term()) -> term().
get_config(Key, Default) ->
    application:get_env(beamai_memory, Key, Default).
