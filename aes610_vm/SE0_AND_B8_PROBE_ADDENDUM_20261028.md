# SE0 and B8 follow-up evidence — 2026-10-28

## SE0 read-only RPC probe

A read-only `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS` probe was run through the existing `gpuallowlist.slice`, without changing the global allowlist configuration or writing any register. It used one register per RPC and a 100 ms delay:

```text
PMC_BOOT_0   = 0x1b2000a1   (positive control)
FSP_EMEMC    = 0x02000014   (positive control)
0x015010f8   = 0xbadf2082
0x016410f8   = 0xbadf1100
```

Log: `/home/user/rt_5090_project/gsp615_rpc_equiv_20261027/se0_read_probe_run.log`

`0xbadf1100` is documented in the local hardware research as a target-not-decoded/poison result. Both candidates are therefore unavailable through the host GSP register-read path. This does not prove physical SE0 absence, but it gives no support for blindly replacing the alias with identity. The 615 descriptor still uses the same `0x01500000` SE0 base, so 615 supplies no new mapping.

The initial ordinary-sudo attempt failed at device open because of the host's cgroup-device guard. The successful probe used the existing allowed slice; no policy was relaxed.

## B8 canary status

The map was corrected for the current enlarged-queue layout:

- ARG=`0x0fe4791610`
- QOUT=`0x2083c100`
- current metadata base from Xid evidence=`0x0fe4791010`

The natural B8 backend still produced no output canary. Follow-up reads of the old page-table address, page-table+0x20, MQI+0x38, and `pTheirEntries` returned zero. This means the natural shared-window/stream state is not recovered. It is not valid to keep substituting nearby page-table addresses or to claim a B8 read/write primitive.

## Current boundary

- Multi-callback and natural AES C construction are verified.
- AES0 reaches an SE0 access fault; no AES oracle exists.
- B8 has no validated window read/write canary.
- No `FSP_RUN` input was used.
- Host NVIDIA/GDM were restored and the task overlays were removed.

Further work should recover the current MQI/shared-window initialization from static code or a new runtime artifact before another B8 experiment.
