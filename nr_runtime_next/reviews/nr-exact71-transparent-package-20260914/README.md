# Independent transparent NR71 CPU model

`model.ExactNR71H512()` loads the bundled pinned checkpoint and exposes one 71-block H512 forward. The package contains no model DLL, CUBIN, PTX, VM/interpreter, Torch/community runtime, or opaque learned-kernel binary; execution is inspectable Python/NumPy. `verify_pure.py` denies reads outside this package and all I/O during forward. F32 FMA boundaries use bundled integer/Fraction RN-even code rather than loading libm.

Interfaces:

- `forward(args264, sampler=...)`: first-counter/absent-history pre0.
- `forward_temporal(args264, state=..., sampler=..., approx=...)`: recovered actual frontend T1 history + T2 motion + optional T4 mask family; returns the explicit counter transition.
- `textures=LiveTextures(...)`, `post_config=FrameConfig(...)`, `post_approx=...`: recovered block70 A/B/C texture/history branch. Texture values remain a strict raw-F32 callback because native sampler precision/resource contents are external inputs, not guessed software filtering.
- `probes={name: callback}` and `keep_blocks=True`: named tensor/boundary inspection.
- `logical_weights()`: read-only 649 logical F16/F32 tensors; zero opaque/unsupported tensors.

Closed static geometry is pre/skip H512 → encoder H256/H128/H64/H32 → split H16 → pool/ViT H8/N64 → decoder H16/H32/H64/H128/H256 → H512. Correct skips are `0→70`, `4→66`, `8→62`, `14→56`, `22→48`; block30 retained output also feeds block39.

`PURE_PACKAGE_RESULT.json` records the independent no-I/O run. The exact logical null-texture output for its fixed fixture is SHA-256 `45a430ebbcd69dc0be5966e6e5fbcce9148bdbf380124c2ea1906293f0417a6b` (4,194,304 bytes).

Evidence boundary: original-PTX CPU comparisons and preserved failure logs live in sibling review evidence and are not runtime dependencies. Native GPU/TensorCore/APPROX/sampler/formatted-surface parity, opaque resource synchronization, and the external output→history copy are not claimed by this CPU model.
