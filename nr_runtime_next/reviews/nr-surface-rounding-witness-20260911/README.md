# Independent formatted-SUST rounding witness — CPU prepared, NOT run

**Main approval required. No GPU, Wine, Driver loading, installed changes, or original PTX compilation was performed by this worker. No neural parity claim.** All deliverables/writes are within this directory.

## CPU verification

From the project root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 reviews/nr-surface-rounding-witness-20260911/verify_cpu.py
```

This regenerates deterministic fixtures, cross-compiles **own** CUDA 13.3.73 SM120 code, builds the **blocked** C++ Driver host, checks CUBIN/SASS bytes and dataflow against the prior object-ABI witnesses/original ELF, runs `blocked-host --cpu-info`, and executes eight CPU tests. It NEVER invokes `--execute`, even with the gate closed. Temp files are under `tmp/`. Fresh evidence/commands are retained. Rebuilding changes build/evidence hashes; `SHA256SUMS` pins this delivered snapshot, not arbitrary subsequent rebuild logs.

- `REPORT.md`: scope, exact conversion/ABI proof, coverage, remaining boundaries.
- `RESULT.json`, `MANIFEST.json`, `fixture_pins.hpp`: artifact/fixture hashes and bounded geometry.
- `evidence/static-proof.json`, `evidence/witness-sass.txt`: byte-backed opcode/dataflow proof.
- `evidence/cpu-tests.stderr`: eight passing tests.
- `FILES_CHANGED.txt`: every exact created file path, including build/evidence artifacts.

## Future Main-only experiment (NOT executed here)

1. Review this snapshot and verify its pins before any rebuild:
   `cd reviews/nr-surface-rounding-witness-20260911 && sha256sum -c SHA256SUMS`.
2. Record Main approval with selected device ordinal, domain(s), code/kernel/fixture pins and bounded resource/launch scope. `positive` and `extended` are separate invocations; approve exploratory NaN/extreme coverage explicitly. No existing approval from an original-kernel test is inherited.
3. Only after approval, Main may compile an enabled host. From this directory:

   ```sh
   TMPDIR="$PWD/tmp" g++ -std=c++20 -O2 -Wall -Wextra -Werror \
     -DMAIN_APPROVED_SURFACE_WITNESS=1 -I/opt/cuda/include \
     host.cpp -ldl -lcrypto -o build/main-approved-host
   sha256sum build/main-approved-host
   ```

   This macro is intentionally absent from the delivered blocked binary. The CLI cannot enable that binary. Approval is a Main review/rebuild procedure, not cryptographic authentication of who launches a process.
4. **Main only**, with its approved ordinal and unique run name:

   ```text
   build/main-approved-host --execute --device N --domain positive --run NAME
   build/main-approved-host --execute --device N --domain extended --run OTHER_NAME
   ```

   Each invocation creates one owned context, loads only the pinned own ELF, allocates one read-only input buffer and one guarded RGBA16F array, creates one whole surface object, launches once (128 threads/CTA), synchronizes, reads raw output/input, validates guard/input integrity, and drains/cleans up. Existing run directories are refused. No textures or original code/data are loaded. Preserve the enabled-host hash and approval next to the run evidence.
5. Require exit 0, `host-result.txt` exit/first-error zero, successful post-launch sync and full cleanup in `cuda-status.tsv`, and unchanged input before interpreting output. Then **CPU-only**:

   ```sh
   python3 fixture_cpu.py --domain positive --analyze run-NAME/output.rgba16f
   python3 fixture_cpu.py --domain extended --analyze run-OTHER_NAME/output.rgba16f
   ```

   Analyzer expects the COMPLETE guarded array, not a cropped tile. It reports both hypotheses independently, signed/range breakdowns, raw unscored NaNs, same-input/different-output observations and guard failures. Exit 0 means array shape/guards are valid, **not** that either rounding hypothesis matched. Unknown reference entries in `.rne/.rtz.rgba16f` have zero storage placeholders with mandatory zero `.known-mask` bytes; never compare those placeholders as predictions.

A matching hypothesis on these vectors measures only this formatted store on the tested device/resource. It does not explain the remaining original-kernel pixel, establish pre-half neural math, or authorize a renderer change.
