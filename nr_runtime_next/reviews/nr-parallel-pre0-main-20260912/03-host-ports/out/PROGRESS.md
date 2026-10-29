# Task C progress — complete, CPU/static only

## Completed

- Verified the independent DLL and nine other used allowed inputs against PACKET hashes.
- Proved ds output mapping: **O[1]→pre+216→graph port1**, **O[0]→pre+248→graph port0**.
- Proved aggregate origin **RSP+70=RBP−90**, exact dimension provenance and ds/non-ds branches.
- Followed network explicit edges, implicit previous-primary edge, N+110←T[][0], layer ordered gather, output-prefix copies and actual vtable dispatch.
- Separately composed historical graph0 port1→post70 skip with current post I0→ABI0/I1→ABI8.
- Identified block1 **unshifted inpview** from current factory flags, builder branches, selector literal names and initializer/forward mechanics. FP8 suffix and base/tilesync dispatch remain conditional, not live guesses.
- Retained bounded pool-pointer provenance; did not infer native allocation extent, non-aliasing, lifetime, completion or neuron layouts.

## Exact task input paths read

Bootstrap:
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/PACKET.json`

Allowed evidence:
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/nvngx_dlssnr.dll`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/pre0.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/pre_inventory.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/old_pre_full_report.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/main_rejected_geometry.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/old_pre_binding_report.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/post_host_proof.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/outer_graph.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/old_routing_report.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/pe_readonly.py`

No historical external paths quoted inside these reports were opened. `pre_code_index.txt`, `pre_identity.json`, and `pre_slab.bin` were not read. Generated evidence/scripts under this task's out directory were read back for analysis/verification; they are not additional external inputs.

## Collection and verification

All commands used `python -B`; all paths and outputs were under this task's out directory. Supplied helper was imported with its SRC assignment patched in memory to the independent input DLL. Its `__main__` was never run.

Collection sequence:
1. `collect.py initial`, `collect.py graph`.
2. `scan_once.py`: single bounded .text scan; `ins.id==0` skipped before operands.
3. `collect.py window layer_dispatch 0x18003fdc0 0x180040000`.
4. `collect.py window network_output_setup 0x18003e4e0 0x18003e820`.
5. `collect.py window substring_helper 0x18003cb80 0x18003cc77`.
6. `collect_stage2.py`, `collect_stage3.py`, `collect_stage4.py`, `collect_stage5.py`, `collect_final.py`.
7. `build_proof.py`: raw-byte checks and symbolic tests only, no extra scans/disassembly.

Budget consumed: **one 699,904-byte text scan, 32 windows totaling23,145 bytes**. Each window≤4,096 bytes. Individually addressed rdata slices and pdata records are in HOST_PORT_PROOF.json. No more disassembly windows remain; do not rerun collection into this ledger.

Verification: **PASS**, every retained text/rdata/pdata slice matches this DLL, ten allowed-input identities match PACKET,176 overlapping old post instruction witnesses match freshly read bytes, and symbolic route/dimension/vtable assertions pass. `verification.log` and `verification.json` retain results. Initial clipped tails remain in raw evidence and have explicit untrusted-suffix annotations in the final proof; none is a claim witness. Pdata split functions were handled with separately bounded continuation windows.

No failed script invocation occurred. Intermediate logs are retained. No native execution, DLL loading, Wine, GPU/CUDA, network, input writes/chmod, recursive discovery, nested agents or original NN prediction.

## Remaining uncertainty

- Current live graph, actual handle identities, FP8 suffix and base versus inpview_tilesync selection.
- Full allocation sizes/slot values, aliasing, lifetime/reuse, and device publication/completion.
- Parent/source-worker C32/planar-A neuron-byte proofs and numerical consumer compatibility.
- Full shape-inference equality across pre high/low and post/block1 dimensions.
- Runtime augmentation from the current post builder's two-entry gather to the historical five-entry descriptor.

Task-requested model is recorded exactly as PACKET: openai-codex/gpt-6-astra, xhigh. The worker cannot independently attest serving configuration.
