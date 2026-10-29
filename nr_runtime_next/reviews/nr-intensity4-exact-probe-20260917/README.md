# DLSS NR 310.8 `DLSSNR.Intensity=4` exact-path probe

## Result

For the pinned public CUDA Feature-18 contract, requested `DLSSNR.Intensity=4.0`
is accepted but produces **exactly the same bytes as intensity 1.0**. It does not
execute four NR passes and does not amplify the first/reset or immediate second
frame beyond the intensity-1 output.

Pinned DLL SHA256:
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.

Contract: 512x512 RGBA32F, scaling ratio 1, tone .25, structure .75, skin -1,
style 0, auto-mask off, no control mask; reset frame followed by counter=1 with
zero motion.

| Output | Intensity 4 SHA256 | Accepted independent transparent intensity-1 SHA256 | Differing bytes |
|---|---|---|---:|
| reset/first frame | `571fa2100c1842deff8769510a78f90cbe84810d64bb3ea82eaba41cf1cd793e` | same | 0 |
| immediate second frame | `e451fcf93663340a587888fa244e6cb62bad3030a0e4b157ff42a9bc6ec2530f` | same | 0 |

The independent transparent 71-block model was also executed once on the
intensity-4 effective route. Its forward had no DLL/CUBIN/PTX/VM/CUDA/file/
network/subprocess calls and returned the same first-frame SHA with zero differing
bytes versus the native intensity-4 oracle.

Observed native timings remained one inference per frame:

- reset frame: 4.331744 ms GPU in the two-frame run (4.360704 ms in the separate first-frame run)
- immediate second frame: 4.333440 ms GPU

An older independent native A/B on a different 384x384 image also has intensity
2 byte-identical to intensity 1, while intensity .5 is the exact binary32 midpoint
between the intensity-0 and intensity-1 outputs. Together these are operational
evidence of saturation at the intensity-1 endpoint for this DLL/path. They do not
locate the closed-source implementation of that saturation.

## Boundary

This does not prove behavior for another DLSS NR DLL/model version, non-RGBA32F
formats, other resolutions, nonzero motion, counter >=2, control masks, or real
game Vulkan/D3D resource lifecycles.

## Safety and retained failure

Both native runs used `benchmark.lock`, the no-games gate, >=4 GiB free-VRAM
gate, 31000 MiB cap, 30 s timeout and the recovery Guardian. Both returned zero.
The first transparent launcher attempt failed before model execution because
`/usr/bin/time` is absent; the exact command/error is retained in
`FIRST_TRANSPARENT_LAUNCH_FAILURE.log`, and the corrected `nice 19` run returned zero.
