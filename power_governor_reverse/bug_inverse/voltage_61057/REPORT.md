# R610.57.04 voltage and clock observation audit

Date: 2026-08-14 (Asia/Singapore)

Scope: static inspection plus read-only runtime queries on the installed RTX
5090 driver.  No SET method, offset, clock lock, benchmark, module load, MMIO
write, or configuration write was performed.

## Outcome

Two formerly open items are now closed enough for data collection:

1. R610.57.04 has unique GSP method-table entries for the **clock-domain**
   methods `CLK_DOMAINS_GET_CONTROL` (`0x2080901b`) and
   `CLK_DOMAINS_SET_CONTROL` (`0x2080d01c`).  Both use a `0x83c` parameter
   block.  These are not `VOLT_RAILS_GET/SET_CONTROL` methods.  Their current
   handlers and flags are listed below; the SET method was located statically
   and was not invoked.
2. The R610.57.04 voltage-rail GET_STATUS wrapper is byte-identical to the
   audited R610.43.03 wrapper.  A full-library and full-function hash-pinned
   reader now returns both aggregate rail target records on the current
   driver.

The rail-status wrapper does **not** return a physical sensed voltage on this
machine: both public `sensed` fields are zero.  The separate power-policy
status path does return nonzero observed/sensed rail voltages.  Target and
sensed therefore need to remain separate columns in the joint sampler.

## Confirmed

### Pinned inputs

| Input | SHA-256 / build ID |
|---|---|
| `/usr/lib/libnvidia-api.so.1` | `fea6a0090bbdca9b294682b34a8808e1a4e3f6613f9b6684b412893d5047cef8`; build ID `076662e9feb0b8f1509e9e63f58cf8bc3d42515d` |
| `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin` | `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`; build ID `4f09703c5c7d57baa527d6a189bb6d118bc60e49` |
| archived `nvidia-utils-610.43.03-4` package | `/var/cache/pacman/pkg/nvidia-utils-610.43.03-4-x86_64.pkg.tar.zst`; package SHA-256 `e9f2bc56c0efe5094a205d24624a1e56b4f600e4639ef8be953d9c17f7e48a51` |
| archived 610.43.03 `libnvidia-api.so.1` extracted for comparison | `14a4861b513d9575a679bc470209e532bfceba688631c6be6eda40ff559b7817`; build ID `b9809390d7b3daaf4c90ed68508d89a0a932d74d` |
| archived 610.43.03 `gsp_ga10x.bin` extracted for comparison | `572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a`; build ID `3609758e15d41b2720db2ffb49df623c4ac21c62` |

The temporary extracted copies were removed after comparison.  The original
package cache and installed driver files were not modified.

### Current GSP method table

The command encodings occur exactly once each in the pinned GSP image.  Each
row below is decoded as `<u32 command, u32 size, u64 class descriptor, u64
handler, u64 flags>` from the unique occurrence.

| Command | File offset | Size | Class descriptor | Handler | Flags |
|---:|---:|---:|---:|---:|---:|
| `0x2080901b` CLK domains GET_CONTROL | `0x00dbd5c0` | `0x083c` | `0x01c23870` | `0x010ddcf0` | `0x48` |
| `0x2080d01c` CLK domains SET_CONTROL | `0x00dbfa20` | `0x083c` | `0x01c23870` | `0x010f46d8` | `0x44` |
| `0x2080b202` voltage rails GET_STATUS | `0x00dbf5e0` | `0x0ca0` | `0x01c23870` | `0x017e3458` | `0x48` |

The 610.43.03 clock entries were at `0x00dba5c0` and `0x00dbca20`,
with handlers `0x010dd334` and `0x010f3d1c`.  Size and flags stayed the same,
but the table, descriptor and handlers moved.  This is direct evidence not to
reuse old handler addresses as R610.57 facts.

### Current user-library wrappers

`nvapi_QueryInterface` remains at VA `0x8aa0`.  Full function bodies, not only
prologues, were compared against the archived R610.43.03 library:

| Wrapper | VA / size | Function SHA-256 | Embedded method | Result |
|---|---|---|---:|---|
| voltage rails GET_STATUS | `0x192e0 / 0x460` | `c8aa0cb8cb6ec1e854ade714564b3d928d9f450314066ccec229289398798479` | `0x2080b202` | byte-identical |
| clock domains GET_CONTROL | `0x32530 / 0x390` | `1374b8c2b4d6ba498ca9dbc4f3232391f8e965e1815d2f50d22bc7bb2098c797` | `0x2080901b` at VA `0x325c7` | byte-identical |
| clock domains SET_CONTROL | `0x328c0 / 0x340` | `9df5fdf9a5f6fcaf57ec3c126cdd21adab10a044d07fd44d6406955837f79261` | `0x2080d01c` at VA `0x32b24` | byte-identical |

The new reader validates both the full current library hash and the complete
`0x460` voltage wrapper before loading the library.

### Voltage runtime result

The tool requested rail mask `0x3`, public status version `0x00021620`, and
received mask `0x3`.  A 20 Hz, ten-sample idle read on the pinned build
returned:

```text
rail0 current/default: 825000 uV (last sample 820000 uV)
rail0 current target : 825000 uV (last sample 820000 uV)
rail0 sensed field   : 0 uV
rail1 current/default: 880000 uV
rail1 current target : 880000 uV
rail1 sensed field   : 0 uV
GET_STATUS duration  : 0.916--1.092 ms in this run
```

In the same idle window, the separate power-policy model query returned:

```text
policy_obs_sensed_volt0_uv=835000
policy_obs_sensed_volt1_uv=890000
```

Thus the wrapper provides aggregate rail target/request information but not a
working physical-sense field here.  The power-policy observation is the
currently available sensed source.

### Method-family boundary

The interfaces in this report must not be collapsed into a single "voltage
control" method:

| Function | Method family | Current status |
|---|---|---|
| aggregate rail target/status | `0x2080b202 VOLT_RAILS_GET_STATUS` | confirmed read-only |
| clock-domain frequency offsets | `0x2080901b/0x2080d01c CLK_DOMAINS GET/SET_CONTROL` | GET confirmed here; SET only located here |
| rail x clock-domain voltage offsets | fields inside the same `CLK_DOMAINS` control records | confirmed on current 610.57 by prior XBAR/MSVDD write/readback; read as zero here |
| global rail tuning offsets | old MODS updates them and commits the ClockDomains control block with `0x2080d01c` | same method family confirmed for the old `0x7bc` ABI; exact current 610.57 field/write semantics remain unverified |

There is therefore no separately confirmed "true rail-offset SET method" in
the current evidence.  The known MODS path treats global rail and rail x
clock-domain tuning as fields marshalled through ClockDomains control.  For
R610.57, only the per-domain field path is runtime-confirmed; projecting the
old global-rail field into the new ABI would be an inference, not a result.

### Read-only clock-control layout

The current raw GET_CONTROL succeeds with a `0x83c` buffer.  Its size is
exactly:

```text
0x3c-byte header + 32 * 0x40-byte domain records = 0x83c
```

The read returned both masks as `0xff`, header word `+0x08 = 0x01010000`, and
active record words at `0x3c + index*0x40`.  The known fields used by the
existing R610.57 XBAR reader are:

```text
domain base               = 0x3c + index * 0x40
record +0x08              = frequency-offset mode
record +0x0c              = signed frequency offset, kHz
record +0x10 + rail*4     = signed per-domain rail offset, uV
XBAR domain index         = 1 (base 0x7c)
XBAR rail-1 offset        = absolute offset 0x90
```

The no-argument read reported `xbar_offset_khz=0`,
`xbar_msvdd_offset_uv=0`, and independently measured XBAR at `1441057 kHz`.
No SET path was entered.

## Inferred

- Because the three relevant user-library wrappers are byte-identical, the
  R610.43.03 public-record field mapping is valid on this exact R610.57.04
  library build.  The full hashes make this statement build-specific.
- The voltage `current_target` field is an aggregate output of rail
  arbitration, not an independent physical sensor.  The nonzero policy
  observation and zero status `sensed` field support keeping both channels.
- Unchanged command sizes and wrappers do not imply an unchanged governor:
  GSP handlers and the GSP image changed.

## Unknown / still open

- `0x2080b202` returns aggregate rail records.  It does not expose the ten
  individual request slots or the winning client ID in the public record.
- The exact semantic names of every `0x83c` header/record field and the exact
  meanings of method flags `0x48`/`0x44` remain private.  Known offsets above
  are closed; unused/unknown bytes are not.
- The GSP GET_STATUS handler dispatches through the voltage object/vtable.
  Its exact path back to the ten-client request array has not yet been closed.
- The new target reader has not been exercised under a synthetic load in this
  task because benchmarks were explicitly out of scope.

## Next minimum discriminating work

1. Import `nv_voltage_rails_61057.py` into the joint sampler and preserve its
   `monotonic_raw_before_ns` / `monotonic_raw_after_ns` around the call.  The
   reader now explicitly uses `CLOCK_MONOTONIC_RAW`, matching the collector;
   do not launch a fresh Python process per sample.
2. Read policy0 observed/sensed voltage immediately before or after the target
   call.  Preserve both timestamps and the ordering so sub-PMU-tick skew can
   be bounded rather than assumed away.
3. For the ten-client winner, statically follow handler `0x017e3458` through
   the voltage object vtable and search the resulting object/status copier for
   the known ten-slot stride.  If no GET copies those slots, switch to
   black-box upper-envelope identification; do not reinterpret aggregate
   target as a client ID.
4. A later write gate still needs complete preimage/readback/rollback checks.
   Nothing in this report authorizes a SET experiment.

## Reproduction

```bash
python bug_inverse/voltage_61057/audit_61057.py
python bug_inverse/voltage_61057/nv_voltage_rails_61057.py
python bug_inverse/voltage_61057/nv_voltage_rails_61057.py \
  --watch 20 --count 10 --terse

# Existing read-only cross-checks used in this report:
./power_cap_limit_probe --policy0-model-summary
./xbar_clock_demo
./power_cap_limit_probe --clk-domains-control-full-raw
```
