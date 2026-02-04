# Performance Optimization and Monitoring for Craftplan MCP + A2A

This comprehensive performance optimization system provides real-time monitoring, caching, load testing, and integration capabilities for the Craftplan MCP + A2A system.

## Features

### Performance Monitoring
- **Real-time metrics collection** with configurable intervals
- **Performance dashboards** via WebSocket (port 9090)
- **System health monitoring** (CPU, memory, network, disk)
- **Alerting system** with configurable thresholds
- **Historical data tracking** and time-series analysis

### Caching System
- **Multi-level caching** with configurable TTL and eviction policies
- **LRU/LFU/TTL eviction** strategies
- **Cache statistics** and monitoring
- **Automatic cache cleanup** and size management

### Connection Pooling
- **HTTP connection pooling** with maximum connections and timeouts
- **Automatic connection reuse** and cleanup
- **Connection statistics** and monitoring
- **Load balancing** capabilities

### Load Testing
- **Performance testing** with configurable scenarios
- **Stress testing** for high-load scenarios
- **Endurance testing** for sustained workloads
- **Test result analysis** and reporting
- **Automated test scenarios** with realistic patterns

### Performance Optimization
- **Request/response optimization** for MCP and A2A servers
- **Asynchronous processing** for better throughput
- **Caching strategies** for frequently accessed data
- **Connection management** for better resource utilization
- **Memory optimization** and garbage collection tuning

## Quick Start

### 1. Enable Performance Monitoring
```erlang
performance_integration:start_integration().
performance_integration:enable_monitoring().
```

### 2. Integrate with Existing Systems
```erlang
performance_integration:integrate_mcp_server().
performance_integration:integrate_a2a_server().
```

### 3. Access Performance Dashboard
Connect to WebSocket at `ws://localhost:9090/ws` to view real-time performance data.

### 4. Run Performance Tests
```erlang
% Basic performance test
load_test:run_test(<<"performance_test">>, 300000).

% Stress test with 100 concurrent users
load_test:run_stress_test(100).

% Endurance test for 1 hour
load_test:run_sustained_test(<<"endurance_test">>, 3600000).
```

## Architecture

### Core Components

1. **Performance Metrics** (`performance_metrics.erl`)
   - Collects system and application metrics
   - Maintains counters, gauges, and histograms
   - Configurable collection intervals

2. **Performance Monitor** (`performance_monitor.erl`)
   - Real-time monitoring and alerting
   - Dashboard data generation
   - Alert threshold management

3. **Cache Manager** (`cache_manager.erl`)
   - Multi-level caching system
   - LRU/LFU/TTL eviction policies
   - Cache statistics and monitoring

4. **HTTP Pool** (`http_pool.erl`)
   - Connection pooling for API calls
   - Automatic connection management
   - Load balancing capabilities

5. **Load Test** (`load_test.erl`)
   - Comprehensive testing framework
   - Multiple test types (performance, stress, endurance)
   - Detailed test reporting

### Integration Points

1. **MCP Server Integration**
   - Optimized request handling
   - Cache integration
   - Performance metrics collection
   - Connection pooling for API calls

2. **A2A Server Integration**
   - Task queue optimization
   - Concurrent task processing
   - Memory management
   - Error handling improvements

3. **API Client Integration**
   - Connection pooling
   - Request caching
   - Error retry mechanisms
   - Performance monitoring

## Configuration

### Environment Variables
```bash
# Performance monitoring configuration
export CRAFTPLAN_CACHE_TTL=30000
export CRAFTPLAN_CACHE_SIZE=10000
export CRAFTPLAN_MAX_CONNECTIONS=50
export CRAFTPERFORMANCE_METRICS_INTERVAL=1000

# Dashboard configuration
export DASHBOARD_PORT=9090
export DASHBOARD_UPDATE_INTERVAL=5000

# Load testing configuration
export LOAD_TEST_DURATION=300000
export LOAD_TEST_USERS=10
export LOAD_TEST_RATE=10
```

### Erlang Configuration
```erlang
{performance_metrics, [
    {collection_interval, 1000},
    {metrics_retention, 3600000},
    {export_enabled, true}
]}.

{performance_monitor, [
    {alert_check_interval, 10000},
    {dashboard_port, 9090},
    {alert_thresholds, [
        {mcp_error_rate, 0.05},
        {a2a_error_rate, 0.02},
        {cpu_usage, 80},
        {memory_usage, 80}
    ]}
]}.

{cache_manager, [
    {cache_config, [
        {api_cache, 5000, 300000},
        {mcp_cache, 10000, 60000},
        {session_cache, 1000, 3600000}
    ]}
]}.

{http_pool, [
    {max_pool_size, 50},
    {max_idle_time, 30000},
    {connection_timeout, 10000}
]}.
```

## Monitoring Dashboard

The real-time dashboard provides:

1. **System Overview**
   - Overall health status
   - Key performance indicators
   - Alert status

2. **Performance Metrics**
   - Request rates and response times
   - Error rates and trends
   - Cache hit rates
   - Connection pool statistics

3. **Health Monitoring**
   - CPU and memory usage
   - Network and disk I/O
   - Process counts
   - System load averages

4. **Historical Data**
   - Time-series charts
   - Performance trends
   - Alert history
   - Test results

## Alerts and Thresholds

### Configurable Alerts
- **High error rates**: MCP/A2A/API error rate thresholds
- **High latency**: Response time thresholds
- **Resource usage**: CPU/memory usage thresholds
- **Queue lengths**: Task queue size thresholds
- **Connection issues**: Connection failure rates

### Alert Types
1. **Threshold Alerts**: Fixed value thresholds
2. **Trend Alerts**: Rate-of-change detection
3. **Anomaly Alerts**: Statistical deviation detection

### Notification Channels
- Console logging
- Email notifications
- Webhook integration
- Slack/Teams integration

## Load Testing

### Test Types
1. **Performance Tests**: Baseline performance measurement
2. **Stress Tests**: High-load scenarios to find breaking points
3. **Endurance Tests**: Sustained workloads for stability
4. **Spike Tests**: Sudden load increases to test recovery

### Test Scenarios
- **MCP Tool Calls**: Various tool operations
- **A2A Task Submission**: Different task types
- **API Call Patterns**: Mixed API workload
- **Concurrent User Simulation**: Multi-user scenarios

### Test Metrics
- Requests per second
- Response time percentiles
- Error rates
- Throughput patterns
- Resource utilization

## Optimization Strategies

### 1. Request Optimization
- **Batch operations**: Multiple requests in single calls
- **Connection reuse**: Keep-alive connections
- **Compression**: Response compression
- **Caching**: Cache frequent responses

### 2. Memory Optimization
- **Object pooling**: Reuse objects instead of creating new ones
- **Garbage collection**: Tune GC parameters
- **Memory monitoring**: Track memory usage
- **Leak detection**: Identify memory leaks

### 3. Network Optimization
- **Connection pooling**: Reuse connections
- **Keep-alive**: Maintain connections
- **Compression**: Compress responses
- **Protocol optimization**: Use efficient protocols

### 4. Database Optimization
- **Query optimization**: Optimize database queries
- **Indexing**: Use proper indexes
- **Connection pooling**: Manage database connections
- **Caching**: Cache database results

## Performance Tuning

### 1. System Tuning
```erlang
% Tune VM parameters
+K true           % Enable kernel poll
+P 32768          % Reduce process message queue depth
+hms 32768        % Maximum heap size
+hs 32768         % Heap size
```

### 2. Application Tuning
```erlang
% Tune cache settings
cache_manager:configure_cache(<<"api_cache">>, #{
    max_size => 5000,
    ttl => 300000,
    eviction_policy => lru
}).

% Tune connection pool
http_pool:configure_pool(<<"api_pool">>, #{
    max_size => 50,
    max_idle => 30000,
    timeout => 10000
}).
```

## Troubleshooting

### Common Issues
1. **High Memory Usage**
   - Check for memory leaks
   - Monitor garbage collection
   - Tune cache sizes

2. **High CPU Usage**
   - Profile code for hotspots
   - Optimize algorithms
   - Increase process pool size

3. **Slow Response Times**
   - Check database queries
   - Optimize network calls
   - Increase connection pool size

4. **High Error Rates**
   - Check error logs
   - Validate input data
   - Implement proper error handling

### Debug Tools
```erlang
% Get performance summary
performance_integration:get_performance_summary().

% Get system health
performance_integration:get_system_health().

% Check cache statistics
cache_manager:stats(<<"api_cache">>).

% Check connection pool statistics
http_pool:pool_stats().
```

## Integration Guide

### 1. Integration Steps
1. **Backup existing systems**
2. **Install performance components**
3. **Configure monitoring settings**
4. **Integrate with existing servers**
5. **Test performance improvements**
6. **Monitor and adjust**

### 2. Integration Code
```erlang
% Initialize performance monitoring
performance_integration:start_integration().
performance_integration:enable_monitoring().

% Integrate with MCP server
performance_integration:integrate_mcp_server().

% Integrate with A2A server
performance_integration:integrate_a2a_server().

% Start dashboard
dashboard:start_link().
```

## Performance Metrics

### Key Metrics
- **Request Rate**: Requests per second
- **Response Time**: Average, min, max, percentiles
- **Error Rate**: Percentage of failed requests
- **Throughput**: Data processed per second
- **Resource Utilization**: CPU, memory, network usage

### Metric Categories
1. **Application Metrics**: Business logic performance
2. **System Metrics**: Host system performance
3. **Network Metrics**: Network traffic and latency
4. **Resource Metrics**: Memory and CPU usage

## Future Enhancements

1. **Advanced Analytics**
   - Machine learning for anomaly detection
   - Predictive performance analysis
   - Automated optimization recommendations

2. **Enhanced Monitoring**
   - Distributed tracing
   - Service mesh integration
   - Container monitoring

3. **Improved Testing**
   - Canary testing
   - Chaos engineering
   - A/B testing capabilities

4. **Integration Features**
   - Cloud provider integration
   - Kubernetes monitoring
   - Docker container metrics

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review configuration settings
3. Monitor logs for errors
4. Run diagnostic tests
5. Contact support for assistance

## License

This performance optimization system is part of the Craftplan MCP + A2A project and follows the same license terms.

---

*Note: This comprehensive performance monitoring and optimization system provides real-time insights, automated alerting, and detailed reporting to ensure optimal performance of the Craftplan MCP + A2A system.*