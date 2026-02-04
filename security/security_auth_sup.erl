%%% @doc Authentication System Supervisor
%%% Supervises the authentication server

-module(security_auth_sup).
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
            id => security_auth,
            start => {security_auth, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [security_auth]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.