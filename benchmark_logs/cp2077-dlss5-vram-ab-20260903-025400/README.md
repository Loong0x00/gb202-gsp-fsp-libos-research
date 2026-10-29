# Cyberpunk 2077 DLSS5 VRAM A/B — 2026-09-03

## Scope

Six official in-game benchmark runs, two per condition, at fixed:

- Cyberpunk 2077 2.31;
- 6144×3456 borderless;
- Path Tracing enabled;
- DLAA selected, DRS off;
- all frame generation off;
- RTX 5090 with the restored user V/F/XBAR/SYS configuration, 15001 MHz MCLK and 600 W power cap.

The two repeat orders were effectively:

1. baseline → dual model → replacement;
2. replacement → dual model → baseline.

VRAM is NVML whole-device `memory.used`, sampled during the benchmark scene. Desktop/background residency is included but was held unchanged. Each row below is the mean of two complete 972-frame runs.

## Conditions

1. **DLAA / NR off:** community add-on loaded but `NeuralUplift=0`; no signed DLSSNR initialization or Feature 18 creation receipt in the run's ReShade log.
2. **DLAA + NR:** normal game DLAA Evaluate followed by signed Feature 18 through the validated Vulkan companion bridge.
3. **NR replacing DLAA:** the owned bridge logs `DLAA replacement enabled` and `DLAA replaced`, skips the original DLAA Evaluate, seeds the game output from raw color, then runs Feature 18.

The replacement condition is a resource/execution experiment, not an image-quality-equivalent shipping recommendation.

## Results

| Condition | FPS | Frame ms | VRAM mean | VRAM median | VRAM P90 | VRAM max | Mean power | Mean GPC |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| DLAA / NR off | 11.4836 | 87.0808 | 26498 MiB | 26474 MiB | 26693 MiB | 26741 MiB | 543.0 W | 2904 MHz |
| DLAA + Feature 18 | 9.6432 | 103.7000 | 29537 MiB | 29528 MiB | 29697 MiB | 29711 MiB | 563.9 W | 2858 MHz |
| Feature 18 replacing DLAA | 9.8059 | 101.9796 | 29454 MiB | 29452 MiB | 29566 MiB | 29615 MiB | 561.4 W | 2864 MHz |

Derived changes:

- Normal Feature 18 chain versus baseline: **+3039 MiB mean VRAM**, +16.619 ms, -16.03% FPS.
- Replacement versus baseline: **+2956 MiB mean VRAM**, +14.899 ms, -14.61% FPS.
- Replacement versus dual chain: **-83 MiB mean VRAM**, -1.720 ms, +1.69% FPS.

Individual FPS values:

- baseline: 11.4592 / 11.5081;
- dual: 9.6228 / 9.6637;
- replacement: 9.8096 / 9.8022.

Individual mean-VRAM values:

- baseline: 26455 / 26541 MiB;
- dual: 29546 / 29529 MiB;
- replacement: 29514 / 29395 MiB.

## Interpretation

The new paired test **does not reproduce** the older apparent 1.55 GiB saving attributed to replacing DLAA. The observed 83 MiB group difference is within the 100 MiB-class residency/run variation and is not a resolved persistent-VRAM saving.

The reason is visible in the integration lifecycle: replacing DLAA skips its per-frame Evaluate, but the game still creates and retains the DLAA feature and associated persistent resources. Feature 18 itself adds about 3.0 GiB of whole-device residency in this 6K configuration. The bridge's explicit full-resolution copy/codec surfaces are only a portion of that; the opaque runtime's weights, history and activation workspace dominate the remaining delta.

Skipping DLAA does produce a small, highly repeatable execution saving of about 1.72 ms, but not a corresponding feature-allocation release.

This result does not constitute a direct Wuthering Waves community-binary-versus-owned-service comparison. Both NR-on Cyberpunk conditions use the same community add-on resource owner plus the same companion bridge; the variable is whether the original DLAA Evaluate executes. The pure community D3D12 output path is visually invalid under this Wine setup and was not used as a fake valid comparator.

Therefore the defensible conclusion is:

> The owned path avoids unnecessary explicit copies in its own code, but current evidence does not support claiming a large total-VRAM advantage. At 6K, the DLSSNR runtime contributes approximately 3 GiB of additional observed residency regardless of whether DLAA Evaluate is skipped.

## Integrity and restoration

Relevant component hashes are in `component-sha256.txt`; the signed DLSSNR runtime is:

`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`

After all six runs:

- Cyberpunk `ReShade.ini` restored byte-for-byte;
- Cyberpunk `UserSettings.json` restored byte-for-byte;
- `/etc/lact/config.yaml` unchanged byte-for-byte;
- MCLK remained 15001 MHz and power limit/default remained 600/600 W;
- no Cyberpunk process remained;
- GPU Recovery Action was `None`, PCIe Replays Since Reset was `0`;
- `kernel-nvidia-events-final.txt` is empty: no Xid, NVRM assertion, `gpu_vaspace` or `intermap` event.

Machine-readable values are in `results.csv` and `summary.json`.
