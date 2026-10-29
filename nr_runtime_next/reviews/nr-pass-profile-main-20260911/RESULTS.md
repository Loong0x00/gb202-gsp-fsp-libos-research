# Live private per-pass tone isolation

Main reviewed the cold-latched three-file runtime delta and exact OFF/P1 original-reference forwarding, reran9 profile sanitizer modes and2 three-layer observer modes, and independently pinned runtime/executor/dependencies. A missing inherited build directory/header was corrected during CPU setup before any GPU execution; no failed deployment/run resulted.

Three fresh private runs, each POST3,768×432, one cold evaluated frame:
- 183140 baseline0efd.
- 183230 candidate f4fe… profile OFF.
- 183320 same candidate profile ON.

All exit0/Guardian0 and signed disk dependencies unchanged, with fenced external-color readbacks. **Baseline and candidate OFF have all three pixel files byte-identical.** All three arms have identical source-A/before-execute bytes and global76-byte control. Same normal reserve, shaders/codecs, guides, order and original NR DLL. No game/SR/Present acceptance or installation/configuration change; fast-exit teardown limitation remains.

Read-only original preblock264 attestation passes all24 records in both profile arms. Effective +172 tones are exactly OFF(2,2,2), ON(2,0,0); all three invocation counters0. Other conditioning/transform fields and selected-call metadata match, excluding opaque addresses. This is more than a setter ACK, but still before-original metadata, not per-kernel memory-effect proof.

## Composed-output difference

- RGB MAE: **0.0188302193**; maxabs0.65625 in linear HDR values.
- Mean linear BT.709 Y: .1974522 → .1818029 (**−7.9256%**).
- Output Y<.01 fraction: .006932% →0% (small counts; not evidence about a broad night scene).
- Alpha identical.

`PROFILE_COMPARISON.png` uses the same fixed CPU preview in all panels, not a claimed game display transform. `verify.py`/`VERIFICATION.json` preserve checks; `TONE_ATTESTATION.json` is the unchanged worker parser's result on actual logs.

**Conclusion:** pinned-community-style later-pass tone defaults demonstrably change this original-NR result despite identical GUI/global control bytes. This does NOT show that the ON image is better, matches the author's configuration, or explains the whole realism gap. Lower average luminance also is not a stand-in for realism.

Encoded B and each layer's raw NR output remain uncaptured. Source/codec equality is provenance, not measured B-byte equality. This is only a tone-profile isolation; no community compressor/compositor/resampler or RR order was transplanted. Other candidate differences remain separate tests.
