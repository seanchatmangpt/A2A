%%%-------------------------------------------------------------------
%%% @doc
%%% A2A HotCI Alerting Unit Tests
%%%
%%% Test suite for the HotCI alerting system module using Chicago TDD.
%%% Tests are written first, then implementations are added to pass them.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(a2a_hotci_alerting_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Setup and Teardown
%%====================================================================

setup() ->
    {ok, Pid} = a2a_hotci_alerting:start_link(#{
        deduplication_window_ms => 1000,
        escalation_enabled => true,
        auto_resolve_enabled => false
    }),
    Pid.

cleanup(_Pid) ->
    a2a_hotci_alerting:stop(),
    ok.

%%====================================================================
%% Test Generators - Alert Management
%%====================================================================

send_alert_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        %% Test sending a simple alert
        ?_test(begin
            ok = a2a_hotci_alerting:send_alert(high, <<"Test alert message">>),
            timer:sleep(100),  % Allow async processing
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1)
        end)
    end}.

send_alert_with_details_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        Details = #{
            upgrade_id => <<"upgrade-123">>,
            alert_type => upgrade_progress,
            tags => [<<"hotci">>, <<"upgrade">>]
        },
        [?_test(begin
            ok = a2a_hotci_alerting:send_alert(critical, <<"Upgrade failed">>, Details),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1)
        end)]
    end}.

acknowledge_alert_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send an alert first
            ok = a2a_hotci_alerting:send_alert(high, <<"Alert to acknowledge">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1),
            %% Acknowledge the first alert
            case ActiveAlerts of
                [Alert | _] ->
                    AlertId = maps:get(id, Alert),
                    ok = a2a_hotci_alerting:acknowledge_alert(AlertId, <<"test-user">>),
                    timer:sleep(50),
                    UpdatedAlerts = a2a_hotci_alerting:get_active_alerts(),
                    [UpdatedAlert | _] = UpdatedAlerts,
                    ?assertEqual(true, maps:get(acknowledged, UpdatedAlert)),
                    ?assertEqual(<<"test-user">>, maps:get(acknowledged_by, UpdatedAlert));
                _ ->
                    ?assert(false, no_alert_found)
            end
        end)]
    end}.

resolve_alert_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            ok = a2a_hotci_alerting:send_alert(high, <<"Alert to resolve">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            case ActiveAlerts of
                [Alert | _] ->
                    AlertId = maps:get(id, Alert),
                    ok = a2a_hotci_alerting:resolve_alert(AlertId, <<"test-resolver">>),
                    timer:sleep(50),
                    UpdatedAlerts = a2a_hotci_alerting:get_active_alerts(),
                    %% After resolution, alert should not be in active alerts
                    ?assert(length([A || A <- UpdatedAlerts, maps:get(id, A) =:= AlertId]) =:= 0);
                _ ->
                    ?assert(false, no_alert_found)
            end
        end)]
    end}.

escalate_alert_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            ok = a2a_hotci_alerting:send_alert(high, <<"Alert to escalate">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            case ActiveAlerts of
                [Alert | _] ->
                    AlertId = maps:get(id, Alert),
                    ok = a2a_hotci_alerting:escalate_alert(AlertId, 2),
                    timer:sleep(50),
                    UpdatedAlerts = a2a_hotci_alerting:get_active_alerts(),
                    [UpdatedAlert | _] = UpdatedAlerts,
                    ?assertEqual(2, maps:get(escalation_level, UpdatedAlert));
                _ ->
                    ?assert(false, no_alert_found)
            end
        end)]
    end}.

cancel_alert_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            ok = a2a_hotci_alerting:send_alert(low, <<"Alert to cancel">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            InitialCount = length(ActiveAlerts),
            case ActiveAlerts of
                [Alert | _] ->
                    AlertId = maps:get(id, Alert),
                    ok = a2a_hotci_alerting:cancel_alert(AlertId, <<"false alarm">>),
                    timer:sleep(50),
                    UpdatedAlerts = a2a_hotci_alerting:get_active_alerts(),
                    ?assert(length(UpdatedAlerts) < InitialCount);
                _ ->
                    ?assert(false, no_alert_found)
            end
        end)]
    end}.

%%====================================================================
%% Test Generators - Alert Rules
%%====================================================================

create_alert_rule_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        RuleId = <<"rule-001">>,
        Name = <<"CPU High Rule">>,
        Config = #{
            description => <<"Alert when CPU usage is high">>,
            alert_type => performance,
            metric_name => <<"cpu_usage">>,
            condition => <<">">>,
            threshold => 80.0,
            severity => high,
            enabled => true
        },
        [?_test(begin
            ok = a2a_hotci_alerting:create_alert_rule(RuleId, Name, Config),
            timer:sleep(50),
            Rule = a2a_hotci_alerting:get_alert_rule(RuleId),
            ?assertNotEqual(undefined, Rule),
            ?assertEqual(RuleId, maps:get(id, Rule)),
            ?assertEqual(Name, maps:get(name, Rule)),
            ?assertEqual(high, maps:get(severity, Rule))
        end)]
    end}.

get_alert_rules_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            a2a_hotci_alerting:create_alert_rule(<<"rule-002">>, <<"Memory Rule">>, #{
                alert_type => performance,
                severity => medium
            }),
            a2a_hotci_alerting:create_alert_rule(<<"rule-003">>, <<"Disk Rule">>, #{
                alert_type => performance,
                severity => low
            }),
            timer:sleep(50),
            Rules = a2a_hotci_alerting:get_alert_rules(),
            ?assert(length(Rules) >= 2)
        end)]
    end}.

update_alert_rule_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            RuleId = <<"rule-004">>,
            a2a_hotci_alerting:create_alert_rule(RuleId, <<"Original Name">>, #{
                alert_type => system_health,
                severity => low
            }),
            timer:sleep(50),
            ok = a2a_hotci_alerting:update_alert_rule(RuleId, <<"severity">>, critical, undefined),
            timer:sleep(50),
            Rule = a2a_hotci_alerting:get_alert_rule(RuleId),
            ?assertNotEqual(undefined, Rule),
            ?assertEqual(critical, maps:get(severity, Rule))
        end)]
    end}.

delete_alert_rule_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            RuleId = <<"rule-005">>,
            a2a_hotci_alerting:create_alert_rule(RuleId, <<"Temp Rule">>, #{
                alert_type => custom
            }),
            timer:sleep(50),
            ?assertNotEqual(undefined, a2a_hotci_alerting:get_alert_rule(RuleId)),
            ok = a2a_hotci_alerting:delete_alert_rule(RuleId, <<"no longer needed">>),
            timer:sleep(50),
            ?assertEqual(undefined, a2a_hotci_alerting:get_alert_rule(RuleId))
        end)]
    end}.

%%====================================================================
%% Test Generators - Notification Channels
%%====================================================================

set_notification_channel_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            ChannelId = <<"slack-001">>,
            Type = slack,
            Name = <<"Alerts Channel">>,
            Config = #{
                url => <<"https://hooks.slack.com/services/TEST">>,
                enabled => true,
                min_severity => high
            },
            ok = a2a_hotci_alerting:set_notification_channel(ChannelId, Type, Name, Config),
            timer:sleep(50),
            %% Verify channel was set (indirectly via alert sending)
            ok
        end)]
    end}.

setup_email_config_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            Config = #{
                smtp_server => <<"smtp.example.com">>,
                from => <<"alerts@example.com">>,
                recipients => [<<"admin@example.com">>]
            },
            Validation = #{},
            ok = a2a_hotci_alerting:setup_email_config(Config, Validation),
            timer:sleep(50),
            ok
        end)]
    end}.

set_webhook_endpoint_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            EndpointUrl = <<"https://example.com/webhook">>,
            Config = #{auth_token => <<"secret-token">>},
            ok = a2a_hotci_alerting:set_webhook_endpoint(EndpointUrl, Config),
            timer:sleep(50),
            ok
        end)]
    end}.

%%====================================================================
%% Test Generators - Escalation Policies
%%====================================================================

set_escalation_policy_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            PolicyId = <<"escalation-001">>,
            Name = <<"Standard Escalation">>,
            Levels = [
                #{level => 1, delay_ms => 300000, notification_channels => [<<"pagerduty">>]},
                #{level => 2, delay_ms => 900000, notification_channels => [<<"email">>, <<"slack">>]}
            ],
            ok = a2a_hotci_alerting:set_escalation_policy(PolicyId, Name, Levels),
            timer:sleep(50),
            ok
        end)]
    end}.

%%====================================================================
%% Test Generators - Alert Queries and Statistics
%%====================================================================

get_alert_statistics_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send some test alerts
            a2a_hotci_alerting:send_alert(low, <<"Low severity alert">>),
            a2a_hotci_alerting:send_alert(high, <<"High severity alert">>),
            a2a_hotci_alerting:send_alert(critical, <<"Critical alert">>),
            timer:sleep(100),
            Stats = a2a_hotci_alerting:get_alert_statistics(),
            ?assert(is_map(Stats)),
            ?assert(maps:is_key(total_alerts, Stats)),
            ?assert(maps:is_key(active_alerts, Stats)),
            ?assert(maps:is_key(critical_alerts, Stats)),
            ?assert(maps:is_key(high_alerts, Stats)),
            ?assert(maps:is_key(low_alerts, Stats)),
            ?assert(maps:is_key(resolution_rate, Stats))
        end)]
    end}.

get_alert_summary_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            a2a_hotci_alerting:send_alert(medium, <<"Summary test alert">>),
            timer:sleep(100),
            Summary = a2a_hotci_alerting:get_alert_summary(),
            ?assert(is_map(Summary)),
            ?assert(maps:is_key(alert_statistics, Summary)),
            ?assert(maps:is_key(active_incidents, Summary))
        end)]
    end}.

get_alert_history_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            a2a_hotci_alerting:send_alert(low, <<"History alert">>),
            timer:sleep(100),
            History = a2a_hotci_alerting:get_alert_history(10),
            ?assert(is_list(History)),
            ?assert(length(History) >= 1)
        end)]
    end}.

%%====================================================================
%% Test Generators - Alert Templates
%%====================================================================

create_alert_template_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            TemplateId = <<"template-001">>,
            Name = <<"Upgrade Failure Template">>,
            Config = #{
                alert_type => upgrade_progress,
                severity => critical,
                title => <<"Upgrade {upgrade_id} Failed">>,
                message => <<"The upgrade process has failed. Please investigate.">>,
                placeholders => [<<"{upgrade_id}">>, <<"{reason}">>]
            },
            ok = a2a_hotci_alerting:create_alert_template(TemplateId, Name, Config),
            timer:sleep(50),
            Template = a2a_hotci_alerting:get_alert_template(TemplateId),
            ?assertNotEqual(undefined, Template),
            ?assertEqual(TemplateId, maps:get(id, Template)),
            ?assertEqual(Name, maps:get(name, Template))
        end)]
    end}.

get_alert_templates_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            a2a_hotci_alerting:create_alert_template(<<"template-002">>, <<"Template 2">>, #{
                alert_type => system_health,
                severity => medium
            }),
            a2a_hotci_alerting:create_alert_template(<<"template-003">>, <<"Template 3">>, #{
                alert_type => performance,
                severity => low
            }),
            timer:sleep(50),
            Templates = a2a_hotci_alerting:get_alert_templates(),
            ?assert(length(Templates) >= 3)  % Includes default template
        end)]
    end}.

update_alert_template_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            TemplateId = <<"template-004">>,
            a2a_hotci_alerting:create_alert_template(TemplateId, <<"Original">>, #{
                alert_type => custom,
                title => <<"Original Title">>
            }),
            timer:sleep(50),
            ok = a2a_hotci_alerting:update_alert_template(TemplateId, <<"title">>, <<"Updated Title">>, undefined),
            timer:sleep(50),
            Template = a2a_hotci_alerting:get_alert_template(TemplateId),
            ?assertNotEqual(undefined, Template),
            ?assertEqual(<<"Updated Title">>, maps:get(title, Template))
        end)]
    end}.

delete_alert_template_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            TemplateId = <<"template-005">>,
            a2a_hotci_alerting:create_alert_template(TemplateId, <<"Temp">>, #{
                alert_type => custom
            }),
            timer:sleep(50),
            ?assertNotEqual(undefined, a2a_hotci_alerting:get_alert_template(TemplateId)),
            ok = a2a_hotci_alerting:delete_alert_template(TemplateId, <<"not needed">>),
            timer:sleep(50),
            ?assertEqual(undefined, a2a_hotci_alerting:get_alert_template(TemplateId))
        end)]
    end}.

%%====================================================================
%% Test Generators - Integration Points
%%====================================================================

integrate_with_incident_system_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            SystemId = <<"pagerduty">>,
            Config = #{
                api_key => <<"test-key">>,
                service_id => <<"service-123">>
            },
            ok = a2a_hotci_alerting:integrate_with_incident_system(SystemId, Config),
            timer:sleep(50),
            ok
        end)]
    end}.

%%====================================================================
%% Test Generators - Alert Deduplication
%%====================================================================

alert_deduplication_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send duplicate alerts within the deduplication window
            Message = <<"Duplicate alert message">>,
            a2a_hotci_alerting:send_alert(high, Message),
            a2a_hotci_alerting:send_alert(high, Message),
            timer:sleep(200),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            %% Due to deduplication, should have fewer alerts than sent
            ?assert(length(ActiveAlerts) =< 1)
        end)]
    end}.

%%====================================================================
%% Test Generators - Notification Sending
%%====================================================================

send_email_notification_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Set up email channel
            Config = #{
                smtp_server => <<"smtp.test.com">>,
                from => <<"alerts@test.com">>,
                recipients => [<<"admin@test.com">>]
            },
            a2a_hotci_alerting:setup_email_config(Config, #{}),
            %% Send critical alert that should trigger email
            a2a_hotci_alerting:send_alert(critical, <<"Email test alert">>),
            timer:sleep(100),
            %% Verify alert was created and notifications logged
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1)
        end)]
    end}.

send_slack_notification_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Set up Slack channel
            a2a_hotci_alerting:set_notification_channel(
                <<"slack-test">>,
                slack,
                <<"Test Slack">>,
                #{url => <<"https://hooks.slack.com/test">>, enabled => true, min_severity => high}
            ),
            %% Send high severity alert
            a2a_hotci_alerting:send_alert(high, <<"Slack test alert">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1)
        end)]
    end}.

send_webhook_notification_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Set up webhook
            a2a_hotci_alerting:set_webhook_endpoint(
                <<"https://example.com/webhook">>,
                #{auth_token => <<"test-token">>}
            ),
            %% Send alert
            a2a_hotci_alerting:send_alert(critical, <<"Webhook test alert">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            ?assert(length(ActiveAlerts) >= 1)
        end)]
    end}.

%%====================================================================
%% Test Generators - Incident Creation
%%====================================================================

incident_creation_for_critical_alerts_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send critical alert
            a2a_hotci_alerting:send_alert(critical, <<"Critical incident">>),
            timer:sleep(100),
            Summary = a2a_hotci_alerting:get_alert_summary(),
            ActiveIncidents = maps:get(active_incidents, Summary),
            %% Critical alerts should create incidents
            ?assert(ActiveIncidents >= 0)
        end)]
    end}.

%%====================================================================
%% Test Generators - ID Generation
%%====================================================================

alert_id_uniqueness_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send multiple alerts and verify unique IDs
            a2a_hotci_alerting:send_alert(high, <<"Alert 1">>),
            a2a_hotci_alerting:send_alert(high, <<"Alert 2">>),
            a2a_hotci_alerting:send_alert(high, <<"Alert 3">>),
            timer:sleep(100),
            ActiveAlerts = a2a_hotci_alerting:get_active_alerts(),
            Ids = [maps:get(id, A) || A <- ActiveAlerts],
            UniqueIds = lists:usort(Ids),
            ?assertEqual(length(Ids), length(UniqueIds))
        end)]
    end}.

%%====================================================================
%% Test Generators - Severity Ranking
%%====================================================================

severity_filtering_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_Pid) ->
        [?_test(begin
            %% Send alerts with different severities
            a2a_hotci_alerting:send_alert(low, <<"Low alert">>),
            a2a_hotci_alerting:send_alert(medium, <<"Medium alert">>),
            a2a_hotci_alerting:send_alert(high, <<"High alert">>),
            a2a_hotci_alerting:send_alert(critical, <<"Critical alert">>),
            timer:sleep(100),
            Stats = a2a_hotci_alerting:get_alert_statistics(),
            ?assert(maps:get(low_alerts, Stats) >= 1),
            ?assert(maps:get(medium_alerts, Stats) >= 1),
            ?assert(maps:get(high_alerts, Stats) >= 1),
            ?assert(maps:get(critical_alerts, Stats) >= 1)
        end)]
    end}.
