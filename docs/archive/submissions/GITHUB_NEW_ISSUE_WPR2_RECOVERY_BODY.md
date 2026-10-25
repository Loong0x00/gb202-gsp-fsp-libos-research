## Summary

This is a separate but related recovery problem to #1080.

On an RTX 5090 / GB202 A1, I observed that after an abnormal GSP-RM shutdown or a failed GSP initialization attempt, later stock-driver loads can stop at:

```text
unexpected WPR2 already up, cannot proceed with booting GSP
RmInitAdapter: Cannot initialize GSP firmware RM
rm_init_adapter failed
```

I am intentionally omitting security-research and trigger details from this public issue. Those details are being provided privately to NVIDIA PSIRT. This issue is limited to the driver/firmware initialization and recovery behavior.

## Environment

```text
GPU: RTX 5090 / GB202 A1
Open GPU Kernel Modules: 610.57.04 and 615.71.09
OS: Linux
```

## Observed behavior

In the later stale-state condition:

- unloading and reloading the driver did not restore GSP-RM initialization;
- FLR and secondary-bus reset were not reliably sufficient;
- in a later dirty-state sequence, the WPR2-up condition was observed again after a complete power cycle;
- the condition remained after six previously changed platform settings were written back to their reference values and read back after a power cycle;
- the failure occurs at the stock driver's early WPR2 state check, before normal GSP-RM initialization completes.

Private diagnostic testing indicated that the hardware was not necessarily unusable while this stale WPR2 state was present: the normal signed firmware bootstrap could still complete, followed by stable `nvidia-smi`, CUDA initialization, VRAM allocation, and ordinary compute/display operation. This suggests that at least some stale WPR2 states may be recoverable after validation rather than always being treated as fatal.

## Recovery gap

The public driver-facing sequence is:

1. GSP exits abnormally or initialization fails.
2. WPR2 remains active or is reconstructed on a later boot.
3. The next stock initialization sees WPR2 already active and refuses to proceed.
4. Available reset methods do not reliably return the device to a stock-driver-accepted state.
5. No documented GB202 teardown, stale-state validation, or service recovery operation is available.

## Expected behavior

After an abnormal GSP shutdown or failed initialization, one of the following should be available:

- firmware-assisted WPR2 teardown;
- validation and safe reuse of an existing WPR2 state;
- a guarded stock-driver recovery path;
- a documented service-level recovery procedure.

## Request

Could NVIDIA please:

1. clarify the intended GB202 recovery path when `kgspIsWpr2Up` is true before GSP-RM boot;
2. add a guarded stale-WPR2 validation/teardown path where safe;
3. document a supported recovery or repair procedure for already affected devices;
4. advise what logs are useful for diagnosing this condition without exposing security-sensitive reproduction details publicly?

If more information is needed, please reply in this issue with the requested non-sensitive diagnostics. Security-sensitive details can be handled through the associated private PSIRT reports.
