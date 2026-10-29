# Main checks, not HSR game acceptance

Main rechecked the final local followup code: two directional fences, mandatory
D3D11 GPU dependency for prepare-only frames, nonblocking slot handling, actual
SR-call-scoped view observation and optional external POST/Retire proposal.

- `make ... check harness`: 57 CPU production-helper checks, 68-export/source
  checks and MinGW build passed (`../../HSR_MAIN_CPU_CHECK.log`).
- Actual Wine fake-NVUnity/core/feature harness passed in the isolated
  test directory recorded by `../../tests/hsr_fake/CURRENT_RUN`: original forwarding counts 1/1/1,
  resource getter slot8 used once, slot9 zero, no native host before coherent
  success. This invokes fake APIs, not actual HSR/NGX/GPU work.
- Source and FormatBridge input manifests verified against local files.

Do not apply OPTIONAL_NATIVE_EXTERNAL_POST.patch unchanged: main now has WuWa
self-identity registration and deferred builtin POST. The proposed global
Attach requirement/self rejection would break WuWa, and pending phase / RR POST
must be preserved while adding external HSR POST acknowledgement and retirement.
Main has not applied that optional patch or deployed this candidate.

Actual HSR numeric AppID, same-resource SRV usage, Guardian publication and
D3D11/D3D12 GPU interop remain unverified. PRE remains unimplemented; a possible
same-format R11 pre-SR route is only documented in reviews/HSR_PRESR_PLAN.md.
No anti-cheat/protected startup component or live Guardian was changed.
