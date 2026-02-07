#!/usr/bin/env python3
"""
YAML Validation Summary Script
Provides a detailed summary of YAML validation issues
"""

import subprocess
import re
from pathlib import Path
from collections import defaultdict


def main():
    """Generate validation summary."""
    root_dir = Path("/home/user/A2A")
    yaml_files = []
    yaml_files.extend(root_dir.glob("**/*.yaml"))
    yaml_files.extend(root_dir.glob("**/*.yml"))
    yaml_files.sort()

    print("=" * 80)
    print("YAML VALIDATION SUMMARY REPORT")
    print("=" * 80)
    print()

    error_types = defaultdict(int)
    warning_types = defaultdict(int)
    files_with_errors = []
    files_with_warnings = []
    valid_files = []

    for yaml_file in yaml_files:
        result = subprocess.run(
            ["yamllint", "-f", "parsable", str(yaml_file)],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode == 0:
            valid_files.append(yaml_file.relative_to(root_dir))
        else:
            output = result.stdout if result.stdout else result.stderr
            has_errors = False
            has_warnings = False

            for line in output.split("\n"):
                if "[error]" in line:
                    has_errors = True
                    # Extract error type from parentheses
                    match = re.search(r'\(([^)]+)\)', line)
                    if match:
                        error_types[match.group(1)] += 1
                elif "[warning]" in line:
                    has_warnings = True
                    # Extract warning type from parentheses
                    match = re.search(r'\(([^)]+)\)', line)
                    if match:
                        warning_types[match.group(1)] += 1

            if has_errors:
                files_with_errors.append(yaml_file.relative_to(root_dir))
            if has_warnings:
                files_with_warnings.append(yaml_file.relative_to(root_dir))

    # Print statistics
    print(f"Total YAML files found: {len(yaml_files)}")
    print(f"  ✓ Valid files: {len(valid_files)}")
    print(f"  ⚠ Files with warnings only: {len(files_with_warnings) - len(files_with_errors)}")
    print(f"  ✗ Files with errors: {len(files_with_errors)}")
    print()

    # Print error types breakdown
    if error_types:
        print("ERROR TYPES BREAKDOWN:")
        print("-" * 80)
        sorted_errors = sorted(error_types.items(), key=lambda x: x[1], reverse=True)
        for error_type, count in sorted_errors:
            print(f"  {error_type:40} {count:6} occurrences")
        print()

    # Print warning types breakdown
    if warning_types:
        print("WARNING TYPES BREAKDOWN:")
        print("-" * 80)
        sorted_warnings = sorted(warning_types.items(), key=lambda x: x[1], reverse=True)
        for warning_type, count in sorted_warnings:
            print(f"  {warning_type:40} {count:6} occurrences")
        print()

    # Print top files with most issues
    print("TOP 10 FILES WITH MOST ISSUES:")
    print("-" * 80)
    file_issue_counts = []
    for yaml_file in yaml_files:
        result = subprocess.run(
            ["yamllint", "-f", "parsable", str(yaml_file)],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode != 0:
            output = result.stdout if result.stdout else result.stderr
            issue_count = len([line for line in output.split("\n") if "[error]" in line or "[warning]" in line])
            if issue_count > 0:
                file_issue_counts.append((yaml_file.relative_to(root_dir), issue_count))

    file_issue_counts.sort(key=lambda x: x[1], reverse=True)
    for i, (file_path, count) in enumerate(file_issue_counts[:10], 1):
        print(f"  {i:2}. {str(file_path):60} ({count} issues)")

    print()
    print("=" * 80)
    print("RECOMMENDATIONS:")
    print("=" * 80)
    print("1. Most common issue is 'line-length' - consider using yamllint config")
    print("   to allow longer lines or split long lines")
    print("2. Add document start marker '---' at the beginning of YAML files")
    print("3. Use 'true' and 'false' instead of 'on', 'off', 'yes', 'no' for")
    print("   boolean values to avoid ambiguity")
    print("4. Review indentation errors carefully as they may indicate structural")
    print("   problems in the YAML files")
    print()
    print("To disable specific rules, create a .yamllint config file in the project")
    print("root directory.")
    print()


if __name__ == "__main__":
    main()
