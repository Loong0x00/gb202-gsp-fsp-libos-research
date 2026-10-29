# ViT31–38 H4 geometry / raw-buffer audit

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B transparent_chain.py --write-report
```

`GEOMETRY_CHAIN_RESULT.json` is generated only after every static/raw check
passes.

## Bounded conclusion

For the recorded `arg5=4,arg6=4` boundary fixture, `N=16` is the logical
kernel argument product.  The 1-D FP8 activation storage is padded to 32
records: `32*1024 = 32768` bytes; expand storage is `32*4096 = 131072` bytes.

* Block31's only input repack is a 24-byte `<QQii>` raw-b32 boundary launch.
  It turns the complete 16 KiB 2-D head into the exact complete 32 KiB N32
  input and explicitly writes the padded part as zero.
* Block31 projection and block32 input are byte-identical across all 32768
  bytes.  This proves a direct **N32 format** handoff for this fixture, not an
  N64 handoff or a visible N32→N64 conversion.
* The recovered outer executor selects `block31.layer4.O[0]` and forwards its
  selected qword into block32's primary-input vector; there is no recovered
  conversion node on that route.  It still does **not** prove that the two
  runtime values alias one physical GPU allocation: snapshots/static qword
  forwarding contain no GPU pointer trace.
* Block38's 24-byte 1-D→2-D repack remains a final boundary operation.  Its
  raw mapping is checked with a complete recorded N32 projection witness, but
  no block38 N32 projection fixture is claimed.

The audit verifies all seven complete original buffers for blocks 31 and 32,
and the complete expand/contract prefix for block33.  It then preserves the
actual refusal:

```text
ValueError: half arithmetic overflow (not sanitized)
```

No output for blocks34–38 is fabricated, and `--require-complete` deliberately
returns nonzero.

## Safety

`chain.py` is now a compatibility refusal.  Its previous implementation reused
the block31-specific `Block31N16` model for blocks32–38, so it is not a valid
transparent chain.  `transparent_chain.py` imports only the two raw-repack CPU
references; it does not import a VM, model/NumPy forward, GPU binding, network
client, or NaN/∞ cleanup path.
