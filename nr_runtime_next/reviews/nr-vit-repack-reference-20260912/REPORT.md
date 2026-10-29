# Block 31 pre-expand `cc_vit_1d_repack_2d_to_1d_fp8` — CPU byte reference

## Scope and result

This directory restores only the statically selected **block 31 pre-expand
sublaunch** named `cc_vit_1d_repack_2d_to_1d_fp8`.  The public
`repack_2d_to_1d_fp8_reference.py` implements its literal `ld.global.b32` /
`st.global.b32` permutation on CPU.  It does not decode or re-encode FP8:
every active four-byte word is copied unchanged and each padded output word is
literal zero.

The pinned regular source file is
`reviews/nr-ptx-bundle-20260911/modules/module-05-dll-00dd4bc0.ptx`, SHA-256
`641ca106cd3e211587f873de41ba4350608413687b1bb99c33fa7529f82b510c`.  Its
header remains `.version 9.4`; this review only reads it.  The entry declares:

```ptx
.visible .entry cc_vit_1d_repack_2d_to_1d_fp8(
.param .align 8 .b8 cc_vit_1d_repack_2d_to_1d_fp8_param_0[24]
)
```

`assert_literal_provenance()` pins that record, both parameter loads, the
thread-index instructions, and the actual b32 load/store.  `SOURCE_PINS.json`
records all static inputs.  No GPU, Wine, PE/host execution, installed-file
write, or sibling-review write is part of this result.

## Exact ABI, launch, and handoff

The record is **24 bytes / `0x18`**, not 18 decimal:

| record bytes | exact static role |
|---:|---|
| `+0x00` | source pointer `I[0]` |
| `+0x08` | destination pointer `O[1]` |
| `+0x10` | `arg5` (`i32`) |
| `+0x14` | `arg6` (`i32`) |

`RepackRecord24` serializes/deserializes exactly `<QQii`; its pointer values
are deliberately symbolic in the CPU reference.  The static FP8 host branch
creates CTA `(256,1,1)`, uses `N = arg5 * arg6`, and launches grid
`(ceil(N/32),1,1)`.  These are launch facts, not semantic H/W or tensor-axis
names.

The retained host-forward text has the literal `0x18` record-size store.  Its
first local record is built from `I[0]`, `O[1]`, `arg5`, and `arg6`; after the
sublaunch the static path carries that `O[1]` value to the main expand record
at `P+0x00`.  Thus the narrow, source-established handoff is:

```text
repack I[0] --[this entry]--> O[1] --[static expand-forward handoff]--> main expand P+0x00
```

This is a pointer handoff only.  It does not establish live predicate truth,
buffer allocation/lifetime, shapes, a producer identity for `I[0]`, or a
whole-graph binding.

### Independent erratum for older wording

Older host-report prose that called this record “18-byte”, or mixed it with an
“80-byte” record, is deliberately left unchanged in its own historical
review.  This independent correction relies on
`nr-vit-ffn-main-20260912/HOST_CORRECTIONS.json` (whose `repack_host_bytes` is
24 and whose `not_18_decimal` is true), the raw static forward excerpt, and
the literal entry above.  The **Main 1-D** expand/contract PTX declarations
are 72 bytes and the host main records are 72 bytes.  The 80-byte declaration
is a different non-1-D entry (for example `cc_vit_ffn_expand`); it is not the
1-D main record and not this 24-byte repack record.

## Physical byte map, including edges

All quantities below are **b32 words** (four raw bytes), not channels.  For a
valid non-negative signed-i32 pair `(arg5,arg6)` with signed-i32 product `N`
and non-overflowing signed-b32 `ceil(N/32)*8192` work bound, the CPU reference
follows each source PC region.  Overflowing launch geometry is explicitly a
negative contract rather than a guessed wraparound launch:

* `$L__BB35_2`: `r72 = ctaid.x*256 + tid.x`; the upper work bound is
  `ceil(N/32)*8192` words.
* `$L__BB35_4`: `r11 = r72//256`, `r9 = r72%256`; later loop trips add
  `grid.x*256` to `r72` exactly as PTX does.
* `$L__BB35_6`: when `r11 >= N`, `%r73` remains zero and is stored.  Otherwise
  it loads one raw word by the active source map below and stores it through
the destination map below.

For active `r11`, let `row,column = divmod(r11,arg6)`, `q=r9`,
`TC=ceil(arg6/4)`, and `t=4*(row%4)+(column%4)`.  The source word index is:

```text
tile_coord(x,d) = 0 if (d & -4) == 4 else x//4
tile  = tile_coord(row,arg5)*TC + tile_coord(column,arg6)
inner = (q//8)*128 + ((q%8)//4)*2 + (t//8) + (t%8)*16 + (q%4)*4
source_word = tile*4096 + inner
```

This includes both literal `selp` special cases: a factor in `4..7` forces
that tile coordinate to zero while `TC` remains `ceil(arg6/4)`.  It is a
source-address fact under such arguments, not evidence that a live buffer was
duplicated or that those arguments occurred.  Tests prove that all 16×256
positions of a complete 4×4 tile are a permutation of `[0,4096)` and exercise
the special path separately.  The source establishes a 4×4 tile address basis
of `4096*4` bytes and a literal tile-base/stride address span; it has no
allocation-size parameter, so this review does **not** promote that span to a
host-buffer-capacity proof.  `minimum_source_read_bytes` is separately the
exact largest active read plus four bytes.

For every work word, including padded ones, with `r11=r72//256`, `q=r72%256`:

```text
row16 = r11 % 16
destination_word = (r72//4096)*4096 + (q//8)*128 + (row16//8) \
                 + ((q%8)//4)*2 + 4*(((row16%8)*16 + 4*(q%4))//4)
```

The host grid makes `grid.x*8192*4` destination bytes all written.  The
reference exposes `LaneAccess` and `lane_accesses()` so callers can inspect
CTA, lane, loop iteration, `r72`, `r11`, `r9`, source word (or padding), and
destination word rather than accepting a bulk copy/identity shortcut.

No “1024 channels” conclusion is drawn from F16 serialization or a nominal
class name.  Likewise, previous 2-D split16 observations, the FFN
constructor’s `1024 -> 4096` checks, and the main launch’s potentially
different `N` factors do not prove incompatibility, duplication, padding,
or token halving.  They are not used by this permutation.  A graph-shape bind
remains conditional on runtime buffer geometry and launch arguments not
available in CPU/static evidence.

## Tests and boundary

Run only the tagged CPU/static suite:

```sh
python -B reviews/nr-vit-repack-reference-20260912/test_reference.py
```

Tests cover source pin/header/entry checks; the 24-byte ABI and host erratum;
4×4 physical source and destination permutations; raw non-numeric b32 byte
preservation; padded zero stores; non-divisible edge geometry and each lane’s
32 loop trips; and short-buffer, invalid-coordinate, negative, and overflow
contracts.  They do not run an original binary or claim GPU/NR/full-model
numerical equivalence.
