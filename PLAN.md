# Plan: Signed and Guarded

## Stage Numbering Reference

Every threat in `THREAT_MODEL.md` and every test maps to this stage sequence:

| Stage | Description |
|-------|-------------|
| Stage 0 | Threat model (`THREAT_MODEL.md`) |
| Stage 1 | kind + Kyverno baseline (pod hardening, disallow `:latest`) |
| Stage 2 | CI pipeline (Gitleaks -> Docker Build -> Trivy -> Push -> Cosign Sign) |
| Stage 3 | Signature enforcement (`verifyImages` pinned to OIDC issuer and subject) |
| Stage 4 | Scan attestation (Trivy Cosign attestation verified by Kyverno) |
| Stage 5 | Break it (`FINDINGS.md` adversarial bypass and failure-mode tests) |
| Stage 6 | AWS EKS and ECR port (GitHub OIDC -> IAM, EKS Pod Identity, ECR immutability) |
