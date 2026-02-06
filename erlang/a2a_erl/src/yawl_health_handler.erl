%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Health Check Handler
%%%
%%% This module provides health check endpoints for the YAWL workflow system.
%%% It reports the status of various components including the orchestrator,
%%% persistence layer, resource manager, and service registry.
%%%
%%% ## Endpoints
%%%
%%% - `GET /health` - Basic health check
%%% - `GET /health/detailed` - Detailed health check with component status
%%% - `GET /health/ready` - Readiness probe (checks if system can accept traffic)
%%% - `GET /health/live` - Liveness probe (checks if system is alive)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_health_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    to_json/2,
    to_text/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    check_type :: basic | detailed | ready | live
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, _State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),

    CheckType = case Path of
        <<"/health">> -> basic;
        <<"/health/detailed">> -> detailed;
        <<"/health/ready">> -> ready;
        <<"/health/live">> -> live;
        _ -> basic
    end,

    NewState = #state{
        method = Method,
        check_type = CheckType
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    {[<<"GET">>, <<"HEAD">>, <<"OPTIONS">>], Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, to_json},
        {{<<"text">>, <<"plain">>, '*'}, to_text}
    ], Req, State}.

%% @private
to_json(Req, State) ->
    Response = case State#state.check_type of
        basic -> handle_basic_health();
        detailed -> handle_detailed_health();
        ready -> handle_readiness_check();
        live -> handle_liveness_check()
    end,

    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
to_text(Req, State) ->
    Response = case State#state.check_type of
        basic ->
            case handle_basic_health() of
                #{status := <<"healthy">>} -> <<"OK">>;
                #{status := Status} -> Status
            end;
        ready ->
            case handle_readiness_check() of
                #{status := <<"ready">>} -> <<"READY">>;
                #{status := Status} -> Status
            end;
        live ->
            case handle_liveness_check() of
                #{status := <<"alive">>} -> <<"ALIVE">>;
                #{status := Status} -> Status
            end;
        detailed ->
            case handle_detailed_health() of
                #{status := <<"healthy">>} -> <<"OK">>;
                #{status := Status} -> Status
            end
    end,

    {Response, Req, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_basic_health() ->
    %% Basic health check - just check if critical processes are alive
    IsOrchestratorAlive = is_process_alive(whereis(yawl_orchestrator)),
    IsPersistenceAlive = is_process_alive(whereis(yawl_persistence)),

    Status = case IsOrchestratorAlive andalso IsPersistenceAlive of
        true -> <<"healthy">>;
        false -> <<"unhealthy">>
    end,

    #{
        status => Status,
        timestamp => erlang:system_time(millisecond),
        uptime => get_uptime()
    }.

%% @private
handle_detailed_health() ->
    %% Detailed health check with component status
    Components = #{
        orchestrator => check_orchestrator_health(),
        persistence => check_persistence_health(),
        resource_manager => check_resource_manager_health(),
        service_registry => check_service_registry_health(),
        mnesia => check_mnesia_health()
    },

    OverallStatus = case lists:all(fun(#{status := S}) -> S =:= <<"healthy">> end, maps:values(Components)) of
        true -> <<"healthy">>;
        false -> <<"degraded">>
    end,

    #{
        status => OverallStatus,
        timestamp => erlang:system_time(millisecond),
        uptime => get_uptime(),
        components => Components,
        system => get_system_info()
    }.

%% @private
handle_readiness_check() ->
    %% Readiness check - system is ready to accept traffic
    IsOrchestratorAlive = is_process_alive(whereis(yawl_orchestrator)),
    IsPersistenceReady = check_persistence_ready(),

    Status = case IsOrchestratorAlive andalso IsPersistenceReady of
        true -> <<"ready">>;
        false -> <<"not_ready">>
    end,

    #{
        status => Status,
        timestamp => erlang:system_time(millisecond),
        checks => #{
            orchestrator => IsOrchestratorAlive,
            persistence => IsPersistenceReady
        }
    }.

%% @private
handle_liveness_check() ->
    %% Liveness check - system is alive and running
    Status = <<"alive">>,

    #{
        status => Status,
        timestamp => erlang:system_time(millisecond),
        pid => list_to_binary(pid_to_list(self()))
    }.

%%====================================================================
%% Component Health Check Functions
%%====================================================================

%% @private
check_orchestrator_health() ->
    case whereis(yawl_orchestrator) of
        undefined ->
            #{
                status => <<"unhealthy">>,
                message => <<"Orchestrator not running">>
            };
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    try
                        {ok, Workflows} = yawl_orchestrator:list_workflows(),
                        #{
                            status => <<"healthy">>,
                            active_workflows => length(Workflows),
                            pid => pid_to_list(Pid)
                        }
                    catch
                        _:_ ->
                            #{
                                status => <<"degraded">>,
                                message => <<"Orchestrator not responding">>
                            }
                    end;
                false ->
                    #{
                        status => <<"unhealthy">>,
                        message => <<"Orchestrator process dead">>
                    }
            end
    end.

%% @private
check_persistence_health() ->
    case whereis(yawl_persistence) of
        undefined ->
            #{
                status => <<"unhealthy">>,
                message => <<"Persistence not running">>
            };
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    try
                        {ok, _Workflows} = yawl_persistence:list_workflows(),
                        #{
                            status => <<"healthy">>,
                            pid => pid_to_list(Pid)
                        }
                    catch
                        _:_ ->
                            #{
                                status => <<"degraded">>,
                                message => <<"Persistence layer issues">>
                            }
                    end;
                false ->
                    #{
                        status => <<"unhealthy">>,
                        message => <<"Persistence process dead">>
                    }
            end
    end.

%% @private
check_persistence_ready() ->
    case whereis(yawl_persistence) of
        undefined -> false;
        Pid when is_pid(Pid) ->
            try
                case mnesia:system_info(use_dir) of
                    true -> true;
                    false -> false
                end
            catch
                _:_ -> false
            end
    end.

%% @private
check_resource_manager_health() ->
    case whereis(yawl_resource_manager) of
        undefined ->
            #{
                status => <<"unhealthy">>,
                message => <<"Resource manager not running">>
            };
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    try
                        {ok, Resources} = yawl_resource_manager:list_resources(),
                        #{
                            status => <<"healthy">>,
                            total_resources => length(Resources),
                            pid => pid_to_list(Pid)
                        }
                    catch
                        _:_ ->
                            #{
                                status => <<"degraded">>,
                                message => <<"Resource manager not responding">>
                            }
                    end;
                false ->
                    #{
                        status => <<"unhealthy">>,
                        message => <<"Resource manager process dead">>
                    }
            end
    end.

%% @private
check_service_registry_health() ->
    case whereis(yawl_service_registry) of
        undefined ->
            #{
                status => <<"unhealthy">>,
                message => <<"Service registry not running">>
            };
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    #{
                        status => <<"healthy">>,
                        pid => pid_to_list(Pid)
                    };
                false ->
                    #{
                        status => <<"unhealthy">>,
                        message => <<"Service registry process dead">>
                    }
            end
    end.

%% @private
check_mnesia_health() ->
    try
        IsRunning = case mnesia:system_info(is_running) of
            yes -> true;
            _ -> false
        end,

        Tables = mnesia:system_info(tables),
        TableStatus = lists:map(fun(Table) ->
            case mnesia:table_info(Table, where_to_read) of
                _ -> {Table, <<"available">>}
            end
        end, Tables),

        #{
            status => case IsRunning of true -> <<"healthy">>; false -> <<"unhealthy">> end,
            is_running => IsRunning,
            tables => length(Tables),
            table_details => TableStatus
        }
    catch
        _:_ ->
            #{
                status => <<"unhealthy">>,
                message => <<"Mnesia not accessible">>
            }
    end.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
get_uptime() ->
    UpTimeMillis = case erlang:statistics(wall_clock) of
        {UpTime, _} -> UpTime;
        _ -> 0
    end,
    UpTimeMillis div 1000.

%% @private
get_system_info() ->
    #{
        process_count => erlang:system_info(process_count),
        memory => get_memory_info(),
        node => node(),
        erts_version => list_to_binary(erlang:system_info(version)),
        otp_release => list_to_binary(erlang:system_info(otp_release))
    }.

%% @private
get_memory_info() ->
    Memory = erlang:memory(),
    #{
        total => proplists:get_value(total, Memory, 0),
        processes => proplists:get_value(processes, Memory, 0),
        system => proplists:get_value(system, Memory, 0),
        atom => proplists:get_value(atom, Memory, 0),
        binary => proplists:get_value(binary, Memory, 0),
        ets => proplists:get_value(ets, Memory, 0)
    }.
