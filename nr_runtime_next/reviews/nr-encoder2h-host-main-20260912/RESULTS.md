# Main current2H host recheck — no silent source-extent repair

Main rehashed installed DLL and independently disassembled its .text, checking **128 selected instruction witnesses/128 distinct sites**, their .pdata entries and **41 exact byte windows/slices** against the new host worker. MAIN_REVIEW.json / MAIN_REVIEW_01.log passed. Worker275checks,30windows29119B and its failures remain separate evidence.

Confirmed conditional factory route:5 inpview2H(0,0),6 ordinary2H(-4,-4),7 ordinary2H(-4,0),8 DS2H(0,-4),9 inpview4H(0,0). DS8 O0→9; DS8 O1→decoder62 I1. **2H upsample62 skip is ABI24** (load65c53/store65c59); **1H upsample66 skip is ABI80**. They are different aggregates, not interchangeable names.

## Source dimensions are NOT carried through block5 overrides

Common2H aggregate A=RBP-0x80,88 bytes. H/W at32/36 are rounded to8; nonDS/inpview stores a **zero qword at80/84** (`xor r8d,r8d` at0x180065d3c, store at0x180065dc7). Therefore supplied block5 PTX falls back to roundedH/W for effective source EH/EW. Positive source override support in PTX does not show the host supplies such values. C+180/+184 positive reads belong to upsample, not this branch.

Host formulas in positive/nonoverflow domain: `R8(n)=ceil8(n)` and `D(n)=ceil4(ceil(n/2))`; source DS learned strides are derived separately from kernel H/W. Do not equate D with floor-half for arbitrary dimensions.

- Default current CPU prefix: block4 H/W64, learned low32x32; block5 rounded/effective32x32 is compatible conditionally.
- Standalone DS4 heldout H56→learned28 is valid for its own no-padding reference, **not automatically a valid block5 input with effective32**. It is deliberately not connected downstream by inventing ABI80=28.
- Nonclean/odd host dimensions, source floor/ceil differences, allocation and padding footprints remain unresolved. These static mismatches are **not a native OOB finding or proven cause of game artifacts**; live base dimensions may satisfy further constraints.

If G and auxiliary handles exist, staticconfiguration permits5tilesync→6/7chained→8DSwait. Actual2H wait semantics require its own PTX review; 1H's relaxed/sign-negative predicate is not assumed for2H. Registration operands32x2/32x4 are not observed launches. Native initialization/epochs/visibility/allocations/lifetimes and binding remain OPEN. No DLL/Wine/GPU/network/game/deployment or gate change occurred.
