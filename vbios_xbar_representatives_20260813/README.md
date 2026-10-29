# RTX 5090 representative VBIOS and XBAR set (2026-08-13)

This bundle separates two kinds of evidence that must not be conflated:

- `roms/`: static VBIOS images. These can establish table equality, factory offsets,
  policy limits, and rail-routing changes.
- `runtime/`: a live RM `CLK_VF_POINTS_GET_STATUS` capture. This is the source of the
  actual 127-point XBAR curve exposed by the running driver.

No firmware was flashed and no tuning value was written while creating this bundle.
The only live operation was a read-only STATUS query on the already-running card.

## Representative samples

| Alias | Internal version | SHA-256 | Whole-card budget | Factory core offset | NVVDD / MSVDD budget | Voltage-rail indices | Live XBAR capture |
|---|---|---|---:|---:|---:|---:|---|
| Astral native OC | `98.02.2E.00.CF` | `c274ec136876852b74fec553275ab1d61025a986ccfc463c0fb0b290fa94c191` | 600 W / 60 A | +45 MHz | 480 A / 180 A | `3,4` | no |
| ROG Matrix 800 W | `98.02.2E.80.C9` | `4c772b46b2df424b94c4c71fffece98da96375c5d2699ce0bfcd1a51828015dd` | 800 W / 80 A | +195 MHz | 480 A / 180 A | `3,4` | no |
| MSI Lightning 800 W, TPU 281640 | `98.02.2E.C0.0F` | `9ae22a0b80836ac80b60b4bcada3c1867daf224a645009225b2fd239d9751e0b` | 800 W / 80 A | +195 MHz | 720 A / 240 A | `3,4` | no |
| MSI Lightning 1000 W, TPU 281649 | `98.02.2E.C0.10` | `5dabed819ca9b8a63756444421c46287d95115d51c091fe95cd7594c50873abc` | 1000 W / 100 A | +195 MHz | 720 A / 240 A | `3,4` | no |
| Astral 2001 W XOC, TPU 281814 | `98.02.2E.80.50` | `0a1a511e72d707f513aab02a1d1ccfa8a78347d56915b0c922398724193ec97d` | 2001 W | +45 MHz | XOC policy | `6,6` | yes, R610.57.04 |
| MSI Lightning 2500 W XOC, associated with TPU 281792 | `98.02.2E.80.E8` | `f0a45a81506f2deabc6ca6c39696d6e835f0ce2b88eeead8f58d16462205f84b` | 2500 W / 250 A | +195 MHz | 2000 A / 1000 A | `6,6` | no |

The full machine-readable inventory is in `manifest.csv`.

## What the static comparison actually establishes

The native Astral, Matrix 800 W, Lightning 800 W, and Lightning 1000 W images
use byte-identical base `VOLTAGE_MAP` data. Matrix and both Lightning images also
share the same `PERFORMANCE`, `BASE_CLOCK`, `VOLTAGE_RAIL`, `VOLTAGE_DEVICE`,
`VOLTAGE_POLICY`, `FactoryOC`, thermal, and recognized low-power tables.

The representative differences are:

1. Matrix/Lightning carry a +195 MHz factory core offset and 2730 MHz factory
   vPstate target, versus Astral native +45 MHz and 2580 MHz.
2. Matrix 800 W raises the whole-card budget but retains Astral's 480 A / 180 A
   NVVDD/MSVDD rail budgets.
3. Lightning raises those rail budgets to 720 A / 240 A; its 800 W and 1000 W
   images otherwise retain the same base V/F and voltage tables.
4. Astral 2001 W and Lightning 2500 W are a separate XOC class: their complete
   `VOLTAGE_RAIL` tables are byte-identical and change the two relevant indices
   from `3,4` to `6,6`.
5. Lightning 2500 W retains the Lightning +195 MHz / 2730 MHz factory settings,
   but raises the whole-card/input limits to 2500 W / 250 A and the NVVDD/MSVDD
   current limits to 2000 A / 1000 A.

Consequently, the local ROM evidence does not support a linear narrative of
"request 1.15 V, therefore XBAR scales to 2900 MHz." The normal Matrix/Lightning
images do not contain a replacement high-voltage XBAR curve. The acquired
Lightning 2500 W image does differ, but the confirmed difference is an XOC
rail-routing and policy-limit change, not a measured runtime XBAR curve.

## Live XBAR result

The read-only 2026-08-13 capture was taken while BIOS `98.02.2E.80.50`
(Astral 2001 W XOC) and driver R610.57.04 were active. The decoder validated all
127 records:

- first point: 450 mV / 225 MHz;
- last point: 1240 mV / 2812 MHz;
- factory XBAR tuning offset: +45 MHz at every point.

Files:

- `runtime/astral-2001w-98.02.2E.80.50-r610.57.04-status.txt`
- `runtime/astral-2001w-98.02.2E.80.50-r610.57.04-xbar.csv`

The decoder reads the live `NV2080_CTRL_CMD_CLK_VF_POINTS_GET_STATUS` object.
The ROM can also be analyzed offline, but it contains the signed inputs to VF
generation rather than a literal copy of this 127-record STATUS bank.

Offline comparison shows that Astral 2001 W XOC and Lightning 2500 W XOC have
byte-identical `PERFORMANCE`, `BOOST`, Clock Programming, Voltage Map v0x30,
NAFLL, Frequency Controller, Clocks/VFE-related, Base Clock, Voltage Device,
Voltage Rail, and Voltage Policy payloads. Their relevant static VF input that
differs is FactoryOC: Astral uses +45 MHz / 2580 MHz while Lightning uses
+195 MHz / 2730 MHz.

On the current Astral STATUS capture, the 127 base frequencies are accompanied
by exactly +45 MHz at every XBAR point. Holding the GPU, driver, temperature,
fuse/speedo values, and VF-generation behavior constant, replacing that term
with +195 MHz projects a +150 MHz shift (for example, the last 2812 MHz point
would become 2962 MHz). This is a controlled projection from byte-identical
static tables plus the live Astral reference, not a direct capture of Lightning.
The exact per-card STATUS still requires the driver/GSP VF generator because it
also evaluates chip fuses/speedo and runtime state such as temperature.

## Lightning 2500 W acquisition and verification

The original TechPowerUp record is associated with ID `281792`, but it currently
returns `BIOS not found`. The older indexed Drive share
`1MTbqvRWoYF6cnFxbgg2uhfCPPZlhXAwt` is also gone.

The OCN page-1697 HTML mirror preserves two current references from the same
poster:

- forum attachment `Lightning_XOC.rom.txt`, attachment ID `2754663`;
- a signature link labelled `MSI Lightning 2500w XOC`, Drive ID
  `1VNEO_LCOz7YvZFqm96Nk5hjmeE4bQ5DV`.

The mirror exposes the attachment metadata but cannot relay its binary body.
The public Drive link does return the ROM bytes. Re-download command:

```sh
curl -L --fail \
  'https://drive.usercontent.google.com/download?id=1VNEO_LCOz7YvZFqm96Nk5hjmeE4bQ5DV&export=download&confirm=t' \
  -o 281792.rom
sha256sum 281792.rom
```

Expected size and SHA-256:

```text
1961983 bytes
f0a45a81506f2deabc6ca6c39696d6e835f0ce2b88eeead8f58d16462205f84b
```

Offline parsing confirms the same GB202 PCI/NPDS/BIT/Falcon container family,
internal board string `MSINV530MH.1L5`, internal version `98.02.2E.80.E8`, six
2500000 mW fields, three 250000 mA fields, and 2000000/1000000 mA rail limits.
The complete `VOLTAGE_RAIL` table is byte-identical to Astral 2001 W XOC.

The previously indexed `.8E` spelling is therefore not used here: the acquired
bytes themselves unambiguously contain `.E8`. The removed TPU object and OCN
attachment were not available for a byte-for-byte comparison, so the TPU-ID
association remains provenance metadata rather than a content-identity proof.

## Reproduction

Static container comparison:

```sh
python tools/gb202_vbios_diff.py roms/*.rom
```

Decode the saved live STATUS object:

```sh
python tools/decode_clk_vf_points_status.py \
  runtime/astral-2001w-98.02.2E.80.50-r610.57.04-status.txt
```
