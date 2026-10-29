# RTX 5090 VBIOS family-group statistics

Scope: local static byte comparison only. No execution/flashing/device access.

## High-interest local samples

| file | id | role/model | version | board power from TPU detail | hash check |
|---|---:|---|---|---|---|
| `281640.rom` | 281640 | MSI, Lightning, RTX 5090, NVIDIA GeForce RTX 5090, 800w Factory bios (2017 / 1750) | 98.02.2E.C0.0F | Target: 800.0 W Limit: 800.0 W Adj. Range: -50%, +0% | MD5 True, SHA1 True |
| `281649.rom` | 281649 | MSI, Lightning Z 1000W, RTX 5090, NVIDIA GeForce RTX 5090, (2017 / 1750) | 98.02.2E.C0.10 | Target: 1000.0 W Limit: 1000.0 W Adj. Range: -60%, +0% | MD5 True, SHA1 True |
| `281814.rom` | 281814 | Asus, Astral, RTX 5090, NVIDIA GeForce RTX 5090, Asus XOC Bios #2 (2017 / 1750) | 98.02.2E.80.50 | Target: 2001.0 W Limit: 2001.0 W Adj. Range: -80%, +0% | MD5 True, SHA1 True |
| `GALAX.RTX5090D.32768.250226.rom` | 277809 | XOC VBIOS | 98.02.31.40.9A | Target: 2001.0 W Limit: 2001.0 W Adj. Range: -80%, +0% | MD5 True, SHA1 True |

## Same-family pair similarity

| family | pair | identity | changed bytes |
|---|---|---:|---:|
| ASUS Astral LC OC | `Asus.RTX5090.32768.250226.rom` vs `Asus.RTX5090.32768.250226_1.rom` | 99.9404% | 1170 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250115_1.rom` vs `Asus.RTX5090.32768.250115.rom` | 99.9306% | 1362 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250327.rom` vs `281814.rom` | 99.9287% | 1398 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250115.rom` vs `Asus.RTX5090.32768.250327.rom` | 99.8587% | 2773 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250115.rom` vs `281814.rom` | 99.8548% | 2848 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250115_1.rom` vs `Asus.RTX5090.32768.250327.rom` | 99.8545% | 2854 |
| ASUS Astral OC/XOC | `Asus.RTX5090.32768.250115_1.rom` vs `281814.rom` | 99.8513% | 2917 |
| ASUS Matrix | `Asus.RTX5090.32768.251013_1.rom` vs `Asus.RTX5090.32768.251013_2.rom` | 99.9964% | 70 |
| ASUS Matrix | `Asus.RTX5090.32768.251013.rom` vs `Asus.RTX5090.32768.251013_2.rom` | 99.9282% | 1409 |
| ASUS Matrix | `Asus.RTX5090.32768.251013.rom` vs `Asus.RTX5090.32768.251013_1.rom` | 99.9258% | 1455 |
| Gigabyte Gaming OC | `Gigabyte.RTX5090.32768.250115.rom` vs `Gigabyte.RTX5090.32768.250115_1.rom` | 99.9301% | 1372 |
| MSI Gaming Trio | `MSI.RTX5090.32768.250120_1.rom` vs `MSI.RTX5090.32768.250120.rom` | 99.9260% | 1452 |
| MSI Lightning XOC | `281640.rom` vs `281649.rom` | 99.9324% | 1327 |
| Palit GameRock | `Palit.RTX5090.32768.250213.rom` vs `Palit.RTX5090.32768.250408.rom` | 99.9374% | 1229 |
| Palit GameRock | `Palit.RTX5090.32768.250114.rom` vs `Palit.RTX5090.32768.250114_1.rom` | 99.9176% | 1616 |
| Palit GameRock | `Palit.RTX5090.32768.250114_1.rom` vs `Palit.RTX5090.32768.250213.rom` | 99.9049% | 1865 |
| Palit GameRock | `Palit.RTX5090.32768.250114_1.rom` vs `Palit.RTX5090.32768.250408.rom` | 99.9048% | 1867 |
| Palit GameRock | `Palit.RTX5090.32768.250114.rom` vs `Palit.RTX5090.32768.250213.rom` | 99.8885% | 2188 |
| Palit GameRock | `Palit.RTX5090.32768.250114.rom` vs `Palit.RTX5090.32768.250408.rom` | 99.8879% | 2199 |

## Selected XOC/normal cross-pairs

| pair | identity | changed bytes |
|---|---:|---:|
| `281814.rom` vs `Asus.RTX5090.32768.250327.rom` | 99.9287% | 1398 |
| `281814.rom` vs `Asus.RTX5090.32768.250115.rom` | 99.8548% | 2848 |
| `281814.rom` vs `281649.rom` | 99.8366% | 3205 |
| `281814.rom` vs `281640.rom` | 99.8373% | 3193 |
| `281814.rom` vs `GALAX.RTX5090D.32768.250226.rom` | 67.4287% | 639043 |
| `281649.rom` vs `GALAX.RTX5090D.32768.250226.rom` | 67.4239% | 639137 |

## Immediate observations

- `281814.rom` is a better high-power outgroup than GALAX HOF for normal RTX 5090 work because it is `10DE 2B85` ASUS Astral, not 5090D `2B87`.
- `281814.rom` vs normal ASUS Astral `98.02.2E.40.85` is the best “same board family: normal vs XOC” comparison currently in the corpus.
- `281640.rom` vs `281649.rom` remains the best Lightning 800W vs 1000W pair.
- None of this implies flash compatibility. It only identifies byte-level deltas worth reverse-engineering.
