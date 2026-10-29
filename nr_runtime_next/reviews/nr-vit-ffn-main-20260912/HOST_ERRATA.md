# Main FFN host review — remove false ABI/thread-shape blockers

Main reran the worker's10 static tests, then checked the exact selected strings and instruction bytes independently in `check_host.py`. Some retained raw host evidence is useful, but three report conclusions were incorrect:

1. **Actual 1-D main records are72 bytes in BOTH host and PTX.** The80-byte PTX declarations belong to `cc_vit_ffn_expand_fp8` / `cc_vit_ffn_contract_fp8`, without `_1d`. Original init selects `cc_vit_1d_ffn_expand_fp8` and `cc_vit_1d_ffn_contract_fp8`, each with its own72-byte declaration. There is no demonstrated truncated80-byte record. Any counter/reduction proof citing the non-1D entry must not automatically be transplanted to the1-D entry.
2. **Repack record is0x18 =24 bytes, not18 decimal.** This fits two64-bit pointers and two32-bit factors. Original forward store at0x180072943 supplies0x18.
3. **Thread shape is available in initialization, despite not being supplied again in forward.** Expand setsR14=0 at0x18007376a, R9D=R14+4 at7377d, R8D=R14+0x20 at73781, and stack z=1 before creation. Contract explicitly setsR9D=4 andR8D=R9D+0x1c, stackz1. Thus both requested main CTA shapes are **(32,4,1)**. Repack creation separately requests **(256,1,1)**. These are source-backed construction requests, not a live GPU launch observation.

True constructor-derived tables remain expandBB998(+8forward72840,+38init73710), contractBB9f0(+8forward72620,+38init73610). The correctly decoded repack names are `cc_vit_1d_repack_2d_to_1d_fp8` / its non-FP8 alternative. `HOST_CORRECTIONS.json` records exact names, dimensions and sizes; the script checks the original DLL hash and relevant bytes.

The static forward grids reported by the worker remain useful: expand `(32*ceil(N/128),1,1)`, contract `(8*ceil(N/128),1,4)`, with N the two host geometry factors' product. Live pointer/vector values, actual model tensor-shape bindings, scratch initialization/lifetime, selected synchronization variant, and the complete reduction/residual semantics remain separate questions.

The corrected contracts now support a strictly specified bounded CPU expand experiment and repack restoration; they are not permission to fill unknown scratch state or claim native equivalence. Original worker files preserved; no GPU/host execution or installed/network changes.
