# YAWL Configuration Reference

## Overview

The YAWL system provides comprehensive configuration options for workflow orchestration, persistence, logging, and performance tuning. This document covers all configuration aspects of the YAWL Erlang SDK, including application environment settings, runtime configuration, and performance optimization parameters.

## Application Configuration

### Main Application Configuration

The YAWL system is configured through the Erlang application environment. Configuration can be set in:

1. `sys.config` file
2. Application environment at runtime
3. Environment variables

#### Basic Configuration

```erlang
%% sys.config
{a2a_erl, [
    {max_concurrent_workflows, 100},
    {default_timeout, 30000},
    {enable_metrics, true},
    {enable_logging, true},
    {log_level, info},
    {persistence, [
        {backend, mnesia},
        {storage_type, disc_copies},
        {backup_interval, 86400000}  % 24 hours
    ]}
]}.
```

### Detailed Configuration Options

#### Workflow Configuration

```erlang
%% Workflow orchestration settings
{yawl, [
    %% Maximum number of concurrent workflows
    {max_concurrent_workflows, 100},

    %% Default workflow timeout (milliseconds)
    {default_timeout, 30000},

    %% Enable workflow metrics collection
    {enable_metrics, true},

    %% Workflow retry policy
    {retry_policy, [
        {max_retries, 3},
        {retry_delay, 1000},
        {exponential_backoff, true},
        {max_retry_delay, 30000}
    ]},

    %% Workflow cleanup settings
    {cleanup_policy, [
        {completed_retention, 86400000},  % 24 hours
        {failed_retention, 259200000},    % 3 days
        {cleanup_interval, 3600000}      % 1 hour
    ]}
]}.
```

#### Persistence Configuration

```erlang
%% Persistence layer settings
{yawl_persistence, [
    %% Mnesia configuration
    {mnesia, [
        {storage_type, disc_copies},
        {ram_copies, []},
        {disc_only_copies, [yawl_checkpoint]},
        {auto_repair, true},
        {fallback_to_disc, true}
    ]},

    %% Backup settings
    {backup, [
        {enabled, true},
        {interval, 86400000},    % 24 hours
        {directory, "/backups"},
        {max_backups, 7},
        {compression, gzip}
    ]},

    %% Checkpoint settings
    {checkpoints, [
        {enabled, true},
        {auto_checkpoint, true},
        {checkpoint_interval, 60000},    % 1 minute
        {max_checkpoints_per_workflow, 10},
        {cleanup_interval, 3600000}     % 1 hour
    ]},

    %% Performance settings
    {performance, [
        {transaction_timeout, 30000},
        {query_timeout, 10000},
        {connection_pool_size, 10},
        {enable_indexing, true}
    ]}
]}.
```

#### XES Logging Configuration

```erlang
%% XES event logging settings
{yawl_xes, [
    %% Output directory for XES files
    {output_dir, "xes_logs"},

    %% Batch processing settings
    {batch_size, 1000},
    {batch_timeout, 1000},

    %% Memory management
    {max_events_per_log, 100000},
    {cleanup_interval, 3600000},

    ** File handling
    {compression_level, 6},
    {max_file_size, 104857600},  % 100MB
    {backup_count, 5},

    %% Timestamp settings
    {enable_timestamps, true},
    {timestamp_precision, millisecond},
    {timezone, utc},

    %% Performance settings
    {async_mode, true},
    {queue_size, 10000},
    {queue_timeout, 5000}
]}.
```

#### Error Handling Configuration

```erlang
%% Error handling and recovery
{yawl_errors, [
    %% Error tracking
    {enable_error_tracking, true},
    {max_error_history, 1000},

    %% Error recovery
    {auto_retry_enabled, true},
    {retry_delays, [1000, 5000, 15000]},
    {deadlock_detection, true},
    {deadlock_timeout, 30000},

    ** Logging
    {error_log_level, warning},
    {error_log_file, "logs/yawl_errors.log"},
    {enable_stacktrace, true}
]}.
```

#### Performance Configuration

```erlang
%% Performance tuning
{yawl_performance, [
    %% Connection pooling
    {pool_size, 10},
    {pool_timeout, 5000},
    {max_overflow, 5},

    ** Caching
    {enable_pattern_cache, true},
    {cache_size, 1000},
    {cache_ttl, 3600000},

    ** Concurrency
    {worker_pool_size, 8},
    {max_concurrent_operations, 50},
    {operation_timeout, 30000},

    ** Monitoring
    {enable_monitoring, true},
    {metrics_interval, 10000},
    {performance_threshold, 1000}
]}.
```

#### Security Configuration

```erlang
%% Security settings
{yawl_security, [
    %% Authentication
    {auth_enabled, false},
    {auth_module, yawl_auth_jwt},
    {token_ttl, 3600000},

    ** Authorization
    {rbac_enabled, true},
    {role_cache_size, 100},
    {permission_check_interval, 60000},

    ** Data protection
    {encrypt_sensitive_data, true},
    {encryption_key, "default_change_me"},
    {enable_audit_logging, true},

    ** Network
    {allowed_origins, ["*"]},
    {enable_cors, true},
    {rate_limiting, [
        {enabled, true},
        {requests_per_minute, 1000},
        {burst_size, 100}
    ]}
]}.
```

#### Colored Petri Nets Configuration

```erlang
%% CPN and Python integration
{yawl_cpn, [
    %% Color sets
    {color_sets, [
        {boolean, #{type => boolean}},
        {integer, #{type => integer}},
        {float, #{type => float}},
        {string, #{type => string}},
        {any, #{type => any}}
    ]},

    %% Python bridge
    {python_bridge, [
        {enabled, true},
        {python_executable, "python3"},
        {bridge_timeout, 30000},
        {pm4py_path, "/usr/local/lib/python3.8/site-packages"},
        {enable_cache, true},
        {cache_size, 100}
    ]},

    ** JSON handling
    {json_format, cpn},
    {llm_integration, [
        {enabled, true},
        {max_response_size, 1048576},  % 1MB
        {timeout, 15000}
    ]}
]}.
```

## Runtime Configuration

### Application Environment Updates

```erlang
%% Update configuration at runtime
application:set_env(a2a_erl, max_concurrent_workflows, 200).
application:set_env(a2a_erl, default_timeout, 60000).

%% Update persistence configuration
application:set_env(yawl_persistence, checkpoint_interval, 30000).

%% Update logging configuration
application:set_env(yawl_xes, batch_size, 2000).
```

### Dynamic Configuration Management

```erlang
%% Get current configuration
Config = application:get_all_env(a2a_erl).

%% Check specific configuration value
MaxWorkflows = application:get_env(a2a_erl, max_concurrent_workflows, 100).

%% Update multiple settings
NewSettings = [
    {max_concurrent_workflows, 150},
    {enable_metrics, false},
    {retry_policy, [
        {max_retries, 5},
        {retry_delay, 2000}
    ]}
],
lists:foreach(fun({K, V}) -> application:set_env(a2a_erl, K, V) end, NewSettings).
```

## Pattern-Specific Configuration

### Basic Patterns

```erlang
%% Basic Sequential Pattern
{basic_sequential, [
    {timeout_per_task, 10000},
    {task_dependencies, []},
    {error_handling, abort_on_failure}
]}.

%% Parallel Split Pattern
{parallel_split, [
    {branches, 4},
    {synchronization_timeout, 30000},
    {enable_branch_cancellation, true},
    {branch_result_aggregation, all}
]}.

%% Parallel Join Pattern
{parallel_join, [
    {required_completions, all},
    {timeout, 60000},
    {partial_completion_handling, wait},
    {enable_progress_tracking, true}
]}.

%% Exclusive Choice Pattern
{exclusive_choice, [
    {conditions, []},
    {default_branch, 1},
    {condition_evaluation_mode, eager},
    {enable_timeout, true},
    {timeout, 15000}
]}.
```

### Advanced Patterns

```erlang
%% Multi-Choice Pattern
{multi_choice, [
    {branches, 5},
    {execution_mode, parallel},
    {max_concurrent_branches, 3},
    {branch_selection_strategy, priority},
    {enable_partial_results, true},
    {aggregation_mode, merge}
]}.

%% Synchronizing Merge Pattern
{synchronizing_merge, [
    {input_branches, 4},
    {output_branches, 1},
    {synchronization_timeout, 45000},
    {enable_timeout_recovery, true},
    {recovery_strategy, rollback}
]}.

%% N-of-M Pattern
{n_of_m, [
    {m_total, 5},
    {n_required, 3},
    {selection_strategy, first_n},
    {timeout, 30000},
    {enable_progress_monitoring, true},
    {completion_handling, immediate}
]}.
```

### Cancellation Patterns

```erlang
%% Cancellation Scope Pattern
{cancellation_scope, [
    {scope_type, immediate},
    {cancellation_strategy, synchronous},
    {enable_cancellation_propagation, true},
    {cleanup_mode, immediate},
    {error_handling, graceful}
]}.

%% Cancelation Point Pattern
{cancellation_point, [
    {point_type, explicit},
    {cancellation_level, local},
    {enable_pre_conditions, true},
    {timeout, 10000},
    {grace_period, 5000}
]}.
```

## Resource Configuration

### Resource Allocation

```erlang
%% Resource management configuration
{yawl_resources, [
    %% Resource pools
    {resource_pools, [
        {cpu, [
            {size, 8},
            {max_concurrent, 4},
            {queue_size, 100},
            {timeout, 30000}
        ]},
        {memory, [
            {size, 4096},  % MB
            {max_concurrent, 2},
            {queue_size, 50},
            {timeout, 60000}
        ]},
        {io, [
            {size, 4},
            {max_concurrent, 1},
            {queue_size, 200},
            {timeout, 45000}
        ]}
    ]},

    ** Resource allocation strategy
    {allocation_strategy, round_robin},
    {enable_priority, true},
    {max_allocations_per_workflow, 10},

    ** Monitoring
    {enable_resource_monitoring, true},
    {metrics_interval, 5000},
    {warning_threshold, 80},
    {critical_threshold, 95}
]}.
```

### Data Mapping Configuration

```erlang
%% Data mapping and transformation
{yawl_data, [
    %% Data validation
    {enable_validation, true},
    {strict_mode, false},
    {max_data_size, 10485760},  % 10MB

    ** Data transformation
    {enable_transformation, true},
    {transformation_timeout, 5000},
    {cache_transformations, true},
    {transformation_cache_size, 1000},

    ** Serialization
    {serialization_format, json},
    {enable_compression, true},
    {compression_threshold, 1024},  % 1KB
    {compression_level, 6}
]}.
```

## Monitoring and Metrics Configuration

### Metrics Collection

```erlang
%% Metrics configuration
{yawl_metrics, [
    %% Metrics collection
    {enabled, true},
    {collection_interval, 10000},
    {retention_period, 86400000},  % 24 hours

    ** Metrics types
    {workflow_metrics, [
        {start_time, true},
        {end_time, true},
        {duration, true},
        {status, true},
        {pattern_type, true}
    ]},

    {resource_metrics, [
        {cpu_usage, true},
        {memory_usage, true},
        {io_operations, true},
        {queue_wait_time, true}
    ]},

    {error_metrics, [
        {error_rate, true},
        {error_types, true},
        {recovery_attempts, true},
        {failure_patterns, true}
    ]}
]}.
```

### Logging Configuration

```erlang
%% Logging configuration
{yawl_logging, [
    %% Log levels
    {log_level, info},
    {log_level_module, debug},

    %% File logging
    {log_to_file, true},
    {log_file, "logs/yawl.log"},
    {log_file_size, 104857600},  % 100MB
    {log_file_count, 5},
    {log_rotation, daily},

    ** Console logging
    {log_to_console, true},
    {console_format, text},
    {console_color, true},

    ** Format settings
    {log_format, structured},
    {enable_metadata, true},
    {include_timestamp, true},
    {include_pid, true},
    {include_module, true},

    ** Async logging
    {async_mode, true},
    {queue_size, 10000},
    {queue_timeout, 5000},
    {flush_interval, 1000}
]}.
```

## Performance Optimization

### Caching Configuration

```erlang
%% Caching settings
{yawl_cache, [
    %% Pattern cache
    {pattern_cache, [
        {enabled, true},
        {size, 1000},
        {ttl, 3600000},  % 1 hour
        {eviction_policy, lru}
    ]},

    ** Configuration cache
    {config_cache, [
        {enabled, true},
        {size, 500},
        {ttl, 1800000}  % 30 minutes
    ]},

    ** Metadata cache
    {metadata_cache, [
        {enabled, true},
        {size, 2000},
        {ttl, 7200000},  % 2 hours
        {preload_on_startup, true}
    ]}
]}.
```

### Connection Pool Configuration

```erlang
%% Database connection pool
{yawl_pool, [
    %% Pool settings
    {pool_size, 10},
    {max_overflow, 5},
    {strategy, lifo},
    {checkout_timeout, 5000},

    ** Maintenance
    {cleanup_interval, 60000},
    {max_age, 3600000},  % 1 hour
    {max_idle_time, 1800000},  % 30 minutes

    ** Monitoring
    {enable_monitoring, true},
    {monitor_interval, 30000},
    {health_check_interval, 10000}
]}.
```

### Cluster Configuration

```erlang
%% Cluster configuration
{yawl_cluster, [
    %% Node discovery
    {discovery_mode, static},
    {static_nodes, ['node1@host', 'node2@host']},
    {auto_discovery, false},
    {heartbeat_interval, 30000},

    ** Load balancing
    {load_balancing, round_robin},
    {enable_work_stealing, true},
    {work_stealing_interval, 15000},

    ** Synchronization
    {enable_synchronization, true},
    {sync_interval, 60000},
    {sync_timeout, 30000},
    {conflict_resolution, last_write_wins}
]}.
```

## Migration Configuration

### Version Migration

```erlang
%% Migration configuration
{yawl_migration, [
    {current_version, "2.0.0"},
    {target_version, "2.1.0"},
    {auto_migrate, true},
    {backup_before_migrate, true},
    {migration_timeout, 300000},  % 5 minutes
    {enable_validation, true},
    {validation_timeout, 120000}
]}.
```

### Python Bridge Migration

```erlang
%% Python bridge migration settings
{yawl_python_migration, [
    {bridge_version, "2.0.0"},
    {compatibility_mode, backward},
    {enable_validation, true},
    {migration_timeout, 60000},
    {fallback_mode, local},
    {enable_logging, true},
    {log_file, "logs/python_migration.log"}
]}.
```

## Configuration Validation

### Configuration Schema

```erlang
%% Validate configuration
validate_config() ->
    RequiredSettings = [
        max_concurrent_workflows,
        default_timeout,
        persistence_backend
    ],

    lists:foreach(fun(Setting) ->
        case application:get_env(a2a_erl, Setting) of
            undefined ->
                error({missing_required_setting, Setting});
            _ -> ok
        end
    end, RequiredSettings).
```

### Configuration Health Check

```erlang
%% Perform configuration health check
perform_health_check() ->
    %% Check critical settings
    CriticalSettings = [
        {max_concurrent_workflows, is_integer},
        {default_timeout, is_integer},
        {persistence_backend, is_atom}
    ],

    HealthStatus = lists:foldl(fun({Key, Validator}, Acc) ->
        case application:get_env(a2a_erl, Key) of
            undefined ->
                Acc#{Key => {error, not_found}};
            {ok, Value} ->
                case Validator(Value) of
                    true -> Acc#{Key => ok};
                    false -> Acc#{Key => {error, invalid}}
                end
        end
    end, #{}, CriticalSettings),

    %% Check system resources
    SystemHealth = check_system_resources(),

    #{config => HealthStatus, system => SystemHealth}.
```

## Best Practices

### Configuration Management

1. **Environment-Specific Configurations**
   - Use separate configuration files for development, testing, and production
   - Implement configuration templates for consistent setup
   - Use environment variables for sensitive values

2. **Configuration Validation**
   - Always validate configuration before starting services
   - Implement health checks for critical settings
   - Provide meaningful error messages for invalid configurations

3. **Performance Considerations**
   - Cache frequently accessed configuration values
   - Use appropriate data types for performance
   - Monitor configuration impact on system performance

4. **Security**
   - Never store sensitive data in plain text
   - Use encrypted configuration for passwords and API keys
   - Implement proper access controls for configuration files

5. **Documentation**
   - Document all configuration options
   - Include examples for common use cases
   - Maintain configuration version history

### Common Configuration Scenarios

#### High-Performance Configuration

```erlang
%% High-performance configuration
{a2a_erl, [
    {max_concurrent_workflows, 1000},
    {default_timeout, 10000},
    {enable_metrics, true},
    {persistence, [
        {backend, mnesia},
        {storage_type, ram_copies},
        {cache_size, 10000}
    ]}
]}.
```

#### High-Availability Configuration

```erlang
%% High-availability configuration
{a2a_erl, [
    {max_concurrent_workflows, 500},
    {default_timeout, 60000},
    {enable_metrics, true},
    {enable_cluster, true},
    {persistence, [
        {backend, mnesia},
        {storage_type, disc_copies},
        {backup_interval, 3600000},
        {checkpoint_interval, 30000}
    ]}
]}.
```

#### Development Configuration

```erlang
%% Development configuration
{a2a_erl, [
    {max_concurrent_workflows, 10},
    {default_timeout, 10000},
    {enable_metrics, false},
    {enable_debug, true},
    {log_level, debug},
    {persistence, [
        {backend, mnesia},
        {storage_type, ram_copies},
        {auto_repair, true}
    ]}
]}.
```