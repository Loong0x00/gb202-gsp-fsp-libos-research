# RTX 5090 VBIOS signature-defect quick audit

Scope: local ROM bytes only; bounded structural checks. No flashing, no execution, no GPU access.

## Result

- ROMs checked: 23
- Nested hash-chain checks all OK: True
- Adjacent-key direct ECDSA verify hits in bounded candidates: 0
- Same raw signature reused on different parent/object: 0
- Same adjacent P-384 point + same r across different parent/object: 0
- DER-like ECDSA signatures found in ROM corpus: 0; reused DER blobs: 0

## FSP_RUN envelope groups

| group sha256[:12] | count | files |
|---|---:|---|
| `1f01255cf607` | 22 | `281640.rom`, `281649.rom`, `281814.rom`, `Asus.RTX5090.32768.250114.rom`, `Asus.RTX5090.32768.250115.rom`, `Asus.RTX5090.32768.250115_1.rom`, `Asus.RTX5090.32768.250226.rom`, `Asus.RTX5090.32768.250226_1.rom`, `Asus.RTX5090.32768.250327.rom`, `Asus.RTX5090.32768.251013.rom`, `Asus.RTX5090.32768.251013_1.rom`, `Asus.RTX5090.32768.251013_2.rom`, `Gigabyte.RTX5090.32768.250115.rom`, `Gigabyte.RTX5090.32768.250115_1.rom`, `Inno3D.RTX5090.32768.250310.rom`, `MSI.RTX5090.32768.250120.rom`, `MSI.RTX5090.32768.250120_1.rom`, `Palit.RTX5090.32768.250114.rom`, `Palit.RTX5090.32768.250114_1.rom`, `Palit.RTX5090.32768.250213.rom`, `Palit.RTX5090.32768.250408.rom`, `Zotac.RTX5090.32768.250114.rom` |

## High-interest rows

| file | visible | entry1 length | envelope sha256[:12] | point[:12] | sig[:12] | direct verify hits |
|---|---|---:|---|---|---|---|
| `281640.rom` | PG145 SKU 30 VGA BIOS  | 169040 | `1f01255cf607` | `383fea5fe830` | `b014aa3e69d3` | [] |
| `281649.rom` | PG145 SKU 30 VGA BIOS  | 169040 | `1f01255cf607` | `383fea5fe830` | `a322b19faad8` | [] |
| `281814.rom` | RTX5090 VB Ver 98.02.2E.40.AS29 | 169040 | `1f01255cf607` | `383fea5fe830` | `7c0b4a5452a7` | [] |
| `Asus.RTX5090.32768.250327.rom` | RTX5090 VB Ver 98.02.2E.40.AS03MR | 169040 | `1f01255cf607` | `383fea5fe830` | `01798403f0b5` | [] |
| `GALAX.RTX5090D.32768.250226.rom` | NVIDIA GeForce RTX 5090 D VGA BIOS XOC-0220K  | 169040 | `e66270a9c726` | `383fea5fe830` | `49489a837870` | [] |

## What this rules out

- No broken/mismatching SHA-384 coverage was found in the checked nested images.
- No obvious copy-paste signature error was found: the same 96-byte signature-shaped field was not reused across different parent/object digests.
- No obvious ECDSA nonce-reuse symptom was found under the adjacent-point model: same point plus same first 48-byte half across different parent/object did not occur.
- No simple direct verification succeeded with the adjacent P-384 point over the bounded transcripts tested. This matches earlier four-sample results and suggests a private certificate/manifest transcript or a parent-key chain, not a trivial self-signature.

## Important implication

- Most current GeForce RTX 5090 samples share the exact same `FSP_RUN` envelope. If a high-power BIOS differs but the envelope group is unchanged, its power-policy delta is probably elsewhere in VBIOS policy data, not inside `FSP_RUN`.
- This audit does not prove the signature scheme is flawless. It only says the easy defects we can check from public/local bytes are not showing up.
