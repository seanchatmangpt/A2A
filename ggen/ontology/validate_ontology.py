#!/usr/bin/env python3
"""
A2A Protocol Ontology Validation Script
Validates RDF/TTL ontology files against SHACL constraints
"""

import argparse
import sys
from rdflib import Graph, URIRef, Namespace
from rdflib.plugins.shacl import validate
from rdflib.namespace import RDF, RDFS, XSD
import json

def load_ontology_files(ontology_file, shacl_file, data_files=None):
    """Load ontology and data files"""
    # Create main graph
    g = Graph()

    # Load main ontology
    g.parse(ontology_file, format="turtle")
    print(f"Loaded ontology: {ontology_file}")

    # Load SHACL shapes
    if shacl_file:
        g.parse(shacl_file, format="turtle")
        print(f"Loaded SHACL constraints: {shacl_file}")

    # Load data files
    if data_files:
        for data_file in data_files:
            g.parse(data_file, format="turtle")
            print(f"Loaded data: {data_file}")

    return g

def validate_with_shacl(graph):
    """Validate graph against SHACL shapes"""
    print("\n" + "="*50)
    print("SHACL VALIDATION RESULTS")
    print("="*50)

    # Run validation
    conforms, results, _ = validate(graph)

    print(f"Conforms to SHACL: {conforms}")

    if not conforms:
        print("\nValidation Errors:")
        for result in results:
            print(f"\n- Focus: {result.focus}")
            print(f"  Path: {result.path}")
            print(f"  Message: {result.message}")
            if result.value:
                print(f"  Value: {result.value}")
            if result.severity:
                print(f"  Severity: {result.severity}")
    else:
        print("\n✅ All validations passed!")

    return conforms, results

def check_consistency(graph):
    """Check logical consistency of the ontology"""
    print("\n" + "="*50)
    print("ONTOLOGY CONSISTENCY CHECK")
    print("="*50)

    # Check for undefined classes
    print("\nChecking for undefined classes...")
    defined_classes = set(graph.subjects(RDF.type, OWL.Class))
    referenced_classes = set()

    for s, p, o in graph:
        if p == RDFS.subClassOf:
            referenced_classes.add(o)
        elif p == RDFS.domain:
            referenced_classes.add(o)
        elif p == RDFS.range:
            referenced_classes.add(o)

    undefined_classes = referenced_classes - defined_classes
    if undefined_classes:
        print(f"⚠️  Undefined classes: {undefined_classes}")
    else:
        print("✅ No undefined classes found")

    # Check for duplicate properties
    print("\nChecking for duplicate property definitions...")
    properties = {}
    duplicate_properties = set()

    for s, p, o in graph:
        if p in [RDFS.domain, RDFS.range]:
            key = str(s)
            if key not in properties:
                properties[key] = []
            properties[key].append((str(p), str(o)))

    for prop, definitions in properties.items():
        if len(definitions) > 1:
            duplicate_properties.add(prop)

    if duplicate_properties:
        print(f"⚠️  Duplicate properties: {duplicate_properties}")
    else:
        print("✅ No duplicate properties found")

    return len(undefined_classes) == 0 and len(duplicate_properties) == 0

def generate_statistics(graph):
    """Generate statistics about the ontology"""
    print("\n" + "="*50)
    print("ONTOLOGY STATISTICS")
    print("="*50)

    # Count entities
    stats = {
        'Classes': len(list(graph.subjects(RDF.type, OWL.Class))),
        'DatatypeProperties': len(list(graph.subjects(RDF.type, OWL.DatatypeProperty))),
        'ObjectProperties': len(list(graph.subjects(RDF.type, OWL.ObjectProperty))),
        'Individuals': len(list(graph.subjects(predicate=None, object=None))) - len(list(graph.subjects(RDF.type))),
        'SHACLShapes': len(list(graph.subjects(RDF.type, sh.NodeShape))),
        'Transitions': len(list(graph.subjects(RDF.type, a2a.Transition))),
        'Errors': len(list(graph.subjects(RDF.type, a2a.Error))),
        'Messages': len(list(graph.subjects(RDF.type, a2a.Message))),
        'Tasks': len(list(graph.subjects(RDF.type, a2a.Task))),
        'Agents': len(list(graph.subjects(RDF.type, a2a.Agent)))
    }

    for stat, count in stats.items():
        print(f"{stat}: {count}")

    return stats

def main():
    parser = argparse.ArgumentParser(description="Validate A2A Protocol Ontology")
    parser.add_argument("-o", "--ontology", required=True, help="Main ontology file")
    parser.add_argument("-s", "--shacl", help="SHACL validation file")
    parser.add_argument("-d", "--data", nargs="+", help="Data files to validate")
    parser.add_argument("--stats", action="store_true", help="Generate statistics")
    parser.add_argument("--consistency", action="store_true", help="Check consistency")

    args = parser.parse_args()

    # Load files
    data_files = args.data or []
    g = load_ontology_files(args.ontology, args.shacl, data_files)

    # Define namespaces
    global a2a, OWL, sh
    a2a = Namespace("https://a2a.com/schema/")
    OWL = Namespace("http://www.w3.org/2002/07/owl#")
    sh = Namespace("http://www.w3.org/ns/shacl#")

    # Generate statistics
    if args.stats:
        generate_statistics(g)

    # Check consistency
    if args.consistency:
        is_consistent = check_consistency(g)
        print(f"\nOverall consistency: {'✅ Consistent' if is_consistent else '❌ Inconsistent'}")

    # Validate with SHACL
    if args.shacl:
        conforms, results = validate_with_shacl(g)
        sys.exit(0 if conforms else 1)
    else:
        print("No SHACL file provided, skipping validation")
        sys.exit(0)

if __name__ == "__main__":
    main()