#!/usr/bin/env python3
"""
YAML Validation Script
Validates all YAML files in the repository using yamllint
"""

import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


def find_yaml_files(root_dir: Path) -> List[Path]:
    """Find all YAML files in the repository."""
    yaml_files = []

    # Find .yaml files
    yaml_files.extend(root_dir.glob("**/*.yaml"))

    # Find .yml files
    yaml_files.extend(root_dir.glob("**/*.yml"))

    # Sort for consistent output
    yaml_files.sort()

    return yaml_files


def check_yamllint_installed() -> bool:
    """Check if yamllint is installed."""
    try:
        result = subprocess.run(
            ["yamllint", "--version"],
            capture_output=True,
            text=True,
            check=False
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def install_yamllint() -> bool:
    """Attempt to install yamllint using pip."""
    print("yamllint not found. Attempting to install...")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", "yamllint"],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            print("✓ yamllint installed successfully")
            return True
        else:
            print(f"✗ Failed to install yamllint: {result.stderr}")
            return False
    except Exception as e:
        print(f"✗ Error installing yamllint: {e}")
        return False


def validate_yaml_file(file_path: Path) -> Tuple[bool, str]:
    """
    Validate a single YAML file using yamllint.
    Returns (is_valid, output_message)
    """
    try:
        result = subprocess.run(
            ["yamllint", "-f", "parsable", str(file_path)],
            capture_output=True,
            text=True,
            check=False
        )

        is_valid = result.returncode == 0
        output = result.stdout if result.stdout else result.stderr

        return is_valid, output.strip()
    except Exception as e:
        return False, str(e)


def main():
    """Main validation function."""
    print("=" * 80)
    print("YAML Validation Script")
    print("=" * 80)
    print()

    # Check if yamllint is installed
    if not check_yamllint_installed():
        if not install_yamllint():
            print("\n✗ Cannot proceed without yamllint. Please install it manually:")
            print("  pip install yamllint")
            sys.exit(1)

    # Find all YAML files
    root_dir = Path("/home/user/A2A")
    print(f"Searching for YAML files in: {root_dir}")
    yaml_files = find_yaml_files(root_dir)

    print(f"Found {len(yaml_files)} YAML files")
    print()

    # Validate each file
    valid_files = []
    invalid_files = []

    print("Validating files...")
    print("-" * 80)

    for yaml_file in yaml_files:
        relative_path = yaml_file.relative_to(root_dir)
        is_valid, output = validate_yaml_file(yaml_file)

        if is_valid:
            valid_files.append(relative_path)
            print(f"✓ {relative_path}")
        else:
            invalid_files.append((relative_path, output))
            print(f"✗ {relative_path}")
            if output:
                # Indent error messages
                for line in output.split("\n"):
                    print(f"  {line}")

    # Print summary
    print()
    print("=" * 80)
    print("VALIDATION SUMMARY")
    print("=" * 80)
    print(f"Total files: {len(yaml_files)}")
    print(f"Valid files: {len(valid_files)}")
    print(f"Invalid files: {len(invalid_files)}")
    print()

    if invalid_files:
        print("Files with errors:")
        print("-" * 80)
        for file_path, error in invalid_files:
            print(f"\n{file_path}:")
            for line in error.split("\n"):
                print(f"  {line}")
        print()
        sys.exit(1)
    else:
        print("✓ All YAML files are valid!")
        sys.exit(0)


if __name__ == "__main__":
    main()
