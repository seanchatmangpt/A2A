#!/bin/bash
set -euo pipefail

echo "Creating Kubernetes manifests..."

: ${NAMESPACE:=default}
: ${APP_INSTANCE_NAME:=a2a}
: ${REPLICAS:=3}
: ${IMAGE_REGISTRY:=gcr.io}
: ${IMAGE_TAG:=latest}

MANIFEST_DIR="/data/manifests"
mkdir -p ${MANIFEST_DIR}

export NAMESPACE
export APP_INSTANCE_NAME
export REPLICAS
export IMAGE_REGISTRY
export IMAGE_TAG

if [[ -d "/data/templates" ]]; then
  echo "Processing template files..."
  for template in /data/templates/*.yaml /data/templates/*.yml; do
    if [[ -f "${template}" ]]; then
      filename=$(basename ${template})
      echo "  Processing ${filename}..."
      envsubst < ${template} > ${MANIFEST_DIR}/${filename}
    fi
  done
fi

if [[ -f "/data/schema.yaml" ]]; then
  echo "Copying schema.yaml..."
  cp /data/schema.yaml ${MANIFEST_DIR}/
fi

echo "Generating application resource..."
cat > ${MANIFEST_DIR}/application.yaml <<EOF
apiVersion: app.k8s.io/v1beta1
kind: Application
metadata:
  name: ${APP_INSTANCE_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes-engine.cloud.google.com/icon: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
    marketplace.cloud.google.com/deploy-info: '{"partner_id": "a2a", "product_id": "a2a", "partner_name": "A2A"}'
  labels:
    app.kubernetes.io/name: ${APP_INSTANCE_NAME}
spec:
  descriptor:
    type: A2A
    version: '1.0'
    description: Agent-to-Agent protocol implementation
    maintainers:
    - name: A2A Team
      email: support@a2a.dev
    links:
    - description: Getting Started
      url: https://github.com/a2a-ai/A2A
  selector:
    matchLabels:
      app.kubernetes.io/name: ${APP_INSTANCE_NAME}
  componentKinds:
  - group: v1
    kind: Service
  - group: apps/v1
    kind: Deployment
  - group: v1
    kind: ConfigMap
  - group: v1
    kind: Secret
EOF

echo "Generating service account..."
cat > ${MANIFEST_DIR}/serviceaccount.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_INSTANCE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_INSTANCE_NAME}
EOF

echo "Generating ConfigMap..."
cat > ${MANIFEST_DIR}/configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_INSTANCE_NAME}-config
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_INSTANCE_NAME}
data:
  config.json: |
    {
      "server": {
        "port": 8080,
        "host": "0.0.0.0"
      },
      "logging": {
        "level": "info"
      }
    }
EOF

echo "Manifest generation completed!"
ls -lh ${MANIFEST_DIR}/
