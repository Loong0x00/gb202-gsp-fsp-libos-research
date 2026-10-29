# Executed community reuse trial

## Weight conversion

Pinned MLX-DLSS commit `0ca2deab092fe6f3e331bf4f616271dbc64521d0` was reviewed as source. Its extractor is a pure PE-resource parser and safetensors writer; its logical converter uses NumPy/safetensors. Under a runtime audit blocking network, subprocess, exec and dlopen and restricting file access to the installed read-only DLL plus this output directory:

- source DLL SHA `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, version310.8.0.0;
- WEIGHTS_HT SHA `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`;
-153 packed tensors /147,683,778 payload bytes;
-649 decoded logical tensors;0 unsupported,0 opaque;
- logical file291,576,650B SHA `399d900614665918b4f4d51cea0eebc4d8a3a3752c3ab19847e9206f50f2d043`.

`WEIGHTS_RESULT.json` records it. The initial package import failure and too-strict lazy UTF-16 audit failure are preserved in separate logs; neither produced a model file. The third direct-module run passed without loading/executing the DLL.

Independent block1 crosscheck: all eight fields,16,449 elements, match our independently decoded immutable weights exactly after casting E4M3 values only to the community declaredfloat16 container. Single-head attention bias additionally requires explicit token-basis conversion: community fragment→raster plus our tile-token→raster;4096/4096 exact. Two rejected checker assumptions (raw NumPy container bytes; omitted token basis) remain logged/JSON. This validates converter/layout interoperability, not graph arithmetic.

## Same-matrix prefix comparison

Input is our exact recovered/default pre0 **128×128×16 half feature matrix**, reconstructed from all256 saved windows. The pinned community PyTorch implementation and logical weights were executed on CPU only.

Serial0→4 errors grow because the first mismatch already exists at the embedding and compounds. More diagnostic teacher-forced runs fed every block its **exact saved original-CPU predecessor matrix**:

|Stage|Exact fraction|MAE|max abs|
|---|---:|---:|---:|
|embedding float32|0.000414|0.00004140|0.0009615|
|embedding after simplehalf cast|0.999815|1.33e-8|0.0004883|
|block0 published|0.610668|0.009583|0.375|
|block1|0.883987|0.003417|0.5|
|block2|0.855339|0.008508|0.5|
|block3|0.817970|0.009853|1.0|
|block4 high|0.838173|0.007205|1.0|
|block4 low|0.813705|0.012661|1.0|

Thus community high-level PyTorch is **not output-identical** even on our already-verified prefix. The near-complete simplehalf embedding match still has97/524288 errors because ordinary BLAS accumulation is not exact one-K16 HMMA order. This is exactly why the community code is useful as graph scaffold but cannot replace the recovered numerical kernels. No tolerance was promoted to acceptance.

The first comparison script had a Main C-layout broadcasting bug before any block ran; the first teacher report compared unquantized block0 to published bytes. Both observer failures are preserved and corrected without changing community source/weights or our frozen outputs.

## Complete71-block graph-edge experiment

Pinned MLX graph retains skips **before** DS blocks; independent current graph/host/source evidence and taowen's graph retain DS high outputs from4/8/14/22 and feed them to66/62/56/48. Locally, original3 vs original4-high already differ111,680/131,072 bytes. `full_graph_candidate.py` changes only these four graph edges; pinned arithmetic remains unchanged.

Six complete64×64×16 dense float32 inputs were run through both71-block graphs with all forward I/O prohibited. Corrected candidate repeated exactly on every case. Upstream vs corrected outputs:

|Input|Exact output fraction|MAE|max abs|
|---|---:|---:|---:|
|zero|1.0|0|0|
|constant .125|0|0.14954|3.2591|
|two-channel impulse|0|0.003540|0.09327|
|gradient|0|0.60645|6.9212|
|alternating ±.25|0|0.08987|1.3614|
|seeded random half|0|0.42267|6.8989|

Zero is non-discriminating; every nonzero structured/random matrix distinguishes the graph choices across all16,384 output elements. This supports correcting the edges, but neither graph is an NVIDIA oracle. Vendor/native full-output comparison remains required.

## Decision

Reuse:
- MLX whole-graph scaffolding and logical converter;
- golden-bundle concepts and deterministic dense matrix suite;
- taowen graph as independent topology/equation crosscheck.

Do not reuse as-is:
- MLX ordinary GEMM/rounding as an exact numerical runtime;
- MLX pre-DS skip edges;
- taowen code for distribution without resolving its absent detected license;
- closed-source AMD runtime as source evidence.

Next engineering path: put our exact block implementations/policies behind this corrected whole-graph scaffold, then run dense final-output A/B. Only mismatching stages get detailed investigation. Native temporal/resource tests remain a separate gated phase.
