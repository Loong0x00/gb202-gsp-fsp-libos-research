# First probe plan (frozen before dataset/model results)

Goal: locate the earliest NR71 representation carrying held-out predictive information about signed local luminance residual, and separate photometric/scale prediction from face/context information.

Primary target: continuous `delta_ev=log2((Yout+1e-4)/(Yin+1e-4))` on visible 512x512 output. Secondary target fixed before fitting: `delta_ev < -0.1`.

Primary low-capacity estimators: ridge regression and L2 logistic regression. A two-layer MLP is only a nonlinear sensitivity follow-up and cannot replace the linear primary result.

Candidate checkpoints: image-only photometric baseline; pre0; encoder skip4/skip14/block22; block30; block38; decoder48/66/69 when probe-specific capture is complete; learned head is a positive-control/tautological upper bound, not onset evidence.

Splits: grouped by source identity before any crop, scale, placement, or color transform. No derivative of one source may cross train/validation/test. Report real->anime, anime->real and face->same-color-nonface separately.

Controls: same-color/different-context paste pairs, scale sweep in a fixed 512 canvas, coordinate/padding baseline, and source RGB/local-gradient baseline. Do not select thresholds, layers or regularization on the held-out test groups.

Acceptance: preserve the first prediction and all failed candidates; report per-layer held-out R2, MAE(deltaEV), Spearman, AUROC/AUPRC/calibration for the fixed threshold, bootstrap confidence intervals by source group, and permutation nulls. A layer is called an onset only if it improves grouped held-out R2 and AUPRC over the image-only baseline with a positive group-bootstrap lower confidence bound, and the next later checkpoint replicates the direction.

Causal follow-up is separate: perturb only a predeclared probe direction at one boundary, run the transparent suffix, and require signed output movement on held-out identities without nonfinite values. No suffix intervention result will be inferred from correlation alone.
