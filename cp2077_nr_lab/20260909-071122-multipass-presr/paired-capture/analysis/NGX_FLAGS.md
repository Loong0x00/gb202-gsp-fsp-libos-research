# NGX DLSS feature-flag verification

The local NVIDIA DLSS SDK checkout was inspected rather than inferring flag
meaning from the observed value `0x4b`.

Verified source at implementation time:

- repository: `/home/user/rt_5090_project/nvidia-dlss-official`
- Git commit: `a291cc7d2cc642a51566f3dfd5376f635cd1b284`
- header: `include/nvsdk_ngx_defs.h`
- header SHA-256:
  `ea23f33497cd274860d1c25a97644fce807dcb0037c594547203343103fad03e`
- enum: `NVSDK_NGX_DLSS_Feature_Flags` (header lines 286-300 in this checkout)

Relevant definitions from that actual header are:

```c
NVSDK_NGX_DLSS_Feature_Flags_IsHDR         = 1 << 0,
NVSDK_NGX_DLSS_Feature_Flags_MVLowRes      = 1 << 1,
NVSDK_NGX_DLSS_Feature_Flags_MVJittered    = 1 << 2,
NVSDK_NGX_DLSS_Feature_Flags_DepthInverted = 1 << 3,
NVSDK_NGX_DLSS_Feature_Flags_AutoExposure  = 1 << 6,
```

Thus `0x4b == 0b01001011` sets bits 0, 1, 3, and 6. It does **not** set bit 2,
so `mv_jittered` must be false for source feature flags `0x4b`. The analyzer
cross-checks metadata against bit 2 and flags disagreement as a metadata error.

This verification establishes the bit's declared meaning only. It does not by
itself establish the captured game's motion-vector direction, sign, coordinate
origin, or which signed jitter delta (if any) is needed for color alignment.
Those remain explicit, reported analysis options; see `README.md`.
