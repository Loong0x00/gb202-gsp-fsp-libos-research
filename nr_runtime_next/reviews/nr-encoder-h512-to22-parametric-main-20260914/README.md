# H512 → encoder block22 low-H16 contract

这是一个**参数化、透明的形状/字节/host-ABI 路线**，不是把小夹具的数值结果冒充为 H512 数值执行。

## 已核查的完整尺度路线

| boundary | H×W / C | FP8 physical bytes |
|---|---:|---:|
| pre0 skip | 512×512 / 32 | 8,388,608 |
| pre0 primary, blocks 1–3, DS4 high | 256×256 / 32 | 2,097,152 |
| DS4 low, blocks 5–7, DS8 high | 128×128 / 64 | 1,048,576 |
| DS8 low, blocks 9–13, DS14 high | 64×64 / 128 | 524,288 |
| DS14 low, blocks 15–21, DS22 high | 32×32 / 256 | 262,144 |
| **DS22 low / block30 input** | **16×16 / 512** | **131,072** |
| block30 pool | 8×8 / 512 | 32,768 |
| block30 head/repack / ViT N64 | 8×8 / 1024 = N64×1024 | 65,536 |
| decoder39 output; blocks 40–47 boundary | 16×16 / 512 | 131,072 |

`encoder_route.py` exposes `route_for_pre0_skip(height, width)`.  It declares every
0–22 edge and checks exact byte length/layout labels. `execute(runner)` accepts only
an explicit caller-supplied stage runner and rejects missing, extra, non-`bytes`, or
wrong-sized outputs. Thus it cannot silently use an H256/H8 artifact for an H512/H16
edge. `dry_run_shape_only()` uses zero-filled buffers solely to test that wiring.

`host_shape_records()` serializes only independently established H/W fields:
pre0 ingress `+208`, primary `+256`; 1H/DS4 `+24` and DS4 low `+72`; later ordinary
blocks `+32`, and DS8/14/22 low `+80`. They are contract witnesses, not native launches.

## Run

```sh
cd nr-encoder-h512-to22-parametric-main-20260914
python3 -B verify_route.py
python3 -B -m unittest -v test_encoder_route.py
```

`verify_route.py` re-hashes all retained pre-existing exact H128 encoder 0–22
artifacts against `FIRST_UNIFIED_OUTPUTS.json`, checks local ABI serializers, checks
the H16→H8/N64 pool/head, decoder39, and blocks 40–47 artifacts, then writes
`AUDIT_RESULT.json`.

## Important boundary distinction

`route_for_pre0_skip(256)` ends at H8×W8/C512 (32,768 B). It is deliberately rejected
by `bottleneck_contract()` as an **intermediate boundary**. It cannot be called the
complete encoder input to the corrected H16 block30 pool.

The checked H512 route reaches H16×W16/C512 (131,072 B), which is the compatible
block30 input. Existing local numerical fixture runners have conservative resolution
bounds, so this audit does **not** claim a numerical H512 original-program execution
equality; it claims and verifies the parameterized topology, bytes, ABI H/W fields,
and downstream host compatibility only. No game, GPU, network, native launch, or
deployment path is used.
