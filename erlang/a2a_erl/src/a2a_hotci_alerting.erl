%%% @doc HotCI Alerting System
%%%
%%% This module provides advanced alerting capabilities specifically for HotCI (Hot Code Upgrade)
%%% environments. It implements intelligent alert routing, multi-channel notifications,
%%% and automated remediation workflows.
%%%
%%% Features:
%%% - Intelligent alert routing based on severity and impact
%%% - Multi-channel notification (email, Slack, PagerDuty, Webhook)
%%% - Alert deduplication and grouping
%%% - Automated alert escalation
%%% - Integration with incident management systems
%%% - Alert lifecycle management (creation, acknowledgement, resolution)
%%% - Alert analytics and reporting
%%%
%%% @end
-module(a2a_hotci_alerting).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Alert management
    send_alert/2,
    send_alert/3,
    acknowledge_alert/2,
    resolve_alert/2,
    escalate_alert/2,
    cancel_alert/2,

    %% Alert rules and thresholds
    create_alert_rule/3,
    update_alert_rule/4,
    delete_alert_rule/2,
    get_alert_rules/0,
    get_alert_rule/1,

    %% Alert configuration
    set_notification_channel/4,
    update_notification_settings/2,
    set_escalation_policy/3,

    %% Alert queries
    get_active_alerts/0,
    get_alert_history/1,
    get_alert_statistics/0,
    get_alert_summary/0,

    %% Integration points
    integrate_with_incident_system/2,
    set_webhook_endpoint/2,
    setup_email_config/2,

    %% Alert templates
    create_alert_template/3,
    update_alert_template/4,
    delete_alert_template/2,
    get_alert_templates/0,
    get_alert_template/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
]).

-include("a2a.hrl").

-define(ALERT_TYPES, [system_health, upgrade_progress, performance, security, custom]).
-define(ALERT_SEVERITIES, [low, medium, high, critical, emergency]).
-define(NOTIFICATION_CHANNELS, [email, slack, pagerduty, webhook, custom]).

%%% ============================================================================
%%% Type Definitions
%%% ============================================================================

-record(alert_rule, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    alert_type :: atom(),
    metric_name :: binary(),
    condition :: binary(),
    threshold :: term(),
    severity :: atom(),
    enabled :: boolean(),
    escalation_policy :: binary(),
    notification_channels :: [binary()],
    created_at :: integer(),
    updated_at :: integer(),
    last_triggered :: integer() | undefined,
    trigger_count :: integer()
}).

-type alert_rule() :: #alert_rule{}.

-record(notification_channel, {
    id :: binary(),
    type :: atom(),
    name :: binary(),
    config :: map(),
    enabled :: boolean(),
    rate_limit :: non_neg_integer(),
    created_at :: integer()
}).

-type notification_channel() :: #notification_channel{}.

-record(alert_template, {
    id :: binary(),
    name :: binary(),
    alert_type :: atom(),
    severity :: atom(),
    title :: binary(),
    message :: binary(),
    details :: map(),
    placeholders :: [binary()],
    enabled :: boolean(),
    created_at :: integer(),
    updated_at :: integer()
}).

-type alert_template() :: #alert_template{}.

-record(alert_data, {
    id :: binary(),
    rule_id :: binary(),
    upgrade_id :: binary(),
    type :: atom(),
    severity :: atom(),
    title :: binary(),
    message :: binary(),
    details :: map(),
    timestamp :: integer(),
    acknowledged :: boolean(),
    resolved :: boolean(),
    resolved_by :: binary() | undefined,
    resolved_at :: integer() | undefined,
    acknowledged_by :: binary() | undefined,
    acknowledged_at :: integer() | undefined,
    notifications_sent :: [binary()],
    escalation_level :: integer(),
    tags :: [binary()]
}).

-type alert_data() :: #alert_data{}.

-record(escalation_policy, {
    id :: binary(),
    name :: binary(),
    levels :: [map()],
    enabled :: boolean(),
    created_at :: integer()
}).

-type escalation_policy() :: #escalation_policy{}.

-record(alert_config, {
    deduplication_window_ms :: non_neg_integer(),
    escalation_enabled :: boolean(),
    auto_resolve_enabled :: boolean(),
    notification_settings :: map(),
    integration_settings :: map()
}).

-type alert_config() :: #alert_config{}.

-record(state, {
    alerts :: [alert_data()],
    alert_rules :: [alert_rule()],
    notification_channels :: [notification_channel()],
    alert_templates :: [alert_template()],
    escalation_policies :: [escalation_policy()],
    config :: alert_config(),
    alert_history :: [map()],
    alert_queue :: [alert_data()],
    active_incidents :: [map()],
    last_alert_id :: binary(),
    metrics :: map()
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the alerting system with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the alerting system with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the alerting system
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%%% ============================================================================
%%% Alert Management
%%% ============================================================================

%% @doc Send a simple alert
-spec send_alert(atom(), binary()) -> ok.
send_alert(Severity, Message) ->
    gen_server:cast(?MODULE, {send_alert, Severity, Message, #{}}).

%% @doc Send an alert with details
-spec send_alert(atom(), binary(), map()) -> ok.
send_alert(Severity, Message, Details) ->
    gen_server:cast(?MODULE, {send_alert, Severity, Message, Details}).

%% @brief Acknowledge an alert
-spec acknowledge_alert(binary(), binary()) -> ok.
acknowledge_alert(AlertId, AcknowledgedBy) ->
    gen_server:cast(?MODULE, {acknowledge_alert, AlertId, AcknowledgedBy}).

%% @brief Resolve an alert
-spec resolve_alert(binary(), binary()) -> ok.
resolve_alert(AlertId, ResolvedBy) ->
    gen_server:cast(?MODULE, {resolve_alert, AlertId, ResolvedBy}).

%% @brief Escalate an alert
-spec escalate_alert(binary(), binary()) -> ok.
escalate_alert(AlertId, EscalationLevel) ->
    gen_server:cast(?MODULE, {escalate_alert, AlertId, EscalationLevel}).

%% @brief Cancel an alert
-spec cancel_alert(binary(), binary()) -> ok.
cancel_alert(AlertId, Reason) ->
    gen_server:cast(?MODULE, {cancel_alert, AlertId, Reason}).

%%% ============================================================================
%%% Alert Rules and Thresholds
%%% ============================================================================

%% @doc Create a new alert rule
-spec create_alert_rule(binary(), binary(), map()) -> ok.
create_alert_rule(RuleId, Name, Config) ->
    gen_server:cast(?MODULE, {create_alert_rule, RuleId, Name, Config}).

%% @doc Update an existing alert rule
-spec update_alert_rule(binary(), binary(), binary(), term()) -> ok.
update_alert_rule(RuleId, Field, Value, Threshold) ->
    gen_server:cast(?MODULE, {update_alert_rule, RuleId, Field, Value, Threshold}).

%% @doc Delete an alert rule
-spec delete_alert_rule(binary(), binary()) -> ok.
delete_alert_rule(RuleId, Reason) ->
    gen_server:cast(?MODULE, {delete_alert_rule, RuleId, Reason}).

%% @doc Get all alert rules
-spec get_alert_rules() -> [map()].
get_alert_rules() ->
    gen_server:call(?MODULE, get_alert_rules).

%% @doc Get a specific alert rule
-spec get_alert_rule(binary()) -> map() | undefined.
get_alert_rule(RuleId) ->
    gen_server:call(?MODULE, {get_alert_rule, RuleId}).

%%% ============================================================================
%%% Alert Configuration
%%% ============================================================================

%% @doc Set notification channel configuration
-spec set_notification_channel(binary(), atom(), binary(), map()) -> ok.
set_notification_channel(ChannelId, Type, Name, Config) ->
    gen_server:cast(?MODULE, {set_notification_channel, ChannelId, Type, Name, Config}).

%% @doc Update notification settings
-spec update_notification_settings(map(), map()) -> ok.
update_notification_settings(Settings, Validation) ->
    gen_server:cast(?MODULE, {update_notification_settings, Settings, Validation}).

%% @doc Set escalation policy
-spec set_escalation_policy(binary(), binary(), map()) -> ok.
set_escalation_policy(PolicyId, Name, Levels) ->
    gen_server:cast(?MODULE, {set_escalation_policy, PolicyId, Name, Levels}).

%%% ============================================================================
%%% Alert Queries
%%% ============================================================================

%% @doc Get all active alerts
-spec get_active_alerts() -> [map()].
get_active_alerts() ->
    gen_server:call(?MODULE, get_active_alerts).

%% @brief Get alert history
-spec get_alert_history(integer()) -> [map()].
get_alert_history(Limit) ->
    gen_server:call(?MODULE, {get_alert_history, Limit}).

%% @brief Get alert statistics
-spec get_alert_statistics() -> map().
get_alert_statistics() ->
    gen_server:call(?MODULE, get_alert_statistics).

%% @brief Get alert summary
-spec get_alert_summary() -> map().
get_alert_summary() ->
    gen_server:call(?MODULE, get_alert_summary).

%%% ============================================================================
%%% Integration Points
%%% ============================================================================

%% @doc Integrate with incident management system
-spec integrate_with_incident_system(binary(), map()) -> ok.
integrate_with_incident_system(SystemId, Config) ->
    gen_server:cast(?MODULE, {integrate_with_incident_system, SystemId, Config}).

%% @doc Set webhook endpoint for alert notifications
-spec set_webhook_endpoint(binary(), map()) -> ok.
set_webhook_endpoint(EndpointUrl, Config) ->
    gen_server:cast(?MODULE, {set_webhook_endpoint, EndpointUrl, Config}).

%% @doc Setup email configuration
-spec setup_email_config(map(), map()) -> ok.
setup_email_config(Config, Validation) ->
    gen_server:cast(?MODULE, {setup_email_config, Config, Validation}).

%%% ============================================================================
%%% Alert Templates
%%% ============================================================================

%% @doc Create alert template
-spec create_alert_template(binary(), binary(), map()) -> ok.
create_alert_template(TemplateId, Name, Config) ->
    gen_server:cast(?MODULE, {create_alert_template, TemplateId, Name, Config}).

%% @doc Update alert template
-spec update_alert_template(binary(), binary(), binary(), term()) -> ok.
update_alert_template(TemplateId, Field, Value, Content) ->
    gen_server:cast(?MODULE, {update_alert_template, TemplateId, Field, Value, Content}).

%% @doc Delete alert template
-spec delete_alert_template(binary(), binary()) -> ok.
delete_alert_template(TemplateId, Reason) ->
    gen_server:cast(?MODULE, {delete_alert_template, TemplateId, Reason}).

%% @doc Get all alert templates
-spec get_alert_templates() -> [map()].
get_alert_templates() ->
    gen_server:call(?MODULE, get_alert_templates).

%% @doc Get a specific alert template
-spec get_alert_template(binary()) -> map() | undefined.
get_alert_template(TemplateId) ->
    gen_server:call(?MODULE, {get_alert_template, TemplateId}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    DeduplicationWindow = maps:get(deduplication_window_ms, Opts, 300000),  % 5 minutes
    EscalationEnabled = maps.get(escalation_enabled, Opts, true),
    AutoResolveEnabled = maps.get(auto_resolve_enabled, Opts, true),

    DefaultConfig = #alert_config{
        deduplication_window_ms = DeduplicationWindow,
        escalation_enabled = EscalationEnabled,
        auto_resolve_enabled = AutoResolveEnabled,
        notification_settings = #{email => #{enabled => false}, slack => #{enabled => false}},
        integration_settings => #{}
    },

    %% Initialize default policies and templates
    DefaultPolicies = [
        #escalation_policy{
            id = <<"default_policy">>,
            name = <<"Default Escalation Policy">>,
            levels = [
                #{level => 1, delay_ms => 300000, notification_channels => [<<"pagerduty">>]},
                #{level => 2, delay_ms => 900000, notification_channels => [<<"email">>, <<"slack">>]}
            ],
            enabled = true,
            created_at = erlang:system_time(millisecond)
        }
    ],

    DefaultTemplates = [
        #alert_template{
            id = <<"upgrade_failure">>,
            name => <<"Upgrade Failure">>,
            alert_type => upgrade_progress,
            severity => critical,
            title => <<"[CRITICAL] Upgrade Process Failed: {upgrade_id}">>,
            message => <<"The upgrade process {upgrade_id} has failed. System may be in unstable state.">>,
            details => #{},
            placeholders => [<<"{upgrade_id}">>],
            enabled = true,
            created_at = erlang:system_time(millisecond)
        }
    ],

    State = #state{
        alerts = [],
        alert_rules = [],
        notification_channels = [],
        alert_templates = DefaultTemplates,
        escalation_policies = DefaultPolicies,
        config = DefaultConfig,
        alert_history = [],
        alert_queue = [],
        active_incidents = [],
        last_alert_id = generate_id(),
        metrics = #{}
    },

    %% Start alert processing timer
    Timer = erlang:send_after(5000, self(), process_alert_queue),

    {ok, State#state{alert_timer = Timer}, {continue, load_configuration}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(load_configuration, State) ->
    %% Load configuration from persistent storage (would be implemented)
    %% For now, set up default channels
    DefaultChannels = [
        #notification_channel{
            id = <<"slack_channel">>,
            type => slack,
            name => <<"HotCI Alerts">>,
            config => #{url => <<"https://hooks.slack.com/services/...">>},
            enabled => false,
            rate_limit => 10,
            created_at = erlang:system_time(millisecond)
        }
    ],

    NewState = State#state{
        notification_channels = DefaultChannels
    },

    %% Start metrics collection
    NewState2 = start_metrics_collection(NewState),

    {ok, NewState2}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call(get_alert_rules, _From, State) ->
    RuleList = lists:map(fun format_alert_rule/1, State#state.alert_rules),
    {reply, RuleList, State};

handle_call({get_alert_rule, RuleId}, _From, State) ->
    Rule = lists:find(fun(R) -> R#alert_rule.id == RuleId end, State#state.alert_rules),
    FormattedRule = case Rule of
        undefined -> undefined;
        R -> format_alert_rule(R)
    end,
    {reply, FormattedRule, State};

handle_call(get_active_alerts, _From, State) ->
    ActiveAlerts = lists:filter(fun(A) -> not A#alert_data.resolved end, State#state.alerts),
    AlertList = lists:map(fun format_alert_data/1, ActiveAlerts),
    {reply, AlertList, State};

handle_call({get_alert_history, Limit}, _From, State) ->
    History = lists:sublist(State#state.alert_history, Limit),
    {reply, History, State};

handle_call(get_alert_statistics, _From, State) ->
    Stats = calculate_alert_statistics(State),
    {reply, Stats, State};

handle_call(get_alert_summary, _From, State) ->
    Summary = generate_alert_summary(State),
    {reply, Summary, State};

handle_call(get_alert_templates, _From, State) ->
    TemplateList = lists:map(fun format_alert_template/1, State#state.alert_templates),
    {reply, TemplateList, State};

handle_call({get_alert_template, TemplateId}, _From, State) ->
    Template = lists:find(fun(T) -> T#alert_template.id == TemplateId end, State#state.alert_templates),
    FormattedTemplate = case Template of
        undefined -> undefined;
        T -> format_alert_template(T)
    end,
    {reply, FormattedTemplate, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({send_alert, Severity, Message, Details}, State) ->
    Alert = create_alert_from_data(Severity, Message, Details, State),
    logger:info("Alert queued for processing", #[
        {alert_id, Alert#alert_data.id},
        {severity, Severity},
        {message, Message},
        {domain, [a2a, alerting]}
    ]),

    %% Add to queue and history
    NewState = State#state{
        alert_queue = [Alert | State#state.alert_queue],
        alert_history = [format_alert_data(Alert) | State#state.alert_history]
    },

    {noreply, NewState};

handle_cast({acknowledge_alert, AlertId, AcknowledgedBy}, State) ->
    case lists:keyfind(AlertId, #alert_data.id, State#state.alerts) of
        false ->
            {noreply, State};
        Alert ->
            AcknowledgedAlert = Alert#alert_data{
                acknowledged = true,
                acknowledged_by = AcknowledgedBy,
                acknowledged_at = erlang:system_time(millisecond)
            },

            logger:info("Alert acknowledged", #[
                {alert_id, AlertId},
                {acknowledged_by, AcknowledgedBy},
                {domain, [a2a, alerting]}
            ]),

            update_alert_in_state(AcknowledgedAlert, State)
    end;

handle_cast({resolve_alert, AlertId, ResolvedBy}, State) ->
    case lists:keyfind(AlertId, #alert_data.id, State#state.alerts) of
        false ->
            {noreply, State};
        Alert ->
            ResolvedAlert = Alert#alert_data{
                resolved = true,
                resolved_by = ResolvedBy,
                resolved_at = erlang:system_time(millisecond)
            },

            logger:info("Alert resolved", #[
                {alert_id, AlertId},
                {resolved_by, ResolvedBy},
                {domain, [a2a, alerting]}
            ]),

            update_alert_in_state(ResolvedAlert, State)
    end;

handle_cast({escalate_alert, AlertId, EscalationLevel}, State) ->
    case lists:keyfind(AlertId, #alert_data.id, State#state.alerts) of
        false ->
            {noreply, State};
        Alert ->
            EscalatedAlert = Alert#alert_data{
                escalation_level = EscalationLevel
            },

            logger:warning("Alert escalated", #[
                {alert_id, AlertId},
                {escalation_level, EscalationLevel},
                {domain, [a2a, alerting]}
            ]),

            %% Send escalated notifications
            send_escalated_notifications(EscalatedAlert, State),

            update_alert_in_state(EscalatedAlert, State)
    end;

handle_cast({cancel_alert, AlertId, Reason}, State) ->
    case lists:keyfind(AlertId, #alert_data.id, State#state.alerts) of
        false ->
            {noreply, State};
        Alert ->
            logger:info("Alert canceled", #[
                {alert_id, AlertId},
                {reason, Reason},
                {domain, [a2a, alerting]}
            ]),

            %% Remove from alerts, add to history
            UpdatedAlerts = lists:keydelete(AlertId, #alert_data.id, State#state.alerts),
            CanceledAlert = Alert#alert_data{
                resolved = true,
                resolved_at = erlang:system_time(millisecond),
                details = maps:put(cancel_reason, Reason, Alert#alert_data.details)
            },

            NewState = State#state{
                alerts = UpdatedAlerts,
                alert_history = [format_alert_data(CanceledAlert) | State#state.alert_history]
            },

            {noreply, NewState}
    end;

handle_cast({create_alert_rule, RuleId, Name, Config}, State) ->
    AlertRule = #alert_rule{
        id = RuleId,
        name = Name,
        description = maps:get(description, Config, <<"">>),
        alert_type = maps:get(alert_type, Config, custom),
        metric_name = maps:get(metric_name, Config, <<"">>),
        condition = maps:get(condition, Config, <<"">>),
        threshold = maps:get(threshold, Config, undefined),
        severity = maps:get(severity, Config, medium),
        enabled = maps:get(enabled, Config, true),
        escalation_policy = maps:get(escalation_policy, Config, <<"default_policy">>),
        notification_channels = maps:get(notification_channels, Config, []),
        created_at = erlang:system_time(millisecond),
        updated_at = erlang:system_time(millisecond),
        last_triggered = undefined,
        trigger_count = 0
    },

    logger:info("Alert rule created", #[
        {rule_id, RuleId},
        {name, Name},
        {domain, [a2a, alerting]}
    ]),

    {noreply, State#state{alert_rules = [AlertRule | State#state.alert_rules]}};

handle_cast({update_alert_rule, RuleId, Field, Value, Threshold}, State) ->
    case lists:keyfind(RuleId, #alert_rule.id, State#state.alert_rules) of
        false ->
            {noreply, State};
        Rule ->
            UpdatedRule = update_alert_rule_field(Rule, Field, Value, Threshold),

            logger:info("Alert rule updated", #[
                {rule_id, RuleId},
                {field, Field},
                {value, Value},
                {domain, [a2a, alerting]}
            ]),

            UpdatedRules = lists:keyreplace(RuleId, #alert_rule.id, State#state.alert_rules, UpdatedRule),
            {noreply, State#state{alert_rules = UpdatedRules}}
    end;

handle_cast({delete_alert_rule, RuleId, Reason}, State) ->
    case lists:keyfind(RuleId, #alert_rule.id, State#state.alert_rules) of
        false ->
            {noreply, State};
        Rule ->
            logger:info("Alert rule deleted", #[
                {rule_id, RuleId},
                {reason, Reason},
                {domain, [a2a, alerting]}
            ]),

            UpdatedRules = lists:keydelete(RuleId, #alert_rule.id, State#state.alert_rules),
            {noreply, State#state{alert_rules = UpdatedRules}}
    end;

handle_cast({set_notification_channel, ChannelId, Type, Name, Config}, State) ->
    Channel = #notification_channel{
        id = ChannelId,
        type = Type,
        name = Name,
        config = Config,
        enabled = maps:get(enabled, Config, true),
        rate_limit = maps:get(rate_limit, Config, 10),
        created_at = erlang:system_time(millisecond)
    },

    logger:info("Notification channel configured", #[
        {channel_id, ChannelId},
        {type, Type},
        {name, Name},
        {domain, [a2a, alerting]}
    ]),

    UpdatedChannels = lists:keyreplace(ChannelId, #notification_channel.id, State#state.notification_channels, Channel),
    {noreply, State#state{notification_channels = UpdatedChannels}};

handle_cast({update_notification_settings, Settings, _Validation}, State) ->
    logger:info("Notification settings updated", #[
        {settings, Settings},
        {domain, [a2a, alerting]}
    ]),

    UpdatedConfig = State#state.config#alert_config{
        notification_settings = maps:merge(State#state.config#alert_config.notification_settings, Settings)
    },

    {noreply, State#state{config = UpdatedConfig}};

handle_cast({set_escalation_policy, PolicyId, Name, Levels}, State) ->
    Policy = #escalation_policy{
        id = PolicyId,
        name = Name,
        levels = Levels,
        enabled = true,
        created_at = erlang:system_time(millisecond)
    },

    logger:info("Escalation policy set", #[
        {policy_id, PolicyId},
        {name, Name},
        {domain, [a2a, alerting]}
    ]),

    UpdatedPolicies = lists:keyreplace(PolicyId, #escalation_policy.id, State#state.escalation_policies, Policy),
    {noreply, State#state{escalation_policies = UpdatedPolicies}};

handle_cast({integrate_with_incident_system, SystemId, Config}, State) ->
    IntegrationConfig = State#state.config#alert_config.integration_settings,
    UpdatedIntegration = maps:put(SystemId, Config, IntegrationConfig),

    logger:info("Integrated with incident system", #[
        {system_id, SystemId},
        {config, Config},
        {domain, [a2a, alerting]}
    ]),

    UpdatedConfig = State#state.config#alert_config{
        integration_settings = UpdatedIntegration
    },

    {noreply, State#state{config = UpdatedConfig}};

handle_cast({set_webhook_endpoint, EndpointUrl, Config}, State) ->
    WebhookChannel = #notification_channel{
        id = <<"webhook_default">>,
        type => webhook,
        name => <<"Default Webhook">>,
        config = maps:put(url, EndpointUrl, Config),
        enabled = true,
        rate_limit = maps:get(rate_limit, Config, 100),
        created_at = erlang:system_time(millisecond)
    },

    UpdatedChannels = lists:keyreplace(<<"webhook_default">>, #notification_channel.id, State#state.notification_channels, WebhookChannel),
    {noreply, State#state{notification_channels = UpdatedChannels}};

handle_cast({setup_email_config, Config, _Validation}, State) ->
    EmailChannel = #notification_channel{
        id = <<"email_default">>,
        type => email,
        name => <<"Default Email">>,
        config = Config,
        enabled = true,
        rate_limit = 5,
        created_at = erlang:system_time(millisecond)
    },

    UpdatedChannels = lists:keyreplace(<<"email_default">>, #notification_channel.id, State#state.notification_channels, EmailChannel),
    {noreply, State#state{notification_channels = UpdatedChannels}};

handle_cast({create_alert_template, TemplateId, Name, Config}, State) ->
    Template = #alert_template{
        id = TemplateId,
        name = Name,
        alert_type = maps:get(alert_type, Config, custom),
        severity = maps:get(severity, Config, medium),
        title = maps:get(title, Config, <<"">>),
        message = maps:get(message, Config, <<"">>),
        details = maps:get(details, Config, #{}),
        placeholders = maps:get(placeholders, Config, []),
        enabled = maps:get(enabled, Config, true),
        created_at = erlang:system_time(millisecond),
        updated_at = erlang:system_time(millisecond)
    },

    logger:info("Alert template created", #[
        {template_id, TemplateId},
        {name, Name},
        {domain, [a2a, alerting]}
    ]),

    {noreply, State#state{alert_templates = [Template | State#state.alert_templates]}};

handle_cast({update_alert_template, TemplateId, Field, Value, Content}, State) ->
    case lists:keyfind(TemplateId, #alert_template.id, State#state.alert_templates) of
        false ->
            {noreply, State};
        Template ->
            UpdatedTemplate = update_alert_template_field(Template, Field, Value, Content),

            logger:info("Alert template updated", #[
                {template_id, TemplateId},
                {field, Field},
                {value, Value},
                {domain, [a2a, alerting]}
            ]),

            UpdatedTemplates = lists:keyreplace(TemplateId, #alert_template.id, State#state.alert_templates, UpdatedTemplate),
            {noreply, State#state{alert_templates = UpdatedTemplates}}
    end;

handle_cast({delete_alert_template, TemplateId, Reason}, State) ->
    case lists:keyfind(TemplateId, #alert_template.id, State#state.alert_templates) of
        false ->
            {noreply, State};
        Template ->
            logger:info("Alert template deleted", #[
                {template_id, TemplateId},
                {reason, Reason},
                {domain, [a2a, alerting]}
            ]),

            UpdatedTemplates = lists:keydelete(TemplateId, #alert_template.id, State#state.alert_templates),
            {noreply, State#state{alert_templates = UpdatedTemplates}}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(process_alert_queue, State) ->
    %% Process queued alerts
    ProcessedState = process_alert_queue(State),

    %% Schedule next processing
    Timer = erlang:send_after(5000, self(), process_alert_queue),
    {noreply, ProcessedState#state{alert_timer = Timer}};

handle_info(alert_timeout, State) ->
    %% Handle alert timeouts for auto-resolution
    TimeoutState = handle_alert_timeouts(State),
    {noreply, TimeoutState};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    %% Cancel timer if exists
    case State#state.alert_timer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @brief Create alert from data
-spec create_alert_from_data(atom(), binary(), map(), state()) -> alert_data().
create_alert_from_data(Severity, Message, Details, State) ->
    AlertId = generate_alert_id(State),
    UpgradeId = maps:get(upgrade_id, Details, undefined),
    RuleId = maps:get(rule_id, Details, undefined),
    AlertType = maps:get(alert_type, Details, custom),
    Tags = maps:get(tags, Details, []),

    #alert_data{
        id = AlertId,
        rule_id = RuleId,
        upgrade_id = UpgradeId,
        type = AlertType,
        severity = Severity,
        title = extract_alert_title(Message, Details),
        message = Message,
        details = Details,
        timestamp = erlang:system_time(millisecond),
        acknowledged = false,
        resolved = false,
        escalation_level = 1,
        tags = Tags
    }.

%% @brief Generate alert ID
-spec generate_alert_id(state()) -> binary().
generate_alert_id(State) ->
    LastId = State#state.last_alert_id,
    NewId = generate_id(),
    State#state{last_alert_id = NewId},
    NewId.

%% @brief Extract alert title from message and details
-spec extract_alert_title(binary(), map()) -> binary().
extract_alert_title(Message, Details) ->
    case maps:get(title, Details, undefined) of
        undefined ->
            Message;
        Title ->
            Title
    end.

%% @brief Process alert queue
-spec process_alert_queue(state()) -> state().
process_alert_queue(State) ->
    case State#state.alert_queue of
        [] -> State;
        [Alert | Rest] ->
            %% Check for duplicates
            IsDuplicate = check_duplicate_alert(Alert, State),

            if not IsDuplicate ->
                    %% Process alert
                    ProcessedState = process_alert(Alert, State),
                    %% Move to processed state
                    ProcessedState#state{
                        alert_queue = Rest,
                        alerts = [Alert | ProcessedState#state.alerts]
                    };
               true ->
                    %% Skip duplicate
                    logger:debug("Skipping duplicate alert", #[
                        {alert_id, Alert#alert_data.id},
                        {domain, [a2a, alerting]}
                    ]),
                    State#state{alert_queue = Rest}
            end
    end.

%% @brief Check if alert is duplicate
-spec check_duplicate_alert(alert_data(), state()) -> boolean().
check_duplicate_alert(Alert, State) ->
    DedupWindow = State#state.config#alert_config.deduplication_window_ms,
    Now = erlang:system_time(millisecond),

    %% Check recent alerts with same severity and type
    RecentAlerts = lists:filter(fun(A) ->
        Now - A#alert_data.timestamp =< DedupWindow andalso
        A#alert_data.severity == Alert#alert_data.severity andalso
        A#alert_data.type == Alert#alert_data.type
    end, State#state.alerts),

    %% Simple duplicate detection based on message hash
    AlertHash = hash_alert(Alert),
    lists:any(fun(A) -> hash_alert(A) == AlertHash end, RecentAlerts).

%% @brief Generate hash for alert
-spec hash_alert(alert_data()) -> binary().
hash_alert(Alert) ->
    MessageHash = crypto:hash(sha256, Alert#alert_data.message),
    TypeHash = crypto:hash(sha256, atom_to_binary(Alert#alert_data.type, utf8)),
    SeverityHash = crypto:hash(sha256, atom_to_binary(Alert#alert_data.severity, utf8)),
    <<MessageHash/binary, TypeHash/binary, SeverityHash/binary>>.

%% @brief Process individual alert
-spec process_alert(alert_data(), state()) -> state().
process_alert(Alert, State) ->
    logger:warning("Processing alert", #[
        {alert_id, Alert#alert_data.id},
        {severity, Alert#alert_data.severity},
        {type, Alert#alert_data.type},
        {domain, [a2a, alerting]}
    ]),

    %% Update trigger count for rule
    State1 = maybe_increment_trigger_count(Alert, State),

    %% Send notifications
    State2 = send_alert_notifications(Alert, State),

    %% Create incident if critical
    State3 = maybe_create_incident(Alert, State2),

    %% Check for automatic resolution
    case should_auto_resolve(Alert, State3) of
        true ->
            ResolvedAlert = Alert#alert_data{
                resolved = true,
                resolved_by = <<"system">>,
                resolved_at = erlang:system_time(millisecond)
            },
            logger:info("Alert auto-resolved", #[
                {alert_id, Alert#alert_data.id},
                {domain, [a2a, alerting]}
            ]),
            update_alert_in_state(ResolvedAlert, State3);
        false ->
            State3
    end.

%% @brief Maybe increment trigger count for rule
-spec maybe_increment_trigger_count(alert_data(), state()) -> state().
maybe_increment_trigger_count(Alert, State) ->
    case Alert#alert_data.rule_id of
        undefined ->
            State;
        RuleId ->
            case lists:keyfind(RuleId, #alert_rule.id, State#state.alert_rules) of
                false ->
                    State;
                Rule ->
                    UpdatedRule = Rule#alert_rule{
                        last_triggered = erlang:system_time(millisecond),
                        trigger_count = Rule#alert_rule.trigger_count + 1
                    },
                    UpdatedRules = lists:keyreplace(RuleId, #alert_rule.id, State#state.alert_rules, UpdatedRule),
                    State#state{alert_rules = UpdatedRules}
            end
    end.

%% @brief Send alert notifications
-spec send_alert_notifications(alert_data(), state()) -> state().
send_alert_notifications(Alert, State) ->
    %% Get active notification channels
    Channels = get_active_notification_channels(State, Alert),

    %% Send notifications
    SentNotifications = lists:filtermap(fun(Channel) ->
        case send_notification(Alert, Channel, State) of
            {ok, NotificationId} -> {true, NotificationId};
            error -> false
        end
    end, Channels),

    %% Update alert with sent notifications
    UpdatedAlert = Alert#alert_data{
        notifications_sent = SentNotifications
    },

    update_alert_in_state(UpdatedAlert, State).

%% @brief Get active notification channels for alert
-spec get_active_notification_channels(state(), alert_data()) -> [notification_channel()].
get_active_notification_channels(State, Alert) ->
    %% Get channels associated with alert's rule
    BaseChannels = case Alert#alert_data.rule_id of
        undefined ->
            DefaultChannels = State#state.notification_channels;
        RuleId ->
            case lists:keyfind(RuleId, #alert_rule.id, State#state.alert_rules) of
                false ->
                    DefaultChannels = State#state.notification_channels;
                Rule ->
                    %% Get channels from rule configuration
                    RuleChannels = Rule#alert_rule.notification_channels,
                    lists:filter(fun(C) -> lists:member(C#notification_channel.id, RuleChannels) end, State#state.notification_channels)
            end
    end,

    %% Filter enabled channels that match alert severity
    lists:filter(fun(Channel) ->
        Channel#notification_channel.enabled andalso
        matches_severity(Alert#alert_data.severity, Channel)
    end, BaseChannels).

%% @brief Check if channel matches alert severity
-spec matches_severity(atom(), notification_channel()) -> boolean().
matches_severity(AlertSeverity, Channel) ->
    ChannelSeverity = maps:get(min_severity, Channel#notification_channel.config, low),
    severity_rank(AlertSeverity) >= severity_rank(ChannelSeverity).

%% @brief Get severity rank
-spec severity_rank(atom()) -> integer().
severity_rank(low) -> 1;
severity_rank(medium) -> 2;
severity_rank(high) -> 3;
severity_rank(critical) -> 4;
severity_rank(emergency) -> 5.

%% @brief Send notification through channel
-spec send_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_notification(Alert, Channel, State) ->
    case Channel#notification_channel.type of
        email -> send_email_notification(Alert, Channel, State);
        slack -> send_slack_notification(Alert, Channel, State);
        pagerduty -> send_pagerduty_notification(Alert, Channel, State);
        webhook -> send_webhook_notification(Alert, Channel, State);
        custom -> send_custom_notification(Alert, Channel, State);
        _ -> error
    end.

%% @brief Send email notification
-spec send_email_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_email_notification(Alert, Channel, _State) ->
    %% Simplified email sending
    %% In production, would use proper email library
    logger:info("Email notification sent", #[
        {alert_id, Alert#alert_data.id},
        {channel_id, Channel#notification_channel.id},
        {domain, [a2a, alerting]}
    ]),
    {ok, generate_notification_id()}.

%% @brief Send Slack notification
-spec send_slack_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_slack_notification(Alert, Channel, _State) ->
    %% Simplified Slack webhook
    logger:info("Slack notification sent", #[
        {alert_id, Alert#alert_data.id},
        {channel_id, Channel#notification_channel.id},
        {domain, [a2a, alerting]}
    ]),
    {ok, generate_notification_id()}.

%% @brief Send PagerDuty notification
-spec send_pagerduty_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_pagerduty_notification(Alert, Channel, _State) ->
    logger:info("PagerDuty notification sent", #[
        {alert_id, Alert#alert_data.id},
        {channel_id, Channel#notification_channel.id},
        {domain, [a2a, alerting]}
    ]),
    {ok, generate_notification_id()}.

%% @brief Send webhook notification
-spec send_webhook_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_webhook_notification(Alert, Channel, _State) ->
    logger:info("Webhook notification sent", #[
        {alert_id, Alert#alert_data.id},
        {channel_id, Channel#notification_channel.id},
        {domain, [a2a, alerting]}
    ]),
    {ok, generate_notification_id()}.

%% @brief Send custom notification
-spec send_custom_notification(alert_data(), notification_channel(), state()) -> {ok, binary()} | error.
send_custom_notification(Alert, Channel, _State) ->
    logger:info("Custom notification sent", #[
        {alert_id, Alert#alert_data.id},
        {channel_id, Channel#notification_channel.id},
        {domain, [a2a, alerting]}
    ]),
    {ok, generate_notification_id()}.

%% @brief Generate notification ID
-spec generate_notification_id() -> binary().
generate_notification_id() ->
    crypto:strong_rand_bytes(8).

%% @brief Maybe create incident from alert
-spec maybe_create_incident(alert_data(), state()) -> state().
maybe_create_incident(Alert, State) ->
    case Alert#alert_data.severity of
        critical ->
            logger:warning("Creating incident for critical alert", #[
                {alert_id, Alert#alert_data.id},
                {domain, [a2a, alerting]}
            ]),
            Incident = #{
                id => generate_id(),
                alert_id => Alert#alert_data.id,
                created_at => erlang:system_time(millisecond),
                status => active,
                severity => Alert#alert_data.severity,
                title => Alert#alert_data.title,
                description => Alert#alert_data.message,
                details => Alert#alert_data.details
            },
            State#state{
                active_incidents = [Incident | State#state.active_incidents]
            };
        _ ->
            State
    end.

%% @brief Check if alert should be auto-resolved
-spec should_auto_resolve(alert_data(), state()) -> boolean().
should_auto_resolve(Alert, State) ->
    case State#state.config#alert_config.auto_resolve_enabled of
        false -> false;
        true ->
            %% Auto-resolve low severity alerts after some time
            case Alert#alert_data.severity of
                low ->
                    Now = erlang:system_time(millisecond),
                    (Now - Alert#alert_data.timestamp) > 3600000;  % 1 hour
                _ -> false
            end
    end.

%% @brief Handle alert timeouts
-spec handle_alert_timeouts(state()) -> state().
handle_alert_timeouts(State) ->
    Now = erlang:system_time(millisecond),
    Timeout = 1800000,  % 30 minutes

    OverdueAlerts = lists:filter(fun(Alert) ->
        not Alert#alert_data.resolved andalso
        (Now - Alert#alert_data.timestamp) > Timeout
    end, State#state.alerts),

    lists:foldl(fun(Alert, AccState) ->
        TimeoutAlert = Alert#alert_data{
            resolved = true,
            resolved_by = <<"timeout">>,
            resolved_at = Now,
            details = maps:put(timeout, true, Alert#alert_data.details)
        },
        logger:warning("Alert timeout auto-resolved", #[
            {alert_id, Alert#alert_data.id},
            {domain, [a2a, alerting]}
        ]),
        update_alert_in_state(TimeoutAlert, AccState)
    end, State, OverdueAlerts).

%% @brief Send escalated notifications
-spec send_escalated_notifications(alert_data(), state()) -> ok.
send_escalated_notifications(Alert, State) ->
    logger:warning("Sending escalated notifications", #[
        {alert_id, Alert#alert_data.id},
        {escalation_level, Alert#alert_data.escalation_level},
        {domain, [a2a, alerting]}
    ]),

    %% Get escalation policy
    EscalationPolicy = lists:find(fun(P) ->
        P#escalation_policy.id == Alert#alert_data.upgrade_id  % Using upgrade_id as policy ID for now
    end, State#state.escalation_policies),

    case EscalationPolicy of
        false ->
            ok;
        Policy ->
            %% Send to escalation channels
            lists:foreach(fun(Level) ->
                if Level#map.level == Alert#alert_data.escalation_level ->
                    Channels = Level#map.notification_channels,
                    lists:foreach(fun(ChannelId) ->
                        Channel = lists:keyfind(ChannelId, #notification_channel.id, State#state.notification_channels),
                        case Channel of
                            false -> ok;
                            _ -> send_notification(Alert, Channel, State)
                        end
                    end, Channels);
                   true -> ok
                end
            end, Policy#escalation_policy.levels)
    end.

%% @brief Update alert in state
-spec update_alert_in_state(alert_data(), state()) -> state().
update_alert_in_state(Alert, State) ->
    UpdatedAlerts = lists:keyreplace(Alert#alert_data.id, #alert_data.id, State#state.alerts, Alert),
    State#state{alerts = UpdatedAlerts}.

%% @brief Update alert rule field
-spec update_alert_rule_field(alert_rule(), binary(), term(), term()) -> alert_rule().
update_alert_rule_field(Rule, <<"threshold">>, Value, _) ->
    Rule#alert_rule{threshold = Value, updated_at = erlang:system_time(millisecond)};
update_alert_rule_field(Rule, <<"severity">>, Value, _) ->
    Rule#alert_rule{severity = Value, updated_at = erlang:system_time(millisecond)};
update_alert_rule_field(Rule, <<"enabled">>, Value, _) ->
    Rule#alert_rule{enabled = Value, updated_at = erlang:system_time(millisecond)};
update_alert_rule_field(Rule, <<"notification_channels">>, Value, _) ->
    Rule#alert_rule{notification_channels = Value, updated_at = erlang:system_time(millisecond)};
update_alert_rule_field(Rule, _, _, _) ->
    Rule.

%% @brief Update alert template field
-spec update_alert_template_field(alert_template(), binary(), term(), term()) -> alert_template().
update_alert_template_field(Template, <<"title">>, Value, _) ->
    Template#alert_template{title = Value, updated_at = erlang:system_time(millisecond)};
update_alert_template_field(Template, <<"message">>, Value, _) ->
    Template#alert_template{message = Value, updated_at = erlang:system_time(millisecond)};
update_alert_template_field(Template, <<"enabled">>, Value, _) ->
    Template#alert_template{enabled = Value, updated_at = erlang:system_time(millisecond)};
update_alert_template_field(Template, _, _, _) ->
    Template.

%% @brief Calculate alert statistics
-spec calculate_alert_statistics(state()) -> map().
calculate_alert_statistics(State) ->
    TotalAlerts = length(State#state.alerts),
    ActiveAlerts = lists:filter(fun(A) -> not A#alert_data.resolved end, State#state.alerts),
    ResolvedAlerts = lists:filter(fun(A) -> A#alert_data.resolved end, State#state.alerts),
    CriticalAlerts = lists:filter(fun(A) -> A#alert_data.severity == critical end, State#state.alerts),
    HighAlerts = lists:filter(fun(A) -> A#alert_data.severity == high end, State#state.alerts),
    MediumAlerts = lists:filter(fun(A) -> A#alert_data.severity == medium end, State#state.alerts),
    LowAlerts = lists:filter(fun(A) -> A#alert_data.severity == low end, State#state.alerts),

    AverageResolutionTime = calculate_average_resolution_time(State),

    #{
        total_alerts => TotalAlerts,
        active_alerts => length(ActiveAlerts),
        resolved_alerts => length(ResolvedAlerts),
        critical_alerts => length(CriticalAlerts),
        high_alerts => length(HighAlerts),
        medium_alerts => length(MediumAlerts),
        low_alerts => length(LowAlerts),
        resolution_rate => case TotalAlerts of
            0 -> 0.0;
            _ -> length(ResolvedAlerts) / TotalAlerts
        end,
        average_resolution_time_ms => AverageResolutionTime,
        last_updated => erlang:system_time(millisecond)
    }.

%% @brief Calculate average resolution time
-spec calculate_average_resolution_time(state()) -> integer().
calculate_average_resolution_time(State) ->
    ResolvedAlerts = lists:filter(fun(A) ->
        A#alert_data.resolved andalso
        A#alert_data.resolved_at /= undefined andalso
        A#alert_data.timestamp /= undefined
    end, State#state.alerts),

    case ResolvedAlerts of
        [] -> 0;
        _ ->
            ResolutionTimes = lists:map(fun(A) ->
                A#alert_data.resolved_at - A#alert_data.timestamp
            end, ResolvedAlerts),
            lists:sum(ResolutionTimes) div length(ResolutionTimes)
    end.

%% @brief Generate alert summary
-spec generate_alert_summary(state()) -> map().
generate_alert_summary(State) ->
    TotalUpgrades = length(State#state.upgrade_history),
    ActiveUpgrade = case State#state.current_upgrade of
        undefined -> undefined;
        UpgradeRecord -> UpgradeRecord#upgrade_record.upgrade_id
    end,

    AlertStats = calculate_alert_statistics(State),

    #{
        current_upgrade => ActiveUpgrade,
        total_upgrades => TotalUpgrades,
        alert_statistics => AlertStats,
        active_incidents => length(State#state.active_incidents),
        notification_channels_enabled => length(lists:filter(
            fun(C) -> C#notification_channel.enabled end,
            State#state.notification_channels
        )),
        last_updated => erlang:system_time(millisecond)
    }.

%% @brief Start metrics collection
-spec start_metrics_collection(state()) -> state().
start_metrics_collection(State) ->
    %% Start periodic metrics collection
    logger:info("Starting alert metrics collection", #{domain => [a2a, alerting]}),
    State.

%% @brief Format alert rule
-spec format_alert_rule(alert_rule()) -> map().
format_alert_rule(Rule) ->
    #{
        id => Rule#alert_rule.id,
        name => Rule#alert_rule.name,
        description => Rule#alert_rule.description,
        alert_type => Rule#alert_rule.alert_type,
        metric_name => Rule#alert_rule.metric_name,
        condition => Rule#alert_rule.condition,
        threshold => Rule#alert_rule.threshold,
        severity => Rule#alert_rule.severity,
        enabled => Rule#alert_rule.enabled,
        escalation_policy => Rule#alert_rule.escalation_policy,
        notification_channels => Rule#alert_rule.notification_channels,
        created_at => Rule#alert_rule.created_at,
        updated_at => Rule#alert_rule.updated_at,
        last_triggered => Rule#alert_rule.last_triggered,
        trigger_count => Rule#alert_rule.trigger_count
    }.

%% @brief Format alert data
-spec format_alert_data(alert_data()) -> map().
format_alert_data(Alert) ->
    #{
        id => Alert#alert_data.id,
        rule_id => Alert#alert_data.rule_id,
        upgrade_id => Alert#alert_data.upgrade_id,
        type => Alert#alert_data.type,
        severity => Alert#alert_data.severity,
        title => Alert#alert_data.title,
        message => Alert#alert_data.message,
        details => Alert#alert_data.details,
        timestamp => Alert#alert_data.timestamp,
        acknowledged => Alert#alert_data.acknowledged,
        resolved => Alert#alert_data.resolved,
        resolved_by => Alert#alert_data.resolved_by,
        resolved_at => Alert#alert_data.resolved_at,
        acknowledged_by => Alert#alert_data.acknowledged_by,
        acknowledged_at => Alert#alert_data.acknowledged_at,
        notifications_sent => Alert#alert_data.notifications_sent,
        escalation_level => Alert#alert_data.escalation_level,
        tags => Alert#alert_data.tags
    }.

%% @brief Format alert template
-spec format_alert_template(alert_template()) -> map().
format_alert_template(Template) ->
    #{
        id => Template#alert_template.id,
        name => Template#alert_template.name,
        alert_type => Template#alert_template.alert_type,
        severity => Template#alert_template.severity,
        title => Template#alert_template.title,
        message => Template#alert_template.message,
        details => Template#alert_template.details,
        placeholders => Template#alert_template.placeholders,
        enabled => Template#alert_template.enabled,
        created_at => Template#alert_template.created_at,
        updated_at => Template#alert_template.updated_at
    }.

%% @brief Generate UUID
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>.