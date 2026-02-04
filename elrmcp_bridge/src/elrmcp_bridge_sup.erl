%%% @doc elrmcp Bridge Supervisor
%%% Supervises bridge components

-module(elrmcp_bridge_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(CHILDREN, [
    {elrmcp_mcp_bridge, {elrmcp_mcp_bridge, start_link, []}, permanent, 5000, worker, [elrmcp_mcp_bridge]},
    {elrmcp_rate_limiter, {elrmcp_rate_limiter, start_link, [100]}, permanent, 5000, worker, [elrmcp_rate_limiter]}
]).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    io:format("Initializing elrmcp Bridge Supervisor~n"),
    {ok, {{one_for_one, 5, 10}, ?CHILDREN}}.