# Historical block23: split boundaries and strict entry reference

## Result — conditional entry, **not restored whole block**

Recovered **four separate graph layers**, their exact raw tensor records, original PTX and host gather/launch routes. Block23 is **not a single 16-warp fused kernel**. Its FFWD inpview entry is a **(32,4,1)-thread CTA**, launched over **(ceil(W/8),ceil(H/8),2)**. The two z slices are separate CTAs, not sixteen cooperating warps.

Implemented the complete, unchanged **FP8 non-tilesync layer0 entry**, through its original `ret`, with real layer0 weights. The synthetic 8×8 witness runs both z slices: **8,192 original MMAs**, **786,432 independently checked scalar half operations**, all **524,288 slab bytes**, and **32,768 output bytes**. All original learned loops, async copies, initialization/arrival/wait instructions and polling backedges remain present. No missing activation was zero-filled or reshaped.

**Critical route conflict:** the historical factory(0) spelling has **no `_fp8`**. The actual host initializer selects the **F16** entry for that spelling. That entry's second stage explicitly reads at **slab+524288**, one-past this exact 524288-byte serialized tensor, and continues beyond it. Therefore this review **does not silently claim the FP8 run is the historical default**, join adjacent tensor records, expand weights, or fabricate the rest of block23. A runtime descriptor rewrite/weight conversion could resolve this, but is not established here. The API requires explicit conditional FP8-route acknowledgement and rejects the historical spelling.

```sh
python -B reviews/nr-split16h-entry-reference-20260911/verify.py
```

CPU/static only; no GPU, Wine, GPU compiler, PE execution, deployment or sibling writes. PTX **9.4 / sm_120 / address_size64** preserved unchanged.

## Independently established historical graph and host edges

Fresh DLL-resource/raw/checkpoint comparisons use the original DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`. All four tensors join by **name, serialized shape, size and raw offset**, not a guessed model axis:

| Layer/class | Raw tensor | Raw offset | Bytes | Graph operator count |
|---|---|---:|---:|---:|
| 0 `CCSplitSwin16HFfwd` | `block23.layer0.layer` | 6727901 | 524288 | 10 |
| 1 `CCSplitSwin16HFfwdProj` | `block23.layer1.layer` | 7252265 | 263168 | 3 |
| 2 `CCSplitSwin16HQKVAttn` | `block23.layer2.layer` | 7515509 | 917568 | 17 |
| 3 `CCSplitSwin16HProj` | `block23.layer3.layer` | 8433153 | 263168 | 3 |

Each complete operator list and class independently matches `graph-factory.log`, not merely architecture JSON or kernel names. The serialized `F16` shape is **container metadata, not a dense FP16 matrix layout**. `EVIDENCE.json` includes all checkpoint/upload offsets and SHA256 values.

`host_proof.py` matches the dumper's actual **monotonic 8-byte scan order**, VECTOR offsets/counts and INDEX_VECTOR values, retaining overlapping pseudo-vectors so they cannot silently shift correspondence. Only native-consumed descriptor fields are interpreted; raw words from string-vector storage are not DAG indices. `DESCRIPTOR_VECTORS.json` preserves this association.

The custom block constructor at **0x180040260** installs vtable **0x1800b2460 → 0x18002ac60**, the actual generic block forward. It creates four separate class-specific layer objects, not one fused object. Relevant native gathers:

* Network **0x18003cec2..ced6 / 0x18003d0c4..d0df**: block23's original descriptor has empty block-edge vectors (verified directly against its 0xe0-byte raw descriptor). The non-first-block default gathers `network.primary[22]` into `V[0]`. This is not inferred from the number 23. Runtime extra vectors may append further handles.
* Layer **0x18002af33..af71**: the native empty +90/+a8 default selects `V[0]`. The layer0 log prints neither gather; applying this default is conditional as explained below.
* **0x18002afd4..b046** appends `V[L+a8[j]]`; **0x18002b080..b10e** then appends prior layer outputs selected by **L+90 / L+c0** (single-output-table fallback at b113..b18b).
* **0x18002b19d..b2d3** conditionally appends completion handles selected by **L+108 / L+120**, after the producing layer's activation-output count. These are not activation tensors. +f0=[0] in all four historical layers participates in selecting trailing completion outputs at **0x18002adcb..ae50**.

**Capture limitation:** the dumper saved raw block descriptors, but **not raw layer descriptors**. Present layer vector offsets/counts/values are positively checked. An unprinted layer field is not a byte-verified zero triple: malformed/unreadable fields can also be omitted by this dumper. The default ingress and absence of additional gathers below therefore assume well-formed bounded layer descriptors matching the printed vectors; this is not hidden as a fresh layer-memory capture.

Under that explicit condition, the activation DAG from descriptor evidence and actual consumers is:

```
V[0] = network.primary[22]       # DS22 bridge bytes/readiness NOT certified here
F = layer0(V[0], weights0)
P = layer1(skip=V[0], src=F, weights1)
A = layer2(P, weights2)
Y = layer3(src=A, skip=P, weights3)
```

Completion layer indices are **0→1, 1→2, 2→3**, each selector0, when completion tables are active. The FFWD projection must retain the original input skip; final projection must retain P. A serial list inferred from names would miss both residual edges and completion handles.

## Exact host route and own ABI

Layer0 constructor **0x18006a640** installs vtable **0x1800ba1e8**, whose +8 points to forward **0x18006c7f0**. Constructor copies the actual layer descriptor. Init **0x18006d710** searches that type string for `inpview` and `_fp8`; at **d82e..d844**, it chooses literal F16 `0x1800ba480` versus FP8 `0x1800ba458`. The inpview branch leaves `ESI=4`; backend creation receives `R8D=32`, `R9D=4`, stack z=1 at **d871..d891**. The otherwise non-inpview FP8 path can select eight warps: **that path is not this entry**.

Forward constructs the 56-byte aggregate at **rsp+68** and launches it at **0x18006c92c..c989**:

| Aggregate offset | Exact own source role |
|---|---|
| +0 | input pointer (`%rd1`) |
| +8 | output pointer (`%rd21`) |
| +16 | layer0 slab (`%rd22`) |
| +24,+28 | signed H,W (`%r84,%r85`) |
| +32..55 | unread by this non-tilesync source; fixture deliberately poisons with 0xA5 |

No 88-byte Swin8H ABI, +80 view override, XY origin, or downstream pointer is inherited. Input-view is implemented by **physical ingress addressing**, not invented shape metadata. Host optional token/gate logic at **c886..c928** may choose a tilesync handle and fill additional parameter fields; those routes are outside the CPU entry API.

Fresh DLL-record Zstd decompression equals original module04. Exact FP8 entry byte slice **[212090,307345)**, 95,255 bytes, SHA256 **`0ba5a3da34dbf89de7be7f280e373d6b02c1a7f4fee7cdb0d071e40acb764bf0`**. Slice begins at `.entry`, after the preceding `.visible `; the original module header is separately preserved. Both F16 and FP8 sources for **all four layers** are retained and checked against module bytes. They are not interchangeable.

## Real weight roles and executed computational boundary

Layer0 SHA256 **`63399444cd1c361a295167f7958cc707d8e88ec363da1cbf2ada632dcc741df5`** is hard-pinned by the API. Every dynamic load at all **24 static slab sites** is checked against independently written source closed forms and exact register bits. Every site is traced into actual **E4M3x4 MMA operands**, not assigned a dtype from the container. All 524288 bytes are consumed across z=0,1; none are borrowed from layers1–3.

Source-defined regions:

* **[0,262144)**: first learned MMA projection, original eight 64-channel input slices (seven loop passes plus original unrolled tail).
* **[262144,393216)**: second-loop learned transform operands, two source load groups per warp/pass, followed by the original cubic activation.
* **[393216,524288)**: final learned MMA operands in that same eight-pass loop, accumulating packed layer0 output.

These are actual byte/operand roles, **not a license to reshape regions into assumed dense matrices**. `proofs.weight_offset`, `STATIC_PROOF.json` and `COMPUTATIONAL_PROOF.json` supply own PCs, pass domains, closed forms, typed uses and full coverage.

The other records are separately bound to their own graph layer and host call. Static PTX anchors additionally show:

* Layers1/3 use **72-byte** aggregates: src+0, skip+8, out+16, slab+24, H/W+32/+36. Their learned coefficient loads at slab-relative **262144** flow into `mul.f16x2` (e.g. layer3 `%r264`, layer1 `%r1126`), not FP32 query scalars. Detailed complete matrix/skip layouts and numerical execution are **not certified**.
* Layer2 uses its own **56-byte** aggregate, input+0/output+8/slab+16/HW+24/+28 and actual XY+32/+36. It has separate QKV/attention operations. Source scalar loads at **917504+4*(4*CTA.z+tid.y)** flow through `cvt.rn.f16.f32`; source region starting **786432** supplies attention MMA C half operands. This is different from a layer0 coefficient or the Swin8H slab layout. Its normalization/softmax approximation policies and full learned-layout reconstruction remain outside this entry reference.

## Original loops, async phases, numerics

All **2075** static instructions parse strictly. Learned backedges are **1219→728** (`%r1363=0,64,…,384`, then original tail at448) and **1891→1401** (`%r1460=0,32,…,224`). Each warp executes **1024 MMAs**. Polling backedges **575→571 / 1216→1213** are retained; the fixture need not take them if arrival counts already completed.

Each CTA has **8192 shared input bytes** (two alternating 4096-byte banks) plus **two 8-byte mbarrier objects**, not 16warp shared storage. The actual `bar.sync 0` at PC21 orders initialization. Original `cp.async.ca.shared.global` copies remain pending per thread until its original commit/wait_group0. Actual arrival count is128; original `try_wait` observes completion before the subsequent read stage. Two barrier objects alternate through four phases each. The CPU represents returned **opaque state** by phase identity, not fabricated native token bits.

`Shared` rejects unknown bytes, bounds, alignment and unsynchronized cross-warp RAW/WAR/WAW. A separate last-producer ledger checks every shared read byte, while the independent swizzle map checks every staged write. Each CTA checks **98,304 cross-warp read-byte events**. Banks persist; no barrier clears storage. Out-of-bounds values arise only from the original `st.shared.u32 0` branch.

Only generic arithmetic/memory pieces with matching actual semantics are reused read-only from the pinned 8h dependency chain. `machine-changes.diff` exposes own async parsing/state hooks, u32/u64 conversions, identity symbolic shared cvta, integer/predicate forms and declaration handling. Nothing edits original PTX or removes loops/barriers.

Numerical contract (`NUMERICAL_POLICIES.json`):

* Explicit exact finite **E4M3 dot + half C, RN-even half per original k32 MMA**; native accumulator parity is not claimed. Every one of the 8192 fixture MMAs is compared to the independent forward-fragment oracle.
* Half clamp/abs/two FMA/multiply boundaries preserved. Actual activation constants: -4, +4, **-0.055908203125**, **0.447265625**, **0.89453125**. Integer-dyadic independent arithmetic checks all 786432 scalar operations; this is the original cubic, **not library SiLU/GELU**.
* Independent finite nearest-even E4M3 quantizer exhausts all finite half patterns and checks all output bytes against **forward ISA C placement**, including original register permutation.
* There are **no `approx` instructions in layer0**. No invented rsqrt/reciprocal/softmax policy or omitted attention is smuggled into its result. Those are separate layer2 work.

## Physical entry / exit maps

Ingress, inferred independently from actual copy address equations:

```
in(y,x,c) = 16*(((c//16)*H+y)*W+x) + c%16     # [32,H,W,16], raw E4M3
```

For shared word u=0…1023 in input slice t=0…7 and byte b=0…3:

```
y = 4*(u>>9) + 2*(u&1) + ((u>>6)&1)
x = 4*((u>>8)&1) + ((u>>4)&3)
c = 64*t + 32*((u>>7)&1) + 16*((u>>1)&1) + 4*((u>>2)&3) + b
shared = 4096*(t%2) + 4*u + b
```

Spatial origins add (8*CTA.y,8*CTA.x). This map is a complete bijection; tests check staging against actual async and explicit OOB stores.

Output is **512-channel 4×4 packed microtiles**, not ingress or dense FP16:

```
m = 4*(y%4) + x%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
out = 8192*((y//4)*(W//4)+x//4) + 1024*(c//64)
      + 512*((c%64)//32) + 16*lane + 2*j + c%2
```

CTA.z produces channels `[256*z,256*(z+1))`; the other half is **not silently zeroed**. All input/output maps are independently bijection-tested. Channel labels here derive from ISA fragments, not checkpoint axes. DS22 must supply the ingress representation and be complete; layer1 must consume the packed result **and retain the separate original skip**. Neither bridge is asserted by this review.

## Verification and limitations

Nine CPU tests pass: fresh source/route contracts; both z slices with all real weight bytes and independent arithmetic; exhaustive finite half→FP8 quantization; map bijections; reverse-warp scheduling; 12×12 corner/OOB trace with different warp ordering; explicit policy/route/geometry/alias/nonfinite/missing-byte rejection; pending-copy/phase/arrival/shared-hole failures; new integer forms and unknown-op rejection.

Interior plus corner tests execute **over2000** static instructions; exact remaining PCs are in `EDGE_PROOF.json`. Dimension1 broadcasting is outside the API's multiples-of4 H/W domain, and polling/alternate divergence branches may not execute. This is **not** mislabeled full static-path coverage.

Synthetic 8×8 output SHA256 **`eeb1ed8db81583bb30b829fdd4e102b25fa7c65b4f8bca91a0a43441d9ac4602`** is a CPU reproducibility result, **not a native golden activation**. API bounds H,W to multiples of4 in [8,32], exact disjoint H*W*512 spans, and the actual host grid. Arbitrary native timing, all possible interleavings, predecessor readiness, descriptor mutation, F16 weight conversion, tilesync flags, remaining split calls, full block23 and whole-model recovery remain explicitly unverified.
