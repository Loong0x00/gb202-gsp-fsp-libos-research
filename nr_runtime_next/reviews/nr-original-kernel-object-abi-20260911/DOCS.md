# Authoritative source map

Full original responses and human-readable HTMLParser text are in `evidence/docs/`. Line references below refer to `.txt` files (not HTML). `network.json` stores URL, response SHA-256, bytes, fetch timestamp, and headers. `samples-network.json` pins the two NVIDIA sample files to immutable revision `5443602d89ed99aede2e4b7bf329daddeadb320e`. To re-fetch: `python3 reviews/nr-original-kernel-object-abi-20260911/fetch_docs.py` (live manuals can change).

## Object creation and supported device API inputs

* [Driver Surface Object Management](https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__SURFOBJECT.html): `driver-surface.txt:193–253`, signature and description of `cuSurfObjectCreate`; creates/returns a surface object, `CU_RESOURCE_TYPE_ARRAY`, valid CUDA array, flags zero, opaque object; cross-reference `cudaCreateSurfaceObject`.
* [Runtime Surface Object Management](https://docs.nvidia.com/cuda/cuda-runtime-api/group__CUDART__SURFACE__OBJECT.html): `runtime-surface.txt:193–246`, matching opaque-object creation description and reciprocal `cuSurfObjectCreate` reference.
* [Driver Texture Object Management](https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__TEXOBJECT.html): `driver-texture.txt:221–295`, `cuTexObjectCreate` signature and returned texture object/resource/sampling model. `:417–468` documents point filtering, normalized coordinates and clamp. Search the saved page for its `cudaCreateTextureObject` cross-reference.
* [Runtime Texture Object Management](https://docs.nvidia.com/cuda/cuda-runtime-api/group__CUDART__TEXTURE__OBJECT.html): corresponding `cudaTextureObject_t` object creation page and reciprocal Driver cross-reference.
* [Driver versus Runtime APIs](https://docs.nvidia.com/cuda/cuda-driver-api/driver-vs-runtime-api.html): `driver-api-interop.txt:22`, “The driver and runtime APIs are very similar and can for the most part be used interchangeably.” This is **not** an unconditional guarantee about every opaque bit or raw mode.
* [C++ guide §21.4, interoperability](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#interoperability-between-runtime-and-driver-apis): `programming-guide.txt:62737–62795`, mixing APIs and sharing the current context. The explicit pointer-cast example here is about device memory, not a license to reinterpret object handles.
* [C++ guide §10.9.1.4, surf2Dwrite](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#surf2dwrite): `programming-guide.txt:23763–23792`, `surf2Dwrite(T data, cudaSurfaceObject_t surfObj, int x, int y, ...)`.
* [C++ guide §10.8.1.5, tex2D](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#tex2d): `programming-guide.txt:22599–22624`, `T tex2D(cudaTextureObject_t texObj, float x, float y)`.
* C++ guide §13.3.1.6.2, Textures and Surfaces: `programming-guide.txt:45286–45291`: “texture and surface objects created from the host may be used and passed around freely on the device.”
* [NVIDIA Driver texture host sample](https://github.com/NVIDIA/cuda-samples/blob/5443602d89ed99aede2e4b7bf329daddeadb320e/cpp/0_Introduction/simpleTextureDrv/simpleTextureDrv.cpp#L169-L197): saved `simpleTextureDrv.cpp:169–197`: genuine `CUtexObject`, `cuTexObjectCreate`, then `&TexObject` passed to `cuLaunchKernel`.
* [Its CUDA device kernel](https://github.com/NVIDIA/cuda-samples/blob/5443602d89ed99aede2e4b7bf329daddeadb320e/cpp/0_Introduction/simpleTextureDrv/simpleTexture_kernel.cu#L36-L51): saved `simpleTexture_kernel.cu:36–51`: `CUtexObject tex` directly passed to `tex2D<float>` without conversion. This concretely connects Driver-created texture objects to documented C++ device inputs; it does **not** establish raw-mode high-word semantics.

The API-level evidence is the common object model, paired create functions/interoperability, documented device inputs, and NVIDIA's direct Driver texture example. Header typedef width is not used as a standalone argument. No consulted manual states an invariant `CUtexObject >> 32 == 0`; a published raw-handle guarantee was not found.

## HALF arrays, surface addressing, formatted conversion

* [Driver cuArray3DCreate / Memory Management](https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__MEM.html): `driver-array.txt:1190–1509`, descriptor, `CU_AD_FORMAT_HALF` (`:1274`), channel count 1/2/4 (`:1367–1368`), surface-load/store flag (`:1374`), 2D extent table (`:1420`), and explicit HALF / four-channel array example (`:1491–1509`). Resource-type support is documented; successful actual allocation has not been measured.
* [C++ guide CUDA Arrays](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#cuda-arrays): `programming-guide.txt:11021–11028`, 1/2/4 components including 16-bit floats, and array access through texture or surface operations. This avoids inferring formatted HALF support solely from a numeric enum.
* [C++ guide Surface Object API](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#surface-object-api): `programming-guide.txt:10504–10564`, surface-capable array flag and **byte** X addressing for documented C++ surface functions. Its two-dimensional example explicitly says Y's byte offset is calculated internally from line pitch. “Byte coordinates x and y” in the short function description must not be misread as multiplying Y by pixel size.
* C++ guide §6.2.14.1.2, 16-Bit Floating-Point Textures: `programming-guide.txt:10309–10326`, HALF components promoted to FP32 before filtering. The old guide's surrounding historical wording about C++ half types is not used as an up-to-date type-system claim.
* [PTX ISA §9.7.13.2, sust](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#surface-instructions-sust): `ptx.txt:32316–32495`. Exact normative distinctions:
  * `sust.b` “performs an unformatted store of binary data”; lowest coordinate is an unscaled **byte offset**, transfer size follows source operand.
  * `sust.p` “performs a formatted store of a vector of 32-bit data values to a surface sample”; R,G,B,A mapping; lowest coordinate is a **sample offset rather than a byte offset**.
  * FLOAT (also UNORM/SNORM) source interpretation is `.f32`, then conversion to surface sample format.
  * `.zero` “drops stores to out-of-bounds addresses”.
  * Indirect `.u64` surfref operand support is documented, but no public bit layout of CUDA object handles is given here.
* PTX §5.3, opaque texture/sampler/surface types: `ptx.txt:3798–3848`. Layout/size hidden; pointers can be passed and used by texture/surface instructions, not ordinary `ld`/`st` or pointer arithmetic. This is why no host descriptor reinterpretation is proposed.

No quoted rule specifies the exact original formatted FP32-to-HALF rounding or driver population of hidden c0 descriptors. Those remain runtime/ABI boundaries, not facts established by compiler acceptance.
