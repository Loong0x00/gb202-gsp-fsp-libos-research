# R610.57 voltage status-path and PMUMON receipt

Date: 2026-08-17 (Asia/Singapore)

Scope: static GSP inspection, read-only RM controls and one known-safe four-second
L2 workload. No clock, voltage, propagation, PERF-limit, MMIO, module or
configuration setter was called.

## Confirmed

- The current GSP voltage method family contains read-only command
  `0x2080b216`, size `0x658`, handler `0x017eced8`, flags `0x48`.
- Its payload is exactly a `0x18`-byte PMUMON super header plus fifty `0x20`-byte
  samples. The public `NV2080_CTRL_PMUMON_GET_SAMPLES_SUPER` header documents
  the first six dwords; setting retrieval mode at `+0x14` to `1` returned one
  latest sample.
- Each voltage sample is a `u64` nanosecond timestamp followed by six `u32`
  voltage words. A fresh paired read returned:

  ```text
  PMUMON: word0=830000 word1=1200000 word2=880000 word3=1000000
           word4=0xffffffff word5=0xffffffff uV
  rail STATUS: rail0 target=830000 rail1 target=880000 uV
  ```

  Therefore word 0 and word 2 equal the aggregate rail-0 and rail-1 targets on
  this exact build/boot. Words 1 and 3 are deliberately left unnamed; words 4
  and 5 were invalid sentinels.
- Under the four-second L2 workload, the PMUMON ring continued advancing and
  its newest captured sample reached word0=1110000 and word2=1000000 uV. The
  workload completed with `pass=1`, `622` rounds, `0` errors and `170/170` SMs.
- `VOLT_RAILS_GET_STATUS` (`0x2080b202`, handler `0x017e3458`) resolves a rail
  status object and calls its vtable `+8` serializer. Constructor
  `0x017f7c00` installs serializers `0x017efc1c` and `0x017efe64`; the base path
  uses the generic BoardObj status copier and the derived path adds one byte.
  This public status path does not read or export the voltage controller's
  active/deferred masks, ten request records, per-client deltas or winner ID.

## Boundary

The new PMUMON path improves timing and aggregate-target observation. It is not
a ten-client request dump and does not identify the binding voltage client.
The live winner remains a hidden input to a fully quantitative inverse solver.

## Files

- `latest-decoded.txt` and `rails-cross-readback.txt`: paired latest-sample and
  aggregate-rail readback.
- `b216-before.out`, `b216-load-*.out`, `b216-after.out`, `workload.log`: raw
  ring snapshots and workload receipt.
- `0x2080b2*.out/.err`: zero-prefill read-only inventory of the current voltage
  method family.
- `gsp61057_voltage_*`: saved static handler, vtable and generic copier output.
- `live-49-column-sampler.log`: four complete live rows and the ignored-test
  result for the integrated sampler.
- `gpu-after.txt` and `kernel-alerts.txt`: post-workload health readback; the
  alert file is empty.
