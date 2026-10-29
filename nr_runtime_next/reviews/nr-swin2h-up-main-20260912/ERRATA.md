# Source and Main code-generation corrections

## Source worker report (preserved)

- The report's opening MMA description `...e4m3.e4m3.f32` is wrong. All276 static MMA instruction sites, including the prefix, are exactly `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`. Main executes864 dynamic MMA perCTA, with F16 accumulators and original K32 rounding. No F32-accumulator substitution was made.
- The4096-byte `.shared .align16 .b8 name[4096]` declaration is fixed/static shared storage, not an extern/dynamic shared declaration.
- P0/P24 are the task's shorthand for ABI offsets0/24, not invented graph port names. The source can establish those offsets: +0 loads rd11 then cvta→rd1; +24 loads rd3. Graph-to-I0/I1 binding needed additional host proof and is now established by62current-byte witnesses. Block8's actual activation is still not restored; P24 remains a labelled fixture.
- The cautious local-dependence result was not treated as a nearest/axis proof. Main's actual MMA-neuron/shuffle/add operand tags independently prove unquantized nearest2x BEFORE per-high-pixel scaled skip addition; all prefix masks and stores remain. Source report unchanged.

## Main preflight correction before predictions/execution

The first mechanical code-generation pass accidentally applied the output-N128→64 replacement to the already-updated prefix K128 expression, producing A_MAP(16,64), B_MAP(64,64), while the source loop required4K32=128. No numerical prediction or original-grid run had occurred.

FIRST_PREFIX_CODEGEN.py.txt preserves that first erroneous tensor file; SOURCE_TENSOR_FIELDS.json retains its first hash. FIRST_SOURCE_PREFLIGHT.py.txt/log preserve the failed shape assertion. Main corrected only the K axis to128 from the actual source loop/operand coverage. The first complete NN prediction was then frozen; it and all active prediction-code hashes have remained unchanged through every original/scalar/heldout comparison. This was a source-preflight model-code correction, not an observer repair or a fit to output bytes.

## 2h execution is not resized4h scheduling

The actual2h FFN mix and raw QKV are TWO UNROLLED K32 groups, not the4h runtime loops. Main observes each source group and explicitly checks the second group's C producer from the first. Final projection likewise has two unrolled K32 groups in each query-half phase. Source-derived bases/gaps, byte axes, scalar constants and all16CTAs are independently checked.

Some frozen arithmetic-candidate docstrings/error messages retain inherited4h/8h wording. Accurate2h semantics and public interfaces are in RESULTS.md/model.py. No inherited wording is used as proof. No later numerical model repair occurred; original7064-op PTX is unchanged.
