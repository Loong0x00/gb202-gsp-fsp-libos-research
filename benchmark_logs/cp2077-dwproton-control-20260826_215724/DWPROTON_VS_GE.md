# DWProton 11.0-4 vs GE-Proton 10-34

## Local bundle difference

| Component | GE-Proton 10-34 | DWProton 11.0-4 |
|---|---|---|
| Wine | `wine-10.0 (Staging)` | `wine-11.0 (CachyOS)` |
| DXVK | `v2.7.1-509-g1676dcaf` | `v2.7.1-715-geae7563` |
| vkd3d-proton | `vkd3d-1.1-5122-gbd3f5e3d` | `vkd3d-1.1-5375-gc150088` |
| DXVK-NVAPI | `v0.9.1-19-g8db2e81` | `v0.9.2-6-g46c300b` |
| Proton launcher diff | baseline | 372 insertions, 314 deletions relative to GE |

The DW run reported `ntsync: up and running`. The runner change is therefore
not simply FSync versus NTSync. DW also replaced the graphics DLLs in the
isolated prefix and reported Windows 11 (`10.0.22000`), while the GE baseline
reported Windows 10 (`10.0.19045`).

## Controlled Cyberpunk 2077 runs

All runs used the same game version and settings: 6144x3456, native rendering,
no frame generation, path tracing enabled, the same 600 W power limit, and the
same live GPU clock configuration.

| Runner/run | Average FPS | Minimum FPS | Mean GPU power | Mean GPU clock | Xid/GSP |
|---|---:|---:|---:|---:|---:|
| GE-Proton 10-34 baseline | 11.6171 | 10.0236 | 512.5 W | 2936.3 MHz | 0 |
| DWProton 11.0-4 launch 1 | 11.6697 | 10.1007 | 513.3 W | 2937.2 MHz | 0 |
| DWProton 11.0-4 launch 2 | 11.5687 | 9.9069 | 514.4 W | 2936.1 MHz | 0 |

The mean of the two DW runs is `11.6192 FPS`, only `+0.017%` relative to the
GE baseline. No meaningful performance difference is demonstrated.

## Cache lifecycle

- Launch 1 rejected the existing working-directory vkd3d-proton cache because
  its recorded driver/translator identity did not match, then generated a DW
  write cache. The pre-run cache was not separately copied before launch, so
  its exact provenance is not claimed here.
- Launch 2 merged and promoted that DW write cache, mapped the resulting read
  cache, parsed it, flushed additional PSOs, and completed normally.
- Both launches completed with no Xid, GSP error, reset, thermal throttle, or
  hardware slowdown.

## Supported conclusion

DWProton is not sufficient to reproduce the failure, including on a second
process launch with its own newly generated pipeline cache. It remains a
correlation shared by the three failing games, but this control weakens a
generic DWProton or generic DW vkd3d-proton failure. It does not test the
DXVK/D3D11 path used by Genshin and Honkai: Star Rail, or the exact dynamic
resource and command streams produced by those games and Wuthering Waves.

The normal Steam Cyberpunk prefix was not modified. Both DW launches used the
Btrfs reflink clone at:

`/home/user/rt_5090_project/test_prefixes/cp2077-dwproton-20260826_215724`

The vkd3d-proton cache is relative to the launch working directory rather than
the Wine prefix. These runs updated `/home/user/vkd3d-proton.cache{,.write}`;
post-run copies and hashes are preserved beside this report. A later GE run
will reject or rebuild the DW cache by translator identity as needed.
