# GB202 FSP/MNOC caps-query result — 2026-07-22

## Result

Direct FSP caps-query works through the same MNOC mailbox path.

The important record is:

```text
NVDM type 0x0013, version 0x0001
```

`0x13` is `NVDM_TYPE_PRC`. This proves the current FSP publishes the PRC
message family as active/supported in its capability list.

Therefore the earlier PRC write-noop failure:

```text
error_code=0x000001e4
PRC_ERROR_PERSISTENCE_NOT_SUPPORTED
```

is not because the whole PRC message family is absent. It is a rejection inside
the specific PRC object-write path: knob, policy, persistence class, lifecycle,
or options.

## Safety boundary

This test only sends `NVDM_TYPE_CAPS_QUERY` requests:

```text
request body = one byte subMessageId
```

No PRC write, floorsweep register write, L2 register write, VBIOS, InfoROM,
OTP/fuse, or reset operation was performed.

The only MMIO writes are the normal MNOC mailbox send sequence needed to ask
FSP for data.

## Tool artifacts

Source/binary/ISO:

```text
/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.c
/home/user/rt_5090_project/vm_mods_lab/gb202_fsp_prc_read.static
/home/user/rt_5090_project/vm_mods_lab/gb202-prc-read-tools.iso
```

Current hashes:

```text
b36ec2312311cf5b616aab580c6c56564d35c253a09c6611f319ad0a291ce67d  gb202_fsp_prc_read.static
ff67ba9a9fd7e73603d234bcc587e55401b14653b718be86beae20d4814d2c9f  gb202-prc-read-tools.iso
```

Because the ISO was created without long-name extensions in this run, the guest
sees the static binary as:

```text
/mnt/prc/gb202_fs.sta
```

Guest hash confirmation:

```text
b36ec2312311cf5b616aab580c6c56564d35c253a09c6611f319ad0a291ce67d  /mnt/prc/gb202_fs.sta
```

## Single-capability query: PRC family

Command:

```text
sudo -n /mnt/prc/gb202_fs.sta --caps-query 0x13 --port 1 --timeout-ms 10000
```

Request:

```text
request: CAPS query subMessageId=0x13 port=1 timeout_ms=10000 mctp_version=1
raw_bytes: 010000c0 7ede1016 13
raw_dwords: 0xc0000001 0x1610de7e 0x00000013
```

Response:

```text
response_size=24
raw_bytes: 000000c0 7ede1015 01000000 16000000 00000000 13000100
raw_dwords: 0xc0000000 0x1510de7e 0x00000001 0x00000016 0x00000000 0x00010013
decode: standard task_id=0x00000001 command_nvdm_type=0x00000016 error_code=0x00000000
decode: standard record@20 raw=0x00010013 nvdm_type=0x0013 version=0x0001
CAPS_QUERY_OK subMessageId=0x13
```

## All-capability query

Command:

```text
sudo -n /mnt/prc/gb202_fs.sta --caps-query 0xff --port 1 --timeout-ms 10000
```

Response records, decoded as `low16=NvdmType`, `high16=Version`:

```text
0x0000 version 0x0001
0x0011 version 0x0001
0x0013 version 0x0001
0x0014 version 0x0001
0x0015 version 0x0001
0x0017 version 0x0001
0x0018 version 0x0001
0x001a version 0x0001
0x0016 version 0x0001
0x0012 version 0x0002
0x001d version 0x0001
0x0000 version 0x0000
0x0000 version 0x0000
```

Known public names among these:

```text
0x11 = NVDM_TYPE_HULK
0x12 = NVDM_TYPE_FIRMWARE_UPDATE
0x13 = NVDM_TYPE_PRC
0x14 = NVDM_TYPE_COT
0x15 = NVDM_TYPE_FSP_RESPONSE
0x16 = NVDM_TYPE_CAPS_QUERY
0x17 = NVDM_TYPE_INFOROM
0x18 = NVDM_TYPE_SMBPBI
0x1a = NVDM_TYPE_ROMREAD
0x1d = NVDM_TYPE_UEFI_XTL_DEBUG_INTR
```

The two final zero records are probably fixed-size/list padding. They should
not be treated as active capability entries.

## Post-test state

Direct PRC read still works:

```text
PRC_READ_OK knob=0x001d value=0x0001
```

BAR0 floorsweep/L2 snapshot remained unchanged:

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

Host status remained:

```text
01:00.0 NVIDIA GB202 [GeForce RTX 5090] [10de:2b85]
Kernel driver in use: vfio-pci
```

No relevant host kernel log lines were found in the recent window for
`NVRM`, `Xid`, `vfio`, `AER`, `PCIe`, `GSP`, `FSP`, `fatal`, or `error`.

## Current conclusion

The FSP PRC family is definitely advertised and queryable on this card in the
current VM state.

The problem has moved one layer deeper:

```text
not transport
not mailbox port
not missing PRC-family capability
not invalid knob ID for read
but PRC object-write policy/options/lifecycle for 0x1d
```

This also means a MODS-style host QCAP prefetch is not a magic credential. The
direct caps-query response contains only `{NvdmType, Version}` records. It does
not return a token, nonce, session handle, lease, or security level that the
subsequent PRC packet would carry.
