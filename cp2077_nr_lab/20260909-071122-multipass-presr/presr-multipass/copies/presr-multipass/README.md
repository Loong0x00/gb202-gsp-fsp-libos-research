# PRE-SR multipass benchmark pair

No deployment or GPU run was performed. `DLSS5_PRE_PASSES` is process-latched,
defaults to 1, and clamps to 1..3.

From the parent lab directory:

```bash
python3 run_case.py presr3 --presr nr \
  --service presr-multipass/copies/presr-multipass/01-dlss5-presr-service.addon64 \
  --router presr-multipass/copies/presr-multipass/00-dlss-ngx-router.addon64 \
  --env DLSS5_PRE_PASSES=3
```

See `MANIFEST.md` for architecture, ABI/count semantics, build checks, and
source provenance. Verify deployable files with `sha256sum -c SHA256SUMS`.
