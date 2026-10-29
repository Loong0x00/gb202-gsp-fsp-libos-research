# True pre-SR 1/2/3-pass package

Branch-local MinGW-w64 build; no deployment or game launch was performed.

## Files

- `00-dlss-ngx-router.addon64` — unchanged single-pre router source/ABI client;
  temporary signed-SR Color bind uses the verified MSVC slot 1 and is restored.
- `01-dlss5-presr-service.addon64` — actual input-resolution base -> A -> B -> A
  service with three independent Feature 18 histories and Vulkan GPU timing.
- `SHA256SUMS` — hashes of the two deployable files.

The router implementation source is byte-identical to the GPU-validated
`../presr` source (`620f6dcc...`). This local PE build has the same size and
code and differs from that prior packaged router at only six linker
timestamp/checksum bytes. The ABI remains v2/layout 160/64; the ABI header's
only changes are semantic comments for multipass and `nr_evaluate_count`.

## Build/test

```bash
make -C router all
make -C service presr-multipass
make -C tests clean check
```

Service defines: `DLSS5_POST_SERVICE=1`, `DLSS5_PRE_SR_SERVICE=1`, and
`DLSS5_GPU_TIMING=1`. Its export table contains `DLSS5_PreEvaluateV2` and
`DLSS5_PreReleaseV2`, and no `DLSS5_PostEvaluate`.

## Invocation

From the parent lab directory, cold launch with settings restoration:

```bash
python3 run_case.py presr3 --presr nr \
  --service presr-multipass/copies/presr-multipass/01-dlss5-presr-service.addon64 \
  --router presr-multipass/copies/presr-multipass/00-dlss-ngx-router.addon64 \
  --env DLSS5_PRE_PASSES=3
```

`DLSS5_PRE_PASSES` is latched, defaults to 1, and is clamped to 1..3.
Compilation/static checks are not evidence of runtime/GPU success.

## Source hashes

```text
620f6dcc269a42050e7d70d61f4e89f7e1bff91698d25703ebd2e1228edfc55d  router/router_addon.cpp
c014d8f005e5487130f3636a10a93fdcf3fdaf336934e8ff2faf1c3803302201  router/ngx_proxy_abi.h
875b7c9dd5c8761078ce6300bf1969133b07350681a48ffa455cc49045768391  router/dlss5_presr_abi.h
4b12b22354d6b56d3cd3190321717889b1306a92e05ce8deb1fbec2e0fe82b75  router/dlss5_presr_policy.h
3d5caf18d1be30ec1ce66b72883cff1192e6f1a9dd2aff8fc6844433d2608b72  service/dlss5_vk_bridge.cpp
b65f90df201f7b4204c79779bab84f50820bff9e3a5e7cea6822f19d17409b23  service/presr_multipass_policy.h
994ac3dc271289c0449685b41a7ec47b68529baff26ca64e3ac63f83b5865293  service/codec_encode.comp
b81c1b16b62e5ffeb05294ea365ba4db0a8b857f3b49171dd5b6073b15e9769a  service/codec_decode.comp
```
