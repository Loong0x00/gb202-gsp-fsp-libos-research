# Swin block1 → completion consumer protocol (CPU/static only)

## Result

**Recovered the actual PTX polling loop and a concrete host completion-buffer edge, including a negative reset kernel.** The important correction is that the consumer **does not perform an acquire load**:

- Incoming flags are **aggregate +40**, upstream X/Y origins **+48/+52**. Outgoing flags remain **+56**.
- Thread `(0,0,0)` repeatedly issues `ld.relaxed.gpu.global.L1::no_allocate.s32`. **Any signed value >= 0 passes**, not only zero. Negative values cause `nanosleep.u32 64` and another load of the same word.
- After all required words pass, the CTA reaches **`bar.sync 0` before its ordinary input data loads**. There is **no `ld.acquire`, `fence`, `membar`, or atomic RMW** in the eight original module00 1h32 wait/chained entries inspected.
- The host's reset is **`cc_cb_clear`**, a separate original **module06** kernel that writes **`-1`**, not zero. `forward_range` conditionally submits it when **start block == 0**, before block dispatch. This is not an allocation-time assumption and not an unconditional per-frame reset.
- Native descriptor **block2 +0x68 = [1]** routes block1's last-layer completion slot into block2's completion-input suffix. Layer2's **+0x138 = [0]** gathers that suffix. The same **network+0x210 offset table** supplies the producer's outgoing flag pointer and this consumer's incoming flag pointer. This is a native pointer/index chain, not a guessed operator-name DAG.

**Actual captured consumer selection and actual reset execution remain unattested.** Existing trace lines create wait/chained/clear function handles, but record submissions only for preblock, selected block1 tilesync, and finalpost. A function-creation line is not a launch. No new observers were used.

The executable deliverable is a **bounded CPU symbolic control/address reference** with explicit polling observations, barrier/publication/reset intents, and pure host completion routing. It never runs the common arithmetic body, grants data visibility, initializes flags implicitly, or equates the whole native kernel with a plain CPU tile.

## Sources and scope

- Physical DLL, read only: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`, SHA256 **`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`**.
- Original module00: `../nr-ptx-bundle-20260911/modules/module-00-dll-000df0e0.ptx`, SHA256 **`9fa036fc715cb56c9138a1f931db1314fdd444ed30d1c31f66307a6babc7176a`**, unchanged `.version 9.4`, `.target sm_120`.
- Exact standard FP8 wait entry byte range **[5066280,5267755)**; chained **[5267766,5470097)**. Also carved the six standard/non-FP8 and ds/outview wait alternatives for an ordering inventory, without changing any instruction/header. All nine carved entries, including clear, have source ranges/hashes in `evidence.json`.
- Historical factory graph: `/home/user/rt_5090_project/dlss5_model_dump/graph-factory.log` and `graph-factory-blocks.bin`; read the dumper source to distinguish offsets from its misleading labels. No historical program was run. Block headers are pinned in evidence; log supplies nonempty pointed-to vector values, not a new memory read.
- Existing run: `../nr-swin1h-binding-main-20260911/runs/20260911-145411-observer_on/`. Both captured producer argument buffers remain identical. `evidence.json` pins them and records exact trace lines.
- Host addresses below are preferred-image **VAs**, base `0x180000000`; PTX aggregate offsets are **decimal bytes**, host object offsets are hexadecimal.

Only this review directory was written. No GPU, Wine, native PE execution, Ghidra/project analysis, header downgrade, DLL changes, observers, allocation/lifetime operations, or activation/flag readbacks. Capstone and objdump only decoded local file bytes. NVIDIA's PTX memory-model documentation was fetched for the acquire-pattern check (`isa-ordering.txt`, URL and HTML hash retained).

## 1. Original consumer loop and address equations

For standard `..._wait_fp8` and `..._chained_fp8`, define:

```text
H,W          = s32 aggregate +24,+28
X,Y          = s32 aggregate +32,+36       # current tile-view origins
read_base    = u64 aggregate +40
PX,PY        = s32 aggregate +48,+52       # predecessor tile-view origins
write_base   = u64 aggregate +56          # chained only
cx,cy        = %ctaid.x,%ctaid.y
```

Standard wait/chained do not use the inpview override fields +72/+76. ds/outview wait variants load additional ordinary-data fields, but retain +40 and +48/+52 and the same eight-unit wait-footprint construction. They were inventoried, **not included as supported executable entry aliases**.

In the ordinary nonoverflow, nonnegative-dimension domain:

```text
C = ceil((W - min(PX,0))/8)
R = ceil((H - min(PY,0))/8)
dx = X + 8*cx - PX
dy = Y + 8*cy - PY
x0 = floor(max(dx,0)/8)
y0 = floor(max(dy,0)/8)
x1 = min(C, ceil((dx+8)/8) if dx+8 > 0 else 0)
y1 = min(R, ceil((dy+8)/8) if dy+8 > 0 else 0)

thread zero, row-major iy in [y0,y1), ix in [x0,x1):
    index = s32_wrap(iy*C + ix)
    address = u64_wrap(read_base + 4*index)
    repeat:
        v = ld.relaxed.gpu.global.L1::no_allocate.s32 [address]
        if signed(v) >= 0: break
        nanosleep.u32 64
all threads: bar.sync 0
then ordinary arithmetic/input-data body
```

Empty X or Y intervals do not poll. Nonzero thread IDs branch straight to the barrier. No null-read-base guard exists in PTX; host binding/selection is responsible. `%ctaid.z` does not change these addresses.

The source uses the same signed division-lowering sequence as the producer: for a nonzero signed span `n`, `a=s32(n-1)`, `q=s32(a+((a>>31 as u32)>>29))>>3`, extent `s32(q+1)`. The reference interpreter executes these original instructions, signed/unsigned shifts, wrap, branch labels, and the **out-of-line nested polling CFG**. The simpler formula has an explicit bounded geometry domain and wraps the flattened index before the signed-wide multiply. It is not silently used for arbitrary signed overflow dimensions.

### Exact anchors (chained FP8)

- Entry lines **11–18**: +56, +48, +40 and ordinary parameter loads.
- **19–81**: current origin, upstream grid extent, and overlap rectangle.
- **82–92**: thread-zero/empty-row gating and join barrier.
- **146–180**: row/column advance, address calculation and actual negative polling backedge. **Line 169** is the relaxed read; **171–172** test `> -1`; **175–179** sleep and retry.
- **13651–13666**: independently recomputed thread-zero predicate, CTA barrier, and outgoing GPU-release zero store after the ordinary body.
- Standard wait FP8: barrier **line 79**, relaxed read **156**, corresponding sign-test/sleep loop follows. No outgoing release.

### Connection to the captured producer's address set

Captured producer: H224 W384, origin0, grid48x28, +56 **`0x245e0000`**. It intends zero publication at **[0x245e0000,0x245e1500)**, 1344 words.

For an **explicit hypothetical** shifted next-block origin `X=Y=-4`, predecessor `PX=PY=0`, same H/W, read_base equal to that producer base:

- CTA(0,0) waits on `0x245e0000`.
- CTA(1,1) waits in order on `0x245e0000, 0x245e0004, 0x245e00c0, 0x245e00c4`.
- CTA(48,28) waits on `0x245e14fc` only.
- Union for grid49x29 is exactly the producer's 1344 words.

This is a tested conditional address calculation. **The next block's actual origins/grid/arguments were not captured; the example is not relabeled as a runtime launch.** A shifted tile can wait on up to four producer tiles; it is not merely a same-index flag read.

## 2. Host launcher, state and origin binding

Actual 1h layer vtable **`0x1800b8108`**: +8 launcher **`0x1800637b0`**, +38 initializer **`0x1800641c0`**, +40 completion-word count **`0x180063d00`**. Constructor **`0x180061ee0`** copies the descriptor to layer+8, installs this table at **`0x180061f24..1f2b`**, and allocates 0x50-byte state `S=*(layer+0x178)` (`0x18006200a..2057`). Its zero initialization is **host state only**, not GPU flag initialization.

Launcher ordinary/non-upsample branch aggregate `A=RSP+0x70=RBP-0x90`; **96 bytes** are dispatched to backend vtable+28 at **`0x180063c25..3c31`**.

| Field | Exact host origin / native sites |
|---|---|
| A+40 | incoming pointer `I[1]` if global byte **0x1800e06d0** is enabled and input count >=2 (`0x180063ab6..3ae3`); otherwise zero; bound at **3b4b** for standard or **3b82** for special wait |
| A+56 | outgoing `O[1]` for standard/inpview, `O[2]` for ds, gated by that global and output count (`0x180063ae3..3afb`); bound at **3b4f** or **3b6b** |
| A+32/+36 | `-4*max(layer dword+7c,0)` / `-4*max(layer dword+78,0)` (`0x1800639d1..3a65`) |
| A+48/+52 | if predecessor descriptor pointer `P=*(layer+158)` exists: `-4*max(P.dword+74,0)` / `-4*max(P.dword+70,0)` at **`0x180063b89..3bb4`**; otherwise retain explicit aggregate zeroes |

Initializer binds:

```text
S+08  base handle
S+10  base handle alias
S+18  tilesync handle
S+20  wait handle
S+28  chained handle
S+30  standard-family boolean from 0x180062210
S+38  special outgoing (inpview/upsample tilesync)
S+40  special incoming (ds/outview wait)
S+48  backend
```

Native `0x180063b02..3b58`: when S+30 is true, mask = `(incoming!=0)*2 | (outgoing!=0)`. Nonzero mask selects `*(S+10+8*mask)` if that handle is nonzero, else keeps base. Incoming/outgoing pointer fields are still filled. With S+30 false, a usable special outgoing handle+pointer takes priority; otherwise a usable special incoming handle+pointer selects wait (`3b5a..3b86`). The flag global's current runtime value is **not inferred from its on-disk initializer**.

### Predecessor-origin setter is a real descriptor edge

Network constructor calls **`0x18003e200` at 0x180031dae**, before building layers (`0x180031dc4`). That routine:

1. Walks network's copied block descriptors at N+78.
2. Takes the first **layer +138** selector; indexes the containing block's **+68** vector (`0x18003e2a0..2cb`).
3. Selects that source block's **last layer descriptor** (`source.layers.end-0x170`) and stores its pointer into current **layer descriptor +150** at **`0x18003e30f`**.
4. Descriptor copier **`0x18001ec92..ec99`** preserves +150; layer constructor copies to layer-object+8. Therefore the pointer is at runtime layer-object **+158**, precisely the pointer read by the launcher.

For block2's selector0 and block+68=[1], the origin pointer names **block1's last descriptor**. This independently agrees with the completion-buffer pointer routing below; it does not arise from the word "shifted" in a name.

## 3. Completion storage layout and actual graph pointer chain

Let `F=N+210` be a three-level table of byte offsets `[block][layer][completion_slot]`, and `B` the workspace base passed to setter **`0x18003e4e0`**. Each nested vector is a native 24-byte vector. Let `T=*(N+208)` be total completion bytes.

### Offset planning / producer binding

- `0x180036300` initializes T, then walks each layer descriptor's **+f0 completion-slot declaration vector**. For each slot, it calls actual layer vtable **+40** to get a word count (`0x180038d30..8d72`). For this 1h family, slot+40 is **0x180063d00**.
- **`0x180038d78..8d80`** computes `(4*count+511)&~511` — **512-byte rounding**, not merely 4-byte stride. **`8dab..8dcd`** appends old T into F and adds the rounded size to T. No native memory allocation is performed by the reference.
- Workspace setter **`0x18003e54e..e575`** saves B to N+250, supplied size to N+258, sets `N+228 = B` iff T != 0, and uses `B+T` as the ordinary-data region base. Thus the flags occupy a workspace prefix; they are not at the arithmetic output pointer.
- **`0x18003eb10..eb43`** appends **`B + F[b][l][q]`** after ordinary per-layer outputs. `0x18003ed02..ed06` calls setter **0x18002c1e0**, which copies this vector-of-vectors into **block-object+140**.
- Block forward **`0x18002ad92..2aef7`** appends the completion suffix from block+140 to the supplied last-layer output vector, starting after the descriptor's ordinary-output count (default one when +d8 is empty). That becomes the launcher's O. Consequently block1's first completion slot is **O[1] → A+56**, alongside its separate ordinary O[0].

For the selected producer's conditional 1344-word count, its reserved completion slot is **5632 bytes (0x1600)**; only **5376 bytes (0x1500)** are intended producer writes. Padding need not receive a producer publication. This is a host-size computation, not allocation/lifetime authorization or an observed total-T measurement.

### Consumer binding, actual descriptor values

Historical `graph-factory-blocks.bin` confirms block2's **+68 vector length 1** and **+80 empty**, as well as no explicit block+38 ordinary edges. The log gives **+68=[1]** (misnamed `input_layers` by the dumper). Block2 layer's **+138=[0]** is recorded; block1 and block2 each declare **+f0=[0]**.

The native consumers establish the meaning:

1. **`0x18003f010..f09f`** iterates current D+68 source-block values; output selector comes from D+80 or defaults to zero.
2. **`0x18003f0da..f13d`** gets the source block's **last layer**, loads its vector in **F=N+210**, checks the completion-slot index.
3. **`0x18003f144..f15f`** computes **`B + F[source][last_layer][slot]`** and appends it to the current block vector in **N+1d8**.
4. Network forward **`0x18003d282..d301`** appends N+1d8[current] **last** to its block-input vector V, then dispatches the block at `d31b`.
5. Block forward **`0x18002b2d9..b364`** reads layer descriptor +138. It calculates suffix start as **`len(V)-len(block_descriptor+68)`**, bounds-checks each selector, gathers `V[suffix_start+selector]`, and appends to I before layer launch (`b3a6`).

Therefore the concrete historical completion edge is:

```text
block1 producer outgoing:
    B + F[1][0][0] → block1+140[0] completion suffix → O[1] → A+56
block2 consumer incoming:
    D2+68[0]=1; D2+80 empty ⇒ slot0; one source layer ⇒ layer0
    B + F[1][0][0] → N+1d8[2][0] → V completion suffix
    L2+138[0]=0 → I completion suffix → A+40 on one-data-input wait/chained path
```

No allocation-ID equality or name-based dependency is assumed. This static route connects the **same table entry** on both sides. It composes with the captured producer address to identify **what a launch along this route would read**, not proof that the captured runtime selected block2's consumer branch.

Ordinary data routing is separate: with empty block+38 and index>0, `0x18003d0c4..d0da` uses **N+110[index-1]**; workspace setter `0x18003e798..e7c4` populates N+110[b] from the first ordinary output in N+1f0[b]. First-layer implicit input at `0x18002af57..af71` appends V[0], not every completion suffix. The +138 gather then adds readiness pointers. Unsupported extra descriptor inputs/alternative graphs must not be silently erased to force the one-data-input ABI.

## 4. Init/reset/reuse chain — negative clear, conditional entry point

1. Host backend setup saves backend into **N+270**, then calls initializer **0x180036250** (`0x18003d97d..d987`).
2. If T>0 and backend exists, **`0x1800362bd..62ef`** creates exact **`cc_cb_clear`** (`0x1800b1af0`) with block256x1x1. Result is saved to **N+230 at 0x1800362f2**. Creating it is not clearing anything.
3. In nonempty `forward_range`, **`0x18003ccf7..cd2e`** requires `start_block==0`, T!=0, N+230!=0, N+228!=0, and N+270!=0. It constructs a **16-byte aggregate** `{u64 base=N+228, s32 count=low32(T>>2), padding}` at RSP+50; grid X is `u32(count+255)>>8`.
4. **`0x18003cd77..cd7b`** calls backend launch vtable+28 with that handle and aggregate **before the ordinary block loop**. Starting at block>0 skips this branch. There is no demonstrated implicit reset for partial ranges or every frame.
5. Original module06 **`cc_cb_clear`**: `index=mad.lo.s32(ctaid.x,ntid.x,tid.x)`; signed guard `index<count`; `st.global.b32 [base+4*index], -1`. No release/acquire in this clear kernel. Original range **[613177,613656)**, module hash in evidence.

Static intent is thus **reset negative → producer release zero → consumer accepts nonnegative**, with reuse through the workspace-prefix pointer. The test reference returns a reset intent only under these explicit branch conditions and never updates a symbolic memory dictionary as a hidden side effect.

**What this closes:** location/table correspondence, negative sentinel, exact initializer/forward branch and clear kernel; initial flag values need not be guessed. **What it does not close:** actual clear submission/completion, backend stream/command-buffer ordering, reset-before-producer execution for the captured frames, absence of concurrent range users, or reset between frames. Same producer argument bytes in submissions2/5 prove none of those. A stale zero passes the real sign predicate; there is no epoch/generation check in these entries.

The generic CUDA function resolver also exposes `cuMemsetD32Async`, but it was **not used as proof of this reset**. The positive recovered chain above is a named CUDA-style kernel handle → launch-site → original PTX store, independent of generic fill/copy speculation.

## 5. Memory-ordering boundary

A GPU release producer does **not automatically turn a relaxed consumer read into an acquire**. PTX §8.8 requires an acquire operation, or a strong read followed by an appropriate acquire operation/fence. None occurs here. The subsequent CTA barrier synchronizes **that CTA's threads**; it is not a GPU-scope acquire fence reading the producer's publication and not a same barrier shared with another kernel's CTA.

Ordinary waited input loads use `ld.weak.global.cg.v4.u32` (bypassing L1), but `.cg` and `.L1::no_allocate` are cache policies, not substitutes for the missing acquire pattern. A sign-test/control dependency is not an acquire either. Consequently **the flag-loop fragment by itself is insufficient to prove release→acquire publication of ordinary data across CTAs/kernels** under the PTX memory model.

Separately proven API execution dependencies could provide the required data visibility, or selected native machine code could contain stronger ordering than this PTX. Neither is established for the actual unobserved consumer/reset here. We do **not** infer a runtime bug from the missing local proof; nor do we repair the PTX or label relaxed polling native-equivalent to acquire polling.

## Executable reference and verification

**18 CPU/static tests passed.**

```sh
python -B reviews/nr-swin-sync-protocol-20260911/collect_evidence.py
python -B reviews/nr-swin-sync-protocol-20260911/test_protocol.py
python -B reviews/nr-swin-sync-protocol-20260911/protocol_reference.py
```

- `protocol_reference.py`: original standard FP8 wait/chained **prefix interpreter only**, bounded at 10,000 instructions; explicit `(address,value)` polling observations. Returns `needs_observation`, `instruction_budget`, or **barrier_intent**, never native completion or acquired visibility. Negative retries consume budget and emit real sleep intents; no spin-loop-as-noop. Separate closed address formula and conditional producer/reset intents.
- `host_reference.py`: bounded pure 512-byte signal-offset planning and actual descriptor-selected completion-suffix routing. Word counts are explicit caller inputs, not manufactured from operator names. No handles, memory, epochs or lifetime operations are created.
- `collect_evidence.py`, `inspect_host.py`: read-only physical-file/static collector, exact extracted-source checks, frozen instruction-slice hashes and vtable bytes. Reuses prior read-only PE reader imports without executing their writers.
- `test_protocol.py`, `tests.txt`: source extraction/hash checks, original ordering inventory, explicit unknown/negative/positive/stale-zero cases, instruction bounds, nonzero threads, 500 randomized geometry cases each against **both original PTX CFGs**, shifted overlap and union, publication wrap, negative reset branch gates, graph-header/table-edge checks, and frozen host bytes. These test static transcription and symbolic effects, **not native numerical or concurrency parity**.
- `objdump-check.txt` independently decodes launcher selection and reset dispatch. `host-evidence.txt` and the two full bounded build/workspace dumps retain instruction evidence. `evidence.json` pins sources/entry ranges and trace lines.

### Exact remaining gaps / integration contract

1. Capture evidence does not identify an actual launched wait/chained consumer, its argument buffer/origins/grid, or actual `cc_cb_clear` launch. The inspected trace records **creation** for these at lines16/17/116; submissions1–6 only cover the three filtered families. No inference of nonexecution from filtering.
2. Actual backend API ordering, completed reset/publication, visibility, stale-zero exclusion and concurrent workspace reuse remain unproven. No claim that flags were zero initially, negative initially, reset every frame, or still owned/live now.
3. Historical descriptor routing is concrete but must remain conditional for other runtime graphs/variants. Runtime producer metadata does not alone attest all historical layer descriptors.
4. Only the producer's conditional common arithmetic/data-store proof from `nr-swin1h-tilesync-20260911` may be reused by main. Carry the **explicit outgoing release intent and unresolved native ordering/reset contract**. This worker adds no whole-body CPU arithmetic or whole-native equivalence and does not authorize lifetime/readback work.
