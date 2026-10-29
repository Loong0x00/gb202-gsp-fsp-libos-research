# CP2077 native installer

This directory contains a CPU-only, fail-closed migration library and CLI for one
installation only:

`/home/user/.local/share/Steam/steamapps/common/Cyberpunk 2077/bin/x64`

It is not a game launcher, a universal installer, or GPU acceptance tooling.

Production inputs are frozen under
`releases/native-pc4-cp-20260910-084731/`: both the exact tested package and all
79 manifest-bound source/package files are retained. The working `native/`
directory is not a release source. Editing or rebuilding HSR support therefore
cannot silently change the package selected by this installer; its original
package/source/GPU hash checks remain mandatory.

## API

```python
from installer import inspect, plan, apply, rollback, BUDGET_ACKNOWLEDGEMENT

inspection = inspect()                 # never writes
proposal = plan()                      # dry-run; never writes
result = apply(                        # explicit mutation
    proposal["plan_id"],
    acknowledgements=[BUDGET_ACKNOWLEDGEMENT],
)
rollback_preview = rollback(result["transaction_id"])  # never writes
rollback_result = rollback(result["transaction_id"], apply_changes=True)
```

Reports are JSON-compatible dictionaries intended for later GTK wiring.
`plan_id` binds apply to the inspected hashes and prevents applying a stale plan.

## CLI

Run from `/home/user/rt_5090_project/nr_runtime_next` (the system may also
have an unrelated PyPA package named `installer`). The frontend loads this
package explicitly by path under a unique module name.

```text
python -m installer                         # dry-run plan (default)
python -m installer inspect
python -m installer plan
python -m installer apply                   # still dry-run
python -m installer apply --apply \
  --acknowledge-cp6kdlaa-budget-bypass
python -m installer rollback TRANSACTION_ID # dry-run
python -m installer rollback TRANSACTION_ID --apply
```

Apply verifies the frozen package manifest, the complete source manifest, and
selected evidence bound by the retained run's frozen `SHA256SUMS`. The three DLL
hashes and installed static capability must all equal the completed restored GPU
run `20260910-084731-native-post-1-enabled1-6144x3456`. A matching filename is
never capability evidence.

Only the exact legacy router/service files and five marker files inventoried by
`tools/run_cp_case.py` are removed, and only at retained known hashes. Existing
`dxgi.dll` is replaced only when absent, already native, or the known backed-up
legacy hash. Any other type/hash or any symlink/case collision blocks the whole
plan. Unrelated files and mods are not enumerated for deletion.

The transaction backs up every replaced/removed file outside the game directory,
stages same-directory writes, atomically renames each replacement, journals each
step, and automatically rolls back ordinary failures. Rollback refuses to
overwrite a post-install file whose content is no longer the transaction's exact
installed state. Both apply and rollback refuse while a `Cyberpunk2077.exe`
process is detected.

The installer does not touch signed NVIDIA DLLs, CP2077 settings/accounts/saves,
D5LC control or receipt files, D5RP request/status receipts, frontend profiles,
`ReShade.ini`, or unrelated mods. It installs only the static capability proof;
it never copies an old active status as a runtime receipt.

## 6K DLAA limitation

The retained 6144x3456 **Quality** run proves this exact pc4 binary set can execute
post/1. A separate current 6144x3456 **DLAA** route was `budget_exceeded` with zero
NR calls. Migration does not weaken that guard or change game quality. The route
will remain NR budget-bypassed on the original game path unless runtime conditions
later fit the guard. Apply therefore requires explicit acknowledgement, but does
**not** require changing DLAA to Quality.

## Tests

```text
python -m unittest discover -s installer/tests -v
```

Tests use temporary fixtures and a fake `/proc` tree only. They do not invoke
Wine, UI, GPU tools, games, sudo, or the real CP2077 path.
