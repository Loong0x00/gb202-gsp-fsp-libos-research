# GB202 R570 clear-PMU V/F relation search reconstruction

Date: 2026-08-16  
Scope: offline analysis of the clear R570 PMU image; no GPU control call or workload was
issued.

## Recovered data path

The V/F relation group is registered at PMU `0x202f64d0` as group enum `0x0b`, transfer
identity `0x2610b0`, group size `0x30` and object size `0x80`. This exactly matches the
same-generation host registration. Its point-evaluation path is:

```text
relation object + selected bank/range
  -> boardobj_lookup(point group, point index)
  -> evaluate_vf_point 0x202c5b28
  -> evaluate_vf_point_impl 0x202c5c76
  -> {u16 frequency_mhz, u32 voltage}
  -> optional relation-type-specific voltage adjustment
```

`evaluate_vf_point_impl` first maps the relation's clock-domain index through the clock
domain group. In base mode it reads a fixed u32 voltage plus a mapped u16 frequency. In
table mode it reads an eight-byte indexed entry containing the u16 frequency and u32
voltage. The optional adjustment is now closed instruction-by-instruction: evaluation
mode 0 preserves that value; mode 1 is accepted only for point object types `0x0c/0x0d`
and replaces the output voltage with the point object's u32 at `+0x0c`. Other mode/type
combinations reach a firmware assert.

## Search directions

PMU `0x202c52d2` resolves a requested frequency. PMU `0x202c50a4` resolves a requested
voltage. Both use the same upper-midpoint core:

```text
lo = relation_bank.first
hi = relation_bank.last
repeat:
    old_lo = lo
    mid = (lo + hi + 1) >> 1
    (freq, volt) = evaluate(point[mid])
    stop if requested == selected_axis(mid) or old_lo == hi
    lo = mid
    if requested is below selected_axis(mid):
        hi = mid - 1
        lo = old_lo
```

The frequency-to-voltage routine then evaluates the adjacent point to distinguish the
open interval and returns the ceiling V/F point. The voltage-to-frequency routine returns
the floor V/F point. Both contain additional relation-type/flag-dependent endpoint status
handling; the virtual solver currently reproduces point selection and explicitly leaves
those exact private status codes outside its claim.

For secondary banks, PMU `0x202bba02` translates the selected primary point index as:

```text
secondary_index = primary_index - primary_relation_lower + secondary_relation_lower
```

Bank 0 uses point group `DAT_ram_200103b0`; later banks use
`DAT_ram_20010410`. Relation range fields are at object `+0x20/+0x22` for bank 0 and
`+0x2e/+0x30 + 8*(bank-1)` for later banks.

## Multi-relation traversal and arbitration

The domain wrappers at `0x202c3c4e/0x202c3d5e` scan their configured relation range in
ascending order. Internal status 0 continues scanning; internal `0x41` means a boundary
was selected, is consumed by the wrapper, and becomes public success. It is therefore a
control-flow sentinel here, not an error to propagate blindly.

`0x202c40f6` evaluates each active relation clamp from the same original input and takes
the minimum result. Its comparison makes a later equal candidate replace the earlier
winner. Separately, `0x202c3fbe` takes the minimum terminal upper bound across active
domains, but only replaces on strict less-than, so the earlier equal bound remains the
winner. These different tie rules are preserved by `relation_arbitration.py`.

## Executable reconstruction

`bug_inverse/algorithm/gpu_inverse/vf_relation_search.py` implements:

- `select_voltage_for_frequency`: upper-midpoint search, neighboring point and ceiling;
- `select_frequency_for_voltage`: upper-midpoint search and floor;
- endpoint clamps and a complete midpoint/comparison trace;
- `map_primary_index_to_bank`: the recovered secondary-bank index formula.
- `apply_r570_point_voltage_mode`: the type-`0x0c/0x0d` mode-1 voltage replacement.
- relation-range `0/0x41` traversal and both minimum reducers with their distinct tie
  rules.

`digital_twin.VFCurve` now uses these primitives instead of a linear scan. Each routine's
trace labels the exact R570 addresses and states that this is same-generation relation
search math, not proof that R610's new group-`0x11` tuple selector is identical.

Run the focused tests:

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm
PYTHONPATH=. python -m unittest tests.test_vf_relation_search -v
```

## Boundary

Confirmed for the R570 clear PMU: object identity, point layouts, both search directions,
upper-midpoint arithmetic, adjacent-point evaluation, endpoint clamps and cross-bank index
translation.

Not yet confirmed for current R610: exact endpoint return codes, current point-object
`+0x0c` values for mode-1 queries, whether the base relation search changed, and the
group-`0x11` VFE tuple selection/filtering state machine. R570 has no group `0x11`, so
this search code cannot close that separate current-PMU algorithm.
