# Optional Guardian publication protocol v1

The current external Guardian has no health-lease API. This directory therefore
defines the consumer and wire structs only; it does not change Guardian and does
not synthesize `GuardianReady` from `StarRail.exe`, a PID file, or the legacy
phase marker.

## Challenge/response files

The NVUnity worker atomically writes:

```text
HSR/.dlss5-linux/hsr-guardian-challenge-v1.bin
```

`GuardianChallengeV1` is exactly 80 bytes and includes the Windows game PID, two
system-RNG nonce words, creation Unix milliseconds, zero reserved fields, and a
checksum. A reviewed Guardian integration may atomically replace:

```text
HSR/.dlss5-linux/hsr-guardian-lease-v1.bin
```

`GuardianLeaseV1` is exactly 112 bytes. It must echo the PID and both nonce
words, identify a nonzero publisher instance, carry nonzero semantic and
heartbeat generations, use a validity interval no greater than 2000 ms, and
publish current Unix milliseconds. All reserved bytes are zero. `seal()` uses
32-bit FNV-1a through the bytes before `checksum`; the checksum detects torn
blocks but is not presented as cryptographic publisher authentication. The
unpredictable per-process challenge and strict path ownership provide freshness
for the trusted external publisher.

The lease explicitly carries:

- Guardian state: unknown / armed healthy / tripped;
- signed game-path integrity: unknown / intact / failed;
- externally reviewed anti-cheat policy: unknown / permitted / denied;
- native build attestation (binary 0/1).

Unknown, missing, stale, checksum-bad, future-dated, challenge-mismatched,
non-monotonic, or malformed publications close the gate. `generation` changes
only when Guardian/integrity/policy/build semantics change;
`guardian_heartbeat_generation` advances with fresh health samples. A new
publisher instance is allowed only because it still must answer the current
random challenge.

## Phase evidence remains independent

The router tails `%USERPROFILE%\AppData\LocalLow\Cognosphere\Star Rail\Player.log`
itself. At startup it records the current EOF and reads only later bytes. It
uses `honkai_star_rail/phase_gate.*`: loading/restart events close immediately,
`_OnLoadingFinish` settles for three seconds, and replacement, truncation,
missing/read failure, or overlong unparsable data closes. This phase watcher
cannot make Guardian healthy.

The final generation is local and strictly increasing. It changes before every
semantic phase, Guardian, integrity, policy, late-route, publisher, or native
build transition. Heartbeats alone do not churn the native generation. That
combined value is sent in both SetGate and RawFrame.

## Required main-owner work

A Guardian publisher must be reviewed together with the real arm-before-launch,
I2C sample, kill-on-trip, and monitor-failure paths. It should publish only after
real hardware monitoring is armed, refresh after each valid sample, publish a
semantic generation before state changes, and remove/expire the lease on every
exit. Adding that publisher is outside this scoped contribution; with today's
Guardian the adapter remains closed by design.
