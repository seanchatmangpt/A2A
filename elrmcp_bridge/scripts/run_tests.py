#!/usr/bin/env python3
"""
Comprehensive test runner for elrmcp_bridge
"""

import subprocess
import sys
import argparse
from pathlib import Path
import time
import json


def run_tests(test_type="all", verbose=False, coverage=False, parallel=False):
    """Run tests with different configurations"""

    # Get the project root
    project_root = Path(__file__).parent.parent
    test_dir = project_root / "tests"

    print(f"🧪 Running {test_type} tests for elrmcp_bridge")
    print(f"📁 Test directory: {test_dir}")
    print("=" * 60)

    # Base pytest command
    cmd = ["python", "-m", "pytest"]

    if verbose:
        cmd.extend(["-v", "-s"])

    # Add coverage options
    if coverage:
        cmd.extend([
            "--cov=src",
            "--cov-report=term-missing",
            "--cov-report=html:htmlcov",
            "--cov-report=xml",
            "--cov-fail-under=80"
        ])

    # Add parallel execution
    if parallel:
        cmd.extend(["-n", "auto"])

    # Add specific test type
    if test_type == "unit":
        cmd.extend(["-m", "not integration and not slow"])
    elif test_type == "integration":
        cmd.extend(["-m", "integration"])
    elif test_type == "slow":
        cmd.extend(["-m", "slow"])
    elif test_type == "smoke":
        cmd.extend(["-m", "smoke"])
    elif test_type == "all":
        pass  # Run all tests
    else:
        print(f"❌ Unknown test type: {test_type}")
        return False

    # Add specific test files or directories
    if test_type == "specific":
        if len(sys.argv) > 3:
            cmd.extend(sys.argv[3:])  # Additional test files/dirs
        else:
            print("❌ Please specify test files/directories for 'specific' test type")
            return False

    # Add test directory
    cmd.append("tests/")

    print(f"🚀 Running command: {' '.join(cmd)}")
    print("=" * 60)

    # Run tests
    start_time = time.time()
    result = subprocess.run(cmd, cwd=project_root)
    end_time = time.time()

    duration = end_time - start_time
    print(f"⏱️ Test duration: {duration:.2f} seconds")

    if result.returncode == 0:
        print("✅ All tests passed!")
        return True
    else:
        print("❌ Some tests failed!")
        return False


def run_linting():
    """Run code linting checks"""
    print("🔍 Running linting checks...")
    print("=" * 60)

    project_root = Path(__file__).parent.parent

    # Run ruff
    print("📝 Running ruff...")
    ruff_result = subprocess.run([
        "python", "-m", "ruff", "check", "src/", "tests/"
    ], cwd=project_root)

    # Run black (check only)
    print("🎨 Running black check...")
    black_result = subprocess.run([
        "python", "-m", "black", "--check", "src/", "tests/"
    ], cwd=project_root)

    # Run mypy
    print("🔡 Running mypy...")
    mypy_result = subprocess.run([
        "python", "-m", "mypy", "src/", "tests/"
    ], cwd=project_root)

    all_passed = all(result.returncode == 0 for result in [ruff_result, black_result, mypy_result])

    if all_passed:
        print("✅ All linting checks passed!")
    else:
        print("❌ Some linting checks failed!")

    return all_passed


def run_security_scan():
    """Run security scan"""
    print("🔒 Running security scan...")
    print("=" * 60)

    project_root = Path(__file__).parent.parent

    # Run bandit
    result = subprocess.run([
        "python", "-m", "bandit", "-r", "src/", "-f", "json", "-o", "bandit-report.json"
    ], cwd=project_root)

    # Check if report was created
    report_path = project_root / "bandit-report.json"
    if report_path.exists():
        with open(report_path, 'r') as f:
            report = json.load(f)

        if report.get("results"):
            print("⚠️ Security issues found:")
            for issue in report["results"]:
                print(f"  - {issue['test_id']}: {issue['issue_text']}")
        else:
            print("✅ No security issues found!")

        # Clean up report
        report_path.unlink()
    else:
        print("✅ No security issues found!")

    return result.returncode == 0


def generate_test_report():
    """Generate comprehensive test report"""
    print("📊 Generating test report...")
    print("=" * 60)

    project_root = Path(__file__).parent.parent

    # Run tests with coverage
    cmd = [
        "python", "-m", "pytest",
        "--cov=src",
        "--cov-report=term-missing",
        "--cov-report=html:htmlcov",
        "--cov-report=xml",
        "--cov-fail-under=80",
        "tests/",
        "-v"
    ]

    result = subprocess.run(cmd, cwd=project_root)

    if result.returncode == 0:
        print("✅ Test report generated successfully!")
        print("📄 HTML report: htmlcov/index.html")
        print("📄 XML report: coverage.xml")
        return True
    else:
        print("❌ Failed to generate test report!")
        return False


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Run tests for elrmcp_bridge")
    parser.add_argument(
        "type",
        choices=["all", "unit", "integration", "slow", "smoke", "specific"],
        help="Type of tests to run"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Run tests in verbose mode"
    )
    parser.add_argument(
        "-c", "--coverage",
        action="store_true",
        help="Run tests with coverage report"
    )
    parser.add_argument(
        "-p", "--parallel",
        action="store_true",
        help="Run tests in parallel"
    )
    parser.add_argument(
        "--lint",
        action="store_true",
        help="Run linting checks"
    )
    parser.add_argument(
        "--security",
        action="store_true",
        help="Run security scan"
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="Generate comprehensive test report"
    )

    args = parser.parse_args()

    # Run tests
    success = run_tests(args.type, args.verbose, args.coverage, args.parallel)

    # Run additional checks if requested
    if args.lint:
        success = run_linting() and success

    if args.security:
        success = run_security_scan() and success

    if args.report:
        success = generate_test_report() and success

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()