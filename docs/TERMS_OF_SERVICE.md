# TERMS OF SERVICE

**Effective Date:** February 6, 2026
**Last Updated:** February 6, 2026

## 1. ENTERPRISE LICENSE AGREEMENT

These Terms of Service ("Agreement") constitute a binding legal agreement between the customer organization ("Customer," "you," or "your") and A2A Platform Provider ("Provider," "we," "us," or "our") governing access to and use of the A2A Platform and related services ("Services").

## 2. DEFINITIONS

**"Service Level Agreement" or "SLA"** means the performance and availability commitments set forth in Section 4.

**"Support Services"** means technical support and maintenance services as defined in Section 5.

**"Covered Claims"** means third-party claims as specified in Section 8.

**"Confidential Information"** means proprietary business, technical, financial, and customer information.

**"Production Environment"** means Customer's live operational deployment of the Services.

**"Business Day"** means any day other than Saturday, Sunday, or a US federal holiday.

## 3. SERVICE DESCRIPTION

The A2A Platform provides enterprise-grade workflow automation, agent orchestration, and integration services with guaranteed uptime, security, and compliance standards suitable for Fortune 5 organizations.

## 4. SERVICE LEVEL AGREEMENT (SLA)

### 4.1 Availability Commitment

Provider commits to the following uptime levels measured monthly:

| Tier | Uptime Commitment | Maximum Downtime/Month |
|------|-------------------|------------------------|
| Platinum | 99.99% | 4.38 minutes |
| Gold | 99.95% | 21.9 minutes |
| Standard | 99.9% | 43.8 minutes |

**Uptime Calculation:** Measured as percentage of time Services are available and operational during each calendar month, excluding Scheduled Maintenance and Excused Downtime.

### 4.2 Performance Metrics

- **API Response Time:** 95th percentile < 200ms for standard operations
- **Throughput:** Minimum 10,000 transactions per second per instance
- **Data Processing Latency:** < 1 second for 99% of workflow executions
- **Recovery Time Objective (RTO):** < 4 hours for critical failures
- **Recovery Point Objective (RPO):** < 15 minutes of data loss

### 4.3 Scheduled Maintenance

- Provider may perform Scheduled Maintenance during designated maintenance windows
- Advance notice of 7 days for planned maintenance
- Maintenance windows limited to 4 hours per month maximum
- Scheduled Maintenance excluded from uptime calculations

### 4.4 Service Credits

If Provider fails to meet SLA commitments, Customer is entitled to Service Credits:

| Uptime Achieved | Service Credit |
|-----------------|----------------|
| < 99.99% to 99.9% | 10% of monthly fees |
| < 99.9% to 99.0% | 25% of monthly fees |
| < 99.0% to 95.0% | 50% of monthly fees |
| < 95.0% | 100% of monthly fees |

**Credit Claim Process:**
- Customer must submit credit requests within 30 days of incident
- Credits applied to subsequent monthly invoices
- Credits are Customer's sole remedy for SLA breaches

### 4.5 Excused Downtime

SLA commitments do not apply to downtime caused by:
- Customer's applications, equipment, or network connectivity
- Force majeure events
- Third-party services or infrastructure failures beyond Provider's control
- Customer-requested changes or configurations
- Denial of service attacks or security incidents not caused by Provider's negligence

## 5. SUPPORT COMMITMENTS

### 5.1 Support Tiers

#### Platinum Support (24x7x365)
- **Response Time - Critical (P1):** 15 minutes
- **Response Time - High (P2):** 2 hours
- **Response Time - Medium (P3):** 8 Business Hours
- **Response Time - Low (P4):** 24 Business Hours
- **Dedicated Technical Account Manager (TAM)**
- **Quarterly Business Reviews**
- **Architecture Review and Optimization**
- **24x7 phone, email, and portal support**
- **Direct escalation to engineering**

#### Gold Support (24x7)
- **Response Time - Critical (P1):** 1 hour
- **Response Time - High (P2):** 4 hours
- **Response Time - Medium (P3):** 12 Business Hours
- **Response Time - Low (P4):** 48 Business Hours
- **Named Support Engineer**
- **Semi-annual Business Reviews**
- **24x7 email and portal support**

#### Standard Support (Business Hours)
- **Response Time - Critical (P1):** 4 Business Hours
- **Response Time - High (P2):** 8 Business Hours
- **Response Time - Medium (P3):** 24 Business Hours
- **Response Time - Low (P4):** 72 Business Hours
- **Portal and email support during Business Hours**

### 5.2 Severity Definitions

**P1 - Critical:** Production system down or severely degraded affecting business operations

**P2 - High:** Major functionality impaired, no workaround available

**P3 - Medium:** Moderate functionality issue with workaround available

**P4 - Low:** Minor issue, question, or feature request

### 5.3 Support Services Include

- Troubleshooting and technical guidance
- Bug fixes and security patches
- Version upgrade assistance
- Performance optimization recommendations
- Documentation and knowledge base access
- Training materials and webinars

### 5.4 Professional Services

Available as add-ons:
- Implementation and integration services
- Custom development and workflow design
- Data migration assistance
- Advanced training and certification
- Dedicated on-site support

## 6. WARRANTIES

### 6.1 Service Warranty

Provider warrants that:

a) **Performance:** Services will perform materially in accordance with documented specifications

b) **Compliance:** Services comply with applicable laws and industry standards

c) **No Malicious Code:** Services are free from viruses, malware, and malicious code

d) **Professional Standards:** Services rendered using qualified personnel exercising professional skill and care

e) **Authority:** Provider has full right and authority to enter this Agreement and provide Services

### 6.2 Security Warranty

Provider warrants implementation and maintenance of:

- Industry-standard security controls and practices
- Encryption for data in transit (TLS 1.3+) and at rest (AES-256)
- Regular security assessments and penetration testing
- Incident response procedures
- Access controls and authentication mechanisms
- Security monitoring and logging

### 6.3 Data Protection Warranty

Provider warrants:

- Compliance with applicable data protection laws (GDPR, CCPA, etc.)
- Implementation of appropriate technical and organizational measures
- Data processing only according to Customer instructions
- Notification of data breaches within 24 hours of discovery
- Assistance with data subject access requests

### 6.4 Warranty Remedies

If Services breach warranties:
- Provider will re-perform Services at no additional cost
- If breach not cured within 30 days, Customer may terminate and receive refund of prepaid fees for unused Services

### 6.5 Warranty Disclaimers

EXCEPT AS EXPRESSLY PROVIDED IN THIS SECTION 6, SERVICES ARE PROVIDED "AS IS." PROVIDER DISCLAIMS ALL OTHER WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR PARTICULAR PURPOSE, AND NON-INFRINGEMENT TO THE MAXIMUM EXTENT PERMITTED BY LAW.

## 7. LIABILITY

### 7.1 Limitation of Liability

**Cap on Liability:** Provider's total cumulative liability for all claims arising from or related to this Agreement shall not exceed the greater of:
- (a) Fees paid by Customer in the 12 months preceding the claim, or
- (b) $10,000,000 USD

### 7.2 Exclusion of Consequential Damages

EXCEPT AS PROVIDED IN SECTION 7.4, NEITHER PARTY SHALL BE LIABLE FOR:
- INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES
- LOST PROFITS, REVENUE, OR BUSINESS OPPORTUNITIES
- LOSS OF DATA OR GOODWILL
- COST OF PROCUREMENT OF SUBSTITUTE SERVICES
- BUSINESS INTERRUPTION

EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

### 7.3 Liability Exceptions - No Cap

The liability limitations in Sections 7.1 and 7.2 do not apply to:

a) **Indemnification obligations** under Section 8

b) **Gross negligence or willful misconduct** by either party

c) **Breach of confidentiality obligations** under Section 10

d) **Data breaches** caused by Provider's failure to implement required security measures

e) **Fraud or fraudulent misrepresentation**

f) **Violations of applicable law** that cannot be limited by contract

g) **Payment obligations** (fees, taxes, credits)

### 7.4 Enhanced Liability Protection (Fortune 5 Enterprise Tier)

For Customer organizations ranked in Fortune 5, Provider offers enhanced liability protection:

- **Increased Liability Cap:** $50,000,000 USD per incident, $100,000,000 USD aggregate annually
- **Cyber Insurance Coverage:** Provider maintains minimum $100,000,000 cyber liability insurance
- **Business Interruption Coverage:** Up to $25,000,000 for documented losses from Provider-caused outages exceeding 4 hours
- **Data Breach Insurance:** Separate $50,000,000 coverage for data breach incidents

### 7.5 Mitigation Obligations

Both parties shall take reasonable steps to mitigate damages. Failure to mitigate may reduce recoverable damages.

## 8. INDEMNIFICATION

### 8.1 Provider Indemnification

Provider shall defend, indemnify, and hold harmless Customer from and against any Covered Claims arising from:

a) **Intellectual Property Infringement:** Claims that Services infringe or misappropriate third-party intellectual property rights

b) **Data Breaches:** Claims arising from Provider's breach of security obligations resulting in unauthorized access to Customer Data

c) **Regulatory Violations:** Claims that Provider's provision of Services violates applicable laws or regulations

d) **Personal Injury or Property Damage:** Claims for bodily injury or tangible property damage caused by Provider's negligence

### 8.2 Customer Indemnification

Customer shall defend, indemnify, and hold harmless Provider from claims arising from:

a) Customer Data content, including intellectual property infringement claims

b) Customer's violation of applicable laws or regulations in use of Services

c) Customer's breach of this Agreement

d) Claims by Customer's employees, contractors, or end users regarding their access to Services

### 8.3 Indemnification Procedures

Party seeking indemnification ("Indemnitee") must:
1. Promptly notify indemnifying party ("Indemnitor") in writing of claim
2. Grant Indemnitor sole control of defense and settlement
3. Cooperate reasonably in defense at Indemnitor's expense

Indemnitor may not settle claim without Indemnitee's consent if settlement:
- Admits liability or wrongdoing by Indemnitee
- Imposes obligations on Indemnitee
- Does not include full release of Indemnitee

### 8.4 Remedies for IP Infringement Claims

If Services become subject to infringement claim, Provider may at its option:

a) Obtain right for Customer to continue using Services

b) Replace or modify Services to be non-infringing

c) If (a) and (b) not commercially reasonable, terminate Agreement and refund prepaid fees

## 9. COMPLIANCE

### 9.1 Regulatory Compliance

Provider maintains compliance with:

#### Information Security
- **SOC 2 Type II** certification (annual)
- **ISO 27001** certification
- **ISO 27017** (cloud security)
- **ISO 27018** (cloud privacy)

#### Data Protection
- **GDPR** (General Data Protection Regulation)
- **CCPA** (California Consumer Privacy Act)
- **HIPAA** compliance available for healthcare customers
- **GLBA** (Gramm-Leach-Bliley Act) for financial services

#### Industry Standards
- **PCI DSS Level 1** for payment card data processing
- **FedRAMP** compliance (Moderate Impact Level) for government contracts
- **FISMA** compliance capabilities

#### International Standards
- **EU-US Data Privacy Framework** participant
- **UK-US Data Bridge** compliant
- **Swiss-US Data Privacy Framework** participant
- **APEC Privacy Framework** compliant

### 9.2 Audit Rights

Customer may:
- Conduct or engage third-party to conduct security and compliance audits annually with 30 days' notice
- Review Provider's SOC 2 reports upon request under NDA
- Request evidence of compliance certifications
- Conduct on-site inspections during Business Hours with reasonable notice

Provider shall cooperate with audits and provide reasonable assistance.

### 9.3 Data Residency and Sovereignty

Provider offers:
- Data storage in Customer-specified geographic regions
- Multi-region deployment options (US, EU, UK, Canada, Australia, Japan)
- Commitments that data will not be transferred outside specified regions without consent
- Local data center options for Fortune 5 customers requiring dedicated infrastructure

### 9.4 Subprocessors

- Provider maintains list of subprocessors on website
- 30-day advance notice of new subprocessors
- Customer may object to new subprocessor; if unresolved, Customer may terminate affected Services
- All subprocessors bound by data protection obligations equivalent to this Agreement

### 9.5 Government Access Requests

Provider will:
- Notify Customer of government data access requests unless legally prohibited
- Challenge overbroad or unlawful requests
- Provide minimum data necessary to comply
- Document all government access requests for Customer review

### 9.6 Export Controls

Services may be subject to US export control laws and regulations. Customer agrees to comply with all applicable export laws and not access Services from embargoed countries or provide access to denied parties.

### 9.7 Records Retention

Provider maintains:
- Security logs for minimum 1 year (3 years for Fortune 5 customers)
- Audit trails for all data access and system changes
- Compliance documentation for 7 years
- Business continuity and disaster recovery test results for 3 years

## 10. CONFIDENTIALITY

### 10.1 Definition

Confidential Information includes:
- Business plans, strategies, and financial information
- Technical information, source code, and algorithms
- Customer Data and usage statistics
- Security measures and vulnerabilities
- Pricing and contract terms
- Information marked "Confidential" or reasonably understood as confidential

### 10.2 Obligations

Receiving party shall:
- Protect Confidential Information using same care as own confidential information (minimum reasonable care)
- Use Confidential Information only for purposes of this Agreement
- Limit disclosure to employees and contractors with need to know
- Not disclose to third parties without written consent

### 10.3 Exceptions

Confidentiality obligations do not apply to information that:
- Is or becomes publicly available through no breach
- Was rightfully known prior to disclosure
- Is independently developed without use of Confidential Information
- Is rightfully received from third party without restriction

### 10.4 Compelled Disclosure

If required by law to disclose Confidential Information, receiving party shall:
- Provide prompt notice to disclosing party
- Cooperate in seeking protective order
- Disclose only minimum information required
- Request confidential treatment of disclosed information

### 10.5 Term

Confidentiality obligations survive for 5 years after disclosure or termination of Agreement.

## 11. DATA PROTECTION AND PRIVACY

### 11.1 Data Processing Agreement

Provider and Customer agree to Data Processing Addendum (DPA) incorporated by reference, which includes:
- Standard Contractual Clauses for international transfers
- Processing purposes and instructions
- Security measures
- Subprocessor list and approval process
- Data subject rights procedures
- Breach notification requirements

### 11.2 Data Ownership

Customer retains all rights, title, and interest in Customer Data. Provider claims no ownership rights in Customer Data.

### 11.3 Data Use Restrictions

Provider shall:
- Process Customer Data only according to Customer's documented instructions
- Not use Customer Data for Provider's own purposes
- Not sell or share Customer Data with third parties
- Not use Customer Data to compete with Customer

### 11.4 Data Security

Provider implements:
- Encryption at rest (AES-256) and in transit (TLS 1.3+)
- Key management with HSM (Hardware Security Module)
- Multi-factor authentication for administrative access
- Network segregation and firewalls
- Intrusion detection and prevention systems
- Regular vulnerability scanning and penetration testing
- Security information and event management (SIEM)

### 11.5 Data Breach Response

Upon discovering data breach, Provider shall:
- Notify Customer within 24 hours
- Investigate and contain breach
- Provide detailed incident report within 72 hours
- Assist with regulatory notifications
- Implement measures to prevent recurrence
- Reimburse reasonable costs of breach response

### 11.6 Data Portability and Deletion

Upon request or termination:
- Provider will export Customer Data in standard formats (JSON, CSV, XML)
- Customer has 30 days to retrieve data after termination
- Provider will delete all Customer Data within 90 days after termination
- Provider will certify deletion upon request

## 12. BUSINESS CONTINUITY AND DISASTER RECOVERY

### 12.1 Business Continuity Plan

Provider maintains documented business continuity plan including:
- Risk assessment and business impact analysis
- Recovery strategies and procedures
- Roles and responsibilities
- Communication protocols
- Annual testing and updates

### 12.2 Disaster Recovery

Provider implements:
- **Geographic Redundancy:** Services deployed across multiple availability zones and regions
- **Data Replication:** Real-time synchronous replication within region, asynchronous cross-region
- **Backup Frequency:** Continuous incremental backups, daily full backups
- **Backup Retention:** 30 days standard, 7 years for compliance data
- **Failover Capability:** Automated failover to secondary region within 15 minutes
- **RTO Target:** 4 hours maximum for full service restoration
- **RPO Target:** 15 minutes maximum data loss

### 12.3 Testing

Provider conducts:
- Quarterly disaster recovery tests
- Annual full business continuity exercise
- Tabletop exercises semi-annually
- Test results shared with Customer upon request

### 12.4 Incident Response

Provider maintains 24x7 security operations center (SOC) with:
- Incident detection and alerting within 15 minutes
- Incident response team activation within 30 minutes
- Regular incident response drills
- Post-incident review and remediation

## 13. PAYMENT TERMS

### 13.1 Fees

Customer shall pay fees as specified in Order Form or Statement of Work.

### 13.2 Invoicing

- Subscription fees invoiced monthly or annually in advance
- Usage-based fees invoiced monthly in arrears
- Professional services invoiced upon completion or monthly for time and materials
- Payment terms: Net 30 days from invoice date

### 13.3 Late Payment

Late payments subject to:
- Interest at lesser of 1.5% per month or maximum allowed by law
- Suspension of Services if payment 30+ days overdue (with 10 days' notice)

### 13.4 Taxes

Fees exclude all taxes. Customer responsible for all sales, use, VAT, GST, and similar taxes except taxes on Provider's net income.

### 13.5 Fee Increases

Provider may increase fees upon 90 days' notice. Increases limited to 7% annually for Fortune 5 customers with multi-year contracts.

### 13.6 Refunds

Pro-rated refunds available for:
- SLA breaches exceeding service credit remedies
- Termination for Provider breach
- Services not delivered as specified
- Termination by Customer due to material breach by Provider

## 14. TERM AND TERMINATION

### 14.1 Initial Term

Agreement effective as of Effective Date and continues for Initial Term specified in Order Form (typically 1-5 years).

### 14.2 Renewal

Automatically renews for successive renewal terms of equal length unless either party provides written notice of non-renewal 90 days before end of current term.

### 14.3 Termination for Cause

Either party may terminate if other party:
- Materially breaches Agreement and fails to cure within 30 days of written notice
- Becomes insolvent or subject to bankruptcy proceedings
- Ceases business operations

### 14.4 Termination for Convenience

Customer may terminate for convenience with 90 days' written notice. Provider may not terminate for convenience during Initial Term.

### 14.5 Effect of Termination

Upon termination:
- Customer's access to Services ceases
- Customer has 30 days to retrieve Customer Data
- Provider deletes Customer Data within 90 days
- Customer pays all fees accrued through termination date
- If Customer terminates for cause, Provider refunds prepaid fees for unused Services
- Sections 7, 8, 10, 11.6, 15, and 16 survive termination

## 15. INSURANCE

### 15.1 Required Coverage

Provider maintains:

| Coverage Type | Minimum Limit |
|--------------|---------------|
| Commercial General Liability | $10,000,000 per occurrence |
| Professional Liability (E&O) | $25,000,000 per claim |
| Cyber Liability | $100,000,000 aggregate |
| Workers' Compensation | Statutory limits |
| Business Interruption | $50,000,000 |
| Crime/Fidelity Bond | $10,000,000 |

### 15.2 Additional Requirements

- Insurance carriers rated A.M. Best A- VIII or better
- Customer named as additional insured on general liability policy
- 30 days' notice of cancellation or material change
- Certificates of insurance provided annually and upon request
- Insurance requirements do not limit Provider's liability obligations

## 16. GENERAL PROVISIONS

### 16.1 Governing Law

This Agreement governed by laws of State of Delaware, USA, without regard to conflict of laws principles.

### 16.2 Dispute Resolution

**Negotiation:** Disputes escalated to executive management for 30-day good faith negotiation period.

**Mediation:** If unresolved, parties shall mediate through JAMS in Wilmington, Delaware.

**Litigation:** If mediation unsuccessful after 60 days, either party may pursue litigation.

**Venue:** Exclusive jurisdiction in state and federal courts in Delaware.

**Exception:** Either party may seek injunctive relief in any court of competent jurisdiction.

### 16.3 Assignment

Neither party may assign this Agreement without other party's written consent, except:
- Assignment to affiliate or successor in merger, acquisition, or sale of substantially all assets
- Provider may assign to entity acquiring Provider's business

### 16.4 Force Majeure

Neither party liable for failure to perform due to circumstances beyond reasonable control including natural disasters, war, terrorism, strikes, government actions, or internet/telecommunications failures, provided affected party:
- Promptly notifies other party
- Uses reasonable efforts to mitigate impact
- Resumes performance when circumstances permit

Force majeure does not excuse payment obligations or excuse performance for more than 90 days.

### 16.5 Notices

All notices must be in writing to addresses in Order Form via:
- Certified mail, return receipt requested
- Overnight courier
- Email (requires confirmation of receipt)

Notices effective upon receipt.

### 16.6 Entire Agreement

This Agreement, including incorporated Order Forms, SOWs, and DPA, constitutes entire agreement and supersedes all prior agreements regarding subject matter.

### 16.7 Amendments

Amendments must be in writing signed by authorized representatives of both parties, except:
- Provider may update policies and documentation with 30 days' notice
- Material adverse changes require Customer consent

### 16.8 Waiver

Failure to enforce provision does not waive right to enforce later. Waiver effective only if in writing signed by waiving party.

### 16.9 Severability

If any provision held invalid or unenforceable, remaining provisions remain in full effect. Invalid provision replaced with valid provision achieving original intent.

### 16.10 Independent Contractors

Parties are independent contractors. Nothing creates partnership, joint venture, agency, or employment relationship.

### 16.11 Third-Party Beneficiaries

No third-party beneficiaries except Provider's affiliates and subcontractors who may enforce relevant protections.

### 16.12 Equitable Relief

Breach of confidentiality, data protection, or intellectual property provisions may cause irreparable harm. Parties entitled to injunctive relief without proving damages or posting bond.

### 16.13 Counterparts

Agreement may be executed in counterparts, each deemed an original. Electronic signatures have same effect as original signatures.

### 16.14 Publicity

Neither party may issue press release or public announcement regarding Agreement without other party's prior written approval, except as required by law or securities regulations.

### 16.15 Government Customers

If Customer is US Government entity, Services are "commercial items" as defined in FAR 2.101, provided with only those rights as specified in this Agreement.

### 16.16 Language

Agreement drafted in English. Any translation for convenience only; English version controls.

---

## ACCEPTANCE

By executing an Order Form or accessing Services, Customer agrees to be bound by these Terms of Service.

For questions regarding these Terms, contact:

**A2A Platform Provider**
Legal Department
Email: legal@a2a-platform.com
Address: [Corporate Address]

**Last Updated:** February 6, 2026
**Version:** 2.0-Enterprise
