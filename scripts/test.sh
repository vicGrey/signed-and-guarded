#!/usr/bin/env bash
set -uo pipefail

EVIDENCE_DIR="docs/evidence"
mkdir -p "${EVIDENCE_DIR}"
EVIDENCE_FILE="${EVIDENCE_DIR}/stage-1-rejection.txt"
> "${EVIDENCE_FILE}"

echo "==================================================" | tee -a "${EVIDENCE_FILE}"
echo "  STAGE 1 VERIFICATION: KYVERNO BASELINE HARDENING" | tee -a "${EVIDENCE_FILE}"
echo "  Timestamp: $(date -u)" | tee -a "${EVIDENCE_FILE}"
echo "==================================================" | tee -a "${EVIDENCE_FILE}"

# Cleanup any leftover test pods
kubectl delete pod good-pod bad-latest-pod bad-privileged-pod bad-root-pod --ignore-not-found=true &>/dev/null

echo -e "\n[TEST 1] Applying compliant manifest (k8s/good/compliant-pod.yaml)..." | tee -a "${EVIDENCE_FILE}"
if kubectl apply -f k8s/good/compliant-pod.yaml 2>&1 | tee -a "${EVIDENCE_FILE}"; then
  echo ">>> SUCCESS: Compliant pod was admitted as expected." | tee -a "${EVIDENCE_FILE}"
else
  echo ">>> FAILURE: Compliant pod was unexpectedly rejected!" | tee -a "${EVIDENCE_FILE}"
  exit 1
fi

echo -e "\n[TEST 2] Applying violating manifest: latest tag (k8s/bad/bad-latest.yaml)..." | tee -a "${EVIDENCE_FILE}"
if kubectl apply -f k8s/bad/bad-latest.yaml 2>&1 | tee -a "${EVIDENCE_FILE}"; then
  echo ">>> FAILURE: bad-latest pod was admitted! Expected rejection." | tee -a "${EVIDENCE_FILE}"
  exit 1
else
  echo ">>> SUCCESS: bad-latest pod was rejected by Kyverno as expected." | tee -a "${EVIDENCE_FILE}"
fi

echo -e "\n[TEST 3] Applying violating manifest: privileged container (k8s/bad/bad-privileged.yaml)..." | tee -a "${EVIDENCE_FILE}"
if kubectl apply -f k8s/bad/bad-privileged.yaml 2>&1 | tee -a "${EVIDENCE_FILE}"; then
  echo ">>> FAILURE: bad-privileged pod was admitted! Expected rejection." | tee -a "${EVIDENCE_FILE}"
  exit 1
else
  echo ">>> SUCCESS: bad-privileged pod was rejected by Kyverno as expected." | tee -a "${EVIDENCE_FILE}"
fi

echo -e "\n[TEST 4] Applying violating manifest: root user (k8s/bad/bad-root.yaml)..." | tee -a "${EVIDENCE_FILE}"
if kubectl apply -f k8s/bad/bad-root.yaml 2>&1 | tee -a "${EVIDENCE_FILE}"; then
  echo ">>> FAILURE: bad-root pod was admitted! Expected rejection." | tee -a "${EVIDENCE_FILE}"
  exit 1
else
  echo ">>> SUCCESS: bad-root pod was rejected by Kyverno as expected." | tee -a "${EVIDENCE_FILE}"
fi

echo -e "\n==================================================" | tee -a "${EVIDENCE_FILE}"
echo "  ALL STAGE 1 TESTS PASSED! Evidence saved to ${EVIDENCE_FILE}" | tee -a "${EVIDENCE_FILE}"
echo "==================================================" | tee -a "${EVIDENCE_FILE}"

# Cleanup test pods after test
kubectl delete pod good-pod --ignore-not-found=true &>/dev/null
