#!/usr/bin/env python3
"""
YAML Auto-Fix Script
Automatically fixes simple YAML issues like missing newlines at end of file
"""

import sys
from pathlib import Path
from typing import List


def find_yaml_files(root_dir: Path) -> List[Path]:
    """Find all YAML files in the repository."""
    yaml_files = []
    yaml_files.extend(root_dir.glob("**/*.yaml"))
    yaml_files.extend(root_dir.glob("**/*.yml"))
    yaml_files.sort()
    return yaml_files


def fix_newline_at_end(file_path: Path) -> bool:
    """
    Add a newline at the end of file if missing.
    Returns True if file was modified.
    """
    try:
        with open(file_path, 'rb') as f:
            content = f.read()

        if not content:
            return False

        # Check if file ends with newline
        if content and not content.endswith(b'\n'):
            with open(file_path, 'ab') as f:
                f.write(b'\n')
            return True

        return False
    except Exception as e:
        print(f"  Error processing {file_path}: {e}")
        return False


def fix_trailing_spaces(file_path: Path) -> bool:
    """
    Remove trailing spaces from lines.
    Returns True if file was modified.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        modified = False
        new_lines = []

        for line in lines:
            # Remove trailing spaces but keep newline
            stripped = line.rstrip(' \t')
            if stripped != line.rstrip('\n\r'):
                modified = True
            # Preserve the original line ending
            if line.endswith('\n'):
                new_lines.append(stripped + '\n')
            else:
                new_lines.append(stripped)

        if modified:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)

        return modified
    except Exception as e:
        print(f"  Error processing {file_path}: {e}")
        return False


def main():
    """Main fix function."""
    print("=" * 80)
    print("YAML Auto-Fix Script")
    print("=" * 80)
    print()
    print("This script will automatically fix:")
    print("  - Missing newlines at end of files")
    print("  - Trailing spaces on lines")
    print()

    root_dir = Path("/home/user/A2A")
    yaml_files = find_yaml_files(root_dir)

    print(f"Found {len(yaml_files)} YAML files")
    print()

    response = input("Do you want to proceed with fixes? (yes/no): ")
    if response.lower() not in ['yes', 'y']:
        print("Aborted.")
        sys.exit(0)

    print()
    print("Fixing files...")
    print("-" * 80)

    newline_fixed = 0
    trailing_fixed = 0

    for yaml_file in yaml_files:
        relative_path = yaml_file.relative_to(root_dir)
        fixed_newline = False
        fixed_trailing = False

        # Fix missing newline at end
        if fix_newline_at_end(yaml_file):
            newline_fixed += 1
            fixed_newline = True

        # Fix trailing spaces
        if fix_trailing_spaces(yaml_file):
            trailing_fixed += 1
            fixed_trailing = True

        if fixed_newline or fixed_trailing:
            fixes = []
            if fixed_newline:
                fixes.append("newline")
            if fixed_trailing:
                fixes.append("trailing-spaces")
            print(f"✓ {relative_path} - Fixed: {', '.join(fixes)}")

    print()
    print("=" * 80)
    print("FIX SUMMARY")
    print("=" * 80)
    print(f"Total files processed: {len(yaml_files)}")
    print(f"Files with newline fixes: {newline_fixed}")
    print(f"Files with trailing space fixes: {trailing_fixed}")
    print()

    if newline_fixed > 0 or trailing_fixed > 0:
        print("✓ Auto-fixes completed successfully!")
        print()
        print("Next steps:")
        print("  1. Run validate_yaml.py to check remaining issues")
        print("  2. Review and commit the changes")
        print("  3. Address remaining indentation and syntax errors manually")
    else:
        print("No fixes needed - all files are clean!")

    sys.exit(0)


if __name__ == "__main__":
    main()
