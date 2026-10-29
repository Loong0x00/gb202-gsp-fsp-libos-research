# CPU-only verification

Passed:

```text
make -C project/native clean
make -C project/native cpu-check -j2
make -C project/adapters/hsr_native clean
make -C project/adapters/hsr_native candidate -j2
make -C project/adapters/hsr_native test -j2
make -C project/adapters/hsr_native harness -j2   # compile only; not run
make -C project/adapters/hsr_native check -j2     # CPU/source/PE only
python3 verify_cpu.py
patch -p1 --dry-run < patches/hsr-project-bootstrap.patch
```

Results are in `logs/`. `native-cpu-check.log` includes the new host-native Project identity copy/conflict/failure policy test and cross-compiles/links the fake private-Core ABI DLL/caller. `hsr-compile-test.log` includes candidate compilation, existing CPU tests, and fake HSR harness compilation only. `project-id-static-pe-check.log` verifies the optional host/runtime exports, fake Core private export, exact pin/proof source conditions, frozen ABI assertions, and the candidate's frozen 68 NVUnity exports.

No Wine executable, game, GPU workload, network operation, prefix/deployment change, signed-file write, or protection change was performed.

Remaining uncertainty: CPU/static checks cannot prove that the exact retained Core will freshly resolve and call exact signed NR for its internal indices `0..17` on the owned Vulkan device. The candidate intentionally reports incompatible if that bounded observation is absent, including when Core used a cached pointer. See `IMPLEMENTATION.md` for the required owned-GPU harness evidence.
