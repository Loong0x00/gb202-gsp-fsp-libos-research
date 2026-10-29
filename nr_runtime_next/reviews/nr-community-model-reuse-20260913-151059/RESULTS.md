# Community deep-recovery triage — pinned source review

Date:2026-09-13. This is a bounded source/repository review, not execution of community code/weights, not a security audit, and not a claim that moving branch heads will remain unchanged. GitHub source is pinned where possible; Hugging Face revision is pinned through its model API. `FETCH_01/02.json` preserve downloaded byte identities. One initial parallel Git tree request returned HTTP504; its error file is retained and only Daniel's tree was retried. No model/DLL/GPU/game/deployment action occurred.

## Short answer

The user's recollection is right: many public projects are wrappers/hosts, but **only about two public lines currently expose substantial independent model reconstruction source**:

1. **iamwavecut/MLX-DLSS**, commit `0ca2deab092fe6f3e331bf4f616271dbc64521d0`: complete71-block PyTorch/MLX/Metal graph, logical weight converter, first-frame and temporal tooling. Apache-2.0 source; extracted weights retain vendor terms.
2. **taowen's DLSS5Graph line**, Git commit `59a414cfd09676f3a09ff042330b5dc8407ebc79` and related HF `dlss5-onnx` revision `d3c44c4ea314d03ea7540cfc9ac4411f9dcfba28`: complete71-block semantic/static graph plus local native probes; the published ONNX is fixed frame0/static256, not complete temporal DLL.

A third deep runtime line exists but is not source-reusable from GitHub:

- **danielblnc/DLSS-NR-on-AMD**, commit `057c87324bfd8131c45c6b7e7de7d22ab46844d5`, states a ground-up HIP/runtime implementation and released setup binary. Current public tree contains only README/LICENSE/funding/third-party text—**no HIP/network/runtime source**. It may be valuable as a runnable black-box oracle on AMD, but not code we can audit/merge today.
- `0x-punk/DLSS-NR-on-AMD-DUMP-` is two Markdown analyses of that external runtime, with contradictory counts/sizes noted in earlier web review; useful leads, not independent executable/source parity evidence.

OptiScaler forks, Feeder, neural-upstream, DLSS5VKLayer, Autopilot and similar projects chiefly solve host injection, codec, ordering, controls or use the original DLL. They matter for task64 integration but do not replace full model recovery.

## MLX-DLSS: high-value reuse candidate, not a parity oracle

### What is real and useful

Pinned `python/mlxdlss/model.py` is a transparent `torch.nn.Module`, no ctypes/DLL call or custom binary wrapper. It has explicit E4M3 publication, half operations, approximate softmax/cosine rules, graph transitions and a complete `NeuralRenderingModel.forward`. The converter emits logical safetensors; repository golden-bundle tools can serialize inputs, run the port and compare outputs. These directly align with the user's dense input→output validation strategy.

Its current graph independently agrees with many recovered corrections already established locally:71 blocks; block0 attention then unquantized pool; raw/published residual forks; DS at4/8/14/22; split23–30; global31–38; bridge39; decoder48/56/62/66; block0 published skip into70; nearest upsample; fragment-swizzled attention bias; split-family grouped FFNs; PCG noise details.

The project reports native NR MAE≈0.0041–0.0048 on five crops—not byte equality. Its64-frame temporal test repeats one256×256 image with zero motion/depth1/no jitter and reports MAE0.0054/max0.12; real motion/jitter/disocclusion/masks remain uncaptured. Therefore it is a **runnable baseline/accelerator**, not the final independent equivalence answer.

### Concrete local discrepancy found before reuse

Pinned MLX `forward` appends `skips=[value]` **after blocks1–3**, then DS4 and later passes `skips[0]` to decoder66. Our independently recovered graph/source evidence says decoder66 secondary/skip comes from **block4 output1**, the high C32 result, not block3. In our exact same default CPU prefix, block3 and block4-high are both131072B C32 but differ in **111680 bytes** (`MLX_SKIP_CANDIDATE_DIFFERENCE.json`); hashes de906e9e... andb2430c8b.... This is not an abstract naming issue.

By contrast, taowen graph explicitly captures `x,skip1=down32_64(x)` and feeds `skip1` to up64_32 block66, matching our routing. MLX's later `full_resolution_skip=block0_output` into70 matches our independently checked0→70 skip route. So MLX cannot be accepted wholesale; the66 skip should be patched/tested in an isolated adapter, not silently folded into our sealed model.

Other differences needing dense A/B, not assumptions: MLX's high-level `average_pool2` and GEMM rounding versus our per-half ordered pool and K32 carry boundaries; global attention approximation; block39; first-front exact features; history/control preprocessing. Its own comment warns chunk-size BLAS can cause rare E4M3 flips.

## taowen graph/ONNX: useful second implementation and cross-check

Pinned source distinguishes:
- native carrier using original CUBIN/runtime (only claimed bit-exact path);
- semantic71-block `DLSS5Graph`, incomplete private front producer;
- portable distilled approximation, not a clone.

Related HF ONNX claims a complete real-weight71-block **fixed256×256 frame0/static path**,145,755,691 parameters, input/output float32 linearRGB. Reference ONNX and its PyTorch graph reportedly matched exactly on four examples. That validates export consistency, **not vendor DLL parity**. The static wrapper fixes current color/history fallback, color scale.125, zero scalars/aux features and reference RGB post; no complete temporal ABI.

Its documentation closely matches several of our hard-won findings: residual coefficient side; QK/B fragment layouts; C32 down offset0x50b0=20656; unquantized fused residual before pooling; explicit FP8 boundaries; pre noise; block0/post skip; ViT Q gain/order. It also reports local native probes through block22 and exact/near-exact isolated cases. This is valuable for filling our existing 4H/VIT graph quickly, but some source is under a repository with no detected license file; copying code requires legal review. We can compare equations/results without treating unlicensed code as mergeable.

## Recommended shortcut and acceptance gate

### Immediate

1. Build an isolated **community baseline adapter** around pinned MLX logical weights/model. Do not modify sealed recovered components.
2. Correct the block66 skip only in an explicit candidate branch and add exact graph-edge assertion.
3. Feed deterministic dense model-input tensors: zeros, constants, impulses, gradients, alternating signs and seeded random finite values. Capture all final outputs and selected stage boundaries.
4. Compare three implementations separately: our recovered reference, patched/unpatched MLX, and taowen static graph where the contract aligns. A/B outputs equal→promote that graph section; mismatch→bisect first block. Never conflate port↔port agreement with NVIDIA parity.
5. For vendor parity, use original DLL/CUBIN captures as oracle under a fresh gated GPU experiment. Compare complete buffers; do not default to MAE-only. Temporal tests require identical initial state and input sequences.

### What this changes

We should stop reconstructing every already-public high-level graph edge from scratch. MLX gives a runnable whole-graph scaffold and golden-bundle format; taowen provides a second graph and native-probe evidence. Our strongest unique value is exact 310.8 source/weight/layout corrections, original CPU instruction comparisons, graph/host routing, and native primitive constraints. Combine them through dense differential testing.

### What this does not change

No community project presently establishes a redistributable, drop-in, bit-exact, complete temporal NVIDIA replacement. AMD runtime is closed-source here. MLX reports approximate NVIDIA agreement; taowen's independent graph has incomplete front/temporal paths; ONNX is static frame0. Community source cannot by itself close native sampler/TC/visibility, actual game resources, task64 host deployment or cross-frame parity.

## Local evidence paths

- `iamwavecut__MLX-DLSS/PIN.json`, source README/recovery/model/golden tools.
- `taowen__dlss5-as-inpainting/PIN.json`, source README/graph/numerics/blocks.
- `taowen__dlss5-onnx/PIN.json`, pinned README/docs/graph/static/numerics.
- `danielblnc__DLSS-NR-on-AMD/PIN.json` and README.
- `0x-punk__DLSS-NR-on-AMD-DUMP-/PIN.json` and reports.
- `MLX_SKIP_CANDIDATE_DIFFERENCE.json`, `FETCH_01.json`, `FETCH_02.json`.
