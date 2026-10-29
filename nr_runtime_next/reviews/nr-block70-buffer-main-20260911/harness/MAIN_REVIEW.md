# Main harness completion fix

First actual GPU run180750 produced four exact-input-before and fenced-output-after captures, but failed harness assertion requiring sampled runtime last_completed_frame==last submitted frame. Frozen pipeline.cpp Submitted intentionally retains first pending completion sample and can skip newer samples until worker drains. This is NOT an NR execution failure.

Main reviewed copy accepts nonzero sampled completion frame in[2,frames+1], while KEEPING exact pass*frame evaluate counts, submission counts, distinct handles, every BEFORE bit-identical to input, and each output map gated by its exact actual D3D12 fence. Final frame pixels have direct harness-fence proof, not invented runtime sample proof. No runtime change or extra empty submissions. Original failed run preserved.
