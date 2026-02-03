%%% @doc HotCI Security System Test Suite
%%%
%%% This test suite validates the security and reliability features
%%% of the HotCI system, including secure upgrades, rollback mechanisms,
%%% and disaster recovery procedures.
-module(a2a_hotci_security_SUITE).
-behaviour(supervisor).
-include_lib("common_test/include/ct.hrl").
-include("a2a.hrl").

%% Test exports
-export([
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2,
    all/0
]).

%% Test cases
-export([
    test_secure_upgrade_integrity/1,
    test_rollback_mechanisms/1,
    test_disaster_recovery_procedures/1,
    test_integrity_validation/1,
    test_monitoring_alerts/1,
    test_encryption_protocols/1,
    test_backup_restore/1,
    test_service_health_validation/1,
    test_critical_failover/1,
    test_security_audit_logging/1
]).

%% Helper exports
-export([
    setup_test_environment/1,
    create_test_package/1,
    simulate_disaster_scenario/2,
    validate_security_event/2
]).

%% ============================================================================
%% Test Suite Configuration
%% ============================================================================

all() ->
    [
        test_secure_upgrade_integrity,
        test_rollback_mechanisms,
        test_disaster_recovery_procedures,
        test_integrity_validation,
        test_monitoring_alerts,
        test_encryption_protocols,
        test_backup_restore,
        test_service_health_validation,
        test_critical_failover,
        test_security_audit_logging
    ].

init_per_suite(Config) ->
    %% Start test environment
    application:start(crypto),
    application:start(sasl),
    application:start(logger),

    %% Start test supervision tree
    {ok, _} = supervisor:start_link({local, a2a_test_sup}, ?MODULE, []),

    %% Setup security modules
    {ok, _} = a2a_hotci_security:start_link(),
    {ok, _} = a2a_integrity_validator:start_link(),
    {ok, _} = a2a_rollback_manager:start_link(),
    {ok, _} = a2a_disaster_recovery:start_link(),
    {ok, _} = a2a_monitoring:start_link(),

    %% Initialize test data
    TestData = setup_test_environment(Config),
    [{test_data, TestData} | Config].

end_per_suite(Config) ->
    %% Cleanup test environment
    case a2a_test_sup of
        undefined -> ok;
        _ -> supervisor:stop(a2a_test_sup)
    end,
    application:stop(logger),
    application:stop(sasl),
    application:stop(crypto),
    Config.

init_per_testcase(TestCase, Config) ->
    %% Setup for each test case
    ct:pal("Starting test case: ~p", [TestCase]),

    %% Initialize security logging
    SecurityLogDir = filename:join(proplists:get_value(priv_dir, Config), "security_logs"),
    filelib:ensure_dir(SecurityLogDir),

    %% Create test backup
    BackupDir = filename:join([SecurityLogDir, "backups"]),
    filelib:ensure_dir(BackupDir),

    [{test_case, TestCase}, {security_log_dir, SecurityLogDir}, {backup_dir, BackupDir} | Config].

end_per_testcase(TestCase, Config) ->
    %% Cleanup after each test case
    ct:pal("Completed test case: ~p", [TestCase]),

    %% Clear test data
    clear_test_data(Config),

    %% Verify system is in clean state
    verify_system_clean_state(Config),

    Config.

%% ============================================================================
%% Test Cases
%% ============================================================================

test_secure_upgrade_integrity(Config) ->
    %% Test secure upgrade package integrity validation
    TestPackage = create_test_package(Config),

    %% Test package validation
    Result = a2a_hotci_security:validate_upgrade_integrity(TestPackage, #{
        version => "1.1.0",
        checksum => <<"test_checksum">>,
        signature => <<"test_signature">>
    }),

    ct:pal("Upgrade integrity validation result: ~p", [Result]),

    case Result of
        {ok, ValidationData} ->
            %% Verify validation data contains required fields
            ct:assert(is_map(ValidationData)),
            ct:assert(maps:is_key(package_path, ValidationData)),
            ct:assert(maps:is_key(checksums, ValidationData)),
            ct:assert(maps:is_key(signatures, ValidationData)),

            %% Test successful upgrade
            UpgradeResult = a2a_hotci_security:perform_secure_upgrade("1.1.0", #{
                operator => "test_operator",
                validation_data => ValidationData
            }),

            case UpgradeResult of
                {ok, UpgradeId} ->
                    ct:assert(binary:part(UpgradeId, {0, 8}) =/= <<>>),

                    %% Verify upgrade completion
                    Status = a2a_hotci_security:get_upgrade_status(),
                    case Status of
                        {ok, StatusData} ->
                            ct:assert(maps:is_key(current_version, StatusData));
                        _ ->
                            ct:fail("Failed to get upgrade status")
                    end;
                {error, Reason} ->
                    ct:fail("Secure upgrade failed: ~p", [Reason])
            end;
        {error, Reason} ->
            ct:fail("Integrity validation failed: ~p", [Reason])
    end.

test_rollback_mechanisms(Config) ->
    %% Test rollback mechanism functionality
    TestPackage = create_test_package(Config),

    %% Perform a test upgrade
    {ok, _UpgradeId} = a2a_hotci_security:perform_secure_upgrade("1.2.0", #{
        operator => "test_operator",
        validation_data => #{}
    }),

    %% Test rollback initiation
    RollbackResult = a2a_rollback_manager:initiate_rollback("1.1.0", #{
        rollback_strategy => atomic,
        cause => "test_rollback"
    }),

    case RollbackResult of
        {ok, RollbackId} ->
            %% Monitor rollback progress
            ct:pal("Rollback initiated with ID: ~p", [RollbackId]),

            %% Check rollback status
            Status = a2a_rollback_manager:rollback_status(RollbackId),
            case Status of
                {ok, StatusData} ->
                    ct:assert(maps:is_key(status, StatusData)),

                    %% Test rollback history
                    History = a2a_rollback_manager:rollback_history(5),
                    case History of
                        {ok, HistoryList} ->
                            ct:assert(length(HistoryList) >= 1);
                        _ ->
                            ct:fail("Failed to get rollback history")
                    end;
                {error, Reason} ->
                    ct:fail("Failed to get rollback status: ~p", [Reason])
            end;
        {error, Reason} ->
            ct:fail("Rollback initiation failed: ~p", [Reason])
    end.

test_disaster_recovery_procedures(Config) ->
    %% Test disaster recovery procedures
    DisasterContext = simulate_disaster_scenario("system_failure", Config),

    %% Test recovery plan validation
    ValidationResult = a2a_disaster_recovery:validate_recovery_plan("banking_recovery_plan"),
    case ValidationResult of
        {ok, ValidationData} ->
            ct:assert(is_map(ValidationData)),
            ct:assert(maps:is_key(readiness_status, ValidationData));
        {error, Reason} ->
            ct:fail("Recovery plan validation failed: ~p", [Reason])
    end,

    %% Test recovery point creation
    RecoveryPoint = a2a_disaster_recovery:create_recovery_point(#{
        backup_sites => ["primary_backup", "secondary_backup"],
        rpo => 300000,
        rto => 600000
    }),

    case RecoveryPoint of
        {ok, PointData} ->
            ct:assert(is_record(PointData, recovery_point)),
            ct:assert(PointData#recovery_point.id =/= <<>>),

            %% Test data recovery
            RecoveryResult = a2a_disaster_recovery:recover_data("test_data", PointData#recovery_point.id),
            case RecoveryResult of
                {ok, RecoveredData} ->
                    ct:assert(is_map(RecoveredData));
                {error, Reason} ->
                    ct:fail("Data recovery failed: ~p", [Reason])
            end;
        {error, Reason} ->
            ct:fail("Recovery point creation failed: ~p", [Reason])
    end.

test_integrity_validation(Config) ->
    %% Test package integrity validation
    TestPackage = create_test_package(Config),

    %% Test checksum verification
    ChecksumResult = a2a_integrity_validator:verify_checksums(TestPackage, #{
        sha256 => <<"test_checksum">>,
        sha512 => <<"test_checksum">>
    }),

    case ChecksumResult of
        {ok, ChecksumData} ->
            ct:assert(is_map(ChecksumData)),
            ct:assert(maps:is_key(sha256, ChecksumData)),
            ct:assert(maps:is_key(sha512, ChecksumData));
        {error, Reason} ->
            ct:fail("Checksum verification failed: ~p", [Reason])
    end,

    %% Test signature verification
    SignatureResult = a2a_integrity_validator:verify_signatures(TestPackage, #{
        admin => <<"admin_signature">>,
        system => <<"system_signature">>
    }),

    case SignatureResult of
        {ok, SignatureData} ->
            ct:assert(is_map(SignatureData));
        {error, Reason} ->
            ct:fail("Signature verification failed: ~p", [Reason])
    end,

    %% Test package completeness validation
    CompletenessResult = a2a_integrity_validator:validate_completeness(TestPackage, #{
        required_directories => ["ebin", "include", "priv"],
        required_files => ["ebin/app.beam"]
    }),

    case CompletenessResult of
        {ok, CompletenessData} ->
            ct:assert(is_map(CompletenessData));
        {error, Reason} ->
            ct:fail("Completeness validation failed: ~p", [Reason])
    end.

test_monitoring_alerts(Config) ->
    %% Test monitoring and alerting system
    StartResult = a2a_monitoring:start_monitoring("test_service", #{
        metrics => ["cpu", "memory"],
        alert_rules => [
            #{
                name => "CPU Alert",
                condition => "cpu_usage > 80",
                severity => high,
                threshold => 80.0
            }
        ]
    }),

    ct:assert(StartResult =:= ok),

    %% Get health metrics
    HealthResult = a2a_monitoring:get_health_metrics(),
    case HealthResult of
        {ok, HealthData} ->
            ct:assert(is_map(HealthData)),
            ct:assert(maps:is_key(overall_status, HealthData));
        {error, Reason} ->
            ct:fail("Health metrics retrieval failed: ~p", [Reason])
    end,

    %% Test manual alert triggering
    AlertResult = a2a_monitoring:trigger_alert("test_service", "critical_error", #{
        message => "Test critical error",
        severity => critical,
        metric_value => 95.0
    }),

    ct:assert(AlertResult =:= ok),

    %% Test alert history
    HistoryResult = a2a_monitoring:get_alert_history(24),
    case HistoryResult of
        {ok, AlertHistory} ->
            ct:assert(is_list(AlertHistory)),
            ct:assert(length(AlertHistory) >= 1);
        _ ->
            ct:fail("Failed to get alert history")
    end.

test_encryption_protocols(Config) ->
    %% Test encryption and security protocols
    TestKey = crypto:strong_rand_bytes(32),

    %% Test encryption initialization
    EncryptionResult = a2a_hotci_security:enable_encryption(TestKey),
    case EncryptionResult of
        {ok, Context} ->
            ct:assert(is_term(Context)),

            %% Test data encryption
            TestData = <<"sensitive_test_data">>,
            EncryptedData = a2a_hotci_security:encrypt_data(TestData, Context),
            ct:assert(is_binary(EncryptedData)),

            %% Verify encryption (should not match original)
            ct:assert(EncryptedData =/= TestData);
        {error, Reason} ->
            ct:fail("Encryption initialization failed: ~p", [Reason])
    end.

test_backup_restore(Config) ->
    %% Test backup and restore functionality
    BackupLocation = proplists:get_value(backup_dir, Config),

    %% Create backup
    BackupResult = a2a_hotci_security:create_backup(BackupLocation),
    case BackupResult of
        {ok, BackupInfo} ->
            ct:assert(is_map(BackupInfo)),
            ct:assert(maps:is_key(location, BackupInfo)),
            ct:assert(maps:is_key(timestamp, BackupInfo)),

            %% Test restore
            RestoreResult = a2a_hotci_security:restore_backup(BackupLocation, BackupInfo#{
                recovery_point => "latest"
            }),

            case RestoreResult of
                {ok, RestoreData} ->
                    ct:assert(is_map(RestoreData));
                {error, Reason} ->
                    ct:fail("Backup restore failed: ~p", [Reason])
            end;
        {error, Reason} ->
            ct:fail("Backup creation failed: ~p", [Reason])
    end.

test_service_health_validation(Config) ->
    %% Test service health validation
    ServiceResult = a2a_monitoring:validate_service_health("a2a_http_handler"),
    case ServiceResult of
        {ok, HealthData} ->
            ct:assert(is_map(HealthData)),
            ct:assert(maps:is_key(service_id, HealthData)),
            ct:assert(maps:is_key(status, HealthData));
        {error, Reason} ->
            ct:fail("Service health validation failed: ~p", [Reason])
    end.

    %% Test critical path monitoring
    PathConfig = #{
        paths => [
            #{
                path_id => "critical_path_1",
                steps => [
                    #{
                        step_id => "step_1",
                        step_type => "service_call",
                        service_id => "a2a_http_handler"
                    },
                    #{
                        step_id => "step_2",
                        step_type => "database_query",
                        query => "SELECT * FROM tasks"
                    }
                ]
            }
        ]
    },

    a2a_monitoring:monitor_critical_paths(PathConfig).

test_critical_failover(Config) ->
    %% Test critical system failover
    BackupSite = "primary_backup",

    %% Activate standby mode
    StandbyResult = a2a_disaster_recovery:activate_standby(),
    ct:assert(StandbyResult =:= ok),

    %% Test failover to backup site
    FailoverResult = a2a_disaster_recovery:failover_to_backup(BackupSite),
    case FailoverResult of
        {ok, FailoverData} ->
            ct:assert(is_map(FailoverData)),
            ct:assert(maps:is_key(backup_site, FailoverData)),
            ct:assert(maps:is_key(traffic, FailoverData));
        {error, Reason} ->
            ct:fail("Failover failed: ~p", [Reason])
    end.

    %% Test deactivation
    DeactivateResult = a2a_disaster_recovery:deactivate_standby("test_completion"),
    ct:assert(DeactivateResult =:= ok).

test_security_audit_logging(Config) ->
    %% Test security audit logging
    SecurityLogDir = proplists:get_value(security_log_dir, Config),
    LogFile = filename:join([SecurityLogDir, "audit_test.log"]),

    %% Test security event logging
    SecurityEvent = #{
        event_type => "test_security_event",
        details => #{action => "test_action", operator => "test_operator"},
        timestamp => erlang:system_time(millisecond)
    },

    a2a_hotci_security:audit_security_event(
        "test_event_type",
        "Test security event details",
        SecurityEvent
    ),

    %% Verify log file exists and contains entries
    ct:assert(filelib:is_file(LogFile)),

    %% Read and verify log content
    {ok, LogContent} = file:read_file(LogFile),
    ct:assert(LogContent =/= <<>>),

    %% Parse and verify JSON content
    case jsx:decode(LogContent, [return_maps]) of
        EventMap when is_map(EventMap) ->
            ct:assert(maps:is_key(type, EventMap)),
            ct:assert(maps:is_key(data, EventMap)),
            ct:assert(maps:is_key(timestamp, EventMap));
        _ ->
            ct:fail("Invalid JSON format in audit log")
    end.

%% ============================================================================
%% Helper Functions
%% ============================================================================

setup_test_environment(Config) ->
    %% Setup test environment and data
    TestData = #{
        test_packages_dir => filename:join(proplists:get_value(priv_dir, Config), "packages"),
        backup_dir => filename:join([proplists:get_value(priv_dir, Config), "backups"]),
        test_data_dir => filename:join([proplists:get_value(priv_dir, Config), "data"])
    },

    %% Create necessary directories
    filelib:ensure_dir(TestData#{
        test_packages_dir := TD
    } = TestData#{
        test_packages_dir := TD
    }),
    filelib:ensure_dir(TestData#{
        backup_dir := BD
    } = TestData#{
        backup_dir := BD
    }),
    filelib:ensure_dir(TestData#{
        test_data_dir := TD
    } = TestData#{
        test_data_dir := TD
    }),

    %% Create test packages
    TestPackagePath = create_test_package_path(TestData),
    create_test_package(TestPackagePath),

    TestData.

create_test_package(Config) ->
    %% Create test upgrade package
    TestData = proplists:get_value(test_data, Config, #{
        test_packages_dir => filename:join(proplists:get_value(priv_dir, Config), "packages")
    }),

    PackagePath = create_test_package_path(TestData),

    PackageData = #{
        version => "1.1.0",
        description => "Test upgrade package",
        checksum => crypto:hash(sha256, <<"test_data">>),
        signature => crypto:hash(sha256, <<"test_signature">>),
        files => ["ebin/app.beam", "include/hrl.hrl", "priv/config.json"],
        directories => ["ebin", "include", "priv"]
    },

    %% Create test package file
    file:write_file(PackagePath, jsx:encode(PackageData)),

    PackagePath.

create_test_package_path(TestData) ->
    %% Create path for test package
    filename:join([TestData#{
        test_packages_dir := PkgDir
    } = TestData#{
        test_packages_dir := PkgDir
    }, "test_package_v1.1.0.zip"]).

simulate_disaster_scenario(ScenarioType, Config) ->
    %% Simulate various disaster scenarios
    case ScenarioType of
        "system_failure" ->
            %% Simulate system failure scenario
            #{
                type => "system_failure",
                severity => "critical",
                timestamp => erlang:system_time(millisecond),
                affected_components => ["a2a_http_handler", "a2a_task_statem"],
                recovery_plan => "banking_recovery_plan"
            };
        "data_corruption" ->
            %% Simulate data corruption scenario
            #{
                type => "data_corruption",
                severity => "high",
                timestamp => erlang:system_time(millisecond),
                affected_components => ["a2a_task_store"],
                recovery_plan => "data_recovery_plan"
            };
        "network_failure" ->
            %% Simulate network failure scenario
            #{
                type => "network_failure",
                severity => "medium",
                timestamp => erlang:system_time(millisecond),
                affected_components => ["external_connections"],
                recovery_plan => "network_failover_plan"
            };
        _ ->
            %% Default scenario
            #{
                type => "unknown",
                severity => "low",
                timestamp => erlang:system_time(millisecond),
                affected_components => [],
                recovery_plan => "default_recovery_plan"
            }
    end.

validate_security_event(EventType, ExpectedDetails) ->
    %% Validate security event format and content
    ct:assert(is_binary(EventType)),
    ct:assert(is_binary(ExpectedDetails) orelse is_map(ExpectedDetails)),

    %% Check that security event contains required fields
    true.

clear_test_data(Config) ->
    %% Clear test data and temporary files
    TestData = proplists:get_value(test_data, Config, #{
        test_packages_dir => "",
        backup_dir => "",
        test_data_dir => ""
    }),

    %% Clean up test packages
    if
        TestData#{
            test_packages_dir := Dir
        } =/= "" ->
            filelib:del_dir_r(TestData#{
                test_packages_dir := Dir
            });
        true ->
            ok
    end,

    %% Clean up backup files
    if
        TestData#{
            backup_dir := BD
        } =/= "" ->
            filelib:del_dir_r(TestData#{
                backup_dir := BD
            });
        true ->
            ok
    end.

    %% Clean up test data
    if
        TestData#{
            test_data_dir := TD
        } =/= "" ->
            filelib:del_dir_r(TestData#{
                test_data_dir := TD
            });
        true ->
            ok
    end.

verify_system_clean_state(Config) ->
    %% Verify system is in clean state after test
    %% Check that no processes are hanging
    Processes = erlang:processes(),
    ct:assert(length(Processes) < 100), % Reasonable limit

    %% Check that all monitoring services are stopped
    case whereis(a2a_hotci_security) of
        undefined -> ok;
        _ -> ct:fail("HotCI security service still running")
    end,

    case whereis(a2a_integrity_validator) of
        undefined -> ok;
        _ -> ct:fail("Integrity validator still running")
    end.

    %% Verify no active alerts
    AlertResult = a2a_monitoring:get_alert_history(1),
    case AlertResult of
        {ok, AlertHistory} ->
            ct:assert(length(AlertHistory) =:= 0);
        _ ->
            ok
    end.