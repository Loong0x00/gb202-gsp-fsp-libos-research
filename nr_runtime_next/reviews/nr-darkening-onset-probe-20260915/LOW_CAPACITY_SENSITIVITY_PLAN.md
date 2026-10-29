# Post-audit low-capacity sensitivity plan (frozen before execution)

Concern: channel-wise Ridge is linear and strongly regularized, but some boundaries expose more raw columns than source groups. This secondary analysis tests whether the layer curve survives an explicitly capped unsupervised representation.

- Use the identity-corrected cases only.
- Fit PCA on train activation cells only, without labels, separately per boundary.
- Keep at most 32 PCs (all channels when fewer). Then construct direct/local-mean/global-mean features, for at most 98 columns including coordinates.
- Keep the registered full image baseline unchanged.
- Select Ridge alpha using validation source groups only; freeze test predictions before scoring.
- Report the same locked-test metrics and source-group bootstrap deltas.
- This is a post-primary robustness analysis and cannot move the preregistered onset earlier. If it disagrees, the disagreement must be reported.
