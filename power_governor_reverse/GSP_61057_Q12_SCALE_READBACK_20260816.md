# R610.57.04 `clkUpScale` / `clkDownScale` proof chain

All runtime queries below used `NV2080_CTRL_CMD_PMGR_PWR_POLICY_GET_STATUS`
(`0x2080a61a`).  They did not issue SET_CONTROL, add load, touch MMIO, or change
GPU state.

## Current GSP transport and object mapping

Firmware: `/tmp/gsp61057.L2bKY9/gsp_inner_61057.elf`

```text
size   = 82558976
sha256 = 88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e
```

The current GSP control table entry at `0x01c20040` is:

```text
command = 0x2080a61a
size    = 0x3610
handler = 0x01762544 (inside power_policies_get_status_61057 at 0x01762438)
```

The combined-policy constructor `0x01af4d50` allocates a `0x3a0`-byte object.
Its interface selector `0x01795d10` returns object `+0x338` for selector 0,
which is the interface used by the GET_STATUS handler.  The corresponding
getter starts at `0x017a0d38` and performs these exact U16 copies after its
base getter succeeds:

```text
status_record + 0x16 <- object + 0x390
status_record + 0x18 <- object + 0x392
```

The paired control getter/setter methods `0x017a09c8` / `0x017a171c` export and
import the same object fields at the same status/control record offsets.  The
constructor copies object `+0x390/+0x392` from the corresponding configuration
fields.

## Field names

In the GB202 R570 MODS binary, strings at file offsets `0x0886f190` and
`0x0886f1c0` are:

```text
policies[%u].data.workload.clkUpScale
policies[%u].data.workload.clkDownScale
```

Their only code references are the control/status printer at `0x016899c7` and
`0x016899dd`.  It reads two consecutive U16 fields in this order.  Thus the
current GSP getter/setter pair above is the expanded R610 ABI location of the
same two workload-policy Q12 controls, rather than a value-shape guess.

## Current readback

R610 status records begin at `0x14` with stride `0xc4`.  Three consecutive
readbacks of each live type-`0x14` policy returned the same pair:

```text
policy 0:  record +0x16 = 0x0800, record +0x18 = 0x1000
policy 10: record +0x16 = 0x0800, record +0x18 = 0x1000
policy 16: record +0x16 = 0x0800, record +0x18 = 0x1000
```

Therefore, for the current boot:

```text
clkUpScale   = 0x0800 = 2048 = 0.5 Q12
clkDownScale = 0x1000 = 4096 = 1.0 Q12
```

Together with the recovered GB202 R570 PMU arithmetic, one PMU tracker update
is now executable with current coefficients:

```text
up:   old + round_half_up((new-old) / 2)
down: new
```

This proves the scale coefficients.  It does not by itself rule out a separate
dwell, hysteresis, P-state, or error-recovery gate elsewhere in the scheduler.

## Reproduction

```bash
cc -O2 -Wall -Wextra -Werror -o /tmp/power_cap_limit_probe.test \
  /home/user/rt_5090_project/power_cap_limit_probe.c

for i in 0 10 16; do
  /tmp/power_cap_limit_probe.test --policy-status-entry-raw "$i"
done
```
