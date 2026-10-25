# GB202 FSP/MNOC PRC write-noop result — 2026-07-22

## Result

A deliberately constrained direct PRC write-noop request reached FSP, but FSP
rejected it with:

```text
error_code=0x000001e4
PRC_ERROR_PERSISTENCE_NOT_SUPPORTED
```

The GPU remained responsive after the attempt. A direct PRC read of knob `0x1d`
still succeeds, BAR0 floorsweep/L2 state is unchanged, and the host still has
the card bound to `vfio-pci`.

## Safety boundary used

The test tool only allowed one PRC write form:

```text
knob  = 0x001d
value = 0x0001
```

and only with the explicit CLI guard:

```text
--i-accept-prc-write
```

The tool performs a pre-read and refuses to send the write unless the current
readback already equals the requested value. In this run:

```text
PRC_READ_OK knob=0x001d value=0x0001
```

So the attempted request was an equal-current write, not an attempt to change
the visible PRC value.

No VBIOS, InfoROM, OTP/fuse, PLM, L2, or floorsweep MMIO writes were performed.

## Tool artifacts

Source/binary/ISO:

```text
/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.c
/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.static
/home/user/rt_5090_project/vm_mods_lab/gb202-prc-read-tools.iso
```

Hashes at the time of the write-noop run:

```text
c0cd19926889486f85ad285dee17fa0d020059fc8d38ed02e518c5c0a441fadc  gb202_fsp_prc_read.static
7743c3172b77fa2641d484660afe061513b5ea3c68edefc603c5f8844a21dc7e  gb202-prc-read-tools.iso
```

Later caps-query support was added to the same source file and rebuilt; see
`fsp_caps_query_result_20260722.md` for the newer binary hash.

## VM command

```text
sudo -n /mnt/prc/gb202_fsp_prc_read.static --prc-write-noop 0x1d 0x1 --i-accept-prc-write --timeout-ms 10000
```

## Transcript

Pre-read:

```text
BDF=0000:00:01.0 resource0=/sys/bus/pci/devices/0000:00:01.0/resource0 mode=prc-write-noop
mnoc_port=1
send_info 0x008f1f10 = 0x80000000 size=0 ready=0 err=0 intr_en=0 intr=1
recv_info 0x008f1f90 = 0x8500000c size=12 ready=1 credit=1 err=0 intr_en=0 intr=1
pre-read before write-noop
request: PRC read knob=0x001d port=1 timeout_ms=10000 mctp_version=1
raw_bytes: 010000c0 7ede1013 0c021d00
raw_dwords: 0xc0000001 0x1310de7e 0x001d020c
response_size=22
raw_bytes: 000000c0 7ede1015 01000000 13000000 00000000 0100
raw_dwords: 0xc0000000 0x1510de7e 0x00000001 0x00000013 0x00000000 0x00000001
decode: task_id=0x00000001 command_nvdm_type=0x00000013 error_code=0x00000000
decode: prc_value_candidate_u16_at_20=0x0001
PRC_READ_OK knob=0x001d value=0x0001
```

Write-noop request:

```text
request: PRC write-noop knob=0x001d value=0x0001 port=1 timeout_ms=10000 mctp_version=1
raw_bytes: 010000c0 7ede1013 0d021d00 01000000
raw_dwords: 0xc0000001 0x1310de7e 0x001d020d 0x00000001
response_size=20
raw_bytes: 000000c0 7ede1015 01000000 13000000 e4010000
raw_dwords: 0xc0000000 0x1510de7e 0x00000001 0x00000013 0x000001e4
decode: task_id=0x00000001 command_nvdm_type=0x00000013 error_code=0x000001e4
PRC write-noop FSP returned nonzero error_code=0x000001e4
mnoc_port=1
send_info 0x008f1f10 = 0x80000000 size=0 ready=0 err=0 intr_en=0 intr=1
recv_info 0x008f1f90 = 0x85000010 size=16 ready=1 credit=1 err=0 intr_en=0 intr=1
```

Post-read:

```text
request: PRC read knob=0x001d port=1 timeout_ms=10000 mctp_version=1
raw_bytes: 010000c0 7ede1013 0c021d00
raw_dwords: 0xc0000001 0x1310de7e 0x001d020c
response_size=22
raw_bytes: 000000c0 7ede1015 01000000 13000000 00000000 0100
raw_dwords: 0xc0000000 0x1510de7e 0x00000001 0x00000013 0x00000000 0x00000001
decode: task_id=0x00000001 command_nvdm_type=0x00000013 error_code=0x00000000
decode: prc_value_candidate_u16_at_20=0x0001
PRC_READ_OK knob=0x001d value=0x0001
```

## Static cross-check

The MODS write executor encodes the task-13 request body as:

```text
id16 + value16 + zero16
```

At the send call site:

```text
0x185f284  r8d = 0
0x185f28c  edx = 2
0x185f294  esi = 0x0d
0x185f299  call 0x185e890
```

The common preparation function stores:

```text
[object+0x78] = task id
[object+0x79] = second argument / subtype
[object+0x7c] = flags/options argument
```

This supports the current direct packet shape using task `0x0d`, subtype `0x02`,
and a 6-byte body. It does not support blindly replacing the second byte with
`0x06` as a length field. The body length is computed from the C++ string.

## Error mapping

Recovered MODS/FSP error-name table maps:

```text
0x1e0  PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS
0x1e3  PRC_ERROR_INVALID_KNOB_ID
0x1e4  PRC_ERROR_PERSISTENCE_NOT_SUPPORTED
0x1e5  PRC_ERROR_PERSISTENCE_NOT_ALLOWED
0x1e6  PRC_ERROR_PERM_KNOB_ID_INVALID
0x1e8  PRC_ERROR_FEATURE_NOT_ALLOWED
0x1ea  PRC_ERROR_PERMISSION_KNOB_ID_INVALID
0x223  INVALID_PRC_KNOB_VALUE
```

The observed `0x1e4` is therefore not a transport failure and not an invalid
knob/value failure. It is a PRC policy/options/persistence-class rejection.

## Post-test state

BAR0 snapshot after the failed write-noop:

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffb8f
0x008200dc plm_l2_raw_sw        = 0xfffffb8f
0x008200f8 plm_latch            = 0xfffffb8f
0x008212ac disable_sw_override  = 0x00000001

raw_fbp0..7       = 0x00000012
effective_fbp0..7 = 0x00000012
software_fbp0..7  = 0x00000000
```

Host status after the failed write-noop:

```text
01:00.0 NVIDIA GB202 [GeForce RTX 5090] [10de:2b85]
Kernel driver in use: vfio-pci
```

No relevant host kernel log lines were found in the recent window for
`NVRM`, `Xid`, `vfio`, `AER`, `PCIe`, `GSP`, `FSP`, `fatal`, or `error`.

## Current conclusion

The direct PRC write path is real enough to reach FSP, but the retail/current
state rejects this equal-current task-13 request with a persistence-related PRC
error.

This narrows the problem:

1. mailbox transport is working;
2. read-object is working;
3. write-object reaches FSP;
4. current task/subtype/body shape is probably close to MODS;
5. the remaining barrier is policy/permission/options/lifecycle, not raw BAR0
   address discovery.

The next lower-risk research step is static: identify what MODS/RM does before
calling the task-13 writer that could change the PRC persistence/permission
state. The next runtime step should remain read-only unless we can name the
unknown policy transition more tightly.
