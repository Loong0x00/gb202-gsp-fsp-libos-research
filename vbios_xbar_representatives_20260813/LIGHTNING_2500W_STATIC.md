# MSI Lightning 2500 W XOC static verification

Date: 2026-08-13

Scope: offline reads of the downloaded ROM and local comparison ROMs. No GPU,
driver setting, firmware, clock, voltage, power, or fan value was written.

## Provenance

- OCN thread page 1697, post `29564089` contains an attachment named
  `Lightning_XOC.rom.txt` (attachment `2754663`, displayed size 1.9 MB).
- The same poster's signature links `MSI Lightning 2500w XOC` to public Drive
  file `1VNEO_LCOz7YvZFqm96Nk5hjmeE4bQ5DV`.
- The verified local ROM was downloaded from that Drive file. It was not
  obtained from the OCN attachment endpoint or the removed TPU object.

## File identity

```text
path: roms/lightning-2500w-xoc-tpu281792.rom
size: 1961983 bytes (0x1defff)
sha256: f0a45a81506f2deabc6ca6c39696d6e835f0ce2b88eeead8f58d16462205f84b
board string: MSINV530MH.1L5
version string: 98.02.2E.80.E8
```

The size matches the local Lightning 800 W and 1000 W images. The scanner
validates the four-part PCI/NPDS chain, BIT table, 35-entry Falcon table, and
72-entry BIT-`i` address table.

## Confirmed policy differences

| Field | Lightning 800 W | Lightning 1000 W | Lightning 2500 W XOC |
|---|---:|---:|---:|
| whole-card/combined power | 800 W | 1000 W | 2500 W |
| total-input current | 80 A | 100 A | 250 A |
| NVVDD current | 720 A | 720 A | 2000 A |
| MSVDD current | 240 A | 240 A | 1000 A |
| voltage-rail indices | `3,4` | `3,4` | `6,6` |
| factory core offset | +195 MHz | +195 MHz | +195 MHz |
| factory vPstate target | 2730 MHz | 2730 MHz | 2730 MHz |

The 2500 W and Astral 2001 W XOC `VOLTAGE_RAIL` payloads are byte-identical.
The 2500 W image's `VOLTAGE_DEVICE`, `VOLTAGE_POLICY`, and 27-byte FactoryOC
payloads remain byte-identical to the regular Lightning images.

## Interpretation boundary

Confirmed: this image raises signed policy limits and switches to the same XOC
voltage-rail routing found in the Astral 2001 W image.

Offline comparison also confirms that the following curve-generation inputs are
byte-identical between Astral 2001 W XOC and Lightning 2500 W XOC:

```text
PERFORMANCE, BOOST, CLOCK_PROGRAM, C+0x1c,
VOLTAGE_MAP v0x30, NAFLL, FREQUENCY_CONTROLLER, CLOCKS,
C+0x20, C+0x24, C+0x28, BASE_CLOCK,
VOLTAGE_DEVICE, VOLTAGE_RAIL, VOLTAGE_POLICY
```

The relevant static difference is FactoryOC: +45 MHz / 2580 MHz on Astral and
+195 MHz / 2730 MHz on Lightning. The active Astral STATUS has a +45 MHz tuning
term at all 127 XBAR points. Under the explicit condition that the same GPU,
driver, temperature, fuse/speedo inputs, and VF-generation behavior are held
constant, the Lightning term projects the XBAR frequencies +150 MHz; the last
2812 MHz point would project to 2962 MHz.

That projection is not the same as claiming the ROM literally stores a final
127-point curve. NVIDIA's VF generator also consumes per-chip fuse/speedo and
runtime state, so an exact Lightning STATUS still requires either booting it or
an offline implementation supplied with those inputs. An actual requested or
delivered voltage and stability at a particular clock are likewise not proven
by ROM parsing. This bundle does not flash or boot the image.
