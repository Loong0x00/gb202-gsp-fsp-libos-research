# Preserved source/diagnostic/batch corrections

## Worker handoff

The original source report is retained unchanged. Its slab ledger copied the provided upsample equations, including gamma131072, QKV131584, scale213504, final213520/gamma229904, then incorrectly insisted those gamma offsets remain ordinary locations. Actual ordinary source loads are FFN gamma98320, QKV98592, bias147744, Qscale180512, final180528 and final gamma196912. All are now independently checked from every original operand on25CTAs; no fitted displacement or serialized-F16 inference.

The report also incorrectly says block58 is the only block matching the ordinary entry and suggests shifted labels prohibit ordinary57/59/60. Source P0/XY, current host selector/aggregate bytes and complete original shifted grids establish that the reviewed entry accepts these explicit signed origins. Names do not themselves prove a live entry/route, but also do not exclude its parameterized shifted path. Block61 remains a distinct OUTVIEW entry and was not numerically accepted here.

## Main opcode alignment diagnostic

The first automatic opcode SequenceMatcher diagnostic aborted at `(upPC3310,ordinaryPC872)` because equal opcode names there had different register-operand arity. `FIRST_CORE_ALIGNMENT_FAILED.py.txt` archives that stdin script. Tool output was:
```
Traceback (most recent call last):
  File "<stdin>", line 9, in <module>
AssertionError: (3310, 872)
```
No CORE_ALIGNMENT acceptance file was emitted. Main instead resolved actual stage PCs/counters/addresses and checked real operands. NORM_TAIL_ALIGNMENT.json is an anchor map only: it records equal late opcodes and the one ambiguous register reuse, not an equivalence theorem. No original PTX or first NN arithmetic was altered.

## Observer batch timeout, not a numerical failure

`check_all.py` and FIRST_ALL_OBSERVERS.log are retained. The480-second tool limit terminated the batch after105 complete stage proof reports were saved (21CTAs); OBSERVER_PROGRESS.json lagged at20CTAs. No live check_all process remained when inspected. There was no numerical/assertion failure.

Separate `resume_observers.py` verified first NN/observer code hashes, reused105 complete reports and ran only the20 missing stage reports. RESUME_OBSERVERS.log and ALL_PROOFS.json close all125 stage reports/25CTAs/70400uniqueMMA. The first batch script/log/progress were not rewritten, and no sibling runner/main was called.

Some first arithmetic candidates retain inherited size wording in docstrings/error text; their actual constants and public model interfaces are ordinary4h. Frozen first code hashes are preserved. Accurate dimensions/ranges are documented in RESULTS.md and model.py.
