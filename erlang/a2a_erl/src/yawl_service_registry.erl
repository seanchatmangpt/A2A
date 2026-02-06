%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Service Registry
%%%
%%% This module provides service registration, discovery, and health
%%% checking for external services used by YAWL workflows.
%%%
%%% Features:
%%% - Service registration with metadata
%%% - Service discovery by name or type
%%% - Health checking with configurable intervals
%%% - Load balancing and failover
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_service_registry).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Service registration
-export([
    register_service/3,
    register_service/4,
    unregister_service/1,
    update_service/2
]).

%% API exports - Service discovery
-export([
    discover_service/1,
    discover_service_by_type/1,
    list_services/0,
    get_service/1
]).

%% API exports - Service invocation
-export([
    call_service/2,
    call_service/3,
    call_service_async/2
]).

%% API exports - Health checking
-export([
    check_health/1,
    check_all_health/0,
    set_health_status/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    services :: #{binary() => #yawl_service_registry{}},
    services_by_type :: #{atom() => [binary()]},
    health_check_timer :: reference() | undefined,
    health_check_interval :: integer()
}).

-record(service_call, {
    service_id :: binary(),
    method :: get | post | put | delete,
    path :: binary(),
    params :: map(),
    timeout :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the service registry.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a service.
-spec register_service(binary(), atom(), binary()) -> {ok, binary()} | {error, term()}.
register_service(ServiceName, ServiceType, Endpoint) ->
    register_service(ServiceName, ServiceType, Endpoint, #{}).

%% @doc Register a service with options.
-spec register_service(binary(), atom(), binary(), map()) -> {ok, binary()} | {error, term()}.
register_service(ServiceName, ServiceType, Endpoint, Options) ->
    gen_server:call(?MODULE, {register_service, ServiceName, ServiceType, Endpoint, Options}).

%% @doc Unregister a service.
-spec unregister_service(binary()) -> ok | {error, term()}.
unregister_service(ServiceId) ->
    gen_server:call(?MODULE, {unregister_service, ServiceId}).

%% @doc Update a service.
-spec update_service(binary(), map()) -> ok | {error, term()}.
update_service(ServiceId, Updates) ->
    gen_server:call(?MODULE, {update_service, ServiceId, Updates}).

%% @doc Discover a service by name.
-spec discover_service(binary()) -> {ok, map()} | {error, term()}.
discover_service(ServiceName) ->
    gen_server:call(?MODULE, {discover_service, ServiceName}).

%% @doc Discover a service by type.
-spec discover_service_by_type(atom()) -> {ok, map()} | {error, term()}.
discover_service_by_type(ServiceType) ->
    gen_server:call(?MODULE, {discover_service_by_type, ServiceType}).

%% @doc List all services.
-spec list_services() -> {ok, [map()]}.
list_services() ->
    gen_server:call(?MODULE, list_services).

%% @doc Get a service by ID.
-spec get_service(binary()) -> {ok, map()} | {error, term()}.
get_service(ServiceId) ->
    gen_server:call(?MODULE, {get_service, ServiceId}).

%% @doc Call a service (synchronous).
-spec call_service(binary(), map()) -> {ok, term()} | {error, term()}.
call_service(ServiceName, Params) ->
    call_service(ServiceName, Params, #{}).

%% @doc Call a service with options.
-spec call_service(binary(), map(), map()) -> {ok, term()} | {error, term()}.
call_service(ServiceName, Params, Options) ->
    gen_server:call(?MODULE, {call_service, ServiceName, Params, Options}, infinity).

%% @doc Call a service asynchronously.
-spec call_service_async(binary(), map()) -> {ok, reference()} | {error, term()}.
call_service_async(ServiceName, Params) ->
    gen_server:call(?MODULE, {call_service_async, ServiceName, Params}).

%% @doc Check health of a service.
-spec check_health(binary()) -> {ok, service_status(), integer()} | {error, term()}.
check_health(ServiceId) ->
    gen_server:call(?MODULE, {check_health, ServiceId}).

%% @doc Check health of all services.
-spec check_all_health() -> {ok, #{binary() => service_status()}}.
check_all_health() ->
    gen_server:call(?MODULE, check_all_health).

%% @doc Set health status externally.
-spec set_health_status(binary(), service_status()) -> ok | {error, term()}.
set_health_status(ServiceId, Status) ->
    gen_server:call(?MODULE, {set_health_status, ServiceId, Status}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Start health check timer
    Interval = application:get_env(a2a_erl, health_check_interval, 30000),
    {ok, TimerRef} = timer:send_interval(Interval, health_check),

    State = #state{
        services = #{},
        services_by_type = #{},
        health_check_timer = TimerRef,
        health_check_interval = Interval
    },
    {ok, State}.

%% @private
handle_call({register_service, ServiceName, ServiceType, Endpoint, Options}, _From, State) ->
    ServiceId = generate_service_id(ServiceName),

    Service = #yawl_service_registry{
        service_id = ServiceId,
        service_name = ServiceName,
        service_type = ServiceType,
        endpoint = Endpoint,
        health_check_url = maps:get(health_check_url, Options, undefined),
        status = active,
        last_check = erlang:monotonic_time(millisecond),
        response_time = undefined,
        success_rate = 1.0,
        metadata = maps:get(metadata, Options, #{})
    },

    NewServices = maps:put(ServiceId, Service, State#state.services),
    NewByType = update_services_by_type(ServiceType, ServiceId, State#state.services_by_type),

    %% Persist if available (optional - services can run without persistence)
    %% Services are primarily in-memory, persistence is best-effort
    ok,

    NewState = State#state{services = NewServices, services_by_type = NewByType},
    {reply, {ok, ServiceId}, NewState};

handle_call({unregister_service, ServiceId}, _From, State) ->
    case maps:get(ServiceId, State#state.services, undefined) of
        undefined ->
            {reply, {error, service_not_found}, State};
        Service ->
            NewServices = maps:remove(ServiceId, State#state.services),
            NewByType = remove_service_by_type(Service#yawl_service_registry.service_type, ServiceId, State#state.services_by_type),
            NewState = State#state{services = NewServices, services_by_type = NewByType},
            {reply, ok, NewState}
    end;

handle_call({update_service, ServiceId, Updates}, _From, State) ->
    case maps:get(ServiceId, State#state.services, undefined) of
        undefined ->
            {reply, {error, service_not_found}, State};
        Service ->
            UpdatedService = Service#yawl_service_registry{
                endpoint = maps_get(endpoint, Updates, Service#yawl_service_registry.endpoint),
                health_check_url = maps_get(health_check_url, Updates, Service#yawl_service_registry.health_check_url),
                metadata = maps:get(metadata, Updates, Service#yawl_service_registry.metadata)
            },
            NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
            NewState = State#state{services = NewServices},
            {reply, ok, NewState}
    end;

handle_call({discover_service, ServiceName}, _From, State) ->
    case find_service_by_name(ServiceName, State) of
        {ok, ServiceId, Service} ->
            {reply, {ok, service_to_map(ServiceId, Service)}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({discover_service_by_type, ServiceType}, _From, State) ->
    ServiceIds = maps:get(ServiceType, State#state.services_by_type, []),
    case ServiceIds of
        [] ->
            {reply, {error, no_services_of_type}, State};
        _ ->
            %% Select best service (e.g., highest success rate)
            BestId = select_best_service(ServiceIds, State#state.services),
            Service = maps:get(BestId, State#state.services),
            {reply, {ok, service_to_map(BestId, Service)}, State}
    end;

handle_call(list_services, _From, State) ->
    Services = [service_to_map(Id, S) || Id <- maps:keys(State#state.services), S <- [maps:get(Id, State#state.services)]],
    {reply, {ok, Services}, State};

handle_call({get_service, ServiceId}, _From, State) ->
    case maps:get(ServiceId, State#state.services, undefined) of
        undefined ->
            {reply, {error, service_not_found}, State};
        Service ->
            {reply, {ok, service_to_map(ServiceId, Service)}, State}
    end;

handle_call({call_service, ServiceName, Params, Options}, _From, State) ->
    case find_service_by_name(ServiceName, State) of
        {ok, ServiceId, #yawl_service_registry{status = Status}} when Status =/= active ->
            {reply, {error, {service_unavailable, Status}}, State};
        {ok, ServiceId, Service} ->
            case invoke_service(Service, Params, Options) of
                {ok, Result, ResponseTime} ->
                    %% Update service stats
                    UpdatedService = update_service_stats(Service, ResponseTime, true),
                    NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
                    NewState = State#state{services = NewServices},
                    {reply, {ok, Result}, NewState};
                {error, Reason} ->
                    %% Update service stats with failure
                    UpdatedService = update_service_stats(Service, 0, false),
                    NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
                    NewState = State#state{services = NewServices},
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({call_service_async, ServiceName, Params}, From, State) ->
    case find_service_by_name(ServiceName, State) of
        {ok, ServiceId, #yawl_service_registry{status = active} = Service} ->
            %% Spawn async caller
            Pid = self(),
            spawn(fun() ->
                Result = invoke_service(Service, Params, #{}),
                gen_server:reply(From, Result)
            end),
            {noreply, State};
        {ok, _ServiceId, #yawl_service_registry{status = Status}} ->
            {reply, {error, {service_unavailable, Status}}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({check_health, ServiceId}, _From, State) ->
    case maps:get(ServiceId, State#state.services, undefined) of
        undefined ->
            {reply, {error, service_not_found}, State};
        #yawl_service_registry{health_check_url = undefined} = Service ->
            {reply, {ok, Service#yawl_service_registry.status, 0}, State};
        Service ->
            %% Perform health check
            StartTime = erlang:monotonic_time(millisecond),
            case perform_health_check(Service) of
                {ok, ResponseTime} ->
                    UpdatedService = Service#yawl_service_registry{
                        status = active,
                        last_check = erlang:monotonic_time(millisecond),
                        response_time = ResponseTime
                    },
                    NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
                    NewState = State#state{services = NewServices},
                    {reply, {ok, active, ResponseTime}, NewState};
                {error, _} ->
                    UpdatedService = Service#yawl_service_registry{
                        status = inactive,
                        last_check = erlang:monotonic_time(millisecond)
                    },
                    NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
                    NewState = State#state{services = NewServices},
                    {reply, {ok, inactive, 0}, NewState}
            end
    end;

handle_call(check_all_health, _From, State) ->
    HealthResults = maps:map(fun(ServiceId, Service) ->
        case Service#yawl_service_registry.health_check_url of
            undefined -> Service#yawl_service_registry.status;
            _Url ->
                case perform_health_check(Service) of
                    {ok, _ResponseTime} -> active;
                    {error, _} -> inactive
                end
        end
    end, State#state.services),
    {reply, {ok, HealthResults}, State};

handle_call({set_health_status, ServiceId, Status}, _From, State) ->
    case maps:get(ServiceId, State#state.services, undefined) of
        undefined ->
            {reply, {error, service_not_found}, State};
        Service ->
            UpdatedService = Service#yawl_service_registry{
                status = Status,
                last_check = erlang:monotonic_time(millisecond)
            },
            NewServices = maps:put(ServiceId, UpdatedService, State#state.services),
            NewState = State#state{services = NewServices},
            {reply, ok, NewState}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(health_check, State) ->
    %% Perform health checks on all services with health_check_url
    NewServices = maps:map(fun(_ServiceId, Service) ->
        case Service#yawl_service_registry.health_check_url of
            undefined -> Service;
            _Url ->
                StartTime = erlang:monotonic_time(millisecond),
                case perform_health_check(Service) of
                    {ok, ResponseTime} ->
                        Service#yawl_service_registry{
                            status = active,
                            last_check = erlang:monotonic_time(millisecond),
                            response_time = ResponseTime
                        };
                    {error, _} ->
                        Service#yawl_service_registry{
                            status = inactive,
                            last_check = erlang:monotonic_time(millisecond)
                        }
                end
        end
    end, State#state.services),
    {noreply, State#state{services = NewServices}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.health_check_timer of
        undefined -> ok;
        TimerRef -> timer:cancel(TimerRef)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
generate_service_id(ServiceName) ->
    Hash = erlang:phash2(ServiceName),
    Timestamp = erlang:monotonic_time(millisecond),
    <<(binary:part(ServiceName, 0, min(byte_size(ServiceName), 32)))/binary,
      "_", (integer_to_binary(Hash))/binary,
      "_", (integer_to_binary(Timestamp))/binary>>.

%% @private
update_services_by_type(ServiceType, ServiceId, ByTypeMap) ->
    CurrentList = maps:get(ServiceType, ByTypeMap, []),
    ByTypeMap#{ServiceType => [ServiceId | CurrentList]}.

%% @private
remove_service_by_type(ServiceType, ServiceId, ByTypeMap) ->
    CurrentList = maps:get(ServiceType, ByTypeMap, []),
    ByTypeMap#{ServiceType => lists:delete(ServiceId, CurrentList)}.

%% @private
find_service_by_name(ServiceName, State) ->
    lists:foldl(fun(ServiceId, Acc) ->
        case Acc of
            {ok, _, _} -> Acc;
            {error, _} ->
                case maps:get(ServiceId, State#state.services, undefined) of
                    #yawl_service_registry{service_name = ServiceName} = Service ->
                        {ok, ServiceId, Service};
                    _ ->
                        {error, not_found}
                end
        end
    end, {error, not_found}, maps:keys(State#state.services)).

%% @private
select_best_service(ServiceIds, Services) ->
    %% Select service with highest success rate and lowest response time
    lists:foldl(fun(Id, BestId) ->
        Service = maps:get(Id, Services),
        BestService = maps:get(BestId, Services),
        case compare_services(Service, BestService) of
            better -> Id;
            worse -> BestId
        end
    end, hd(ServiceIds), ServiceIds).

%% @private
compare_services(S1, S2) ->
    S1Rate = S1#yawl_service_registry.success_rate,
    S2Rate = S2#yawl_service_registry.success_rate,
    if
        S1Rate > S2Rate -> better;
        S1Rate < S2Rate -> worse;
        true ->
            %% Equal rates, compare response time
            S1Time = S1#yawl_service_registry.response_time,
            S2Time = S2#yawl_service_registry.response_time,
            if S1Time < S2Time -> better; true -> worse end
    end.

%% @private
invoke_service(#yawl_service_registry{endpoint = Endpoint}, Params, Options) ->
    Method = maps_get(method, Options, get),
    Path = maps_get(path, Options, <<>>),
    Timeout = maps_get(timeout, Options, 5000),

    Url = case Endpoint of
        <<"http://", _/binary>> -> <<Endpoint/binary, Path/binary>>;
        <<"https://", _/binary>> -> <<Endpoint/binary, Path/binary>>;
        _ -> <<"http://", Endpoint/binary, Path/binary>>
    end,

    StartTime = erlang:monotonic_time(millisecond),

    try
        Result = case Method of
            get ->
                %% Build query string
                QueryString = build_query_string(Params),
                FullUrl = case QueryString of
                    <<>> -> Url;
                    _ -> <<Url/binary, "?", QueryString/binary>>
                end,
                httpc_request(get, {binary_to_list(FullUrl), []});
            post ->
                ContentType = maps_get(content_type, Options, <<"application/json">>),
                Body = encode_body(Params, ContentType),
                httpc_request(post, {binary_to_list(Url), [], binary_to_list(ContentType), Body});
            put ->
                ContentType = maps_get(content_type, Options, <<"application/json">>),
                Body = encode_body(Params, ContentType),
                httpc_request(put, {binary_to_list(Url), [], binary_to_list(ContentType), Body});
            delete ->
                httpc_request(delete, {Url, []})
        end,

        EndTime = erlang:monotonic_time(millisecond),
        ResponseTime = EndTime - StartTime,

        case Result of
            {ok, Response} ->
                {ok, Response, ResponseTime};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Type:Error:Stacktrace ->
            {error, {Type, Error, Stacktrace}}
    end.

%% @private
httpc_request(Method, Request) ->
    httpc:request(Method, Request, [], [{body_format, binary}]).

%% @private
build_query_string(Params) when is_map(Params) ->
   Pairs = maps:fold(fun(K, V, Acc) ->
        KBin = to_binary(K),
        VBin = to_binary(V),
        [[KBin, "=", uri_string:quote(binary_to_list(VBin))] | Acc]
    end, [], Params),
    iolist_to_binary(lists:join($&, lists:reverse(Pairs)));
build_query_string(_) ->
    <<>>.

%% @private
encode_body(Params, <<"application/json">>) ->
    jiffy:encode(Params);
encode_body(Params, <<"application/x-www-form-urlencoded">>) ->
    build_query_string(Params);
encode_body(Params, _) ->
    jiffy:encode(Params).

%% @private
perform_health_check(#yawl_service_registry{health_check_url = Url}) ->
    StartTime = erlang:monotonic_time(millisecond),
    case httpc:request(get, {binary_to_list(Url), []}, [], [{body_format, binary}]) of
        {ok, {{_, StatusCode, _}, _, _}} when StatusCode >= 200, StatusCode < 300 ->
            ResponseTime = erlang:monotonic_time(millisecond) - StartTime,
            {ok, ResponseTime};
        {ok, _} ->
            {error, unhealthy};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
update_service_stats(Service, ResponseTime, Success) ->
    CurrentRate = Service#yawl_service_registry.success_rate,
    NewRate = case Success of
        true -> (CurrentRate * 0.9) + (1.0 * 0.1);
        false -> (CurrentRate * 0.9) + (0.0 * 0.1)
    end,

    Service#yawl_service_registry{
        response_time = ResponseTime,
        success_rate = NewRate,
        last_check = erlang:monotonic_time(millisecond)
    }.

%% @private
service_to_map(ServiceId, #yawl_service_registry{} = Service) ->
    #{
        service_id => ServiceId,
        service_name => Service#yawl_service_registry.service_name,
        service_type => Service#yawl_service_registry.service_type,
        endpoint => Service#yawl_service_registry.endpoint,
        health_check_url => Service#yawl_service_registry.health_check_url,
        status => Service#yawl_service_registry.status,
        last_check => Service#yawl_service_registry.last_check,
        response_time => Service#yawl_service_registry.response_time,
        success_rate => Service#yawl_service_registry.success_rate,
        metadata => Service#yawl_service_registry.metadata
    }.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_integer(Term) -> integer_to_binary(Term);
to_binary(Term) when is_list(Term) -> list_to_binary(Term).
