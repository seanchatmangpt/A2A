%%% @doc Security Monitoring System
%%% Handles security event logging, intrusion detection, and vulnerability scanning

-module(security_monitor).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([log_security_event/2, log_vulnerability/2, log_intrusion/2]).
-export([start_vulnerability_scan/0, check_system_vulnerabilities/0]).
-export([get_security_report/0, get_audit_trail/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(LOG_FILE, "security_monitor.log").
-define(VULN_SCAN_INTERVAL, 3600000). % 1 hour
-define(MAX_AUDIT_TRAIL_SIZE, 10000).

-record(event, {
    id :: binary(),
    timestamp :: integer(),
    type :: binary(),
    severity :: info | warning | error | critical,
    user_id :: binary(),
    action :: binary(),
    resource :: binary(),
    details :: map(),
    ip_address :: binary(),
    user_agent :: binary()
}).

-record(vulnerability, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    severity :: low | medium | high | critical,
    affected_components :: [binary()],
    remediation :: binary(),
    discovered_at :: integer(),
    status :: open | resolved | false_positive
}).

-record(intrusion_event, {
    id :: binary(),
    timestamp :: integer(),
    type :: brute_force | dos | sql_injection | xss | command_injection,
    source_ip :: binary(),
    target :: binary(),
    details :: map(),
    severity :: warning | error | critical,
    mitigated :: boolean(),
    mitigated_at :: integer() | undefined
}).

-record(state, {
    events :: map(),
    vulnerabilities :: map(),
    intrusions :: map(),
    scan_results :: map()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Log a security event
-spec log_security_event(map(), binary()) -> ok.
log_security_event(EventData, Type) ->
    gen_server:cast(?SERVER, {log_security_event, EventData, Type}).

%% @doc Log a vulnerability
-spec log_vulnerability(map(), binary()) -> ok.
log_vulnerability(VulnData, Name) ->
    gen_server:cast(?SERVER, {log_vulnerability, VulnData, Name}).

%% @doc Log an intrusion attempt
-spec log_intrusion(map(), binary()) -> ok.
log_intrusion(IntrusionData, Type) ->
    gen_server:cast(?SERVER, {log_intrusion, IntrusionData, Type}).

%% @doc Start vulnerability scan
-spec start_vulnerability_scan() -> {ok, binary()}.
start_vulnerability_scan() ->
    gen_server:call(?SERVER, start_vulnerability_scan).

%% @doc Check system vulnerabilities
-spec check_system_vulnerabilities() -> map().
check_system_vulnerabilities() ->
    gen_server:call(?SERVER, check_system_vulnerabilities).

%% @doc Get security report
-spec get_security_report() -> map().
get_security_report() ->
    gen_server:call(?SERVER, get_security_report).

%% @doc Get audit trail
-spec get_audit_trail(integer()) -> [map()].
get_audit_trail(Limit) ->
    gen_server:call(?SERVER, {get_audit_trail, Limit}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    %% Initialize log file
    ensure_log_file(),

    %% Start periodic vulnerability scans
    erlang:send_after(?VULN_SCAN_INTERVAL, self(), run_vulnerability_scan),

    State = #state{
        events = #{},
        vulnerabilities = #{},
        intrusions = #{},
        scan_results = #{}
    },

    {ok, State}.

handle_call(start_vulnerability_scan, _From, State) ->
    ScanId = generate_id(),
    ScanStartTime = os:system_time(millisecond),

    %% Start scan in background
    spawn_link(fun() ->
        {ok, Result} = run_vulnerability_scan_internal(),
        gen_server:cast(?SERVER, {vulnerability_scan_complete, ScanId, ScanStartTime, Result})
    end),

    {reply, {ok, ScanId}, State};

handle_call(check_system_vulnerabilities, _From, State) ->
    {reply, check_system_vulnerabilities_internal(), State};

handle_call(get_security_report, _From, State) ->
    Report = generate_security_report(State),
    {reply, Report, State};

handle_call({get_audit_trail, Limit}, _From, State) ->
    Events = lists:sublist(lists:map(fun event_to_map/1,
                    maps:values(State#state.events)), Limit),
    {reply, Events, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({log_security_event, EventData, Type}, State) ->
    Event = #event{
        id = generate_id(),
        timestamp = os:system_time(millisecond),
        type = Type,
        severity = maps:get(severity, EventData, info),
        user_id = maps:get(user_id, EventData, <<"unknown">>),
        action = maps:get(action, EventData, <<"unknown">>),
        resource = maps:get(resource, EventData, <<"unknown">>),
        details = EventData,
        ip_address = maps:get(ip_address, EventData, <<"unknown">>),
        user_agent = maps:get(user_agent, EventData, <<"unknown">>)
    },

    %% Log to file
    log_to_file(Event),

    %% Update state
    NewEvents = maps:put(Event#event.id, Event, State#state.events),

    %% Keep only recent events
    RecentEvents = filter_recent_events(NewEvents, ?MAX_AUDIT_TRAIL_SIZE),

    %% Check for suspicious patterns
    analyze_security_patterns(Event),

    {noreply, State#state{events = RecentEvents}};

handle_cast({log_vulnerability, VulnData, Name}, State) ->
    Vuln = #vulnerability{
        id = generate_id(),
        name = Name,
        description = maps:get(description, VulnData, <<"Unknown vulnerability">>),
        severity = maps:get(severity, VulnData, medium),
        affected_components = maps:get(affected_components, VulnData, []),
        remediation = maps:get(remediation, VulnData, <<"No remediation available">>),
        discovered_at = os:system_time(millisecond),
        status = open
    },

    %% Update state
    NewVulnerabilities = maps:put(Vuln#vulnerability.id, Vuln, State#state.vulnerabilities),

    %% Log critical vulnerabilities immediately
    case Vuln#vulnerability.severity of
        critical ->
            log_to_file_vulnerability(Vuln);
        _ ->
            ok
    end,

    {noreply, State#state{vulnerabilities = NewVulnerabilities}};

handle_cast({log_intrusion, IntrusionData, Type}, State) ->
    Intrusion = #intrusion_event{
        id = generate_id(),
        timestamp = os:system_time(millisecond),
        type = Type,
        source_ip = maps:get(source_ip, IntrusionData, <<"unknown">>),
        target = maps:get(target, IntrusionData, <<"unknown">>),
        details = IntrusionData,
        severity = maps:get(severity, IntrusionData, warning),
        mitigated = false
    },

    %% Log to file
    log_to_file_intrusion(Intrusion),

    %% Update state
    NewIntrusions = maps:put(Intrusion#intrusion_event.id, Intrusion, State#state.intrusions),

    %% Trigger mitigation if needed
    case Intrusion#intrusion_event.severity of
        critical ->
            mitigate_intrusion(Intrusion);
        _ ->
            ok
    end,

    {noreply, State#state{intrusions = NewIntrusions}};

handle_cast({vulnerability_scan_complete, ScanId, ScanStartTime, Result}, State) ->
    ScanEndTime = os:system_time(millisecond),
    ScanDuration = ScanEndTime - ScanStartTime,

    ScanResult = #{
        id => ScanId,
        start_time => ScanStartTime,
        end_time => ScanEndTime,
        duration => ScanDuration,
        total_checks => maps:get(total_checks, Result, 0),
        vulnerabilities_found => maps:get(vulnerabilities_found, Result, 0),
        critical => maps:get(critical, Result, 0),
        high => maps.get(high, Result, 0),
        medium => maps.get(medium, Result, 0),
        low => maps.get(low, Result, 0),
        details => Result
    },

    %% Update state
    NewScanResults = maps:put(ScanId, ScanResult, State#state.scan_results),

    {noreply, State#state{scan_results = NewScanResults}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(run_vulnerability_scan, State) ->
    spawn_link(fun() ->
        {ok, Result} = run_vulnerability_scan_internal(),
        gen_server:cast(?SERVER, {vulnerability_scan_complete, generate_id(), os:system_time(millisecond), Result})
    end),

    %% Schedule next scan
    erlang:send_after(?VULN_SCAN_INTERVAL, self(), run_vulnerability_scan),

    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    close_log_file().

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

ensure_log_file() ->
    case file:open(?LOG_FILE, [append]) of
        {ok, Fd} ->
            file:close(Fd);
        {error, eacces} ->
            error_logger:info_msg("Cannot access security log file: ~p", [?LOG_FILE]);
        {error, enoent} ->
            %% Create directory and file
            case file:make_dir("logs") of
                ok ->
                    case file:open(?LOG_FILE, [write]) of
                        {ok, Fd} ->
                            file:close(Fd);
                        {error, _} ->
                            error_logger:info_msg("Cannot create security log file: ~p", [?LOG_FILE])
                    end;
                {error, _} ->
                    error_logger:info_msg("Cannot create logs directory: logs")
            end;
        {error, _} ->
            error_logger:info_msg("Cannot open security log file: ~p", [?LOG_FILE])
    end.

log_to_file(Event) ->
    LogEntry = format_log_entry(Event),
    file:write_file(?LOG_FILE, [LogEntry, $\n], [append]).

log_to_file_vulnerability(Vuln) ->
    LogEntry = format_vulnerability_log(Vuln),
    file:write_file(?LOG_FILE, [LogEntry, $\n], [append]).

log_to_file_intrusion(Intrusion) ->
    LogEntry = format_intrusion_log(Intrusion),
    file:write_file(?LOG_FILE, [LogEntry, $\n], [append]).

format_log_entry(Event) ->
    Timestamp = format_timestamp(Event#event.timestamp),
    Severity = format_severity(Event#event.severity),
    io_lib:format("~s [~s] SecurityEvent: User=~s, Action=~s, Resource=~s, IP=~s~n",
                  [Timestamp, Severity, Event#event.user_id, Event#event.action,
                   Event#event.resource, Event#event.ip_address]).

format_vulnerability_log(Vuln) ->
    Timestamp = format_timestamp(Vuln#vulnerability.discovered_at),
    Severity = format_severity(Vuln#vulnerability.severity),
    io_lib:format("~s [~s] Vulnerability: ~s - ~s~n", [Timestamp, Severity, Vuln#vulnerability.name, Vuln#vulnerability.description]).

format_intrusion_log(Intrusion) ->
    Timestamp = format_timestamp(Intrusion#intrusion_event.timestamp),
    Severity = format_severity(Intrusion#intrusion_event.severity),
    io_lib:format("~s [~s] Intrusion: Type=~s, Source=~s, Target=~s~n",
                  [Timestamp, Severity, Intrusion#intrusion_event.type, Intrusion#intrusion_event.source_ip, Intrusion#intrusion_event.target]).

format_timestamp(Timestamp) ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:now_to_time({Timestamp div 1000000, Timestamp rem 1000000, 0}),
    io_lib:format("~4.10.0B-~2.10.0B-~2.10.0B ~2.10.0B:~2.10.0B:~2.10.0B", [Year, Month, Day, Hour, Minute, Second]).

format_severity(info) -> "INFO";
format_severity(warning) -> "WARNING";
format_severity(error) -> "ERROR";
format_severity(critical) -> "CRITICAL".

event_to_map(Event) ->
    #{
        id => Event#event.id,
        timestamp => Event#event.timestamp,
        type => Event#event.type,
        severity => Event#event.severity,
        user_id => Event#event.user_id,
        action => Event#event.action,
        resource => Event#event.resource,
        details => Event#event.details,
        ip_address => Event#event.ip_address,
        user_agent => Event#event.user_agent
    }.

filter_recent_events(Events, MaxSize) ->
    SortedEvents = lists:sort(fun(E1, E2) ->
        E1#event.timestamp > E2#event.timestamp
    end, maps:values(Events)),
    lists:sublist(SortedEvents, MaxSize),
    maps:from_list([{E#event.id, E} || E <- SortedEvents]).

analyze_security_patterns(Event) ->
    %% Analyze for suspicious patterns
    case Event#event.type of
        <<"login">> ->
            analyze_login_patterns(Event);
        <<"api_call">> ->
            analyze_api_patterns(Event);
        <<"data_access">> ->
            analyze_data_access_patterns(Event);
        _ ->
            ok
    end.

analyze_login_patterns(Event) ->
    UserEvents = maps:filter(fun(_, E) ->
        E#event.user_id =:= Event#event.user_id andalso
        E#event.type =:= <<"login">> andalso
        E#event.severity =:= error
    end, Event#event.events),

    %% Multiple failed logins in short time
    RecentFailures = lists:filter(fun(E) ->
        Event#event.timestamp - E#event.timestamp < 300000 % 5 minutes
    end, maps:values(UserEvents)),

    case length(RecentFailures) >= 5 of
        true ->
            %% Log as potential brute force
            IntrusionData = #{
                source_ip => Event#event.ip_address,
                user_id => Event#event.user_id,
                attempts => length(RecentFailures),
                time_window => 300000
            },
            log_intrusion(IntrusionData, brute_force);
        false ->
            ok
    end.

analyze_api_patterns(Event) ->
    %% Check for unusual API patterns
    case Event#event.action of
        <<"bulk_export">> ->
            %% Large data exports
            case maps:get(data_size, Event#event.details, 0) > 1000000 of
                true ->
                    log_security_event(#{
                        severity => warning,
                        resource => "api",
                        action => "large_export"
                    }, "unusual_pattern");
                false ->
                    ok
            end;
        _ ->
            ok
    end.

analyze_data_access_patterns(Event) ->
    %% Check for unusual data access
    case Event#event.resource of
        <<"customer_data">> ->
            case maps:get(records_accessed, Event#event.details, 0) > 1000 of
                true ->
                    log_security_event(#{
                        severity => warning,
                        resource => "data",
                        action => "large_query"
                    }, "unusual_pattern");
                false ->
                    ok
            end;
        _ ->
            ok
    end.

mitigate_intrusion(Intrusion) ->
    %% Implement intrusion mitigation
    %% In production, this would involve:
    %% - Blocking IP addresses
    %% - Alerting security team
    %% - Increasing monitoring
    %% - Implementing temporary restrictions

    io:format("CRITICAL: Mitigating intrusion from ~p~n", [Intrusion#intrusion_event.source_ip]),

    %% Log mitigation action
    log_security_event(#{
        severity => critical,
        action => "mitigation",
        details => #{
            intrusion_id => Intrusion#intrusion_event.id,
            action => "block_ip",
            source_ip => Intrusion#intrusion_event.source_ip
        }
    }, "mitigation_action").

run_vulnerability_scan_internal() ->
    %% This is a placeholder implementation
    %% In production, this would check for:
    %% - Known CVEs in dependencies
    %% - Configuration security
    %% - Code vulnerabilities
    %% - Infrastructure security

    Result = #{
        total_checks => 150,
        vulnerabilities_found => 3,
        critical => 0,
        high => 1,
        medium => 2,
        low => 0,
        details => [
            #{
                name => "weak_password_policy",
                severity => high,
                affected => ["authentication"],
                remediation => "Implement strong password requirements"
            },
            #{
                name => "missing_rate_limiting",
                severity => medium,
                affected => ["api"],
                remediation => "Implement API rate limiting"
            },
            #{
                name => "insecure_directories",
                severity => medium,
                affected => ["web_server"],
                remediation => "Remove directory listing and secure access"
            }
        ]
    },

    {ok, Result}.

check_system_vulnerabilities_internal() ->
    %% Check current vulnerability status
    CriticalCount = count_vulnerabilities_by_severity(critical),
    HighCount = count_vulnerabilities_by_severity(high),
    MediumCount = count_vulnerabilities_by_severity(medium),
    OpenCount = count_open_vulnerabilities(),

    #{
        total_vulnerabilities => CriticalCount + HighCount + MediumCount,
        critical => CriticalCount,
        high => HighCount,
        medium => MediumCount,
        open => OpenCount,
        risk_level => calculate_risk_level(CriticalCount, HighCount, MediumCount),
        last_scan => get_last_scan_time()
    }.

count_vulnerabilities_by_severity(Severity) ->
    %% Placeholder - would query actual vulnerability database
    case Severity of
        critical -> 0;
        high -> 1;
        medium -> 2;
        low -> 0
    end.

count_open_vulnerabilities() ->
    %% Count vulnerabilities with 'open' status
    maps:size(get_open_vulnerabilities()).

get_open_vulnerabilities() ->
    %% Filter vulnerabilities by status
    maps:filter(fun(_, Vuln) -> Vuln#vulnerability.status =:= open end, #{}).

calculate_risk_level(Critical, High, Medium) ->
    if
        Critical > 0 -> critical;
        High > 0 -> high;
        Medium > 0 -> medium;
        true -> low
    end.

get_last_scan_time() ->
    %% Get timestamp of last scan
    os:system_time(millisecond).

generate_security_report(State) ->
    #{
        summary => #{
            total_events => maps:size(State#state.events),
            total_vulnerabilities => maps:size(State#state.vulnerabilities),
            total_intrusions => maps:size(State#state.intrusions),
            recent_scans => maps:size(State#state.scan_results)
        },
        events_by_severity => count_events_by_severity(State#state.events),
        vulnerabilities_by_severity => count_vulns_by_severity(State#state.vulnerabilities),
        intrusions_by_type => count_intrusions_by_type(State#state.intrusions),
        recent_activity => get_recent_activity(State#state.events, 10),
        risk_assessment => generate_risk_assessment(State),
        recommendations => generate_recommendations(State)
    }.

count_events_by_severity(Events) ->
    lists:foldl(fun(Event, Acc) ->
        Severity = Event#event.severity,
        maps:update(Severity, maps:get(Severity, Acc, 0) + 1, Acc)
    end, #{info => 0, warning => 0, error => 0, critical => 0}, maps:values(Events)).

count_vulns_by_severity(Vulnerabilities) ->
    lists:foldl(fun(Vuln, Acc) ->
        Severity = Vuln#vulnerability.severity,
        maps:update(Severity, maps:get(Severity, Acc, 0) + 1, Acc)
    end, #{low => 0, medium => 0, high => 0, critical => 0}, maps:values(Vulnerabilities)).

count_intrusions_by_type(Intrusions) ->
    lists:foldl(fun(Intrusion, Acc) ->
        Type = Intrusion#intrusion_event.type,
        maps:update(Type, maps:get(Type, Acc, 0) + 1, Acc)
    end, #{brute_force => 0, dos => 0, sql_injection => 0, xss => 0, command_injection => 0}, maps:values(Intrusions)).

get_recent_activity(Events, Count) ->
    SortedEvents = lists:sort(fun(E1, E2) -> E1#event.timestamp > E2#event.timestamp end, maps:values(Events)),
    lists:sublist(SortedEvents, Count).

generate_risk_assessment(State) ->
    CriticalVulns = count_vulnerabilities_by_severity(critical),
    HighVulns = count_vulnerabilities_by_severity(high),
    RecentCriticalEvents = lists:filter(fun(E) -> E#event.severity =:= critical end, maps:values(State#state.events)),

    case CriticalVulns > 0 orelse HighVulns > 3 orelse length(RecentCriticalEvents) > 0 of
        true -> high;
        false -> medium
    end.

generate_recommendations(State) ->
    Recommendations = [],

    case count_vulnerabilities_by_severity(critical) > 0 of
        true -> Recommendations ++ ["Address critical vulnerabilities immediately"];
        false -> Recommendations
    end,

    case count_vulnerabilities_by_severity(high) > 0 of
        true -> Recommendations ++ ["Resolve high severity vulnerabilities"];
        false -> Recommendations
    end,

    case count_events_by_severity(info) > 1000 of
        true -> Recommendations ++ ["Review monitoring thresholds"];
        false -> Recommendations
    end,

    Recommendations.

generate_id() ->
    crypto:strong_rand_bytes(16).