# GB202 no-reload internal GPIO bridge

Status: **normal GPIO live test completed; bridge is currently unloaded**.

This directory contains a narrowly filtered, one-shot kprobe bridge for the
currently installed NVIDIA 610.43.03 driver.  It is intended to answer whether
the existing, normally locked internal GPIO controls can reach the GB202 GSP
without replacing or reloading `nvidia.ko`.

The bridge does not expose an arbitrary RM command.  It accepts fixed,
compile-time profiles only, requires `CAP_SYS_RAWIO`, allows one open file, binds the arm to
the exact calling thread, requires ordinary control flags (`0`), expires after
two seconds, and consumes the arm on the first matching call.

`NVGIB_PROFILE_WPR_REGION_INFO` is a read-only metadata profile. It accepts
only `0x20801364` with its documented 40-byte WPR-region-info output structure;
it has no input address, transfer length, or write field.

The key ABI fact is independently confirmed in both source and machine code:

- `RS_RES_CONTROL_PARAMS_INTERNAL.bInternal` is byte offset `0x68`.
- `serverControl_ValidateCookie` in the built 610.43.03 `nvidia.o` tests it as
  `cmpb $0, 0x68(%rbx)`.
- The kprobe changes only this per-call byte.  The request entered through the
  ordinary external RM path, so normal RM lock selection remains intact.

`bridge_read_probe` is deliberately read-only.  It arms only the published host
command `0x20802302` (8-byte params), which maps to GSP `GPIO ReadInput`, and
reads GPIO13.  It has no output, direction, mux,
reset, VBIOS, MMIO-write, or driver-reload path.

Runtime sampling disproved the earlier static one-entry-shift hypothesis:
`0x20802301` produced a constant zero for GPIO13, while the published
`0x20802302` produced 92 transitions in 1000 samples.  The bridge profiles now
use the published `0x20802300..0x20802303` direction/output/read/activate IDs.

Important limitation discovered after the bridge was built: Lightning's GPIO3
runtime record has function `0xff` and selector `0`.  GSP `ActivateHwFunction`
does **not** treat selector zero as generic GPIO; it follows an assertion/error
path.  Do not attempt `Activate(0xff, GPIO3)`.  Restoring Astral fan group 2/4
requires either changing the GSP runtime record to function `0xd1`, selector
`0x5c`, or reaching the raw GB202 `OBJGPIO +0x250` selector method.  Merely
crossing the host internal-permission gate is insufficient.

Build without loading anything:

```sh
make
```

Do not load or run this while unattended.  Before the first live test, verify
the loaded NVIDIA version is exactly 610.43.03 and repeat the disassembly check.
`bridge_gpio3_static_probe` implements the bounded rollback sequence derived
from Lightning's DCB record: stage the latch, select output, measure GPIO7 at
both values, restore input, restore latch zero.  Its 2026-07-26 live run reached
all three verified GPIO controls but produced no GPIO7 tach transitions at
either level.  This is a negative result for normal-GPIO static control; it is
not evidence that selector `0x5c`/PWM11 control is impossible.

`bridge_activate_d1_probe` is a second one-shot discriminator.  It submits
only `ActivateHwFunction(function=0xd1, pin=3)`.  On 2026-07-26 GSP returned
`0x0000ffff`, temperature stayed at 40 C, no Xid/NVRM error appeared, and the
bridge was unloaded.  This confirms that the existing Lightning `ff/0` record
must be updated before the normal activate command can reach selector `0x5c`.
