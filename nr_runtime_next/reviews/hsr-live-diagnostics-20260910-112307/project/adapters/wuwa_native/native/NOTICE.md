# Source provenance and redistribution notice

The native host/runtime implementation in this directory is new project code derived from the local, game-verified behavior in:

- `/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/full-order`
- `/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/presr-multipass`
- `/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/multipass`
- `/home/user/rt_5090_project/dlss_ngx_proxy`

In particular, the private NGX parameter slot contracts, DWORD handle-ID rule, vkd3d-proton interop IID, signed NR Vulkan bootstrap, Feature 18 scalar/resource keys, and HDR codec behavior retain that provenance. The two GLSL codec sources and their three SPIR-V artifacts were copied unchanged from `full-order/service`; their pre-copy SHA-256 values are documented below.

```text
994ac3dc271289c0449685b41a7ec47b68529baff26ca64e3ac63f83b5865293  codec_encode.comp
b81c1b16b62e5ffeb05294ea365ba4db0a8b857f3b49171dd5b6073b15e9769a  codec_decode.comp
cf5dd51be82fb9a4c48d5902523e8317bd218a3eddf94fdb8fe9a6c91c96c334  codec_encode.comp.spv
838f60474af9367a520e500aad3fc9bdf02a37ef22df6a10fcc1d5a4b20ac74f  codec_decode.comp.spv
b17e32cdd120d2c40976d86ca05d375b2c128c837ad2c737a1ae1eb73f4c702e  codec_decode_r11.comp.spv
```

Those local sources contained no license header to carry forward. No copyright or license header was removed. This repository must not represent NVIDIA DLLs, NGX, Vulkan, Wine, vkd3d-proton, ReShade, or RenoDX as being included or relicensed by this notice.

The package intentionally contains no NVIDIA binary. `nvngx_dlssnr.dll`, NGX core, signed SR/RR feature DLLs, Wine/Proton DXGI, winevulkan, and vkd3d-proton are separately supplied prerequisites and are loaded without on-disk patching.
