# Host shift contract — bounded static review

## Finding
**Confirmed, as current-static expected configuration:** the first decoder-table pair `(1,1)` maps to the first seven-pair decoder iteration and, when correlated with the separately source-retyped historical graph ordering, to block 49. It produces initial forward origin `(-4,-4)`. This is a current-PE + historical-graph inference only—not a fresh capture, execution result, or guarantee about a mutable runtime instance.

## Evidence chain

1. **Constructor/copy offsets.** `0x18006865b` retains `this` in `r14`; `0x18006866a` changes `rcx` to `this+8` and `0x18006866e` calls `0x18001ea60` with the descriptor in `rdx`. Thus the constructor performs descriptor copy at `this+8`.
   * The copy loads/stores descriptor-relative `+0x70` at `0x18001eac0/0x18001eac3` and `+0x74` at `0x18001eac6/0x18001eac9`.
   * With destination `this+8`, these become runtime `this+0x78` and `this+0x7c`; this is direct address arithmetic from the instructions, not an assumed layout stride.

2. **Builder ABI and field order.** At `0x1800688ecb`, `descriptor_builder` saves Win64 register argument `r9d`; it stores that saved fourth argument into descriptor `+0x70` at `0x18006919e/0x1800691a2`. It reads `[rbp+0x400]` at `0x1800691a5` and stores it to `+0x74` at `0x1800691ab`.
   * From the prologue (`0x1800688ea0`–`0x1800688eb3`), `[rbp+0x400]` is entry `[rsp+0x28]`: the Win64 fifth argument. Therefore `r9d -> desc+0x70`; fifth stack dword -> `desc+0x74`.
   * The decoder loop loads the second dword at `0x18003ae90` and the first at `0x18003ae94`, places the first in caller `[rsp+0x20]` at `0x18003aece`, the second in `r9d` at `0x18003aed2`, then calls the builder at `0x18003aee5`. Consequently table `(first, second)` maps to runtime `(+0x7c, +0x78)`, respectively.

3. **Table, bounds, and ordinal correlation.** The loop base is `0x1800b2298` via `0x18003ae81`; pair loads are `[r13]`/`[r13+4]` at `0x18003ae90/0x18003ae94`. It starts ordinal counter `1` at `0x18003ae78`, advances by eight bytes at `0x18003af59`, and stops before `0x1800b22d0` (`0x18003af5d`–`0x18003af67`): exactly seven pairs.
   * Pairs in selection order: 1 `(1,1)`; 2 `(1,0)`; 3 `(0,1)`; 4 `(-1,-1)`; 5 `(1,1)`; 6 `(1,0)`; 7 `(0,1)`.
   * The PE establishes iteration order and builder dataflow, but does **not** embed a literal global block number in this loop. `HISTORICAL_GRAPH_CONTEXT.json` (explicitly historical/source-retyped) identifies block 49 as the first shifted decoder block, with block 48 as its producer. Combining that graph ordering with the first loop iteration confirms the *expected static* association `block 49 <- pair 1 (1,1)`. It must not be promoted to a fresh/live graph-instance claim; differing factory path, ordering, or mutable fields would require separate evidence.

4. **Forward origin and grid.** In the `rdx == -1` branch (`0x180069d20`–`0x180069e23`), forward reads runtime `+0x78` at `0x180069e32` and `+0x7c` at `0x180069e23`. `test/cmovs/neg/shl 2` at `0x180069e36`–`0x180069e43` and `0x180069e44`–`0x180069e58` implement exactly:

   `origin_x = -4 * max(runtime[+0x78], 0)`

   `origin_y = -4 * max(runtime[+0x7c], 0)`.

   Hence `(1,1)` yields `(-4,-4)`. For the seven listed pairs, resulting `(origin_x, origin_y)` are: `(-4,-4)`, `(0,-4)`, `(-4,0)`, `(0,0)`, `(-4,-4)`, `(0,-4)`, `(-4,0)`.

   Let `D90` and `D98` denote the dwords read from `[rbp+0x90]` and `[rbp+0x98]`. The two grid counts written to `r9d` and `r8d` follow `0x180069ff1`–`0x18006a042`:

   `grid_90 = ceil((D90 + 4*max(runtime[+0x78],0))/8)`

   `grid_98 = ceil((D98 + 4*max(runtime[+0x7c],0))/8)`

   for the expected non-negative dimensions. The literal signed instruction form is `(n+7+(((n+7)>>31)&7)) >> 3` (`0x18006a014`–`0x18006a02e` and `0x18006a037`–`0x18006a049`), so no mental division/stride shortcut was used.

## Scope caveats

* This establishes code/data configuration, not that the `rdx == -1` branch is selected on every invocation; that selection is explicit at `0x180069d20`–`0x180069d24`.
* The forward body also conditionally reads a separate object at runtime `+0x158` (`0x180069fb5`–`0x180069fe0`), so no immutable-instance guarantee is warranted.
* Main's reported ordinary CPU/NN zero and `-4` grids are not independently revalidated here and are not claimed live. They are only compatible with the static contract above.

Notification: bounded source-only report complete for Main.
