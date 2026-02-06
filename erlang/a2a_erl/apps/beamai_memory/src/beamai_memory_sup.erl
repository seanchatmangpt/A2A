%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Supervisor
%%%
%%% Top-level supervisor for the BeamAI memory subsystem. Starts and
%%% monitors the following children in order:
%%%
%%% 1. beamai_memory_store     - Key-value storage (ETS or SQLite backend)
%%% 2. beamai_memory_checkpoint - Checkpoint/snapshot manager
%%% 3. beamai_memory_timeline   - Timeline tracker for time-travel debugging
%%% 4. beamai_memory_importance - Importance scoring for memory items
%%% 5. beamai_memory_forgetting - Forgetting curve and cleanup manager
%%%
%%% Uses a rest_for_one strategy: if the store crashes, the checkpoint
%%% and timeline workers are also restarted since they depend on it.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callback
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the memory supervisor.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor Callbacks
%%====================================================================

%% @private
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 10,
        period => 60
    },

    %% Read backend configuration
    Backend = beamai_memory_app:get_config(backend, ets),
    StoreOpts = #{
        backend => Backend,
        sqlite_db_path => beamai_memory_app:get_config(sqlite_db_path, "beamai_memory.db"),
        default_ttl => beamai_memory_app:get_config(default_ttl, infinity)
    },

    MemoryStore = #{
        id => beamai_memory_store,
        start => {beamai_memory_store, start_link, [StoreOpts]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_memory_store]
    },

    CheckpointManager = #{
        id => beamai_memory_checkpoint,
        start => {beamai_memory_checkpoint, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_memory_checkpoint]
    },

    TimelineTracker = #{
        id => beamai_memory_timeline,
        start => {beamai_memory_timeline, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_memory_timeline]
    },

    ImportanceScorer = #{
        id => beamai_memory_importance,
        start => {beamai_memory_importance, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_memory_importance]
    },

    ForgettingManager = #{
        id => beamai_memory_forgetting,
        start => {beamai_memory_forgetting, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [beamai_memory_forgetting]
    },

    Children = [
        MemoryStore,
        CheckpointManager,
        TimelineTracker,
        ImportanceScorer,
        ForgettingManager
    ],

    {ok, {SupFlags, Children}}.
