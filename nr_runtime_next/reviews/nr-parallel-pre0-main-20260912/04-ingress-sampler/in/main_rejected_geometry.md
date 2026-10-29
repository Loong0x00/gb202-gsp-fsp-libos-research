# Main receipt — worker finished; geometric claims are not accepted wholesale

The worker report is retained verbatim. No new preblock NN prediction has been made, so these are source-review corrections before any numerical model freeze, not repairs to a failed prediction.

## Rejected factor-of-four composition

Worker defines `Ht=H//4, Wt=W//4` (tile counts), then incorrectly states post70 pixel dimensions `h=Ht,w=Wt` and uses another `floor(Wt/4)` in the pixel→tile-neuron equation.

From the source's own skip store `512*(tile_y*Wt+tile_x)+16*lane`, the correct high-pixel C32 equation for the admitted divisible-by4 geometry is:

```
m = 16*((Y//4)*(W//4) + X//4) + 4*(Y%4) + X%4
skip byte = c_offset(m,c,32)
post70 high h=H, w=W, NOT Ht,Wt
```

For H=W128, tile counts are32x32, while the high skip is128x128x32 (524288 bytes). The source's stride is512 bytes per4x4 tile. Dividing the tile count again would incorrectly shrink dimensions and row strides. This directly contradicts the worker's proposed compatibility condition; no such condition is used in Main's model.

Physical high-C32 compatibility still needs an independent actual final-neuron→byte map and separate host port/allocation binding. PTX store order/offset is not graph port order. The two-plane +248 layout must also receive a neuron/channel map before labelling it canonicalC versus planarA; a32-channel count alone is insufficient.

## Source line and reduction checks

- First barrier is source line590, **not ~203** (line203 is noise hash arithmetic). Second is1097. Conditional padding barrier is15012.
- A further essential fork is independently visible: final F16 MMA D `%r3402/%r3410` are produced at12452/12480; skip FP8 conversions read them at12508/12532, while downsample selectors read the original unquantized registers at14426/14427. Downsampling must NOT decode/reduce the already-quantized skip buffer.
- Balanced downsample half tree is confirmed at14451/14455/14459/14469: `r5086=r5082+r5083`, `r5087=r5084+r5085`, `r5089=r5086+r5087`, `r5147=r5089*half(0.25)`, each source half operation separately rounded. Its four source-neuron selectors remain to be independently mapped.
- Main has separately matched the canonical current catalogue slice to this older source after `.visible ` and edge-whitespace normalization: current6459op264ABI SHA7ef1fb2650817e1b45b44104e06fac39d9d26c3a2afcd042f915681167a2bba8. See `../nr-pre1h0-main-20260912/SOURCE_AND_WEIGHT_IDENTITY.json`.

Worker is now complete; no active subagent remains. Main continues CPU/static analysis. Native sampler/noise/MMA/counters, full producer closure and fullNR remain open.
