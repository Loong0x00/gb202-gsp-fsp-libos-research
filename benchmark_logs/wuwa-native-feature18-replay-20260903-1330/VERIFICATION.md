# Native Feature18 temporal replay verification

- Source evidence: `/home/user/rt_5090_project/benchmark_logs/wuwa-native-replay-r-cinematic-20260903-122359/README.md`
- Capture: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-raw-captures/20260903-122359-540-p320`
- Capture preflight: all entries in `SHA256SUMS` passed (full log: `input-sha256-check.log`).
- Capture file size/mtime inventory is byte-identical before/after; `input-files.diff` is empty.
- Runtime DLL SHA-256: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` (required exact value).
- Executable also checked the DLL SHA and the original six bytes at RVA `0x17e94` before patching.
- Smoke: one raw0 frame, GPU codec encode equivalent with HdrMode=1/PaperWhiteScale=1, RGBA16F color/output, RG16F motion, R32F depth; passed.
- Temporal replay: one Feature18 handle evaluated every frame raw0..31 in order. No temporal prefix was skipped.
- Create-only compatibility metadata: 4096x2304, scaling ratio 0.5, upscaling=true.
- Evaluation metadata: 3564x2005 guides, scaling ratio 1, upscaling=false; manifest jitter/exposure/subrect/MV scale/reset used per frame.
- Raw0 capture reset was false; replay forced it true and discloses this in every run/session sidecar. Captured reset at raw9 was preserved.
- Only neural raw24..28 were saved in the default replay, each as tightly packed 6144x3456 RGBA16F. Their SHA-256 values are in `replay-raw0-31/output-manifest.jsonl`.
- No game deployment files were changed and no capture payload was moved, deleted, or cleaned.
- Ordinary local Wine/CUDA execution was used; no Fast/priority service tier was requested.
