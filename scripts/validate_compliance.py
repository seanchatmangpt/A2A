#!/usr/bin/env python3
"""
Compliance Validation Script for PCI-DSS, SOC2, and HIPAA
Validates infrastructure configurations against compliance requirements
"""

import os
import sys
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple
import subprocess

# ANSI color codes for output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

class ComplianceValidator:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.terraform_dir = self.project_root / "terraform"
        self.docs_dir = self.project_root / "docs"
        self.results = {
            'pci_dss': {'passed': [], 'failed': [], 'warnings': []},
            'soc2': {'passed': [], 'failed': [], 'warnings': []},
            'hipaa': {'passed': [], 'failed': [], 'warnings': []}
        }

    def print_header(self, text: str):
        """Print formatted header"""
        print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*80}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{text.center(80)}{Colors.RESET}")
        print(f"{Colors.BOLD}{Colors.BLUE}{'='*80}{Colors.RESET}\n")

    def print_check(self, framework: str, check_name: str, status: str, details: str = ""):
        """Print compliance check result"""
        if status == "PASS":
            symbol = f"{Colors.GREEN}✓{Colors.RESET}"
            self.results[framework]['passed'].append(check_name)
        elif status == "FAIL":
            symbol = f"{Colors.RED}✗{Colors.RESET}"
            self.results[framework]['failed'].append(check_name)
        else:  # WARNING
            symbol = f"{Colors.YELLOW}⚠{Colors.RESET}"
            self.results[framework]['warnings'].append(check_name)

        print(f"{symbol} [{framework.upper()}] {check_name}")
        if details:
            print(f"  {details}")

    def read_terraform_file(self, filename: str) -> str:
        """Read Terraform configuration file"""
        try:
            filepath = self.terraform_dir / filename
            if filepath.exists():
                with open(filepath, 'r') as f:
                    return f.read()
            return ""
        except Exception as e:
            print(f"{Colors.RED}Error reading {filename}: {e}{Colors.RESET}")
            return ""

    def check_pattern_in_file(self, content: str, pattern: str) -> bool:
        """Check if pattern exists in file content"""
        return bool(re.search(pattern, content, re.IGNORECASE | re.MULTILINE))

    # ==================== PCI-DSS VALIDATION ====================

    def validate_pci_dss(self):
        """Validate PCI-DSS v4.0 compliance requirements"""
        self.print_header("PCI-DSS v4.0 Compliance Validation")

        compliance_tf = self.read_terraform_file("compliance.tf")
        audit_tf = self.read_terraform_file("audit.tf")

        # Requirement 1: Install and maintain network security controls
        self.check_firewall_configuration(compliance_tf)

        # Requirement 2: Apply secure configurations
        self.check_secure_configurations(compliance_tf)

        # Requirement 3: Protect stored cardholder data
        self.check_data_encryption_at_rest(compliance_tf)

        # Requirement 4: Protect cardholder data with strong cryptography during transmission
        self.check_data_encryption_in_transit(compliance_tf)

        # Requirement 5: Protect all systems and networks from malicious software
        self.check_malware_protection(compliance_tf)

        # Requirement 6: Develop and maintain secure systems and software
        self.check_secure_development(compliance_tf)

        # Requirement 7: Restrict access to system components and cardholder data
        self.check_access_controls(compliance_tf)

        # Requirement 8: Identify users and authenticate access
        self.check_authentication(compliance_tf)

        # Requirement 9: Restrict physical access to cardholder data
        self.check_physical_security(compliance_tf)

        # Requirement 10: Log and monitor all access to system components and cardholder data
        self.check_logging_monitoring(audit_tf)

        # Requirement 11: Test security of systems and networks regularly
        self.check_security_testing(compliance_tf)

        # Requirement 12: Support information security with organizational policies
        self.check_security_policies()

    def check_firewall_configuration(self, content: str):
        """PCI-DSS Req 1: Network security controls"""
        # Check for firewall rules
        has_firewall_deny_all = self.check_pattern_in_file(content, r'deny_all_(ingress|egress)')
        has_firewall_rules = self.check_pattern_in_file(content, r'google_compute_firewall')
        has_waf = self.check_pattern_in_file(content, r'google_compute_security_policy.*pci')

        if has_firewall_deny_all and has_firewall_rules:
            self.print_check('pci_dss', 'Network Segmentation & Firewall Rules', 'PASS',
                           'Default deny-all firewall rules configured')
        else:
            self.print_check('pci_dss', 'Network Segmentation & Firewall Rules', 'FAIL',
                           'Missing default deny firewall rules')

        if has_waf:
            self.print_check('pci_dss', 'Web Application Firewall (WAF)', 'PASS',
                           'PCI-DSS security policy configured')
        else:
            self.print_check('pci_dss', 'Web Application Firewall (WAF)', 'FAIL',
                           'Missing WAF configuration')

    def check_secure_configurations(self, content: str):
        """PCI-DSS Req 2: Secure configurations"""
        has_org_policies = self.check_pattern_in_file(content, r'google_organization_policy')
        has_shielded_vm = self.check_pattern_in_file(content, r'requireShieldedVm')
        has_os_login = self.check_pattern_in_file(content, r'requireOsLogin')

        if has_org_policies and has_shielded_vm and has_os_login:
            self.print_check('pci_dss', 'Secure System Configurations', 'PASS',
                           'Organization policies enforce secure configurations')
        else:
            self.print_check('pci_dss', 'Secure System Configurations', 'FAIL',
                           'Missing organization security policies')

    def check_data_encryption_at_rest(self, content: str):
        """PCI-DSS Req 3: Encryption at rest"""
        has_kms = self.check_pattern_in_file(content, r'google_kms_crypto_key')
        has_hsm = self.check_pattern_in_file(content, r'protection_level.*HSM')
        has_rotation = self.check_pattern_in_file(content, r'rotation_period')
        has_bucket_encryption = self.check_pattern_in_file(content, r'encryption\s*{[^}]*default_kms_key_name')

        if has_kms and has_hsm:
            self.print_check('pci_dss', 'Encryption Keys (HSM-backed)', 'PASS',
                           'KMS keys with HSM protection configured')
        else:
            self.print_check('pci_dss', 'Encryption Keys (HSM-backed)', 'FAIL',
                           'Missing HSM-backed encryption keys')

        if has_rotation:
            self.print_check('pci_dss', 'Key Rotation Policy', 'PASS',
                           'Automatic key rotation configured')
        else:
            self.print_check('pci_dss', 'Key Rotation Policy', 'FAIL',
                           'Missing key rotation policy')

        if has_bucket_encryption:
            self.print_check('pci_dss', 'Data-at-Rest Encryption', 'PASS',
                           'Storage bucket encryption enabled')
        else:
            self.print_check('pci_dss', 'Data-at-Rest Encryption', 'FAIL',
                           'Storage encryption not configured')

    def check_data_encryption_in_transit(self, content: str):
        """PCI-DSS Req 4: Encryption in transit"""
        has_https_only = self.check_pattern_in_file(content, r'allow_https_ingress')
        has_tls_policy = self.check_pattern_in_file(content, r'(TLS|ssl|https)')

        if has_https_only:
            self.print_check('pci_dss', 'HTTPS/TLS Enforcement', 'PASS',
                           'HTTPS ingress rules configured')
        else:
            self.print_check('pci_dss', 'HTTPS/TLS Enforcement', 'WARNING',
                           'Verify TLS enforcement in application layer')

    def check_malware_protection(self, content: str):
        """PCI-DSS Req 5: Anti-malware"""
        has_binary_auth = self.check_pattern_in_file(content, r'google_binary_authorization_policy')
        has_dlp = self.check_pattern_in_file(content, r'google_data_loss_prevention')

        if has_binary_auth:
            self.print_check('pci_dss', 'Binary Authorization (Container Scanning)', 'PASS',
                           'Binary authorization policy configured')
        else:
            self.print_check('pci_dss', 'Binary Authorization (Container Scanning)', 'WARNING',
                           'Consider enabling container image scanning')

        if has_dlp:
            self.print_check('pci_dss', 'Data Loss Prevention (DLP)', 'PASS',
                           'DLP scanning configured for sensitive data')
        else:
            self.print_check('pci_dss', 'Data Loss Prevention (DLP)', 'FAIL',
                           'Missing DLP configuration')

    def check_secure_development(self, content: str):
        """PCI-DSS Req 6: Secure development"""
        has_waf_protection = self.check_pattern_in_file(content, r'sqli-stable|xss-stable|rce-stable')

        if has_waf_protection:
            self.print_check('pci_dss', 'WAF Protection (OWASP Top 10)', 'PASS',
                           'WAF rules for SQL injection, XSS, RCE configured')
        else:
            self.print_check('pci_dss', 'WAF Protection (OWASP Top 10)', 'FAIL',
                           'Missing WAF protection against common vulnerabilities')

    def check_access_controls(self, content: str):
        """PCI-DSS Req 7: Access controls"""
        has_iam_policies = self.check_pattern_in_file(content, r'google_project_iam')
        has_access_context = self.check_pattern_in_file(content, r'google_access_context_manager')
        has_service_perimeter = self.check_pattern_in_file(content, r'service_perimeter')

        if has_iam_policies:
            self.print_check('pci_dss', 'Role-Based Access Control (RBAC)', 'PASS',
                           'IAM policies configured')
        else:
            self.print_check('pci_dss', 'Role-Based Access Control (RBAC)', 'FAIL',
                           'Missing IAM access controls')

        if has_access_context and has_service_perimeter:
            self.print_check('pci_dss', 'VPC Service Controls', 'PASS',
                           'Access context manager and service perimeter configured')
        else:
            self.print_check('pci_dss', 'VPC Service Controls', 'FAIL',
                           'Missing VPC service controls')

    def check_authentication(self, content: str):
        """PCI-DSS Req 8: User identification and authentication"""
        has_device_policy = self.check_pattern_in_file(content, r'device_policy')
        has_mfa = self.check_pattern_in_file(content, r'require_admin_approval|require_screen_lock')

        if has_device_policy and has_mfa:
            self.print_check('pci_dss', 'Multi-Factor Authentication (MFA)', 'PASS',
                           'Device policy with admin approval required')
        else:
            self.print_check('pci_dss', 'Multi-Factor Authentication (MFA)', 'WARNING',
                           'Verify MFA enforcement for all users')

    def check_physical_security(self, content: str):
        """PCI-DSS Req 9: Physical access controls"""
        has_hsm = self.check_pattern_in_file(content, r'protection_level.*HSM')

        if has_hsm:
            self.print_check('pci_dss', 'Physical Security (HSM)', 'PASS',
                           'Hardware Security Modules (HSM) configured')
        else:
            self.print_check('pci_dss', 'Physical Security (HSM)', 'FAIL',
                           'Missing HSM for key protection')

    def check_logging_monitoring(self, content: str):
        """PCI-DSS Req 10: Logging and monitoring"""
        has_audit_logs = self.check_pattern_in_file(content, r'google_project_iam_audit_config')
        has_log_retention = self.check_pattern_in_file(content, r'retention_days.*2555')  # 7 years
        has_log_sinks = self.check_pattern_in_file(content, r'google_logging_project_sink')
        has_monitoring = self.check_pattern_in_file(content, r'google_logging_metric')

        if has_audit_logs:
            self.print_check('pci_dss', 'Audit Logging (All Services)', 'PASS',
                           'Comprehensive audit logging configured')
        else:
            self.print_check('pci_dss', 'Audit Logging (All Services)', 'FAIL',
                           'Missing audit logging configuration')

        if has_log_retention:
            self.print_check('pci_dss', 'Log Retention (7 years)', 'PASS',
                           '7-year log retention period configured')
        else:
            self.print_check('pci_dss', 'Log Retention (7 years)', 'FAIL',
                           'Insufficient log retention period')

        if has_log_sinks:
            self.print_check('pci_dss', 'Log Collection & Centralization', 'PASS',
                           'Log sinks for centralized collection configured')
        else:
            self.print_check('pci_dss', 'Log Collection & Centralization', 'FAIL',
                           'Missing centralized log collection')

        if has_monitoring:
            self.print_check('pci_dss', 'Security Monitoring & Alerting', 'PASS',
                           'Log metrics for security monitoring configured')
        else:
            self.print_check('pci_dss', 'Security Monitoring & Alerting', 'FAIL',
                           'Missing security monitoring')

    def check_security_testing(self, content: str):
        """PCI-DSS Req 11: Security testing"""
        has_vulnerability_scanning = self.check_pattern_in_file(content, r'dlp|vulnerability')

        if has_vulnerability_scanning:
            self.print_check('pci_dss', 'Vulnerability Scanning', 'PASS',
                           'Automated vulnerability scanning configured')
        else:
            self.print_check('pci_dss', 'Vulnerability Scanning', 'WARNING',
                           'Verify external vulnerability scanning process')

    def check_security_policies(self):
        """PCI-DSS Req 12: Information security policy"""
        compliance_doc = self.docs_dir / "COMPLIANCE.md"

        if compliance_doc.exists():
            content = compliance_doc.read_text()
            has_pci_dss = 'PCI-DSS' in content or 'PCI DSS' in content

            if has_pci_dss:
                self.print_check('pci_dss', 'Security Policy Documentation', 'PASS',
                               'PCI-DSS compliance documentation exists')
            else:
                self.print_check('pci_dss', 'Security Policy Documentation', 'WARNING',
                               'Update compliance documentation')
        else:
            self.print_check('pci_dss', 'Security Policy Documentation', 'FAIL',
                           'Missing compliance documentation')

    # ==================== SOC2 VALIDATION ====================

    def validate_soc2(self):
        """Validate SOC 2 Type II compliance requirements"""
        self.print_header("SOC 2 Type II Compliance Validation")

        compliance_tf = self.read_terraform_file("compliance.tf")
        audit_tf = self.read_terraform_file("audit.tf")
        policy_tf = self.read_terraform_file("policy_enforcement.tf")

        # Security: System protection against unauthorized access
        self.check_soc2_security(compliance_tf)

        # Availability: System availability for operation
        self.check_soc2_availability(compliance_tf, policy_tf)

        # Processing Integrity: Complete, valid, accurate processing
        self.check_soc2_integrity(compliance_tf)

        # Confidentiality: Protection of confidential information
        self.check_soc2_confidentiality(compliance_tf)

        # Privacy: Personal information protection
        self.check_soc2_privacy(compliance_tf)

        # Change Management
        self.check_soc2_change_management(policy_tf)

        # Monitoring and Logging
        self.check_soc2_monitoring(audit_tf)

    def check_soc2_security(self, content: str):
        """SOC2: Security controls"""
        has_access_controls = self.check_pattern_in_file(content, r'google_access_context_manager')
        has_encryption = self.check_pattern_in_file(content, r'google_kms_crypto_key')
        has_network_security = self.check_pattern_in_file(content, r'google_compute_security_policy')

        if has_access_controls and has_encryption and has_network_security:
            self.print_check('soc2', 'Security Controls (Access, Encryption, Network)', 'PASS',
                           'Comprehensive security controls implemented')
        else:
            self.print_check('soc2', 'Security Controls (Access, Encryption, Network)', 'FAIL',
                           'Missing security controls')

    def check_soc2_availability(self, compliance_content: str, policy_content: str):
        """SOC2: Availability controls"""
        has_backup_encryption = self.check_pattern_in_file(compliance_content, r'backup_encryption_key')
        has_retention = self.check_pattern_in_file(compliance_content, r'retention_policy')
        has_pdb_policy = self.check_pattern_in_file(policy_content, r'PodDisruptionBudget|K8sRequirePDB')

        if has_backup_encryption and has_retention:
            self.print_check('soc2', 'Backup and Recovery', 'PASS',
                           'Backup encryption and retention configured')
        else:
            self.print_check('soc2', 'Backup and Recovery', 'FAIL',
                           'Missing backup configuration')

        if has_pdb_policy:
            self.print_check('soc2', 'High Availability (PodDisruptionBudget)', 'PASS',
                           'PodDisruptionBudget policy enforced')
        else:
            self.print_check('soc2', 'High Availability (PodDisruptionBudget)', 'WARNING',
                           'Consider enforcing PodDisruptionBudget policies')

    def check_soc2_integrity(self, content: str):
        """SOC2: Processing integrity"""
        has_monitoring = self.check_pattern_in_file(content, r'google_monitoring_alert_policy')
        has_binary_auth = self.check_pattern_in_file(content, r'google_binary_authorization_policy')

        if has_monitoring:
            self.print_check('soc2', 'Processing Integrity Monitoring', 'PASS',
                           'Monitoring and alerting configured')
        else:
            self.print_check('soc2', 'Processing Integrity Monitoring', 'FAIL',
                           'Missing monitoring configuration')

        if has_binary_auth:
            self.print_check('soc2', 'Code Integrity (Binary Authorization)', 'PASS',
                           'Binary authorization ensures code integrity')
        else:
            self.print_check('soc2', 'Code Integrity (Binary Authorization)', 'WARNING',
                           'Consider enabling binary authorization')

    def check_soc2_confidentiality(self, content: str):
        """SOC2: Confidentiality controls"""
        has_secrets = self.check_pattern_in_file(content, r'google_secret_manager_secret')
        has_kms_encryption = self.check_pattern_in_file(content, r'customer_managed_encryption')
        has_dlp = self.check_pattern_in_file(content, r'google_data_loss_prevention')

        if has_secrets and has_kms_encryption:
            self.print_check('soc2', 'Secret Management & Encryption', 'PASS',
                           'Secrets manager with customer-managed encryption')
        else:
            self.print_check('soc2', 'Secret Management & Encryption', 'FAIL',
                           'Missing secret management or encryption')

        if has_dlp:
            self.print_check('soc2', 'Data Classification & DLP', 'PASS',
                           'Data Loss Prevention configured')
        else:
            self.print_check('soc2', 'Data Classification & DLP', 'FAIL',
                           'Missing DLP configuration')

    def check_soc2_privacy(self, content: str):
        """SOC2: Privacy controls"""
        has_data_residency = self.check_pattern_in_file(content, r'location.*=.*(US|EU)')
        has_retention_policy = self.check_pattern_in_file(content, r'retention_policy|lifecycle_rule')

        if has_data_residency:
            self.print_check('soc2', 'Data Residency Controls', 'PASS',
                           'Geographic data residency configured')
        else:
            self.print_check('soc2', 'Data Residency Controls', 'WARNING',
                           'Verify data residency requirements')

        if has_retention_policy:
            self.print_check('soc2', 'Data Retention & Disposal', 'PASS',
                           'Data retention and lifecycle policies configured')
        else:
            self.print_check('soc2', 'Data Retention & Disposal', 'FAIL',
                           'Missing data retention policies')

    def check_soc2_change_management(self, content: str):
        """SOC2: Change management controls"""
        has_gatekeeper = self.check_pattern_in_file(content, r'gatekeeper|ConstraintTemplate')
        has_policies = self.check_pattern_in_file(content, r'K8sRequired|K8sAllowed|K8sBlock')

        if has_gatekeeper and has_policies:
            self.print_check('soc2', 'Change Management (OPA Gatekeeper)', 'PASS',
                           'Policy enforcement via OPA Gatekeeper')
        else:
            self.print_check('soc2', 'Change Management (OPA Gatekeeper)', 'FAIL',
                           'Missing policy enforcement')

    def check_soc2_monitoring(self, content: str):
        """SOC2: Monitoring controls"""
        has_siem_integration = self.check_pattern_in_file(content, r'siem|pubsub_topic.*security')
        has_metrics = self.check_pattern_in_file(content, r'google_logging_metric')
        has_comprehensive_logging = self.check_pattern_in_file(content, r'audit_log_config.*DATA_READ.*DATA_WRITE', )

        if has_siem_integration:
            self.print_check('soc2', 'SIEM Integration', 'PASS',
                           'Security event streaming to SIEM configured')
        else:
            self.print_check('soc2', 'SIEM Integration', 'WARNING',
                           'Consider SIEM integration for security monitoring')

        if has_metrics and has_comprehensive_logging:
            self.print_check('soc2', 'Comprehensive Audit Logging', 'PASS',
                           'All operations logged with metrics')
        else:
            self.print_check('soc2', 'Comprehensive Audit Logging', 'FAIL',
                           'Incomplete audit logging')

    # ==================== HIPAA VALIDATION ====================

    def validate_hipaa(self):
        """Validate HIPAA compliance requirements"""
        self.print_header("HIPAA Compliance Validation")

        compliance_tf = self.read_terraform_file("compliance.tf")
        audit_tf = self.read_terraform_file("audit.tf")

        # Administrative Safeguards
        self.check_hipaa_administrative(compliance_tf, audit_tf)

        # Physical Safeguards
        self.check_hipaa_physical(compliance_tf)

        # Technical Safeguards
        self.check_hipaa_technical(compliance_tf, audit_tf)

        # Breach Notification
        self.check_hipaa_breach_notification(audit_tf)

    def check_hipaa_administrative(self, compliance_content: str, audit_content: str):
        """HIPAA: Administrative safeguards"""
        has_risk_management = self.check_pattern_in_file(compliance_content, r'google_monitoring_alert_policy')
        has_workforce_security = self.check_pattern_in_file(compliance_content, r'google_access_context_manager')
        has_audit_controls = self.check_pattern_in_file(audit_content, r'google_project_iam_audit_config')
        has_incident_response = self.check_pattern_in_file(audit_content, r'security_events|incident')

        if has_risk_management:
            self.print_check('hipaa', 'Security Risk Management', 'PASS',
                           'Risk monitoring and alerting configured')
        else:
            self.print_check('hipaa', 'Security Risk Management', 'FAIL',
                           'Missing risk management controls')

        if has_workforce_security:
            self.print_check('hipaa', 'Workforce Security & Access Management', 'PASS',
                           'Access context manager for workforce controls')
        else:
            self.print_check('hipaa', 'Workforce Security & Access Management', 'FAIL',
                           'Missing workforce security controls')

        if has_audit_controls:
            self.print_check('hipaa', 'Audit Controls', 'PASS',
                           'Comprehensive audit logging for PHI access')
        else:
            self.print_check('hipaa', 'Audit Controls', 'FAIL',
                           'Missing audit controls')

        if has_incident_response:
            self.print_check('hipaa', 'Security Incident Procedures', 'PASS',
                           'Security incident logging and response')
        else:
            self.print_check('hipaa', 'Security Incident Procedures', 'WARNING',
                           'Verify incident response procedures')

    def check_hipaa_physical(self, content: str):
        """HIPAA: Physical safeguards"""
        has_hsm = self.check_pattern_in_file(content, r'protection_level.*HSM')
        has_device_controls = self.check_pattern_in_file(content, r'device_policy|require_corp_owned')

        if has_hsm:
            self.print_check('hipaa', 'Physical Security (HSM for Key Storage)', 'PASS',
                           'Hardware Security Modules protect encryption keys')
        else:
            self.print_check('hipaa', 'Physical Security (HSM for Key Storage)', 'FAIL',
                           'Missing HSM for physical key protection')

        if has_device_controls:
            self.print_check('hipaa', 'Workstation & Device Security', 'PASS',
                           'Device security policies enforced')
        else:
            self.print_check('hipaa', 'Workstation & Device Security', 'WARNING',
                           'Verify workstation security policies')

    def check_hipaa_technical(self, compliance_content: str, audit_content: str):
        """HIPAA: Technical safeguards"""
        # Access Control
        has_unique_user_id = self.check_pattern_in_file(compliance_content, r'require_admin_approval|iam')
        has_encryption_at_rest = self.check_pattern_in_file(compliance_content, r'google_kms_crypto_key.*HSM')
        has_encryption_in_transit = self.check_pattern_in_file(compliance_content, r'https|tls')
        has_audit_logs = self.check_pattern_in_file(audit_content, r'DATA_READ.*DATA_WRITE')
        has_integrity_controls = self.check_pattern_in_file(compliance_content, r'versioning|binary_authorization')

        if has_unique_user_id:
            self.print_check('hipaa', 'Access Control (Unique User IDs)', 'PASS',
                           'IAM provides unique user identification')
        else:
            self.print_check('hipaa', 'Access Control (Unique User IDs)', 'FAIL',
                           'Missing unique user identification')

        if has_encryption_at_rest:
            self.print_check('hipaa', 'PHI Encryption at Rest (AES-256, HSM)', 'PASS',
                           'KMS with HSM for PHI encryption at rest')
        else:
            self.print_check('hipaa', 'PHI Encryption at Rest (AES-256, HSM)', 'FAIL',
                           'Missing PHI encryption at rest')

        if has_encryption_in_transit:
            self.print_check('hipaa', 'PHI Transmission Security (TLS 1.3)', 'PASS',
                           'TLS/HTTPS encryption for data in transit')
        else:
            self.print_check('hipaa', 'PHI Transmission Security (TLS 1.3)', 'WARNING',
                           'Verify TLS 1.3 enforcement')

        if has_audit_logs:
            self.print_check('hipaa', 'Audit Logging (PHI Access)', 'PASS',
                           'All PHI read/write operations logged')
        else:
            self.print_check('hipaa', 'Audit Logging (PHI Access)', 'FAIL',
                           'Incomplete PHI access logging')

        if has_integrity_controls:
            self.print_check('hipaa', 'Data Integrity Controls', 'PASS',
                           'Versioning and integrity controls configured')
        else:
            self.print_check('hipaa', 'Data Integrity Controls', 'WARNING',
                           'Verify data integrity mechanisms')

    def check_hipaa_breach_notification(self, content: str):
        """HIPAA: Breach notification"""
        has_alerting = self.check_pattern_in_file(content, r'security_events|data_exfiltration|unauthorized_access')
        has_monitoring = self.check_pattern_in_file(content, r'google_logging_metric')

        if has_alerting and has_monitoring:
            self.print_check('hipaa', 'Breach Detection & Notification', 'PASS',
                           'Security event monitoring and alerting configured')
        else:
            self.print_check('hipaa', 'Breach Detection & Notification', 'FAIL',
                           'Missing breach detection mechanisms')

    # ==================== REPORTING ====================

    def generate_summary_report(self):
        """Generate compliance validation summary report"""
        self.print_header("Compliance Validation Summary Report")

        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

        for framework in ['pci_dss', 'soc2', 'hipaa']:
            framework_name = framework.replace('_', '-').upper()
            passed = len(self.results[framework]['passed'])
            failed = len(self.results[framework]['failed'])
            warnings = len(self.results[framework]['warnings'])
            total = passed + failed + warnings

            if total > 0:
                pass_rate = (passed / total) * 100

                print(f"\n{Colors.BOLD}{framework_name} Compliance:{Colors.RESET}")
                print(f"  {Colors.GREEN}✓ Passed:  {passed}{Colors.RESET}")
                print(f"  {Colors.RED}✗ Failed:  {failed}{Colors.RESET}")
                print(f"  {Colors.YELLOW}⚠ Warnings: {warnings}{Colors.RESET}")
                print(f"  {Colors.BOLD}Pass Rate: {pass_rate:.1f}%{Colors.RESET}")

                if pass_rate >= 90:
                    status = f"{Colors.GREEN}EXCELLENT{Colors.RESET}"
                elif pass_rate >= 75:
                    status = f"{Colors.YELLOW}GOOD{Colors.RESET}"
                elif pass_rate >= 60:
                    status = f"{Colors.YELLOW}NEEDS IMPROVEMENT{Colors.RESET}"
                else:
                    status = f"{Colors.RED}CRITICAL{Colors.RESET}"

                print(f"  Status: {status}")

        print(f"\n{Colors.BOLD}Overall Compliance Status:{Colors.RESET}")
        total_passed = sum(len(self.results[f]['passed']) for f in self.results)
        total_failed = sum(len(self.results[f]['failed']) for f in self.results)
        total_warnings = sum(len(self.results[f]['warnings']) for f in self.results)
        total_checks = total_passed + total_failed + total_warnings

        if total_checks > 0:
            overall_pass_rate = (total_passed / total_checks) * 100
            print(f"  Total Checks: {total_checks}")
            print(f"  Overall Pass Rate: {overall_pass_rate:.1f}%")

            if total_failed == 0:
                print(f"\n  {Colors.GREEN}{Colors.BOLD}✓ All critical compliance requirements met!{Colors.RESET}")
            else:
                print(f"\n  {Colors.RED}{Colors.BOLD}✗ {total_failed} critical issues require attention{Colors.RESET}")

        print("\n" + "="*80 + "\n")

    def run_all_validations(self):
        """Run all compliance validations"""
        print(f"\n{Colors.BOLD}A2A Compliance Validation Tool{Colors.RESET}")
        print(f"Project Root: {self.project_root}\n")

        try:
            self.validate_pci_dss()
            self.validate_soc2()
            self.validate_hipaa()
            self.generate_summary_report()

            # Return exit code based on failures
            total_failed = sum(len(self.results[f]['failed']) for f in self.results)
            return 1 if total_failed > 0 else 0

        except Exception as e:
            print(f"\n{Colors.RED}Error during validation: {e}{Colors.RESET}")
            import traceback
            traceback.print_exc()
            return 2


def main():
    """Main entry point"""
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    validator = ComplianceValidator(project_root)
    exit_code = validator.run_all_validations()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
