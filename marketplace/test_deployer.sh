#!/bin/bash
set -euo pipefail

: ${PROJECT_ID:?PROJECT_ID environment variable is required}
: ${CLUSTER_NAME:?CLUSTER_NAME environment variable is required}
: ${ZONE:=us-central1-a}
: ${IMAGE_TAG:=latest}

IMAGE_NAME="gcr.io/${PROJECT_ID}/a2a-deployer:${IMAGE_TAG}"

echo "Testing A2A deployer image..."
echo "  Image: ${IMAGE_NAME}"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Zone: ${ZONE}"

gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}

echo "Running deployer in test mode..."
docker run --rm \
  -v ${HOME}/.kube:/root/.kube:ro \
  -v ${HOME}/.config/gcloud:/root/.config/gcloud:ro \
  -e CLUSTER_NAME=${CLUSTER_NAME} \
  -e ZONE=${ZONE} \
  -e NAMESPACE=a2a-test \
  -e APP_INSTANCE_NAME=a2a-test \
  -e REPLICAS=1 \
  ${IMAGE_NAME}

echo ""
echo "Test deployment completed!"
echo "To cleanup:"
echo "  kubectl delete namespace a2a-test"
