# Actual HSR + GTK baseline verification (not native HSR acceptance)

User correctly challenged the previous GUI claim. The earlier 26 tests and
synthetic UI captures were not a real installed desktop/controller/game loop.

## Reproduced real defects

The actual desktop launcher points at the current source. Its real saved targets
were all restored legacy deployments, so topology widgets were disabled for a
valid reason: no native D5RP backend was installed. A real-profile screenshot is
`frontend-real-20260910-095954/settings.png`. Static review also found WuWa's stale
control_only=false selecting the old installer, unsafe/mismatched launcher routes,
and success messages without acknowledgements. See
`reviews/frontend-real-use/CPU_STATIC_AUDIT.md`.

## Actual HSR runs

All runs used original 6144x3456 display, the unchanged existing Guardian and
normal launcher chain in isolated Gamescope. No network configuration, protected
startup component, signed DLL, account DB or whole Wine registry was modified or
restored. Official game login/data updates are game-owned and retained.

- `hsr-runs/20260910-100957-legacy-baseline-ui`: login succeeded, official data
  update succeeded and required restart. Stopped/restored; no NR activation claim.
- `.../20260910-101610-legacy-baseline-ui`: remained at login; no live NR check.
  Zero-duration synthetic clicks were not reliable; held 150ms clicks were added.
  Timed out normally and restored. This is not classified as a network failure.
- `.../20260910-102845-legacy-baseline-ui`: login and entry succeeded; actual
  gameplay in Morning Dew Mansion, normal Guardian phase settle. No network
  workaround was necessary.

## Real GTK switch / real backend result

Within the third run, `real-gtk-controls-103636/` opened a separate real product
GTK MainWindow with the actual ProfileStore and actual HSR files (NON_UNIQUE on
the existing session bus, no fake profile/backend). It exercised the real switch
callback and sampled the actual 72-byte status, then restored the original OFF
preference. The source hashes stayed constant during this check.

- ON: fresh D5LC sequence 1789007799297599175, matching runtime acknowledgement.
- ON-late: acknowledgement retained; legacy service reported successful Feature18
  evaluations through frame 1200, output6144x3456/guides3072x1728/result0x1.
- OFF: fresh sequence1789007827597519385, matching acknowledgement; service
  explicitly returned to native DLSS pass-through.
- Real GTK captures before/on/on-late/off and JSON receipts are retained.
- Topology remained insensitive, correctly: this is still the legacy single-layer
  backend. It does NOT verify new native HSR interop, D5RP, PRE, or ten layers.
- The only persistent profile field change was WuWa control_only false->true,
  the intended mode correction. HSR's original OFF setting was restored.

The first GUI instrumentation attempt (`real-gtk-controls/`) failed before
switching NR because it captured immediately after changing pages, before GTK
layout. Its failed result is retained. Waiting for layout fixed the test harness.

All three RESTORED.json records report game stopped, controls restored, and
original deployment/signed/Guardian hashes unchanged. Candidate HSR DLLs have not
been deployed in these runs.

## Privacy and diagnostic caveats

Credentials were supplied to the official game form via stdin, not command-line
arguments or credential files. Login input rectangles are redacted in retained
login diagnostics; these images are not unmodified compositor references. One
login PNG was interrupted during redaction and recovered with truncated-image
handling, explicitly noted in that run. No picture-quality conclusion uses it.

The initial private-D-Bus GUI snapshot spawned a second accessibility bus that
replaced the session socket. Main restored at-spi-dbus-bus.service and verified
connection; subsequent real GTK tests used NON_UNIQUE on the existing session
bus instead. No accessibility/desktop setting was changed.
