%%% @doc Dashboard data and alerting adapter for beamai components.
%%% Aggregates health, metrics, and recent events for monitoring dashboards.
-module(beamai_monitoring_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, get_dashboard_data/0, configure_alerts/1, get_logs/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    alert_config = #{} :: map(),
    events = [] :: [map()],
    max_events = 500 :: pos_integer()
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_dashboard_data() ->
    gen_server:call(?MODULE, get_dashboard_data, ?DEFAULT_TIMEOUT).

configure_alerts(Config) when is_map(Config) ->
    gen_server:call(?MODULE, {configure_alerts, Config}, ?DEFAULT_TIMEOUT).

get_logs(Opts) when is_map(Opts) ->
    gen_server:call(?MODULE, {get_logs, Opts}, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_monitoring_adapter starting"),
    erlang:send_after(10000, self(), collect_events),
    {ok, #state{alert_config = default_alerts()}}.

handle_call(get_dashboard_data, _From, #state{events = Events, alert_config = AC} = State) ->
    %% Aggregate health from beamai_health_adapter
    Health = try beamai_health_adapter:status()
             catch _:_ -> #{status => unknown} end,
    %% Aggregate metrics from beamai_metrics_adapter
    Metrics = try beamai_metrics_adapter:collect_all()
              catch _:_ -> #{} end,
    %% Kernel info
    KernelInfo = try
        K = #{name => <<"monitor">>, tools => []},
        #{tools => beamai_kernel:list_tools(K),
          service => beamai_kernel:get_service(K)}
    catch _:_ -> #{} end,
    %% Agent card
    AgentCard = try beamai_a2a_server:get_agent_card(#{})
                catch _:_ -> unavailable end,
    Dashboard = #{health => Health, metrics => Metrics,
                  kernel => KernelInfo, agent_card => AgentCard,
                  recent_events => lists:sublist(Events, 50),
                  alert_config => AC,
                  timestamp => erlang:system_time(millisecond)},
    {reply, Dashboard, State};

handle_call({configure_alerts, Config}, _From, State) ->
    Merged = maps:merge(State#state.alert_config, Config),
    ?LOG_INFO("Alert config updated"),
    {reply, ok, State#state{alert_config = Merged}};

handle_call({get_logs, Opts}, _From, #state{events = Events} = State) ->
    Limit = maps:get(limit, Opts, 100),
    Since = maps:get(since, Opts, 0),
    Filtered = [E || E = #{timestamp := T} <- Events, T >= Since],
    {reply, lists:sublist(Filtered, Limit), State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(collect_events, #state{events = Events, max_events = Max,
                                    alert_config = AC} = State) ->
    Now = erlang:system_time(millisecond),
    %% Collect system snapshot as event
    ProcCount = erlang:system_info(process_count),
    MemMB = erlang:memory(total) / (1024 * 1024),
    Event = #{type => system_snapshot, timestamp => Now,
              process_count => ProcCount, memory_mb => MemMB},
    NewEvents = lists:sublist([Event | Events], Max),
    %% Check alert thresholds
    MaxMem = maps:get(max_memory_mb, AC, 512),
    MaxProcs = maps:get(max_processes, AC, 100000),
    case MemMB > MaxMem of
        true -> ?LOG_ERROR("ALERT: Memory ~.1f MB exceeds threshold ~p MB", [MemMB, MaxMem]);
        false -> ok
    end,
    case ProcCount > MaxProcs of
        true -> ?LOG_ERROR("ALERT: Process count ~p exceeds threshold ~p", [ProcCount, MaxProcs]);
        false -> ok
    end,
    erlang:send_after(10000, self(), collect_events),
    {noreply, State#state{events = NewEvents}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%% Internal

default_alerts() ->
    #{max_memory_mb => 512, max_processes => 100000,
      max_error_rate => 0.05}.
