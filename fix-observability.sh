#!/bin/bash

# Script to fix escaped quotes in observability.yaml

FILE="/home/user/A2A/helm/templates/observability.yaml"
BACKUP="/home/user/A2A/helm/templates/observability.yaml.backup"

# Create backup
cp "$FILE" "$BACKUP"

# Replace all instances of namespace=\"{{ .Release.Namespace }}\" with namespace='{{ .Release.Namespace }}'
sed -i "s/namespace=\\\\\"{{ \.Release\.Namespace }}\\\\\"/namespace='{{ .Release.Namespace }}'/g" "$FILE"

# Replace status_code=~\"5..\" with status_code=~'5..'
sed -i "s/status_code=~\\\\\"5\.\.\\\\\"/status_code=~'5..'/g" "$FILE"

# Replace status=\"success\" with status='success'
sed -i "s/status=\\\\\"success\\\\\"/status='success'/g" "$FILE"

# Replace status=\"failed\" with status='failed'
sed -i "s/status=\\\\\"failed\\\\\"/status='failed'/g" "$FILE"

# Replace latency_sla=\"met\" with latency_sla='met'
sed -i "s/latency_sla=\\\\\"met\\\\\"/latency_sla='met'/g" "$FILE"

# Replace phase=\"Running\" with phase='Running'
sed -i "s/phase=\\\\\"Running\\\\\"/phase='Running'/g" "$FILE"

# Replace phase=\"Pending\" with phase='Pending'
sed -i "s/phase=\\\\\"Pending\\\\\"/phase='Pending'/g" "$FILE"

# Replace phase=\"Failed\" with phase='Failed'
sed -i "s/phase=\\\\\"Failed\\\\\"/phase='Failed'/g" "$FILE"

# For pod regex patterns, we need to handle them specially
# Replace pod=~\"{{ include \"a2a.fullname\" . }}.*\" with pod=~'{{ include "a2a.fullname" . }}.*'
sed -i "s/pod=~\\\\\"{{ include \\\\\"a2a\.fullname\\\\\" \. }}\.\*\\\\\"/pod=~'{{ include \"a2a.fullname\" . }}.*'/g" "$FILE"

echo "Fixed escaped quotes in $FILE"
echo "Backup saved to $BACKUP"
