# GPT Pro follow-up static closure, 2026-07-27

Scope: static/read-only only. No live GPU access, no BAR/MMIO/FB/WPR/GSP heap read, no reset, no VBIOS change.

## Summary

GPT Pro's main recommendation is directionally correct:

```text
narrowly validate live gpio_object
  -> in-place repair GPIO3 d1/5c runtime record
  -> ActivateHwFunction(d1, 3)
  -> drive PWM11 directly at low duty
```

This is now the highest-value route **if and only if** a safe single-address GSP VA read/write primitive exists. The current missing primitive is still the live GSP private-object access, not the field semantics.

The immediate static follow-up closed the attractive `0x20800aeb` question and several display/G-SYNC control candidates:

- `0x20800aeb` returns only a 64-bit free heap size, not a heap base, object address, allocation descriptor, or pointer list.
- `0x20800adc`, `0x20800ade`, and `0x20800aed` are display/G-SYNC oriented controls and do not expose arbitrary GPIO3 function/selector payloads.
- The true `ActivateHwFunction` implementation begins before the wrapper at `0x01801fa4`; the wrapper tail-calls the implementation around `0x01801ee8`.

## New files generated

```text
/home/user/rt_5090_project/fan_followup_dispatch_rows_20260727.txt
/home/user/rt_5090_project/fan_followup_handler_snippets_20260727.txt
/home/user/rt_5090_project/fan_followup_activate_hw_function_full_20260727.txt
```

These have also been copied into:

```text
/home/user/gptpro_fan_route_pack_20260727_flat
```

## `0x20800aeb` closure

Public header:

```c
typedef struct NV2080_CTRL_INTERNAL_GPU_GET_GSP_RM_FREE_HEAP_PARAMS {
    NV_DECLARE_ALIGNED(NvU64 freeHeapSize, 8);
} NV2080_CTRL_INTERNAL_GPU_GET_GSP_RM_FREE_HEAP_PARAMS;

#define NV2080_CTRL_CMD_INTERNAL_GPU_GET_GSP_RM_FREE_HEAP (0x20800aeb)
```

Dispatch row:

```text
0x20800aeb handler=0x01431074 flags=0xc0 access=0x0 psize=0x8
```

Key handler behavior:

```asm
0143107e: mv    a5, a0
01431080: mv    s1, a1          ; params pointer
...
01431096: ld    a5, -0x1e8(a0)
0143109c: ld    a5, 0x278(a5)
014310a0: ld    a5, 0x78(a5)
014310a2: sd    a5, 0(s1)       ; params->freeHeapSize
0143109a: li    a0, 0           ; NV_OK
```

Conclusion:

- It is not a GSP heap reader.
- It is not a heap base/address leak.
- It cannot locate `gpio_object`.
- It can at most provide an aggregate free-size number, similar in usefulness class to existing heap stats.

## `0x20800adc` / `0x20800ade` / `0x20800aed`

Dispatch rows:

```text
0x20800adc handler=0x0121f8a8 flags=0xc0 access=0x0 psize=0x18
0x20800ade handler=0x011d44d4 flags=0xc0 access=0x0 psize=0x10
0x20800aed handler=0x011f86f4 flags=0xc0 access=0x0 psize=0x1
```

Header-level ABI:

```c
// 0x20800adc
typedef struct {
    NvU32  pinSetIn;          // in
    NvU32  pinSetOut;         // in
    NvBool bMasterScanLock;   // out
    NvU32  masterScanLockPin; // out
    NvBool bSlaveScanLock;    // out
    NvU32  slaveScanLockPin;  // out
} NV2080_CTRL_INTERNAL_DISP_PINSETS_TO_LOCKPINS_PARAMS;

// 0x20800ade
typedef struct {
    NvU32  pinSet;        // in
    NvU32  gpioFunction;  // out
    NvU32  gpioPin;       // out
    NvBool gpioDirection; // out
} NV2080_CTRL_INTERNAL_DISP_SET_SLI_LINK_GPIO_SW_CONTROL_PARAMS;

// 0x20800aed
typedef struct {
    NvBool bApplyStereoPinAlwaysHiWar;
} NV2080_CTRL_INTERNAL_GSYNC_APPLY_STEREO_PIN_ALWAYS_HI_WAR_PARAMS;
```

Conclusion:

- `0x20800adc` maps display pinsets to lock pins; no selector payload.
- `0x20800ade` has only `pinSet` as input; `gpioFunction`, `gpioPin`, and `gpioDirection` are outputs.
- `0x20800aed` can apply a stereo-pin workaround and calls the GPIO `+0x250` selector path with fixed selector values (`0x48` or `0`) around GPIO line `0x10`; it is not a GPIO3/PWM11 arbitrary selector setter.
- These routes should not be fuzzed live for fan recovery.

## Activate wrapper correction

The exported wrapper at `0x01801fa4` is only a Subdevice/RM wrapper:

```asm
01801fa4: ld    a5, 0x158(a0)
01801faa: ld    a5, 0xe0(a5)
01801fae: ld    a0, 8(a5 + 0x2000) ; GPIO object pointer
01801fb2: lw    a2, 4(a1)
01801fb4: lw    a1, 0(a1)
01801fb6: tail  0x01801ee8
```

The real implementation is around `0x01801ee8`. The follow-up snippet file contains both the implementation and wrapper.

This supports GPT Pro's suggestion that `0x01801fa4`/wrapper may help recover a shorter object-location chain:

```text
Subdevice/RM object -> ... -> *(+0xe0) -> +0x2000 + 8 -> gpio_object
```

But it does **not** by itself give a host-readable pointer value.

## Agreement with GPT Pro's route

The practical route should be split:

1. **Physical route first**
   - Make GPIO3 select PWM11.
   - Use already known PWM11 config/duty writes to drive fans 2/4.
   - Do not require NV-CONTROL to show a second fan target initially.

2. **FanCooler/BoardObjGrp later**
   - Creating a second FanCooler child is much larger and not needed for first physical proof.

The hard blocker remains:

```text
safe live GSP private-object read/write primitive
```

Without that primitive, the exact proposed narrow read:

```text
*(0x041d3f00)
*(vbios_table_object + 0x21a8)
gpio_object + vtable/count/record slices
```

cannot yet be executed safely.

## Next useful static targets

If continuing without live GPU access, the best static targets are:

1. Reconstruct the shortest `Subdevice -> gpio_object` pointer chain from `0x01801fa4` and its surrounding object layout.
2. Identify whether any CPU-RM state mirrors that `gpio_object` pointer or corresponding GSP object handle.
3. Audit any existing project code that claims to read single GSP VA values; reject broad FB/WPR scans.
4. If a single-address GSP VA reader is found, test only the GPT Pro proposed pointer chain and vtable fingerprint; do not scan.

## Updated no-repeat boundary

Do not continue treating `0x20800aeb` as a possible heap-address disclosure. It is an aggregate free-size getter only.
