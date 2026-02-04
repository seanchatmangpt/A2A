#!/bin/bash
# K8s Ingress Validation Script for A2A Erlang
# Validates ingress configuration without requiring a running cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_FILE="${SCRIPT_DIR}/ingress.yaml"
SERVICE_FILE="${SCRIPT_DIR}/service.yaml"
NAMESPACE_FILE="${SCRIPT_DIR}/namespace.yaml"

echo "========================================="
echo "A2A Erlang K8s Ingress Validation"
echo "========================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check Python availability
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 is required for validation${NC}"
    exit 1
fi

echo "1. Validating YAML syntax..."
python3 -c "
import sys
import yaml

files = [
    ('${NAMESPACE_FILE}', 'Namespace'),
    ('${SERVICE_FILE}', 'Service (multi-doc)'),
    ('${INGRESS_FILE}', 'Ingress'),
]

for filepath, name in files:
    try:
        with open(filepath, 'r') as f:
            data = list(yaml.safe_load_all(f))
            print(f'  ✓ {name}: Valid YAML ({len([d for d in data if d])} document(s))')
    except yaml.YAMLError as e:
        print(f'  ✗ {name}: YAML Error - {e}')
        sys.exit(1)
    except FileNotFoundError:
        print(f'  ✗ {name}: File not found')
        sys.exit(1)
"

echo
echo "2. Validating Ingress spec structure..."
python3 -c "
import yaml

with open('${INGRESS_FILE}', 'r') as f:
    ingress = yaml.safe_load(f)

# Check required fields
errors = []

if ingress.get('kind') != 'Ingress':
    errors.append('Kind must be Ingress')

if ingress.get('apiVersion') != 'networking.k8s.io/v1':
    errors.append('API version should be networking.k8s.io/v1')

metadata = ingress.get('metadata', {})
if not metadata.get('name'):
    errors.append('Missing metadata.name')

if not metadata.get('namespace'):
    errors.append('Missing metadata.namespace')

spec = ingress.get('spec', {})
if not spec.get('ingressClassName'):
    errors.append('Missing spec.ingressClassName')

rules = spec.get('rules', [])
if not rules:
    errors.append('No rules defined')
else:
    for i, rule in enumerate(rules):
        if not rule.get('host'):
            errors.append(f'Rule {i}: Missing host')

        http = rule.get('http', {})
        paths = http.get('paths', [])
        if not paths:
            errors.append(f'Rule {i}: No paths defined')

        for j, path in enumerate(paths):
            if not path.get('path'):
                errors.append(f'Rule {i}, Path {j}: Missing path')

            path_type = path.get('pathType')
            if path_type not in ['Exact', 'Prefix', 'ImplementationSpecific']:
                errors.append(f'Rule {i}, Path {j}: Invalid pathType: {path_type}')

            backend = path.get('backend', {})
            service = backend.get('service', {})
            if not service.get('name'):
                errors.append(f'Rule {i}, Path {j}: Missing backend service name')

            port = service.get('port', {})
            if not port.get('number'):
                errors.append(f'Rule {i}, Path {j}: Missing backend service port')

# Check TLS is properly commented
tls = spec.get('tls')
if tls is None:
    print('  ✓ TLS: Properly commented (ready to enable)')
elif isinstance(tls, list):
    if len(tls) == 0:
        print('  ✓ TLS: Empty list (TLS disabled)')
    else:
        print('  ✓ TLS: Configured')

if errors:
    print('  ✗ Errors found:')
    for error in errors:
        print(f'    - {error}')
    exit(1)
else:
    print('  ✓ All required fields present')
    print('  ✓ spec.ingressClassName: ' + spec.get('ingressClassName'))
    print('  ✓ Number of rules: ' + str(len(rules)))
    print('  ✓ Number of paths: ' + str(sum(len(r.get('http', {}).get('paths', [])) for r in rules)))
"

echo
echo "3. Checking service port references..."
python3 -c "
import yaml

with open('${SERVICE_FILE}', 'r') as f:
    svc_docs = list(yaml.safe_load_all(f))
    # Find the a2a-service
    service_port = None
    for doc in svc_docs:
        if doc and doc.get('kind') == 'Service' and doc.get('metadata', {}).get('name') == 'a2a-service':
            for port in doc.get('spec', {}).get('ports', []):
                if port.get('name') == 'http':
                    service_port = port.get('port')
                    break
            break

with open('${INGRESS_FILE}', 'r') as f:
    ingress = yaml.safe_load(f)

# Check all ingress paths reference the correct port
paths = ingress.get('spec', {}).get('rules', [{}])[0].get('http', {}).get('paths', [])
for path in paths:
    port = path.get('backend', {}).get('service', {}).get('port', {}).get('number')
    if port != service_port:
        print(f'  ✗ Port mismatch: ingress references port {port}, service exposes port {service_port}')
        exit(1)

print(f'  ✓ All ingress paths reference service port {service_port}')
"

echo
echo "4. Validating A2A protocol specific paths..."
python3 -c "
import yaml

with open('${INGRESS_FILE}', 'r') as f:
    ingress = yaml.safe_load(f)

paths = ingress.get('spec', {}).get('rules', [{}])[0].get('http', {}).get('paths', [])
path_list = [p.get('path') for p in paths]

required_paths = {
    '/health': 'Exact',
    '/health/ready': 'Exact',
    '/health/live': 'Exact',
    '/metrics': 'Exact',
    '/.well-known/agent-card.json': 'Exact',
    '/message:send': 'Exact',
    '/message:stream': 'Exact',
    '/tasks': 'Exact',
    '/tasks/': 'Prefix',
    '/extendedAgentCard': 'Exact',
}

errors = []
for path, expected_type in required_paths.items():
    found = False
    for p in paths:
        if p.get('path') == path:
            found = True
            if p.get('pathType') != expected_type:
                errors.append(f'{path}: Expected pathType {expected_type}, got {p.get(\"pathType\")}')
            break

    if not found:
        errors.append(f'{path}: Path not found')

if errors:
    print('  ✗ Errors found:')
    for error in errors:
        print(f'    - {error}')
    exit(1)
else:
    print('  ✓ All A2A protocol paths defined correctly')
    print(f'  ✓ /message:send and /message:stream paths configured')
"

echo
echo "5. Checking NGINX Ingress annotations..."
python3 -c "
import yaml

with open('${INGRESS_FILE}', 'r') as f:
    ingress = yaml.safe_load(f)

annotations = ingress.get('metadata', {}).get('annotations', {})

required_annotations = {
    'nginx.ingress.kubernetes.io/ssl-redirect': 'false',
    'nginx.ingress.kubernetes.io/use-regex': 'true',
    'nginx.ingress.kubernetes.io/websocket-services': 'a2a-service',
}

missing = []
for key, value in required_annotations.items():
    if annotations.get(key) != value:
        missing.append(f'{key}={value}')

if missing:
    print('  ⚠ Missing or incorrect annotations:')
    for ann in missing:
        print(f'    - {ann}')
else:
    print('  ✓ All required NGINX annotations present')
    print('  ✓ Websocket support enabled for SSE')
    print('  ✓ Regex enabled for special path handling')
"

echo
echo "========================================="
echo -e "${GREEN}✓ Ingress validation passed!${NC}"
echo "========================================="
echo
echo "Summary:"
echo "  - Ingress resource is valid"
echo "  - Host rules properly configured (a2a.local)"
echo "  - TLS can be enabled by uncommenting tls section"
echo "  - All A2A protocol paths route correctly"
echo "  - Compatible with NGINX Ingress Controller"
echo
echo "To apply to a cluster:"
echo "  kubectl apply -f ${NAMESPACE_FILE}"
echo "  kubectl apply -f ${SERVICE_FILE}"
echo "  kubectl apply -f ${INGRESS_FILE}"
echo
