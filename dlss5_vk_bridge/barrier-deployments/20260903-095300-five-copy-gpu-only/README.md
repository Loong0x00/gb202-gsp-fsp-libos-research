# Wuthering Waves five-resource GPU-copy-only A/B

## Binary

Previous full-output-only copy service:

`ed2db2a3ed3e0f83284a904b9965407af39ff5f753760ec5bcb644f781d5425a`

Current five-resource copy service:

`466e2cac1b9e3c05a3b3f040488490a6d392077bd434546f2c239053e8c15e6c`

## Controlled change

Output-only full copy did not suppress the defect. This build reproduces the
GPU portion of successful raw capture for all five resources after Feature18:

1. signed RR pre-NR snapshot
2. Feature18+codec post-NR output
3. original engine Color
4. engine motion vectors
5. engine depth

Each resource is transitioned to `COPY_SOURCE`, fully copied to one persistent
readback-heap sink, and restored to its documented state. Expected aggregate
GPU copy footprint is 284,929,728 bytes per Feature18 frame.

There is no fence signal/completion polling, Map, row packing, worker thread,
or disk write. The sinks are reused on the same ordered queue. This separates
the complete raw-capture transition/copy workload from its CPU/fence/writer
behavior.

## Test

1. Launch normally at 6K.
2. Do not press `Super+Alt+C`.
3. Wait until the login gate enables Feature18, then test the same R animation
   twice.
4. Report whether the structured bad frame remains. Recording is optional.

A valid run must contain the build marker, five `sink[i] ready` records, and:

`post-SR five-copy sinks ready aggregate-bytes=284929728`

The first Feature18 frame allocates about 272 MiB of persistent sinks; no
multi-gigabyte raw data is generated. `restore.sh` returns to the prior
output-only-copy build while the game is stopped.

## Live result

FAIL to suppress the defect. The build marker, all five sink records, and the
exact `aggregate-bytes=284929728` confirmation are present. The user reports
that the bad frame still exists; raw capture was not armed.

The run contains 2,467 Router Evaluate records. After login gating, 947
Feature18 posts succeeded and zero failed. The game exited normally, with no
new UE4 crash or Xid. This excludes the complete five-resource barrier/copy
GPU command set as the condition that made the earlier raw window clean. The
remaining differences are raw capture's per-Present queue fence signal,
concurrent worker/Map/write path, allocation/CPU disturbance, or ordinary
run-to-run non-occurrence.
