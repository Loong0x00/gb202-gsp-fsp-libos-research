# Submission record — 2026-10-13

## NVIDIA PSIRT private email submissions

Sent via the user's already-authenticated Gmail session to NVIDIA PSIRT. Gmail displayed `Message sent` for both messages.

1. Subject: `GB202 FSP runtime management services remain unavailable after malformed-message robustness testing`
   - Source: `PSIRT_FINAL_EMAIL_1_RUNTIME_DOS_SANITIZED.txt`
   - SHA-256: `c30e72b83ec68d5ff3dd9a02174275ff271979389c434b45436098bacb9887f9`

2. Subject: `GB202 stale WPR2 state can block stock GSP-RM initialization across cold boots`
   - Source: `PSIRT_FINAL_EMAIL_2_WPR2_SANITIZED.txt`
   - SHA-256: `a2f35e670604a860da790156f5fcac571987ed62bd484a76053ab3c3ab74b96a`

Both messages request a supported repair/recovery method for the already affected board, an appropriate service/RMA path if no field repair exists, and invite NVIDIA to reply directly for additional sanitized information.

No attachments were sent. No proof of concept, exact packet data, private local paths, hardware serial identifiers, or implementation details were included.

## Public GitHub report

Created a new public issue in `NVIDIA/open-gpu-kernel-modules`, referencing #1080:

- Issue: https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1442
- Title: `GB202: stale WPR2 after abnormal GSP shutdown can block subsequent stock initialization`
- State at verification: OPEN
- Body source: `GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md`
- SHA-256: `b6db78cbe4ac2dbf65ed19c1283b1bb23d707e39740f2614e79319c977247186`

The public issue contains only driver/firmware initialization and recovery behavior. It excludes trigger implementation, non-public interface details, proof-of-concept material, private local paths, and personal contact information.

## Verification time

`2026-10-13T07:18:58+08:00`
