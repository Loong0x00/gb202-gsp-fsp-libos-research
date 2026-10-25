# GB202 FSP/MNOC PRC direct-read result — 2026-07-22

## Result

Direct, non-MODS FSP/MNOC PRC read works in the isolated VM.

The minimal client sent a single PRC object-read request through the live FSP
MNOC mailbox and read back:

```text
PRC_READ_OK knob=0x001d value=0x0001
```

This reproduces the useful part of the earlier MODS result without running
MODS' full GPU initialization path.

## Safety boundary used

The tool created for this test implements only:

- MNOC mailbox status read;
- PRC object-read request.

It does not implement PRC write, floorsweep register writes, PCI config writes,
VBIOS writes, InfoROM writes, OTP/fuse writes, or reset commands.

The only MMIO writes performed in `--prc-read` mode are the normal FSP mailbox
send sequence:

- write `MESSAGE_INFO_0_RECEIVEMBOX(port)` with message size + trigger;
- write request DWORDs to `WDATA_0_RECEIVEMBOX(port)`.

Source/binary:

- `/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.c`
- `/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.static`
- `/home/user/rt_5090_project/vm_mods_lab/gb202-prc-read-tools.iso`

Static binary SHA256:

```text
0318ee026194c1a238f1383f33e34db4073cb39615f4e22f28d994fb3f33623f  gb202_fsp_prc_read.static
```

ISO SHA256:

```text
1a7dc9657f5e5635c19eb2292e79e55fc1bf6d481cda878c5aaa521daede9c38  gb202-prc-read-tools.iso
```

## Protocol facts used

From OpenRM 610.43.03:

- `NVDM_TYPE_PRC = 0x13`.
- Generic FSP response NVDM type is `0x15`.
- MCTP/NVDM header is two little-endian DWORDs:
  - transport header;
  - vendor-defined PCI header, NVIDIA vendor `0x10de`.
- GH100 public PRC read-object payload precedent:
  - `prcObjType = 0x0c`;
  - `numBytes = 0x02`;
  - `knobId = NvU16`.
- GB100 public MNOC mailbox layout:
  - FSP MNOC base used by the public Blackwell HAL: `0x008f1e00`;
  - sendbox info offset in aperture: `0x104 + port * 0xc`;
  - sendbox data offset in aperture: `0x108 + port * 0xc`;
  - receivebox info offset in aperture: `0x184 + port * 0xc`;
  - receivebox data offset in aperture: `0x188 + port * 0xc`.

## Live mailbox port finding

The public 610 Blackwell HAL names `KERNEL_FSP_MBOX_PORT = 2`, but on this VM
the live readable port set was different:

```text
port 0:
send_info 0x008f1f04 = 0x00000000
recv_info 0x008f1f84 = 0x05000000  ready=1 credit=1

port 1:
send_info 0x008f1f10 = 0x80000000
recv_info 0x008f1f90 = 0x8500000c  ready=1 credit=1 size=12

port 2:
send_info 0x008f1f1c = 0xbadf5720  err=1
recv_info 0x008f1f9c = 0x04000000  ready=0 credit=1

port 3:
send_info 0x008f1f28 = 0xbadf5720  err=1
recv_info 0x008f1fa8 = 0x04000000  ready=0 credit=1
```

Port 1 was selected because:

- it had receive-ready and credit set;
- its receivebox size field was already `12`, exactly matching the known PRC
  read request size from the MODS run.

## Direct PRC read transcript

Command:

```text
sudo -n /mnt/prc/gb202_fsp_prc_read.static --prc-read 0x1d --port 1 --timeout-ms 10000
```

Request:

```text
request: PRC read knob=0x001d port=1 timeout_ms=10000 mctp_version=1
raw_bytes: 010000c0 7ede1013 0c021d00
raw_dwords: 0xc0000001 0x1310de7e 0x001d020c
```

Response:

```text
response_size=22
raw_bytes: 000000c0 7ede1015 01000000 13000000 00000000 0100
raw_dwords: 0xc0000000 0x1510de7e 0x00000001 0x00000013 0x00000000 0x00000001
decode: task_id=0x00000001 command_nvdm_type=0x00000013 error_code=0x00000000
decode: prc_value_candidate_u16_at_20=0x0001
PRC_READ_OK knob=0x001d value=0x0001
```

Interpretation:

- response NVDM type `0x15` = FSP response;
- response command type `0x13` = PRC;
- firmware error code `0`;
- PRC value at response byte offset `20` = `0x0001`.

This matches the earlier MODS log:

```text
PRC Knob Read Result: PrcKnob Value= 0x1 for knob PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT (knobId 29)
```

## Related read-only PRC scan

Same client, same port, same read-only request format:

| Knob | Existing recovered name/context | Result |
|---:|---|---:|
| `0x1b` | `RRL_ALLOW_INB` | `0x0001` |
| `0x1c` | `RPR_ALLOW_INB` | `0x0001` |
| `0x1d` | `FLOORSWEEPING_ALLOW_INB_ONE_SHOT` | `0x0001` |
| `0x1e` | `HBM_FREQ_CHANGE_ALLOW_INB` | `0x0001` |
| `0x1f` | `ROW_REMAP_ALLOW_INB` | `0x0001` |
| `0x20` | `ROW_REMAP` | `0x0001` |
| `0x21` | `HULK_ALLOW_INB` | `0x0001` |
| `0x22` | `HULK` | `0x0001` |
| `0x23` | `FORCE_RESET_COUPLING_ALLOW_INB` | `0x0001` |
| `0x24` | `FORCE_RESET_COUPLING` | `0x0001` |
| `0x2d` | GH100 public protected-PCIe precedent | FSP error `0x000001e3`, no value |

The `0x2d` failure is consistent with the earlier public-source conclusion that
the GH100 protected-PCIe PRC knob should not be assumed to exist on GB202.

## Post-test state checks

Host PCI binding remained:

```text
01:00.0 NVIDIA GB202 [GeForce RTX 5090] [10de:2b85]
Kernel driver in use: vfio-pci
```

Host kernel log check over the recent window found no matching NVIDIA/vfio/Xid/AER
errors.

Guest BAR0 floorsweep snapshot after the read-only tests:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffb8f
0x008200dc plm_l2_raw_sw        = 0xfffffb8f
0x008200f8 plm_latch            = 0xfffffb8f
0x008212ac disable_sw_override  = 0x00000001

raw_fbp0..7       = 0x00000012 for all 8 FBP entries
effective_fbp0..7 = 0x00000012 for all 8 FBP entries
software_fbp0..7  = 0x00000000 for all 8 FBP entries
```

No L2/FS state change was observed.

## Current conclusion

Path 1 is viable for read-only work: we can now talk to FSP/PRC directly without
depending on MODS, at least for simple PRC object reads.

This does not by itself unlock L2. It establishes the direct transport and shows
that the relevant permission/state knobs are readable. The next technical step,
if we choose to continue along this route, is to implement a deliberately gated
PRC write test harness in the same style, with:

1. exact knob/value allowlist;
2. pre-read and post-read compare;
3. no FS register write in the same run at first;
4. immediate post-test BAR0 snapshot;
5. VM-only execution.

The open question remains whether writing a PRC knob such as `0x1d` changes any
later FSP floorsweep acceptance, and whether it is sufficient without MODS'
separate task-2/subobject-1 transaction.
