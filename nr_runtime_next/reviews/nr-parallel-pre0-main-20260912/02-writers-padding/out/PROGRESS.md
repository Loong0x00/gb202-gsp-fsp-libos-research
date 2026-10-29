# Progress — complete

- Read PACKET.json first; 19 bounded authorized input-window reads, each <=2000 lines. No binary/DLL reads, network, original kernel execution, neural numbers, nested agents, or input changes.
- Independently confirmed high +216 C32 at pixel H/W, low +248 two-plane16 layout and exact physical-k→final-c permutation, positive floor normal extents versus positive ceil padding comparisons.
- Traced all 512 low-byte symbolic reductions: original unquantized final F16, exact source-lane selections, ordered pair+pair half tree then half quarter and FP8. Full provenance is in reduction_provenance.csv.
- Critical padding finding: original zeros use FOUR 16-byte planes and allocated AH/AW strides, unlike the normal TWO-plane h/w writer. Padded cases demonstrate normal-data aliases, OOB relative to hypothetical C32 capacity, and holes. Cropped and odd metadata do not repair this.
- Geometry-only suffix interpreter preserves original predicates/counters/loops/zero stores and observes barrier6028 without substituting a CPU barrier. All 478 padding PCs, 60 zero-store sites, and 11 backward edges exercised; rectangle oracle agrees on positive cases.
- Default128→64 passes static footprints with no padding. Twenty named cases and ten suffix-only thread-count fixtures pass. No arbitrary geometry or native visibility claim.
- Initial test coverage failure is preserved in audit_geometry_failed_01.py and audit_run_01.log. Adding a partial-valid geometry fixture, not changing source logic, completed coverage. Successful logs: audit_run_02.log, audit_run_03.log.
- Delivered REPORT.md and PADDING_CONTRACT.json. Host allocation/port binding, ingress equality, real GPU visibility, sampler/MMA numerics and full-NN prediction remain unproven. All files are confined to this task's out directory.
