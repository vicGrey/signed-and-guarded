# Signed & Guarded: Kubernetes Container Supply Chain Security

Cryptographic container signing (Sigstore Cosign) and Kubernetes admission enforcement (Kyverno `ImageValidatingPolicy`) for a Python FastAPI workload.

> **Core Security Premise:** A signature is only a claim; it is not a security control until an admission controller rejects every workload that lacks one. This repository bridges the gap between keyless CI signing via GitHub Actions OIDC and fail-closed enforcement at the Kubernetes API server.

---

## Architecture & Trust Boundaries

```
[ Git Push to main ]
        │
        ▼
[ Step 1: Gitleaks Secret Scan ] ──────────────► (Leaked credential? ➔ Block build)
        │
        ▼
[ Step 2: Docker Build (Hardened Non-Root) ]
        │
        ▼
[ Step 3: Trivy Vulnerability Scan ] ──────────► (HIGH/CRITICAL CVE? ➔ Block push)
        │
        ▼
[ Step 4: Push to GHCR (Untrusted Storage) ]
        │
        ▼
[ Step 5: Keyless Cosign Signing (GitHub OIDC) ]
        │
        ▼
[ Kubernetes API Server ]
        │
        ▼
[ Kyverno Admission Controller ]
        ├── 1. Baseline Pod Hardening (No root, no :latest, no privileged)
        └── 2. ImageValidatingPolicy (CEL verification against Rekor & Fulcio OIDC)
                ├── Valid signature from main? ➔ ADMIT (Mutate to immutable @sha256 digest)
                └── Unsigned or untrusted signer? ➔ REJECT (403 Forbidden)
```

1. **Source & CI Pipeline (GitHub Actions):**
   - **Secret Detection:** Scans git history and source via **Gitleaks**.
   - **Container Build:** Builds a hardened multi-stage non-root (`USER 10001:10001`) FastAPI image pinned by digest.
   - **Vulnerability Gate:** Scans image layers via **Trivy** (`HIGH`/`CRITICAL` exit-code gate) before pushing to GHCR.
   - **Keyless OIDC Signing:** Requests an ephemeral OIDC token from `https://token.actions.githubusercontent.com`, obtains a signing certificate from **Fulcio**, signs the immutable `@sha256` image digest via **Cosign v3**, and records the transparency log entry in **Rekor**.
2. **Untrusted Storage (GHCR):**
   - Registry write access alone cannot result in cluster execution. Direct `docker push` builds bypassing CI are blocked at admission.
3. **Kubernetes Admission Control (Kyverno):**
   - **Baseline Pod Hardening:** Enforces `runAsNonRoot: true`, blocks `privileged: true`, drops capabilities, and disallows mutable `:latest` tags.
   - **Cryptographic Signature Verification (`ImageValidatingPolicy`):** Uses Kyverno's modern `policies.kyverno.io/v1` `ImageValidatingPolicy` and CEL expressions (`verifyImageSignatures`) to verify the Rekor transparency log entry, OIDC issuer, and exact `main` branch workflow identity before admitting any Pod.

---

## Quick Navigation

- [Threat Model & Attack Matrix (`THREAT_MODEL.md`)](THREAT_MODEL.md)
- [Implementation Roadmap (`PLAN.md`)](PLAN.md)
- [Kyverno Admission Policies (`policies/`)](policies/)
- [Verification Evidence Logs (`docs/evidence/`)](docs/evidence/)

---

## Verification Matrix (Completed Stages)

| Stage | Control Layer | Test Case | Manifest / Policy | Outcome | Evidence |
|---|---|---|---|---|---|
| **Stage 0** | Architecture | Threat boundaries, OIDC pinning, and honest scope limits | `THREAT_MODEL.md` | Documented | [`THREAT_MODEL.md`](THREAT_MODEL.md) |
| **Stage 1** | Kyverno Baseline | Admit compliant non-root Pod (`UID 10001`) | `k8s/good/compliant-pod.yaml` | **Admitted** | [`stage-1-rejection.txt`](docs/evidence/stage-1-rejection.txt) |
| **Stage 1** | Kyverno Baseline | Block mutable `:latest` tag | `k8s/bad/bad-latest.yaml` | **Rejected** | [`stage-1-rejection.txt`](docs/evidence/stage-1-rejection.txt) |
| **Stage 1** | Kyverno Baseline | Block privileged container (`privileged: true`) | `k8s/bad/bad-privileged.yaml` | **Rejected** | [`stage-1-rejection.txt`](docs/evidence/stage-1-rejection.txt) |
| **Stage 1** | Kyverno Baseline | Block root execution (`runAsNonRoot` missing) | `k8s/bad/bad-root.yaml` | **Rejected** | [`stage-1-rejection.txt`](docs/evidence/stage-1-rejection.txt) |
| **Stage 2** | GitHub Actions + Sigstore | Gitleaks + Trivy scan + keyless Cosign signing by `@sha256` digest | `.github/workflows/build-sign.yml` | **Signed & Logged** | [`stage-2-ci-pipeline.txt`](docs/evidence/stage-2-ci-pipeline.txt) |
| **Stage 3** | Kyverno `ImageValidatingPolicy` | Admit GHCR image signed by trusted `main` workflow OIDC identity | `k8s/good/signed-pod.yaml` | **Admitted** | [`stage-3-signature-enforcement.txt`](docs/evidence/stage-3-signature-enforcement.txt) |
| **Stage 3** | Kyverno `ImageValidatingPolicy` | Reject unsigned image pushed directly to GHCR | `k8s/bad/unsigned-pod.yaml` | **Rejected** | [`stage-3-signature-enforcement.txt`](docs/evidence/stage-3-signature-enforcement.txt) |

---

## Reproducing the Lab

### Prerequisites
- Docker, `kind`, `kubectl`, and `helm`
- Kubernetes cluster (tested on `kind` v1.31.2 and Civo Kubernetes)
- Kyverno v1.14+ (`ImageValidatingPolicy` CRD support)

### 1. Bootstrap Cluster & Guardrails
```bash
./scripts/up.sh
```

### 2. Run Baseline Hardening Tests (Stage 1)
```bash
./scripts/test.sh
```

### 3. Test Cryptographic Signature Enforcement (Stage 3)
```bash
# 1. Deploy cryptographically signed image (Admitted)
kubectl apply -f k8s/good/signed-pod.yaml

# 2. Deploy unsigned image from registry (Rejected by ImageValidatingPolicy)
kubectl apply -f k8s/bad/unsigned-pod.yaml
```

### 4. Teardown
```bash
./scripts/down.sh
```
