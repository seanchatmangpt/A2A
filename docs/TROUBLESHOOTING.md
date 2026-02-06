# A2A Protocol Troubleshooting Guide

This guide provides solutions to common issues encountered when implementing or operating the Agent2Agent (A2A) Protocol, along with diagnostic procedures and enterprise support escalation paths.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
  - [Connection Issues](#connection-issues)
  - [Authentication & Authorization](#authentication--authorization)
  - [Message Handling](#message-handling)
  - [Task Management](#task-management)
  - [Streaming Issues](#streaming-issues)
  - [Performance Issues](#performance-issues)
  - [Integration Issues](#integration-issues)
- [Advanced Diagnostics](#advanced-diagnostics)
- [Enterprise Support Escalation](#enterprise-support-escalation)

## Quick Diagnostics

Before diving into specific issues, run these quick checks:

### 1. Check Protocol Version Compatibility

```bash
# Verify your A2A protocol version
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "agent/getCard", "id": 1}'
```

Expected response should include version information in the AgentCard.

### 2. Verify Network Connectivity

```bash
# Test basic connectivity
curl -v https://your-agent.example.com/a2a

# Test with timeout
curl --max-time 10 https://your-agent.example.com/a2a
```

### 3. Check Server Logs

Look for these common indicators:
- Authentication failures
- Malformed JSON-RPC requests
- Task timeout errors
- Resource exhaustion warnings

### 4. Validate JSON-RPC Format

Ensure your requests follow JSON-RPC 2.0 specification:
- Must include `jsonrpc: "2.0"`
- Must include `method` field
- Must include `id` field (for requests)
- Parameters should be in `params` object

## Common Issues

### Connection Issues

#### Issue: Connection Refused

**Symptoms:**
- Cannot establish connection to agent endpoint
- Error: `ECONNREFUSED` or `Connection refused`

**Diagnostics:**
```bash
# Check if service is running
systemctl status a2a-agent  # for systemd services

# Check port availability
netstat -tlnp | grep 8080

# Test with telnet
telnet your-agent.example.com 443
```

**Solutions:**
1. Verify the agent service is running
2. Check firewall rules allow inbound connections on required ports
3. Ensure correct endpoint URL and port
4. Verify DNS resolution: `nslookup your-agent.example.com`
5. Check if reverse proxy/load balancer is properly configured

**Prevention:**
- Implement health check endpoints (`/health`, `/readiness`)
- Use monitoring to detect service outages
- Configure automatic service restart on failure

---

#### Issue: SSL/TLS Certificate Errors

**Symptoms:**
- `certificate verify failed`
- `SSL: CERTIFICATE_VERIFY_FAILED`
- `ERR_CERT_AUTHORITY_INVALID`

**Diagnostics:**
```bash
# Check certificate details
openssl s_client -connect your-agent.example.com:443 -showcerts

# Verify certificate chain
curl -vI https://your-agent.example.com/a2a
```

**Solutions:**
1. Ensure certificate is valid and not expired
2. Verify certificate chain includes intermediate certificates
3. Check system trust store includes necessary CA certificates
4. For development: Use proper test certificates (not self-signed in production)
5. Update root CA certificates: `update-ca-certificates` (Linux) or `certutil` (Windows)

**For Development Only:**
```python
# Python - disable SSL verification (NEVER in production)
import requests
requests.post(url, json=payload, verify=False)
```

---

#### Issue: Timeout Errors

**Symptoms:**
- Request times out before completion
- Error: `Request timeout` or `ETIMEDOUT`

**Diagnostics:**
```bash
# Test with increased timeout
curl --max-time 60 -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "agent/getCard", "id": 1}'

# Check network latency
ping your-agent.example.com
traceroute your-agent.example.com
```

**Solutions:**
1. Increase client timeout values (default is often too low for agent operations)
2. For long-running tasks, use async task pattern instead of synchronous
3. Check server-side processing time in logs
4. Implement connection pooling to reduce handshake overhead
5. Use streaming endpoints for progressive updates

**Recommended Timeouts:**
- Connection timeout: 10-30 seconds
- Read timeout for sync operations: 60-120 seconds
- For async operations: Use webhooks or polling instead

---

### Authentication & Authorization

#### Issue: Authentication Failed

**Symptoms:**
- `401 Unauthorized` response
- `Authentication credentials invalid`
- `Token expired`

**Diagnostics:**
```bash
# Test with auth token
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"jsonrpc": "2.0", "method": "agent/getCard", "id": 1}'

# Decode JWT token (if using JWT)
echo "YOUR_TOKEN" | cut -d'.' -f2 | base64 -d | jq
```

**Solutions:**
1. Verify authentication token is included in request headers
2. Check token expiration time (`exp` claim in JWT)
3. Ensure correct authentication scheme (Bearer, API Key, etc.)
4. Verify token has not been revoked
5. Check token issuer and audience match expected values
6. Refresh expired tokens using refresh token flow

**Token Refresh Example:**
```python
import time
from datetime import datetime, timedelta

def get_valid_token():
    if token_expires_at < datetime.now():
        # Refresh token
        token = refresh_authentication()
    return token
```

---

#### Issue: Authorization Failed (Insufficient Permissions)

**Symptoms:**
- `403 Forbidden` response
- `Insufficient permissions` error
- Access denied to specific operations

**Diagnostics:**
```bash
# Check token claims/scopes
# For JWT tokens
echo "YOUR_TOKEN" | cut -d'.' -f2 | base64 -d | jq '.scope'

# Review agent's access control configuration
cat /etc/a2a/access-control.json
```

**Solutions:**
1. Verify token includes required scopes for the operation
2. Check user/service account has necessary permissions
3. Review agent's access control policies
4. Ensure proper role assignment in identity provider
5. For service-to-service: Verify service principal has required grants

**Required Scopes by Operation:**
- `agent:read` - Get agent card
- `task:create` - Send messages, create tasks
- `task:read` - Get task details, list tasks
- `task:write` - Cancel tasks, update task state
- `task:stream` - Stream message responses

---

### Message Handling

#### Issue: Message Not Received

**Symptoms:**
- Message sent but no response
- Task created but no processing occurs
- Silent failures

**Diagnostics:**
```bash
# Verify message was sent successfully
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "task/sendMessage",
    "params": {
      "message": {
        "role": "user",
        "parts": [{"text": "Hello"}]
      }
    },
    "id": 1
  }' -v

# Check server logs for message processing
grep "task/sendMessage" /var/log/a2a-agent/app.log
```

**Solutions:**
1. Verify message format matches A2A message schema
2. Check `role` field is valid (user/agent/system)
3. Ensure at least one `part` is included in message
4. Verify content type of parts matches data
5. Check message size limits (typically 10MB max)
6. Ensure proper JSON-RPC envelope structure
7. Verify task ID is valid if replying to existing task

**Message Validation Checklist:**
- [ ] Valid JSON syntax
- [ ] JSON-RPC 2.0 format
- [ ] Required fields present (role, parts)
- [ ] Valid part types (text, file, data, artifact)
- [ ] Proper encoding for binary data (base64)
- [ ] Valid MIME types for file parts

---

#### Issue: Malformed Message Error

**Symptoms:**
- `400 Bad Request` response
- `Invalid message format`
- `JSON parse error`

**Diagnostics:**
```bash
# Validate JSON syntax
echo '{"your": "json"}' | jq .

# Check message schema
cat message.json | jq '.params.message | keys'
```

**Solutions:**
1. Validate JSON syntax with linter
2. Ensure all required fields are present
3. Check field types match specification
4. Verify enum values are valid (e.g., role must be "user", "agent", or "system")
5. Ensure proper escaping of special characters in text content
6. Check for trailing commas (not allowed in JSON)

**Example Valid Message:**
```json
{
  "jsonrpc": "2.0",
  "method": "task/sendMessage",
  "params": {
    "message": {
      "role": "user",
      "parts": [
        {
          "text": "Please help me with this task"
        }
      ],
      "metadata": {
        "priority": "high"
      }
    }
  },
  "id": "msg-123"
}
```

---

#### Issue: Large Message Handling

**Symptoms:**
- `413 Payload Too Large` response
- Message truncated
- Out of memory errors

**Diagnostics:**
```bash
# Check message size
cat message.json | wc -c

# Check server limits
curl -I https://your-agent.example.com/a2a
# Look for: X-Content-Length-Limit header
```

**Solutions:**
1. Split large messages into multiple smaller messages
2. Use file references instead of embedding large content
3. Implement chunking for large data transfers
4. Use artifact parts for large structured data
5. Consider streaming for large responses
6. Increase server payload limits if appropriate

**Size Recommendations:**
- Single message: < 1MB
- Embedded files: < 5MB (prefer file references)
- Use artifacts for data > 100KB
- Stream responses > 10MB

---

### Task Management

#### Issue: Task Not Found

**Symptoms:**
- `404 Not Found` when getting task
- `Task does not exist` error

**Diagnostics:**
```bash
# Verify task ID format
echo "task-123" | grep -E '^[a-zA-Z0-9_-]+$'

# List existing tasks
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "task/list",
    "params": {},
    "id": 1
  }'
```

**Solutions:**
1. Verify task ID is correct and properly formatted
2. Check if task has been deleted/expired
3. Ensure you have permission to access the task
4. Verify task belongs to your session/user
5. Check task retention policies
6. Confirm task was successfully created (check response from sendMessage)

**Task ID Best Practices:**
- Use UUIDs or unique identifiers
- Store task IDs persistently
- Implement task ID validation
- Handle task expiration gracefully

---

#### Issue: Task State Not Updating

**Symptoms:**
- Task remains in `working` state indefinitely
- Task progress not reflected
- Task never reaches terminal state

**Diagnostics:**
```bash
# Check current task state
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "task/get",
    "params": {"taskId": "YOUR_TASK_ID"},
    "id": 1
  }' | jq '.result.status'

# Monitor task over time
watch -n 5 'curl -s ... | jq .result.status'
```

**Solutions:**
1. Check server logs for processing errors
2. Verify agent implementation properly updates task state
3. Implement task timeout mechanisms
4. Check for deadlocks or blocking operations
5. Ensure database/state store is accessible
6. Monitor agent resource utilization (CPU, memory)
7. Implement health checks for task processing

**Task State Flow:**
```
pending → working → completed (success)
                 → failed (error)
                 → cancelled (user action)
```

---

#### Issue: Cannot Cancel Task

**Symptoms:**
- Cancel operation returns success but task continues
- `409 Conflict` when trying to cancel
- Task in uncancellable state

**Diagnostics:**
```bash
# Attempt to cancel task
curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "task/cancel",
    "params": {"taskId": "YOUR_TASK_ID"},
    "id": 1
  }'

# Check task status after cancellation
curl -X POST ... method: "task/get" ...
```

**Solutions:**
1. Verify task is in cancellable state (pending or working)
2. Check agent supports cancellation (see agent card)
3. Ensure proper cancellation signal handling in agent implementation
4. Implement graceful shutdown for long-running operations
5. Use task timeouts as fallback
6. Check if task has already completed/failed

**Cancellation Support Check:**
```json
// In AgentCard
{
  "capabilities": {
    "taskCancellation": true
  }
}
```

---

### Streaming Issues

#### Issue: Stream Disconnects Unexpectedly

**Symptoms:**
- SSE connection drops mid-stream
- Partial responses received
- Connection reset errors

**Diagnostics:**
```bash
# Test SSE connection with curl
curl -N -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "task/streamMessage",
    "params": {
      "message": {
        "role": "user",
        "parts": [{"text": "Hello"}]
      }
    },
    "id": 1
  }'

# Check for proxy timeout settings
curl -I https://your-agent.example.com/a2a | grep -i timeout
```

**Solutions:**
1. Configure longer timeouts for SSE connections (5-30 minutes)
2. Implement heartbeat/keepalive messages (send comment every 30s)
3. Check reverse proxy SSE support (nginx, Apache)
4. Verify client properly handles SSE reconnection
5. Use reconnection with Last-Event-ID header
6. Implement exponential backoff for reconnection attempts

**Nginx SSE Configuration:**
```nginx
location /a2a {
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 600s;
    proxy_set_header Connection '';
    chunked_transfer_encoding on;
}
```

---

#### Issue: Stream Events Not Parsing

**Symptoms:**
- Cannot parse SSE events
- Missing event data
- Malformed event structure

**Diagnostics:**
```bash
# Inspect raw SSE stream
curl -N -X POST ... | hexdump -C

# Check event format
curl -N -X POST ... | grep -A 2 "^event:"
```

**Solutions:**
1. Verify SSE format: `event: <type>\ndata: <json>\n\n`
2. Ensure proper newline characters (CRLF or LF)
3. Check JSON data is valid within data field
4. Handle multi-line data fields properly
5. Implement robust event parser
6. Validate event types match specification

**SSE Event Format:**
```
event: message
data: {"type": "part", "index": 0, "part": {"text": "Hello"}}

event: message
data: {"type": "done"}
```

---

### Performance Issues

#### Issue: Slow Response Times

**Symptoms:**
- Requests take longer than expected
- Increased latency over time
- Timeouts on operations that previously worked

**Diagnostics:**
```bash
# Measure response time
time curl -X POST https://your-agent.example.com/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "agent/getCard", "id": 1}'

# Check server metrics
curl https://your-agent.example.com/metrics

# Monitor system resources
top -p $(pgrep a2a-agent)
```

**Solutions:**
1. Enable response caching for agent card and static data
2. Implement connection pooling
3. Use compression (gzip/brotli) for large responses
4. Optimize database queries and indexes
5. Scale horizontally with load balancing
6. Implement rate limiting to prevent overload
7. Use CDN for static assets
8. Monitor and optimize slow operations

**Performance Targets:**
- Agent card retrieval: < 100ms
- Message send (sync): < 5s
- Task status check: < 200ms
- Stream initiation: < 1s

---

#### Issue: Memory Leaks

**Symptoms:**
- Increasing memory usage over time
- Out of memory errors
- Agent crashes after extended operation

**Diagnostics:**
```bash
# Monitor memory usage
watch -n 1 'ps aux | grep a2a-agent | grep -v grep'

# Check for memory leaks (Linux)
valgrind --leak-check=full ./a2a-agent

# Heap profiling (if available)
curl https://your-agent.example.com/debug/pprof/heap > heap.prof
```

**Solutions:**
1. Review task cleanup procedures
2. Implement proper resource disposal (connections, files)
3. Set task retention limits and automatic cleanup
4. Use streaming for large data instead of buffering
5. Implement memory limits and circuit breakers
6. Review third-party library usage
7. Use memory profiling tools to identify leaks

**Memory Management Best Practices:**
- Limit concurrent task count
- Set maximum message size
- Implement task TTL (time-to-live)
- Clean up completed tasks periodically
- Use weak references where appropriate

---

#### Issue: High CPU Usage

**Symptoms:**
- CPU utilization consistently high
- Agent unresponsive
- Slow processing times

**Diagnostics:**
```bash
# Check CPU usage
top -p $(pgrep a2a-agent)

# Profile CPU usage
perf record -p $(pgrep a2a-agent) -g -- sleep 30
perf report

# Check for CPU-intensive operations
strace -c -p $(pgrep a2a-agent)
```

**Solutions:**
1. Review agent processing logic for inefficiencies
2. Implement request throttling and rate limiting
3. Use asynchronous processing for heavy operations
4. Optimize JSON parsing and serialization
5. Review regular expression usage
6. Implement worker pools with limits
7. Use caching to reduce repeated computations
8. Consider horizontal scaling

---

### Integration Issues

#### Issue: SDK Version Mismatch

**Symptoms:**
- Incompatible operations
- Unexpected response formats
- Missing features

**Diagnostics:**
```bash
# Check SDK version
pip show a2a-sdk  # Python
npm list a2a-sdk  # Node.js

# Check server protocol version
curl -X POST ... method: "agent/getCard" ... | jq '.result.version'
```

**Solutions:**
1. Upgrade SDK to match protocol version
2. Check compatibility matrix in documentation
3. Use protocol version negotiation if available
4. Review migration guide for breaking changes
5. Test in staging environment before production upgrade

**Version Compatibility:**
- SDK 0.3.x → Protocol 0.3.x ✓
- SDK 0.2.x → Protocol 0.3.x (limited)
- SDK 0.1.x → Protocol 0.3.x ✗

---

#### Issue: Cross-Origin Resource Sharing (CORS) Errors

**Symptoms:**
- Browser-based clients cannot connect
- `Access-Control-Allow-Origin` errors
- Preflight request failures

**Diagnostics:**
```bash
# Test CORS with curl
curl -X OPTIONS https://your-agent.example.com/a2a \
  -H "Origin: https://your-app.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -v
```

**Solutions:**
1. Configure CORS headers on agent endpoint
2. Allow appropriate origins (avoid `*` in production)
3. Include required methods: POST, OPTIONS
4. Add necessary headers to Access-Control-Allow-Headers
5. Set credentials flag if using authentication

**CORS Configuration Example:**
```javascript
// Express.js
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', 'https://your-app.example.com');
  res.header('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.header('Access-Control-Allow-Credentials', 'true');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});
```

---

#### Issue: Webhook Delivery Failures

**Symptoms:**
- Webhook notifications not received
- Task updates not triggering callbacks
- Missed events

**Diagnostics:**
```bash
# Verify webhook endpoint is accessible
curl -X POST https://your-webhook.example.com/webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "event"}' \
  -v

# Check webhook configuration
curl -X POST ... method: "agent/getCard" ... | jq '.result.webhooks'

# Review webhook delivery logs
grep "webhook" /var/log/a2a-agent/webhook-delivery.log
```

**Solutions:**
1. Verify webhook URL is publicly accessible
2. Ensure webhook endpoint accepts POST requests
3. Check firewall rules allow outbound connections
4. Implement webhook signature verification
5. Return 200 OK promptly (< 5s)
6. Implement retry logic with exponential backoff
7. Use webhook delivery queue for reliability
8. Monitor webhook failure rates

**Webhook Implementation Checklist:**
- [ ] HTTPS endpoint (required)
- [ ] Verify request signatures
- [ ] Idempotent processing
- [ ] Return 200 within 5 seconds
- [ ] Handle retries gracefully
- [ ] Log all webhook deliveries

---

## Advanced Diagnostics

### Enable Debug Logging

```bash
# Set environment variable
export A2A_LOG_LEVEL=debug

# Restart agent service
systemctl restart a2a-agent

# Monitor logs
tail -f /var/log/a2a-agent/app.log
```

### Capture Network Traffic

```bash
# Use tcpdump to capture traffic
tcpdump -i any -w a2a-traffic.pcap 'port 443 and host your-agent.example.com'

# Analyze with Wireshark
wireshark a2a-traffic.pcap

# Or use curl with verbose output
curl -v -trace-ascii trace.txt ...
```

### Health Check Endpoints

Implement and monitor these health check endpoints:

```bash
# Liveness check (is service running?)
curl https://your-agent.example.com/health/live

# Readiness check (can handle traffic?)
curl https://your-agent.example.com/health/ready

# Metrics endpoint
curl https://your-agent.example.com/metrics
```

### Performance Profiling

```bash
# HTTP load testing
ab -n 1000 -c 10 -H "Authorization: Bearer TOKEN" \
  -p message.json -T application/json \
  https://your-agent.example.com/a2a

# Distributed tracing
# Check X-Trace-Id or X-Request-Id headers
curl -H "X-Trace-Id: 12345" ...

# Review trace in distributed tracing system (Jaeger, Zipkin, etc.)
```

### Database Diagnostics

```bash
# Check database connections
psql -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'a2a-agent';"

# Review slow queries
psql -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# Check table sizes
psql -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
```

## Enterprise Support Escalation

### When to Escalate

Escalate to enterprise support when:

1. **Critical Production Issues**
   - Service completely unavailable
   - Data loss or corruption
   - Security incident
   - Performance degradation affecting all users

2. **Complex Integration Issues**
   - Multi-agent communication failures
   - Protocol compliance questions
   - Custom implementation guidance needed

3. **Unresolved After Following Troubleshooting**
   - Issue persists after trying documented solutions
   - Root cause unclear
   - Requires code-level investigation

### Escalation Severity Levels

**Severity 1 (Critical) - Response Time: 1 hour**
- Complete service outage
- Data breach or security vulnerability
- Critical business functionality unavailable
- Impact: All users or business-critical functionality

**Severity 2 (High) - Response Time: 4 hours**
- Major functionality impaired
- Significant performance degradation
- Security concern (non-breach)
- Impact: Multiple users or important functionality

**Severity 3 (Medium) - Response Time: 1 business day**
- Minor functionality issues
- Workaround available
- Integration questions
- Impact: Limited users or non-critical functionality

**Severity 4 (Low) - Response Time: 3 business days**
- Feature requests
- Documentation questions
- General guidance
- Impact: Minimal or no production impact

### Information to Gather Before Escalating

Prepare the following information to expedite support:

#### Required Information

1. **Environment Details**
   ```bash
   # Gather system info
   cat > support-info.txt << EOF
   A2A Protocol Version: $(curl ... method: "agent/getCard" | jq -r '.result.version')
   SDK Version: $(pip show a2a-sdk | grep Version)
   Operating System: $(uname -a)
   Date/Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
   EOF
   ```

2. **Reproduction Steps**
   - Exact sequence of actions leading to issue
   - Timestamps when issue occurred
   - Frequency (one-time, intermittent, consistent)

3. **Request/Response Examples**
   ```bash
   # Capture full request/response
   curl -v -X POST https://your-agent.example.com/a2a \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer REDACTED" \
     -d '{"jsonrpc": "2.0", "method": "...", "id": 1}' \
     > request-response.log 2>&1
   ```

4. **Logs**
   ```bash
   # Collect relevant logs (last 1 hour)
   journalctl -u a2a-agent --since "1 hour ago" > agent-logs.txt

   # Sanitize sensitive information
   sed -i 's/Bearer [^"]*/Bearer REDACTED/g' agent-logs.txt
   ```

5. **Error Messages**
   - Full error message text
   - Error codes
   - Stack traces (if available)

6. **Impact Assessment**
   - Number of affected users
   - Business functions impacted
   - Estimated revenue/productivity loss
   - Workaround status

#### Optional but Helpful

- Network topology diagram
- Recent changes to configuration or code
- Performance metrics (CPU, memory, network)
- Database query logs
- Distributed tracing data

### How to Escalate

#### Enterprise Support Portal

1. Navigate to: `https://support.a2a-protocol.enterprise`
2. Log in with enterprise credentials
3. Click "Create New Case"
4. Select appropriate severity level
5. Attach gathered information
6. Submit and note case number

#### Email Escalation

For Severity 1 issues:
```
To: enterprise-support@a2a-protocol.org
Subject: [SEV1] Brief description of issue - Case: [case-number-if-exists]

Company: [Your Company Name]
Contact: [Your Name]
Phone: [24/7 Contact Number]
Environment: [Production/Staging]
Protocol Version: [Version]

Issue Summary:
[Brief description]

Impact:
[Business impact]

Reproduction:
[Steps to reproduce]

Attached:
- logs.zip
- request-response.log
- support-info.txt
```

#### Emergency Phone Escalation

**Available 24/7 for Severity 1 Issues Only**

- US/Americas: +1-800-XXX-XXXX
- EMEA: +44-20-XXXX-XXXX
- APAC: +65-XXXX-XXXX

Have ready:
- Case number (if already created)
- Your enterprise customer ID
- Brief description of issue
- Current impact

### Service Level Agreements (SLA)

**Response Times:**
- Severity 1: Initial response within 1 hour
- Severity 2: Initial response within 4 hours
- Severity 3: Initial response within 1 business day
- Severity 4: Initial response within 3 business days

**Resolution Times:**
- Severity 1: Best effort resolution within 24 hours
- Severity 2: Target resolution within 5 business days
- Severity 3: Target resolution within 10 business days
- Severity 4: Based on roadmap and priority

**Business Hours:**
- Standard Support: Monday-Friday, 9 AM - 5 PM local time
- Premium Support: 24/7/365 coverage

### Escalation Management

If your issue is not being addressed appropriately:

1. **First Level Escalation** - Request to speak with Support Team Lead
2. **Second Level Escalation** - Contact Customer Success Manager
3. **Executive Escalation** - Email: escalations@a2a-protocol.org

### Self-Service Resources

Before escalating, check these resources:

- **Documentation**: https://a2a-protocol.org/docs
- **API Reference**: https://a2a-protocol.org/specification
- **Community Forum**: https://community.a2a-protocol.org
- **Status Page**: https://status.a2a-protocol.org
- **Known Issues**: https://github.com/a2aproject/A2A/issues
- **Release Notes**: https://github.com/a2aproject/A2A/releases

### Post-Resolution

After issue resolution:

1. **Verify Fix** - Test in your environment
2. **Document Learnings** - Update internal runbooks
3. **Provide Feedback** - Complete satisfaction survey
4. **Request RCA** - For Severity 1/2 issues, request Root Cause Analysis document

## Additional Resources

### Monitoring and Observability

Implement comprehensive monitoring:

```yaml
# Key metrics to monitor
metrics:
  - name: request_latency_ms
    type: histogram
    alerts:
      - p95 > 5000 (warning)
      - p99 > 10000 (critical)

  - name: error_rate
    type: counter
    alerts:
      - rate > 5% (warning)
      - rate > 10% (critical)

  - name: active_tasks
    type: gauge
    alerts:
      - count > 1000 (warning)

  - name: task_completion_time
    type: histogram
    alerts:
      - p95 > 300000 (5 minutes)
```

### Testing Tools

```bash
# Protocol compliance tester
a2a-test-suite --endpoint https://your-agent.example.com/a2a

# Load testing
a2a-load-test --duration 60s --rps 100 --endpoint https://your-agent.example.com/a2a

# Integration testing
pytest tests/integration/test_a2a_protocol.py -v
```

### Security Best Practices

1. **Authentication**
   - Use OAuth 2.0 or JWT tokens
   - Implement token rotation
   - Use short-lived access tokens

2. **Authorization**
   - Implement proper RBAC
   - Validate all permissions server-side
   - Use principle of least privilege

3. **Transport Security**
   - TLS 1.2 or higher required
   - Validate certificates
   - Use strong cipher suites

4. **Input Validation**
   - Validate all inputs against schema
   - Sanitize user content
   - Implement rate limiting

5. **Audit Logging**
   - Log all authentication attempts
   - Log all authorization decisions
   - Log all task operations

### Compliance Considerations

For regulated industries:

- **Data Residency**: Ensure agent and data storage comply with regional requirements
- **Encryption**: Use encryption at rest and in transit
- **Retention**: Implement appropriate data retention policies
- **Audit Trails**: Maintain comprehensive audit logs
- **Privacy**: Implement data anonymization/pseudonymization as required

---

**Last Updated**: 2026-02-06
**Document Version**: 1.0
**Protocol Version**: 0.3.0+

For the latest version of this document, visit: https://a2a-protocol.org/troubleshooting
