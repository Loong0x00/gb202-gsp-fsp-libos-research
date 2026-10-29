# Block-28 origin `(-4,-4)` transparent H4 attention

## Implementation

`candidate_origin_negneg.py` adds a pure-NumPy layer-2 branch selected by the
geometry `(H, W, origin) == (4, 4, (-4, -4))` in
`split_standard_candidate_h4.py`.  It consumes the supplied packed layer-1
bytes only: it has no VM/replay import, output lookup, or input digest gate.
The branch is geometry-based, so it also describes another model using that
same H4 corner geometry; Block-24's equal output is an incidental final-E4M3
quantization result, not its derivation.

The source-derived retained 8x8 score/PV topology is:

* logical query rows `0..15` use physical bias rows
  `[36,37,38,39,44,45,46,47,52,53,54,55,60,61,62,63]`;
* every physical K **and** V position `p` aliases compact token
  `4*((p//8)%4) + p%4`;
* QK scores are placed by the eight physical fragment-column groups recorded
  in `score_fragment_columns` in the result report; together they are exactly
  physical columns `0..63`;
* all 64 mapped columns remain in ordinary `_softmax`; this path does **not**
  use H4 zero-padding denominator subtraction.

There is no head-specific operation.  The old generic H4 path happened to
miss 204 published codes on the current input (55 in head 5 and 149 in head
13); the shared physical layout fixes all heads.

## Evidence

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B verify_block28_h4_transparent.py
PYTHONDONTWRITEBYTECODE=1 python3 -B block28_attention_ref/run_h4.py
```

The verifier evaluates candidate current and independent finite heldout inputs
before importing the diagnostic VM, rejects replay/digest tokens from the new
model path, then compares both outputs with fresh four-slice VM results.  It
also re-runs every layer of Blocks 23--27 against their published corrected
outputs.  `BLOCK28_H4_TRANSPARENT_RESULT.json` records 0 byte difference for
current, heldout, and all 23--27 regression layers.  The refreshed
`CORRECTED_BLOCK28_LAYER2.bin` has SHA-256
`8f763d7c3dd21b8129b7de8bbf9e7a2cad6615c2e1284f158644fa6aee7fa32b`.
