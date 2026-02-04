#!/usr/bin/env python3
"""
Demo script for ggen configuration and generation
Shows how to use the comprehensive ggen.toml configuration
"""

import os
import sys
import subprocess
import json
from pathlib import Path

def print_banner():
    """Print demo banner"""
    print("=" * 60)
    print("🚀 A2A GGen Configuration Demo")
    print("=" * 60)
    print()

def show_config_overview():
    """Show configuration overview"""
    print("📋 Configuration Overview:")
    print("   🎯 Project: a2a-ggen v0.2.0")
    print("   📚 Ontologies: 3 source files")
    print("   🔧 Templates: 4 directories")
    print("   ☁️  Cloud: Docker, Kubernetes, Helm")
    print("   🔥 HotCI: Enabled")
    print("   📊 Metrics: Enabled")
    print("   🛡️  Security: Enabled")
    print()

def show_generation_phases():
    """Show generation phases"""
    print("🔄 Generation Phases:")
    phases = [
        ("ontology", "Load and validate ontologies", []),
        ("sparql", "Execute SPARQL queries", ["ontology"]),
        ("erlang", "Generate Erlang modules and configs", ["sparql"]),
        ("docker", "Generate Docker configurations", ["sparql"]),
        ("k8s", "Generate Kubernetes manifests", ["sparql"]),
        ("helm", "Generate Helm charts", ["sparql"]),
        ("validation", "Validate generated files", ["erlang", "docker", "k8s", "helm"]),
        ("hooks", "Run post-generation hooks", ["validation"])
    ]

    for phase, desc, deps in phases:
        deps_str = f" (deps: {', '.join(deps)})" if deps else ""
        print(f"   {phase:12} → {desc}{deps_str}")
    print()

def show_output_structure():
    """Show output directory structure"""
    print("📁 Output Structure:")
    structure = [
        "generated/erlang/src/",
        "generated/erlang/config/",
        "generated/docker/",
        "generated/k8s/",
        "generated/helm/a2a-erl/",
        "generated/helm/a2a-erl/templates/",
        "generated/tests/"
    ]

    for path in structure:
        print(f"   📂 {path}")
    print()

def show_cloud_configs():
    """Show cloud configurations"""
    print("☁️  Cloud Provider Configurations:")
    print()

    print("   🐳 Docker:")
    print("      - Multi-stage build enabled")
    print("      - Base image: erlang:27-alpine")
    print("      - Health checks: 30s interval")
    print()

    print("   ☸️  Kubernetes:")
    print("      - Namespace: a2a-system")
    print("      - Replicas: 2")
    print("      - Service: ClusterIP")
    print("      - Resources: 100m/128Mi requests, 500m/256Mi limits")
    print("      - Health probes: Liveness & Readiness")
    print()

    print("   🎯 Helm:")
    print("      - Chart: a2a-erl v0.2.0")
    print("      - Values: replicaCount=2, service.type=ClusterIP")
    print("      - Monitoring: Prometheus annotations")
    print("      - Security: Pod security contexts")
    print()

def show_hotci_features():
    """Show HotCI features"""
    print("🔥 HotCI Integration:")
    print("   - Hot code upgrade testing: Enabled")
    print("   - Test types: upgrade, downgrade, consistency, performance")
    print("   - Upgrade monitor: 30s interval")
    print("   - Rollback timeout: 5 minutes")
    print("   - Consistency checks: 60s interval")
    print()

def show_security_features():
    """Show security features"""
    print("🛡️  Security Features:")
    print("   - Secret scanning: Enabled")
    print("   - Vulnerability scanning: Enabled")
    print("   - Dependency scanning: Enabled")
    print("   - Code analysis: Enabled")
    print("   - Security rules: 4 rules defined")
    print()

def show_validation_rules():
    """Show validation rules"""
    print("✅ Validation Rules:")
    rules = [
        ("erlang-syntax", "Validate Erlang syntax", "erlc -o /tmp {file}"),
        ("yaml-syntax", "Validate YAML syntax", "yq eval . {file}"),
        ("required-files", "Ensure required files are generated", "file existence check"),
        ("module-naming", "Validate module naming conventions", "regex check")
    ]

    for name, desc, cmd in rules:
        print(f"   {name:20} → {desc}")
    print()

def show_hooks():
    """Show hook configurations"""
    print("🪝 Hook Configurations:")
    print()

    print("   Pre-generation:")
    print("   - 'echo Starting A2A code generation...'")
    print("   - 'mkdir -p logs'")
    print()

    print("   Post-generation:")
    print("   - 'echo Code generation completed successfully!'")
    print("   - Count and log generated files")
    print("   - Git integration (add and status)")
    print()

def show_ontologies():
    """Show ontology files"""
    print("📚 Ontology Sources:")
    ontology_files = [
        "ontology/erlang-otp.ttl",
        "ontology/cloud-infrastructure.ttl",
        "ontology/a2a-spec.ttl"
    ]

    for file in ontology_files:
        if os.path.exists(file):
            print(f"   ✅ {file}")
        else:
            print(f"   ❌ {file}")
    print()

def show_templates():
    """Show template files"""
    print("🔧 Template Files:")
    template_dirs = [
        "templates/erlang",
        "templates/docker",
        "templates/k8s",
        "templates/helm"
    ]

    for dir_path in template_dirs:
        if os.path.exists(dir_path):
            tera_files = list(Path(dir_path).rglob("*.tera"))
            print(f"   ✅ {dir_path} ({len(tera_files)} .tera files)")
        else:
            print(f"   ❌ {dir_path}")
    print()

def show_sparql_queries():
    """Show SPARQL query files"""
    print("🔍 SPARQL Queries:")
    query_files = [
        "queries/extract-erlang-modules.sparql",
        "queries/extract-task-states.sparql",
        "queries/extract-records.sparql",
        "queries/extract-k8s-resources.sparql",
        "queries/extract-docker-config.sparql"
    ]

    for file in query_files:
        if os.path.exists(file):
            print(f"   ✅ {file}")
        else:
            print(f"   ❌ {file}")
    print()

def demo_generation_commands():
    """Show example generation commands"""
    print("🚀 Example Generation Commands:")
    print()

    commands = [
        ("ggen generate all", "Generate all components"),
        ("ggen generate erlang", "Generate only Erlang modules"),
        ("ggen generate docker", "Generate only Docker configs"),
        ("ggen generate k8s", "Generate only Kubernetes manifests"),
        ("ggen generate helm", "Generate only Helm charts"),
        ("ggen validate generated/", "Validate generated output"),
        ("ggen generate all --output-dir ./my-app", "Generate to custom directory"),
        ("ggen generate all --validate", "Generate and validate")
    ]

    for cmd, desc in commands:
        print(f"   {cmd:40} → {desc}")
    print()

def show_file_permissions():
    """Show file permission settings"""
    print("🔐 File Permissions:")
    permissions = {
        "erl": "644",
        "yaml": "644",
        "md": "644",
        "txt": "644"
    }

    for ext, perm in permissions.items():
        print(f"   .{ext:4} files → {perm} permissions")
    print()

def show_performance_settings():
    """Show performance settings"""
    print("⚡ Performance Settings:")
    print("   - Parallel generation: 4 workers")
    print("   - Max concurrent tasks: 4")
    print("   - Cache TTL: 300 seconds")
    print("   - Max memory: 512 MB")
    print("   - GC threshold: 100 MB")
    print()

def show_metrics_logging():
    """Show metrics and logging settings"""
    print("📊 Metrics & Logging:")
    print("   - Metrics enabled: True")
    print("   - Track generation time: True")
    print("   - Track file count: True")
    print("   - Track template usage: True")
    print("   - Output file: metrics/ggen_metrics.json")
    print("   - Log level: info")
    print("   - Log format: json")
    print("   - Log file: logs/ggen.log")
    print()

def main():
    """Main demo function"""
    print_banner()

    show_config_overview()
    show_generation_phases()
    show_output_structure()
    show_cloud_configs()
    show_hotci_features()
    show_security_features()
    show_validation_rules()
    show_hooks()
    show_ontologies()
    show_templates()
    show_sparql_queries()
    show_file_permissions()
    show_performance_settings()
    show_metrics_logging()
    demo_generation_commands()

    print("=" * 60)
    print("✅ Demo completed successfully!")
    print("🎯 Ready for A2A code generation!")
    print("=" * 60)

if __name__ == "__main__":
    main()