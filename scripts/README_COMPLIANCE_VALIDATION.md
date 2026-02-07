# Compliance Validation Tool

Automated validation script for PCI-DSS v4.0, SOC2 Type II, and HIPAA compliance requirements.

## Quick Start

```bash
# Run the validation
python3 scripts/validate_compliance.py

# Or make it executable and run directly
chmod +x scripts/validate_compliance.py
./scripts/validate_compliance.py
```

## What It Checks

### PCI-DSS v4.0 (20 checks)
- Network segmentation and firewall rules
- Secure system configurations
- Encryption at rest and in transit (HSM-backed)
- Access controls and authentication
- Comprehensive audit logging
- Security monitoring and testing
- WAF protection against OWASP Top 10

### SOC2 Type II (12 checks)
- Security controls (access, encryption, network)
- Availability (backup, recovery, high availability)
- Processing integrity (monitoring, code integrity)
- Confidentiality (secrets management, DLP)
- Privacy (data residency, retention)
- Change management (OPA Gatekeeper)
- SIEM integration

### HIPAA (12 checks)
- Administrative safeguards (risk management, workforce security)
- Physical safeguards (HSM, device security)
- Technical safeguards (encryption, access controls, audit logging)
- Breach detection and notification

## Output

The script provides:
- ✓ Green checkmarks for passed checks
- ✗ Red X marks for failed checks
- ⚠ Yellow warnings for items needing attention
- Detailed pass rates for each framework
- Overall compliance summary

## Exit Codes

- `0` - All compliance checks passed
- `1` - One or more compliance checks failed (review required)
- `2` - Error during validation execution

## Configuration Files Validated

- `/terraform/compliance.tf` - Infrastructure compliance configurations
- `/terraform/audit.tf` - Audit logging configurations
- `/terraform/policy_enforcement.tf` - OPA Gatekeeper policies
- `/docs/COMPLIANCE.md` - Compliance documentation

## Integration with CI/CD

### GitHub Actions Example
```yaml
name: Compliance Validation

on: [push, pull_request]

jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.x'
      - name: Run Compliance Validation
        run: python3 scripts/validate_compliance.py
```

### GitLab CI Example
```yaml
compliance_validation:
  stage: test
  script:
    - python3 scripts/validate_compliance.py
  only:
    - merge_requests
    - main
```

## Report Generation

After running the validation, review:
- Console output for immediate results
- `COMPLIANCE_VALIDATION_REPORT.md` for detailed findings

## Compliance Frameworks Coverage

### PCI-DSS Requirements Mapped
1. Network Security Controls ✓
2. Secure Configurations ✓
3. Protect Stored Cardholder Data ✓
4. Protect Data in Transit ✓
5. Anti-Malware ✓
6. Secure Development ✓
7. Access Controls ✓
8. User Authentication ✓
9. Physical Access ✓
10. Logging & Monitoring ✓
11. Security Testing ✓
12. Security Policies ✓

### SOC2 Trust Services Criteria
- Security ✓
- Availability ✓
- Processing Integrity ✓
- Confidentiality ✓
- Privacy ✓

### HIPAA Rules Covered
- Privacy Rule ✓
- Security Rule ✓
  - Administrative Safeguards ✓
  - Physical Safeguards ✓
  - Technical Safeguards ✓
- Breach Notification Rule ✓

## Customization

To add custom checks, edit `validate_compliance.py`:

1. Add validation method in the appropriate class
2. Call the method from framework validation function
3. Use `self.print_check()` to report results

Example:
```python
def check_custom_requirement(self, content: str):
    """Custom compliance check"""
    has_feature = self.check_pattern_in_file(content, r'pattern')

    if has_feature:
        self.print_check('framework', 'Check Name', 'PASS', 'Details')
    else:
        self.print_check('framework', 'Check Name', 'FAIL', 'Missing feature')
```

## Troubleshooting

### Script fails to find files
- Ensure you're running from project root: `/home/user/A2A`
- Check that terraform files exist in `/terraform/` directory

### False positives
- Review regex patterns in validation methods
- Check actual Terraform configuration for compliance features
- Update patterns to match your specific implementation

### Permission denied
```bash
chmod +x scripts/validate_compliance.py
```

## Maintenance

### Regular Updates
- Review and update validation patterns quarterly
- Add new compliance requirements as regulations evolve
- Update documentation with audit findings

### Version History
- v1.0 (Feb 2026) - Initial release with PCI-DSS, SOC2, HIPAA

## Support

For issues or questions:
- Review detailed report: `COMPLIANCE_VALIDATION_REPORT.md`
- Check Terraform configurations in `/terraform/`
- Consult compliance documentation: `/docs/COMPLIANCE.md`

## License

Internal tool for A2A compliance validation.
