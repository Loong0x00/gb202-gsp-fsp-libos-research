# Frozen suffix intervention plan (after probe association, before interventions)

This is a causal follow-up, not a redefinition of the primary onset criterion. The primary locked-test predictions already exist. No intervention result has been inspected as of this freeze.

- Boundaries: `block22_low` (first statistically accepted captured boundary) and `block38` (largest encoder/ViT transition).
- Direction: derive only from each train-fitted Ridge checkpoint. Reconstruct the raw-activation gradient for a spatially uniform perturbation from the direct, 3x3-local-mean, and global-mean coefficient thirds. Express it in direct-channel standard-deviation coordinates and normalize to RMS 1.
- Perturbation: add `+0.10` or `-0.10` channel SD uniformly over the logical square used by the registered probe (block22 first 16x16; block38 valid first 8x8). Re-encode to E4M3FN and run the unmodified transparent suffix. Positive means the Ridge-predicted `delta_ev` direction.
- Negative control: fixed-seed Gaussian direction orthogonal to the fitted effective direction in standardized coordinates, identical RMS, with both signs.
- Held-out cases: lexicographically first primary locked-test case in each available category: real=`commons-012`, stylized=`fluent-003`, game=`game-hsr-local`, material=`material-ciaccona-diffuse-preview`. This selection does not use targets or predictions.
- For every case/layer, the unmodified suffix must reproduce `output.rgba32f` byte-for-byte before an intervention is accepted.
- Primary signed endpoint: half of the `+/-` contrast in mean output luminance EV over finite, unsaturated baseline pixels (`0.02 < Y < 0.90`). Secondary: full-frame mean-luminance EV.
- Acceptance for a boundary: target direction has the preregistered positive sign in at least 3/4 source groups and its median absolute directional contrast exceeds the matched orthogonal control. This establishes that the encoded direction is causally upstream of output movement; it does not prove that this exact block created the information.
- No amplitude adjustment or failed-case removal is permitted. All failures and raw intervention outputs are retained.
