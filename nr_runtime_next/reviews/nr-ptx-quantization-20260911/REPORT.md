# Original NR PTX FP8 conversion and fragment primitives (CPU/static only)

## Result / reusable boundary

Implemented **integer-bit, exact supported-domain conversions**, not approximate float casts:

- `ptx_fp8.py`: scalar and packed forms of the two original E4M3 CVTs, signed zero, gradual E4M3 subnormals, RN-even and finite saturation; byte/half pack helpers; exact finite integer decoders.
- `mma_fragments.py`: full-warp A/B/C/D raw-register ↔ matrix maps for **`mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`**, plus coordinate inverses and strict validation. These functions preserve all raw patterns, including NaNs; numerical conversion rejects NaNs.
- **14 CPU tests pass**. Exhaustive finite-half conversion, all FP8 codes and all packed FP8 pairs; independent rational/standard-library reference and NVIDIA CUDA-header **CPU host fallback**; exhaustive fragment coverage and independent piecewise-ISA comparison; original CVT→pack→A integration.

No GPU, PyTorch, CUDA driver/runtime calls, nvcc, PTX assembly, source version downgrade, or native accumulation-parity assertion. All writes are confined to this directory. Prior tile/head/prehead directories are read-only. The code has no third-party dependency; the retained host-oracle data allow tests without compiling CUDA headers.

## Actual variants before implementation

Read `../nr-static-tile-20260911/REPORT.md`, `../nr-ptx-finalpost-20260911/REPORT.md`, the original finalpost text and all 15 original bundle PTX modules. Recomputed the following counts directly and cross-checked the existing bundle histogram:

| Exact opcode | Finalpost | All 15 modules |
|---|---:|---:|
| `cvt.rn.satfinite.e4m3x2.f16x2` | 388 | 24,736 |
| `cvt.rn.f16x2.e4m3x2` | 40 | 4,744 |
| `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` | 256 | 19,728 |
| `mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16` | 16 | 35,072 |

No other E4M3/E5M2 FP8 CVT or MMA variant occurs in this bundle. No `.relu`, `.pzo`, `.scaled`, `.rs`, `.rz`, BF16-source or FP32-source FP8 conversion is being silently substituted. The FP16 K16 head opcode is listed for distinction, **not implemented here**. Other FP16/FP32 arithmetic in the bundle remains out of scope.

Every module still declares `.version 9.4`, `.target sm_120`. Original finalpost is 265,352 bytes, SHA256 **`b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`**. `EVIDENCE.json` pins all 15 module hashes and exact opcode counts. Tests verify all **19,728** original FP8 MMA operand vector sizes are D=2, A=4, B=2, C=2 registers. `finalpost-sites.json` retains exact multiline operands and original line numbers for every finalpost CVT/MMA in scope.

Installed `ptxas --version` reports CUDA 13.3.73; the earlier read-only `ptxas-reassembly.log` explicitly says **“Unsupported .version 9.4; current version is '9.3'”**. That log is retained in the evidence. This task only queried the assembler version; **it did not assemble anything or change a source directive**. The public ISA fetched here actually identifies itself as **PTX ISA 9.4**, matching the original source language version.

## Documented conversion contract

Public source: <https://docs.nvidia.com/cuda/parallel-thread-execution/index.html>.
The complete fetched HTML, extracted text, SHA256 and bounded excerpts are retained locally:

- **§5.2.3** (`isa-formats.txt`): E4M3 has four exponent bits, three fraction bits; **no infinities**; only NaN codes `0x7f`, `0xff`.
- **§9.7.10.24** (`isa-cvt.txt`): packed ordering, RN-even, default subnormal support and `.satfinite` rules. `.satfinite` preserves the input sign when clamping magnitudes above MAX_NORM; NaN inputs produce NaN, not zero.
- **§9.7.10.4** (`isa-mov.txt`): `mov.b32 d,{a.x,a.y}` is `a.x | (a.y << 16)` for two 16-bit elements.
- Installed `/opt/cuda/include/cuda_fp8.hpp`, hash and numbered bounded excerpts retained: independently specifies E4M3 exponent bias **7**, minimum normal **2^-6**, minimum subnormal **2^-9**, maximum normal code **0x7e = 448**, and host conversion/rounding implementations. This is the NVIDIA E4M3 encoding, **not E4M3FNUZ**.

### Precisely supported and unsupported inputs

| Input | Numerical API result |
|---|---|
| All **63,488 finite binary16 encodings** | Exact RN-even E4M3 conversion with sign-preserving saturation |
| Half `+inf` / `-inf` | **`0x7e` / `0xfe`**, because ISA clamps magnitudes above MAX_NORM |
| All **254 finite E4M3 encodings** | Exact half widening; `.rn` loses no precision |
| Half ±0 / FP8 ±0 | Zero sign preserved in bit-pattern conversion |
| All **2,046 half NaNs**; FP8 `0x7f`, `0xff` | **`UnsupportedNaN`**, including if only one packed lane is NaN |

The ISA establishes NaN **class**, but this review did not establish a unique output NaN sign/payload encoding. The installed host fallback has concrete NaN choices; those are **not promoted to a PTX/native bit-exact promise**. No canonical-NaN or sign policy is invented. `half_class` / `e4m3_class` expose classification if a caller needs to stop before numerical conversion. Integer value decoders necessarily lose zero sign; bit conversions retain it. Width/type validation rejects negative, oversized and non-integer register arguments instead of silently masking them.

### Integer derivation

For half exponent `E`, fraction `M`, the unsigned finite magnitude in units **2^-24** is:

```
N = M                         if E == 0
N = (1024 + M) << (E - 1)     otherwise
```

E4M3 has four significant bits. Its minimum grid spacing is **2^-9 = 2^15 half units**. Choose `shift = max(15, bit_length(N)-4)`, divide by `2^shift`, and increment the quotient precisely when remainder exceeds half a step, or equals half a step and the quotient is odd. This is RN-even using integers only. On the subnormal grid quotient <8 is the FP8 code; otherwise the code is `((shift-14)<<3) + quotient - 8`. A quotient of 16 naturally carries into the next exponent. Clamp the magnitude code to `0x7e`, then restore sign. This is equivalent to choosing the closest representable finite value with even-code ties, including values above 448.

FP8 widening is exact: for exponent `e>0`, half exponent is `e+8`, half fraction is `m<<7`. For FP8 subnormals, normalize the nonzero 3-bit fraction; they all become **normal half numbers**, not half subnormals. The smallest is `0x01 → 0x1800 = 2^-9`.

### Packed ordering / actual source anchor

```
CVT half→FP8:  a[15:0]  → d[7:0],   a[31:16] → d[15:8]
CVT FP8→half:  a[7:0]   → d[15:0],  a[15:8]  → d[31:16]
```

This differs from the **two-source FP32** syntax (first source occupies the high destination element), which does not occur here and is not implemented.

Original finalpost lines **2921–2947** produce the first A fragment:

| A word | Destination | Half-pair CVT inputs, low pair then high pair |
|---:|---|---|
| 0 | `%r1044` | `%r944`, `%r950` |
| 1 | `%r1045` | `%r947`, `%r953` |
| 2 | `%r1046` | `%r956`, `%r962` |
| 3 | `%r1047` | `%r959`, `%r965` |

For example `cvt ... %rs53,%r944; cvt ... %rs54,%r950; mov.b32 %r1044,{%rs53,%rs54};`. First FP8 MMA at **line 3033** consumes these four words, B=`{%r1042,%r1043}`, C=`{%r5420,%r5420}`, D=`{%r1072,%r1084}`. The test parses this actual chain and checks converted values at all 512 A matrix positions against the independent rational quantizer and piecewise ISA mapping.

## m16n8k32 byte-to-matrix rules

Documented by **§9.7.16.5.10**, figures **91, 93, 94, 95**; retained in `isa-m16n8k32.txt`. Let lane `l=0..31`, `g=l>>2`, `t=l&3`, and `j` be **register index in the PTX operand vector**, not a register-number ordering or memory stride.

| Operand | Word / element | Matrix row | Matrix column |
|---|---|---|---|
| A, 16×32 | j=0..3, byte b=0..3 | `g + 8*(j&1)` | `4*t + b + 16*(j>>1)` |
| B, 32×8 | j=0..1, byte b=0..3 | `4*t + b + 16*j` | `g` |
| C/D, 16×8 | j=0..1, half h=0..1 | `g + 8*j` | `2*t + h` |

Element zero is the **least significant byte/half**. Byte order in a little-endian u32 load is low to high. B is indexed **B[k][n]**, not transposed into B[n][k] by the `.col` spelling. All A **512**, B **256**, C **128** and D **128** slots form bijections; every inverse is checked. No extrapolation from the earlier SASS output selector is used to establish these maps.

These maps only unpack register operands. They do **not** establish upstream tensor channels, weight-slab address permutation, graph routing, or complete prehead computation. No MMA arithmetic API is supplied: PTX explicitly leaves accumulation order, rounding and subnormal handling unspecified (`isa-mma.txt`), so conversion exactness must not be mistaken for native MMA bit parity.

## Minimal use

Place this directory on `sys.path`, then:

```python
from ptx_fp8 import (cvt_rn_satfinite_e4m3x2_f16x2,
                    cvt_rn_f16x2_e4m3x2,
                    convert_half_words_to_fp8_word)
from mma_fragments import fragment_to_matrix, matrix_to_fragment

assert cvt_rn_satfinite_e4m3x2_f16x2(0xc0003c00) == 0xc038  # low +1, high -2
assert cvt_rn_f16x2_e4m3x2(0xc038) == 0xc0003c00
word = convert_half_words_to_fp8_word(0xc0003c00, 0x5f001800)
assert word == 0x7e01c038  # bytes +1, -2, 2^-9, +448
A_registers = [[word, 0, 0, 0] for _ in range(32)]
A_codes = fragment_to_matrix('A', A_registers)  # [16][32] raw FP8 codes
assert matrix_to_fragment('A', A_codes) == A_registers
```

## Verification and reproduction

From this directory (all output/temporary paths stay here):

```sh
# Optional independent oracle regeneration: ordinary CPU C++, never nvcc.
TMPDIR="$PWD" g++ -std=c++17 -O2 -I/opt/cuda/include cuda_host_oracle.cpp \
  -o cuda_host_oracle > oracle-build.log 2>&1
./cuda_host_oracle > cuda-host-oracle.bin
ldd ./cuda_host_oracle > oracle-linkage.txt
python -B collect_evidence.py > collection.log 2>&1
python -B test_primitives.py > verification.txt 2>&1
sha256sum -c SHA256SUMS
```

`cuda_host_oracle.cpp` explicitly rejects CUDA compilation, uses only the NVIDIA headers' **host fallback**, and links no CUDA library (see `oracle-linkage.txt`). The production Python converter uses integer bit math only. Independent tests additionally use exact rational values and Python's standard binary16 pack/unpack; the header's widening to host float/double is independent reference work, **not** a production floating-point approximation.

Coverage: all finite half patterns versus two independent references; both infinities; every half NaN rejected; all 256 FP8 classifications/conversions; all **126 adjacent finite-positive FP8 midpoints** and neighboring half encodings with both signs; all **65,536 FP8 packed pairs**, with NaN pairs rejected; every supported half encoding in both packed positions with asymmetric partner; raw byte/half order; every fragment slot/inverse and every slot isolated as a basis input; random raw words including NaNs; malformed widths/shapes; pinned original hashes/counts and actual CVT/pack/MMA operands.

These are exhaustive mathematical/source/reference checks, **not native device validation**, and do not complete whole-NR numerical restoration. They supply reusable exact conversion and register-layout primitives for that work without hiding unsupported NaN bits or native MMA precision gaps.
