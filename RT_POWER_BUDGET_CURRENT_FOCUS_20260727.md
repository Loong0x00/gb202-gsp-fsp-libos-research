# RTX 5090: RT workload cannot use the advertised board-power ceiling

## New live observation (2026-07-27)

- Active VBIOS board-power ceiling: 800 W.
- In a second RT-game workload using the default GPU curve, the governing
  `WORKLOAD_COMBINED_2X`-family controller permitted about **2955 MHz** but
  only about **500 W** of effective budget/power.
- Observed peak GPU temperature was 69 C and the normal fan controller held
  about 1800 RPM.

## Correct interpretation

This is not evidence that the card needed a manual 3000-RPM fan target or that
thermal protection forced the approximately-500-W result.  The owner had
expected a roughly 600--700-W effective budget under the 800-W VBIOS ceiling;
the new observation instead indicates that the workload controller itself is
the primary restriction.

`800 W` remains an outer board policy ceiling.  The primary research question
is why the runtime combined-workload budget/search selects about 500 W for RT
workloads and how that selection constrains approved frequency.  Fan recovery
is an enabling/safety subproblem for experiments, not the explanatory target.

## Evidence boundary

- The exact 500-W value should be captured together with the policy-0
  `CurrLimit`, `CurrValue`, candidate estimated values, DG0, real clock,
  voltage and board-power telemetry in the next controlled run.
- Do not call the controller "wrong" from this observation alone.  What is
  established is that its effective budget is much lower than the user had
  expected from the 800-W outer limit.
