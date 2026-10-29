# Solver amendment — frozen before target construction/optimization

The only trainable mapping is linear: 32 frozen exact features to 3 RGB head channels. Instead of an iterative optimizer/step grid, solve the same weighted L2 objective by deterministic closed-form ridge regression. This removes optimizer and step-count ambiguity and does not expand trainable scope.

- Candidate lambdas fixed to `[1e-6,1e-5,1e-4,1e-3,1e-2,1e-1,1,10]`.
- For each leave-one-source-out fold, reserve heights64 and128 from the three training identities for lambda selection; all other heights plus background form the fit subset.
- Region weights are normalized per case before summation: background1, person4, warm-face additional8. Thus small subjects are not downweighted by pixel area.
- Select lambda by minimum validation weighted correction MSE, then refit on every scale of the three training identities.
- Train a delta from the original weight matrix and quantize the resulting 96 weights to FP16 before held-out evaluation.
