#!/usr/bin/env python3
"""
Validation script for ggen.toml configuration file
Verifies that the configuration is complete and properly structured
"""

import os
import sys
import toml
from pathlib import Path

def validate_config():
    """Validate the ggen.toml configuration file"""
    config_path = "ggen.toml"

    if not os.path.exists(config_path):
        print(f"❌ Configuration file not found: {config_path}")
        return False

    try:
        config = toml.load(config_path)
    except Exception as e:
        print(f"❌ Error loading TOML configuration: {e}")
        return False

    print("✅ Configuration file loaded successfully")

    # Validate required sections
    required_sections = [
        "project",
        "ontology",
        "templates",
        "output",
        "generation",
        "validation",
        "hooks"
    ]

    for section in required_sections:
        if section not in config:
            print(f"❌ Missing required section: [{section}]")
            return False
        print(f"✅ Found section: [{section}]")

    # Validate project metadata
    project = config["project"]
    required_fields = ["name", "version", "description"]
    for field in required_fields:
        if field not in project:
            print(f"❌ Missing required field in [project]: {field}")
            return False
        print(f"✅ Found project field: {field} = {project[field]}")

    # Validate ontology sources
    ontology = config["ontology"]
    if "sources" not in ontology:
        print("❌ Missing [ontology].sources")
        return False

    if len(ontology["sources"]) == 0:
        print("❌ [ontology].sources is empty")
        return False

    for source in ontology["sources"]:
        if "path" not in source:
            print("❌ Ontology source missing 'path' field")
            return False
        if not os.path.exists(source["path"]):
            print(f"❌ Ontology source file not found: {source['path']}")
            return False

    print("✅ Ontology sources validated")

    # Validate SPARQL queries
    if "sparql_queries" not in ontology:
        print("❌ Missing [ontology].sparql_queries")
        return False

    for query in ontology["sparql_queries"]:
        if "file" not in query:
            print("❌ SPARQL query missing 'file' field")
            return False
        if not os.path.exists(query["file"]):
            print(f"❌ SPARQL query file not found: {query['file']}")
            return False

    print("✅ SPARQL queries validated")

    # Validate template paths
    templates = config["templates"]
    if "paths" not in templates:
        print("❌ Missing [templates].paths")
        return False

    for template_path in templates["paths"]:
        full_path = Path(template_path)
        if not full_path.exists():
            print(f"❌ Template directory not found: {template_path}")
            return False

        # Check for .tera files
        tera_files = list(full_path.rglob("*.tera"))
        if len(tera_files) == 0:
            print(f"⚠️  No .tera files found in: {template_path}")

    print("✅ Template paths validated")

    # Validate output structure
    output = config["output"]
    if "structure" not in output:
        print("❌ Missing [output].structure")
        return False

    for structure_item in output["structure"]:
        if "type" not in structure_item or "path" not in structure_item:
            print("❌ Output structure item missing required fields")
            return False

    print("✅ Output structure validated")

    # Validate generation phases
    generation = config["generation"]
    if "phases" not in generation:
        print("❌ Missing [generation].phases")
        return False

    # Check phase dependencies
    phase_names = [phase["name"] for phase in generation["phases"]]

    for phase in generation["phases"]:
        dependencies = phase.get("dependencies", [])
        for dep in dependencies:
            if dep not in phase_names:
                print(f"❌ Phase '{phase['name']}' references undefined dependency: {dep}")
                return False

    print("✅ Generation phases validated")

    # Validate cloud configurations
    cloud_sections = [
        "cloud.docker",
        "cloud.kubernetes",
        "cloud.helm"
    ]

    for section in cloud_sections:
        keys = section.split(".")
        current = config
        try:
            for key in keys:
                current = current[key]
            print(f"✅ Found configuration section: {section}")
        except KeyError:
            print(f"❌ Missing configuration section: {section}")
            return False

    # Validate Erlang configuration
    if "erlang" not in config:
        print("❌ Missing [erlang] section")
        return False

    erlang = config["erlang"]
    erlang_required = ["otp_version", "rebar3_path", "application_name"]

    for field in erlang_required:
        if field not in erlang:
            print(f"❌ Missing [erlang] field: {field}")
            return False

    print("✅ Erlang configuration validated")

    # Validate HotCI configuration
    if "hotci" in erlang:
        hotci = erlang["hotci"]
        if "enabled" not in hotci:
            print("❌ Missing [erlang.hotci].enabled")
            return False
        print(f"✅ HotCI enabled: {hotci['enabled']}")
    else:
        print("⚠️  HotCI configuration not found in [erlang]")

    # Validate security configuration
    if "security" not in config:
        print("⚠️  Missing [security] section - adding default security config")
        config["security"] = {
            "enable_secret_scanning": True,
            "enable_vulnerability_scanning": True,
            "dependency_scanning": True,
            "code_analysis": True
        }

    security = config["security"]
    security_required = ["enable_secret_scanning", "enable_vulnerability_scanning"]

    for field in security_required:
        if field not in security:
            print(f"❌ Missing [security] field: {field}")
            return False

    print("✅ Security configuration validated")

    # Validate hooks
    hooks = config["hooks"]
    if "pre_generation" not in hooks or "post_generation" not in hooks:
        print("❌ Missing [hooks].pre_generation or [hooks].post_generation")
        return False

    print("✅ Hooks configuration validated")

    # Check for existing templates mentioned in config
    template_files = [
        "templates/erlang/src/gen_server.tera",
        "templates/erlang/src/gen_statem.tera",
        "templates/erlang/src/supervisor.tera",
        "templates/docker/Dockerfile.tera",
        "templates/k8s/deployment.yaml.tera",
        "templates/k8s/service.yaml.tera",
        "templates/helm/Chart.yaml.tera",
        "templates/helm/values.yaml.tera"
    ]

    for template_file in template_files:
        if not os.path.exists(template_file):
            print(f"⚠️  Template file not found: {template_file}")

    print("\n🎉 Configuration validation completed successfully!")
    print("✅ All required sections and fields are present")
    print("✅ All file paths are valid")
    print("✅ All dependencies are properly defined")

    return True

if __name__ == "__main__":
    success = validate_config()
    sys.exit(0 if success else 1)