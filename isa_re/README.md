# sm_120 cache-control and special-register oracle corpus

This directory is the reproducible companion to
[`SM120_CACHE_AND_REGISTER_ISA.md`](../SM120_CACHE_AND_REGISTER_ISA.md).

## Safety boundary

- Every executable cubin is produced by CUDA 13.3 `ptxas` from legal PTX.
- The selector/field enumeration scripts patch temporary cubin **copies only for
  offline `nvdisasm` decoding**. Temporary files are deleted and are never
  passed to CUDA, OptiX, a driver API, or a GPU.
- Before each assembly, the runner removes the previous same-name cubin and
  publishes a new cubin only after the current `ptxas` succeeds. Thus
  `run_all.sh --gpu` can load only current-run, untouched ptxas outputs. The
  GPU phase reads public special registers and returns `createpolicy`
  descriptors; it does not execute `discard`, write MMIO, alter firmware, or
  inject opcodes.

## Reproduce

Static compiler/disassembler corpus:

```sh
./isa_re/run_all.sh
```

Add the legal read-only GPU observations:

```sh
./isa_re/run_all.sh --gpu
```

Requirements used here:

```text
CUDA / ptxas / nvdisasm 13.3.73
target sm_120
GPU phase: RTX 5090, driver 610.43.03, libcuda
```

Generated source modules live under `generated/`; cubins and full disassembly
go under ignored `build/`; compact checked results go under `results/`.
Generators remove obsolete PTX modules, build runners remove prior assembly
artifacts, and the final completeness gate checks the pinned probe counts,
status distributions, decoder-table shapes, and validation coverage.
Static result tables are deterministic for the pinned compiler/disassembler.
GPU rows containing allocation addresses, clocks, timers, and counters naturally
vary between runs; reproducibility there means the same table structure and
passing descriptor checks, not byte-identical raw values.

A run without `--gpu` deliberately does not launch a GPU and therefore does not
refresh `policy_values.tsv`, `policy_descriptor_validation.tsv`, or
`public_sr_values.tsv`; if old copies exist, the final console message calls
that out explicitly.

## Main outputs

- `results/cache_probe_summary.tsv`: legal PTX to SASS/hex mapping.
- `results/cache_field_diffs.tsv`: matched 128-bit XORs with changed bit indices.
- `results/{cctl,cctll}_*_decoder.tsv`: offline decoder names for suboperations.
- `results/sr_index_catalog.{tsv,md}`: all 256 SR selectors with confidence.
- `results/s2r_destination_decoder.tsv`: offline confirmation of the complete
  8-bit destination-register field, including `0xff -> RZ`.
- `results/public_sr_values.tsv`: untouched legal probes run on RTX 5090.
- `results/policy_descriptor_validation.tsv`: recovered descriptor model versus
  58 GPU-returned values.
- `results/operand_field_validation.tsv`: cross-corpus register-field checks.

The `verified`, `inferred-name-only`, and `unknown` distinctions are deliberate:
an `nvdisasm` label is not treated as proof of runtime semantics.
