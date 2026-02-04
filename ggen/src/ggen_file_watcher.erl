%%====================================================================
%% Module: ggen_file_watcher
%% Description: Watch for changes in ontology and template files
%%====================================================================

-module(ggen_file_watcher).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    watch_dirs :: list(),
    watchers :: list(),
    last_check :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

-spec init(Args :: term()) -> {ok, term()} | {stop, term()}.
init(_Args) ->
    %% Watch directories for changes
    WatchDirs = [
        "ontology",
        "templates",
        "queries"
    ],

    %% Create initial watchers
    Watchers = lists:map(fun(Dir) ->
        case filelib:is_dir(Dir) of
            true ->
                %% TODO: Implement file watching
                {Dir, 0};
            false ->
                {Dir, undefined}
        end
    end, WatchDirs),

    State = #state{
        watch_dirs = WatchDirs,
        watchers = Watchers,
        last_check = erlang:system_time(millisecond)
    },

    {ok, State}.

-spec handle_call(Request :: term(), From :: term(), State :: term()) ->
    {reply, term(), term()} | {noreply, term()} | {stop, term(), term()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec handle_cast(Msg :: term(), State :: term()) -> {noreply, term()} | {stop, term(), term()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(Info :: term(), State :: term()) -> {noreply, term()} | {stop, term(), term()}.
handle_info({file_event, _File, _Event}, State) ->
    %% Handle file change events
    io:format("📁 File change detected~n"),
    {noreply, State};

handle_info(check_files, State) ->
    %% Periodically check for file changes
    check_file_changes(State),
    {noreply, State#state{last_check = erlang:system_time(millisecond)}};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(Reason :: term(), State :: term()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(OldVsn :: term(), State :: term(), Extra :: term()) -> {ok, term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec check_file_changes(State :: #state{}) -> ok.
check_file_changes(#state{watch_dirs = WatchDirs} = _State) ->
    lists:foreach(fun(Dir) ->
        case filelib:is_dir(Dir) of
            true ->
                check_directory_changes(Dir);
            false ->
                io:format("❌ Directory not found: ~p~n", [Dir])
        end
    end, WatchDirs).

-spec check_directory_changes(Dir :: string()) -> ok.
check_directory_changes(Dir) ->
    Files = filelib:wildcard(Dir ++ "/*"),
    lists:foreach(fun(File) ->
        case filelib:last_modified(File) of
            0 ->
                io:format("📄 File added: ~p~n", [File]);
            Time when is_integer(Time) ->
                %% Check if modified recently (within last 60 seconds)
                Now = erlang:system_time(millisecond),
                case Now - Time < 60000 of
                    true ->
                        io:format("📝 File modified: ~p~n", [File]);
                    false ->
                        ok
                end
        end
    end, Files).