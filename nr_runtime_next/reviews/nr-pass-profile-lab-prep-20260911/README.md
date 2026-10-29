# Private per-layer tone candidate — PREP ONLY

**CPU tests and crossbuild passed. No GPU, Wine, harness execution, deployment, installed-setting change, or original signed-file edit. Main must review/approve before any run.**

This isolates one difference against **pinned community C e237f895623742b761f9e5f00067cb3dc62619f4** (`PassProfiles.h`): later passes default LocalTone to zero. It is **not** an author's configuration, a community-host port, a new GUI feature, or evidence of improved image quality. A fixed-N CPU compositor comparison cannot test this conditioning change; P1 is deliberately identical.

## Candidate

- Source cloned from `../nr-swin-consumer-main-20260911/source`, verified against all **92 source-file pins** and Main's approval manifest where present. Inherited build artifacts were excluded (do not mistake an ancestor DLL for this candidate).
- Runtime: `build/cross/dlss5-native-runtime.dll`
  - SHA256 `f4fe75f36eea3537e4ee2b5226be15363456d93cd7f37e93cf370b3672e773f3`
  - Main baseline runtime: `0efd06383925b2e41a9c84d38746317de89ef8907ebb93c03be6858ee58c2690`.
- Crossbuilt-only private executor: `build/cross/image_chain_probe.exe`
  - SHA256 `38d80e106a0b725037d9487cb1958f2ac35a5d3837d9d8738ffab6171a1e7980`.
  - Main's existing executor accepts only 1/5 layers and rejects a new runtime hash. Its local clone changes **only** the argument restriction to exactly 3 layers/1 frame and the candidate/trace identity gate. Its controls, source restoration, guides, readback/fence/retirement and watchdog code remain literal Main source. No runner/deployment script was added.

### Three-file runtime delta

`source/native/runtime/lab_pass_profile.h` adds a 38-line private policy. `entry.cpp` latches it during `DLL_PROCESS_ATTACH`. `pipeline.cpp` wraps the existing configure call at **both Create and Evaluate**, using the existing zero-based internal layer index.

| Cold-load environment | Layer 1 | Layers 2/3 | Global request / codec controls |
|---|---:|---:|---|
| `D5R_LAB_PASS_PROFILE` absent, empty, or invalid | global tone | global tone | unchanged |
| exact `OWNED_STATIC_OFFSCREEN_TONE_200` | global tone | positive float zero | unchanged |

The exact token is the only opt-in. `1`, `true`, other case, prefixes, suffixes, spaces, and truncation are rejected to OFF. The environment is never polled on a frame and the latch cannot change between Create/Evaluate, Reset, or later frames. Use a **new process** for each arm; do not unload/reload to toggle inside a live process. The runtime cannot authenticate the experiment owner—keep this DLL private and never install it.

OFF and P1 pass the **original request reference** into the **unchanged configure function**. ON later layers copy the request locally and change **only** `local.control.local_tone`; no user-global mutation. This is exact old runtime control/dataflow behavior when OFF, **not a binary-identical DLL or a measured OFF pixel-parity claim**. The private policy zeros every later valid internal layer if explicitly enabled; the prepared executor intentionally permits only three layers and one frame.

Preserved byte-for-byte: normal reserve (`max(Budget/10,1 GiB)`), original NR loading/bootstrap and identity IAT path, observer/ABI allowlists and 32-attempt cap, public headers and six exports, shaders/SPIR-V/embedded codecs, Source A ingress, encode/compose parameters, order/SR contract, guides, reset/history policy, independent feature/parameter blocks and duplicate rejection, barriers, submission and retirement code. One original NR Create and one original NR Evaluate per successful layer remain in their original loops.

## Later Main-owned experiment: approval required

`LAB_PLAN.json` pins the candidate, executor, prior dependency hashes, source A, global control bytes, and intended arguments. It is **not approval or an executable launcher**.

1. Main independently reviews `SOURCE_DIFF.patch`, `HARNESS_DIFF.patch`, build hashes and the existing identity/Guardian policy. Use the same candidate DLL in **both** arms; only the profile environment differs. Never run in a game directory or install these files. All signed dependencies remain exact original pins, including NR `e16bcf15…fc8e` and Core `bdad96fd…283`.
2. Two fresh private cold processes/directories; **exactly one first evaluated frame, three independent layers**, 768×432. No warm-up, no history reuse, no second frame. Same source A SHA256 `0161224fd94c3131492de22c5dd55c5204f0cd4e8afe0fb615644fdab29e6ef6`. Same original fixture synthetic zero motion / constant .375 depth; source is restored, not self-fed. Same POST fixture, **no actual SR execution**, no game/Present proof.
3. In **both** arms set the existing metadata-only opt-in `D5R_FINALPOST_TRACE=OWNED_STATIC_OFFSCREEN`; keep `D5R_DIAGNOSTIC_LAYER_CAPTURE` unset. Profile OFF: unset `D5R_LAB_PASS_PROFILE`. Profile ON: exact token above, set **before process creation**. Keep all other environment/controls identical. Global tone stays **2** in both `pixels/control.bin` files, with the same style2 / intensity2 / structure2 / skin2 / autoMask1 / preset0 / paperWhite1 / transfer.6 / color1. No codec or GUI adjustment.
4. Record independent process/environment and loaded-file identity receipts, all output streams and complete trace; require original signed files unchanged, successful Evaluate, exact 3 reported calls, three distinct feature IDs with Create/Evaluate counts 1/1, successful Guardian/exit and fenced composed-output readbacks. Fast fenced exit has the **same pre-existing teardown limitation**: no normal DLL-teardown acceptance.
5. Compare **both** `pixels/control.bin` to the expected 76-byte value in `LAB_PLAN.json`. Compare source A and `frame-01-before-execute.rgba16f` hashes/bytes; compare `case.json` controls/guides/format metadata. No input/codec constant change is allowed. Compare composed outputs only after all identity/input/metadata gates pass; no quality threshold is predicted.
6. Run the read-only gate (CPU file parsing only):
   ```sh
   python3 -B reviews/nr-pass-profile-lab-prep-20260911/attest.py OFF_RUN ON_RUN
   ```
   This gates **metadata**, not the independent identity/input/fence gates above. Do not treat its PASS alone as approval or complete A/B acceptance.

### Actual-argument attestation, not a setter ACK

The unchanged observer snapshots the exact allowed preblock264 aggregate **before forwarding the original call**; it never follows embedded device addresses or changes launch arguments. `attest.py` requires exactly **24 saved records = 3 × [clear16, preblock264, tilesync96, chained96 ×4, finalpost184]**, contiguous submission indices, exact module/name/route/size and successful persistent save receipts. All **three** preblocks must have:

- `+172 f32`: OFF **(2,2,2)**, ON **(2,0,0)** (bit-exact positive zero).
- `+200 u64`: **0,0,0**, with cold T1/T2/T3 zeroed.
- Matching non-tone scalar/transform/conditioning region and selected-launch metadata across arms; opaque addresses are not compared between processes.

The existing **32-attempt** budget fits **24** calls, not two three-layer frames (48). Attempts lost to reads/save/ABI/filter/coverage problems still consume budget. **Any** drop, skip, sticky uncertainty, missing/extra artifact, unexpected sequence/module/size/epoch, incomplete executor receipt or wrong tone rejects this gate. Do not truncate a longer run or accept only the three successful preblocks. If model/provider gating produces something other than the expected tuple, reject the effective-tone claim rather than trusting the user's tone field. Kernel function handles are **not** NR feature handles.

## Deliberate capture / proof gap

**Encoded B and per-layer raw NR output are NOT captured. Do not claim same B bytes, raw-output parity, full end-to-end parity, or a video/author match.**

The cloned runtime has only readonly host argument/module snapshots; the old image harness fences/readbacks its **external color before/after the whole chain**. Its legacy diagnostic sleep is not a runtime B/raw capture lifecycle. B and ping textures are private runtime resources; ping0 is overwritten by layer3. Safe per-layer capture would need new owned-image copies and explicit submission/fence/retirement bookkeeping, not merely an extra final readback. No proven existing B/per-layer capture lifecycle was present in this baseline, so no broad merge or observer mutation was attempted. Source/codec equality is provenance, **not observed B equality**. Before-original args also do not prove per-kernel GPU effects/completion.

## Verification

Reproduce only the allowed checks:

```sh
python3 -B reviews/nr-pass-profile-lab-prep-20260911/verify.py
```

- Nine ASan/UBSan CPU modes using actual extracted configure/Create/Evaluate bodies with mocked backend: OFF literal reference, ON per-layer profile and full parameter maps, invalid-token OFF, P1 OFF/ON, immutable cold latch on both call sites, independent handles/parameter blocks, three duplicate-rejection variants, exactly one call/layer, evaluation failure and history/reset behavior. All global/codec request bytes remain unchanged.
- Seventeen unchanged Main observer sanitizer modes; two additional CPU observer mocks prove 24 first-frame records fit and a second frame hits the unchanged cap, without modifying original call arguments/counts.
- Read-only attestation parser: synthetic positive fixture plus **30 negative mutations** (loss, size, module, route, counter, tone, control and executor-count failures). These fixtures are **not GPU observations**.
- Runtime and executor Windows crossbuild only. Six public exports equal pinned Main; public ABI headers byte-identical. All 92 ancestor source hashes rechecked after build. `VERIFICATION.json` / `verification.log` record evidence.

No visual/effective-live-tone claim is made until Main's separately approved first-frame A/B supplies actual artifacts.
