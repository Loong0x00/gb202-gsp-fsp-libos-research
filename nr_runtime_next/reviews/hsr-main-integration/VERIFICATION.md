# CPU-only verification

Run only inside `reviews/hsr-main-integration/`; no game, GPU or Wine command was
executed.

## Main

```sh
make -C proposed/project/native clean cpu-check
```

A later incremental final rerun also passed. Results:

- MinGW compilation of the three native DLLs passed;
- HSR external-POST channel/current-epoch, CP POST, built-in WuWa RR POST,
  frozen Raw200/Result216/Commit72/Query80 and no-early-active checks passed;
- existing policy, loader and factory tests passed;
- source and PE export checks passed, including both new exports.

Log: `logs/main-cpu-check.log`.

## HSR adapter

```sh
make -C proposed/project/adapters/hsr_native clean check
```

Final rerun results:

- MinGW candidate and format helper compilation passed;
- existing HSR logic: 57 checks passed;
- new vtable permission/CAS/predecessor-lifetime test passed;
- source checks confirmed one bounded external pending sample, nonblocking D3D11
  retirement polling before Commit, and no render-thread CPU fence wait;
- 68-export/source/PE checks and updated source/artifact manifests passed;
- candidate SHA-256:
  `5e5c245e1162e7eb0a776982f593c34fcde846db0a5d3c685d822c8482db3121`;
- format helper SHA-256:
  `04aac6e84149860ec619deeae814839a960fa1f4e4a34b1e342fb3e91f65f10f`.

Log: `logs/hsr-adapter-cpu-check.log`.

## Guardian publisher

```sh
cd proposed/guardian
python3 -m py_compile astral_hsr_guard.py \
  hsr_native_health_publisher.py test_native_health_publisher.py
python3 test_native_health_publisher.py
```

Challenge80/Lease112 packing, pinned receipt validation, signed-input verifier
requirements, safe-sample-only source ordering, lease revoke ordering and
artifact-drift failure passed. Log: `logs/guardian-publisher-cpu-check.log`.

## Compile-only harnesses

The native fake runtime/Wine harness executable and HSR fake NVUnity/core/feature
harness were cross-compiled but deliberately not run:

```sh
make -C proposed/project/native \
  build/wine_harness.exe build/fake/dlss5-native-runtime.dll
make -C proposed/project/adapters/hsr_native harness
```

Log: `logs/cross-compiled-harnesses.log`.

## Patch reproducibility

Both integration patches applied with `patch -p1` to a fresh copy of `base/project`;
the Guardian patch applied to `base/guardian`. Recursive comparisons (excluding
build output) exactly matched `proposed/`. Logs:
`logs/integration-patch-apply.log`, `logs/guardian-patch-apply.log`, and
`logs/patch-tree-verify.log`.

No live runtime/game/Guardian state was inspected for acceptance or changed.
