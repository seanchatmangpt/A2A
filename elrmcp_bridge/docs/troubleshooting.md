# Troubleshooting Guide

This guide provides solutions for common issues encountered while working with the elrmcp bridge.

## Common Issues

### Connection Issues

#### Bridge Cannot Connect to Craftplan MCP

**Symptoms**
- Bridge initialization fails
- Connection timeout errors
- Tools not registering

**Solutions**

1. **Verify Craftplan MCP is running**
   ```bash
   # Check Craftplan MCP status
   curl -f http://localhost:8090/health

   # If not running, start it
   cd craftplan/mcp-server
   make start
   ```

2. **Check URL configuration**
   ```json
   {
     "elrmcp_bridge": {
       "craftplan": {
         "url": "http://localhost:8090",
         "timeout": 30000
       }
     }
   }
   ```

3. **Test network connectivity**
   ```bash
   # Test connectivity from bridge host
   telnet localhost 8090
   nc -zv localhost 8090

   # Test from within container/K8s pod
   kubectl exec -it elrmcp-bridge-xxx -- telnet craftplan-mcp 8090
   ```

4. **Check authentication**
   ```json
   {
     "elrmcp_bridge": {
       "craftplan": {
         "auth_token": "your-api-key"
       }
     }
   }
   ```

#### High Latency Connection

**Symptoms**
- Slow response times
- Timeouts
- Poor performance

**Solutions**

1. **Reduce timeouts**
   ```json
   {
     "craftplan": {
       "timeout": 15000,
       "connect_timeout": 3000
     }
   }
   ```

2. **Enable caching**
   ```json
   {
     "performance": {
       "enable_caching": true,
       "cache_ttl": 300000
     }
   }
   ```

3. **Check network path**
   ```bash
   # Network path analysis
   traceroute craftplan-mcp
   mtr craftplan-mcp

   # Bandwidth testing
   iperf3 -c craftplan-mcp
   ```

### Tool Registration Issues

#### Tools Not Registering

**Symptoms**
- Empty tool list
- Registration failures
- Unknown tool errors

**Solutions**

1. **Check tool availability**
   ```bash
   # Test direct connection
   curl -X POST http://localhost:8090/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"tools/list","id":"123"}'
   ```

2. **Check whitelist/blacklist configuration**
   ```json
   {
     "tool_management": {
       "whitelist": ["customer_management", "order_management"],
       "blacklist": ["admin_tools"]
     }
   }
   ```

3. **Enable auto-register**
   ```json
   {
     "tool_management": {
       "auto_register": true
     }
   }
   ```

#### Invalid Tool Schemas

**Symptoms**
- Schema validation errors
- Tool call failures
- Bad request errors

**Solutions**

1. **Verify tool schemas**
   ```erlang
   % Get tool definition
   elrmcp_mcp_bridge:get_tool_info(<<"customer_management">>).
   ```

2. **Check schema compliance**
   ```bash
   # Validate tool schema
   curl -X POST http://localhost:8090/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"customer_management","arguments":{"operation":"list"}},"id":"123"}'
   ```

3. **Update tool whitelist**
   ```json
   {
     "tool_management": {
       "whitelist": ["customer_management"]
     }
   }
   ```

### Rate Limiting Issues

#### Rate Limit Exceeded

**Symptoms**
- 429 Too Many Requests errors
- Request failures
- Throttled performance

**Solutions**

1. **Increase rate limits**
   ```json
   {
     "rate_limiting": {
       "requests_per_second": 200,
       "burst_size": 20
     }
   }
   ```

2. **Implement request queuing**
   ```erlang
   % Add request queuing logic
   -spec queue_request(binary(), map()) -> {ok, map()} | {error, term()}.
   queue_request(ToolName, Args) ->
       case rate_limiter:check() of
           allowed -> forward_request(ToolName, Args);
           denied -> {error, rate_limited}
       end.
   ```

3. **Monitor rate limiting metrics**
   ```bash
   # Check rate limiting metrics
   curl http://localhost:9090/metrics | grep elrmcp_bridge_rate_limit

   # Monitor available tokens
   curl http://localhost:9090/metrics | grep elrmcp_bridge_tokens
   ```

#### Rate Limiter Not Working

**Symptoms**
- No rate limiting applied
- Unlimited requests
- Resource exhaustion

**Solutions**

1. **Enable rate limiting**
   ```json
   {
     "rate_limiting": {
       "enabled": true
     }
   }
   ```

2. **Check configuration**
   ```bash
   # Verify configuration
   grep rate_limit config/bridge.config

   # Test rate limiting
   for i in {1..10}; do curl http://localhost:8091/mcp; done
   ```

### Performance Issues

#### High Memory Usage

**Symptoms**
- High memory consumption
- Memory leaks
- Slow performance

**Solutions**

1. **Check memory usage**
   ```bash
   # Monitor memory usage
   ps aux | grep elrmcp_bridge
   kubectl top pods -n elrmcp-bridge

   # Check Erlang memory
   erl -eval 'io:format("~p~n", [erlang:memory()]).' -s init stop
   ```

2. **Optimize cache size**
   ```json
   {
     "performance": {
       "cache_size": 500,
       "cache_ttl": 1800000
     }
   }
   ```

3. **Enable garbage collection**
   ```erlang
   % Add to vm.args
   -env ERL_FULLSWEEP_AFTER 100
   ```

#### High CPU Usage

**Symptoms**
- High CPU utilization
- Slow response times
- System overload

**Solutions**

1. **Monitor CPU usage**
   ```bash
   # Check CPU usage
   top -p $(pgrep -f elrmcp_bridge)
   kubectl top pods -n elrmcp-bridge

   # CPU profiling
   erl +pc unicode -eval "profiling:start(), your_function(), profiling:stop()."
   ```

2. **Optimize tool calls**
   ```erlang
   % Batch requests
   batch_call_tools(Tools, Args) ->
       lists:map(fun(Tool) -> call_tool(Tool, Args) end, Tools).
   ```

3. **Scale horizontally**
   ```yaml
   # Kubernetes scaling
   replicas: 3
   resources:
     requests:
       cpu: "500m"
     limits:
       cpu: "1000m"
   ```

### Error Handling Issues

#### Common Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| -32601 | Method not found | Check tool name and availability |
| -32602 | Invalid params | Validate input schema |
| -32000 | Bridge error | Check bridge logs |
| -32001 | Rate limited | Adjust rate limits or implement queuing |

#### Error Debugging

1. **Check error logs**
   ```bash
   # Application logs
   tail -f logs/erlang.log.1

   # System logs
   journalctl -u elrmcp-bridge -f
   ```

2. **Enable debug logging**
   ```bash
   export LOG_LEVEL=debug
   make start
   ```

3. **Request tracing**
   ```erlang
   % Add request tracing
   trace_request(ToolName, Args) ->
       lager:debug("Request: ~p ~p", [ToolName, Args]),
       Result = call_tool(ToolName, Args),
       lager:debug("Response: ~p", [Result]),
       Result.
   ```

### Configuration Issues

#### Configuration Not Loading

**Symptoms**
- Default values being used
- Configuration ignored
- Application startup failures

**Solutions**

1. **Check file permissions**
   ```bash
   # Check file access
   ls -la config/bridge.config

   # Fix permissions
   chmod 644 config/bridge.config
   ```

2. **Validate configuration**
   ```bash
   # Validate JSON syntax
   python -m json.tool config/bridge.config

   # Test configuration loading
   rebar3 shell --config test/test.config
   ```

3. **Check configuration format**
   ```json
   {
     "elrmcp_bridge": {
       "craftplan": {
         "url": "http://localhost:8090"
       }
     }
   }
   ```

#### Environment Variables Not Working

**Solutions**

1. **Check environment setup**
   ```bash
   # Verify environment variables
   echo $CRAFTPLAN_URL

   # Set environment
   export CRAFTPLAN_URL="http://localhost:8090"
   ```

2. **Check environment precedence**
   ```erlang
   % Environment override order:
   % 1. Runtime API
   % 2. Environment variables
   % 3. Configuration files
   % 4. Defaults
   ```

### Testing Issues

#### Tests Failing

**Symptoms**
- Unit test failures
- Integration test failures
- Test timeouts

**Solutions**

1. **Check test dependencies**
   ```bash
   # Verify dependencies
   rebar3 deps

   # Install missing dependencies
   rebar3 install_deps
   ```

2. **Run tests with verbose output**
   ```bash
   # EUnit tests
   rebar3 eunit --verbose

   # Common Test
   rebar3 ct --verbose
   ```

3. **Check test configuration**
   ```bash
   # Verify test config
   cat test/test.config

   # Run with specific config
   rebar3 ct --config test/test.config
   ```

#### Mock Services Not Working

**Solutions**

1. **Check mock service setup**
   ```bash
   # Start mock service
   make start-mock-craftplan

   # Verify mock service
   curl -f http://localhost:18090/health
   ```

2. **Test mock service interaction**
   ```erlang
   % Test mock service
   {ok, Tools} = elrmcp_mcp_client:list_tools(),
   ct:assertMatch([_|_], Tools).
   ```

### Deployment Issues

#### Container Deployment Issues

**Symptoms**
- Container startup failures
- Port mapping issues
- Network connectivity problems

**Solutions**

1. **Check container logs**
   ```bash
   # Docker logs
   docker logs elrmcp-bridge

   # Kubernetes logs
   kubectl logs -f deployment/elrmcp-bridge -n elrmcp-bridge
   ```

2. **Check port mapping**
   ```bash
   # Docker port mapping
   docker port elrmcp-bridge

   # Kubernetes services
   kubectl get services -n elrmcp-bridge
   ```

3. **Test connectivity**
   ```bash
   # Test from outside
   curl http://localhost:8091/health

   # Test from within cluster
   kubectl exec -it test-pod -- curl http://elrmcp-bridge-service:8091/health
   ```

#### Kubernetes Deployment Issues

**Symptoms**
- Pod crashes
- Image pull failures
- Service discovery issues

**Solutions**

1. **Check pod status**
   ```bash
   # Pod status
   kubectl get pods -n elrmcp-bridge

   # Pod events
   kubectl get events -n elrmcp-bridge

   # Pod description
   kubectl describe pod elrmcp-bridge-xxx -n elrmcp-bridge
   ```

2. **Check image issues**
   ```bash
   # Image pull secrets
   kubectl get secrets -n elrmcp-bridge

   # Image pull events
   kubectl describe pod elrmcp-bridge-xxx -n elrmcp-bridge | grep -i image
   ```

3. **Check resource limits**
   ```yaml
   # Check resource requests
   resources:
     requests:
       cpu: "100m"
       memory: "256Mi"
     limits:
       cpu: "500m"
       memory: "512Mi"
   ```

## Performance Optimization

### Performance Tuning

1. **Enable caching**
   ```json
   {
     "performance": {
       "enable_caching": true,
       "cache_size": 2000,
       "cache_ttl": 600000
     }
   }
   ```

2. **Optimize rate limiting**
   ```json
   {
     "rate_limiting": {
       "requests_per_second": 200,
       "burst_size": 20
     }
   }
   ```

3. **Tune VM parameters**
   ```erlang
   % vm.args
   +K true
   +P 1048576
   -hms 64 +hmsz 64
   ```

### Monitoring and Alerting

1. **Set up monitoring**
   ```bash
   # Prometheus
   curl http://localhost:9090/metrics

   # Health checks
   curl http://localhost:8091/health
   ```

2. **Set up alerts**
   ```yaml
   # Alert rules
   - alert: BridgeDown
     expr: up{job="elrmcp-bridge"} == 0
     for: 1m
   ```

## Debug Tools

### Erlang Debug Tools

1. **Interactive Shell**
   ```bash
   rebar3 shell
   ```

2. **Process Monitoring**
   ```erlang
   % Check processes
   processes().

   % Monitor process
   spawn_monitor(fun() -> some_function() end).
   ```

3. **Memory Analysis**
   ```erlang
   % Memory usage
   erlang:memory().

   % Garbage collection
   garbage_collect().
   ```

### Network Debug Tools

1. **Network Diagnostics**
   ```bash
   # Network connectivity
   telnet craftplan-mcp 8090
   nc -zv craftplan-mcp 8090

   # Network path
   traceroute craftplan-mcp
   mtr craftplan-mcp
   ```

2. **HTTP Testing**
   ```bash
   # HTTP requests
   curl -v http://localhost:8090/health

   # Load testing
   ab -n 1000 -c 10 http://localhost:8091/mcp
   ```

### System Monitoring

1. **Resource Monitoring**
   ```bash
   # System resources
   top

   # Container resources
   docker stats elrmcp-bridge

   # Kubernetes resources
   kubectl top pods -n elrmcp-bridge
   ```

2. **Application Metrics**
   ```bash
   # Application metrics
   curl http://localhost:9090/metrics

   # Health status
   curl http://localhost:8091/health
   ```

## Support and Community

### Getting Help

1. **GitHub Issues**
   - Search existing issues
   - Create new issue with detailed information
   - Include logs and configuration

2. **Community Forums**
   - Erlang Forums
   - Stack Overflow
   - Bridge-specific forums

3. **Documentation**
   - API documentation
   - User guides
   - Troubleshooting guides

### Contributing

1. **Reporting Bugs**
   - Include reproduction steps
   - Provide logs and configuration
   - Describe expected vs actual behavior

2. **Feature Requests**
   - Describe use case
   - Include requirements
   - Provide implementation suggestions

### Best Practices

1. **Logging**
   - Include request ID in logs
   - Use structured logging
   - Log key events and errors

2. **Configuration**
   - Use environment-specific configs
   - Validate configuration
   - Document configuration changes

3. **Testing**
   - Write comprehensive tests
   - Test error scenarios
   - Integration test with real services

## Conclusion

This troubleshooting guide should help resolve most common issues with the elrmcp bridge. For additional support, please refer to the community resources and documentation.