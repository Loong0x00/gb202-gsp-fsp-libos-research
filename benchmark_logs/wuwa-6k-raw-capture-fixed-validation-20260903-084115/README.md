# Fixed 6K raw-capture four-frame validation

Capture directory:

`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-raw-captures/20260903-084115-539-p320`

## Result

PASS.

- Fixed service SHA-256:
  `6e01cfef594cf877dede77ec49e3fbe49c66e9bf99691728ecf60645f303fc7d`
- Session requested/recorded/completed: `4/4/4`.
- Abandoned/write-failed: `0/0`.
- Five surfaces per frame, 20 raw files total.
- All 20 file sizes exactly match the manifest.
- Total raw payload: `1,137,151,872` bytes (about 1.06 GiB).
- Capture log confirms lazy worker start and normal session finalization.
- Active/trigger/stop markers were removed after completion.
- Game continued running normally after capture.
- No new UE4 crash and no matching kernel Xid/NVRM event.

Captured bridge frames: 991–994. Nearest Router global Evaluate frames: 2632–2635.
All four were 6144×3456, mode 2, Reset false, signed RR success and Feature18
post success.

Formats and dimensions:

- pre/post: 6144×3456 `DXGI_FORMAT_R11G11B10_FLOAT`, 84,934,656 bytes each.
- Color: 3564×2008 `DXGI_FORMAT_R16G16B16A16_FLOAT`, 57,252,096 bytes.
- MV: 3564×2005 `DXGI_FORMAT_R16G16_FLOAT`, 28,583,280 bytes.
- Depth: 3564×2005 `DXGI_FORMAT_R32_FLOAT`, 28,583,280 bytes.

All decoded surfaces have zero non-finite components. The four post frames have
red-dominant fractions between `0.00002298` and `0.00002543`; visual contact
sheet contains no structured red bad frame. This was a pipeline safety test,
not the final anomaly capture.

First-time readback allocation increased CPU command-recording time for Router
frames 2632–2634 to approximately 13.3, 20.5 and 31.2 ms; the reused slot frame
2635 returned to approximately 4.3 ms. GPU Feature18 timings exclude capture
copies by design.

Artifacts:

- `manifest.jsonl`
- `SHA256SUMS.capture`
- `analysis.json`
- `pre-post-contact.png`

After this successful validation, the GNOME capture hotkey was increased to a
bounded 24-frame window. The native hard maximum remains 32, and a second
`Super+Alt+C` press stops early.
