# Native signed RR recording A/B

The game was stopped. The post Feature18/codec service was removed from the
add-on search directory; the telemetry Router and signed game DLSS runtime were
left untouched. With no post-service export, Router preserves the original
signed RR Evaluate result and output.

Expected telemetry after the login gate:

- original_result = success
- post_called = 0
- effective_dlss5_mode = 0

No raw capture hotkey should be used. Record the same R animation normally in
OBS. Restore Feature18 only after the game exits with `restore-dlss5.sh`.

The first two Steam starts at 11:32:57 and 11:33:03 exited with code 1 before
Proton launched the game because the 6K wrapper still required the removed
service hash. The wrapper now has an explicit fail-closed
`native-rr-only` marker mode: it requires the service to be absent, preserves
the 6K INI/database checks, and reports
`service=disabled-native-signed-rr-only`. A live `--check` then returned 0.

During the native-RR run, four `Super+Alt+C` presses at 11:39:12, 11:39:21,
11:39:27 and 11:39:31 each hit the helper's expected service-hash guard. Since
the service is intentionally absent, each invocation refused and emitted the
single warning bell; none entered prepare/start/save state. The GNOME binding
has now been disabled for the remainder of this native-RR A/B. The restore
script reinstates the binding together with the service.
