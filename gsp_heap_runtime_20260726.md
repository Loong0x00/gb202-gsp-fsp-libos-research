# GB202 / 610.43.03 GSP-RM heap runtime result

## Scope

This records a single public, read-only RM query made on the live RTX 5090.
It does not map BAR0, scan framebuffer memory, load the local bridge module,
send a GSP-DMA transfer, change fan state, reset the GPU, or alter firmware.

## Runtime result

`NV2080_CTRL_CMD_GSP_GET_RM_HEAP_STATS` (`0x20803602`) succeeded through an
ordinary temporary RM client/device/subdevice tree:

```text
gsp_rm_heap managed=0x0a9045e0  largest_free=0x06096800
current allocated=0x0102b660 usable=0x00ffb3f0 tracking=0x00030270 allocations=12327
peak    allocated=0x013b9f30 usable=0x0139bee0 tracking=0x0001e050 allocations=7685
```

The managed heap is `177,227,232` bytes, or **169.017 MiB**.  The GPU
remained healthy immediately after the query (37 C, about 123 W at idle).

## What this corrects

The open 610.43.03 source calls this the *GSP FW WPR heap*:

- `kernel_gsp_gh100.c` places `kgspGetFwHeapSize(...)` in
  `pWprMeta->gspFwHeapSize` on Hopper-and-later, which is the GB202 path.
- `gsp_fw_heap.h` describes the size as the GSP FW WPR heap and includes a
  2048-client reserve of 96 MiB.
- GB202's generated HAL selects an OS carveout parameter of 22 MiB, a base of
  14 MiB, and min/max WPR heap limits of 88/280 MiB.

Therefore the earlier inference that the unreported gap after public ordinary
FB region `[0x300000, 0x7d95cffff]` was a complete 38.6-MiB GSP carveout was
false: a real 169-MiB WPR heap cannot fit in that gap.  The public FB-region
getter describes ordinary regions, not the full secure-WPR geometry.

As a result, the formerly inferred metadata address `0x7d98e0000` is retired.
The prior eight-byte zero read there is **not** evidence that WPR reads are
zero-masked, and is **not** evidence about GSP heap contents; it was an
unverified address.

## Remaining boundary

The public WPR-region getter (`0x20801364`) is unavailable from this client:
it returns `0x56` even after the narrowly scoped host-side internal flag
experiment.  The implementation requires an RM-internal caller, not merely
the internal control bit.  The supported heap-stats getter intentionally
returns aggregate counters only—no physical base, virtual base, allocation
address, or object enumeration.

Thus the evidence establishes that the relevant runtime objects reside in a
large protected GSP-managed heap, but it does not reveal an address at which a
FanCooler/GPIO record could be read or changed.  The safe next research task
is to locate an authenticated GSP/FSP layout-report mechanism or a genuine
runtime object-update API; brute-force FB addressing is no longer justified.
