### Additional GB202 initialization/recovery data point (sanitized)

I have now observed a second recovery failure mode on an RTX 5090/GB202 that appears relevant to this issue, although the initiating workload was different.

After an abnormal GSP-RM shutdown or a failed GSP initialization attempt, later stock-driver loads can stop at:

```text
unexpected WPR2 already up, cannot proceed with booting GSP
RmInitAdapter: Cannot initialize GSP firmware RM
rm_init_adapter failed
```

In the later state I observed:

- unloading and reloading the driver did not recover the GPU;
- FLR and secondary-bus reset were not reliably sufficient;
- in a later dirty-state sequence, the WPR2-up condition was observed again after a complete power cycle;
- the behavior did not disappear after six previously changed platform settings were written back to their reference values and read back after a power cycle.

A useful diagnostic result is that the GPU was not necessarily unusable once the early `kgspIsWpr2Up` refusal was reached. Private diagnostic testing showed that the normal signed firmware bootstrap could still complete and that `nvidia-smi`, CUDA initialization, VRAM allocation, and ordinary compute/display operation were stable. This suggests that at least some stale WPR2 states could potentially be validated and recovered or reused instead of unconditionally failing initialization.

I am not posting a reproducer or security-research details here. The public driver-facing issue is the recovery gap:

1. an abnormal GSP exit can leave WPR2 active;
2. the next stock initialization refuses to proceed;
3. the available reset paths do not reliably restore a clean state;
4. there is no documented teardown/recovery operation for GB202.

Could NVIDIA clarify the intended GB202 recovery path when `kgspIsWpr2Up` is true before GSP-RM boot? A guarded stale-state validation/teardown path, or a firmware-assisted recovery operation, would prevent the device from becoming unavailable after a dirty GSP shutdown.

Environment for this observation:

```text
GPU: RTX 5090 / GB202 A1
Driver branches: 610.57.04 and 615.71.09 open kernel modules
OS: Linux
```

Any security-sensitive details are being provided privately to NVIDIA rather than through GitHub.
