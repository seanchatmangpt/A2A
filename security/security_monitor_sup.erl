%%% @doc Security Monitor Supervisor
%%% Supervises the security monitoring system

-module(security_monitor_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },

    ChildSpecs = [
        #{
            id => security_monitor,
            start => {security_monitor, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [security_monitor]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.