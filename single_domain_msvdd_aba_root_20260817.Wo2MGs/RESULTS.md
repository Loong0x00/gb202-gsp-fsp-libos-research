# Single-domain MSVDD +5 mV A-B-A result

Date: 2026-08-17  
GPU: NVIDIA GeForce RTX 5090, 170 SM, R610.57.04 exact private contract  
Load: continuous 25 s PTX L2 correctness workload, 32 MiB L2 working set

## Transaction contract

XBAR, SYS and NVD were tested sequentially. Each transaction:

1. captured a fresh complete clock-domain CONTROL preimage;
2. sampled 1.2 s A1;
3. changed only that domain's rail-1 offset from `0` to `+5000 uV`;
4. required a complete CONTROL readback equal to the submitted block;
5. sampled 1.2 s B;
6. restored the complete preimage and required byte equality;
7. sampled 1.2 s A2.

The changed zero-based field offsets were XBAR `0x90`, SYS `0x110`, and NVD
`0x150`. In each submitted block only the two nonzero bytes of the intended
four-byte little-endian field differed (`5000 = 0x1388`). The final complete
CONTROL block equals the initial block byte for byte.

## Result

All 11 samples in each A1 and A2 window reported aggregate MSVDD and voltage
PMUMON word 2 at `995000 uV`. The target-domain post-arbitration frequency
changed during B and returned during A2:

| perturbed mapping | A1 target | B target | A2 target | B - A |
|---|---:|---:|---:|---:|
| XBAR +5 mV | 2422 MHz | 2415 MHz | 2422 MHz | -7 MHz |
| SYS +5 mV | 2407 MHz | 2400 MHz | 2407 MHz | -7 MHz |
| NVD +5 mV | 2295 MHz | 2287 MHz | 2295 MHz | -8 MHz |

The other domains' STATUS targets stayed unchanged inside each corresponding
B window. This is direct runtime evidence that the three rail-1 offset fields
independently translate their own voltage/frequency mappings even though they
feed one physical MSVDD rail.

XBAR B and NVD B each contained four consecutive `1000000 uV` samples, while
SYS B did not. A separate 13 s read-only L2 control also contained four
consecutive `1000000 uV` samples among 105 rows. Therefore those short voltage
steps are normal workload/governor behavior in this run and are not evidence
that XBAR or NVD won voltage arbitration. No single +5 mV perturbation produced
a stable aggregate MSVDD increase, so this experiment does not identify the
binding voltage-request client.

## Correctness and recovery

- Live SET test: 1 passed, 0 failed.
- L2 workload: 3886 rounds, 170/170 SM, 0 errors, 412.863 GiB/s.
- Read-only control workload: 2801 rounds, 170/170 SM, 0 errors, 413.221 GiB/s.
- Three per-domain restored blocks and global original/final blocks: byte-equal.
- All receipt hashes verify.
- Post-test GPU: 32 C, about 55 W, GPC 517 MHz, memory 15001 MHz.
- No new Xid, GSP, AER, reset-required, or fallen-off-bus kernel entry.

Reproduce the numeric summary with:

```sh
python /home/user/rt_5090_project/power_governor_reverse/bug_inverse/perf_limits_61057/analyze_single_domain_msvdd_aba.py \
  /home/user/rt_5090_project/single_domain_msvdd_aba_root_20260817.Wo2MGs
```

The earlier non-root attempt is preserved separately at
`single_domain_msvdd_aba_20260817.xKg0gR/`; contract validation stopped it before
any SET because the unprivileged process could not read the live VBIOS ROM
SHA-256.
