-module(helm_upgrade_SUITE).
-author('a2a-project').

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%% Test Server Callbacks
-export([suite/0, init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).

%% Test Cases
-export([helm_chart_exists/1, helm_chart_has_rolling_update/1,
          helm_chart_has_revision_limit/1, helm_values_has_rolling_config/1,
          helm_has_upgrade_hooks/1, helm_has_test_pod/1,
          helm_configmap_has_checksum/1, helm_deployment_has_probes/1,
          helm_values_has_test_config/1, helm_deployment_has_resource_limits/1,
          helm_health_check_configurable/1, helm_helper_templates_exist/1,
          all/0]).

all() ->
    [helm_chart_exists,
     helm_chart_has_rolling_update,
     helm_chart_has_revision_limit,
     helm_values_has_rolling_config,
     helm_has_upgrade_hooks,
     helm_has_test_pod,
     helm_configmap_has_checksum,
     helm_deployment_has_probes,
     helm_values_has_test_config,
     helm_deployment_has_resource_limits,
     helm_health_check_configurable,
     helm_helper_templates_exist].

suite() ->
    [{timetrap, {seconds, 300}}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

%%--------------------------------------------------------------------
%% helm_chart_exists: Verify Helm chart exists and is valid
%%--------------------------------------------------------------------
helm_chart_exists(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    ?assertNotEqual({error, enoent}, file:read_file_info(ChartDir)),

    ChartYaml = filename:join(ChartDir, "Chart.yaml"),
    ?assertNotEqual({error, enoent}, file:read_file_info(ChartYaml)),

    ValuesYaml = filename:join(ChartDir, "values.yaml"),
    ?assertNotEqual({error, enoent}, file:read_file_info(ValuesYaml)),

    TemplatesDir = filename:join(ChartDir, "templates"),
    ?assertNotEqual({error, enoent}, file:read_file_info(TemplatesDir)),

    %% Check for required templates
    Deployment = filename:join(TemplatesDir, "deployment.yaml"),
    ?assertNotEqual({error, enoent}, file:read_file_info(Deployment)),

    Service = filename:join(TemplatesDir, "service.yaml"),
    ?assertNotEqual({error, enoent}, file:read_file_info(Service)),

    ok.

%%--------------------------------------------------------------------
%% helm_chart_has_rolling_update: Verify deployment has rolling update config
%%--------------------------------------------------------------------
helm_chart_has_rolling_update(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    DeploymentTemplate = filename:join([ChartDir, "templates", "deployment.yaml"]),

    {ok, Content} = file:read_file(DeploymentTemplate),
    ContentStr = binary_to_list(Content),

    %% Verify rollingUpdate strategy is present
    ?assert(string:str(ContentStr, "strategy:") > 0),
    ?assert(string:str(ContentStr, "type: RollingUpdate") > 0),
    ?assert(string:str(ContentStr, "rollingUpdate:") > 0),
    ?assert(string:str(ContentStr, "maxSurge:") > 0),
    ?assert(string:str(ContentStr, "maxUnavailable:") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_chart_has_revision_limit: Verify deployment has revision history limit
%%--------------------------------------------------------------------
helm_chart_has_revision_limit(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    DeploymentTemplate = filename:join([ChartDir, "templates", "deployment.yaml"]),

    {ok, Content} = file:read_file(DeploymentTemplate),
    ContentStr = binary_to_list(Content),

    %% Verify revisionHistoryLimit is present
    ?assert(string:str(ContentStr, "revisionHistoryLimit:") > 0),

    %% Verify default value is 10
    ?assert(string:str(ContentStr, "default 10") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_values_has_rolling_config: Verify values.yaml has rolling update config
%%--------------------------------------------------------------------
helm_values_has_rolling_config(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    ValuesFile = filename:join(ChartDir, "values.yaml"),

    {ok, Content} = file:read_file(ValuesFile),
    ContentStr = binary_to_list(Content),

    %% Verify rollingUpdate configuration
    ?assert(string:str(ContentStr, "rollingUpdate:") > 0),
    ?assert(string:str(ContentStr, "maxSurge:") > 0),
    ?assert(string:str(ContentStr, "maxUnavailable:") > 0),

    %% Verify revisionHistoryLimit
    ?assert(string:str(ContentStr, "revisionHistoryLimit:") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_has_upgrade_hooks: Verify chart has upgrade hooks
%%--------------------------------------------------------------------
helm_has_upgrade_hooks(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    TemplatesDir = filename:join(ChartDir, "templates"),
    TestsDir = filename:join(TemplatesDir, "tests"),

    %% Check if tests directory exists
    case file:read_file_info(TestsDir) of
        {ok, _} ->
            %% Check for pre-upgrade hook
            PreUpgrade = filename:join(TestsDir, "pre-upgrade-check.yaml"),
            case file:read_file_info(PreUpgrade) of
                {ok, _} ->
                    {ok, Content} = file:read_file(PreUpgrade),
                    ContentStr = binary_to_list(Content),
                    ?assert(string:str(ContentStr, "pre-upgrade") > 0);
                {error, _} ->
                    ct:fail(pre_upgrade_hook_missing)
            end,

            %% Check for post-upgrade hook
            PostUpgrade = filename:join(TestsDir, "post-upgrade-test.yaml"),
            case file:read_file_info(PostUpgrade) of
                {ok, _} ->
                    {ok, Content2} = file:read_file(PostUpgrade),
                    ContentStr2 = binary_to_list(Content2),
                    ?assert(string:str(ContentStr2, "post-upgrade") > 0);
                {error, _} ->
                    ct:fail(post_upgrade_hook_missing)
            end;
        {error, _} ->
            ct:fail(tests_directory_missing)
    end,

    ok.

%%--------------------------------------------------------------------
%% helm_has_test_pod: Verify chart has test connection pod
%%--------------------------------------------------------------------
helm_has_test_pod(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    TemplatesDir = filename:join(ChartDir, "templates"),
    TestsDir = filename:join(TemplatesDir, "tests"),
    TestConnection = filename:join(TestsDir, "test-connection.yaml"),

    case file:read_file_info(TestConnection) of
        {ok, _} ->
            {ok, Content} = file:read_file(TestConnection),
            ContentStr = binary_to_list(Content),
            ?assert(string:str(ContentStr, "helm.sh/hook: test") > 0);
        {error, _} ->
            ct:fail(test_connection_pod_missing)
    end,

    ok.

%%--------------------------------------------------------------------
%% helm_configmap_has_checksum: Verify configmap checksum annotation
%%--------------------------------------------------------------------
helm_configmap_has_checksum(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    DeploymentTemplate = filename:join([ChartDir, "templates", "deployment.yaml"]),

    {ok, Content} = file:read_file(DeploymentTemplate),
    ContentStr = binary_to_list(Content),

    %% Verify checksum/config annotation for rolling updates on config changes
    ?assert(string:str(ContentStr, "checksum/config:") > 0),
    ?assert(string:str(ContentStr, "sha256sum") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_deployment_has_probes: Verify deployment has liveness and readiness probes
%%--------------------------------------------------------------------
helm_deployment_has_probes(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    DeploymentTemplate = filename:join([ChartDir, "templates", "deployment.yaml"]),

    {ok, Content} = file:read_file(DeploymentTemplate),
    ContentStr = binary_to_list(Content),

    %% Verify liveness probe
    ?assert(string:str(ContentStr, "livenessProbe:") > 0),

    %% Verify readiness probe
    ?assert(string:str(ContentStr, "readinessProbe:") > 0),

    %% Verify health check path is configurable
    ?assert(string:str(ContentStr, "healthCheck.path") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_values_has_test_config: Verify values.yaml has test config
%%--------------------------------------------------------------------
helm_values_has_test_config(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    ValuesFile = filename:join(ChartDir, "values.yaml"),

    {ok, Content} = file:read_file(ValuesFile),
    ContentStr = binary_to_list(Content),

    %% Verify tests configuration
    ?assert(string:str(ContentStr, "tests:") > 0),
    ?assert(string:str(ContentStr, "enabled:") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_deployment_has_resource_limits: Verify deployment has resource limits
%%--------------------------------------------------------------------
helm_deployment_has_resource_limits(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    DeploymentTemplate = filename:join([ChartDir, "templates", "deployment.yaml"]),

    {ok, Content} = file:read_file(DeploymentTemplate),
    ContentStr = binary_to_list(Content),

    %% Verify resources configuration
    ?assert(string:str(ContentStr, "resources:") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_health_check_configurable: Verify health check is configurable
%%--------------------------------------------------------------------
helm_health_check_configurable(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    ValuesFile = filename:join(ChartDir, "values.yaml"),

    {ok, Content} = file:read_file(ValuesFile),
    ContentStr = binary_to_list(Content),

    %% Verify healthCheck configuration
    ?assert(string:str(ContentStr, "healthCheck:") > 0),
    ?assert(string:str(ContentStr, "enabled:") > 0),
    ?assert(string:str(ContentStr, "path:") > 0),
    ?assert(string:str(ContentStr, "initialDelaySeconds:") > 0),
    ?assert(string:str(ContentStr, "periodSeconds:") > 0),
    ?assert(string:str(ContentStr, "timeoutSeconds:") > 0),
    ?assert(string:str(ContentStr, "failureThreshold:") > 0),

    ok.

%%--------------------------------------------------------------------
%% helm_helper_templates_exist: Verify helper templates exist
%%--------------------------------------------------------------------
helm_helper_templates_exist(_Config) ->
    ChartDir = filename:absname("../../../helm/a2a-erl"),
    HelpersFile = filename:join([ChartDir, "templates", "_helpers.tpl"]),

    {ok, Content} = file:read_file(HelpersFile),
    ContentStr = binary_to_list(Content),

    %% Verify common helper templates
    ?assert(string:str(ContentStr, "a2a-erl.name") > 0),
    ?assert(string:str(ContentStr, "a2a-erl.fullname") > 0),
    ?assert(string:str(ContentStr, "a2a-erl.labels") > 0),
    ?assert(string:str(ContentStr, "a2a-erl.selectorLabels") > 0),

    ok.
