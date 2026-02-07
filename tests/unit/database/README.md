# Cloud SQL Database Tests

Comprehensive test suite for Google Cloud SQL functionality including connection, failover, and replication testing.

## Test Overview

This test suite validates critical Cloud SQL functionality:

### 1. Connection Tests (`test_cloudsql_connection.py`)
Tests database connection functionality with 11 test cases:

- **Successful Connection**: Validates basic database connection establishment
- **SSL/TLS Connections**: Tests secure connections with SSL enabled
- **Connection Pooling**: Verifies connection pool management and multiple concurrent connections
- **Connection Timeout**: Tests timeout handling for slow connections
- **Retry Logic**: Validates connection retry mechanism with exponential backoff
- **Private IP Connections**: Tests VPC-based private IP connectivity
- **IAM Authentication**: Validates IAM-based authentication mechanism
- **Connection Closure**: Tests proper connection cleanup and resource management
- **Invalid Credentials**: Verifies proper error handling for authentication failures
- **Max Connections Limit**: Tests behavior when connection limits are reached
- **Concurrent Connections**: Validates concurrent connection establishment

### 2. Failover Tests (`test_cloudsql_failover.py`)
Tests database failover mechanisms with 16 test cases:

- **Primary Failure Detection**: Validates detection of primary instance failures
- **Automatic Failover**: Tests automatic failover to healthy replicas
- **Manual Failover**: Validates manual failover to specific replicas
- **No Healthy Replicas**: Tests behavior when no healthy replicas are available
- **Concurrent Failover Prevention**: Ensures only one failover occurs at a time
- **Failover Recovery Time**: Validates failover completes within acceptable time limits
- **Failover Notifications**: Tests notification system for failover events
- **Replica Promotion**: Validates promotion of replica to primary role
- **Primary Demotion**: Tests demotion of primary to replica role
- **Failover History**: Verifies tracking of failover events and history
- **Status Reporting**: Tests failover status and state reporting
- **Heartbeat Timeout Detection**: Validates detection via heartbeat monitoring
- **Regional Failover**: Tests failover in regional HA configurations
- **Application Reconnection**: Validates application reconnection after failover
- **Manual Failover Validation**: Tests prevention of failover to unhealthy replicas
- **Multiple Replica Failover**: Tests failover selection with multiple replicas

### 3. Replication Tests (`test_cloudsql_replication.py`)
Tests database replication functionality with 20 test cases:

- **Read Replica Creation**: Validates creation of read replicas
- **Multiple Replicas**: Tests management of multiple read replicas
- **Replica Removal**: Validates removal of read replicas
- **Replication Lag Monitoring**: Tests monitoring of replication lag
- **High Lag Detection**: Validates detection of excessive replication lag
- **Replica Monitoring**: Tests comprehensive monitoring of all replicas
- **Data Consistency Verification**: Validates data consistency between primary and replicas
- **Inconsistency Detection**: Tests detection of data inconsistencies
- **Replica Synchronization**: Validates forced sync of all replicas
- **Cross-Region Replication**: Tests replication across multiple regions
- **Region-Based Replica Selection**: Validates replica selection by region
- **Least Lagged Replica**: Tests identification of replica with minimal lag
- **Replication Slot Management**: Validates PostgreSQL replication slot management
- **Read Scaling**: Tests read load distribution across replicas
- **Replication Health Monitoring**: Validates health status monitoring
- **Continuous Monitoring**: Tests ongoing replication metrics collection
- **Lag Alert Thresholds**: Validates alerting on excessive lag
- **Replica to Primary Promotion**: Tests replica promotion during failures
- **Primary Requirement Validation**: Ensures primary is required before adding replicas
- **Metrics Collection**: Tests comprehensive replication metrics tracking

## Test Execution

### Run All Database Tests
```bash
python -m pytest tests/unit/database/ -v --override-ini="addopts="
```

### Run Specific Test Suite
```bash
# Connection tests only
python -m pytest tests/unit/database/test_cloudsql_connection.py -v --override-ini="addopts="

# Failover tests only
python -m pytest tests/unit/database/test_cloudsql_failover.py -v --override-ini="addopts="

# Replication tests only
python -m pytest tests/unit/database/test_cloudsql_replication.py -v --override-ini="addopts="
```

### Generate HTML Report
```bash
python -m pytest tests/unit/database/ -v --override-ini="addopts=" \
  --html=tests/unit/database/test_report.html --self-contained-html
```

## Test Results Summary

**Total Tests**: 47
- Connection Tests: 11
- Failover Tests: 16
- Replication Tests: 20

**Status**: ✅ All tests passing

## Test Architecture

The tests use:
- **pytest**: Modern testing framework with async support
- **pytest-asyncio**: For testing async database operations
- **Mock objects**: To simulate Cloud SQL behavior without real infrastructure
- **Fixtures**: For reusable test configurations and objects

## Key Features Tested

### High Availability
- Automatic failover detection and execution
- Manual failover capabilities
- Replica promotion and primary demotion
- Regional high availability configurations

### Performance & Scalability
- Connection pooling and management
- Read replica scaling
- Concurrent connection handling
- Replication lag monitoring

### Security
- SSL/TLS encrypted connections
- IAM-based authentication
- Private IP connectivity
- Credential validation

### Reliability
- Connection retry logic with exponential backoff
- Timeout handling
- Health monitoring
- Data consistency verification

## Configuration

Tests use mock configurations that mirror production Cloud SQL setups:
- **Instance Name**: test-project:us-central1:test-instance
- **Database**: test_db
- **Regions**: us-central1, us-east1, europe-west1, asia-southeast1
- **Tier**: db-custom-2-7680 (custom 2 vCPU, 7.68 GB RAM)
- **Availability**: REGIONAL (high availability)

## Dependencies

See `requirements.txt` for the full list of test dependencies.

Key dependencies:
- pytest >= 7.4.3
- pytest-asyncio >= 0.21.1
- pytest-mock >= 3.12.0

## Future Enhancements

Potential areas for expansion:
1. Performance benchmarking tests
2. Backup and restore testing
3. Point-in-time recovery validation
4. Maintenance window testing
5. Query insights validation
6. Database flag configuration tests
7. Integration tests with actual Cloud SQL instances (separate from unit tests)
