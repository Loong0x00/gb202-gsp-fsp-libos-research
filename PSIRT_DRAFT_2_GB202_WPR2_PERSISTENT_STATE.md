# DRAFT 2 — NVIDIA PSIRT Submission

> **Internal review note — remove before submission**
>
> This report combines two related observations: an initial WPR2-up failure after COT version fuzzing, and a later cold-boot-recurrent/deep-lock state after multiple COT messages were sent while FSP was in a CC-induced boot-limbo state. It does not claim that a specific flash record is proven. References in older local notes to "record A/B" or a "flash poison record" are hypotheses, not physical evidence.
>
> Raw slot-switch chronology does not prove that Observation A occurred on the original VBIOS slot; it may have occurred on the XOC slot. Observation B is the clearest original-slot-associated transition because the original slot was explicitly verified healthy earlier that day and no later switch was recorded before the five-COT sequence. The report therefore treats the slot identity of Observation A as unknown.
>
> The MMIO values historically read from legacy PFB WPR2 offsets should not be used as the primary proof because their architectural applicability to GB202 was later questioned. The driver's own `kgspIsWpr2Up` result and behavior are stronger evidence.

## Suggested title

**GB202 cold-boot-recurrent WPR2-up state observed after compound failed-boot, boot-message robustness, and dirty-GSP sequences prevents stock GSP-RM initialization**

## Reporter

- Name: [REPORTER NAME]
- Email: [REPORTER EMAIL]
- Preferred disclosure credit: [NAME / HANDLE / NONE]

## Product information

- GPU: ASUS ROG Astral GeForce RTX 5090 OC, air-cooled retail model
- Board identification string: `ROG-ASTRAL-RTX5090-O32G-GAMING`
- GPU: NVIDIA GB202 A1
- PCI device ID: `10de:2b85`
- PCI subsystem ID: `1043:89e3`
- Driver branches involved during investigation: NVIDIA Open GPU Kernel Modules `615.71.09` and `610.57.04`
- Original VBIOS slot reported as `98.02.2E.40.E0`
- XOC VBIOS slot reported as `98.02.2E.80.50`
- Operating system: Linux

## Vulnerability class

- Persistent denial of service against the stock GSP-RM boot path
- Possible WPR2 lifecycle/state-machine inconsistency after compound failed-boot testing
- Incomplete cleanup after GSP/FSP boot failure or abnormal GSP shutdown

## Summary

After a compound investigation involving failed GSP initialization, COT robustness testing, and later abnormal GSP shutdowns, GB202 was observed in a state where the stock NVIDIA driver repeatedly reported that WPR2 was already active before a new GSP-RM boot attempt:

```text
unexpected WPR2 already up, cannot proceed with booting GSP
```

The first transition correlated with COT version fuzzing. A later experiment sent five COT requests containing unusual `gspFmcSysmemOffset` values while FSP was intentionally held in a CC-induced boot-limbo state. Immediately afterward, FSP communication and GSP boot entered a deeper failure state.

Even after the CC-related PRC knobs were later restored to their healthy values, later cold boots recreated a WPR2-up condition that caused the unmodified driver's early check to refuse GSP boot. Additional dirty GSP crash experiments occurred between the limbo-COT event and the final cold-boot-recurrent state, so the persistent state cannot be attributed solely to the five COT requests.

A one-line diagnostic driver modification that skipped only the `kgspIsWpr2Up` fail-early check allowed the otherwise standard FSP/ACR/GSP-FMC boot sequence to continue. With that diagnostic bypass, GSP-RM, `nvidia-smi`, CUDA initialization, and large VRAM allocations were stable. This indicates that the persistent WPR2-up state blocks the stock driver but does not necessarily make the protected memory window unusable for the subsequent firmware boot.

## Scope: three WPR2-related states must be separated

The investigation observed at least three distinct situations:

1. **Ordinary post-crash WPR2 stuck:** after a malformed host RPC/GSP failure, the next driver load reported WPR2 already up; a later system restart restored normal operation. This is consistent with volatile dirty shutdown state.
2. **COT-fuzz-associated WPR2-up:** first observed after the COT version sequence described below. The exact triggering version and persistence were not isolated.
3. **Cold-boot-recurrent WPR2-up:** observed later after boot-limbo COT testing and additional dirty GSP crashes. This is the condition currently worked around by the driver bypass.

This report does not assume that all three situations share one storage mechanism or one fixed WPR2 range.

## Security impact

A privileged actor able to submit COT messages directly to the FSP boot communication path may be able to leave a consumer GB202 GPU unusable with an unmodified NVIDIA driver across driver reloads and cold boots.

Observed impact:

- stock driver refuses GSP-RM initialization;
- `nvidia-smi` and CUDA are unavailable with the stock fail-early behavior;
- repeated resets do not reliably restore a clean cold-boot state;
- continued operation requires a locally modified driver that bypasses a security-state sanity check;
- no supported recovery procedure is known.

No unprivileged trigger or cross-tenant impact is claimed. The historical research required privileged direct device access.

## Observation A — first WPR2-up transition

The active VBIOS slot for this first transition was not conclusively recorded. Later raw user messages suggest the card was likely on the XOC slot before a switch back to the standard/original slot, so this observation must not be attributed exclusively to either SPI device.

### Initial conditions

- NVIDIA driver unloaded and GSP stopped.
- FSP communication was available for direct COT and PRC testing.

### Baseline request

A COT baseline was sent with:

```text
version = 2
size = 860
gspFmcSysmemOffset = 0x1000000
authentication/signature-related fields zero-filled by the test harness
```

### Size-axis tests

COT requests were then sent with the following size-field values:

```text
0
1
859
861
2048
4096
32768
65535
```

During this phase, the PRC handler remained responsive.

### Version-axis tests

COT requests were then sent with:

```text
version = 0
version = 1
version = 3
version = 0xffff
```

After this version sequence:

- PRC stopped responding;
- a subsequent stock driver load reported `unexpected WPR2 already up`;
- repeated module unload/reload did not clear the condition.

Because the four values were tested as one series without restoring full device state after each value, the exact single triggering version is unknown.

## Observation B — deep lock during a boot-limbo COT sequence

At a later point, the following historical experiment was run as one compound sequence:

1. PRC knob 8 was set to `1`.
2. PRC knob 6 was set to `1`.
3. A secondary-bus reset was performed.
4. The NVIDIA driver was loaded and allowed to reach a CC-related boot-failure/limbo state.
5. Five COT requests were sent with `version=2`, `size=860`, and the following `gspFmcSysmemOffset` values:

```text
0x0000000055c03000
0x0000000000000000
0x00000000dead0000
0x0000000100000000
0x00007fffffffffff
```

The first request produced a response decoded by the test harness as an FSP response for COT with a value reported as error `0x1db`; the semantic meaning of `0x1db` was not independently verified. Later entries showed differing response/echo shapes; stale queue data cannot be fully excluded for those entries.

Immediately after the sequence:

- clearing knob 8 failed;
- the FSP counter/register path returned `0xbadf4100`;
- FSP scratch state included `0x0a`;
- GSP boot timed out;
- secondary-bus reset did not immediately recover the prior responsive limbo state;
- a subsequent cold boot still failed.

The CC knobs were later recovered separately and verified to survive power loss in their healthy values. Additional GSP crash/injection experiments then occurred before the final cold-boot-recurrent WPR2 state was characterized. The later persistence therefore remains associated with the broader failed-boot/dirty-GSP sequence, not proven to be a direct effect of the five COT requests alone.

## Current reproducible stock-driver symptom

On cold boot, an unmodified driver follows the normal early guard:

```c
if (kgspIsWpr2Up_HAL(pGpu, pKernelGsp) && ...)
{
    NV_PRINTF(LEVEL_ERROR,
        "unexpected WPR2 already up, cannot proceed with booting GSP\n");
    ...
}
```

Observed log:

```text
NVRM: GPU0 _kgspBootGspRm: unexpected WPR2 already up, cannot proceed with booting GSP
NVRM: GPU0 RmInitAdapter: Cannot initialize GSP firmware RM
NVRM: GPU 0000:01:00.0: rm_init_adapter failed
```

## Diagnostic bypass result

For diagnosis only, the guard was changed to:

```c
if (0 && kgspIsWpr2Up_HAL(pGpu, pKernelGsp) && ...)
```

No other WPR2 teardown or clear operation was added.

After this change, the normal FSP/ACR/GSP-FMC path continued and the following succeeded:

```text
nvidia-smi device enumeration
CUDA cuInit
approximately 31.4 GiB visible VRAM
1 GiB CUDA allocation/free test
normal display/compute use
```

This bypass has also survived normal host reboots as a driver workaround. It does not clear WPR2 and is not proposed as a production fix.

## Expected behavior

If a COT request is rejected, FSP/GSP boot firmware should do at least one of the following:

1. avoid activating WPR2 before all request validation is complete;
2. tear down WPR2 on every error path;
3. provide a supported teardown/recovery command;
4. recognize a stale but safe WPR2 configuration and reuse or replace it;
5. ensure that a fundamental reset or complete power cycle restores a state accepted by the stock driver.

A malformed or rejected COT should not make future cold boots fail indefinitely.

## Actual behavior

- The compound COT/failed-boot sequences were followed by a WPR2-up state; a direct single-request cause was not established.
- The stock driver refused all subsequent GSP-RM boots at its early check.
- Cold boot recreated the same condition rather than returning to a stock-driver-accepted state.
- Skipping only the early check allowed the remaining signed firmware bootstrap to operate normally.

## Reset and recovery observations

Different failure phases showed different reset behavior:

- an ordinary post-crash WPR2-up condition was observed after a malformed host RPC/GSP failure and later cleared after restart; other ordinary cases were sometimes cleared by SBR;
- the later cold-boot-recurrent condition returned after complete power cycling;
- FLR, SBR, fundamental-SBR experiments, driver reloads, and full shutdown did not produce a durable stock-driver recovery;
- rapid repeated SBR attempts caused temporary PCIe link degradation or device disappearance and are not recommended.

These results suggest a reset-reason-dependent FSP state machine, but the report does not claim a proven root cause.

## Evidence available on request

Sanitized evidence can be provided as:

- COT baseline/size/version request logs;
- first stock-driver `unexpected WPR2 already up` log;
- the five-request boot-limbo COT sequence;
- CC-knob recovery verification;
- stock-driver cold-boot failure log;
- diagnostic-bypass boot log;
- `nvidia-smi` and CUDA verification after the bypass;
- source diff showing the single disabled guard.

Proposed attachment names:

```text
01_cot_version_sequence.txt
02_first_wpr2_up_stock_driver.txt
03_limbo_five_cot_sequence.txt
04_cc_knobs_recovered.txt
05_cold_boot_stock_failure.txt
06_bypass_diff_and_success.txt
```

## Evidence limitations

- No complete, repeatable one-request trigger has been isolated.
- The exact COT version responsible for Observation A is unknown.
- Observation B sent five messages in one boot-limbo session.
- Later GSP dirty-crash experiments are a major confounder and may have created or changed the final cold-boot-recurrent state.
- Historical reports use differing apparent WPR2 values after different phases; they must not be treated as one fixed persistent window.
- There is no before/after physical 4 MiB SPI image.
- No persistent flash object or byte has been identified.
- A flash "poison record," "record A/B," or private InfoROM state remains a hypothesis.
- Historical reads from legacy PFB WPR2 offsets are not treated as definitive GB202 range measurements.
- The diagnostic bypass proves continued operation, not that every possible WPR2 configuration is safe.

## Requested NVIDIA assistance

1. Confirm the intended GB202 WPR2 lifecycle for COT rejection and GSP-RM unload.
2. Identify the supported recovery path when `kgspIsWpr2Up` is true at driver initialization.
3. Determine whether cold boot restores WPR2 from persistent FSP/InfoROM state or reconstructs it from another source.
4. Advise whether the existing WPR2 window may be safely reused after validation instead of failing early.
5. Provide a service-level recovery mechanism for affected consumer GB202 boards.
6. Consider adding error-path teardown or a guarded recovery path to the open driver/firmware interface.

## Disclosure status

- Not publicly disclosed as a new security vulnerability.
- No public proof-of-concept has been published.
- An earlier public WPR2/SBR issue authored by the reporter describes related reset behavior but should not be treated as independent corroboration of this persistent case.
- Submitted privately to NVIDIA PSIRT first, in accordance with NVIDIA repository security policy.
