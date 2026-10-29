# 610.43.03 GSP inner-ELF provenance

Verified on 2026-07-21.  This records how the temporary static-analysis ELF
maps back to the installed NVIDIA firmware without storing another 79-MiB
copy in the project.

## Outer firmware

- Path: `/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin`
- Size: `84277400` bytes
- SHA-256:
  `572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a`

## Inner ELF

- Temporary path used during this study: `/tmp/gsp_inner_19f040_a.elf`
- Outer file offset: `0x19f040` (`1699904`, exactly 26561 blocks of 64 bytes)
- Size: `82577496` bytes, extending exactly to outer EOF
- SHA-256:
  `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
- Format: stripped ELF64 little-endian RISC-V executable with RVC

## Reproduction and verification

The inner file is exactly the suffix of the outer firmware beginning at
`0x19f040`.  A reproducible extraction is:

```sh
dd if=/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin \
   of=/tmp/gsp_inner_19f040_a.elf bs=64 skip=26561 status=none
sha256sum /tmp/gsp_inner_19f040_a.elf
```

The 2026-07-21 streaming comparison was:

```sh
cmp -s -n 82577496 -i 1699904:0 \
  /usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin \
  /tmp/gsp_inner_19f040_a.elf
```

Result: `IDENTICAL`.

This proves artifact provenance only.  It does not by itself prove that any
particular function is selected by the GB202 HAL or reachable at runtime;
those require separate constructor/vtable and call-site evidence.
