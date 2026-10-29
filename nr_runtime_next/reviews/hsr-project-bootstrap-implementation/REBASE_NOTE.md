# Integration/rebase note

The isolated copy was captured before the concurrently owned `reviews/hsr-nvx-observer` changes landed in Main. In particular, this Project-ID patch's HSR `router.cpp`, `Makefile`, and generated HSR manifests share integration surface with that worker. Do not copy the isolated HSR directory over Main or apply the patch with fuzz. Rebase the Project-ID capture/optional-attach pieces into the NVX owner's resulting router, retain both observer paths, rebuild, and regenerate HSR source/candidate manifests once after the merge.

`patches/hsr-project-bootstrap.patch` applies exactly to `BASE_SOURCE_SHA256SUMS`; `logs/patch-dry-run.log` proves that captured-base application only. Native host/runtime files matched their captured Main inputs when copied.
