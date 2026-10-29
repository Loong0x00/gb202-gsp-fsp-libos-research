# block70 live-TEX reconstruction boundary

## PTX / ABI facts used

Pinned source: `../nr-post1h70-h512-main-20260913/original.ptx`, SHA-256
`8833e1a55197d3e6e2acc1d2032c6ba22c9712c96a58c2a873733c59506fb91c`.

| ABI field | Reconstructed use | PTX evidence |
|---|---|---|
| `+56` | optional A object | first tail TEX (`%rd4`) at 13915; A decode at 13916–13921 |
| `+64/+72/+80` | A coordinate FMA/multiply chain | 13908–13915; mirrored at 16038–16045 |
| `+88` | optional B/history object | `%rd9` five B TEX calls at 14077–14081; `%rd10` at 16212–16216 |
| `+96` | optional C/motion object | `%rd5` motion TEX at 13985; mirrored `%rd5` at 16118 |
| `+104` | nullable raw F16 blend scalar | 13943–13958 / 16076–16091 |
| `+112..+168` | named C motion and B coordinate transforms | 13973–14076 / 16107–16211 |
| `+172/+176` | source width/height, normalized coordinates and source bounds | 13897–13907 / 16025–16037 |

The B tap geometry follows the literal instruction order, including the
half-shifted base, `[0.5, extent-0.5]` center clamp, `base-1`, `base+2`, and
cross-first B TEX sequence `(x0,y1), (x1,y0), (x1,y1), (x1,y2), (x2,y1)`.
The final array forward keeps the source-derived 139xx/160xx row-path selection
explicit; the oracle probe covers both origin `(0,0)` and host-admitted
`(-4,-4)` CTA grids.  It also compares the +104 null default, finite-zero, and
raw-half-infinity blend branches.  Blend NaN remains fail-closed rather than
being assigned an unmeasured PTX NaN/min/max behavior.

## Sampler evidence and intentional boundary

`../nr-vulkan-sampling-history-20260911/REPORT.md` states at line 5 that
A/C use Vulkan mode 2 and B uses mode 0 (normalized nearest/clamp and normalized
linear/clamp respectively); lines 58 and 161 explicitly say this does **not**
prove driver subtexel/interpolation precision, resource reads, or conversion.

Accordingly `live_tex.LiveTextures` only transmits the proved mode metadata:

* A: mode 2;
* B history: mode 0;
* C motion: mode 2.

It requires `fetch(slot, mode, u_f32_bits, v_f32_bits) -> RGBA F32-bit tuple`.
There is no NumPy image binding, no nearest/linear fallback, and no claimed
native GPU texture result.

## Approximate instructions

`f32bits.SyntheticRNApprox` is an explicit finite CPU probe policy only.  It is
passed unchanged to both the array forward and `oracle_original` so the oracle
comparison does not silently substitute a different `div.approx`,
`rcp.approx`, or `ex2.approx` behavior.  It is not a native APPROX claim.
