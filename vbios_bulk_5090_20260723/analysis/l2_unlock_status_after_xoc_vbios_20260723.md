# L2 unlock status after adding XOC/high-power VBIOS samples

Scope: static local-file analysis only. No flashing, no execution, no GPU/device access.

## Short answer

The new XOC/high-power BIOS samples do not reveal a practical L2 unlock method.

They are still useful samples, but not because of power limit. Their value is that they are valid signed images with different board policy. If L2 floorsweep policy were exposed in the same visible VBIOS tables, these samples might have shown a clean diff. They did not.

## Checked high-interest samples

- `281640.rom`: MSI Lightning 800W, `2B85`
- `281649.rom`: MSI Lightning 1000W, `2B85`
- `281814.rom`: ASUS Astral XOC #2, 2001W, `2B85`
- `GALAX.RTX5090D.32768.250226.rom`: GALAX HOF XOC, 2001W, `2B87`
- `Asus.RTX5090.32768.250327.rom`: normal ASUS Astral reference, `2B85`

## Static L2-specific findings

1. Normal ASUS Astral, ASUS Astral XOC, MSI Lightning 800W, and MSI Lightning 1000W all share the same visible L2 register-address table.

2. The BIT `i` table contains `0x00822080` and adjacent software-mask addresses:

   ```text
   0x00822080
   0x00822084
   ...
   0x0082209c
   ```

   But this table lists addresses only. It does not contain values to write, and it does not contain the observed disabled mask `0x12`.

3. Across the local corpus, no checked ROM/NVFW contains obvious plaintext/simple binary patterns for:

   ```text
   8 x 0x12
   8 x 0xed
   8 x u16/u32 0x12
   8 x u16/u32 0xed
   0x8234e0 raw L2 disable base
   0x822900 effective L2 disable base
   0x8200f8 latch/raw-override PLM
   0x820040 latch request
   ```

   The one real shared hit is `0x822080`, the software-mask address-table entry.

4. The only `0x8200f8` / `0x820040`-looking hits found in a Dell RTX PRO 6000 NVFW are inside high-entropy bytes and are treated as accidental byte patterns, not decoded policy fields.

5. The `FSP_RUN` object is identical across almost all normal RTX 5090 / `2B85` samples, including the high-power XOC BIOSes. Therefore the visible 800W/1000W/2001W differences are probably in outer board policy, not in `FSP_RUN`.

## What remains true from runtime work

The observed L2 state on the target 5090 was:

```text
raw masks       = 0x12 on FBP0..7
effective masks = 0x12 on FBP0..7
software masks  = 0x00 on FBP0..7
```

So the driver is not merely software-disabling those slices. The disabled 32 MiB is coming from raw/effective floorsweep state.

The visible raw/latch path is:

```text
raw L2 shadow:        0x8234e0 + 4 * FBP
raw L2 PLM:           0x8200dc
latch request:        0x820040.bit0
latch/raw override PLM: 0x8200f8
software override ctl: 0x8212ac.bit0
```

Isolated VFIO testing showed:

- FSP task2/subobject1 can open `0x8200d0/0x8200dc`.
- It does not open `0x8200f8`.
- Direct writes to `0x8200f8` read back the old value.
- With `0x8200dc` open, writes to the raw L2 shadow still do not stick.

## Practical meaning

The L2 unlock problem is still an authorization/lifecycle problem, not a missing mask encoding problem.

A working route would likely need one of:

1. A valid signed HULK/FSP/VBIOS authorization object that opens `0x8200f8` or directly changes the raw/effective floorsweep state.
2. A parser/authorization bug in the secure loader, FSP, HULK, or VBIOS policy chain.
3. A hardware/lifecycle/fault-injection style route, which is outside the safe software-only path.

The current XOC BIOS corpus does not provide #1, and the low-cost signature-defect checks did not find #2.

## Next useful static targets

- Locate and classify the outer board-policy tables that differ between:
  - `Asus.RTX5090.32768.250327.rom`
  - `281814.rom`
  - `281640.rom`
  - `281649.rom`
- Separate power/thermal policy deltas from identity/signature metadata.
- Check whether any changed table references floorsweep, FB/LTC/LTS, repair, or topology tokens.
- Continue looking for a legitimate HULK/FSP authorization schema, because `0x8200f8` remains the bottleneck.

