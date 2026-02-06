#!/bin/bash
set -euo pipefail

: ${PROJECT_ID:?PROJECT_ID environment variable is required}
: ${IMAGE_TAG:=latest}

IMAGE_NAME="gcr.io/${PROJECT_ID}/a2a-deployer"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building GCP Marketplace deployer image..."
echo "  Image: ${FULL_IMAGE}"

docker build -t ${FULL_IMAGE} -f Dockerfile .

echo ""
echo "Build completed successfully!"
echo ""
echo "To push to GCR:"
echo "  docker push ${FULL_IMAGE}"
echo ""
echo "To test locally:"
echo "  docker run --rm ${FULL_IMAGE}"
