# Private NvAPI V3 non-advertised channel scan

Read-only command run on RTX 5090, driver 610.43.03:

```sh
./nvapi_thermal_probe.py --scan-hidden-v3
```

The V3 status structure contains three 32-bit request masks, for 96 possible
slots.  The driver advertised group 0 mask `0x00ffffff` and group 1/2 masks
`0x00000000`.  The probe then made one GET call per non-advertised bit:

* group 0 bits 24..31: 8 calls;
* group 1 bits 0..31: 32 calls;
* group 2 bits 0..31: 32 calls.

All 72 calls returned `NVAPI_ERROR` (`-1`); zero returned a record or a
temperature.  The advertised GPU_MAX channel remained the invalid 255 C
sentinel, GPU_AVG matched edge, and MEMORY remained the primary memory value.

Status: **VERIFIED negative** for this exact private API/version/driver.  It
does not rule out a different, unknown Blackwell-specific control.
