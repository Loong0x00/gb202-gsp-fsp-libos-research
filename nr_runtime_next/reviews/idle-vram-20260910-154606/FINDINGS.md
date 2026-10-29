# Read-only idle VRAM attribution — 2026-09-10 15:43–15:48

User asks why roughly4G is used rather than their expected3G. No application was closed, GPU test launched, desktop altered, hardware acceleration disabled, or GPU/network configuration changed.

## Current observations

Five same-command `nvidia-smi -q -x` snapshots all report allocated framebuffer memory3725MiB (~3.64GiB). Visible per-process entries total2834MiB (C+G processes counted once):

| Process | PID | MiB |
|---|---:|---:|
| GNOME Shell |5083|879|
| Chrome GPU process |26235|827|
| Quill terminal |2376801|456|
| ChatGPT/Codex desktop GPU process (`/usr/lib/chatgpt/ChatGPT`) |611042|423|
| Steam + two web helpers |2682351/2682781/2682826|240|
| Xwayland |5372|9|

The arithmetic residual is891MiB. It is **not assigned to a particular process by these NVML entries**; do not call it confirmed driver cache, game residue, or a leak. This residual is separate from the460MiB reserved memory below. Per-process and device accounting need not match exactly, and shared resources complicate attribution.

No game/NR process appears in the GPU-process list or NVIDIA-device FD holders. FD inspection also shows mutter-x11-frames, browser/ChatGPT subprocesses and the Mission Center monitor; an open device FD alone does not prove significant VRAM ownership. Available user-readable fdinfo lacks per-client GPU-memory counters, so no finer attribution was established.

Quill's installed desktop description identifies it as a Rust+wgpu+cosmic-text Wayland terminal, not a local model inference service. C+G in NVML is not proof that an AI model is running. Quill started Sep8; the ChatGPT/Codex GPU process started Sep10 04:34. Start dates do not establish historical allocation sizes.

## Verified API accounting difference

Direct read-only calls to both NVML memory APIs at one instant returned:

- v1.used: **4185.125MiB =4.087GiB**
- v2.used (allocated): **3724.9375MiB =3.638GiB**
- v2.reserved: **460.1875MiB**
- exact equality: v1.used == v2.used + v2.reserved

Local SDK `/opt/cuda/include/nvml.h` lines249–273 explicitly defines v1.used as reserved+allocated, and v2.used as allocated, with system/driver/firmware reservation separated. A monitor using v1 or total-minus-free therefore shows ~4.09GiB where nvidia-smi's allocated field shows ~3.64GiB. The running Mission Center binary contains both API symbol names; its exact selected call was not proven, so do not claim its implementation solely from strings.

## Historical limit

Retained WuWa launch-initial GPU samples already show3693MiB at09:00 and3688MiB at09:22, versus3725MiB now. These are launch-initial samples, not a controlled idle A/B, but they do not show a newly accumulated whole1GiB from the latest NR test. There is no captured per-process breakdown of the user's expected3G baseline, so the precise cause of a perceived historical increase remains unproven.

Potential next step requires user choice: close one unneeded GUI application and compare the same APIs before/after. ChatGPT/Codex currently accounts for423MiB and Quill456MiB; their summed879MiB is current attribution, **not proof of a recent879MiB increase or a guaranteed free-memory gain on exit**. Do not kill GNOME/Xwayland or the user's current Quill terminal to conduct a test.
