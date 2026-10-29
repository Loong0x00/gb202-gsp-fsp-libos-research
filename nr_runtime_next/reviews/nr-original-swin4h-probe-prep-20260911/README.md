# Disabled original plain4h inpview oracle — CPU/static preparation

**Gate FALSE. Host compiled/type-checked, NEVER executed. No GPU/Driver/Wine invocation.**
The one frozen prediction is a reference-policy measurement target, not a native golden or tolerance acceptance. Scope exception: the first legacy reference test invocation rewrote a sibling `COVERAGE.json` with byte-identical content; see `SCOPE_EXCEPTION.md`. The corrected verifier redirects that write locally and denies other external writes.

## Exact identity, independently carved

Fresh pinned DLL scanning selects **module02**, not module01 or a wait/tilesync/DS/outview entry:

* DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
* Fatbin DLL `[7332096,9751384)`, 2419288 bytes, SHA256 `13f9782f9fcc2757a2273231fef4642672b3bcfcd74be8bf7407b31cef634631`.
* Untouched whole ELF DLL `[8161200,9751384)`, **1590184 bytes**, SHA256 `9cba6bc0001a80c902ee20fd5638bf442bdf0674aaada676d67a6d1b89ca0aaa`.
* Exact symbol **`cc_tinlayout_fused_swin_4h_128_4_inpview_fp8`**, ELF symbol74, text section75, file `[690816,730112)`, 39296 bytes, text SHA256 `7fb40d8c7927aad6efa7fa2952c1d343b7e021ea62ba73c5c83f3ff02499d9e7`.
* Fresh original PTX module decompression SHA256 `ea5afe1ed2dbfb125a91db607210c6905632e047e22d40f7f2ffdb1bd77e8a3e`. Entry `[1899483,2114298)`, 214815 bytes, SHA256 `805e92d0dcceee5aaaf6c300ed2483abf0776be7ac1d8ff9fed03ff30f38e24c`. **PTX9.4 / sm_120 unchanged**, never recompiled.

Every selected SASS instruction's two 64-bit encoding words match the ELF text bytes. Full disassembly, raw section metadata, compiler resources and tool/source hashes are retained. All ELF sections remain intact, including **14982-byte `.nv.capmerc.text`**, Mercury info/relocations and globals. Loading this ELF, matching attributes, or future matching FP8 output does **not** prove selected native/Mercury representation or actual game selection.

## Own ABI and minimal launch

The own4h declaration and six parameter loads independently establish one aligned **88-byte aggregate**:

| Bytes | Role |
|---|---|
| 0..7 | own input pointer `%rd10` → `%rd1` |
| 8..15 | own output pointer `%rd11`, sole root of all global stores |
| 16..23 | actual block9 slab `%rd12` → `%rd2/%rd5` |
| 32,36 | signed H,W = 8,8 |
| 40,44 | signed X,Y = 0,0 |
| 80,84 | signed input-view overrides = 0,0 |
| [24,32), [48,80) | unread, zero in host template; **+72 is not a downstream pointer** |

One grid **(1,1,1)**, block **(32,4,1)** = all four full warps /128 threads, noncluster, dynamic shared **0**. Flattening to128x1 or borrowing32x2 is rejected. No flags, texture/surface bindings, native pointers, inter-CTA dependencies or input-view repacking. Own allocation spans are nonzero, 256-aligned, nonwrapping and pairwise disjoint, including both output guards.

* Input **8192 bytes**, frozen synthetic DS8-produced 8x8x128 ingress from accepted4href, SHA256 `76302b3cfd47283519f4bb67ceb87d35b032440c4a124cea86156f63358cda41`. Produced by four synthetic actual block8 DS CTAs, **not captured game activation**.
* Output **8192 bytes** packed 4x4 microtiles. Own output allocation8704 bytes =256 prefix +8192 payload +256 suffix; ABI+8 points256 bytes into it.
* Slab **actual block9, 197184 bytes**, SHA256 `934cebc771cfa1ed086f47f018426090e14ca4326dcb22843cbc17dff9851c32`. Fresh raw `[147498206,147695390)` and checkpoint `[147500658,147697842)` match the complete slab; upload offset147522048 is provenance, not an address bound to the kernel. Not block10 and not block8's69936-byte DS slab.

## Independent full footprint

`STATIC_REVIEW.json` gives every PTX parameter/global site, all opcode counts, recurrences and barriers, and every SASS memory/control site. `sass_footprint.py` evaluates **all128 lane integer/address/control traces**, with floating/tensor/load results marked UNKNOWN; UNKNOWN affecting an address, predicate or branch rejects. It is **not a numerical SASS emulator**. Live-in scratch masks are checked with both0/all1. All8 branches are classified; only three finite learned backedges exist before EXIT; the self-branch at0x98d0 is unreachable post-EXIT padding, not a wait loop.

| Census | Original PTX | Original SASS |
|---|---:|---:|
| Static instructions, including source branches / SASS padding | 5404 | 2456 |
| Input global load sites | 16 | 16 |
| Slab global load sites | 115 | 63 (13 scalar+50 vector) |
| Output b128 store sites | 4 | 4 |
| Shared sites | 64 | 64 (48 LDS+16 STS) |
| Original128-thread barrier sites | 10 | 10 |
| Dynamic k32 MMAs, complete CTA | 2816 | 2816 |

SASS loops `[0x12f0,0x2650]`, `[0x2eb0,0x30a0]`, `[0x3650,0x3a80]` have80/16/48 static MMAs, each four passes; outside128 MMAs per warp. Own PTX loop PCs832..1334,1882..1931,2102..2203 use induction0,32,64,96. Source and SASS have704 dynamic MMAs per warp, not2h-derived counts.

SASS barriers: `12e0,2910,2ea0,30b0,3640,3ae0,69f0,7510,90e0,98b0`; EXIT98c0. Every original shared lane/byte/epoch read and write multiplicity agrees with the fresh PTX footprint after subtracting the independently derived1024 SASS bias. The accepted reference's strict producer/RAW/WAR/WAW proof is rerun with all128 participants; later upper-half shared data is retained, not reset. Full global/shared event records are retained.

Input and output each cover `[0,8192)` exactly once. All slab reads lie in `[0,197184)`; unique197136 bytes; unread `[98304,98320)`, `[98576,98592)`, `[197168,197184)` remain in the upload. Per-warp/lane slab byte sets match PTX; compiler coefficient-load reuse removes26624 repeated byte events only in `[98320,98576)` and `[196912,197168)`. SASS219648 versus PTX246272 slab byte events is explicitly **not** misreported as identical load multiplicity.

Ingress is E4M3 `[8,H,W,16]`: `16*(((c//16)*H+row)*W+col)+c%16`. For output, `m=4*(row%4)+col%4`, `lane=4*(m%8)+(c%8)//2`, `j=4*((c%32)//16)+2*(m//8)+(c%16)//8`; offset is `2048*((row//4)*(W//4)+col//4)+512*(c//32)+16*lane+2*j+c%2`. These are different bijections, not a reshape. Four SASS stores73f0,7500,97a0,98a0 address `2048*tile+512*warp+16*lane`, sixteen bytes per lane, yielding all8192 bytes exactly once.

## Shared accounting: derive, then conditionally query

Own4h original evidence independently gives:

* PTX user shared declaration **8192**;
* ELF `.nv.shared` / cuobjdump compiled extent **9216**;
* all SASS user addresses **[1024,9216)**, bias **1024** (UMOV0x400 + noncluster CTA base, not2h extrapolation);
* actual compiled registers **167** (source `.maxnreg168` is a ceiling), stack/local0, constant0=984, one barrier ID, texture/surface/sampler0.

The disabled host separately queries Driver function attributes. Because own ELF != own user size, it conditionally queries `CU_DEVICE_ATTRIBUTE_RESERVED_SHARED_MEMORY_PER_BLOCK`; it requires user attr8192, reservation1024 and sum9216 **only after those values were independently derived here**. Unsupported query, differing registers/accounting/architecture or cluster requirement fail before allocation/launch; no attribute setter, dynamic-shared substitution or fallback. These4h Driver values remain **unmeasured** and can require Main review; equality is not evidence of codepath identity.

`evidence/main2h-*` snapshots preserve the newly landed accounting erratum/results:191319 rejected ELF==funcattr before alloc/launch;191601 original and own4096 compiler witness report4096 function +1024 device reservation against5120 ELF;191747 separately approved original2h CTA matched4096/4096 bytes, cleanup/Guardian0. Those observations explain the accounting distinction; **none supplies4h counts, offsets or parity**.

## Frozen numerical prediction and future ownership protocol

Prediction SHA256 **`0422ff26b9c9dedc3e4f547330b27b62bc9f037059739324e6c3a1340dacd312`** was copied/pinned before any possible future Main GPU invocation and recomputed from the exact input/slab, host zero/unread template and guard-biased synthetic pointer packing. Every warp reaches original final barrier/ret.

Explicit policies: finite E4M3 exact dot plus half C, RN-half **after each k32 MMA**; exact mathematical zero becomes+0; source half2 arithmetic/E4M3 conversion order preserved; RSQRT reference RN-even FP32 on positive normals only; RCP reference RN-even FP32 with subnormal output flush and unsupported/FTZ-zero rejection. These are not native tensor accumulation or `approx.ftz` oracles. Own4h PTX mul/add/fma counts320/160/128 versus SASS HMUL2/HADD2/HFMA2 counts288/128/160 show possible contractions, including square-sum chains; no full rounding-equivalence claim.

All8192 bytes compare exactly, with per2048-byte microtile and FP8 diagnostic errors available. Prefix0xa5/suffix0x5a must remain unchanged; payload poison is prediction XOR0xff, so an exact match cannot retain any initial payload byte. On mismatch poison collisions do not establish runtime store coverage. Input/slab must read back unchanged. **Exit2 is a valid numerically mismatching measurement, not tolerance acceptance; never refit, reseed or change policies after GPU observation.** Runtime/guard/read-only/cleanup errors are operational failures.

Host ownership/status/error/drain logic is scoped reuse from robust2h preparation. All CUDA statuses and first failure are logged; failed launch/sync forbids readback; failed cleanup drain skips individual frees/unload and attempts context destruction. GateFALSE appears both before main filesystem/Driver access and inside proposed_run. No CLI/environment bypass. No runnable approval harness is supplied: any future Main run needs separate exact approval, serialization/no-games/headroom/watchdog/Guardian and its own copied artifacts. Do not execute this preparation host, even to test the blocked branch.

## Verification

`bash reviews/nr-original-swin4h-probe-prep-20260911/verify_cpu.sh`

* Fresh carve/PTX byte checks, full reference and independent footprint checks.
* **15 reference tests**, redirected local coverage output with external-write audit denial.
* **9 preparation tests**, **8319 CUDA-free C++ packing/negative checks**, including all88 aggregate-byte mutations and all8192 output-byte mutations, layout bijections, guards, aliases/wrap/misalignment, swapped roles, wrong geometry, obsolete ELF==attr, reservation failures and UNKNOWN SASS address/control/opcode negatives.
* CUDA13.3 header assertion; g++ C++20 optimized host build and unoptimized full-body syntax check; ELF dynamic-dependency inspection. Host **never invoked**; no linked CUDA runtime/driver.

General native numerical parity, real plain-variant selection, predecessor readiness, multi-CTA execution, model/image/history fidelity and Mercury selection remain unproved. No installed content was changed; the byte-identical sibling metadata-write exception is disclosed separately, not hidden under a blanket no-writes claim.
