# RTX 5090 VBIOS static statistics

Scope: local ROM bytes only. No execution, no flashing, no device access.

## Corpus

- Downloaded ROMs indexed: 22
- Extra local reference ROMs indexed: 1

| file | size | md5[:8] | visible version/name | FSP_RUN offsets | target register literal hits |
|---|---:|---|---|---|---|
| `281640.rom` | 1961983 | `6ae68f3d` | MSINV530MH.1M1<br>PG145 SKU 30 VGA BIOS <br>PPIDROG-ASTRAL-RTX5090-O32G-WHITE-2I3S#250861931500416 | 0x11b331 | yes |
| `281649.rom` | 1961983 | `98d7be96` | MSINV530MH.1N0<br>PG145 SKU 30 VGA BIOS <br>PPIDROG-ASTRAL-RTX5090-O32G-GAMING-2I3S#250455002700066 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250114.rom` | 1961983 | `3bfa9566` | RTX5090 VB Ver 98.02.2E.00.AS11<br>PPIDTUF-RTX5090-32G-GAMING-2I3S#250150062400145 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250115.rom` | 1961983 | `4a5d732f` | RTX5090 VB Ver 98.02.2E.00.AS05<br>PPIDROG-ASTRAL-RTX5090-O32G-GAMING-2I3S#250149461500740 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250115_1.rom` | 1961983 | `4642bc34` | RTX5090 VB Ver 98.02.2E.00.AS06<br>PPIDROG-ASTRAL-RTX5090-O32G-GAMING-2I3S#250251386100989 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250226.rom` | 1961983 | `dcd4e936` | RTX5090 VB Ver 98.02.2E.40.AS22<br>PPIDROG-ASTRAL-LC-RTX5090-O32G-GAMING-2I3S#250251220000369 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250226_1.rom` | 1961983 | `c20ce7d7` | RTX5090 VB Ver 98.02.2E.40.AS21<br>PPIDROG-ASTRAL-LC-RTX5090-O32G-GAMING-2I3S#250251220000369 | 0x11b331 | yes |
| `Asus.RTX5090.32768.250327.rom` | 1961983 | `0a3826e7` | RTX5090 VB Ver 98.02.2E.40.AS03MR | 0x11b331 | yes |
| `Asus.RTX5090.32768.251013.rom` | 1961983 | `31871930` | RTX5090 VB Ver 98.02.2E.80.AS15<br>PPIDROG-MATRIX-RTX5090-P32G-30TH-2I3S#251064576500079 | 0x11b331 | yes |
| `Asus.RTX5090.32768.251013_1.rom` | 1961983 | `91f3324a` | RTX5090 VB Ver 98.02.2E.80.AS16 | 0x11b331 | yes |
| `Asus.RTX5090.32768.251013_2.rom` | 1961983 | `26182a61` | RTX5090 VB Ver 98.02.2E.80.AS16<br>PPIDROG-MATRIX-RTX5090-P32G-30TH-2I3S#251064772400086 | 0x11b331 | yes |
| `GALAX.RTX5090D.32768.250226.rom` | 1961983 | `33e22336` | NVIDIA GeForce RTX 5090 D VGA BIOS XOC-0220K  | 0x11b331 | yes |
| `Gigabyte.RTX5090.32768.250115.rom` | 1961983 | `e9c22eb9` |  | 0x11b331 | yes |
| `Gigabyte.RTX5090.32768.250115_1.rom` | 1961983 | `9b25710e` |  | 0x11b331 | yes |
| `Inno3D.RTX5090.32768.250310.rom` | 1912272 | `1df3075a` | PG145 SKU 30 VGA BIOS  | 0x11b331 | yes |
| `MSI.RTX5090.32768.250120.rom` | 1961983 | `54ffbda0` | MSINV530MH.171<br>PG145 SKU 30 VGA BIOS  | 0x11b331 | yes |
| `MSI.RTX5090.32768.250120_1.rom` | 1961983 | `c8295dd5` | MSINV530MH.161<br>PG145 SKU 30 VGA BIOS  | 0x11b331 | yes |
| `Palit.RTX5090.32768.250114.rom` | 1961983 | `51777d92` |  | 0x11b331 | yes |
| `Palit.RTX5090.32768.250114_1.rom` | 1961983 | `7a1cc5f0` |  | 0x11b331 | yes |
| `Palit.RTX5090.32768.250213.rom` | 1961983 | `e1ee4888` |  | 0x11b331 | yes |
| `Palit.RTX5090.32768.250408.rom` | 1961983 | `cb2c77ca` |  | 0x11b331 | yes |
| `Zotac.RTX5090.32768.250114.rom` | 1961983 | `469e77a3` | PG145 SKU 30 VGA BIOS  | 0x11b331 | yes |
| `unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | 1961983 | `df6bc54e` | PG144 SKU 30 VGA BIOS  | 0x11b331 | yes |

## Selected byte similarity

| pair | identity | changed bytes | contiguous ranges | merged ranges gap64 |
|---|---:|---:|---:|---:|
| `281640.rom` vs `281649.rom` | 99.9324% | 1327 | 72 | 41 |
| `281640.rom` vs `MSI.RTX5090.32768.250120.rom` | 99.8517% | 2909 | 312 | 75 |
| `281640.rom` vs `MSI.RTX5090.32768.250120_1.rom` | 99.8503% | 2938 | 305 | 75 |
| `281649.rom` vs `MSI.RTX5090.32768.250120.rom` | 99.8512% | 2920 | 312 | 75 |
| `281649.rom` vs `MSI.RTX5090.32768.250120_1.rom` | 99.8499% | 2944 | 308 | 75 |
| `281649.rom` vs `GALAX.RTX5090D.32768.250226.rom` | 67.4239% | 639137 | 2689 | 106 |
| `281640.rom` vs `GALAX.RTX5090D.32768.250226.rom` | 67.4211% | 639192 | 2684 | 107 |
| `281649.rom` vs `Asus.RTX5090.32768.250327.rom` | 99.8409% | 3122 | 374 | 91 |
| `281640.rom` vs `Asus.RTX5090.32768.250327.rom` | 99.8417% | 3105 | 383 | 91 |

## Interpretation

- `281640.rom` and `281649.rom` are extremely close but not identical: 1327 bytes differ over 1961983 bytes (99.9324% identical). That matches the expectation that they are two Lightning variants with changed policy/table/signature data, not unrelated images.
- Every downloaded 5090/5090D ROM in this corpus contains `FSP_RUN` at a visible offset. This is consistent with board policy being packed into a signed firmware/container region rather than exposed as simple editable ASCII.
- The scan found no obvious plaintext ASCII L2-control register names/addresses. Raw little/big-endian dword hits, if any, are listed in the JSON per file.
- The 800W/1000W distinction is not visible as a simple `800`/`1000` ASCII field inside the ROM. Treat it as structured binary policy plus integrity metadata.

## Output files

- `analysis/vbios_static_stats.json`: full per-file metadata, selected diff ranges, string diffs, variable 4K pages.
- `analysis/pairwise_similarity.csv`: pairwise byte identity matrix in long format.
- `analysis/selected_top_diff_blocks.csv`: hottest differing 4 KiB blocks for selected comparisons.
