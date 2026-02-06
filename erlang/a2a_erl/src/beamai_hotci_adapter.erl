%%% @doc HotCI upgrade adapter for beamai modules.
%%% Registers beamai_* modules with the HotCI upgrade system and
%%% manages ordered code upgrades/downgrades with state preservation.
-module(beamai_hotci_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, register_modules/0, get_upgrade_plan/1,
         handle_upgrade/2, handle_downgrade/2, get_module_states/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    modules = [] :: [module()],
    module_states = #{} :: #{module() => map()},
    last_registered :: integer() | undefined
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_modules() ->
    gen_server:call(?MODULE, register_modules, ?DEFAULT_TIMEOUT).

get_upgrade_plan(TargetVsn) ->
    gen_server:call(?MODULE, {get_upgrade_plan, TargetVsn}, ?DEFAULT_TIMEOUT).

handle_upgrade(Module, Extra) ->
    gen_server:call(?MODULE, {handle_upgrade, Module, Extra}, ?DEFAULT_TIMEOUT).

handle_downgrade(Module, Extra) ->
    gen_server:call(?MODULE, {handle_downgrade, Module, Extra}, ?DEFAULT_TIMEOUT).

get_module_states() ->
    gen_server:call(?MODULE, get_module_states).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_hotci_adapter starting"),
    {ok, #state{}}.

handle_call(register_modules, _From, State) ->
    AllLoaded = [M || {M, _} <- code:all_loaded()],
    BeamaiMods = lists:sort([M || M <- AllLoaded,
        lists:prefix("beamai_", atom_to_list(M))]),
    ModStates = lists:foldl(fun(M, Acc) ->
        Info = try M:module_info(attributes) catch _:_ -> [] end,
        Vsn = proplists:get_value(vsn, Info, [undefined]),
        Acc#{M => #{vsn => Vsn, status => registered}}
    end, #{}, BeamaiMods),
    Now = erlang:system_time(millisecond),
    ?LOG_INFO("Registered ~p beamai modules", [length(BeamaiMods)]),
    {reply, {ok, BeamaiMods},
     State#state{modules = BeamaiMods, module_states = ModStates,
                 last_registered = Now}};

handle_call({get_upgrade_plan, _TargetVsn}, _From, #state{modules = Mods} = State) ->
    %% Core modules first, then adapters. Kernel is a map in beamai_kernel.
    CoreOrder = [beamai_kernel, beamai_memory, beamai_agent, beamai_a2a_server],
    Ordered = [M || M <- CoreOrder, lists:member(M, Mods)] ++
              [M || M <- Mods, not lists:member(M, CoreOrder)],
    {reply, {ok, Ordered}, State};

handle_call({handle_upgrade, Module, Extra}, _From, #state{module_states = MS} = State) ->
    ?LOG_INFO("Upgrading module ~p", [Module]),
    OldState = maps:get(Module, MS, #{status => unknown}),
    Snapshot = OldState#{pre_upgrade => erlang:system_time(millisecond), extra => Extra},
    Result = try
        code:purge(Module),
        case code:load_file(Module) of
            {module, Module} -> ok;
            {error, Reason} -> {error, Reason}
        end
    catch C:R -> {error, {C, R}}
    end,
    NewMS = MS#{Module => Snapshot#{status => case Result of ok -> upgraded; _ -> failed end}},
    {reply, Result, State#state{module_states = NewMS}};

handle_call({handle_downgrade, Module, Extra}, _From, #state{module_states = MS} = State) ->
    ?LOG_INFO("Downgrading module ~p", [Module]),
    OldState = maps:get(Module, MS, #{}),
    NewMS = MS#{Module => OldState#{status => downgraded, extra => Extra,
                                     at => erlang:system_time(millisecond)}},
    {reply, ok, State#state{module_states = NewMS}};

handle_call(get_module_states, _From, #state{module_states = MS} = State) ->
    {reply, MS, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
