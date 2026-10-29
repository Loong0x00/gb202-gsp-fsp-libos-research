# Optional Guardian publisher design — not applied

The reviewed production input was
`/home/user/rt_5090_project/astral_pin_monitor/astral_hsr_guard.py`, 25,489
bytes, SHA-256
`8947300c02c179db59343038086be52175b59847b2b7f9eddd971af3118fc413`.
The base copy is under `base/guardian/`; all proposed code is under
`proposed/guardian/`. No live Guardian, launcher, game, Wine prefix, hardware,
or production file was changed or invoked.

`patches/GUARDIAN_PUBLISHER_OPTIONAL.patch` adds an opt-in publisher. Without
`--publish-hsr-native-health`, the existing Guardian behavior and defaults are
unchanged. Enabling publication additionally requires all of these explicit
arguments:

- a hash-pinned, owner-controlled `d5-hsr-build-integrity/v1` receipt;
- a hash-pinned, owner-controlled, reviewed `LOCAL`
  `d5-hsr-local-route-policy/v1` receipt;
- the exact native build ID;
- a hash-pinned `osslsigncode`-compatible Authenticode verifier.

The build receipt must enumerate exactly the game executable, retained original
NVUnity, signed DLSS/DLSSNR files, owned NVUnity proxy, format bridge, native
host and native runtime. Every current file is SHA-256 checked. Signed inputs
must also pass the pinned verifier and the receipt's signer-subject match.
Metadata fingerprints and both receipt expiry times are checked before each
publication; drift/expiry raises the existing fail-closed exception/kill path
and the lease is revoked first.

The route receipt must say `scope=LOCAL`, `reviewed=true`,
`decision=permitted`, route `hsr-nvunity-late-post-v1`, and explicitly say both
`vendor_authorization_claimed=false` and
`protection_bypass_permitted=false`. The resulting wire policy value means only
this reviewed local route decision. It is **not** and must never be described as
vendor anti-cheat authorization.

At startup the optional publisher removes a stale lease, but does not arm until
the unchanged hardware path has read its baseline and three valid pre-launch
frames. Launch/attach remains after hardware and receipt arm. During the loop:

1. the existing stable IT8915 frame validation runs;
2. the existing absolute and ratio thresholds run;
3. trip revokes before logging/killing;
4. only a valid non-tripping sample with a live game can answer a valid,
   current 80-byte random challenge with a 112-byte lease;
5. monitor failure, exception, interrupt, timeout and final exit revoke before
   kill/exception/exit handling.

The lease is atomically replaced, owner-only, valid for at most 2,000 ms, and
carries nonzero semantic/heartbeat/publisher generations. Missing, unsafe,
malformed, future, pre-arm or checksum-bad challenges remove/withhold the lease.
No process-name presence alone publishes health.

No approved receipts are included here. The examples in `receipt-templates/`
are deliberately `reviewed:false`/`decision:denied`; they cannot arm the
publisher. Main must produce real receipts for the exact cold-reviewed build
and current signed files. Existing historical HSR signature evidence is useful
review input but does not attest this unaccepted native build or grant policy.
