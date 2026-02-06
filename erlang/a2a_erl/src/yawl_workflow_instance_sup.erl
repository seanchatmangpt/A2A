%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Instance Supervisor
%%%
%%% Dynamic supervisor for managing workflow instance processes.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_instance_sup).
-author("A2A Team").
-behaviour(supervisor).

%% API
-export([start_link/0, start_child/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API Functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a new workflow instance.
-spec start_child(binary(), map()) -> supervisor:startchild_ret().
start_child(WorkflowId, Config) ->
    SupervisorRef = ?MODULE,
    ChildSpec = #{
        id => WorkflowId,
        start => {yawl_workflow_instance, start_link, [WorkflowId, Config]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [yawl_workflow_instance]
    },
    supervisor:start_child(SupervisorRef, ChildSpec).

%%====================================================================
%% Supervisor Callbacks
%%====================================================================

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 60
    },
    {ok, {SupFlags, []}}.
