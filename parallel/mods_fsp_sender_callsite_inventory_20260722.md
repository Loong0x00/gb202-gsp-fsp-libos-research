# MODS FSP sender callsite inventory — 2026-07-22

Scope: static-only audit of
`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`.
No MODS execution and no live GPU register access was performed for this
inventory.

## Direct sender callsites

The common MODS FSP sender wrapper at `0x185e890` has 18 direct callsites:

```text
0x106c587  0x106c893
0x12352f1  0x1235391  0x1235453
0x1243aae  0x124efe3  0x124f0b1  0x124f151
0x1258756  0x12587a8  0x125a065  0x125e00e
0x126dc11  0x126dd84
0x185e99b  0x185f299  0x18fddb7
```

Other related sender-layer targets:

```text
0x185e260: 5 direct calls
0x185e9b0: 7 direct calls
0x185e0e0: 7 direct calls
0x185e530: 0 direct calls
```

The explicit task IDs reaching `0x185e890` are only:

```text
1, 2, 3, 4, 8, 13
```

No additional direct high-numbered FSP task was found in this binary path.

## Task/subobject summary

| Callsite | Task | Subobject | Payload shape | Current interpretation |
|---|---:|---:|---|---|
| `0x106c587` | `2` | `1` | string payload from caller; the tested GB202 path used six zero bytes | Known FSP floorsweep / PLM preparation path. Runtime probe returned OK and changed `0x8200d0/0x8200dc`, but not `0x8200f8`. |
| `0x106c893` | `2` | `1` | payload built by `0x106bfd0` | Sibling/alternate floorsweep path. Builder appears tied to NVLINK/NVLC slot state; all-zero payload remains the strongest static default on this no-NVLINK GB202 card. |
| `0x12352f1` | `1` | `1` | one byte `0x00` | FSP state/control toggle. Exact semantic still unnamed. |
| `0x1235391` | `1` | `1` | one byte `0x01` | FSP state/control toggle. Exact semantic still unnamed. |
| `0x1235453` | `8` | `1` | one byte from `bl` | FSP fusing-mode related. |
| `0x1243aae` | `3` | `1` | four bytes derived from `ebp` little-endian | Nearby log: `Using the GH100 dramclk devinit WAR with COEFF register = 0x%08x`. Not an L2/f8 candidate. |
| `0x124efe3` | `4` | `1` | one byte from `bl` | Reset-coupling / recovery state related path. A sibling callsite logs unsupported FSP reset-coupling options. |
| `0x124f0b1` | `1` | `1` | one byte `0x00` | Same task-1 toggle on a different object offset. |
| `0x124f151` | `1` | `1` | one byte `0x01` | Same task-1 toggle on a different object offset. |
| `0x1258756` | `13` | `2` | special 8-byte payload; byte 0 initially `0x00`, byte 1 comes from caller, remaining bytes zeroed | First phase of a special task13/sub2 helper. Nearby string handling references `SMSKED_MESSAGE`/`SMHOST_MESSAGE`; this is not the generic PRC knob writer. |
| `0x12587a8` | `13` | `2` | same payload after byte 0 is rewritten to `0x06` | Second phase of that special task13/sub2 helper after the first sender call succeeds. This may be a trigger/commit/cleanup transaction for that helper only. |
| `0x125a065` | `8` | `1` | one byte fusing-mode use case | Explicitly logged as `Running FSP fusing mode for use case:%s(%u)!`. Treat as potentially destructive until proven otherwise. |
| `0x125e00e` | `3` | `1` | compact four-byte transformed integer | Same task-3 family. |
| `0x126dc11` | `4` | `1` | one byte loaded from table at `0x92c0c08 + index` | Same task-4/reset-coupling family. |
| `0x126dd84` | `3` | `1` | compact four-byte transformed integer | Same task-3 family. |
| `0x185e99b` | caller-provided | caller-provided | empty local string; arguments forwarded | Internal wrapper path; no new explicit task ID. |
| `0x185f299` | `13` | `2` | generic PRC knob/value executor payload | Generic PRC write path. It sends once, then calls the PRC readback helper and logs old/new knob values. |
| `0x18fddb7` | `8` | `1` | one byte from `bpl` | Another task-8/fusing-mode family callsite. |

## Decoded nearby strings

Relevant string references decoded from `.rodata`:

```text
0x8c09990  FSP msg transfer or response reception failed -ec : %d, %s
0x8c09e98  Skipping FSP FS because PLMs are already lowered!
0x8c2bf30  Skipping fusing mode use case: %s(%u) as the fuses are already blown!
0x8c2bf68  Requested Fusing Mode use case(%u) is not supported on this chip!
0x8c2b250  Using the GH100 dramclk devinit WAR with COEFF register = 0x%08x
0x8c2b858  Unsupported FSP reset coupling option: %s
0x8c2bfb0  Running FSP fusing mode for use case:%s(%u)!
0x8c2c000  GPU is in Recovery Mode! Issuing another reset to recover from it.
0x8c92a70  FSP: Pri Ring init timed out!
0x90fbef2  PRC_ERROR_INVALID_KNOB_VAL
```

Other high-level strings also present:

```text
-skip_fsp_plm_check and -skip_fsp_fs can't be used together
Cannot use -skip_fsp_fs as the PLMs are raised
-floorsweep disabled via priv mask
HULK License verification requires -hulk_cert command line argument
%s register is PRIV protected. Please acquire HULK license.
OPT_SECURE_UNIT_FLOORSWEEP_WR_SECURE
OPT_SECURE_FUSE_FLOORSWEEP_WR_SECURE
Fsp fusing mode disabled! Fuses for usecase 0x%x can't be blown.
SMSKED_MESSAGE
SMHOST_MESSAGE
UnlockHost2Jtag:Start
UnlockHost2Jtag:End
```

## New sequencing observation

The special MODS task13/sub2 helper at `0x1258756/0x12587a8` is not a
single-message operation:

1. It builds and sends `task=13, subobject=2`.
2. If the first call returns success, it rewrites the first byte of the same
   payload to `0x06`.
3. It sends `task=13, subobject=2` again.

The generic MODS PRC knob write path at `0x185f299` is different: it sends one
`task13/sub2` write request, then invokes the PRC readback helper. Nearby strings
decode as:

```text
After Write PRC, new Knob Value= 0x%x for knob %s (knobId %u), requested value is 0x%x
PRC Write Successful for knob %s (knobId %u). Old knob Value 0x%x. New knob Value 0x%x
```

Therefore the conservative local PRC write-noop probe implemented in
`vm_mods_lab/prc-read-tools/gb202_fsp_prc_read.c` is closer to the generic
knob-write path than to the special two-phase helper. The two-phase helper is
still a useful sequencing lead, but it should not be assumed to apply to every
PRC write.

Important limitation: this is only a sequencing finding. It does not prove that
`0x8200f8`, L2 raw masks, or the latch path are writable. The earlier runtime
tests already showed that simple host BAR0 writes to `0x8200f8`,
`0x8200e0`, `0x8200f4`, and raw FBP0 shadow do not stick after task2-zero.

## Current interpretation

The remaining plausible routes are narrower:

- a valid device/SKU-bound HULK action blob that specifically lowers the
  needed write permissions or performs the register RMW itself;
- a special MODS two-phase task13/sub2 operation whose payload semantics still
  need to be named;
- a VBIOS/FSP/GFW policy path that decides whether task2/PRC effects are
  allowed to reach `0x8200f8` and the raw/effective L2 masks;
- a reset-coupled adoption path after legitimate FSP state changes.

The current evidence does not support treating task8/fusing-mode as a safe
runtime unlock candidate. It is explicitly tied to fusing-mode use cases and
messages about fuses being blown.

## Special task13/sub2 helper priority

The helper body at `0x1258650` has no direct `call` xrefs. It is referenced as
an 8-byte function pointer in `.rodata` at 12 vtable/table locations:

```text
0x92b4dc8  0x92b9278  0x92bb800  0x92bedb8
0x92c1c88  0x92c2dc0  0x92c44b8  0x92c5bb0
0x92c72a8  0x92c8c38  0x92cabe8  0x92cc188
```

Those tables also contain common method pointers such as `0x124f050`,
`0x124f0f0`, `0x125c920`, `0x125ca40`, and `0x12520f0`, which matches a
multi-class virtual method family rather than a GB202-only hidden path.

Current priority: low for L2/f8. It remains useful as an example that task13/sub2
can carry more than one sub-protocol, but the visible string context points to
SM scheduler/host/debug plumbing rather than L2 floorsweep mask control.
