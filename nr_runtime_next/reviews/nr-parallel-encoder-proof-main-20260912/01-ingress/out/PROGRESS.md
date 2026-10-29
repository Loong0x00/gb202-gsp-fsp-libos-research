# Ingress worker progress

## Completed

1. Read the exact absolute packet first, then only its allowed PTX, prior report, and original0 input. Left the independent DLL copy entirely unopened. One-time bounded ingestion produced own immutable-evidence caches; packet PTX/input hashes verified. **12/24 primary read units used**, none over2,000 lines.
2. Recovered the source's actual 769-op boundary and all sixteen zero-initialized guarded loads. Parsed/counted all source statically; no instruction at/after PC769 executed.
3. Implemented `ingress_candidate.py` from pixel/channel equations, not as a checker/VM wrapper. Includes signed positive overrides, independent singleton axes, complete source guards, uint32 word arithmetic, signed wide offset, per-byte provenance, literal source-zero, missing-byte exceptions, and signed /4 coordinate handoff.
4. Implemented `prefix_checker.py` independently, with strict register initialization, typed integer/predicate operations, branches, parameter loads and explicit global-byte loads. Suffix instructions are absent from its executable tuple.
5. First full differential run: PASS on592 cases. Added explicit +4GiB signed-wide case, verified both row-major and tile-major byte views, Boolean guard proof, and raw zero/load definition provenance. Final domain: **593 cases**, **18,976 lanes**, **303,616 words**, **1,214,464 bytes**, **769 prefix PCs**, **48 branch outcomes**.
6. Original0 all64 CTAs at the declared64×64 ABI preserve/reconstruct all131,072 bytes, including190 actual0x00 and179 actual0x80 bytes. No whole-window padding substitution. Separate negative/override/singleton/overflow/tagged cases and fourteen expected missing-byte error scenarios pass.
7. Produced source counts, prefix-only instruction listing, ABI/address/guard contract, full illustrative byte provenance, Boolean guard table, per-case results, coverage, report, ledger, and preserved exploratory issues.

## Corrected issues (no new primary reads)

- A cached-source line-only exploratory counter mishandled multiline/inline PTX; discarded in favor of semicolon parsing with independent declaration subtraction.
- Initial static suffix opcode histogram truncated uppercase `.L1` modifiers; corrected regex and added exact store-opcode assertion. It did not affect the ingress executable prefix.
- No differential-test mismatch or unresolved implementation failure. Expected missing-byte exceptions are intentional passing tests. Details: `failures.json`.

## Verification commands

```sh
# One-time ingestion was already run; it now refuses re-ingestion.
PYTHONDONTWRITEBYTECODE=1 python out/prefix_checker.py
PYTHONDONTWRITEBYTECODE=1 python out/test_ingress.py
```

All reruns read generated own-out caches only. Test stdout is retained in `test_stdout.log`; machine-readable final counts are in `test_results.json`.

## Handoff / still outside scope

Main must select the explicit row-major versus four-tile byte view, independently review the source contract, and separately prove every learned-core/MMA and output claim before integration. Physical K is not asserted to be predecessor canonical C. The chosen original0 test shape is not a fresh host-launch recovery. No DLL/PE/native/GPU/Wine/network/full-NN/frozen-model/output access, deployment/gate action, outside discovery, or subagent occurred. No native or untested perfect-equality claim is made.
