#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="signed-and-guarded"

echo "==> Tearing down kind cluster: ${CLUSTER_NAME}..."
kind delete cluster --name "${CLUSTER_NAME}"
echo "==> Cluster destroyed cleanly."
