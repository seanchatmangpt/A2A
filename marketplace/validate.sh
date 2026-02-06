#!/bin/bash
set -euo pipefail

echo "Validating A2A deployment..."

: ${NAMESPACE:=default}
: ${APP_INSTANCE_NAME:=a2a}

echo "Checking deployment status..."
DEPLOYMENT_EXISTS=$(kubectl get deployment ${APP_INSTANCE_NAME} -n ${NAMESPACE} --ignore-not-found -o name)
if [[ -z "${DEPLOYMENT_EXISTS}" ]]; then
  echo "Error: Deployment ${APP_INSTANCE_NAME} not found in namespace ${NAMESPACE}"
  exit 1
fi

echo "Checking pods..."
READY_PODS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME} --field-selector=status.phase=Running -o json | jq '.items | length')
TOTAL_PODS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME} -o json | jq '.items | length')

echo "  Ready pods: ${READY_PODS}/${TOTAL_PODS}"

if [[ ${READY_PODS} -eq 0 ]]; then
  echo "Error: No pods are ready"
  kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME}
  exit 1
fi

echo "Checking services..."
SERVICE_EXISTS=$(kubectl get svc ${APP_INSTANCE_NAME} -n ${NAMESPACE} --ignore-not-found -o name)
if [[ -z "${SERVICE_EXISTS}" ]]; then
  echo "Warning: Service ${APP_INSTANCE_NAME} not found"
else
  echo "  Service: ${SERVICE_EXISTS} ✓"
fi

echo "Checking application resource..."
APP_EXISTS=$(kubectl get application ${APP_INSTANCE_NAME} -n ${NAMESPACE} --ignore-not-found -o name)
if [[ -z "${APP_EXISTS}" ]]; then
  echo "Warning: Application resource not found"
else
  echo "  Application: ${APP_EXISTS} ✓"
fi

echo "Getting pod logs (last 20 lines)..."
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${POD_NAME}" ]]; then
  echo "  Pod: ${POD_NAME}"
  kubectl logs ${POD_NAME} -n ${NAMESPACE} --tail=20 || true
fi

echo "Testing connectivity..."
if [[ -n "${SERVICE_EXISTS}" ]]; then
  SERVICE_IP=$(kubectl get svc ${APP_INSTANCE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
  SERVICE_PORT=$(kubectl get svc ${APP_INSTANCE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].port}')

  echo "  Service endpoint: ${SERVICE_IP}:${SERVICE_PORT}"

  kubectl run -n ${NAMESPACE} test-curl-${RANDOM} \
    --image=curlimages/curl:latest \
    --rm -i --restart=Never \
    --command -- curl -s -m 5 http://${SERVICE_IP}:${SERVICE_PORT}/health || echo "  Health check returned non-zero (service may not have /health endpoint)"
fi

echo ""
echo "Validation completed!"
echo ""
echo "Deployment summary:"
kubectl get all -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME}
