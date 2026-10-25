### Checklist

- [x] The problem is not listed in the hardware support matrix as a known limitation.
- [x] This report includes a minimal before/after configuration comparison, daemon log evidence, and the relevant GUI control flow. A full debug snapshot can be provided if needed.
- [x] The live reproduction occurred on development build `b3efeb273f7e0ed9b83bc37b24938f6b51fb555f`. The same control flow is still present in current `master` at `cecf05a32f4caf80e69512961c4dd09e1806f9d4`.

### Bug description

Applying an unrelated GPU setting in the LACT GUI can silently remove an already saved NVIDIA V/F curve from `/etc/lact/config.yaml`.

The issue occurs when a non-empty V/F curve is already configured, the GUI has loaded the runtime V/F points, and **Enable V/F curve editing** remains disabled (its default state). Changing another setting such as the power limit or fan configuration and then applying/confirming the change can serialize `gpu_vf_curve` as an empty map. No error or warning is displayed.

This has happened on the test system more than once. A damaged configuration was preserved before restoration, allowing an exact comparison.

### Reproduction steps

1. Start with an NVIDIA GPU configuration containing a non-empty `gpu_vf_curve`.
2. Open the LACT GUI and allow the GPU data and clocks table to load.
3. Do not enable **Enable V/F curve editing**.
4. Change an unrelated setting, for example the power cap or fan settings.
5. Click **Apply** and confirm the change.
6. Inspect `/etc/lact/config.yaml`.

### Expected behavior

Applying an unrelated setting should preserve the existing `gpu_vf_curve` byte-for-byte unless the user actually edits or resets the V/F curve.

### Actual behavior

The saved V/F curve disappears while the unrelated settings remain. There is no GUI error and no daemon warning.

The preserved before/after files from one occurrence were:

#### Before

- File size: 7779 bytes
- SHA-256: `72c89a17b3f2467e474e38173992467f2622fecfa29c94fffe2e86ada9c34b9f`
- Config version: 6
- GPU key: `10DE:2B85-1043:89E3-0000:01:00.0`
- `gpu_vf_curve`: 127 points
- `power_cap`: 600.0 W
- `mem_clock_offsets`: `{0: 2000, 8: 2000}`

#### After the GUI save

- File size: 678 bytes
- SHA-256: `75db3f88ebdb162a2b400906967f3dfa0b6d4b5b1695954ea51668b76261d348`
- Config version: 6
- Same GPU key
- `gpu_vf_curve`: absent / 0 points
- `power_cap`: still 600.0 W
- `mem_clock_offsets`: still `{0: 2000, 8: 2000}`
- Fan configuration remained present

Relevant daemon journal entry:

```text
Jul 30 06:32:47 lact[3793]: INFO lact_daemon::server::handler: saving updated config
```

There was no accompanying warning or error.

An earlier saved configuration from May also preserved the same failure shape: the other GPU settings remained present, but `gpu_vf_curve` contained 0 points.

### Relevant control flow

The GUI loads the NVIDIA clocks table and forwards its V/F points to the curve editor even if the editor window is never opened:

- `AppModel::update_gpu_data()`
- `OcPageMsg::ClocksTable`
- `VfCurveEditorMsg::Clocks`

The curve editor initializes `allow_editing` to `false`, while its point collection becomes non-empty after the clocks table is loaded.

When applying any GPU settings, `OcPage::apply_clocks_config()` currently uses:

```rust
if !self.vf_curve_editor.model().is_empty() {
    config.gpu_vf_curve = self.vf_curve_editor.model().get_configured_curve();
}
```

However, `VfCurveEditor::get_configured_curve()` returns an empty map while editing is disabled:

```rust
if !self.allow_editing.value() {
    return IndexMap::new();
}
```

Therefore, after the clocks table has loaded:

- `is_empty()` is false because runtime points are present;
- `get_configured_curve()` returns an empty map because editing is disabled;
- the existing saved curve is replaced with the empty map during an otherwise unrelated settings update.

The same two conditions are present in current `master` at `cecf05a32f4caf80e69512961c4dd09e1806f9d4`.

Related source locations:

- `lact-gui/src/app.rs`: `AppModel::apply_settings()` and `update_gpu_data()`
- `lact-gui/src/app/pages/oc_page.rs`: `OcPage::apply_clocks_config()`
- `lact-gui/src/app/pages/oc_page/vf_curve.rs`: editor initialization, `is_empty()`, and `get_configured_curve()`

Commit `58b2b4b0afee6fcfc1742c69fe5c627bcfae9c30` ("fix: unnecessary curve overwriting") added the current `is_empty()` guard. The behavior described above remains possible with that guard because the loaded runtime point collection is non-empty while editing is disabled.

This is separate from issue #1076. That issue was caused by the confirmation window not being raised and the configuration timing out/reverting. In this case the change is confirmed and saved successfully, but the persisted V/F curve field is emptied.

### System info

Live reproduction environment:

- LACT package: `lact-git r1198.b3efeb27-1`
- LACT commit: `b3efeb273f7e0ed9b83bc37b24938f6b51fb555f`
- GPU: NVIDIA GeForce RTX 5090
- GPU PCI device ID: `10de:2b85`
- GPU subsystem at reproduction: `1043:89e3`
- NVIDIA driver: `610.43.03`
- GSP-RM: enabled
- Kernel at reproduction: `7.1.4-arch1-1`
- Distribution: Arch Linux

Current upstream source checked:

- `master`: `cecf05a32f4caf80e69512961c4dd09e1806f9d4`
