# Boundary: BLOCKED, not an unsafe SurfaceObject assumption

## Established statically

The **unmodified** 2,789,376-byte ELF SHA-256 is
`feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
Its exact selected entry is `cc_tinlayout_fused_post_block_swin_1h_32_fp8`.
The raw ELF metadata declares one 184-byte aggregate, parameter constant-bank
base `0x380`. Fresh CPU cuobjdump output contains 3,336 instructions, each
128-bit encoding checked against the ELF's selected `.text` section.

Two original stores:

| SASS PC | Handle load immediately preceding store | Store |
|---|---|---|
| `aa90` | `aa80: LDCU UR8, c[0][0x390]` | `SUST.P.2D.STRONG.SM.IGN [R52], R12, UR8` |
| `cfd0` | `cfc0: LDCU UR4, c[0][0x390]` | `SUST.P.2D.STRONG.SM.IGN [R52], R8, UR4` |

Thus the original SASS consumes the **low 32 bits of p+16 directly as a
uniform surface operand**. It does not load a descriptor through a device
pointer passed at p+16. This is distinct from main/skip/slab device pointers.
The pinned original PTX loads a 64-bit operand from p+16 into rd398/rd439 and
uses `sust.p.2d.v4.b32.zero` on both paths.

Local PTX ISA section 9.7.13.2 and the freshly fetched official documentation
(`evidence/official-sust.html`, URL and whole-response hash in `network.json`)
confirm:

* `.p` is a **formatted** store; X is a **sample/pixel offset**, NOT byte X.
* `.v4.b32` operands are R,G,B,A. For FLOAT surface formats these bits are FP32
  and are converted to the destination format. RGBA16F is the proposed format;
  it is NOT an instruction to store 16 raw bytes at x*8 or x*16.
* `.zero` drops out-of-range stores. The reference's two maps cover exactly
  x=0..7, y=0..7 for origin0/CTA0; no out-of-range store is needed here.
* The PTX description calls an indirect operand a `.u64` register holding the
  address of a `.surfref` variable. PTX's opaque-type section forbids treating
  this as ordinary dereferenceable memory or doing pointer arithmetic.

## NOT established

The CUDA Driver header documents that `cuSurfObjectCreate` returns an opaque
`CUsurfObject` for a CUDA array. It does **not** document the bit-level
correspondence between that opaque value and this original, previously
NVX/Vulkan-supplied, direct uniform `SUST.P` operand. The installed CUDA
`surf2Dwrite` wrapper calls an opaque compiler intrinsic; it does not expose
that correspondence either. A 64-bit typedef, the PTX `.u64` type, the archived
small numeric handle, and a successful resource-descriptor query are **not**
proof of exact original ELF compatibility. This is an evidence gap, not a
claim that CUDA objects are incompatible.

No documented source consulted here establishes the exact original handle
binding or original formatted FP32-to-F16 rounding. Source A's texture-object
binding to the original TEX operands also remains an end-to-end boundary;
normalized/nearest/clamp resource configuration alone does not prove it.
ELF CUDA API `0x86`, Mercury ISA 1.1 and load acceptance are retained as-is.
No supported-driver-load result has been measured.

## Consequence

`host.cpp` is a **compiled, non-launchable proposal**. The exact CLI execute
syntax is necessary but NOT sufficient: `original_surface_object_abi_established`
is hard-coded `false`. Even with `--execute`, it returns 78 before opening
libcuda, creating output files, or calling any CUDA API. There is no CLI,
environment or build-definition override. Do not flip this simply to try a
launch and infer whether an opaque handle happened to work.

Before activation, the main agent needs independently reviewed evidence
mapping a genuine Driver-created object to the **exact original** SUST.P
operand convention, including formatted HALF array support, and must review
source TEX binding and the complete original memory-descriptor ABI. Acceptable
next evidence could be authoritative ABI documentation or already available,
proven original/Driver operand-binding records. No device-code witness was
compiled in this CPU/host-compile-only task. Unsupported module load or object
behavior must fail with its original CUresult; never patch the ELF, replace
this kernel with PTX, reinterpret/truncate handles in host code, or fall back
to an old architecture/front-end path.
