# Pre-SR single-pass benchmark artifacts

Built locally with MinGW-w64 for x86-64 PE/COFF. No deployment was performed.

- `00-dlss-ngx-router.addon64`: owned signed-SR interception and ABI-v2 client.
- `01-dlss5-presr-service.addon64`: compact current-frame staging, HDR codec,
  one Vulkan Feature 18 pass, GPU timestamps. Exports no post-Evaluate service.
- `SHA256SUMS`: artifact hashes.

Build commands:

```bash
make -C router clean all
make -C service presr
make -C tests clean check
```

Build defines for the service:

```text
DLSS5_POST_SERVICE=1
DLSS5_PRE_SR_SERVICE=1
DLSS5_GPU_TIMING=1
```

Source/reference hashes at build:

```text
620f6dcc269a42050e7d70d61f4e89f7e1bff91698d25703ebd2e1228edfc55d  router/router_addon.cpp
c014d8f005e5487130f3636a10a93fdcf3fdaf336934e8ff2faf1c3803302201  router/ngx_proxy_abi.h
232188c7f1ec3f6e626aed56433eb9a036c27af94d79634b1e18bde18990ec45  router/dlss5_presr_abi.h
4b12b22354d6b56d3cd3190321717889b1306a92e05ce8deb1fbec2e0fe82b75  router/dlss5_presr_policy.h
1c75ddb306f8383e21b0600dd4e0aa4ac0f72cbbb5e53344b8ebbaeb7d21f9ee  service/dlss5_vk_bridge.cpp
994ac3dc271289c0449685b41a7ec47b68529baff26ca64e3ac63f83b5865293  service/codec_encode.comp
b81c1b16b62e5ffeb05294ea365ba4db0a8b857f3b49171dd5b6073b15e9769a  service/codec_decode.comp
b4b3fdac879fe1e0643dd6c001cb507d0f74667f51e899323c51664a897c4837  neural-upstream/src/addon.cpp @ c06c07b27c3c5af0d916c3d9545434735d624bdf
f9d0a217ac97107e257eb1be2da5d6d12fcdbf83852a68cc382dcf3beb1cf861  OptiScaler/shaders/dlssnr/DlssNr_Dx12.cpp @ ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853
2fa2846cd34b2229ac96b96c77994f5a1715c4fcb852bd6a359936cde7b7fdd8  benchmark_logs/dlss5-presr-static-20260908/README.md
```

Activation and evidence gates are in `../../docs/PRESR_BENCHMARK.md`.
