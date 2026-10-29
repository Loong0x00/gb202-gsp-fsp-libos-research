# CPU-only original-kernel object-ABI review

**Keep blocked.** Surface SUST low32 input convention now has a documented CUDA C++ compiler witness. Original raw TEX consumes a uniform pair from the complete object; normal `tex2D<float4>` supplies `{low32,0}` instead. NVIDIA nvdisasm liveness confirms both texture registers are used. No documented Driver handle high-word guarantee was found.

* [REPORT.md](REPORT.md): findings, original-byte comparison, HALF/coordinates, remaining boundary.
* [DOCS.md](DOCS.md): official API/device-input connection and precise sources.
* `RESULT.json`: machine-readable byte/provenance checks.
* `witness.cu`, `texture_control.cu`: own device-only sources.
* `build/`: compiler-generated PTX/cubins/intermediates; no original recompile.
* `evidence/`: fresh disassembly, uniform-register liveness, commands, official document snapshots.
* `FILES_CHANGED.txt`, `SHA256SUMS`: exact inventory and hashes.

Reproduce checks (CPU compilation/static disassembly only):

```sh
python3 reviews/nr-original-kernel-object-abi-20260911/verify_cpu.py
```

The verifier writes only here, uses nvcc/ptxas13.3 for SM120, and checks 3,336 original + 728 own instructions against ELF bytes. No CUDA API/library initialization, GPU/Wine/module load, object creation, or execution. Existing host and its gate were not changed. Rebuilding regenerates artifacts; refresh this directory's checksums before comparing a new build snapshot.
