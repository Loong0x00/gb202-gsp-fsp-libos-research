# GB202 FSP task2/subobject1 zero-payload runtime result — 2026-07-22

## Scope and safety boundary

This note records the bounded VM-side runtime probe for the MODS-derived
FSP task `2`, subobject `1` transaction.

Safety boundary used for this run:

- GPU was passed through to the isolated MODS VM.
- No VBIOS, firmware, SPI flash, or persistent storage was written.
- The initial task2-zero, PRC readback, latch-only, and e0/f4/f8-only probes
  did not write raw L2 masks. One later bounded FBP0 raw-shadow
  clear-then-restore probe was run and is recorded separately below; its
  attempted raw write did not stick.
- The only post-task2 BAR0 write in this note was a single latch-request
  `0x820040 = 1` probe, with L2 raw/effective/software masks unchanged before
  and after.

## Why this transaction was tested

Static MODS analysis found a host-side sender:

- MODS inner executable: `mods_audit/static/extracted_inner/mods`
- callsite: VA `0x106c587`
- arguments at the call:
  - `rdi = FSP object`
  - `esi = 2`
  - `edx = 1`
  - `rcx = std::string payload`
  - `r8 = 0`
- common sender: `0x185e890`
- lower send path: `0x185e260`

The payload builder at `0x106bfd0` builds six bytes from NVLINK/NVLC_LINK
state. On this RTX 5090 / GB202 setup, there is no evidence of exposed NVLink
or NVLC_LINK state, so the strongest bounded default payload was six zero
bytes.

The direct wire body tested was therefore:

```text
02 01 00 00 00 00 00 00
```

Meaning:

- task `0x02`
- subobject `0x01`
- six-byte zero payload

## MODS tracer attempt

Tool:

```text
vm_mods_lab/mods_task2_payload_tracer.c
vm_mods_lab/mods_task2_payload_tracer.static
vm_mods_lab/task2-trace-tools.iso
```

The tracer planted a breakpoint at `0x106c587`, but the local MODS run
segfaulted before reaching the task2 call. The visible path reached FSP init,
meminfo, GSP-disabled setup, and then GSP-image loading before crashing.

Conclusion from this attempt:

- Live MODS capture did not produce the payload.
- This local MODS build remains blocked on its GSP/RM firmware/runtime path.
- The runtime task2 test below therefore used the already-established common
  sender ABI and the statically-derived all-zero payload.

## Direct FSP task2-zero run

Tool:

```text
vm_mods_lab/prc-read-tools/gb202_fsp_prc_read.c
vm_mods_lab/prc-read-tools/gb202_fsp_prc_read.static
vm_mods_lab/gb202-prc-read-tools.iso
```

Command in guest:

```text
sudo timeout 25s /mnt/prc/gb202_fs.static \
  --task2-zero \
  --i-accept-task2-zero \
  --port 1 \
  --timeout-ms 10000
```

Request sent:

```text
raw_bytes: 010000c0 7ede1013 02010000 00000000
raw_dwords: 0xc0000001 0x1310de7e 0x00000102 0x00000000
```

Response:

```text
response_size=20
raw_bytes: 000000c0 7ede1015 01000000 13000000 00000000
decode: task_id=0x00000001 command_nvdm_type=0x00000013 error_code=0x00000000
TASK2_ZERO_OK
```

Result:

- The retail GB202 FSP accepted task `2` / subobject `1` / zero payload.
- The FSP returned generic success status.

## BAR0 state before/after task2-zero

Earlier baseline before task2-zero:

| Register | Meaning | Value |
|---|---:|---:|
| `0x820040` | latch request | `0x00000000` |
| `0x8200d0` | floorsweep PLM | `0xfffffb8f` |
| `0x8200dc` | L2 raw/software PLM | `0xfffffb8f` |
| `0x8200f8` | latch PLM | `0xfffffb8f` |
| raw FBP0..7 | raw L2 mask | `0x00000012` |
| effective FBP0..7 | effective L2 mask | `0x00000012` |
| software FBP0..7 | software mask | `0x00000000` |

Immediate post-task2 snapshot:

| Register | Meaning | Value |
|---|---:|---:|
| `0x820040` | latch request | `0x00000000` |
| `0x8200d0` | floorsweep PLM | `0xfffffbff` |
| `0x8200dc` | L2 raw/software PLM | `0xfffffbff` |
| `0x8200f8` | latch PLM | `0xfffffb8f` |
| raw FBP0..7 | raw L2 mask | `0x00000012` |
| effective FBP0..7 | effective L2 mask | `0x00000012` |
| software FBP0..7 | software mask | `0x00000000` |

Later read-only snapshot still showed:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffbff
0x008200dc plm_l2_raw_sw        = 0xfffffbff
0x008200f8 plm_latch            = 0xfffffb8f
0x00820434 reset_coupling       = 0x00000001
0x008212ac disable_sw_override  = 0x00000001
raw_fbp0..7       = 0x00000012
effective_fbp0..7 = 0x00000012
software_fbp0..7  = 0x00000000
```

Interpretation:

- task2-zero changed `0x8200d0` and `0x8200dc` from `...b8f` to `...bff`.
- task2-zero did not change `0x8200f8`.
- L2 raw/effective/software masks did not change.
- The changed `d0/dc` state persisted for at least the follow-up snapshots.

## Post-task2 latch-only probe

Command in guest:

```text
sudo /mnt/prc/gb202_bar0_latch_probe --commit-latch-bit0
```

Before:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffbff
0x008200dc plm_l2_raw_sw        = 0xfffffbff
0x008200f8 plm_latch            = 0xfffffb8f
raw/effective FBP0..7           = 0x00000012
software FBP0..7                = 0x00000000
```

Write issued:

```text
BAR0[0x00820040] = 0x00000001
```

After:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffbff
0x008200dc plm_l2_raw_sw        = 0xfffffbff
0x008200f8 plm_latch            = 0xfffffb8f
raw/effective FBP0..7           = 0x00000012
software FBP0..7                = 0x00000000
```

Interpretation:

- Opening `0x8200d0` and `0x8200dc` is not enough for latch.
- `0x8200f8` remains the current visible hard blocker.
- The latch request still does not stick.

## Post-task2 PRC adjacent-knob readback

After task2-zero, the adjacent PRC object-read set `0x1b..0x24` was queried
through the same direct FSP mailbox reader.

Command shape:

```text
sudo timeout 12s /mnt/prc/gb202_fs.static \
  --prc-read 0xKNOB \
  --port 1 \
  --timeout-ms 5000
```

Readback:

| PRC knob | Current decoded name from local MODS map | Value |
|---:|---|---:|
| `0x1b` | RRL_ALLOW_INB | `0x0001` |
| `0x1c` | RPR_ALLOW_INB | `0x0001` |
| `0x1d` | FLOORSWEEPING_ALLOW_INB_ONE_SHOT | `0x0001` |
| `0x1e` | HBM_FREQ_CHANGE_ALLOW_INB | `0x0001` |
| `0x1f` | ROW_REMAP_ALLOW_INB | `0x0001` |
| `0x20` | ROW_REMAP | `0x0001` |
| `0x21` | HULK_ALLOW_INB | `0x0001` |
| `0x22` | HULK | `0x0001` |
| `0x23` | FORCE_RESET_COUPLING_ALLOW_INB | `0x0001` |
| `0x24` | FORCE_RESET_COUPLING | `0x0001` |

Interpretation:

- The adjacent HULK and reset-coupling PRC knobs are readable and currently
  report `1`.
- Because every adjacent object in this range also reports `1`, this readback
  does not identify a unique f8/latch grant.
- It also does not contradict the BAR0 evidence: `0x8200f8` remained
  `0xfffffb8f`, and latch writes still did not stick.

## Post-task2 capability readback for HULK and PRC

The FSP CAPS query was used only to check family presence/version. It did not
send a HULK certificate or any HULK action.

Commands:

```text
sudo timeout 12s /mnt/prc/gb202_fs.static --caps-query 0x11 --port 1 --timeout-ms 5000
sudo timeout 12s /mnt/prc/gb202_fs.static --caps-query 0x13 --port 1 --timeout-ms 5000
```

Results:

```text
CAPS 0x11: raw=0x00010011 nvdm_type=0x0011 version=0x0001
CAPS 0x13: raw=0x00010013 nvdm_type=0x0013 version=0x0001
```

Interpretation:

- The current FSP reports HULK NVDM type `0x11` as present, version `1`.
- The current FSP reports PRC NVDM type `0x13` as present, version `1`.
- This proves the protocol families exist; it does not prove any GB202/f8
  HULK certificate is available or authorized.

## Direct f8-only write/readback probe

A separate security-PLM-only probe family was added to:

```text
vm_mods_lab/gb202_bar0_latch_probe.c
```

First f8-only binary SHA256:

```text
50945f7ea2531292b13c31ae4fed090064103ac55c9bb10f6a10b381c32635ae  gb202_bar0_latch_probe
```

Later e0/f4-capable binary SHA256:

```text
135633e7bf97d45c33d2c96c2a05f1117304d4cd966388de9ea78e0d72c1c478  gb202_bar0_latch_probe
```

Later refreshed ISO SHA256:

```text
e93fb4264729df473b5a8228f11eda6417c469c006bb78ce95559c93110eb0a0  gb202-prc-read-tools.iso
```

Safety boundary:

- requires `d0 == 0xfffffbff`, `dc == 0xfffffbff`,
  `e0 == 0x00800b8f`, `f4 == 0x00800b8f`, and
  `f8 == 0xfffffb8f`;
- requires latch request `0`, raw/effective FBP0..7 `0x12`, software FBP0..7
  `0`;
- does not write latch;
- does not write any raw L2 mask;
- attempts only one selected PLM-like word, reads back, then writes the original
  value.

f8 command:

```text
sudo timeout 20s /mnt/prc/gb202_bar0_latch_probe \
  --commit-f8-open-then-restore
```

Key transcript:

```text
before 0x008200d0 plm_floorsweep_0 = 0xfffffbff
before 0x008200dc plm_l2_raw_sw    = 0xfffffbff
before 0x008200f8 plm_latch        = 0xfffffb8f

phase open: BAR0[0x008200f8] = 0xfffffbff
phase open readback: BAR0[0x008200f8] = 0xfffffb8f

phase restore: BAR0[0x008200f8] = 0xfffffb8f
phase restore readback: BAR0[0x008200f8] = 0xfffffb8f
```

e0 command and result:

```text
sudo timeout 20s /mnt/prc/gb202_bar0_latch_probe \
  --commit-e0-open-then-restore

phase open e0: BAR0[0x008200e0] = 0x00800bff
phase open readback e0: BAR0[0x008200e0] = 0x00800b8f
phase restore e0: BAR0[0x008200e0] = 0x00800b8f
phase restore readback e0: BAR0[0x008200e0] = 0x00800b8f
```

f4 command and result:

```text
sudo timeout 20s /mnt/prc/gb202_bar0_latch_probe \
  --commit-f4-open-then-restore

phase open f4: BAR0[0x008200f4] = 0x00800bff
phase open readback f4: BAR0[0x008200f4] = 0x00800b8f
phase restore f4: BAR0[0x008200f4] = 0x00800b8f
phase restore readback f4: BAR0[0x008200f4] = 0x00800b8f
```

Post-probe status:

```text
FSP port 1 status-only: err=0, receive ready/credit set
0x008200d0 = 0xfffffbff
0x008200dc = 0xfffffbff
0x008200e0 = 0x00800b8f
0x008200f4 = 0x00800b8f
0x008200f8 = 0xfffffb8f
raw/effective FBP0..7 = 0x00000012
software FBP0..7 = 0x00000000
```

Guest `dmesg` after the probe showed no new NVIDIA Xid, PCIe AER, fatal GPU
error, or guest kernel fault in the tail that was checked.

Interpretation:

- Even after task2-zero opened `d0/dc`, a normal host BAR0 write cannot make
  `0x8200f8` stick.
- The same is true for sibling security PLM-like words `0x8200e0` and
  `0x8200f4`.
- Therefore `f8` is protected by a mechanism not represented by the MODS
  RegHal self-access metadata and not bypassed by task2-zero.
- This closes the simplest direct e0/f4/f8 self-write route.

## Post-task2 raw L2 one-bit clear-then-restore probe

After proving `0x8200dc` was open but `0x8200f8`/latch were still closed, the
existing bounded raw-shadow probe was run once. This probe is intentionally
non-persistent and restores the original raw value immediately if a write ever
sticks.

Safety boundary:

- isolated VFIO VM;
- precondition requires latch request `0`, raw/effective FBP0..7 `0x12`, and
  software FBP0..7 `0`;
- touches only `0x820040` latch request and FBP0 raw-shadow `0x8234e0`;
- no VBIOS/firmware/flash/PCI config/reset operation;
- final snapshot and FSP status were checked.

Command:

```text
sudo timeout 25s /mnt/prc/gb202_bar0_latch_probe \
  --commit-fbp0-bit1-clear-then-restore
```

Before:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffbff
0x008200dc plm_l2_raw_sw        = 0xfffffbff
0x008200f8 plm_latch            = 0xfffffb8f
fbp0 raw/effective/software     = 0x12 / 0x12 / 0
```

Clear phase:

```text
BAR0[0x00820040] = 0x00000001
BAR0[0x008234e0] = 0x00000010

after_clear 0x00820040 latch_request = 0x00000000
after_clear fbp0 raw                 = 0x00000012
after_clear fbp0 effective           = 0x00000012
after_clear fbp0 software            = 0x00000000
```

Restore phase:

```text
BAR0[0x00820040] = 0x00000001
BAR0[0x008234e0] = 0x00000012

after_restore 0x00820040 latch_request = 0x00000000
after_restore fbp0 raw                 = 0x00000012
after_restore fbp0 effective           = 0x00000012
after_restore fbp0 software            = 0x00000000
```

Post-probe status:

```text
FSP port 1 status-only: err=0
0x008200d0 = 0xfffffbff
0x008200dc = 0xfffffbff
0x008200e0 = 0x00800b8f
0x008200f4 = 0x00800b8f
0x008200f8 = 0xfffffb8f
raw/effective FBP0..7 = 0x00000012
software FBP0..7 = 0x00000000
```

Guest `dmesg` tail after this probe again showed no new NVIDIA Xid, PCIe AER,
fatal GPU error, or guest kernel fault.

Interpretation:

- Opening `0x8200dc` is not sufficient for ordinary host BAR0 raw-shadow writes.
- The raw write is discarded/blocked before visible readback, not merely failing
  at later effective-mask adoption.
- The latch/f8 path or a firmware-mediated commit path remains necessary.

## Current conclusion

This is a real positive result, but it is not an L2 unlock yet.

What is now proven:

- Direct task2/subobject1/zero-payload reaches retail GB202 FSP.
- FSP accepts it with generic success.
- It changes the visible floorsweep/L2 raw-software PLM words `0x8200d0`
  and `0x8200dc` from `0xfffffb8f` to `0xfffffbff`.
- Direct f8 BAR0 write/readback after that still fails: attempted
  `0xfffffbff` reads back as `0xfffffb8f`.
- Direct e0/f4 BAR0 write/readback also fails: attempted `0x00800bff`
  reads back as `0x00800b8f`.
- Direct FBP0 raw-shadow one-bit clear after task2 also fails: attempted
  `0x8234e0 = 0x10` reads back as `0x12`.

What is still not solved:

- It does not open `0x8200f8`.
- It does not make `0x820040` latch writes stick.
- It does not change raw or effective L2 masks.

Next research target:

- Stop spending time on whether task2 can open `d0/dc`; that is now measured.
- Focus on the separate latch PLM path at `0x8200f8`, or on any FSP/HULK/task4
  transaction that legitimately opens or consumes the latch.
- Do not attempt raw L2 mask mutation until the latch path is understood or a
  safer supported commit path is found.
