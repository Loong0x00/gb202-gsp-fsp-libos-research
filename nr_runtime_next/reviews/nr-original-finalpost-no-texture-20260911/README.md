# Original finalpost with A=B=C=NULL — BLOCKED proposal

Read **REPORT.md** for the 14-site PTX **and original SASS** exclusion proof, exact predicate chains, numerical caveats and remaining launch blockers.

```sh
bash reviews/nr-original-finalpost-no-texture-20260911/verify_cpu.sh
```

CPU/static only. Builds but **never runs `build/blockedhost`**. Runs only Python CPU references/tests and the isolated CPU packing test. No CUDA initialization, Driver loading, GPU execution, Wine, original kernel patching or header downgrade.

* `blockedhost.cpp`: separate clone, no textures/source arrays; owned main/skip/slab/**2-byte blend** and RGBA16F output surface only. Full opaque surface value unchanged. Main approval/runtime gate stays false.
* `prove_exclusion.py`: complete TEX inventory, byte-checked original SASS, conservative predicate/CFG certificate and independent PTX proof.
* `prepare.py`, `fixture_pins.hpp`, `fixtures/`, `MANIFEST.json`: pinned scalar contract and deterministic synthetic internal features, original slab/blend, output poison.
* `reference_cpu.py`: both connected no-A CPU-reference policies, no sampler. No native parity or surface-rounding claim.
* `test_cpu.py`, `packing_cpu.cpp`: 17 Python tests, exhaustive finite-half color semantics, null/high-word/control mutants, 188 argument mutations.
* `EXTERNAL_PINS.json`, `provenance_cpu.py`, `evidence/`: external integrity, disassembly, checks and CPU predictions.
* `FILES_CHANGED.txt`, `SHA256SUMS`: exact retained-file inventory and hashes.

**Scope:** proposed ORIGINAL compiled finalpost neural arithmetic + surface output on synthetic internal features, **not actual image processing or the full model**. Runtime ELF/API0x86 acceptance, hidden constants, resource compatibility and formatted surface rounding remain open. Prior reviews and installed files are untouched.
