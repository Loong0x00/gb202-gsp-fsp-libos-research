# Complete expand tensor reference report

## Result

The new CPU/static operator covers `M=128, K=1024, N=4096` and all 32 CTA-x
groups. It has source-derived logical A/B offsets, an inspectable literal
fragment/tail physical-output map, float64 K=32 GEMMs with RN-half after every
block, source constants `ab28/3728/3b28`, and finite-only E4M3 packing.

The CTA-x conclusion is mapped, not inferred from a dense CTA-0 result:
source launch parameters make `r58=1`, hence `r2=cx`; the remainder makes
`r3=0`. `r6=(128*cx)|(64*oddwarp)` combines disjoint bit fields. Therefore B
and logical output n shift by `128*cx`, while physical output shifts by
`2048*cx`. The expanded `cta_slots` map has 16,384 bytes per CTA and exactly
covers all bytes 0 through 524,287 with no overlaps or holes.

The implementation rejects E4M3 NaNs and non-finite f16 carry/tail values;
it never uses the old silent NaN-to-126 behavior. This is a finite-domain
reference, not an unproved source-Inf behavior emulation.

## Scope boundary

No GPU, Wine, native execution, autograd, PTX downgrade, or whole-model/native
MMA equivalence claim is made. The saved literal CPU runner is used only by an
optional read-only first/last-CTA comparison test. Earlier partial/failed
reports are untouched.
