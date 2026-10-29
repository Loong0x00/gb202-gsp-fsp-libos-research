# Main rejects the worker's slab/pipeline/synchronization ledger

Original REPORT.md is retained. Its96-byte parameter-load offsets and exact F16 MMA spelling are useful, but its ranges and stage labels are NOT accepted.

Actual own5875-op parse in ../nr-swin1h-up-main-20260912 has NO shared declaration and ZERO bar.sync instructions. The worker cited block65's six barriers as synchronization context: those are not block66 boundaries and cannot be transplanted. Own1h is a single register-private warp with movmatrix V transpose.

Actual source operands, now checked on every264MMA in all64CTAs (16896MMA), show:

- FFN expansion32→128 at0..4096, contraction128→32 at4096..8192, four interleaved hidden32 chunks. Not an8192-byte expansion or grouped10400 bank.
- Prefix64→32 at8192..10240, two K32 passes. The worker's8192..9216 upper bound omitted the second K32 slab panel;9216..10240 is NOT untouched.
- FFN gamma10256..10320, late skip gamma10336..10400:64bytes each, NOT overlapping128-byte fields.
- RawQKV10400..13472, bias13472..21664, Qscale21664..21668, gap12, final21680..22704, finalgamma22704..22768, tail16. The two4096-byte bias query halves13472/17568 are not raw/later projection banks.
- Actual slab read union22724bytes excludes exactly60gap/tail bytes. Low65536bytes and highskip131072bytes are completely consumed with actual byte-source proofs.

The source's sign-bit add then arithmetic shift is **truncation toward zero**, not generic signed round-up/ceil: +3→1,-3→-1. Do not conflate signed coordinate division with host positive dimension roundup8.

Own query halves are M0..31 and M32..63, not Q-bank versus K-bank. QK starts PCs4389/5166, PV5003/5766, final5053/5816. Worker labeled final MMA as PV. Prefix starts238/backedge244→42; own260static sites execute264dynamic MMA because prefix K0/32 repeats four sites.

Two essential arithmetic forks: FFN early seed multiplies **unquantized** learned-upsample-plus-skip half P by gamma; final early seed multiplies **unquantized FFN half F** by gamma (e.g. PC3314 r3455=r2050*r2155). Neither seed reloads/decodes an FP8 shared checkpoint. Source-first NN was built with these distinctions BEFORE any complete prediction, and first output remains unchanged.

Current Main evidence: first64x64 zero-origin NN then64originalCTAs/all131072outputbytes match; all16896actualMMA A/B/C/D, B/bias/low origins and carries, final unquantized seed fork; all64CTA normalization/scalar/transpose plus attention/scalar/private-PV/final-store proofs,65536RSQRT and8192RCP calls. Prefix/FFN complete scalar lineage and host/public/heldout acceptance still pending. No native/fullNR/independent packaging claim.

One first Main MMA checker tried packing decoded float64 through a finite-binary16-only helper. FIRST_MMA_OBSERVER.py.txt/log are preserved; only the checker was changed to use already predicted FP8 input codes. NN code and first predictions were not changed.

Host review additionally finds P88 carries unrounded positive caller highskip H/W, while P24 carries rounded output H/W. The zero-override fixture is functionally equal at64x64 but not the same raw ABI field assignment; actual positive64/64 configuration still requires its separate witness/execution record. Do not silently rewrite that distinction.
