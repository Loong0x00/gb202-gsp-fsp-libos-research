# HSR physical diagnostic result — no NR acceptance

Run: `hsr-runs/20260910-113832-native-ingress-probe-NR-OFF-physical-user-operated`
Candidate: `e3263cea269ccc083ba3166089d7c75cbc67c3da6a9649467734567ad18af35e`
User operated the actual desktop; no Gamescope/input automation/screenshots.
User reported operation complete and game exited. Main checked the current
process list, inactive unit, RESTORED.json and rehashed all seven original
executable/owned/signed/Guardian baseline files successfully.

## What the real log proves

- 455 retained Evaluate samples, through sequence 53400; all logged original
  calls exactly once and original SR results successful. Sequence also counts
  other events and is not an exact Evaluate count.
- Actual resource formats remain 26/33/19.
- View capture armed in every retained diagnostic. CAS installation succeeded;
  subsequent status is already-installed. The first GetLastError=183 after a
  successful install is not itself a failure result.
- The observer saw 3322 CreateShaderResourceView calls, but zero matching motion
  or depth resource identities inside the scoped original SR evaluation. No
  exact motion/depth typed-view contract has been attested.
- Core Init and Init_Ext resolutions were observed, as was core
  NVSDK_NGX_D3D11_Init_ProjectID resolution. No intercepted numeric Init return
  event was seen. ProjectID resolution is NOT proof of ProjectID invocation.
- Logged appid=0 is the unset capture variable, NOT a proven actual AppID zero.
- Native host/runtime/helper were not installed, legacy service was temporarily
  removed, and no native NR completion/acceptance is claimed.

## Offline follow-up, no further user login requested yet

1. Verify the private Init_ProjectID export ABI independently of public static
   Init_with_ProjectID. Local official nvsdk_ngx.h documents the public API but
   explicitly excludes ProjectID Core/Snippet interfaces for NGX_SNIPPET_BUILD;
   do not alias these function signatures by assumption. Inspect official static
   SDK wrapper libraries/retained real modules read-only as needed.
2. Add scoped actual SRV binding observation (SDK-proven context slots and
   permission-safe CAS/lifetimes), not only view creation observation. Views
   may have been created outside the current capture scope; that is a hypothesis,
   not yet a demonstrated cause. Log unexpected formats without accepting them.
3. Preserve exact original forwarding, strict 37/21 attestation until actual
   evidence supports any different conversion contract, late loading, Guardian,
   and completed D3D11 retirement proof. Never invent a numeric identity.

CPU-only isolated workers own `reviews/hsr-projectid-abi/` and
`reviews/hsr-binding-diagnostics/`. No new game launch or deployment is requested
while this evidence is being analyzed. Main native development/production
Guardian integration and full HSR NR game acceptance remain incomplete.
