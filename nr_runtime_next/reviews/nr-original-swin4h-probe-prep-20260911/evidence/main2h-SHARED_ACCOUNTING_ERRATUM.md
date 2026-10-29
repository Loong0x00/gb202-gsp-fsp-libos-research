# Original 2h shared-memory accounting: independent correction

The preparation correctly reported **original ELF/SASS shared extent5120**, PTX user declaration4096 and SASS user base1024. The operational assumption that `CU_FUNC_ATTRIBUTE_SHARED_SIZE_BYTES` must equal the entire ELF extent was not established and proved wrong in this environment. Main preserves the original preparation and first rejected run rather than rewriting them.

## Evidence sequence

1. **191319**, load/query only. Untouched original ELF loads, exact function resolves, all CUDA calls and normal drain/unload/destroy return0. Driver reports function shared4096, not5120. The strict gate rejects with host70 **before all caller allocations and launch**. Guardian was intentionally stopped by Main's error cleanup (exit−15); this is not a passed full Guardian run or a GPU launch failure.
2. Installed CUDA13.3 headers define separate function static-memory and device driver-reservation attributes (`/opt/cuda/include/cuda.h`, SHARED_SIZE_BYTES and RESERVED_SHARED_MEMORY_PER_BLOCK). Public API documentation: https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__TYPES.html . The generic static-size wording alone was not used as proof of this ELF accounting convention.
3. Main compiles **own independent `shared_accounting.cu`**, with exactly4096 bytes of source-declared static shared memory. Original NR PTX9.4 is not recompiled or changed. `cuobjdump` reports own witness ELF shared5120; its SASS independently contains user base0x400 plus cluster-CTA addressing, as in the original. Sources/disassembly/resource output retained. The witness is never launched.
4. **191601**, new load/query-only approval. Driver independently reports **original function4096, own witness function4096, device driver reservation1024**. Sum4096+1024 equals each5120-byte ELF extent. Both modules unload, context drains/destroys, all CUDA and full Guardian finish0. No caller CUDA buffer allocation or kernel in this run.
5. Main retains the actual5120-byte compiled footprint check as **function4096 + independently queried reservation1024**, with dynamicShared0 and no attribute setter. This is not shrinking the original shared section, requesting4096 dynamic bytes, deleting a prefix, or forcing a code path. **191747** separately approves and executes only the original kernel after these checks; own witness remains unlaunched.

The evidence supports this accounting interpretation on the current GPU/driver/compiler. Do not universalize1024 bytes or transplant2h/4h resource constants. Future kernels must derive their own original declared/user/compiled extents and query device reservation independently.

Unchanged ELF identity, matching attributes and output do **not** identify which embedded native/Mercury representation the driver selects. This experiment neither removes Mercury sections nor claims a recovered in-memory SASS dump.
