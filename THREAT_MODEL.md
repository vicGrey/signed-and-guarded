# Threat Model: Signed and Guarded

## 1. Central Architectural Limit and Scope Guarantee

**Central limit:** A compromised workflow or malicious commit merged into the trusted branch (`main`) will sign a bad image, and Kyverno will admit it.

Cryptographic signing (Cosign) and admission control (Kyverno) guarantee **workflow provenance and artifact integrity**, not **code safety**. If an attacker merges malicious application logic into `main`, or edits `.github/workflows/build-sign.yml` on `main` to remove security scanners, the workflow will still produce a valid signature and Kyverno will admit the pod. Protecting `main` requires upstream Git controls: branch protection with mandatory review first, plus commit signing (which proves who authored a commit, not that it is safe).

The pipeline covers a FastAPI workload deployed to a local kind cluster and a short-lived AWS EKS demo cluster. Admitted images were signed by `.github/workflows/build-sign.yml` on `main`. Secret and vulnerability scans run before signing in that workflow, but Kubernetes admission does not cryptographically verify scan results unless the Stage 4 attestation policy is enabled.

---

## 2. Stage Numbering Reference

Every threat and test maps to the stage sequence defined in `PLAN.md` (Stage 0 threat model through Stage 6 AWS EKS/ECR port).

---

## 3. Trust Boundaries

- **Source boundary (GitHub repository):** Code moves from untrusted developer workstations into the protected `main` branch.
- **Build and sign boundary (GitHub Actions + Sigstore):** Ephemeral CI runners execute security gates (Gitleaks, Trivy), then sign the image `@sha256` digest keylessly in three steps:
  1. The runner requests an OIDC identity token from GitHub's issuer (`https://token.actions.githubusercontent.com`).
  2. Fulcio (Sigstore's CA, `fulcio.sigstore.dev`) exchanges that token for a short-lived signing certificate bound to the workflow identity.
  3. The signature and certificate are logged as a transparency entry in Rekor.
- **Storage boundary (container registry, GHCR or AWS ECR):** Treated as untrusted storage. Write access to the registry alone must not allow execution in the cluster.
- **Execution boundary (Kubernetes admission control, Kyverno):** Intercepts Pod creation requests at the Kubernetes API server, verifies cryptographic signatures and attestations against Rekor/Fulcio and pinned workflow identities, rewrites tags to immutable digests, and enforces container hardening.

---

## 4. Threat Matrix (In-Scope Controls)

### T-01: Direct registry push (CI bypass)

- **Threat / attack vector:** An attacker with registry push access builds an image locally, skipping CI, and pushes it directly to GHCR/ECR.
- **Security control and honest limits:** Keyless image signing in CI (`cosign sign` by digest) + Kyverno `verifyImages` policy requiring a valid signature.
- **Enforcement layer:** Sigstore + Kyverno
- **Stage:** 2 & 3
- **Verification test:** Push an unsigned image from local Docker CLI to registry and deploy -> **Rejected** (`image verification failed: no matching signatures`).

### T-02: Mutable tag overwrite (`:latest` or re-tagging)

- **Threat / attack vector:** An attacker deploys `:latest`, overwrites an existing signed tag (`:v1.0.0`) with a new unsigned image, or swaps a tag between admission check and kubelet pull (TOCTOU).
- **Security control and honest limits:**
  1. Disallow `:latest` policy.
  2. Sign by `@sha256` digest.
  3. Kyverno `mutateDigest: true` pins admitted pods to `@sha256`.
  4. ECR tag immutability in AWS phase.
- **Enforcement layer:** Kyverno + Registry
- **Stage:** 1, 3, 5 & 6
- **Verification tests:**
  - Attack test 1: Deploy `:latest` -> **Rejected**.
  - Attack test 2: Overwrite a signed tag with a new unsigned build and deploy -> Kyverno resolves tag to new unsigned digest -> **Rejected**.
  - Mutation check: Inspect admitted Pod spec -> confirms `image:` is rewritten to `@sha256:...`.

### T-03: Unauthorized workflow, branch, or fork signing

- **Threat / attack vector:** An attacker triggers CI from a fork PR, an unreviewed feature branch, a modified workflow file, or another repository to obtain a valid Cosign signature.
- **Security control and honest limits:** Strict OIDC pinning in Kyverno `verifyImages`:
  - Issuer: `https://token.actions.githubusercontent.com`
  - Subject: exact repo and workflow ref ending in `@refs/heads/main`.
  - The workflow never uses `pull_request_target`, which would let fork code run with base-repo permissions, OIDC included.
- **Enforcement layer:** GitHub OIDC + Kyverno
- **Stage:** 3 & 5
- **Verification tests:**
  - Attack test 1 (fork PR): Open PR from fork -> **Stopped at GitHub layer** (GitHub withholds `id-token: write` token; signing step fails before Kyverno).
  - Attack test 2 (feature branch): Sign image on `refs/heads/feat-test` and deploy -> **Stopped at Kyverno** (valid signature, rejected on subject mismatch).
  - Attack test 3 (other repo or workflow file): Sign from alternate workflow or repo and deploy -> **Stopped at Kyverno** (subject mismatch).

### T-04: Known vulnerable base image or dependency

- **Threat / attack vector:** An image containing HIGH or CRITICAL CVEs is built, or deployed after a stale scan.
- **Security control and honest limits:**
  - Stage 2: Trivy image scan in CI (`--exit-code 1` on HIGH/CRITICAL; `--ignore-unfixed` rationale documented in README).
  - Stage 4: Trivy vulnerability attestation signed via Cosign and verified by Kyverno (result + timestamp freshness).
  - **Limit:** Point-in-time check. A newly disclosed CVE next week will not evict an already-running pod, though Stage 4 blocks new deployments once the attestation timestamp expires.
  - **Freshness cuts both ways:** Once the attestation expires, a legitimate image is blocked too until it is rescanned. Either run a scheduled rescan/re-attest job, or accept manual rescans for this demo.
- **Enforcement layer:** GitHub Actions (Trivy) + Kyverno (Stage 4)
- **Stage:** 2 & 4
- **Verification tests:**
  - Attack test 1 (Stage 2): Point Dockerfile to a vulnerable base image -> **Stopped at GitHub CI** before `cosign sign` runs.
  - Attack test 2 (Stage 4): Deploy image with failing or expired scan attestation -> **Rejected by Kyverno**.

### T-05: Hardcoded secrets in source repository

- **Threat / attack vector:** A developer commits API keys or credentials into git history or source files.
- **Security control and honest limits:** Gitleaks secret scanning runs as Step 1 in the CI pipeline (`--scanners vuln,secret` also enabled in Trivy for built image layers).
- **Enforcement layer:** GitHub Actions (Gitleaks + Trivy)
- **Stage:** 2
- **Verification test:** Commit a dummy AWS or API key to a test branch -> **Stopped at GitHub CI** at Step 1.
  - **Caveat:** GitHub push protection may block a real-format AWS key at `git push`, before CI runs. Use a fake key that Gitleaks catches but GitHub does not, or record the actual stopping layer (GitHub push protection) in `FINDINGS.md`. Either outcome is a valid finding.

### T-06: Privileged pod or root execution

- **Threat / attack vector:** A validly signed image is deployed with `privileged: true` or runs as UID 0.
- **Security control and honest limits:** Numeric non-root user (`USER 10001`) in Dockerfile (required so Kubernetes `runAsNonRoot` can verify UID without starting the container) + Kyverno policies blocking privileged pods and enforcing `runAsNonRoot: true`.
- **Enforcement layer:** Dockerfile + Kyverno
- **Stage:** 1
- **Verification test:** Apply `k8s/bad/privileged-pod.yaml` and `k8s/bad/root-pod.yaml` -> **Rejected by Kyverno**.

### T-07: Compromised long-lived cloud credentials

- **Threat / attack vector:** Static AWS IAM access keys stored in GitHub Secrets or K8s Secrets are leaked and used to push or pull ECR images.
- **Security control and honest limits:** GitHub OIDC federation to AWS IAM role (trust policy `sub` scoped to repo and `main` branch) + EKS Pod Identity for Kyverno's service account to read private ECR.
- **Enforcement layer:** AWS IAM + GitHub OIDC
- **Stage:** 6
- **Verification test (config inspection, non-attack check):** Verify zero static AWS keys in GitHub Secrets or K8s; inspect IAM role trust policy and Pod Identity association.

### T-08: Admission layer bypass

- **Threat / attack vector:** Workloads deploy into excluded system namespaces (`kube-system`), Kyverno webhook is down and fails open, or a lookalike image path (`ghcr.io/owner/signed-and-guarded-evil`) bypasses a loose `imageReferences` wildcard.
- **Security control and honest limits:**
  1. Explicit `failurePolicy: Fail` on verification policies.
  2. Minimal, documented namespace exclusions.
  3. Strict `imageReferences`: the reference must be `ghcr.io/<owner>/signed-and-guarded@*` or `ghcr.io/<owner>/signed-and-guarded:*`, never `ghcr.io/<owner>/signed-and-guarded*`. The trailing bare wildcard is exactly what lets `signed-and-guarded-evil` through.
- **Enforcement layer:** Kyverno + Kubernetes API
- **Stage:** 3 & 5
- **Verification tests:**
  - Attack test 1: Scale Kyverno replicas to 0 and deploy unsigned pod -> **Rejected** (`failurePolicy: Fail`). The API server will most likely return a `failed calling webhook` error rather than a Kyverno message; record the actual error in `FINDINGS.md`. Also check which `failurePolicy` field the pinned Kyverno version uses, since its location has moved between releases.
  - Attack test 2: Deploy unsigned pod to excluded namespace (`kube-system`) -> **Admitted** (documented boundary).
  - Attack test 3: Deploy from lookalike repo path -> **Rejected**.

---

## 5. Out-of-Scope Threats and Availability Trade-offs

| ID | Threat / operational risk | Why it is out of scope / trade-off | Mitigation / architectural note |
|----|---------------------------|------------------------------------|---------------------------------|
| OOS-01 | **Runtime memory or application zero-day exploit:** An attacker exploits a bug inside a running, properly signed FastAPI pod. | Admission webhooks only evaluate workloads at CREATE/UPDATE time, not after the container starts executing. | Runtime eBPF security monitoring (e.g., Tetragon, Falco) and NetworkPolicies. |
| OOS-02 | **Cluster admin (`system:masters`) tampering:** An actor with cluster-admin rights deletes the Kyverno ClusterPolicy or ValidatingWebhookConfiguration. | This model assumes Kubernetes RBAC restricts policy and webhook modification to platform administrators. | Strict Kubernetes RBAC, API server audit logs, and GitOps drift reconciliation. |
| OOS-03 | **Node-level compromise and static pods:** An attacker with root access to a worker node starts a container via `crictl`/`containerd` or drops a static pod manifest into `/etc/kubernetes/manifests`. | Static pods are managed directly by the local kubelet and do not pass through admission webhooks; direct runtime socket calls bypass Kubernetes entirely. | Hardened immutable node OS (e.g., Bottlerocket), restricted node SSH/SSM access, and host integrity monitoring. |
| AVAIL-01 | **Sigstore or webhook outage (fail-closed trade-off):** Fulcio, Rekor, or the Kyverno admission webhook becomes unreachable during a deployment or node scale-up. | Enforcing `failurePolicy: Fail` prioritizes security over availability: new pods cannot be admitted while Kyverno or Sigstore verification endpoints are unreachable. | Run Kyverno in HA mode in real environments and monitor webhook latency; accepted trade-off for this security demo. |
