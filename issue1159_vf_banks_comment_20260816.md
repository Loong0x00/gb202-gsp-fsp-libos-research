## Runtime update: complete global VF-point inventory and guarded write results

This corrects the negative result in section 4 above. RM status `0x1b` is
`NV_ERR_INSUFFICIENT_PERMISSIONS` on the current driver. The byte-identical
SET had been submitted from an unprivileged RM client. Repeating exactly the
same operation as root succeeds.

This does **not** mean that every accepted control value is used by the clock
evaluator. The tests below deliberately distinguish:

1. SET returned `NV_OK`;
2. GET_CONTROL returned the submitted bytes;
3. GET_STATUS actually changed the effective curve;
4. the original complete control records were restored and read back.

Only (3) establishes that the submitted per-point frequency offset was adopted
by the runtime VF-point evaluator. It is still not a workload stability result.

### Complete active point inventory

On this RTX 5090 / 610.57.04 configuration, global `CLK_VF_POINTS_GET_INFO`
advertises flat indices 0 through 647. They form seven contiguous banks:

| Flat indices | Count | Point type | Domain | `+15 MHz` point test |
|---:|---:|---:|---|---|
| 0..126 | 127 | `0x11`, voltage-indexed | GPC | CONTROL and STATUS changed; restored |
| 127..253 | 127 | `0x11`, voltage-indexed | XBAR | CONTROL and STATUS changed; restored |
| 254..258 | 5 | `0x0f`, frequency-indexed | MCLK | tested frequency-offset field was cleared; STATUS unchanged |
| 259..385 | 127 | `0x11`, voltage-indexed | SYS | CONTROL and STATUS changed; restored |
| 386..512 | 127 | `0x11`, voltage-indexed | NVD | CONTROL and STATUS changed; restored |
| 513..639 | 127 | `0x11`, voltage-indexed | PWR | CONTROL retained the value; STATUS unchanged at points 0 and 63 |
| 640..647 | 8 | `0x0f`, frequency-indexed | PCIE | tested frequency-offset field was cleared; STATUS unchanged |

The second BoardObj group has no active entries in this capture.

Every one of the seven banks first passed a root byte-identical SET followed by
an exact GET_CONTROL comparison. A real `+15000 kHz` write was then made to one
low point at a time and immediately restored. For GPC, XBAR, SYS and NVD, the
selected STATUS point increased by exactly 15 MHz and its total-frequency-offset
field increased by exactly 15000 kHz. The final CONTROL and STATUS values matched
the original state, and no new Xid was logged.

PWR is an important counterexample: the submitted `+15000 kHz` value was
returned by GET_CONTROL, but GET_STATUS did not change at either the lowest
point or a middle point. Therefore successful SET plus exact control readback
must not be presented as proof that a curve is effective.

The MCLK and PCIE entries are type `0x0f` frequency-indexed points, not the
type `0x11` voltage-indexed F(V) points. Writing the tested type-`0x11`
frequency-offset field did not survive GET_CONTROL. This result does not rule
out a different type-specific voltage control; it only shows that these records
must not be exposed as per-point frequency controls using the `0x11` layout.

### Read path

The global object uses these branch-specific RM controls:

| Operation | Command | Size |
|---|---:|---:|
| INFO | `0x20809021` | `0x8208` |
| STATUS | `0x20809022` | `0x98208` |
| GET_CONTROL | `0x20809023` | `0x1020c` |
| SET_CONTROL | `0x2080d024` | `0x1020c` |

For a read-only implementation:

1. Call INFO and use its returned active mask; do not hard-code `0..647` on a
   different GPU, VBIOS or driver branch.
2. Allocate a zeroed STATUS buffer.
3. For each desired primary flat index `i`, set bit `i` at
   `params + 0x4 + 4 * (i / 32)`.
4. Call STATUS and decode only records whose bits were advertised by INFO.

For the currently validated primary voltage-point layout:

```c
size_t record = 0x0d8 + (size_t)flat_index * 0x98;

type_or_valid       = u32(record + 0x2c); /* low 16 bits 0x1111 */
effective_voltage_uV= u32(record + 0x30);
effective_freq_MHz  = u32(record + 0x34);
base_freq_16_16_MHz = u32(record + 0x38);
source_voltage_uV   = u32(record + 0x44);
effective_freq_dup  = u32(record + 0x58);
effective_volt_dup  = u32(record + 0x5c);
total_freq_offset_kHz = i32(record + 0x80);
total_volt_offset_uV  = i32(record + 0x88);
```

The matching primary CONTROL record is:

```c
size_t control_record = 0x108 + (size_t)flat_index * 0x10;
point_type             = u8(control_record + 0x1);
freq_offset_kHz        = i32(control_record + 0x8); /* validated for type 0x11 */
```

The effective STATUS curves are runtime materializations, not necessarily
literal 127-entry tables stored in the VBIOS. Domain offsets, factory/client
offsets, ClockProgs/VF tuples, rail relationships and clock-grid quantization
all contribute. For example, a `SYS +15 MHz` domain request shifted every one
of the 127 SYS STATUS points by exactly 15 MHz while all other banks remained
unchanged.

### Implementation boundary

A conservative implementation should start with generic read-only discovery
and display. If any point writing is later exposed, it should be explicitly
experimental and must require, at minimum:

- root/privileged RM access;
- INFO-driven type and mask validation;
- a complete GET_CONTROL restoration preimage;
- byte-exact no-op SET and readback before any modified SET;
- modified CONTROL readback **and** STATUS adoption checks;
- immediate full restore plus exact final readback;
- physical-clock, Xid/reset and workload-output/data-integrity monitoring.

Even satisfying all of the above proves only that the control is applied and
reversible on that tested build. It does not prove that an arbitrary curve is
stable, useful or portable to another GPU/driver/VBIOS.
