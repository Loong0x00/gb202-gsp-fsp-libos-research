# H512 original-literal geometry evidence (CPU/static only)

This directory validates the already frozen transparent chain in
`../nr-exact-encoder0-22-h512-main-20260914/` at the expanded geometry:

```
pre0 512² → 1H 256² → 2H 128² → 4H 64² → 8H 32²
```

It does **not** run a game, GPU, network client, deployment, or a full
thousands-CTA literal replay.

## What is executed

`run.py` imports each source family's existing `literal.py` and runs its
existing `literal.run` CPU/PTX VM against frozen transparent global buffers.
For every encoder block it selects:

- all four corners;
- one middle CTA on each of the four edges; and
- four or five interior CTAs (all four for a 4×4 grid).

For each selected CTA, every byte written by the literal is compared directly
with the same offsets of the frozen transparent global output.  The comparison
is sparse/offset-aware, so it works for non-contiguous 4×4 physical tiles and
planar low outputs.  `DS4`, `DS8`, `DS14`, and `DS22` each check both `high`
and `low` ports.

The frozen transparent outputs are candidates only.  This evidence never calls
a transparent-to-transparent comparison an original result.

## Admission-only extension

The external `validator.py` changes only process-local validator bindings:

- geometry upper caps: pre0 `512`, 1H `256`, 2H `128`, 4H `64`;
- planar ingress source-extent caps: 1H `256`, 2H `128`, 4H `64`, 8H `32`.

The original PTX text, parsed literal body, `literal.run` bytecode, source
files, weights, arithmetic callbacks, VM, reads, writes, and scheduling are
not replaced.  `SOURCE_INTEGRITY.json` records hashes before and after.

## Whole-output writer argument

`STATIC_PARTITION.json` independently enumerates the affine writer *cells* for
every CTA of every port without numerically executing those CTAs:

- high/ordinary outputs use disjoint 4×4 physical-C tiles;
- low/pre-primary outputs use disjoint planar16 `(group,y,x)` cells.

For each port it proves full byte coverage and no cross-CTA writer overlap.
Every selected original-literal patch must exactly equal that formula's cells;
interior samples also require an identical original-literal store-PC/lane/size
signature under translation.  Thus unselected CTAs are not filled from the
transparent buffer or represented as an assembled "original" output.

The numerical extension to unselected translations relies on the pre-existing
fixed-window local-program equivalence plus the unchanged PTX body and this
partition proof; it is not an assertion that every H512 CTA was replayed here.

## Preservation and outputs

- `RESULT.json` is created only once after a complete pass.
- `FIRST_RUN.log` is append-free after its first run.
- `FAILURES/FIRST_FAILURE_*.json` is never overwritten.
- The source chain's earlier B15 extent failure is retained byte-for-byte as
  `FAILURES/PREEXISTING_TRANSPARENT_B15_EXTENT_FAILURE.log`; it is explicitly
  a transparent-chain history record, not an original-literal failure.
- `TRANSPARENT_CHAIN_FIRST.json` is the source chain's preserved first output.
- `INPUT_MANIFEST.json`, `SOURCE_INTEGRITY.json`, `SAMPLE_COMPARE.json`, and
  `STATIC_PARTITION.json` are the independent receipts; `WHOLE_OUTPUT_PROOF.md`
  states the local-program + partition implication and its exact boundary.

Run from this directory with:

```sh
python3 run.py
```

The scope audit blocks process spawning, dynamic-library loading, and network
operations after all static inputs are loaded.  Local reads performed by the
untouched literal itself (for its pinned PTX or weight-range receipt) remain
allowed.
