#!/usr/bin/env python3
"""
A2A Protocol Ontology Documentation Generator
Generates HTML documentation from RDF/TTL ontology
"""

import os
from rdflib import Graph, URIRef, Namespace
from rdflib.namespace import RDF, RDFS, OWL
import json

def generate_class_doc(g, cls_uri, prefix):
    """Generate documentation for a class"""
    doc = {
        'name': str(cls_uri).split('#')[-1],
        'uri': str(cls_uri),
        'label': None,
        'comment': None,
        'properties': [],
        'subclasses': []
    }

    # Get label and comment
    for label in g.objects(cls_uri, RDFS.label):
        doc['label'] = str(label)

    for comment in g.objects(cls_uri, RDFS.comment):
        doc['comment'] = str(comment)

    # Get properties
    for prop in g.subjects(RDFS.domain, cls_uri):
        if prop.startswith(prefix):
            prop_info = {
                'name': str(prop).split('#')[-1],
                'uri': str(prop),
                'label': None,
                'range': None
            }

            # Get property label
            for label in g.objects(prop, RDFS.label):
                prop_info['label'] = str(label)

            # Get property range
            for range_uri in g.objects(prop, RDFS.range):
                if str(range_uri).startswith(prefix):
                    prop_info['range'] = str(range_uri).split('#')[-1]
                else:
                    prop_info['range'] = str(range_uri)

            doc['properties'].append(prop_info)

    # Get subclasses
    for subcls in g.objects(cls_uri, RDFS.subClassOf):
        if isinstance(subcls, URIRef) and subcls.startswith(prefix):
            doc['subclasses'].append(str(subcls).split('#')[-1])

    return doc

def generate_html_doc(ontology_file, output_dir="docs"):
    """Generate HTML documentation"""
    # Load ontology
    g = Graph()
    g.parse(ontology_file, format="turtle")

    # Define namespaces
    a2a = Namespace("https://a2a.com/schema/")
    prefix = "https://a2a.com/schema/"

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Generate class documentation
    classes = []
    for cls in g.subjects(RDF.type, OWL.Class):
        if cls.startswith(prefix):
            class_doc = generate_class_doc(g, cls, prefix)
            classes.append(class_doc)

    # Generate index
    index_html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>A2A Protocol Ontology Documentation</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }}
        .header {{ background: #f4f4f4; padding: 20px; margin-bottom: 30px; }}
        .class {{ margin-bottom: 30px; padding: 20px; border: 1px solid #ddd; }}
        .class h2 {{ color: #333; }}
        .property {{ margin: 10px 0; padding: 10px; background: #f9f9f9; }}
        .property h4 {{ color: #666; }}
        .subclasses {{ margin-top: 15px; padding: 10px; background: #e8f4f8; }}
        ul {{ margin: 0; padding-left: 20px; }}
        .toc {{ background: #f9f9f9; padding: 20px; margin-bottom: 30px; }}
        .toc h2 {{ color: #333; }}
        .toc ul {{ columns: 2; }}
        code {{ background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>A2A Protocol Ontology Documentation</h1>
        <p>Comprehensive RDF/TTL ontology for Agent-to-Agent protocol specifications</p>
    </div>

    <div class="toc">
        <h2>Table of Contents</h2>
        <ul>
"""

    # Add classes to TOC
    for cls in sorted(classes, key=lambda x: x['name']):
        index_html += f'            <li><a href="#{cls["name"]}">{cls["name"]}</a> - {cls["label"] or "No label"}</li>\n'

    index_html += """
        </ul>
    </div>

    <h1>Class Documentation</h1>
"""

    # Generate class documentation
    for cls in sorted(classes, key=lambda x: x['name']):
        index_html += f"""
    <div class="class">
        <h2 id="{cls['name']}">{cls['name']}</h2>
        <p><strong>URI:</strong> <code>{cls['uri']}</code></p>
        <p><strong>Label:</strong> {cls['label'] or 'No label'}</p>
        <p><strong>Description:</strong> {cls['comment'] or 'No description'}</p>

        <h3>Properties</h3>
"""

        if cls['properties']:
            for prop in cls['properties']:
                index_html += f"""
        <div class="property">
            <h4>{prop['name']}</h4>
            <p><strong>URI:</strong> <code>{prop['uri']}</code></p>
            <p><strong>Label:</strong> {prop['label'] or 'No label'}</p>
            <p><strong>Range:</strong> <code>{prop['range']}</code></p>
        </div>
"""
        else:
            index_html += "<p>No properties defined.</p>"

        if cls['subclasses']:
            index_html += """
        <div class="subclasses">
            <h4>Subclasses</h4>
            <ul>
"""
            for subcls in cls['subclasses']:
                index_html += f"                <li>{subcls}</li>\n"
            index_html += """
            </ul>
        </div>
"""

        index_html += """
    </div>
"""

    # Add footer
    index_html += """
    <div class="footer">
        <p>Generated by A2A Protocol Ontology Documentation Generator</p>
    </div>
</body>
</html>
"""

    # Write index file
    with open(os.path.join(output_dir, "index.html"), "w") as f:
        f.write(index_html)

    print(f"Documentation generated in {output_dir}/index.html")

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate ontology documentation")
    parser.add_argument("-o", "--ontology", required=True, help="Ontology file")
    parser.add_argument("-d", "--output-dir", default="docs", help="Output directory")

    args = parser.parse_args()
    generate_html_doc(args.ontology, args.output_dir)

if __name__ == "__main__":
    main()