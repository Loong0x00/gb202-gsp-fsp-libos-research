# Windows 610.88 vs Linux 610.57.04 GSP comparison

Date: 2026-08-21

No GPU control operation was performed. The Windows package was downloaded,
listed, and extracted offline. The Linux comparison files were read from the
currently installed driver package.

## Sources

- Windows package:
  `https://us.download.nvidia.com/Windows/610.88/610.88-desktop-win10-win11-64bit-international-dch-whql.exe`
- Windows release page:
  `https://www.nvidia.com/en-us/geforce/drivers/details/274392/`
- Linux firmware:
  `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`
- NVIDIA R610 release pairing:
  Linux `610.57.04`, Windows `610.88`

## Package receipt

```text
979651304 bytes
SHA-256 576a90c6f6eea47748db1defcbca1746c81fe4eb972f3132d30878778cee0b09
```

## Direct GSP comparison

```text
Windows 610.88 Display.Driver/gsp_ga10x.bin
size      84306072 bytes
SHA-256   24bf29785da0570b0ec6d66f08bfe8eff6fc6274a3b25f3dbcb5084a1bcf72c3
Build ID  97c5acd730b88a330e5c134ab36684fd97f767a2
.fwversion 610.57.01
build marker DVSReal r610_85 610.88 unknown

Linux 610.57.04 gsp_ga10x.bin
size      84310168 bytes
SHA-256   c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999
Build ID  4f09703c5c7d57baa527d6a189bb6d118bc60e49
.fwversion 610.57.04
build marker Private r610_85 610.88 unknown
```

The full-file hashes do not match. The Linux file is exactly 4096 bytes larger.
Both files are 64-bit little-endian RISC-V relocatable ELF containers with the
same 19-section layout. Both contain GB20x-specific signature sections.

The `.fwimage` payloads first differ at one-based byte offset 446482. Comparing
nonzero 4096-byte blocks independent of the one-block layout shift found 16402
identical blocks out of 20162 Windows nonzero blocks (81.351056%). The result is
strong evidence of a shared firmware code line, but it is not byte-identical
firmware and does not prove identical runtime behavior.

## GB202-selected PMU images

The outer-file mismatch is caused by the host GSP-RM build, not by a different
GB202 PMU payload. The main inner GSP ELF starts at wrapper offset `0x19f040` in
both packages. Its executable segment is one page larger on Linux. After
aligning at the end of each main ELF, both appended firmware stores are exactly
`65323008` bytes long.

The two stores differ in 802 bytes grouped into 381 ranges. Seven bytes are the
`DVSReal` versus `Private` build marker, four bytes are a relocated address in
the nested vGPU-host ELF, and nearly all remaining differences are relocated
pointers in the final bindata table. The firmware payload storage is otherwise
byte-identical.

The Windows and Linux `Pmu` constructors were independently followed for
GB202/chip index 65. Both take the same mask branch and install getters for the
same three bindata archives:

```text
Pmu HAL slot 0x320 -> UCODE_DESC index 838, 92 bytes
SHA-256 1d207d20a545070c65265bd0e20e2028b5c3557a75bac21a741c3d5cd65701cd

Pmu HAL slot 0x330 -> UCODE_IMAGE index 849, 2002944 bytes
SHA-256 1b042288def7e80fe60478cf8deca7743699f286b30afb665ee6ee367c84379c

Pmu HAL slot 0x348 -> UCODE_IMAGE index 858, 2002944 bytes
SHA-256 32ce8e78803f776b3faab02cb0cef6cfc6dedc0d5033c3fd1510995412455dc3
```

Every hash above is identical between Windows 610.88 and Linux 610.57.04.
Because both possible GB202 PMU image slots match, the result does not depend
on which production profile the runtime ultimately selects.

## Exact host-GSP control-code matches

Several already reconstructed Linux control blocks also occur exactly once in
the Windows main GSP ELF:

```text
voltage-request writer prefix, 192 bytes
Linux VA  0x0167d028
Windows VA 0x01680d24
SHA-256 1fc54ab4e8c7ffd772c174c17e40315839b95d7ec61e4ef3bd3fe4e5510ae9e9

voltage-arbiter winner loop, 96 bytes
Linux VA  0x017deb48
Windows VA 0x017e0e60
SHA-256 c21692b2a12d382351528cb62de4ba880fdff372dcaf2cb89cc6f37f7a5c3f8c

voltage-grid quantizer prefix, 96 bytes
Linux VA  0x017e1cdc
Windows VA 0x017e3ff4
SHA-256 a1f59081a6cf2c185439e03d31c8383360cd3e8def2286e4459184e0c0f16e33
```

These are exact byte matches, not decompiler-level similarity.

## Windows RTX 5090 installation path

The generic Windows INF maps `PCI\\VEN_10DE&DEV_2B85` (RTX 5090) to
`Section094`. That section uses `nv_system32_RS_copyfiles__06`, which explicitly
copies both `gsp_ga10x.bin` and `gsp_tu10x.bin`. Thus the compared GSP is part of
the Windows RTX 5090 installation path, not merely an unrelated archived file.

## Live Linux readback

Read-only `nvidia-smi -q` on the tested RTX 5090 reported:

```text
KMD Version          610.57.04
GSP Firmware Version 610.57.04
VBIOS Version        98.02.2E.80.50
```

## Conclusion

The outer host-GSP containers are not byte-identical because the paired Windows
and Linux packages embed host revisions `610.57.01` and `610.57.04`. However,
the GB202-selected PMU descriptor and both possible PMU images are byte-for-byte
identical, and exact copies of the reconstructed voltage-request, winner-loop,
and quantization code are present in the Windows host GSP.

This rules out a Windows-specific PMU predictor implementation. A Windows
runtime test is still useful to determine whether WDDM/host-RM supplies the same
inputs and preserves the same post-DG0 voltage/final-clock mismatch, but it is
no longer needed to establish that the PMU algorithm shipped for GB202 is the
same binary.
