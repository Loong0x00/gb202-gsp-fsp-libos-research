# Lightning / HOF high-power VBIOS notes

Static notes only. Do not flash from this file.

## Local files

- `downloads/manual_from_downloads/281649.rom`
  - TPU id: 281649
  - Card shown by TPU: MSI RTX 5090 LIGHTNING Z
  - VBIOS version: `98.02.2E.C0.10`
  - Internal string: `MSINV530MH.1N0`
  - TPU page MD5/SHA1 matched local file
  - TPU-parsed board power: Target `1000.0 W`, Limit `1000.0 W`

- `downloads/manual_from_downloads/GALAX.RTX5090D.32768.250226.rom`
  - TPU id: 277809
  - Card shown by TPU: GALAX RTX 5090 D HOF OC LAB XOC
  - VBIOS version: `98.02.31.40.9A`
  - Internal string: `NVIDIA GeForce RTX 5090 D VGA BIOS XOC-0220K`
  - TPU page MD5/SHA1 matched local file
  - TPU-parsed board power: Target `2001.0 W`, Limit `2001.0 W`

## Lightning Z wattage claims

- MSI official specification lists power consumption as `OC:800 W` and `EXtreme:1000W`.
- MSI official product page also mentions `2500W XOC BIOS`, for extreme overclockers, and says warranty is voided when enabled.
- Media reports say 800W/1000W Lightning BIOS files leaked first, then a 2500W XOC BIOS leaked later. Those reports also warn about using such BIOSes on non-MSI / single-connector RTX 5090 cards.

Sources:

- https://au.msi.com/Graphics-Card/GeForce-RTX-5090-32G-LIGHTNING-Z/Specification
- https://www.msi.com/Graphics-Card/GeForce-RTX-5090-32G-LIGHTNING-Z
- https://wccftech.com/msi-rtx-5090-lightning-z-800-and-1000-watt-bioses-leaked/
- https://wccftech.com/after-800w-and-1000w-bios-files-msi-rtx-5090-lightning-z-2500w-xoc-bios-leaked/
- https://www.igorslab.de/en/msi-rtx-5090-lightning-z-2500w-xoc-bios-leaked-crossing-the-line-with-warning/

