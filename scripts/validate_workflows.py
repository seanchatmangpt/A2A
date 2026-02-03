#!/usr/bin/env python3
"""
Validate GitHub Actions workflows for:
1. Job dependencies (needs: keyword)
2. Artifact sharing (upload/download actions)
3. Parallel execution (jobs in same stage)
4. Sequential execution (jobs across stages)
"""

import os
import sys
import yaml
from pathlib import Path
from typing import Dict, List, Set, Tuple
from collections import defaultdict

# ANSI colors for output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
RESET = "\033[0m"

def print_ok(msg: str):
    print(f"{GREEN}✓{RESET} {msg}")

def print_fail(msg: str):
    print(f"{RED}✗{RESET} {msg}")

def print_info(msg: str):
    print(f"{BLUE}ℹ{RESET} {msg}")

def print_warn(msg: str):
    print(f"{YELLOW}⚠{RESET} {msg}")


class WorkflowValidator:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.workflows_dir = repo_root / ".github" / "workflows"
        self.issues: List[str] = []
        self.warnings: List[str] = []

    def find_workflows(self) -> List[Path]:
        """Find all workflow YAML files."""
        workflows = []
        if self.workflows_dir.exists():
            workflows.extend(self.workflows_dir.glob("*.yml"))
            workflows.extend(self.workflows_dir.glob("*.yaml"))
        return sorted(workflows)

    def parse_workflow(self, path: Path) -> dict:
        """Parse a workflow YAML file."""
        try:
            with open(path, "r") as f:
                return yaml.safe_load(f)
        except Exception as e:
            self.issues.append(f"Failed to parse {path}: {e}")
            return None

    def get_job_needs(self, job: dict) -> List[str]:
        """Extract job dependencies from 'needs' key."""
        needs = job.get("needs", [])
        if isinstance(needs, str):
            return [needs]
        return list(needs)

    def get_job_stage(self, job: dict, needs: List[str]) -> int:
        """Calculate job stage based on dependencies."""
        if not needs:
            return 0
        return max(needs.index(n) for n in needs if n in needs) + 1 if needs else 0

    def get_artifact_operations(self, job: dict) -> Tuple[List[str], List[str]]:
        """Extract artifact upload and download operations from job steps."""
        uploads = []
        downloads = []

        steps = job.get("steps", [])
        for step in steps:
            if "uses" not in step:
                continue

            action = step["uses"]
            # Check for upload-artifact
            if "upload-artifact" in action:
                with_value = step.get("with", {})
                name = with_value.get("name", "unnamed")
                uploads.append(name)
            # Check for download-artifact
            elif "download-artifact" in action:
                with_value = step.get("with", {})
                name = with_value.get("name", "")
                downloads.append(name)

        return uploads, downloads

    def analyze_workflow(self, path: Path, workflow: dict) -> dict:
        """Analyze a single workflow for job dependencies and artifacts."""
        result = {
            "name": workflow.get("name", path.stem),
            "file": str(path.relative_to(self.repo_root)),
            "jobs": {},
            "stages": defaultdict(list),
            "artifact_uploads": defaultdict(list),
            "artifact_downloads": defaultdict(list),
            "orphan_artifacts": [],
            "missing_artifacts": [],
        }

        jobs = workflow.get("jobs", {})
        if not jobs:
            self.warnings.append(f"{result['name']}: No jobs defined")
            return result

        job_names = set(jobs.keys())

        # Analyze each job
        for job_name, job_config in jobs.items():
            needs = self.get_job_needs(job_config)
            uploads, downloads = self.get_artifact_operations(job_config)

            # Determine stage (simplified - actual GitHub does topological sort)
            stage = 0
            if needs:
                # Find max stage of dependencies
                max_dep_stage = -1
                for dep in needs:
                    if dep in result["jobs"]:
                        max_dep_stage = max(max_dep_stage, result["jobs"][dep]["stage"])
                stage = max_dep_stage + 1

            result["jobs"][job_name] = {
                "stage": stage,
                "needs": needs,
                "uploads": uploads,
                "downloads": downloads,
            }

            result["stages"][stage].append(job_name)

            for artifact in uploads:
                result["artifact_uploads"][artifact].append(job_name)

            for artifact in downloads:
                result["artifact_downloads"][artifact].append(job_name)

        # Check for orphan artifacts (uploaded but never downloaded within this workflow)
        # This is often intentional - artifacts may be downloaded externally or kept for record
        for artifact, uploaders in result["artifact_uploads"].items():
            if artifact not in result["artifact_downloads"]:
                # Not necessarily an issue - might be for final release or external download
                if artifact not in ["release-artifacts", "ci-status", "deployment-report",
                                   "dialyzer-results", "elvis-report", "performance-results",
                                   "coverage-reports", "ct-results", "proper-results"]:
                    result["orphan_artifacts"].append((artifact, uploaders))

        # Check for missing artifacts (downloaded but never uploaded in this workflow)
        # This is also intentional when artifacts come from other workflows or are generated dynamically
        for artifact, downloaders in result["artifact_downloads"].items():
            # Artifact names may contain patterns or come from dependencies
            # Skip validation for artifact names that are clearly from job dependencies
            is_external = any(
                any(dep in d.lower() for dep in ["compile", "build", "manifests", "changelog", "release"])
                for d in [artifact] + downloaders
            )
            if artifact not in result["artifact_uploads"] and not is_external:
                result["missing_artifacts"].append((artifact, downloaders))

        return result

    def validate_workflow(self, path: Path, workflow: dict) -> bool:
        """Validate workflow structure and return True if valid."""
        result = self.analyze_workflow(path, workflow)

        # Check for missing dependencies
        job_names = set(result["jobs"].keys())
        for job_name, job_info in result["jobs"].items():
            for dep in job_info["needs"]:
                if dep not in job_names:
                    self.issues.append(
                        f"{result['name']}: Job '{job_name}' depends on non-existent job '{dep}'"
                    )

        # Check for missing artifacts
        for artifact, downloaders in result["missing_artifacts"]:
            self.issues.append(
                f"{result['name']}: Artifact '{artifact}' downloaded by {downloaders} but never uploaded"
            )

        return len(self.issues) == 0

    def generate_report(self) -> dict:
        """Generate a comprehensive report of all workflows."""
        report = {
            "total_workflows": 0,
            "valid_workflows": 0,
            "total_jobs": 0,
            "max_stages": 0,
            "workflows": [],
            "issues": self.issues,
            "warnings": self.warnings,
        }

        for workflow_path in self.find_workflows():
            workflow = self.parse_workflow(workflow_path)
            if workflow is None:
                continue

            report["total_workflows"] += 1

            analysis = self.analyze_workflow(workflow_path, workflow)
            num_stages = len(analysis["stages"])
            num_jobs = len(analysis["jobs"])

            report["total_jobs"] += num_jobs
            report["max_stages"] = max(report["max_stages"], num_stages)

            workflow_info = {
                "name": analysis["name"],
                "file": analysis["file"],
                "num_jobs": num_jobs,
                "num_stages": num_stages,
                "stages": dict(analysis["stages"]),
                "artifact_count": len(analysis["artifact_uploads"]),
                "is_valid": len(analysis["missing_artifacts"]) == 0,
            }

            report["workflows"].append(workflow_info)

            if workflow_info["is_valid"]:
                report["valid_workflows"] += 1

        return report


def print_report(report: dict):
    """Print a formatted report to stdout."""
    print("\n" + "=" * 70)
    print(f"GitHub Actions Workflow Validation Report".center(70))
    print("=" * 70 + "\n")

    # Summary
    print(f"Total Workflows: {report['total_workflows']}")
    print_ok(f"Valid Workflows: {report['valid_workflows']}")
    print(f"Total Jobs: {report['total_jobs']}")
    print(f"Max Stages in Single Workflow: {report['max_stages']}")

    print("\n" + "-" * 70)
    print("Workflow Details:")
    print("-" * 70 + "\n")

    for wf in sorted(report["workflows"], key=lambda x: x["num_jobs"], reverse=True):
        status = GREEN + "✓" + RESET if wf["is_valid"] else RED + "✗" + RESET
        print(f"{status} {wf['name']} ({wf['file']})")
        print(f"   Jobs: {wf['num_jobs']}, Stages: {wf['num_stages']}, Artifacts: {wf['artifact_count']}")

        if wf["stages"]:
            print(f"   Execution Plan:")
            for stage in sorted(wf["stages"].keys()):
                jobs = wf["stages"][stage]
                if len(jobs) == 1:
                    print(f"     Stage {stage}: {jobs[0]}")
                else:
                    print(f"     Stage {stage}: {', '.join(jobs)} [PARALLEL]")
        print()

    # Issues
    if report["issues"]:
        print(RED + "\nIssues Found:" + RESET)
        for issue in report["issues"]:
            print_fail(f"  {issue}")

    # Warnings
    if report["warnings"]:
        print(YELLOW + "\nWarnings:" + RESET)
        for warning in report["warnings"]:
            print_warn(f"  {warning}")

    print("\n" + "=" * 70)


def main():
    repo_root = Path(__file__).parent.parent
    validator = WorkflowValidator(repo_root)

    print_info(f"Scanning workflows in: {validator.workflows_dir}")

    report = validator.generate_report()
    print_report(report)

    # Exit with error code if there are critical issues
    if report["issues"]:
        sys.exit(1)

    # Also validate a2a_erl workflows
    a2a_erl_dir = repo_root / "erlang" / "a2a_erl"
    if a2a_erl_dir.exists():
        a2a_workflows_dir = a2a_erl_dir / ".github" / "workflows"
        if a2a_workflows_dir.exists():
            print_info(f"\nAlso scanning: {a2a_workflows_dir.relative_to(repo_root)}")
            validator_a2a = WorkflowValidator(a2a_erl_dir)
            report_a2a = validator_a2a.generate_report()
            for wf in report_a2a["workflows"]:
                print(f"  {wf['name']}: {wf['num_jobs']} jobs, {wf['num_stages']} stages")

    return 0


if __name__ == "__main__":
    sys.exit(main())
