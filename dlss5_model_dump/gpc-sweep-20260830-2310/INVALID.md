# Invalid timing interpretation

Do not use `results.csv` in this directory as inference latency.

The CUDA events and stream synchronization were placed on the caller's explicit
Green Context stream, while NGX submitted the model to an internal/default
stream. The resulting approximately 1.9 ms numbers measured only submission-side
work. The output copy later performed the missing synchronization.

The corrected sweep uses `cuCtxSynchronize` and is stored in
`../gpc-sweep-contextsync-20260830-2315/`.
