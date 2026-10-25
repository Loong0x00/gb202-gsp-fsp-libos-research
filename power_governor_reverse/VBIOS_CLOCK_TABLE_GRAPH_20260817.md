# GB202 VBIOS clock-domain to relationship graph

## Result

The requested domain clock is not written directly to a PLL. The current ROM
and recovered R610 parser establish this front half:

```text
BIT C v2
  C+0x08 -> Clocks v0x50
               | type 1: direct V/F relationship range
               | type 2: another clock-domain mapping index
  C+0x0c -> Clock Programming v0x50, indexed by direct relationship ID
               -> type-7 fixed-frequency or type-9 V/F object
               -> tuple/VFE selection
               -> limit and propagation stages
               -> PMU source-grid/divider projection
```

This corrects an earlier false lead: BIT `P+0x50` belongs to the version-2
Thermal Policy portion of BIT P. It is not Clock Programming. Clock Programming
is BIT `C+0x0c`.

## Exact ROM and pointers

- ROM SHA-256: `0a1a511e72d707f513aab02a1d1ccfa8a78347d56915b0c922398724193ec97d`
- VBIOS: `98.02.2E.80.50`
- BIT: ROM `0x38df0`
- BIT C v2 payload: ROM `0x38eb5`, length `0x30`
- expansion-image pointer bias: `0x50000`
- Clocks (`C+0x08`): ROM `0x91953`
- Clock Programming (`C+0x0c`): ROM `0x69fa5`
- NAFLL (`C+0x10`): ROM `0x9159e`
- ADC (`C+0x14`): ROM `0x9bb25`
- Frequency Controller (`C+0x18`): ROM `0x91682`

The pointer roles follow NVIDIA's published BIT layout. The physical offsets,
pointer bias and table contents above are exact for this ROM.

## Recovered parser ABI

Clocks v0x50 header bytes are `50 0d 0f 09 03 02 08 e8 03 00 00 ff ff`.
R610 parser `0x0117e9c4` uses:

- header `7b3w`, minimum 13 bytes;
- 9 entries, at most 32;
- base entry `1b1w1d2w1d`, minimum 15 bytes;
- two `1b1w` subentries, minimum 3 bytes each;
- exact stride `15 + 2*3 = 21` bytes;
- mapping descriptor version 8.

Clock Programming v0x50 header bytes are `50 08 17 19 03 04 04 03`.
R610 parser `0x0118d228` uses:

- header `8b`, minimum 8 bytes;
- 25 entries;
- base entry `1b5w2d2w`, 23 bytes on this ROM;
- four `1b1w` first subentries;
- three `2w` second subentries;
- exact stride `23 + 4*3 + 3*4 = 47` bytes.

Rows 0..17 are active. Rows 18..24 are disabled/sentinel rows.

## Domain graph

| Clocks index | Domain | internal ID | direct relationship/program IDs | type-2 reference |
|---:|---|---:|---|---|
| 0 | GPC | 1 | 13 | — |
| 1 | XBAR | 2 | 17 | — |
| 2 | MCLK | 5 | 8..12 | — |
| 3 | SYS | 3 | 15 | — |
| 4 | NVD | 20 | 14 | — |
| 5 | PWR | 19 | 16 | — |
| 6 | PCIe | 26 | —; nominal range 22..26 | mapping index 2, MCLK |
| 7 | API40 | 7 | 0..7 | — |
| 8 | API08 | 4 | —; nominal range 18..21 | mapping index 7, API40 |

For a type-1 Clocks subentry the 16-bit value contains low/high relationship
IDs. For type 2 the parser consumes its low byte as a mapping descriptor index,
checks that the target descriptor exists, and constructs a linked clock-domain
object. This is the first byte-exact proof of the domain-to-program indirection.

The type-9 Clock Programming rows also contain tuple-bank ranges that exactly
match current CLK_VF_TUPLES INFO:

- relation 13 GPC: tuples 0..40;
- relation 14 NVD: 41..61;
- relation 15 SYS: 62..82;
- relation 16 PWR: 83..103;
- relation 17 XBAR: 104..124.

Rows 0..7 contain the eight API40 frequency keys. Rows 8..12 contain the five
ROM MCLK keys. This independently joins the ROM program objects to the already
recovered runtime V/F relation and tuple model.

## ROM is not final runtime state

Three byte-exact/runtime differences are deliberately retained:

- ROM GPC type-9 maximum: 3450 MHz; current GET_INFO maximum: 3495 MHz;
- ROM XBAR type-9 maximum: 3450 MHz; current GET_INFO maximum: 3495 MHz;
- ROM relation 12 key: 14001 MHz; current GET_INFO: 15001 MHz.

Therefore a VBIOS row is an input to object construction, not proof of the
final runtime control object. Factory offsets, board-object control, relation
selection, propagation, limit clients and the PMU grid can all intervene.

## Executable reproduction

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm
PYTHONPATH=. python inspect_vbios_clock_graph.py \
  --rom /home/user/rt_5090_project/vbios_bulk_5090_20260723/downloads/manual_from_downloads/281814.rom \
  --bit-c 0x38eb5 --pointer-bias 0x50000
PYTHONPATH=. python -m unittest tests.test_vbios_clock_tables -v
```

`gpu_inverse/vbios_clock_tables.py` rejects truncated tables and enforces the
same size/count limits as the recovered parser. The virtual solver exposes the
resolved graph at `stages.vbios_clock_graph` while retaining current GET_INFO
as its active supported-frequency input.

## Evidence boundary

Confirmed: BIT C pointers, both v0x50 layouts, exact strides/counts, nine-domain
order, mapping-version-8 internal IDs, direct relation ranges, type-2 domain
references, 18 active program rows and five type-9 tuple banks.

Inferred but strongly cross-checked: the packed signed 16-bit pair in each
Clocks row is an offset-control range. The executable parser exposes the pair
but does not use that name in the solver.

Still open: names for every neutral Clock Programming word/dword, the exact
current encrypted-R610 PMU consumer of all transferred fields, and the raw
unreduced divider factorization. These do not erase the now-closed graph or the
observed many-to-one output explanations.
