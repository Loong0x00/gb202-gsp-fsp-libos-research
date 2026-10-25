# FAN control current anchor — do not repeat the same discovery

Current hardware/BIOS state:

- Card: ASUS Astral Black RTX 5090 running MSI Lightning 800 W VBIOS.
- Physical fan mapping previously observed:
  - logical/controller 0 drives physical fans 1 and 3.
  - logical/controller 1 should drive physical fans 2 and 4.
- Lightning VBIOS advertises only one `FAN_COOLERS` active slot: `00 ff ff ff`.
- Current RM/GSP fan cooler API returns only one cooler; this has been rechecked.

## 2026-07-28 practical resolution and priority update

The immediate cooling problem no longer requires the missing GSP FanCooler
object to be solved first.  The shortest practical route is a reversible
hardware PWM reroute:

- Keep the existing 12 V and ground wiring for physical fans 2/4.
- Disconnect only their PWM input from the inactive PWM11/GPIO3 route, so two
  PWM outputs can never drive against one another.
- Feed both fan PWM inputs from the already working PWM10/controller-0 signal,
  or from the two ASUS external FanConnect headers whose IT8915 control path is
  already known.
- Do **not** tie two tachometer outputs together.  Preserve them separately or
  connect only one tach output to one input.
- Two standard PWM fan inputs present negligible control-signal load compared
  with the fan motor power, but pin order, voltage level and output topology
  must still be measured rather than inferred from wire colour.

This can be implemented either by repinning/crimping two wires or by a passive
two-layer adapter PCB.  A full replacement GPU PCB is not required.  The
adapter can be made reversible and can leave every high-current power wire in
the original harness.

The ASUS external-header alternative is documented in:

`/home/user/rt_5090_project/ASUS_GPUTWEAK_IT8915_EXTERNAL_FAN_RE_20260728.md`

It uses GPU I2C bus 1, 7-bit address `0x2b`; registers `0x40/0x41` control a
shared external-fan mode/duty and `0x44/0x48` report the two tachometers.  This
route controls the external headers, not the missing onboard PWM11 route, but
it can become a valid physical source after rewiring.

### Astral LC donor option

The user observed an approximately CNY 500 Xianyu listing for an ASUS Astral
LC RTX 5090 assembly/PCB with the GPU core and VRAM removed.  This price has
not been independently verified, but if the listing is complete it provides:

- the factory 360 mm radiator, pump, full-coverage cold plate and mounting
  hardware;
- a sacrificial PCB for checking mounting holes, component heights, connector
  pinout and continuity before touching the live card;
- a possible source of intact board-controller/VBIOS reference hardware.

Confirmed public product geometry is three radiator fans plus one on-card
auxiliary fan.  The likely logical topology is one shared radiator-fan group
and one auxiliary-fan group, but the exact mapping of those groups to
PWM10/PWM11 is still unknown.  The donor PCB makes that a narrow continuity
measurement instead of a live-GPU experiment.  If the radiator group maps to
the already active PWM10 route, the Lightning BIOS may operate the useful main
cooling group directly; otherwise its PWM input can be rerouted to PWM10 or a
motherboard header.

### Priority order

1. Repin/reroute the PWM input for physical fans 2/4; this is the lowest-cost,
   shortest-feedback-loop solution.
2. If a clean reversible harness is preferred, make a passive two-layer
   adapter after measuring both connector pinouts.
3. Consider the CNY 500 Astral LC donor only if the pump, radiator, cold plate
   and mounting hardware are present and can be pressure-tested on the dead
   PCB first.
4. Preserve the GSP runtime-object work as research, not as a prerequisite for
   restoring cooling.

### Signature and full-PCB boundary

- Existing VBIOS signatures and public keys are not signing authority.  A
  modified image needs the private signing key/service, an engineering
  authorization path, or a verifier/signer implementation flaw.
- If signing authority existed, rebuilding the missing FAN/GPIO table would
  likely be clean.  It would not by itself provide physical VRAM packages or
  guarantee that fuse-disabled/defective SM/L2 units can operate.
- A 96 GB GB202 configuration additionally needs the corresponding memory
  topology, packages and PCB routing; firmware signing alone cannot create it.
- Designing a whole GB202 board from scratch entails PCIe 5.0, 512-bit GDDR7,
  BGA escape routing, power integrity, sequencing and matching firmware.  A
  proven existing two-slot conversion PCB/service is qualitatively different
  from a one-off home PCB design and is unnecessary for the fan problem.

Known GPIO/PWM facts:

- Astral fan group 2/4 needs GPIO3 as PWM11:
  - Astral GPIO3 DCB: `03 d1 00 80 ef 10`
  - required runtime function/selector: `function=0xd1`, `selector=0x5c`
- Lightning GPIO3 DCB/runtime basis:
  - Lightning GPIO3 DCB: `03 ff 00 00 ef 10`
  - runtime record is effectively `function=0xff`, `selector=0x00`
- GPIO7 is the related tach line for that group.

Do not repeat these already-negative paths:

- Normal fan cooler API only sees one cooler.
- `ActivateHwFunction(function=0xd1, pin=3)` returned `0x0000ffff`; it does not create/upgrade the missing GPIO3 record.
- Direction/output-only GPIO3 tests do not create PWM11 routing.
- Direct BAR0 GPIO pad writes read back `0xbadf1100` / protected and are not a working path.
- The newer decoded selector geometry points at PMGR output-control style
  offset `NV_GPIO_OUTPUT_CNTL(3) = 0x0002120c`, not the older pad offset
  guesses.  However ordinary external RM/regops reads of `0x21200`,
  `0x2120c`, `0x2121c`, `0x21240`, and `0x21244` also returned
  `0xbadf1100`.  Do not repeat plain BAR0/regops probing of these offsets as a
  presumed host-accessible path.
- `NV2080_CTRL_CMD_GPIO_CUSTOMER_ASYNCRW_QUERY = 0x2080a304` was tested as a
  read-only possible alternate GPIO/DCB route under the Lightning 800 W BIOS.
  Indices 0..31 all returned `rm_status=0x00000040` and zero payload, so this
  did not expose a usable GPIO3 runtime/DCB query path on this build.
- MODS JS-level fan helpers modify existing cooler tables; no object-creation path was found there.
- NVD FAN dump succeeded as root via `NV2080_CTRL_CMD_NVD_GET_DUMP`, component 6, on driver `610.43.03`.
  The captured payload was only 120 bytes
  (`/home/user/rt_5090_project/nvdump_runs/fan_component6_root_20260727_054657.pb`,
  sha256 `5c1c9a15fffa0d522f726b7b918eaafef80b48bdd29939a49395cbe4bacbf7cc`).
  It decoded as a tiny wrapped GSP FAN component summary, not a live FanCooler/Fan1 object pointer or object list.
- `RmFan2XOverride` is not a boolean.  Static decode says:
  - value `1` forces an existing-GPIO fan-policy/fallback path;
  - value `2` forces the stronger group/object importer path and is the first
    value to test if a driver/GSP re-init is acceptable.
- Runtime reload tests on Lightning 800 W BIOS:
  - `RmFan2XOverride=2`: driver loads with the key, but NV-CONTROL still exposes exactly one fan target.
  - `RmFan2XOverride=1`: fan telemetry/control target disappears (`nvidia-smi fan.speed=N/A`), no second target appears.
  - `RmFan2XOverride=0x01`: same result as decimal `1`; the issue is not decimal-vs-hex spelling.
  - `RmFan2XOverride=3`: driver loads with the key, but NV-CONTROL still exposes exactly one fan target.
  - Returning to `RegistryDwords="RMUseSwI2c=0x01"` restores the single visible fan target.
- Do not treat `RmFan2XOverride=2` as a proven fix.  The importer remains
  table-driven: it reads table header / entry count / entry size through the
  GSP VBIOS parser and then constructs child objects.  It does not directly
  synthesize the missing Astral GPIO3 `function=0xd1`, `selector=0x5c`.

Current I2C observation under Lightning 800 W BIOS:

- NVIDIA bus 1 read-mode scan sees addresses `0x15`, `0x2b`, `0x67`, `0x68`.
- NVIDIA buses 2/3 look like display DDC/EDID buses; buses 4/5 were empty in read-mode scan.
- This does not identify an out-of-band fan controller for group 2/4; keep I2C as board-MCU identification only unless a register map is found.

Stock ASUS Astral BIOS good-state baseline:

- See `/home/user/rt_5090_project/ASTRAL_STOCK_FAN_BASELINE_20260727.md`.
- With VBIOS `98.02.2E.40.E0`, NV-CONTROL exposes two fan targets.
- LACT static 45% confirms both `[fan:0]` and `[fan:1]` are controllable.
- Asymmetric test `fan0=35%`, `fan1=70%` maps:
  - `fan0 -> PWM10`
  - `fan1 -> PWM11`
- Good-state PWM11 is live:
  - `0x00118ab8 GB202_PWM11_PERIOD_OR_CONFIG = 0x1a000438`
  - `0x00118abc GB202_PWM11_DUTY` tracks fan1 target.
- This contrasts with the recorded Lightning bad state:
  - `PWM11_CONFIG=0x1a0000d8`
  - `PWM11_DUTY=0x00000000`

Runtime PWM11 direct-write result under Lightning 800 W BIOS:

- Tool:
  `/home/user/rt_5090_project/hotspot_reader/pwm11_lightning_ctl`
- Root is required for `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`; user mode returned
  `REG_OPS rm_status=0x0000001f`, while `sudo -n` succeeded.
- Fixed test wrote only:
  - `0x00118ab8 GB202_PWM11_PERIOD_OR_CONFIG`, low config bits
    `0x0d8 -> 0x438`, producing full value `0x1a000438`;
  - `0x00118abc GB202_PWM11_DUTY`, low duty bits
    `0x000 -> 0x292` (`658/1000`, same as ASUS stock fan1 70% test).
- Immediate transaction readback and later readback both kept:
  - `PWM11_CFG=0x1a000438`
  - `PWM11_DUTY=0x00000292`
- `nvidia-settings -q fans` still reported only one fan target after the write.
  Therefore this write proves PWM11 is host-writable and not immediately
  overwritten by GSP, but it does not create the missing RM/NV-CONTROL fan1
  object.
- Physical observation of fans 2/4 after this write is still required to decide
  whether the raw PWM11 route alone is enough to spin the missing group.
- Physical observation result: fans 2/4 did **not** spin.  Fans 1/3 still spun.
  Therefore the raw PWM11 config/duty registers are not sufficient by
  themselves; the missing layer is earlier in the route, most likely the
  GPIO3/PWM11 mux/selector/runtime record rather than the PWM duty latch.
- Additional fixed test: PWM11 was also programmed to mimic the currently
  working Lightning PWM10 shape:
  - `PWM11_CFG=0x000003e8`
  - `PWM11_DUTY=0x00000292`
  The values stuck, but physical fans 2/4 still did **not** spin.  This rules
  out the simple hypothesis that the ASUS-style `0x1a000438` config word was
  the wrong PWM mode for the Lightning BIOS.
- Restore command if needed:
  `sudo -n /home/user/rt_5090_project/hotspot_reader/pwm11_lightning_ctl restore-lightning`

Remaining pure-software target (not the current practical priority):

- Find a host-accessible path that reaches one of these GSP-side primitives:
  1. runtime record setter/helper pair around GSP VA `0x017fe4b8` and
     `0x017fe5b4`.
     Important correction from the 2026-07-28 static audit:
     `0x017fe5b4` is **not** a function/selector setter.  `0x017fe4b8`
     writes the canonical `record+0x724=function`; `0x017fe5b4` only writes
     `record+0x72b` and `record+0x72c`.  The target state is still
     GPIO3 `+0x724=0xd1`, `+0x72b=0x5c`, but the helpers are split.
  2. raw GB202 selector method at GSP VA `0x01802f74`, which preserves the per-pin word and replaces the low selector byte.
     Desired effect: set `selector(GPIO3)=0x5c`.
- Current best decoded selector detail:
  - `0x01802f74` computes register-object relative offset
    `(gpio_index + 0x880) * 4`.
  - For GPIO3, this is `0x220c`.
  - With a likely PMGR register-object base of `0x1f000`, this corresponds to
    BAR0-style `0x2120c`, matching public `NV_GPIO_OUTPUT_CNTL(3)`.
  - This is useful as a static anchor, but normal root/regops reads of that
    address are filtered/protected on the current stack.

Already checked around `0x017fe5b4`:

- Direct callers:
  - `0x0118152c`
  - `0x011f11ee`
  - `0x011f12e4`
  - `0x0121cb92`
  - `0x0122a69e`
  - `0x0122a6fa`
  - `0x0129484e`
  - `0x01294878`
- These look like initialization/table-import paths that take function/selector from parsed temporary tables, not a host-supplied runtime control.
- Other `+0x72b/+0x72c` writes seen in global scans are mostly same-offset fields in unrelated classes or object initializers, not a confirmed GPIO runtime record update path.

Useful next software searches (only if resuming the firmware route):

- Work upward from the eight `0x017fe5b4` callers only if tracing their parents toward RPC/control dispatch, not to rediscover their local parameter extraction.
- Search generated RM control tables for any command whose handler/RPC path reaches GPIO object import/update, not standard fan cooler get/set.
- If doing runtime experiments, prefer one-shot, readback-heavy probes. Avoid broad FB/WPR scans; they have previously caused display/GPU hangs.
- Existing one-shot reload helper:
  `~/rmfan2x-override-reload-test.sh`; current recommendation is to run value
  `2` before value `1`, from TTY/SSH with the desktop stopped and no process
  using `/dev/nvidia*`.
- 2026-07-27 extra registry-key sweep:
  - `RMForceEnableBrightnessOverPwmPin`: display brightness/LCD PWM path, not board fan PWM.
  - `RMSCIVidPWM`: SCI VID/voltage PWM object construction, not fan cooler route.
  - `RMGpioPmuMutexTimeoutus`: GPIO/PMU mutex timeout, not GPIO3/PWM11 selector.
  - `RmPmgrPmuOverride`: PMGR PMU-backend policy bit, not fan topology.
  - `RmPmgrOverride`: PMGR init override; only a possible boot/reload experiment
    candidate, with no static proof that it can synthesize
    `GPIO3 function=0xd1 selector=0x5c`.
  Do not restart investigation by treating these as confirmed fan-enabling
  knobs.

Signature side short status:

- No trivial signature mistake has been observed so far.
- A separate read-only audit verified examples of ECDSA-P384/SHA384 and RSA-PSS/SHA384 signatures successfully; no repeated nonce, obvious small factor, or simple twin-prime-style RSA failure was found in the checked samples.
- “No trivial bug found” is not a proof of no implementation bug. Plausible remaining classes would be parser/canonicalization mistakes, version/board-policy confusion, downgrade/rollback mistakes, or a bug in a signer/offline tool not visible from public samples.

2026-07-27 additional no-repeat boundaries:

- Whole GSP RM method table scan:
  - parsed 1156 method entries from `/tmp/gsp_inner_19f040_a.elf`;
  - direct hits on key GPIO/FanCooler functions are recorded in
    `/home/user/rt_5090_project/full_method_table_key_function_hits_20260727.txt`;
  - the only direct GPIO base/secondary helper method hit is
    `0x20800a58 = NV2080_CTRL_CMD_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER`;
  - low-order reverse-call closure also finds
    `0x20800ac9 = NV2080_CTRL_INTERNAL_GSYNC_IS_DISPLAYID_VALID`;
  - both are display/G-SYNC internal routes and have no fan index, GPIO
    function, selector, DCB fragment, PWM id, or FanCooler create payload.
- Do not treat `0x20800a58` or `0x20800ac9` as fan topology controls merely
  because they touch GPIO helper code.
- NVD FAN component:
  - `component_6.pb` is only 120 bytes and has the same SHA-256 as THERMAL,
    FUSE, and GSP 120-byte wrapper dumps:
    `5c1c9a15fffa0d522f726b7b918eaafef80b48bdd29939a49395cbe4bacbf7cc`;
  - it does not contain fan/cooler records, BoardObjGrp masks, child indexes,
    PWM ids, GPIO function/selector bytes, or live pointers;
  - do not keep decoding this 120-byte protobuf looking for FanCooler state.
- `NV2080_CTRL_CMD_GPU_RPC_GSP_TEST` / `QUERY_SIZES`:
  - not arbitrary GSP RPC invocation;
  - TEST only performs fixed integrity/NOP/timeout behavior or a fixed
    GET_IP_VERSION route.
- `NV2080_CTRL_CMD_INTERNAL_MEMMGR_MEMORY_TRANSFER_WITH_GSP`:
  - transfer-surface physical memcpy/memset ABI, not GSP private heap VA
    access;
  - current configuration was already classified as `NV_ERR_NOT_SUPPORTED`.
- `NV2080_CTRL_CMD_INTERNAL_CONTROL_GSP_TRACE` and
  `NV2080_CTRL_CMD_GSP_CRYPTO_CONTROL`:
  - trace logging / crypto operation ABIs;
  - not GSP object lookup, arbitrary function invoke, or heap read/write
    routes.
- `NV2080_CTRL_CMD_INTERNAL_GPU_GET_GSP_RM_FREE_HEAP = 0x20800aeb`:
  - exact 610.43.03 parameter struct is only one output field,
    `NvU64 freeHeapSize`;
  - dispatch row is `handler=0x01431074 flags=0xc0 psize=0x8`;
  - handler stores an internal aggregate free-size value to params+0 and
    returns `NV_OK`;
  - it is not a heap base leak, allocation list, object address, or private GSP
    VA reader.  Do not restart from this command as if it can locate
    `gpio_object`.
- Current safe conclusion: normal RM control/NVD/debug-test ABI still has no
  found route for installing Lightning's missing GPIO3 `function=0xd1`,
  `selector=0x5c`, or for creating the missing second FanCooler object.

2026-07-28 static-audit correction boundaries:

- Correct GSP ELF code mapping for `/tmp/gsp_inner_19f040_a.elf` is
  `file_offset = VA - 0x01000000` for executable-code VAs.  Do not use
  `file_offset = VA` when regenerating snippets.
- `object+0x25a4` is `line_count`, not record count.
- `object+0x02f8` is record-bank count.
- `object+0x6c8` is not proven to be an object-level active/occupancy mask.
  With the confirmed formula `function_table[f] = object + 0x328 + f*4`,
  `object+0x6c8` is exactly `function_table[0xe8]`.
- Wrapper `0x01801fa4` jumps to `0x01801ee4`; snippets starting at
  `0x01801ee8` miss the first four bytes of the callee.
- `0x01805b30` reads `+0x72b/+0x72c`; if both are zero it calls raw selector
  with fixed selector `3`.  It is not an arbitrary PWM11 selector route and
  should not be treated as a way to set selector `0x5c`.
