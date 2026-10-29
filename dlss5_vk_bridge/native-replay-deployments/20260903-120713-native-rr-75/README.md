# Native signed-RR replay flight deployment

- Deployment: 20260903-120713
- Capture: untouched 6144x3456 signed RR output + native motion + native depth
- Bound: 75 deferred frames, hard 12-GiB readback cap
- Service SHA-256: fc776abc5c728152c26fe6a5a9af37456b6e8e4df1a04e07caff39963321e8a0
- Router SHA-256: 13feb8aa200c6a3019875c76712335a8f21254885ade25ee36639d8d00bb1a76
- Signed nvngx_dlss.dll SHA-256: 22c4660249da5b352cde0ce4d95178c3761223dd6ac096d0b88e5c03d7a5cdd1
- The capture service exports only DLSS5_CaptureNative; it does not link codec shaders, Vulkan, NGX Feature 18, or CUDA.
- Router keeps requested/effective_dlss5_mode=0 and never changes the signed RR Evaluate return value.
- Rollback: /home/user/rt_5090_project/dlss5_vk_bridge/native-replay-deployments/20260903-120713-native-rr-75/restore.sh
