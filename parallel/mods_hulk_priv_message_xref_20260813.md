# MODS HULK/PRIV message xref and GB202 PRC correction — 2026-08-13

This is a static-only audit.  No MODS/nvflash executable was run and no GPU,
BAR0, firmware, reset, token, or license operation was performed.

## 1. PRC packet correction

NVIDIA's 2026 Nova PRC patch defines the generic request header as four packed
bytes:

```text
sub_message_id, flags, object_id, reserved
```

It defines `FLAG_ACTIVE = 1 << 1`; the companion documentation says flag bit 0
selects the persistent value and bit 1 selects the active value.  Therefore the
observed packet

```text
0d 02 1d 00  01 00 00 00
```

is `WRITE`, `ACTIVE`, object `0x1d`, reserved zero, value `1`.  It is not a
persistent request.  Direct sources:

- code: <https://patchew.org/linux/20260604114339.1565660-1-zhiw%40nvidia.com/20260604114339.1565660-5-zhiw%40nvidia.com/>;
- documentation: <https://patchew.org/linux/20260604114339.1565660-1-zhiw%40nvidia.com/20260604114339.1565660-6-zhiw%40nvidia.com/>.

Archived mboxes:

```text
patch4_prc.mbox      17395 bytes  sha256 350a1c044d7515992f584533c55be8cfaf73218377a210564a3618f92512e700
patch5_fsp_docs.mbox 17577 bytes  sha256 74d8d315e9922bb3fb7fba7473a5e199c7ac75eb67cf865f06a9a15c5b24fa76
```

The test was an equal-current forced write: object `0x1d` read as `1` before
the request, FSP returned `0x1e4`, and it still read as `1` afterwards.  The
normal public `gpu-admin-tools` helper would skip the write when old equals
new.  Hence `0x1e4 = PRC_ERROR_PERSISTENCE_NOT_SUPPORTED` proves only the
literal FSP response to this active-only equal-current request.  It does not
prove that persistence was requested, that HULK was missing, or that all PRC
writes are unavailable.  The internal validation order and reason for this
apparently mismatched error name remain unknown.

Source transcript:
`vm_mods_lab/fsp_prc_write_noop_result_20260722.md`, SHA-256
`a98fdf44e6404487bb8afe5d9340a7d14affccebe7fdc6b1536f13fcb93a28fe`.

## 2. `%s register is PRIV protected` is a diagnostic translator

Fixed MODS ELF:

```text
mods 392339552 bytes
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

The string at file offset `0x88549c0`, virtual address `0x8c549c0`, is:

```text
%s register is PRIV protected. Please acquire HULK license.
```

Its only immediate reference found by exact pointer and bounded disassembly is
at `0x1536ba3`, inside helper `0x1536b60`.  The helper:

1. invokes a caller-supplied register-access virtual method;
2. checks whether the returned value's high 16 bits equal `0xbadf`;
3. if so, prints the HULK message with the caller-supplied register name and
   returns MODS status `0x13b`.

Twenty-seven direct callers pass names such as `Write to PRIV ERROR CODE`,
`Write to HBM IEEE1500 INSTR`, `Write to HBM IEEE1500 DATA`,
`Write to HBM IEEE1500 MODE`, and `Read from HBM IEEE1500 DATA`.  These callers
are clustered in the HBM repair/IEEE1500 code at `0x1536c30..0x15381be`.

This proves the message is a generic translation of an observed PRIV/BADF
access result in that subsystem.  The helper does not inspect a HULK blob,
certificate state, PRC object `0x1d`, or `0x8200f8`.  Consequently the mere
presence of this string cannot prove that every protected register, or the
GB202 L2 latch path specifically, requires a HULK certificate.

The separate GPC FMon message at virtual address `0x8c2c750` is referenced by
two FMon access routines (`0x126f49f` and `0x126f7bb`) after register access
tests fail.  It is direct evidence that MODS recommends HULK for that FMon
case, not evidence for GB202 L2.

`OPT_SECURE_UNIT_FLOORSWEEP_WR_SECURE` and
`OPT_SECURE_FUSE_FLOORSWEEP_WR_SECURE` are inserted into option/name tables at
`0x1430541/0x143056b` and `0x14318cb/0x14318f5`.  These xrefs establish option
metadata presence, but do not by themselves bind the options to GB202's
`0x8200f8` or prove which authorization makes a write succeed.

## 3. What the task-2 observation proves

On the observed retail GB202 state, FSP accepted PRC task `2`, subobject `1`,
zero payload and returned success.  No HULK certificate or HULK NVDM action was
sent in that run.  Afterwards:

```text
0x8200d0  0xfffffb8f -> 0xfffffbff
0x8200dc  0xfffffb8f -> 0xfffffbff
0x8200f8  remained 0xfffffb8f
0x820040  remained 0
raw/effective L2 masks remained 0x12
```

This separates at least two gates: task 2 can lower/open the visible `d0/dc`
PLM state, but it did not open `f8`, make the latch request stick, or apply an
L2 mask change.  It disproves any claim that the visible `d0/dc` transition
itself necessarily requires loading a HULK certificate in the same run.

It does **not** prove the card had no pre-existing, fused, flashed, lifecycle,
or boot-time authorization state.  It also does not identify what legitimate
mechanism opens/consumes `0x8200f8`.  HULK, PRC permission state, a debug token,
an FSP-only transaction, SKU/lifecycle policy, and a hardware state machine
remain distinct hypotheses until one is tied to an observed `f8` transition.

Source transcript:
`vm_mods_lab/fsp_task2_zero_result_20260722.md`, SHA-256
`990eddbffd1d931596c3eb85fffac468bd04e7e9014ac4695be3631c0c2761b3`.

## 4. Defensible answer to “does L2 require HULK?”

- **Proved:** current host-visible writes are blocked at independent raw-mask
  and latch/`f8` gates; task 2 alone opened only `d0/dc`.
- **Proved:** HULK is a real signed register-operation mechanism and could, in
  principle, carry a target address without that address appearing in GSP
  text.
- **Not proved:** any GB202 HULK policy or signed object covers `0x8200f8`,
  `0x820040`, or the desired L2 operation.
- **Not proved:** HULK is the only mechanism capable of authorizing the missing
  transition.
- **Unknown:** the actual FSP/hardware consumer and authorization predicate for
  `0x8200f8` and the final L2 commit.

Therefore a 100% necessity statement is currently unjustified.  The strongest
accurate formulation is: **a further privileged authorization/firmware path is
still required for the observed `f8`/latch/commit barrier, and HULK is one
plausible supported path, but neither its necessity nor its sufficiency for
GB202 L2 has been demonstrated.**
