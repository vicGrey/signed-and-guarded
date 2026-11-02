#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="signed-and-guarded"
NODE_IMAGE="kindest/node:v1.31.2@sha256:18fbefc20a7113353c7b75b5c869d7145a6abd6269154825872dc59c1329912e"
KYVERNO_VERSION="3.3.9"

echo "==> Creating kind cluster: ${CLUSTER_NAME}..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
else
  kind create cluster --name "${CLUSTER_NAME}" --image "${NODE_IMAGE}"
fi

echo "==> Installing Kyverno (chart version ${KYVERNO_VERSION})..."
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm repo update
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version "${KYVERNO_VERSION}" \
  --wait

echo "==> Applying Kyverno baseline policies..."
kubectl apply -f policies/

echo "==> Cluster is ready and guarded!"
