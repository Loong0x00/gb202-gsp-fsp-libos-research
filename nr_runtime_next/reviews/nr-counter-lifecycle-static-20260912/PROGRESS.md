# Progress

Concrete source fact established: `cc_cb_clear.ptx` computes `i = ctaid.x * ntid.x + tid.x`, returns when `i >= param_0+8`, and otherwise stores 32-bit `-1` at `param_0 + 4*i`.
