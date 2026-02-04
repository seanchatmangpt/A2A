# Makefile for A2A Protocol Ontology

# Variables
ONTOLYNS = a2a-comprehensive-ontology.ttl a2a-shacl-validation.ttl
EXAMPLES = examples/a2a-protocol-examples.ttl
VENV = venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip
OWLTOOLS = owltools
RDFLIB = rdflib

# Default target
.PHONY: all
all: validate test

# Create virtual environment
.PHONY: venv
venv:
	@echo "Creating virtual environment..."
	python3 -m venv $(VENV)
	$(PIP) install -r requirements.txt

# Install dependencies
.PHONY: install
install: venv
	@echo "Installing dependencies..."
	$(PIP) install -r requirements.txt

# Validate ontology with SHACL
.PHONY: validate
validate: venv
	@echo "Running SHACL validation..."
	$(PYTHON) validate_ontology.py -o $(ONTOLYNS) -s $(ONTOLYNS) -d $(EXAMPLES) --stats --consistency

# Run tests
.PHONY: test
test: venv
	@echo "Running test suite..."
	$(PYTHON) test_ontology.py

# Check consistency
.PHONY: consistency
consistency: venv
	@echo "Checking consistency..."
	$(PYTHON) validate_ontology.py -o $(ONTOLYNS) --consistency

# Generate statistics
.PHONY: stats
stats: venv
	@echo "Generating statistics..."
	$(PYTHON) validate_ontology.py -o $(ONTOLYNS) --stats

# Run validation on examples
.PHONY: examples
examples: venv
	@echo "Validating examples..."
	$(PYTHON) validate_ontology.py -o $(ONTOLYNS) -s $(ONTOLYNS) -d $(EXAMPLES)

# Validate only ontology structure
.PHONY: validate-structure
validate-structure: venv
	@echo "Validating structure..."
	$(PYTHON) validate_ontology.py -o $(ONTOLYNS) --consistency

# Clean up
.PHONY: clean
clean:
	@echo "Cleaning up..."
	rm -rf $(VENV)
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -delete
	find . -name ".DS_Store" -delete

# Format ontology files
.PHONY: format
format:
	@echo "Formatting ontology files..."
	# This would use an RDF formatter if available
	@echo "Please install RDF formatter for proper formatting"

# Convert to different formats
.PHONY: convert
convert:
	@echo "Converting ontology formats..."
	# Convert to RDF/XML
	$(RDFLIB) -c "a2a-comprehensive-ontology.ttl" -o "a2a-ontology.rdf"
	# Convert to JSON-LD
	$(RDFLIB) -c "a2a-comprehensive-ontology.ttl" -o "a2a-ontology.jsonld"

# Generate documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	# This could generate HTML documentation from the ontology
	@echo "Documentation generation not implemented"

# Check for issues
.PHONY: check
check: validate test consistency
	@echo "All checks completed!"

# Quick validation
.PHONY: quick
quick: validate-structure

# Full validation pipeline
.PHONY: full
full: clean install validate test stats examples

# Development setup
.PHONY: dev
dev: install
	@echo "Development environment ready!"

# Help
.PHONY: help
help:
	@echo "A2A Protocol Ontology Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Run all validations and tests"
	@echo "  venv          - Create virtual environment"
	@echo "  install       - Install dependencies"
	@echo "  validate      - Run SHACL validation"
	@echo "  test          - Run test suite"
	@echo "  consistency   - Check consistency"
	@echo "  stats         - Generate statistics"
	@echo "  examples      - Validate examples"
	@echo "  validate-structure - Validate structure"
	@echo "  clean         - Clean up"
	@echo "  format        - Format ontology files"
	@echo "  convert       - Convert formats"
	@echo "  docs          - Generate documentation"
	@echo "  check         - Run all checks"
	@echo "  quick         - Quick validation"
	@echo "  full          - Full validation pipeline"
	@echo "  dev           - Development setup"
	@echo "  help          - Show this help"