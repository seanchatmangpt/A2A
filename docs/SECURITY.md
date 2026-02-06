# Security Architecture and Controls

## Table of Contents

1. [Security Architecture](#security-architecture)
2. [Security Controls](#security-controls)
3. [Compliance and Certifications](#compliance-and-certifications)
4. [Vulnerability Management](#vulnerability-management)
5. [Incident Response](#incident-response)
6. [Security Best Practices](#security-best-practices)

## Security Architecture

### Overview

The Agent2Agent (A2A) Protocol is designed with security as a foundational principle, enabling secure communication between independent AI agent systems across organizational boundaries. The security architecture follows defense-in-depth principles, leveraging industry-standard protocols and practices to ensure confidentiality, integrity, and availability.

### Security Design Principles

#### 1. Zero Trust Architecture

A2A operates on a zero-trust model where:

- **No Implicit Trust**: Every agent interaction requires explicit authentication and authorization
- **Least Privilege**: Agents receive minimum necessary permissions for their operations
- **Verify Always**: All requests are authenticated and validated regardless of source
- **Opaque Execution**: Agents collaborate without exposing internal state, memory, or proprietary tools

#### 2. Secure by Default

- **HTTPS Required**: All production deployments MUST use HTTPS/TLS for transport encryption
- **Authentication Mandatory**: No anonymous agent interactions in production environments
- **Input Validation**: All messages and data structures validated against protocol schemas
- **Sanitized Outputs**: All agent responses sanitized to prevent injection attacks

#### 3. Defense in Depth

Multiple security layers protect the protocol:

```
┌─────────────────────────────────────────────────┐
│          Application Layer Security             │
│  (Input Validation, Output Encoding, RBAC)      │
├─────────────────────────────────────────────────┤
│         Protocol Layer Security                 │
│  (JSON-RPC/gRPC Authentication, Authorization)  │
├─────────────────────────────────────────────────┤
│         Transport Layer Security                │
│         (TLS 1.3, Certificate Validation)       │
├─────────────────────────────────────────────────┤
│         Network Layer Security                  │
│    (Firewalls, Network Segmentation, DDoS)      │
└─────────────────────────────────────────────────┘
```

### Architecture Components

#### Transport Security

**TLS/HTTPS Requirements:**

- TLS 1.3 RECOMMENDED, TLS 1.2 minimum
- Strong cipher suites only (ECDHE, AES-GCM)
- Certificate validation REQUIRED for all connections
- Certificate pinning RECOMMENDED for high-security deployments
- Perfect Forward Secrecy (PFS) REQUIRED

**Supported Bindings:**

- **JSON-RPC over HTTPS**: OAuth 2.0, API Keys, mTLS
- **gRPC with TLS**: Token-based auth, mTLS
- **HTTP/REST**: Bearer tokens, OAuth 2.0, API Keys

#### Authentication Mechanisms

The A2A protocol supports multiple authentication methods to accommodate diverse deployment scenarios:

1. **OAuth 2.0 / OpenID Connect**
   - RECOMMENDED for enterprise deployments
   - Supports delegated authorization
   - Token-based stateless authentication
   - Refresh token rotation supported

2. **API Keys**
   - Simple integration for trusted environments
   - MUST be rotated regularly (90 days maximum)
   - MUST be transmitted only over HTTPS
   - Rate limiting per key RECOMMENDED

3. **Mutual TLS (mTLS)**
   - RECOMMENDED for high-security agent-to-agent communication
   - Certificate-based authentication
   - Automatic client verification
   - Strong cryptographic identity

4. **Custom Authentication Extensions**
   - Protocol allows custom auth schemes via Agent Cards
   - MUST follow security best practices
   - Should document security properties

#### Authorization Model

**Role-Based Access Control (RBAC):**

- **Agent Roles**: Publisher, Consumer, Administrator
- **Capability-Based**: Fine-grained permissions per skill/operation
- **Task-Level Permissions**: Control over task creation, modification, cancellation
- **Context Isolation**: Tasks and contexts isolated between principals

**Permission Levels:**

| Role | Send Message | Stream | Get Task | Cancel Task | Admin Operations |
|------|--------------|--------|----------|-------------|------------------|
| Consumer | ✓ | ✓ | Own tasks only | Own tasks only | ✗ |
| Publisher | ✓ | ✓ | All tasks | All tasks | ✗ |
| Administrator | ✓ | ✓ | All tasks | All tasks | ✓ |

### Data Security

#### Data in Transit

- All agent communication MUST use TLS encryption
- No sensitive data in URLs or query parameters
- Message payloads encrypted at transport layer
- Push notifications MUST use HTTPS webhooks

#### Data at Rest

Implementation-specific but RECOMMENDED:

- Encryption of task state and message history
- Encryption of artifacts and file attachments
- Secure key management (HSM, KMS)
- Data retention policies with automatic purging

#### Data Privacy

- **Minimal Data Sharing**: Agents share only necessary information
- **No Memory Leakage**: Internal agent state never exposed
- **Context Boundaries**: Strict isolation between contexts
- **PII Handling**: Implementations SHOULD follow GDPR, CCPA requirements
- **Right to Deletion**: Support for data deletion requests

### Network Security

#### Endpoint Hardening

- **Rate Limiting**: Prevent abuse and DoS attacks
- **Request Size Limits**: Protect against oversized payloads
- **Timeout Controls**: Prevent resource exhaustion
- **Connection Limits**: Per-client connection restrictions

#### DDoS Protection

RECOMMENDED deployment practices:

- CDN/edge protection (Cloudflare, Akamai)
- Web Application Firewall (WAF)
- Rate limiting at multiple layers
- Anomaly detection and blocking

#### Network Segmentation

- Isolate A2A servers in dedicated security zones
- Restrict egress to required services only
- Webhook destinations validated against allowlists
- Internal agent networks separated from public endpoints

## Security Controls

### Authentication Controls

#### 1. Token Management

**OAuth 2.0 Token Lifecycle:**

```
Token Issuance → Active Use → Refresh → Expiration → Revocation
     ↓              ↓           ↓          ↓            ↓
  Validate     Rate Limit   Rotation   Archive    Audit Log
```

**Token Security:**

- Access tokens: 1-hour expiration RECOMMENDED
- Refresh tokens: 90-day maximum, rotation on use
- Secure storage: Never log tokens in plaintext
- Transmission: HTTPS only, never in URLs

#### 2. API Key Management

- Generation: Cryptographically random, minimum 256 bits
- Storage: Hashed with salt (bcrypt, Argon2)
- Rotation: Mandatory 90-day cycle
- Revocation: Immediate effect, logged and audited
- Scoping: Limit keys to specific agent operations

#### 3. Certificate Management (mTLS)

- Certificate Authority: Internal CA or trusted public CA
- Validity: 1-year maximum for client certificates
- Revocation: CRL or OCSP support REQUIRED
- Key strength: RSA 2048-bit minimum, ECDSA P-256 RECOMMENDED
- Storage: Hardware security modules (HSM) for production

### Authorization Controls

#### 1. Skill-Based Access Control

Agents declare skills in Agent Cards, clients verify:

```json
{
  "skills": [
    {
      "name": "document_analysis",
      "required_permissions": ["read_documents", "analyze"],
      "allowed_roles": ["consumer", "publisher"]
    }
  ]
}
```

#### 2. Task Lifecycle Controls

- **Creation**: Authenticated clients only
- **Access**: Task ID as capability, or RBAC enforcement
- **Modification**: Only task owner or administrator
- **Cancellation**: Task owner, agent, or administrator
- **Deletion**: Requires explicit permission, audited

#### 3. Context Isolation

- Contexts partition task/message spaces
- No cross-context data access
- Context-specific authentication possible
- Audit logs maintain context attribution

### Input Validation Controls

#### 1. Protocol Validation

All implementations MUST validate:

- JSON-RPC structure conformance
- Message schema compliance (per a2a.proto)
- Field type and range validation
- Required field presence

#### 2. Content Validation

- **Part Types**: Verify MIME types against allowlist
- **File References**: Validate URLs, check for SSRF
- **Text Content**: Length limits, encoding validation
- **Structured Data**: Schema validation for forms/JSON

#### 3. Injection Prevention

- **SQL Injection**: Use parameterized queries
- **Command Injection**: Never execute unsanitized input
- **XSS Prevention**: Sanitize all agent responses in UIs
- **Path Traversal**: Validate and sanitize file paths
- **SSRF Prevention**: Allowlist webhook/file URLs

### Output Controls

#### 1. Response Sanitization

- Remove internal error details in production
- Sanitize stack traces and debug information
- Filter sensitive environment variables
- Rate-limit error responses to prevent enumeration

#### 2. Data Leakage Prevention

- No exposure of internal agent state
- Tool implementations remain opaque
- Memory/context never included in responses
- Redact sensitive data in logs and artifacts

### Audit and Logging Controls

#### 1. Security Event Logging

MUST log the following security events:

- Authentication attempts (success/failure)
- Authorization decisions (allow/deny)
- Task creation, modification, cancellation
- Agent Card accesses
- Administrative operations
- Security errors and exceptions

#### 2. Log Format

Structured logging RECOMMENDED (JSON):

```json
{
  "timestamp": "2026-02-06T12:00:00Z",
  "event_type": "authentication",
  "result": "success",
  "principal": "agent-client-123",
  "source_ip": "192.168.1.100",
  "operation": "send_message",
  "task_id": "task-abc-123",
  "agent_id": "agent-xyz"
}
```

#### 3. Log Security

- Logs MUST NOT contain tokens, passwords, or keys
- Centralized log collection RECOMMENDED
- Log integrity protection (WORM storage, signing)
- Retention: 90 days minimum for security logs
- Access controls: Read-only for analysts, admin for security team

#### 4. Audit Trail

Immutable audit trail for:

- All administrative changes
- Permission modifications
- Agent Card updates
- Security configuration changes
- Incident response actions

### Monitoring and Alerting

#### 1. Security Monitoring

- Failed authentication rate thresholds
- Unusual task creation patterns
- Authorization denial spikes
- Anomalous message sizes or frequencies
- Webhook destination changes

#### 2. Alerting Thresholds

| Event | Threshold | Severity |
|-------|-----------|----------|
| Failed auth attempts | 5/minute from single IP | Medium |
| Failed auth attempts | 20/minute across all IPs | High |
| Authorization denials | 10/minute per principal | Medium |
| Large message payloads | >10MB | Low |
| Unusual webhook URLs | New domain | Medium |
| Multiple task cancellations | >50/hour | Medium |

## Compliance and Certifications

### Current Status

The A2A Protocol is an open standard designed to facilitate compliance with industry regulations. Individual implementations may pursue certifications based on their deployment contexts.

### Applicable Standards and Frameworks

#### 1. OWASP Top 10 Compliance

The protocol design addresses OWASP Top 10 vulnerabilities:

- **A01 Broken Access Control**: RBAC, task-level permissions
- **A02 Cryptographic Failures**: TLS 1.3, strong ciphers
- **A03 Injection**: Input validation, parameterized queries
- **A04 Insecure Design**: Threat modeling, security reviews
- **A05 Security Misconfiguration**: Secure defaults, hardening guides
- **A06 Vulnerable Components**: Dependency scanning, updates
- **A07 Auth Failures**: Strong auth mechanisms, MFA support
- **A08 Data Integrity**: Message signing, integrity checks
- **A09 Logging Failures**: Comprehensive audit logging
- **A10 SSRF**: URL validation, allowlisting

#### 2. SOC 2 Type II

For commercial implementations, SOC 2 Type II alignment:

- **Security**: Access controls, encryption, monitoring
- **Availability**: Uptime SLAs, redundancy, disaster recovery
- **Confidentiality**: Data classification, need-to-know access
- **Processing Integrity**: Input validation, error handling
- **Privacy**: PII handling, consent management, data retention

#### 3. GDPR Compliance

Protocol features supporting GDPR:

- **Right to Access**: Task and message retrieval APIs
- **Right to Erasure**: Task deletion, data purging
- **Data Minimization**: Agent cards declare only necessary data
- **Purpose Limitation**: Skill-based scoping
- **Data Portability**: Standard JSON format for export
- **Consent Management**: Extension points for consent tracking

#### 4. HIPAA (Healthcare Deployments)

For healthcare use cases:

- **Encryption**: PHI encrypted in transit and at rest
- **Access Controls**: RBAC with audit trails
- **Integrity Controls**: Message validation, checksums
- **Audit Controls**: Comprehensive logging of PHI access
- **Business Associate Agreements**: Required for third-party agents

#### 5. ISO 27001

Information Security Management alignment:

- **Risk Assessment**: Threat modeling for agent interactions
- **Access Control**: Multi-factor authentication, RBAC
- **Cryptography**: Key management, algorithm selection
- **Operations Security**: Secure deployment, configuration management
- **Incident Management**: Detection, response, recovery

### Certification Roadmap

Planned certifications for reference implementations:

- **Q2 2026**: SOC 2 Type I (Security, Availability)
- **Q4 2026**: SOC 2 Type II
- **Q1 2027**: ISO 27001 certification
- **Q2 2027**: FedRAMP Moderate (for government deployments)

### Compliance Documentation

SDK providers and implementers SHOULD provide:

- Security architecture documentation
- Data flow diagrams
- Threat models and mitigations
- Penetration test results
- Security assessment reports
- Compliance mapping documents

## Vulnerability Management

### Vulnerability Disclosure Policy

#### Reporting Security Issues

**DO NOT** open public GitHub issues for security vulnerabilities.

**Email**: security@lists.a2aproject.org

Include in your report:

- Description of the vulnerability
- Steps to reproduce
- Affected versions/components
- Potential impact assessment
- Proof-of-concept code (if applicable)
- Suggested remediation (optional)

#### Response Timeline

| Phase | Timeline | Activity |
|-------|----------|----------|
| Acknowledgment | 24 hours | Confirm receipt of report |
| Initial Assessment | 72 hours | Severity classification, impact analysis |
| Remediation Planning | 7 days | Develop fix, test, security advisory |
| Patch Release | 30 days | Release patched versions (critical: 7 days) |
| Public Disclosure | 90 days | Publish CVE and security advisory |

#### Severity Classification

Based on CVSS v3.1:

- **Critical (9.0-10.0)**: Remote code execution, authentication bypass
- **High (7.0-8.9)**: Privilege escalation, sensitive data exposure
- **Medium (4.0-6.9)**: XSS, CSRF, information disclosure
- **Low (0.1-3.9)**: Minor information leaks, configuration issues

### Vulnerability Management Process

#### 1. Detection

Multiple detection mechanisms:

- **Security Researchers**: Responsible disclosure program
- **Automated Scanning**: Dependency checks, SAST, DAST
- **Bug Bounty**: Community-driven vulnerability discovery
- **Internal Audits**: Regular security assessments
- **Penetration Testing**: Annual third-party assessments

#### 2. Triage

Security team evaluates:

- Vulnerability authenticity
- Affected components and versions
- Exploitability assessment
- Impact and risk scoring
- Prioritization for remediation

#### 3. Remediation

Fix development process:

```
Vulnerability Report → Triage → Fix Development → Testing → Review
                                                             ↓
Public Disclosure ← Monitoring ← Release ← Security Advisory
```

**Code Review Requirements:**

- All security fixes require two-person review
- Security team approval mandatory for critical/high severity
- Regression test suite updated
- Changelog and advisory documentation

#### 4. Disclosure

**Private Disclosure (Days 0-90):**

- Notify affected SDK maintainers
- Provide early access to patches
- Coordinate release timing
- Prepare security advisory

**Public Disclosure:**

- Publish CVE in NVD (National Vulnerability Database)
- Release security advisory with:
  - Vulnerability description
  - Affected versions
  - Remediation steps
  - Workarounds (if applicable)
  - Credit to reporter
- Notify users via GitHub Security Advisory
- Post to security mailing list

### Dependency Management

#### 1. Dependency Scanning

Continuous monitoring of dependencies:

- **Tools**: Dependabot, Snyk, OWASP Dependency-Check
- **Frequency**: Daily automated scans
- **Scope**: All SDKs (Python, Go, JS, Java, .NET)
- **Response**: High/Critical vulnerabilities patched within 7 days

#### 2. Supply Chain Security

- **Provenance**: Verify package signatures and checksums
- **Vendoring**: Pin dependencies to specific versions
- **SBOM**: Generate Software Bill of Materials for releases
- **Minimal Dependencies**: Reduce attack surface by limiting deps

#### 3. Update Policy

- Security patches: Immediate integration
- Minor updates: Monthly review and integration
- Major updates: Quarterly review, compatibility testing
- End-of-life dependencies: Replace within 30 days

### Security Testing

#### 1. Static Application Security Testing (SAST)

- **Tools**: SonarQube, Semgrep, CodeQL
- **Integration**: CI/CD pipeline (pre-merge)
- **Frequency**: Every commit
- **Coverage**: All SDK repositories, specification

#### 2. Dynamic Application Security Testing (DAST)

- **Tools**: OWASP ZAP, Burp Suite
- **Scope**: Reference implementations, sample applications
- **Frequency**: Weekly automated scans
- **Targets**: Authentication, authorization, injection vulnerabilities

#### 3. Penetration Testing

- **Frequency**: Annual comprehensive assessment
- **Scope**: Full protocol stack, all bindings
- **Methodology**: OWASP Testing Guide, PTES
- **Deliverables**: Executive summary, detailed findings, remediation plan

#### 4. Fuzzing

- **Targets**: Protocol parsers, message handlers
- **Tools**: AFL++, libFuzzer, Jazzer
- **Continuous**: Integrated into CI/CD
- **Coverage**: JSON-RPC, gRPC, message validation

### Patch Management

#### 1. Release Process

Security patches follow accelerated release:

- **Critical**: Emergency release within 24-72 hours
- **High**: Hotfix release within 7 days
- **Medium**: Regular release cycle (monthly)
- **Low**: Next scheduled release

#### 2. Version Support

- **Current major version**: Full support
- **Previous major version**: Security patches for 12 months
- **Older versions**: End-of-life, no support

#### 3. Backward Compatibility

- Security fixes prioritized over backward compatibility
- Breaking changes documented in security advisory
- Migration guides provided for impactful changes

## Incident Response

### Incident Response Team

#### Roles and Responsibilities

- **Incident Commander**: Overall coordination, decisions, communications
- **Security Lead**: Technical analysis, remediation strategy
- **Communications Lead**: Internal/external stakeholder updates
- **Engineering Lead**: Patch development, deployment coordination
- **Legal/Compliance**: Regulatory notifications, legal review

### Incident Classification

#### Severity Levels

**P0 - Critical:**

- Active exploitation of vulnerability
- Data breach or unauthorized access
- Complete service outage
- Widespread security compromise

**P1 - High:**

- Confirmed vulnerability with high risk
- Attempted unauthorized access
- Significant service degradation
- Security control failure

**P2 - Medium:**

- Suspicious activity requiring investigation
- Minor security policy violations
- Isolated service issues
- Potential vulnerability

**P3 - Low:**

- General security questions
- Minor configuration issues
- Non-security-impacting anomalies

### Incident Response Process

#### 1. Detection and Identification

**Detection Sources:**

- Security monitoring alerts
- User reports
- Vulnerability disclosures
- Automated scanners
- Third-party notifications

**Initial Assessment:**

- Confirm incident authenticity
- Classify severity level
- Identify affected systems/users
- Estimate impact and scope
- Activate incident response team

#### 2. Containment

**Short-term Containment:**

- Isolate affected systems
- Block malicious IP addresses
- Disable compromised credentials
- Apply temporary mitigations
- Preserve evidence for investigation

**Long-term Containment:**

- Deploy security patches
- Implement enhanced monitoring
- Strengthen access controls
- Update security rules/policies

#### 3. Eradication

- Remove malicious code or unauthorized access
- Close exploited vulnerabilities
- Restore systems from clean backups
- Reset compromised credentials
- Update security configurations

#### 4. Recovery

**Restoration:**

- Restore services from containment
- Validate system integrity
- Monitor for recurring issues
- Gradually restore access
- Performance and security validation

**Verification:**

- Confirm vulnerability remediated
- Test security controls
- Review logs for residual activity
- Document restoration steps

#### 5. Post-Incident Activities

**Lessons Learned:**

- Conduct blameless postmortem within 7 days
- Document timeline of events
- Identify root causes
- Review detection and response effectiveness
- Develop improvement action items

**Remediation Tracking:**

- Create tickets for improvements
- Assign owners and deadlines
- Update runbooks and procedures
- Enhance monitoring and detection
- Update incident response plan

### Communication Plan

#### Internal Communications

**Immediate (P0/P1):**

- Notify incident response team
- Alert engineering leadership
- Inform product security team
- Brief executive stakeholders

**Regular Updates:**

- P0: Every 2 hours during active incident
- P1: Every 4 hours or major status change
- P2/P3: Daily updates

#### External Communications

**User Notifications:**

Required for:

- Data breaches or unauthorized access
- Widespread service outages
- Security vulnerabilities requiring user action
- Regulatory compliance obligations

**Notification Timeline:**

- Initial notification: Within 72 hours of confirmation
- Regular updates: As investigation progresses
- Final notification: Post-resolution with lessons learned

**Notification Channels:**

- GitHub Security Advisory
- Security mailing list (security-announce@lists.a2aproject.org)
- Website security bulletin
- Direct email to affected users (if identifiable)

**Regulatory Notifications:**

- GDPR: 72 hours for data breaches affecting EU citizens
- HIPAA: 60 days for healthcare data breaches
- Other: Per applicable regulations

### Incident Playbooks

#### Playbook: Unauthorized Access

**Scenario**: Unauthorized access to agent systems or data

**Response Steps:**

1. Identify compromised accounts/systems
2. Disable compromised credentials immediately
3. Review access logs for scope of breach
4. Isolate affected systems from network
5. Collect forensic evidence
6. Assess data exposure
7. Notify affected users if PII/PHI exposed
8. Reset all credentials for affected systems
9. Restore from clean backups if necessary
10. Implement additional access controls

#### Playbook: DDoS Attack

**Scenario**: Distributed denial of service targeting A2A endpoints

**Response Steps:**

1. Confirm DDoS pattern (traffic analysis)
2. Activate DDoS mitigation (CDN, WAF)
3. Implement rate limiting and blocking rules
4. Scale infrastructure if needed
5. Monitor service health and user impact
6. Coordinate with hosting provider/CDN
7. Document attack characteristics
8. Review and strengthen DDoS defenses
9. Post-incident capacity planning

#### Playbook: Vulnerability Exploitation

**Scenario**: Active exploitation of disclosed vulnerability

**Response Steps:**

1. Confirm exploitation and assess scope
2. Deploy emergency patch or mitigation
3. Block attack vectors (WAF rules, firewall)
4. Identify and contain compromised systems
5. Scan all systems for indicators of compromise
6. Notify users of required updates
7. Monitor for continued exploitation attempts
8. Accelerate patch deployment timeline
9. Post-exploitation forensics and hardening

#### Playbook: Data Breach

**Scenario**: Unauthorized disclosure of sensitive data

**Response Steps:**

1. Confirm breach and identify data types
2. Contain source of breach
3. Assess number of affected individuals
4. Preserve evidence for investigation
5. Begin regulatory notification process (72-hour GDPR window)
6. Notify affected users
7. Offer remediation (credit monitoring, etc.)
8. Conduct forensic investigation
9. Implement preventive controls
10. Document for compliance and legal review

### Recovery and Business Continuity

#### Disaster Recovery Plan

**Recovery Time Objective (RTO):** 4 hours for critical services
**Recovery Point Objective (RPO):** 1 hour for data

**Backup Strategy:**

- Automated daily backups of all critical systems
- Geographically distributed backup storage
- Encrypted backups with key escrow
- Monthly backup restoration testing
- 90-day backup retention

**Failover Procedures:**

- Active-passive configuration for critical services
- Automated health checks and failover triggers
- DNS-based traffic redirection
- Database replication and failover
- Documented manual failover procedures

#### Business Continuity

**Essential Functions:**

1. Agent communication (SendMessage operations)
2. Authentication and authorization services
3. Agent Card distribution
4. Security incident response capabilities

**Alternate Operations:**

- Backup data centers in different regions
- Cloud-based infrastructure redundancy
- Key personnel backup coverage
- Communication channels (email, Slack, PagerDuty)
- Vendor relationships for emergency support

## Security Best Practices

### For A2A Server Implementers

#### 1. Deployment Hardening

- Enable TLS 1.3 with strong cipher suites
- Implement mTLS for agent-to-agent communication
- Use OAuth 2.0 with short-lived tokens
- Deploy behind WAF and DDoS protection
- Enable rate limiting per client
- Implement request size limits (10MB default)
- Configure timeout values appropriately
- Use network segmentation and firewalls

#### 2. Authentication Best Practices

- Require authentication for all production endpoints
- Support multiple auth methods (OAuth, mTLS, API keys)
- Implement token rotation and expiration
- Use secure token storage (never log tokens)
- Enable multi-factor authentication where possible
- Monitor for authentication anomalies

#### 3. Authorization Implementation

- Implement least-privilege access controls
- Use task-level permissions
- Validate authorization on every request
- Isolate contexts and users
- Audit all authorization decisions
- Regularly review and update permissions

#### 4. Input Validation

- Validate all inputs against protocol schema
- Implement allowlists for file types and URLs
- Sanitize all user-provided content
- Check message size limits
- Validate webhook URLs before use
- Prevent SSRF in file/webhook handling

#### 5. Monitoring and Logging

- Log all security-relevant events
- Implement centralized log collection
- Set up alerts for anomalies
- Monitor failed authentication attempts
- Track unusual task patterns
- Review logs regularly for security issues

### For A2A Client Developers

#### 1. Secure Agent Card Handling

- Verify Agent Card signatures if available
- Validate TLS certificates when fetching cards
- Cache cards with appropriate TTL
- Re-fetch cards on authentication failures
- Validate required auth mechanisms

#### 2. Credential Management

- Store credentials securely (keyring, vault)
- Never hardcode credentials in code
- Use environment variables or secure config
- Rotate credentials regularly
- Implement credential revocation handling

#### 3. Webhook Security

- Use HTTPS for all webhook endpoints
- Validate webhook payloads with signatures
- Implement webhook authentication
- Rate-limit webhook handlers
- Validate webhook sources against allowlist

#### 4. Error Handling

- Never expose sensitive data in errors
- Implement proper timeout handling
- Retry with exponential backoff
- Log errors securely (redact sensitive data)
- Handle edge cases gracefully

### For SDK Maintainers

#### 1. Secure Development Lifecycle

- Perform security code reviews
- Run SAST tools in CI/CD
- Scan dependencies for vulnerabilities
- Publish security advisories
- Maintain security changelog
- Provide security documentation

#### 2. Cryptographic Standards

- Use well-established crypto libraries
- Follow NIST/industry standards
- Implement secure random number generation
- Support modern TLS versions
- Provide examples of secure configurations

#### 3. Dependency Management

- Minimize dependencies
- Pin dependency versions
- Scan for vulnerabilities regularly
- Update promptly for security patches
- Publish SBOM with releases

### For Enterprise Deployments

#### 1. Network Architecture

- Deploy in private VPC/network segments
- Use internal service mesh for agent-to-agent
- Implement egress filtering
- Deploy API gateway for external access
- Use load balancers with health checks
- Enable DDoS protection services

#### 2. Identity and Access Management

- Integrate with enterprise SSO (SAML, OIDC)
- Implement role-based access control
- Use service accounts for agents
- Enable audit logging for compliance
- Implement privileged access management
- Regular access reviews and recertification

#### 3. Data Protection

- Classify data according to sensitivity
- Encrypt data at rest and in transit
- Implement data loss prevention (DLP)
- Use tokenization for sensitive data
- Implement data retention policies
- Support right-to-erasure requests

#### 4. Compliance and Governance

- Document security architecture
- Maintain compliance artifacts
- Conduct regular security assessments
- Perform vendor risk assessments
- Implement change management
- Maintain security policies and procedures

#### 5. Incident Preparedness

- Develop incident response plans
- Conduct tabletop exercises
- Train incident response team
- Establish communication protocols
- Maintain vendor contact lists
- Test disaster recovery procedures

---

## Additional Resources

- **Protocol Specification**: [A2A Protocol Specification](https://a2a-protocol.org/latest/specification/)
- **Security Policy**: [SECURITY.md](../SECURITY.md)
- **Contributing**: [CONTRIBUTING.md](../CONTRIBUTING.md)
- **Community**: [GitHub Discussions](https://github.com/a2aproject/A2A/discussions)
- **Security Contact**: security@lists.a2aproject.org

## Document Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-06 | Initial security architecture documentation |

---

**Last Updated**: 2026-02-06
**Document Owner**: A2A Security Team
**Review Cycle**: Quarterly
