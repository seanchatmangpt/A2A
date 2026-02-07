# YAML Validation Guide

This directory contains scripts and configuration for validating all YAML files in the A2A project.

## Files

- **validate_yaml.py** - Main validation script that checks all YAML files
- **validate_yaml_summary.py** - Generates a detailed summary report of validation issues
- **.yamllint** - yamllint configuration file with project-specific rules

## Quick Start

### Run Full Validation

```bash
python3 validate_yaml.py
```

This will:
1. Install yamllint if not already installed
2. Find all .yaml and .yml files in the repository
3. Validate each file against yamllint rules
4. Display detailed errors for each file
5. Show a summary of results

### Generate Summary Report

```bash
python3 validate_yaml_summary.py
```

This provides:
- Total file counts (valid, warnings, errors)
- Breakdown of error types and their frequencies
- Top 10 files with most issues
- Recommendations for fixes

## Current Validation Results

After applying the custom .yamllint configuration:

- **Total YAML files**: 226
- **Valid files**: 107 (47%)
- **Files with errors**: 119 (53%)

### Top Error Types

1. **indentation** (199 occurrences) - Structural indentation issues
2. **syntax** (75 occurrences) - YAML syntax errors
3. **new-line-at-end-of-file** (70 occurrences) - Missing newline at EOF
4. **line-length** (warnings only) - Lines exceeding 120 characters

## yamllint Configuration

The `.yamllint` configuration has been customized for this project:

- **Line length**: Max 120 characters (warning level)
- **Document start**: Not required (common in CI/CD files)
- **Truthy values**: Allows `true`, `false`, `yes`, `no`, `on`, `off`
- **Indentation**: 2 spaces with sequence indentation
- **Braces/Brackets**: Flexible spacing allowed

## How to Fix Common Issues

### 1. Missing Newline at End of File

Add a blank line at the end of the file:

```bash
# Automatically fix for a single file
echo "" >> path/to/file.yaml
```

### 2. Indentation Errors

Review the YAML structure carefully. Common fixes:
- Ensure consistent 2-space indentation
- Check that list items are properly indented
- Verify nested structures align correctly

### 3. Syntax Errors

These require manual review. Common issues:
- Missing colons after keys
- Incorrect use of quotes
- Invalid character sequences
- Duplicate keys

### 4. Long Lines

Options:
1. Break long strings across multiple lines using YAML multi-line syntax
2. Use line continuation with `>` or `|` operators
3. Adjust .yamllint config to allow longer lines if needed

## Integration with CI/CD

You can add YAML validation to your CI/CD pipeline:

```yaml
- name: Validate YAML files
  run: |
    pip install yamllint
    python3 validate_yaml.py
```

## Troubleshooting

### yamllint Not Found

Install yamllint:
```bash
pip install yamllint
# or
pip3 install yamllint
```

### Too Many Errors

1. Review `.yamllint` configuration
2. Adjust rules as needed for your project
3. Focus on fixing critical errors (syntax, indentation) first
4. Warnings can be addressed incrementally

### Custom Rules

Edit `.yamllint` to customize validation rules:

```yaml
rules:
  line-length:
    max: 150  # Increase if needed
    level: warning

  indentation:
    spaces: 2
    indent-sequences: true
```

## Files with Most Issues

Top files requiring attention:
1. `helm/templates/observability.yaml` (47 issues)
2. `helm/templates/slo.yaml` (31 issues)
3. `marketplace/deployer.yaml` (26 issues)
4. `helm/templates/sso.yaml` (18 issues)
5. `infrastructure/kubernetes/helm/craftplan/values.yaml` (16 issues)

## Resources

- [yamllint Documentation](https://yamllint.readthedocs.io/)
- [YAML Specification](https://yaml.org/spec/)
- [yamllint Rules Reference](https://yamllint.readthedocs.io/en/stable/rules.html)

## Maintenance

Run validation regularly:
- Before committing changes
- As part of pre-commit hooks
- In CI/CD pipeline
- During code reviews

Consider adding to `.pre-commit-config.yaml`:

```yaml
- repo: https://github.com/adrienverge/yamllint
  rev: v1.35.1
  hooks:
    - id: yamllint
      args: [-c=.yamllint]
```
