# NR Style enum audit — CPU/static/public web only

Audited 2026-09-10. **No Main/frontend/runtime edits, DLL patches, GPU, Wine, or game execution.** All new files are under this review directory. Retained binaries were read only.

## Decision

**The existing UI is mislabeled and excludes raw Style 2. Its stored 0/1 values are already raw values, not a logical Natural/Cinematic enum needing an implicit +1.** The supported naming/mapping is:

| Existing stored / NGX raw value | Correct name | Current Chinese label |
|---:|---|---|
| 0 | Default / 默认 | 自然 — wrong |
| 1 | Natural / 自然 | 电影感 — wrong |
| 2 | Cinematic / 电影感 | Not selectable; rejected by current runtime |

This is supported by **actual three-item combo construction and unchanged NGX parameter write in the locally retained original RenoDX add-on**, the exact retained NR DLL's integer parameter read, and an independent public Vulkan implementation's combo/call code. It does not depend on video opinions, string adjacency alone, or assuming an INI index is a raw enum.

Consequently the reported Style 1 / five-layer run was **raw Natural, not raw Cinematic**, under the audited direct path. Five layers do not turn value 1 into value 2. This correction does **not** by itself explain all small visual changes or prove that Cinematic would improve that scene.

**Do not silently change existing 0→1 or 1→2. Do not automatically enable Style 2.** See proposed semantics below.

## 1. Primary local binary proof

### Exact inputs

| Read-only path | SHA-256 | Identity |
|---|---|---|
| `/home/user/rt_5090_project/dlss5_model_dump/nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` | 165,840,496 bytes; PE version `310,8,0,0`, original filename `CL 38718415` |
| `/home/user/Downloads/dlss5-leak-inspect-20260829/renodx-dlss5.addon64` | `87aef9ddd937c7241e6bf8d8efea0045d63559135e254c60dab316db3d3a4aee` | 391,168 bytes; file version `0.2026.0827.2036` |

Both image bases are `0x180000000`. Addresses below are **RVAs**, not file offsets or live process addresses. These are retained originals, not the localized add-on. Hashes were recomputed; signature authenticity was not revalidated in this audit.

### Add-on: three actual options, one unmodified integer all the way to NGX

`addon-style-proof.txt`, `addon-static-probe.txt`, and executable CPU assertions in `verify_static.py` establish:

1. At RVA `0x11345`, the combo's first pointer is loaded from string RVA **`0x423e0 = "Default"`** and stored at `[rsp+0x50]`.
2. At `0x1135e`, string **`0x42438 = "Natural"`** is stored at `[rsp+0x58]`.
3. At `0x1136a`, string **`0x42440 = "Cinematic"`** is stored at `[rsp+0x60]`.
4. At **`0x1134c`, `mov r9d,3`** supplies the item count. `r8` points to that pointer array, `rdx` to an integer current index, `rcx` to **`"NR Style"` at `0x42450`**. The UI callback is called at `0x11384` through table offset `0x408`.
5. The index is initially read at `0x11328` from global **RVA `0x5a778`**; on edit, `0x11394` reads the integer selection and **`0x1139c` exchanges it directly into the same global**. No +1/-1. The subsequent integer-to-text path writes config key **`NRStyle`**, whose pointer is loaded at `0x1146e` (string RVA `0x42460`); config callback at `0x11484`.
6. At **`0x14a9f`**, `rdx` receives **`"DLSSNR.Style"`**, string RVA `0x41fd8`. At **`0x14aa6`**, `r8d` receives the same global **`0x5a778`** directly. At **`0x14ab1`**, the call is **`[vtable+0x20]` = `Set(const char*, int)`**. No translation between combo value and NGX value.

The easily missed fact is the pooled **Default** string: searching only near `Natural\0Cinematic` falsely suggests two entries. The pointer array and count prove three. This is stronger than simply observing words in a binary.

### Exact e16bcf… NR: direct integer read; no front-end enum translation

`static-probe.txt` and the PE-unwind-bounded function dump `style-functions.txt` show:

- `DLSSNR.Style`: file offset **`0xadb58`**, RVA **`0xae958`**.
- Reader function: RVA **`0x19f30..0x1ac2a`**.
- At `0x1aa06`, `r12d` is zeroed. At `0x1aab7` the destination integer is initialized to zero.
- **`0x1aaad`** loads the Style key; **`0x1aabc`** loads **vtable `+0x60` = `Get(const char*, int*)`**; `0x1aac0` calls via the indirect-call guard thunk.
- `0x1aac6` reads the returned integer. `0x1aad1..0x1aae2` checks the NGX failure prefix `0xbad00000` and substitutes zero on failure. **`0x1aae6` writes that integer unchanged to control field `+0xec`.** There is no +1/-1 or 0/1-only validation in this read block.
- A later apparent control consumer, function **`0x21bb0..0x22a43`**, reads field `+0xec` at **`0x224e7`**, bounds it against a selected descriptor's `+0x64` count, and converts/scales it (`0x224e2..0x22505`; multiplier at RVA `0xb0d6c` is `1/128`). This is **not a proved universal style maximum**: the selected descriptor/count and complete model semantics were not reconstructed. Do not infer every model accepts/distinguishes all values just from this consumer.

ABI interpretation is checked against the locally available NVIDIA header at commit **`a291cc7d2cc642a51566f3dfd5376f635cd1b284`**, [`include/nvsdk_ngx_params.h#L53-L71`](https://github.com/NVIDIA/DLSS/blob/a291cc7d2cc642a51566f3dfd5376f635cd1b284/include/nvsdk_ngx_params.h#L53-L71): eight Set entries followed by eight Get entries, signed integer slots 4 and 12 respectively. It provides the parameter ABI, **not an NR-specific named enum**.

### What the binary proof does / does not establish

It establishes the original integration's exact three-value name→raw call mapping and this exact NR DLL's consumption of that raw integer. **The names are recovered from the add-on, not from named enum symbols inside the stripped NR DLL.** No NVIDIA-authored 310.8 NR enum declaration was recovered. Thus this is primary integration/call proof, not a claim to possess the full official NR SDK source.

The local official DLSS headers searched contain no NR style enum. Current public Streamline `include/sl_dlss_nr.h` at checked commit `2122257e0fce486f91b385aa63b9a09b0a34b363` returned 404. The retained ZIP's `sl.dlss_nr.dll` was also inspected **in memory without extraction/execution** (SHA-256 `9f6672e5e0170dc118a3188d21bda187e1fc1aa3502895b21ab846d23165c11d`): `DLSSNR.Style` exists at RVA `0x4d810`, but no Natural/Cinematic strings were found. Embedded source paths / any source index are metadata, not proof of the missing enum body or source availability. See `streamline-static.txt`.

## 2. Independent public source with actual numeric/call evidence

Git smart-HTTP worked despite the reported GitHub API rate limit. Commits were obtained by `git ls-remote`/fetch and snapshots preserved as text under `sources/`; see `sources/COMMITS.txt`. No GitHub API-derived commit assumptions.

### bmitch87/DLSS5VKLayer

Pinned **`0fd9a6a5e19081ae38a77582f1397697212984ee`**:

- [`gui/passdialog.cpp#L99-L104`](https://github.com/bmitch87/DLSS5VKLayer/blob/0fd9a6a5e19081ae38a77582f1397697212984ee/gui/passdialog.cpp#L99-L104): ordered combo `{Default,Natural,Cinematic}`; reads/writes integer `currentIndex()` directly. `writePass` at line 135 stores that integer in `pc.style`.
- [`core/ngx_snippet.cpp#L468-L479`](https://github.com/bmitch87/DLSS5VKLayer/blob/0fd9a6a5e19081ae38a77582f1397697212984ee/core/ngx_snippet.cpp#L468-L479): **`ParamSetUI(s.params, "DLSSNR.Style", t.style, &seh)`**; helper at lines 110–113 calls `p->Set(n,v)` directly.
- [`README.md#L374-L383`](https://github.com/bmitch87/DLSS5VKLayer/blob/0fd9a6a5e19081ae38a77582f1397697212984ee/README.md#L374-L383) explicitly names raw `0 Default / 1 Natural / 2 Cinematic`.

This project uses unsigned Set while the retained add-on and Main use signed Set. Values 0/1/2 have the same integer magnitude; this distinction does **not** imply a logical index offset. The exact NR reader uses signed Get as above. The public project does not pin its DLL hash to our e16bcf… input, so it is corroboration, not a hash-specific execution test.

### criso2hd-alt/DLSS5-Image-Converter — important historical mislabeling

Pinned **`138786e0690c9ae0b230e8e3d8db662605b96062`**:

- [`dlss5_converter/settings.py#L13-L23`](https://github.com/criso2hd-alt/DLSS5-Image-Converter/blob/138786e0690c9ae0b230e8e3d8db662605b96062/dlss5_converter/settings.py#L13-L23): `NR_STYLES = ("Default", "Natural", "Cinematic")`, explicitly explains its prior two-entry labeling bug.
- [`dlss5_converter/runtime.py#L376-L384`](https://github.com/criso2hd-alt/DLSS5-Image-Converter/blob/138786e0690c9ae0b230e8e3d8db662605b96062/dlss5_converter/runtime.py#L376-L384): writes **clamped selected integer**, not integer+1, to `[RenoDX.DLSS5] NRStyle`. `len(NR_STYLES)` is three. Its nearby “only two styles” comment is stale, not executable mapping.
- Actual correction commit **[`3bdcbd6ecaddd243d2ef0b7df7f405f5c3cb34ae`](https://github.com/criso2hd-alt/DLSS5-Image-Converter/commit/3bdcbd6ecaddd243d2ef0b7df7f405f5c3cb34ae)** changes `(Natural,Cinematic)` to `(Default,Natural,Cinematic)` and says the old index 0 hit Default and Cinematic was unreachable. Saved as `sources/ImageConverter-style-fix.patch`.
- **Do not use historical README/ROADMAP “Natural versus Cinematic” numeric image differences as calibrated raw 1 versus raw 2 evidence.** README still says “only two styles”; the ROADMAP associates tests with **RenoDX Generic v4.1.5**. Historical results may carry the earlier mislabels. The repo writes INI and relies on an externally supplied add-on; it does not itself prove every RenoDX build's INI→NGX mapping. Our retained add-on's actual direct write supplies that missing call evidence for its own hash.

## 3. Style 2 crash evidence — bounded, not universal

Public pinned source **jlrouzies-fr/DLSS5-Feeder `76a08db83652617cfe4192eeecf9e46bfc008382`**:

- [`README.md#L220-L234`](https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/76a08db83652617cfe4192eeecf9e46bfc008382/README.md#L220-L234) reports a **Metro 2033 Redux / NVIDIA Smooth Motion** run: null read on the present path 1–2 seconds into boot, before the feeder feeds a frame. It labels the RenoDX setting **v4.6+**, says it still occurred without Luma, and suggests `NRStyle=0` to recover.
- [`src/dlss5-feed.cpp#L413-L427`](https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/76a08db83652617cfe4192eeecf9e46bfc008382/src/dlss5-feed.cpp#L413-L427): warning is gated by `g_renodx_v46` and INI integer 2; explicitly **warns without rewriting the user's choice**. The host variant copies the same warning.
- [`DLSS5-Swapper issue #167`](https://github.com/rakanki911/DLSS5-Swapper/issues/167) (opened September 5) quotes that warning in a Call of Duty 4 / feed32 **0.12.0** log. **This is propagation of the reference-machine warning, not an independently proved Style-2 crash in CoD4.** Saved HTML/plain text under `sources/swapper-issue-167.*`.
- The same current Feeder source [`src/dlss5-feed32.cpp#L2522-L2571`](https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/76a08db83652617cfe4192eeecf9e46bfc008382/src/dlss5-feed32.cpp#L2522-L2571) implements three choices and says it follows v4.7, but retains stale “two-entry” historical comments. Treat the current array/count as code evidence, not those comments as proof that every older build had two choices.

**Boundary:** this is a configuration-specific report for the RenoDX v4.6-family/Smooth Motion integration, not a universal prohibition in e16bcf… NR. The report has no matching add-on/NR SHA-256, no exact first-bad or fixed build, and does not establish behavior in our direct Vulkan path without RenoDX. Conversely, enum/call validity does not establish crash-free rendering here. Do not claim “all Style 2 unsafe”, “fixed in v4.7”, or “works on the user's machine”. No such execution was authorized or performed.

## 4. Current local path and non-destructive proposed semantics

`local-code-evidence.txt` records file hashes and line locations:

- `/home/user/rt_5090_project/dlss5_linux_frontend/core.py:79`: `NRStyle` min 0 / max 1 / default 0; line 1202 serializes the same integer.
- `/home/user/rt_5090_project/dlss5_linux_frontend/app.py:59,319`: labels `[自然,电影感]`, direct combo.
- `native/runtime/pipeline.cpp:96,289`: rejects `style>1`, directly sets `DLSSNR.Style = control.style`.
- Frozen release pipeline has the same rejection/direct assignment (exact path recorded in evidence text).
- Old `/home/user/rt_5090_project/dlss5_vk_bridge/dlss5_vk_bridge.cpp:2675`: same direct style; another explicit fallback sets zero, not a remap to Cinematic.

### Proposed follow-up (not implemented)

1. **Immediate label correction only:** retain accepted values `{0,1}`, display `默认（raw 0）` and `自然（raw 1）`; explain that Cinematic/raw 2 is currently unavailable in this runtime. Keep default 0. Preserve profiles, INI, protocol values, and frozen artifacts bit-for-bit.
2. Define persisted/wire `NRStyle` explicitly as **raw NGX style**. Existing profiles with 1 retain raw 1, even if their old display said Cinematic. Announce the old label error rather than guessing original artistic intent. No background migration, fallback rewriting, or +1 conversion.
3. If later authorized, add **explicit opt-in** raw 2 as a separate capability-gated choice and update compatible UI validation, protocol/host/runtime checks, diagnostics, and tests together. Old frozen runtime remains incapable: refuse with a clear message instead of silently clamping to 1 or remapping existing values.
4. If a new UI insists on a two-item *logical* Natural/Cinematic selector, use explicit item data `{Natural:1,Cinematic:2}` in a **new, versioned UI mapping**, with stored raw value 0 represented separately as Default. Do not reinterpret historical `NRStyle=0/1` as that new logical selector.
5. CPU regression tests should assert legacy raw round-trip 0→0 and 1→1; default remains 0; label/item-data alignment; no automatic Style 2; old-runtime rejection of explicit 2; any future authorized 2→2 emission. Real output/safety testing is separate and requires user authorization.

## Verification and residual uncertainty

- Read-only SHA-256 and PE version checks, ASCII string/RVA mapping, Capstone disassembly, PE unwind-bounded function decoding.
- `python reviews/nr-style-enum-audit/verify_static.py` **PASS**: hashes, three exact label pointers, combo count, shared global index, direct NGX Set slot, exact NR Get slot and control store. Output: `verification.txt`.
- Reproduce broader scans with `python .../static_probe.py <retained DLL/add-on>`; no PE is loaded as executable code.
- Public commits resolved through Git, selected source snapshots retained, source correction diff inspected; API rate limit did not prevent commit pinning. Failed raw header/source URLs and unhelpful search pages are retained as failed probes, not evidence.
- Source hashes are recorded in `SHA256SUMS`. No claim of image equivalence/difference, complete model count reconstruction, runtime safety, or availability of official 310.8 NR named-enum source. **The label/raw call mapping is proved; automatic switching to raw 2 is neither warranted nor performed.**
