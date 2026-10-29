# Reproduction order and frozen-artifact cautions

The authoritative inputs are `DATASET_MANIFEST.json`, `TRAINING_CASE_FILTER.json`, and `IDENTITY_EXCLUSIONS.json`. Do not rerun `prepare_dataset.py` as a discovery scan and assume it reproduces the frozen cohort.

CPU verification / corrected analysis order:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B verify_captures.py
PYTHONDONTWRITEBYTECODE=1 python3 -B extract_features.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_probes.py
PYTHONDONTWRITEBYTECODE=1 python3 -B bootstrap_metrics.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_logistic.py
PYTHONDONTWRITEBYTECODE=1 python3 -B bootstrap_logistic.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_baseline_ablations.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_cross_domain.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_open_subset.py
PYTHONDONTWRITEBYTECODE=1 python3 -B train_low_capacity.py
PYTHONDONTWRITEBYTECODE=1 python3 -B bootstrap_low_capacity.py
```

The full pipeline permutation nulls are sharded by layer. Run `permutation_pipeline_worker.py` and `lowcap_permutation_worker.py` for all 13 layer names, then `aggregate_pipeline_permutation.py` and `aggregate_lowcap_permutation.py` respectively.

`permutation_null.py` and `train_logistic_refit.py` are preserved first-attempt analyses and must not be used to regenerate the corrected headline files. Their pre-correction outputs are retained under `results/PRE_IDENTITY_AUDIT/`.

`aggregate_interventions.py` verifies the already-generated intervention outputs. Re-executing native DLL validation requires the separate guarded GPU approval protocol; the original native command log is not present in this directory and no native rerun is implied here.
