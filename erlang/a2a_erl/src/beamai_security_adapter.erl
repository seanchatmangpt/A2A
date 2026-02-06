%%% @doc Security auditing adapter for beamai components.
%%% Validates module checksums, audits tool calls, and checks API key config.
-module(beamai_security_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, validate_modules/0, audit_tool_call/2,
         check_api_keys/0, get_security_report/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    module_checksums = #{} :: #{module() => binary()},
    audit_log = [] :: [map()],
    max_audit_entries = 1000 :: pos_integer()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

validate_modules() ->
    gen_server:call(?MODULE, validate_modules, ?DEFAULT_TIMEOUT).

audit_tool_call(ToolName, Args) ->
    gen_server:cast(?MODULE, {audit_tool_call, ToolName, Args}).

check_api_keys() ->
    gen_server:call(?MODULE, check_api_keys, ?DEFAULT_TIMEOUT).

get_security_report() ->
    gen_server:call(?MODULE, get_security_report, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_security_adapter starting"),
    Checksums = compute_checksums(),
    {ok, #state{module_checksums = Checksums}}.

handle_call(validate_modules, _From, #state{module_checksums = Saved} = State) ->
    Current = compute_checksums(),
    Changed = maps:fold(fun(Mod, Hash, Acc) ->
        case maps:find(Mod, Saved) of
            {ok, Hash} -> Acc;
            {ok, _OldHash} -> [Mod | Acc];
            error -> [Mod | Acc]
        end
    end, [], Current),
    Removed = [M || M <- maps:keys(Saved), not maps:is_key(M, Current)],
    Result = case {Changed, Removed} of
        {[], []} -> {ok, verified};
        _ -> {warning, #{changed => Changed, removed => Removed}}
    end,
    {reply, Result, State#state{module_checksums = Current}};

handle_call(check_api_keys, _From, State) ->
    KeyChecks = lists:map(fun({EnvVar, Label}) ->
        case os:getenv(EnvVar) of
            false -> {Label, missing};
            "" -> {Label, empty};
            Val when length(Val) < 8 -> {Label, too_short};
            _Val -> {Label, ok}
        end
    end, [{"BEAMAI_LLM_API_KEY", llm_key},
          {"BEAMAI_API_SECRET", api_secret},
          {"BEAMAI_ENCRYPTION_KEY", encryption_key}]),
    Status = case lists:all(fun({_, S}) -> S =:= ok end, KeyChecks) of
        true -> secure;
        false -> insecure
    end,
    {reply, #{status => Status, keys => maps:from_list(KeyChecks)}, State};

handle_call(get_security_report, _From, State) ->
    Report = #{module_checksums => map_size(State#state.module_checksums),
               audit_entries => length(State#state.audit_log),
               recent_audits => lists:sublist(State#state.audit_log, 20)},
    {reply, Report, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({audit_tool_call, ToolName, Args}, #state{audit_log = Log, max_audit_entries = Max} = State) ->
    Entry = #{tool => ToolName, args_hash => erlang:phash2(Args),
              timestamp => erlang:system_time(millisecond), node => node()},
    Trimmed = lists:sublist([Entry | Log], Max),
    {noreply, State#state{audit_log = Trimmed}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%% Internal

compute_checksums() ->
    AllLoaded = [M || {M, _} <- code:all_loaded()],
    BeamaiMods = [M || M <- AllLoaded,
                  lists:prefix("beamai_", atom_to_list(M))],
    lists:foldl(fun(Mod, Acc) ->
        case code:get_object_code(Mod) of
            {Mod, Beam, _File} ->
                Hash = crypto:hash(sha256, Beam),
                Acc#{Mod => Hash};
            error -> Acc
        end
    end, #{}, BeamaiMods).
