%%%-------------------------------------------------------------------
%%% @doc BeamAI Configuration module.
%%% Reads BeamAI configuration from application environment (sys.config)
%%% and provides default configurations for LLM providers.
%%% Also supports runtime configuration via ETS.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_config).

-export([
    get/1,
    get/2,
    set/2,
    all/0,
    init/0
]).

-define(CONFIG_TABLE, beamai_config_table).

%%--------------------------------------------------------------------
%% @doc Initialize the configuration ETS table.
%% Called automatically when needed. Safe to call multiple times.
%% @end
%%--------------------------------------------------------------------
-spec init() -> ok.
init() ->
    case ets:info(?CONFIG_TABLE) of
        undefined ->
            ?CONFIG_TABLE = ets:new(?CONFIG_TABLE, [
                named_table, public, set, {read_concurrency, true}
            ]),
            ok;
        _ ->
            ok
    end.

%%--------------------------------------------------------------------
%% @doc Get a configuration value by key.
%% Looks up in this order:
%%   1. Runtime ETS overrides
%%   2. beamai_core application environment
%%   3. Returns undefined if not found
%% @end
%%--------------------------------------------------------------------
-spec get(atom()) -> term() | undefined.
get(Key) ->
    get(Key, undefined).

%%--------------------------------------------------------------------
%% @doc Get a configuration value by key with a default.
%% Looks up in this order:
%%   1. Runtime ETS overrides
%%   2. beamai_core application environment
%%   3. Returns Default if not found
%% @end
%%--------------------------------------------------------------------
-spec get(atom(), term()) -> term().
get(Key, Default) ->
    %% First check ETS runtime overrides
    case ets_lookup(Key) of
        {ok, Value} ->
            Value;
        error ->
            %% Fall back to application environment
            case application:get_env(beamai_core, Key) of
                {ok, Value} ->
                    Value;
                undefined ->
                    Default
            end
    end.

%%--------------------------------------------------------------------
%% @doc Set a runtime configuration value.
%% This overrides the application environment for the given key.
%% @end
%%--------------------------------------------------------------------
-spec set(atom(), term()) -> ok.
set(Key, Value) ->
    ensure_table(),
    ets:insert(?CONFIG_TABLE, {Key, Value}),
    ok.

%%--------------------------------------------------------------------
%% @doc Return all configuration as a map.
%% Merges application environment with runtime overrides.
%% @end
%%--------------------------------------------------------------------
-spec all() -> map().
all() ->
    %% Get all from application env
    AppEnv = case application:get_all_env(beamai_core) of
        Env when is_list(Env) -> maps:from_list(Env);
        _ -> #{}
    end,
    %% Merge with runtime overrides
    EtsOverrides = ets_all(),
    maps:merge(AppEnv, EtsOverrides).

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
-spec ensure_table() -> ok.
ensure_table() ->
    case ets:info(?CONFIG_TABLE) of
        undefined -> init();
        _ -> ok
    end.

%% @private
-spec ets_lookup(atom()) -> {ok, term()} | error.
ets_lookup(Key) ->
    try
        case ets:lookup(?CONFIG_TABLE, Key) of
            [{Key, Value}] -> {ok, Value};
            [] -> error
        end
    catch
        error:badarg ->
            %% Table does not exist yet
            error
    end.

%% @private
-spec ets_all() -> map().
ets_all() ->
    try
        List = ets:tab2list(?CONFIG_TABLE),
        maps:from_list(List)
    catch
        error:badarg ->
            #{}
    end.
