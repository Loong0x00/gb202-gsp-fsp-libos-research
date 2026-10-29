# SOURCE-ONLY Counter Lifecycle Audit

## Result

`cc_cb_clear` is the 13-instruction / 16-byte-parameter entry identified in `IDENTITY.json` (module `module-06-dll-010e2a40`, SHA-256 `b5ef…1354`). Its PTX establishes only this device-program equation:

```
i = ctaid.x * ntid.x + tid.x
if i < N: *(int32 *)(B + 4*i) = -1
```

where `B = param_0[0:8]` and `N = param_0+8` (`u32`). It does **not** establish native happens-before, live device contents, every epoch, complete buffer ownership, or that all counter consumers see the result.

### Exact host binding and fields

The relevant object is `this = r15` in `outer_execute.txt` and `this = rsi/rdi` in the binding fragments; the identical displacement dataflow below is the source-level basis for the field names.

| Field | Source evidence | Source-only meaning |
|---|---|---|
| `this+0x230` | `host-1800362bd.txt` PCs `0x1800362d3`–`0x1800362ef` loads the exact `cc_cb_clear` string and calls through `([this+0x270]->vtable+0x20)`; `0x1800362f2` stores the result to `[this+0x230]`. `HOST_XREFS.json` independently reports this string reference. | clear-function handle/result |
| `this+0x270` | `0x1800362bd` loads it as the binding context; `outer_execute.txt` `0x18003cd24` loads it as the launch context. | clear binding/launch context |
| `this+0x228` | `workspace_bind.txt` `0x18003e55c`–`0x18003e575` sets it to incoming base `A` iff `E=[this+0x208]` is nonzero; outer `0x18003cd18` uses it as PTX parameter base. | clear base `B` (here `B=A` when bound) |
| `this+0x208` | outer `0x18003cd00`–`0x18003cd39` requires nonzero and computes `N = (u32)(E >> 2)`; bind `0x18003e55c`–`0x18003e567` forms `A+E`. | clear byte extent `E` |

The second name reference is the registration/availability check at `host-18003c280.txt` PC `0x18003c3d4` (also in `HOST_XREFS.json`); it does not itself store the handle.

The host launch setup at `outer_execute.txt` PCs `0x18003cd30`–`0x18003cd7b` creates the exact 16-byte PTX argument area:

```
param[0:8]  = B = [this+0x228]
param[8:12] = N = low32([this+0x208] >> 2)
block.x     = 0x100
grid.x      = (N + 0xff) >> 8
function    = [this+0x230]
context     = [this+0x270]
```

Consequently, the host-requested clear range is

```
[B, B + 4*floor(E/4))
```

and is `[B, B+E)` only when `E` is divisible by four. The code’s `dword` truncation means neither a sub-four-byte `E` nor any `E mod 4` tail is cleared by this PTX invocation.

### Begin/range behavior

`outer_execute.txt` copies input `begin` to `r13` at `0x18003ccb8` and `end` to `rbx` at `0x18003ccb1`. It validates `begin <= end` (`0x18003ccd5`–`0x18003ccd8`) and returns for `begin == end` (`0x18003ccee`–`0x18003ccf1`).

* For a nonempty `begin == 0` range, PCs `0x18003ccf7`–`0x18003cd7b` conditionally submit the clear before the outer per-item processing entry at `0x18003cd81`.
* For a nonempty partial range (`begin != 0`), `0x18003ccfa` branches directly to `0x18003cd81`; this source block makes no clear submission.
* Even at zero begin, submission is skipped when any of `E`, clear handle, `B`, or context is zero (tests at `0x18003cd07`, `0x18003cd13`, `0x18003cd1f`, `0x18003cd2b`).

Thus zero begin changes host **submission behavior**, while partial begin bypasses it. This is not proof that a submitted clear completes before later native work.

### Relation to last-layer auxiliary offsets

Workspace bind computes `P = A + E` at `0x18003e55c`–`0x18003e567`. Its later descriptor-derived addresses add offsets to `P`, e.g. `0x18003e735`–`0x18003e743` and `0x18003ec45`–`0x18003ec4d` form `P + O = B + E + O` (for the corresponding descriptor/table offset `O`). Therefore the clear range ends at `B + 4*floor(E/4)`, while these shown auxiliary-address equations are based at `B+E`.

If `E` is word-aligned and the relevant `O >= 0`, the shown auxiliary regions begin at/after the cleared region, not inside it. Source supplied here does **not** establish that every called “last-layer auxiliary” buffer uses these exact descriptors, that every `O` is nonnegative, or ownership/non-overlap; those are retained unknowns.

## Promotion boundary for the existing fresh-counters-`-1` caller condition

The supplied sources support a limited promotion: for this object state, a nonempty outer call with `begin=0`, nonzero `E/B/handle/context`, submits the identified clear setup before this host routine starts processing its range. The PTX says the submitted kernel writes `-1` to its bounded dword range.

They do **not** support promoting the literal FFN/QKV/decoder prerequisite to an unconditional claim that their counters are fresh `-1` at every caller, epoch, buffer, or actual kernel consumption. Main must inspect: (1) call sites/arguments proving the relevant FFN/QKV/decoder paths invoke this outer routine with `begin=0` and nonempty range; (2) command/stream and synchronization implementation behind the indirect launches, to establish ordering/completion; (3) descriptor and allocation construction to map the counter addresses to `[B,B+4*floor(E/4))`; and (4) reuse/epoch ownership and any intervening writes.

## Retained wrong/rejected hypotheses

* **Wrong hypothesis retained:** `this+0x208` is the clear base. Rejected by outer PCs `0x18003cd00`–`0x18003cd39`, which shift it right by two to construct `N`; the base passed to PTX is separately loaded from `this+0x228` at `0x18003cd18`.
* **Wrong hypothesis retained:** a partial block range receives a proportional/partial reset. Rejected for this host block: nonzero begin jumps at `0x18003ccfa` to `0x18003cd81`, skipping the only shown clear launch.
* **Unresolved, not promoted:** a host call appearing before the loop proves native happens-before. The supplied source does not reveal the called launch API’s stream/synchronization semantics.

## Scope

This was a bounded static, source-only review of the supplied files. No execution or tests were run.
