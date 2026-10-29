# Split16H route resolution (static / CPU-only)

## Conclusion

The apparent conflict is resolved as an **ordering distinction**, not an F16 conversion or a malformed tensor.

* The archived historical graph was produced by `factory(storage, 0)` and therefore records the **pre-rewrite** spelling `cc_split_swin_16h_ffwd_inpview_512` for block23/layer0.
* The packaged catalog route is statically `manager 0x180020fae -> catalog 0x18003d670`.  Catalog itself calls the factory with `EDX=0` at `0x18003d6ac..d6b6`, copies that result, and then calls the all-layer name rewriter at `0x18003d6e6..d6f0`.  The manager receives the post-rewrite catalog only after that call returns.
* For this archived catalog, all **152** layer names are rewritten by the literal `_fp8` append/check path.  Block23/layer0 specifically becomes `cc_split_swin_16h_ffwd_inpview_512_fp8` (historical length/capacity 34/47, so the four-byte append takes the inline path).
* A Split16H layer initialized from that rewritten name selects the FP8 base literal at `0x18006d82e..d844`; it does not select the F16 literal.  Thus the exact 524,288-byte serialized block23/layer0 slab is compatible with the **statically proven rewritten route**.  This establishes a static path, not that a live block23 invocation, weight upload, or submission was captured.

The prior factory(0) observation remains valid, but it identifies an intermediate descriptor state.  It must not be used as the final-name selector for the catalog path above.

## Byte/call/flag lineage

All VAs below are in the DLL pinned in the inventory.  `host-*.txt` and `bytes/*.bin` preserve the complete listed ranges; `EVIDENCE.json` binds each byte range to its SHA-256.

| Step | Preserved proof | What it establishes |
|---|---|---|
| Historical source | `dump_graph_factory.cpp:191` calls `factory(storage, 0)`; `graph-factory.log:307` records block23/layer0 without `_fp8`. | The historical record is an intentional mode-0, pre-catalog-rewrite snapshot. Its raw descriptor bytes at `0x60..0x62` are `00 00 00`. |
| Catalog generation | `host-catalog.txt`: `33 d2` at `0x18003d6ac`; `call 0x180039780` at `d6b6`; copy at `d6bc..d6ce`; `call 0x180032e20` at `d6f0`. | The DLL’s catalog routine calls factory with zero, then rewrites the copied graph before returning it. |
| Rewriter | `host-rewrite.txt`, especially `0x180033131` (`cmp ... '_fp8'`) and `0x18003317c..183` (write `_fp8\0`); `REWRITTEN_NAMES.json`. | The testable rule is substring-presence, not suffix-only: retain a name containing `_fp8`, otherwise append it. All 152 historical layer names satisfy that recorded transformation. |
| Manager handoff | `host-manager-selection.txt`: catalog call at `20fae`; ownership transfer of returned vector at `20fb3..20feb`; per-resource matching at `21086..21094`. | The statically followed manager construction consumes the catalog return, rather than the factory’s temporary object. This is not a live call trace. |
| Resource flags | Literal resource table `0x1800b0d80`, bytes `+0x20..+0x22 = 01 01 01`; manager copies selected-resource bytes `[r15+0x20..22]` at `0x18002121d/225/22d` into its constructed descriptor. | The table bytes and the byte-for-byte copy are proven. Their higher-level semantics and values in a selected live object are **not** inferred from the historical factory object’s `00 00 00`. |
| Network initialization | `host-network-init.txt`: constructs table and calls `0x180036250` at `d984..d98c`; `host-network-init-layers.txt` calls each layer initializer at `0x180036290..62a6`. | The network initializes layer wrappers after its table setup. This proves code connectivity, not a captured selected network instance. |
| Split construction and selection | `host-block-split.txt` recognizes the split block and constructs the 0x180-byte object at `0x180040347..365`; Split vtable +56 is `0x18006d710`.  `host-split-init.txt:d82e..d844` chooses names by `_fp8` presence. | The rewritten block23/layer0 name selects literal `0x1800ba458` (`...inpview_512_fp8`); the unrewritten alternative is `0x1800ba480` (`...inpview_512`). |

The resource-table flags are deliberately kept separate from the name selector: the inspected selector tests the layer name; it does not read those three manager-copied bytes in this retained range.  Conversely, a historical `00 00 00` byte triple does not undo the catalog’s explicit rewrite.

## Weight format and the former `+524288` conflict

`WEIGHT_SPANS.json` identifies `block23.layer0.layer` as one record:

* source `WEIGHTS_HT.bin[6727901:7252189]`, size and reserved size **524288**;
* serialized pool offset `6733312`;
* SHA-256 `63399444cd1c361a295167f7958cc707d8e88ec363da1cbf2ada632dcc741df5`.

`block23-layer0-serialized.bin` is an exact copy of precisely that closed source interval.  Verification rejects a read crossing its end.  No adjacent record is concatenated, and no F16 conversion output is supplied or asserted.

The two retained PTX entries are alternatives selected by the host name branch, not a single entry with interchangeable weight storage:

| Host-selected name | PTX entry | Slab consequence |
|---|---|---|
| `...inpview_512_fp8` | `cc_split_swin_16h_ffwd_inpview_512_fp8` | Its preserved static weight forms cover exactly `[0,524288)`; the pinned slab is sufficient for that entry’s layer0 loads. |
| `...inpview_512` | `cc_split_swin_16h_ffwd_inpview_512` | It loads parameter `+16` into `%rd249` and at source line 2514 forms `%rd136 = %rd249 + ... + 524288`, then performs a 16-byte load. A caller of this alternative must provide a different/larger compatible weight allocation. |

Therefore the F16 entry’s second-stage `+524288` is not an “original bug” and does not license reading the next serialized tensor.  It is evidence that the F16 alternative has a different required slab layout/extent.  The resolved static catalog route instead reaches the FP8 alternative, whose proven byte domain is the one exact record.  A live runtime could still select a different catalog/network/descriptor; that has not been observed here.

## Conditional base / tilesync dispatch

For `inpview`, init creates the base function in state slot `+0x20` and sets the initialized byte at `+0x18` (`0x18006d871..d8b7`).  With `inpview` present it creates exactly one additional function in `+0x28` (`d8cd..d8ec`): the FP8/F16 tilesync literal chosen by the same `_fp8` test.  Constructor-zero slots `+0x30` and `+0x38` are not initialized on this branch.

Forward `0x18006c7f0` does **not** have an unconditional tilesync launch:

1. `c886..c8be` obtains optional candidates only when each supplied handle range has at least two entries; the candidate pointers are the second entries.  Call them `I` (first range) and `O` (second range).
2. `c8c8` reads the separate global byte at `0x1800e06d0`.  If it is zero, it immediately falls through to base.
3. With that byte nonzero and at least one candidate non-null, `c8e1..c8f3` computes the slot index.  For `I=0,O!=0` it is 1 (`+0x28`, tilesync).  For `I!=0` (whether or not `O` exists) it is 2 (`+0x30`), which is null for the inpview initialization; `c8f8..c928` then falls back to base.  With neither candidate it also uses base.
4. The eventual backend call is at `c97d..c989`; the chosen handle is placed in `%r11`/`RDX` before that call.  The optional-pointer fields in the launch aggregate are only populated when the non-base handle survived the null check.

So the statically proven inpview truth table is:

| sync global | I second entry | O second entry | handle |
|---:|---:|---:|---|
| 0 | any | any | base |
| nonzero | 0 | 0 | base |
| nonzero | 0 | nonzero | tilesync (`+0x28`) |
| nonzero | nonzero | 0/nonzero | attempted `+0x30` (null), then base |

The archived existing observer trace contains function **creation** records only for these relevant names and has zero `phase=before_original` submissions.  Its two 264-byte argument blobs have `aggregate192=1`; that offset is neither read by the 56-byte Split16H non-tilesync PTX ABI nor evidence for `0x1800e06d0`, `I`, `O`, the selected handle, block23, or a global mode.  It is therefore excluded from this truth table and from all live-selection claims.

## Immutable pin inventory

| Artifact | SHA-256 |
|---|---|
| Pre-resume archive `../nr-resume-main-20260912/PRE_RESUME_PARTIALS.tar.gz` | `b0f45cd91772b583439dc49abb8ffbc51fb20040b36819e4056f1fa0a8260af6` |
| DLL `nvngx_dlssnr.dll` (165,840,496 bytes) | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` |
| Historical factory log | `1b18a3dc66175c312d4149cac6b625ea12c4c119a09369d522bd05628a236cde` |
| Historical factory object | `0b5417ba89999d67a3cbca4b95dfa40bb0b9746b5c7c49369ee10ad4bbb68d83` |
| Historical weights | `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4` |
| Exact block23/layer0 serialized record | `63399444cd1c361a295167f7958cc707d8e88ec363da1cbf2ada632dcc741df5` |
| FP8 entry PTX | `0ba5a3da34dbf89de7be7f280e373d6b02c1a7f4fee7cdb0d071e40acb764bf0` |

`EVIDENCE.json` supplies the full source and native-range inventory (path, byte count, SHA-256); it is the machine-checked authoritative list rather than this abbreviated table.

## Verification and boundaries

Run only:

```sh
python -B reviews/nr-split16h-route-resolution-20260911/verify.py
```

The nine CPU-only tests rehash the resume archive, DLL ranges, all pinned original sources and captured argument blobs; re-read every retained native range from the DLL; verify 152 rewrites; check the exact inpview selector truth table; compare the closed 524288-byte record with its source span; and distinguish function creation from submission.  No GPU, Wine, PE execution, deployment, network access, or sibling-test writes were used.

**Not established:** a live selected block23 descriptor, live resource-flag values, the value of `0x1800e06d0` at launch, optional handle ranges, a tilesync submission, any runtime weight conversion/upload, or whole-block execution.  Those unknowns do not weaken the static catalog/name/selector/closed-slab claims above, but they prohibit an actual-runtime or whole-model completion claim.
