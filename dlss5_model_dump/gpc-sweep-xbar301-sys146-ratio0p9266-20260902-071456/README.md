# DLSSNR 6K SM sweep — XBAR +301 / SYS +146 / ratio 0.92656

## Active tuple

- XBAR offset: `+301449 kHz`
- SYS offset: `+145797 kHz`
- GPC→XBAR ratio: `60723/65536 = 0.9265594482`
- GPC peak: 2992 MHz
- Memory: 15001 MHz
- Power limit: 600 W

## Contract

- Same signed DLSSNR 310.8 DLL, 6K input and current Green Context probe as the immediately previous sweep.
- 16→170 SM, five calls per point, first call discarded.
- All Evaluate/stream/context synchronization operations succeeded.
- All outputs: `028e7fa578b62928031494f1a0c399ef12d5a8a26c7e013a858eac5963116a24`.
- No new Xid or NVIDIA assertion.

## Comparison

| SM | SYS146/ratio.9266 | SYS206/ratio.9500 | Delta | Original old |
|---:|---:|---:|---:|---:|
| 16 | 166.074 ms | 164.735 ms | +0.81% | 155.170 ms |
| 32 | 84.246 ms | 84.588 ms | -0.41% | 78.382 ms |
| 48 | 57.134 ms | 57.496 ms | -0.63% | 53.575 ms |
| 64 | 43.635 ms | 44.074 ms | -1.00% | 41.551 ms |
| 80 | 36.130 ms | 36.172 ms | -0.12% | 33.794 ms |
| 96 | 30.890 ms | 30.842 ms | +0.16% | 28.856 ms |
| 112 | 27.601 ms | 27.348 ms | +0.93% | 25.576 ms |
| 128 | 25.382 ms | 25.101 ms | +1.12% | 23.639 ms |
| 144 | 23.381 ms | 22.568 ms | +3.60% | 22.069 ms |
| 160 | 21.803 ms | 22.097 ms | -1.33% | 20.686 ms |
| 170 | 21.179 ms | 21.220 ms | -0.20% | 20.129 ms |

## Fit

- Current: `time_ms = 2565.65/SM + 4.790`, R²=0.999539.
- Previous tuple: `time_ms = 2549.57/SM + 4.956`, R²=0.999720.
- Original old sweep: `time_ms = 2392.83/SM + 4.67`, R²=0.99949.

## Result

- 170 SM: 21.179 ms versus 21.220 ms, -0.20%.
- Median pointwise change versus the previous tuple: -0.12%.
- Mean change excluding the isolated 144-SM point: -0.07%.
- Lowering SYS from +206 to +146 MHz and ratio from 0.9500 to 0.92656 produced no measurable single-model throughput change.
- Both current tuples remain about 5.2–5.4% slower than the original sweep at 170 SM, mainly confounded by the current 2992 MHz versus old 3097 MHz GPC clock and the unavailable old probe binary.
- This strengthens the conclusion that the single DLSSNR instance is not materially XBAR/SYS-sensitive in this range. It does not test concurrent independent model instances.
