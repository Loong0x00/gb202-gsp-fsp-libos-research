# GB202 R570 post-selection domain-frequency adjustment

Date: 2026-08-16  
Safety boundary: offline clear-PMU analysis only; no GPU setter or workload.

## Arithmetic at `0x202c2c28`

The input and output are u16 MHz. Two object types are accepted:

```text
type 0: delta_mhz = signed_s32(+4) / 1000, truncating toward zero
type 1: product = mulw(signed_s16(+4), input_mhz)
        delta_mhz = arithmetic_shift(product, 12)
        if product bit 11 is set:
            delta_mhz += +1 when product >= 0, else -1

sum = signed_s16(input_mhz + delta_mhz)
output_mhz = max(0, sum)
```

The s16 narrowing before the negative clamp is visible as `slliw 16; sraiw 16`; it is
not a saturating u16 add. The signed-Q12 negative rule above is the literal instruction
behavior and must not be silently replaced with ordinary round-to-nearest.

## Object choice at `0x202c4746`

Normally the object at domain `+0x3c` is used. When the group-level dual-selection flag
is set, both `+0x3c` and `+0x44` objects must be type 0; the one with the larger signed
s32 `+4` value wins.

## Active-domain walk at `0x202c4786`

The PMU saves the original selected frequency, walks every active type-1 domain entry,
selects its relation, and applies the chosen adjustment object. If the transformed result
differs from the frequency saved before the loop, it sends that result through the
relation query at `0x202c3e6e` and replaces the working frequency with the projected
result. The comparison is against the original loop input on every iteration, not the
previous iteration's input.

This creates a real multi-stage reason for a domain's initially selected frequency to
differ from the later materialized frequency:

```text
initial selection
  -> per-domain literal/Q12 adjustment
  -> V/F relation reprojection
  -> next active-domain adjustment/reprojection
```

## Four-object order at `0x202c8fde` and mode dispatch at `0x202c904a`

The clear PMU also exposes the exact order used by one clock-domain/program
materialization path. Starting from the u16 working frequency, `0x202c8fde`
applies:

```text
global clock-group object +0x38
  -> selected owner object +0x3c or +0x44
  -> owner object +0x80
  -> peer object +0x3c
```

Every arrow calls the bit-exact `0x202c2c28` primitive and feeds its u16 output
into the next call. This order cannot be reduced to an unordered sum: a literal
offset followed by Q12 scaling produces a different result from the reverse
order.

`0x202c904a` dispatches two visible modes. Mode 1 runs the full four-object
sequence. Mode 2 first runs selected owner `+0x3c/+0x44` and owner `+0x80`; for
object types 6/7 it resolves a linked active object and then runs the full
four-object sequence on that linked object. Other object types return after the
two-call prefix. The executable reconstruction exposes both branches and rejects
a missing linked object instead of inventing one.

## Same-generation host-side name and control-flow cross-check

The stripped R570.151 MODS executable supplies an independent x86-64 copy of the
same operation:

- `0x072f6370` accepts the same two object types and implements the same signed
  kHz/1000 and signed-Q12/bit-11 rounding rules, including s16 narrowing before
  the negative clamp.
- Its invalid-type message is `Invalid Clock Domain offset - type : %d`, so
  **clock-domain offset/adjustment** is now a name supported by same-generation
  host code rather than a name inferred only from the PMU arithmetic.
- `0x06ddb4c0` saves the original frequency, applies the domain/program
  adjustments through `0x072f64b0` and `0x072f6370`, then invokes a quantization
  virtual method only when the adjusted result differs from that original.
  This independently corroborates the PMU stage order.

The nearby `CLK_DOMAIN_35_PROG_CLIENT_FREQ_DELTA_ADJ` RPC is not enough to name
each PMU object as a user/client offset. Its MODS wrapper at `0x06dec6b0` first
sends a separate RPC and then calls `0x072f8b00`, whose visible job is to build or
expand a monotonic frequency list. Likewise, separate strings prove that Factory
OC adjusts P-state tuples, but do not identify which compressed PMU adjustment
slot contains it. The executable model therefore keeps neutral object names
instead of conflating factory, client and per-V/F-point deltas.

Raw decompiler evidence is retained in:

- `mods_clk_domain30_adjust_helpers.c`
- `mods_clk_domain30_methods.c`
- `mods_freq_delta_functions_try.c`
- `mods_freq_delta_direct_callees.c`
- `r570_pmu_ordered_adjustment_pipeline.c`

## Executable reconstruction

`bug_inverse/algorithm/gpu_inverse/domain_adjustment.py` implements the arithmetic,
dual-object choice, four-object order, mode dispatch and callback-driven
relation-reprojection loop. Its tests include negative literal truncation, positive
and negative Q12 half-bit cases, s16 wrap/clamp, a non-commutative order
counterexample, mode-2 linked-object behavior, and a two-relation counterexample
proving the comparison uses the original input.

This stage is not enabled in the default R610 digital twin because the current R610
group flags and adjustment-object values have not been read back. Enabling invented
zeros or guessed objects would make the trace look more complete while reducing its
truthfulness.
