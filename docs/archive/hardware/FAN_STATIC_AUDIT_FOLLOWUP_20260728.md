# FAN static audit follow-up, 2026-07-28

Scope: static/offline only.  No live GPU access, no BAR/MMIO/FB/WPR/GSP heap
read, no reset, no VBIOS change.

## Short conclusion

GPT Pro's second response is materially useful.  It mostly did not open a new
runtime route; instead it corrected field semantics and narrowed the remaining
unknowns.

The main causality still holds:

```text
ASUS stock BIOS builds two fan/cooler routes
Lightning BIOS builds only one route
PWM11 duty/config alone can be written but does not spin physical fans 2/4
missing layer is before PWM11 duty latch, most likely GPIO3 selector/runtime record
ActivateHwFunction only applies an already-existing record
```

The current hard blocker remains unchanged:

```text
safe way to locate/read/modify the live GSP GPIO object, or a normal ABI that
causes GSP to rebuild that object from corrected topology data
```

## Important corrections accepted

### `0x017fe5b4` is not a function/selector setter

Correct split:

```text
0x017fe4b8 writes base/canonical function:
  record + 0x00 / object+0x724 = function

0x017fe5b4 writes only secondary bytes:
  record + 0x07 / object+0x72b = selector used by Activate
  record + 0x08 / object+0x72c = secondary/auxiliary byte, exact meaning unknown
```

Therefore the old shorthand:

```text
0x017fe5b4(gpio, line, function, selector)
```

is wrong.  Better:

```text
0x017fe5b4(gpio, line, secondary_byte_0, secondary_byte_1)
```

For the target Astral route:

```text
+0x724 should be 0xd1
+0x72b should be 0x5c
+0x72c should not be guessed; copy from known-good state or close its consumer first
```

### `object+0x25a4` is line count

`0x017fe4b8`, `0x017fe5b4`, `0x017f699c`, and `0x01805b30` all use:

```text
object + 0x25a4  line_count
```

The earlier label "record count" for this field was wrong.  The actual record
bank count is:

```text
object + 0x02f8  record_count
```

### `object+0x6c8` is not proven to be an object-level mask

Given the confirmed function table formula:

```text
function_table[f] = object + 0x0328 + f * 4
```

then:

```text
object + 0x06c8 = function_table[0xe8]
```

So any old note treating `+0x6c8` as an independent object-level active mask is
not proven.  It may be a misidentified function-table entry, a different base,
or a missing base adjustment in that old window.

### Activate exact target

The wrapper at `0x01801fa4` jumps to `0x01801ee4`, not logically to
`0x01801ee8`.  A snippet starting at `0x01801ee8` is missing the first four
bytes of the real callee.

## Local static files generated after GPT Pro's request

```text
gsp_callsite_normalization_manifest.txt
gpio_activate_vmethod_017f699c_full.txt
gpio_selector_consumer_01805b30_full.txt
gpio_runtime_getters_017fe640_017fed50.txt
gpio_line_map_xrefs_3598_refined.txt
gpio_function_entry_second_qword_xrefs_refined.txt
rm_disable_therm_only_gpio_raw_windows.txt
display_af0_af1_af2_handlers_callgraph.txt
nvml_fan_api_declarations_610.43.03.txt
nvcontrol_fan_attributes_610.43.03.txt
gpio_vtable_constructor_019422e0_019426c0.txt
```

All regenerated disassembly files use the corrected executable mapping:

```text
file_offset = GSP_code_VA - 0x01000000
```

## Immediate observations from the new static files

### `gpio_activate_vmethod_017f699c_full.txt`

Confirms the Activate vmethod consumes already-existing record state:

```text
017f69aa  load line_count from object+0x25a4
017f69b4  fail if pin >= line_count
017f69ca  load record+0x724 function
017f69ce  fail if function != requested function
017f69d2  load record+0x72b selector
017f69d6  fail if selector == 0
017f69da  load vtable+0x250
017f69ec  jump raw selector method
```

No writes to `+0x724`, `+0x72b`, `+0x72c`, function table, line map, or
FanCooler objects occur in this path.

### `gpio_selector_consumer_01805b30_full.txt`

Confirms this helper also consumes record secondary bytes:

```text
01805b64  lbu +0x72b
01805b68  lbu +0x72c
01805b70  if both are zero, call vtable+0x250 with fixed selector 3
01805b96  otherwise pass +0x72b into vtable+0x290 path
```

This is not a PWM11 `0x5c` arbitrary selector route.  It is useful evidence for
the meaning of `+0x72b/+0x72c`, but not a direct solution.

### `gpio_line_map_xrefs_3598_refined.txt`

The refined pattern found the expected line-map use sites:

```text
0x017fe51c  0x017fe4b8 record_index==0 path writes line-map entry zero
0x017fe5d2  0x017fe5b4 reads line -> record_index
0x017fe6aa  getter/helper reads the same line-map shape
0x017fe78a  getter/helper reads the same line-map shape
```

It also found several earlier candidates around `0x0177dxxx` with the same
arithmetic pattern; those need separate ownership classification before being
called GPIO-object accesses.

Current static status:

- line-map read semantic is confirmed;
- the only confirmed write in this helper family is the `record_index == 0`
  zeroing path in `0x017fe4b8`;
- non-zero line-map writer remains unknown.

### `gpio_function_entry_second_qword_xrefs_refined.txt`

Near the known GPIO helper/getter area, clear direct accesses are to the low
64-bit qword at:

```text
object + 0x25a8 + function*0x10
```

The refined search did not find a clear local GPIO-helper use of:

```text
object + 0x25a8 + function*0x10 + 8
```

Only one broader candidate direct memory access to `0x5b0(...)` remains at
`0x01b55ea8`; it is not yet proven to share the same GPIO object base.

### `display_af0_af1_af2_handlers_callgraph.txt`

Dispatch rows:

```text
0x20800af0 handler=0x0121f808 flags=0xc0 psize=0
0x20800af1 handler=0x012172ec flags=0xc0 psize=0
0x20800af2 handler=0x01217398 flags=0xc0 psize=0
```

All three are singleton/no-payload controls.  They cannot carry a GPIO line,
function, selector, DCB record, fan index, or FanCooler descriptor through their
external ABI.

`af1/af2` fetch display state and dispatch through internal display object
vtable slots.  No direct call to the GPIO base helper, secondary helper, raw
selector, FanCooler importer, or FanCooler allocator appears in the bounded
windows.

This is strong negative evidence against using display pre/post modeset as a
normal fan-topology import path.  It is not a full transitive-vtable proof.

### NVML and NV-CONTROL public fan APIs

The extracted headers show public fan/cooler APIs are index/target based:

```text
nvmlDeviceGetNumFans
nvmlDeviceGetFanSpeed_v2(device, fan, ...)
nvmlDeviceSetFanSpeed_v2(device, fan, speed)

NV_CTRL_TARGET_TYPE_COOLER
NV_CTRL_GPU_COOLER_MANUAL_CONTROL
NV_CTRL_THERMAL_COOLER_LEVEL
NV_CTRL_THERMAL_COOLER_CURRENT_LEVEL
```

No public declaration carries topology payload such as GPIO function, selector,
PWM mux, DCB record, or FanCooler create descriptor.  This matches the runtime
observation that these APIs operate already-created targets.

## Current ranking

1. **Static closure of GPIO object construction/update path**
   - Find non-zero line-map writer.
   - Classify `+0x72c`, `+0x72a`, `+0x72d`.
   - Close whether `+0x25a8+function*0x10+8` matters.

2. **Locate a normal/reload path, if any**
   - Current public RM/NVD/NVML/NV-CONTROL/registry evidence remains negative.
   - Any candidate must show actual data flow from a payload or table source
     into `0xd1/0x5c` runtime record fields.

3. **Live object route**
   - Still blocked by safe single-address GSP private-object access.
   - Do not retry broad heap/FB/WPR scans.

## Files to send for another GPT Pro static pass

If continuing the webpage GPT Pro thread, send these first:

```text
FAN_STATIC_AUDIT_FOLLOWUP_20260728.md
gsp_callsite_normalization_manifest.txt
gpio_activate_vmethod_017f699c_full.txt
gpio_selector_consumer_01805b30_full.txt
gpio_runtime_getters_017fe640_017fed50.txt
gpio_line_map_xrefs_3598_refined.txt
gpio_function_entry_second_qword_xrefs_refined.txt
rm_disable_therm_only_gpio_raw_windows.txt
display_af0_af1_af2_handlers_callgraph.txt
```

Only add these if it asks about public APIs:

```text
nvml_fan_api_declarations_610.43.03.txt
nvcontrol_fan_attributes_610.43.03.txt
```

Good next question for GPT Pro:

```text
Please continue only static analysis.  Using the new files, identify:

1. the non-zero writer/lifecycle for object+0x3598+line*4;
2. whether record+0x72c, +0x72a, or +0x72d affects selector activation;
3. whether object+0x25a8+function*0x10+8 is used by the same GPIO object;
4. whether display af0/af1/af2 have any transitive vtable path to GPIO/FanCooler
   importer despite psize=0;
5. the minimum additional static windows needed if the above cannot be decided.

Do not propose live patching, protected memory read/write, exploit primitives,
or firmware modification.  Keep the output to facts/inferences/unknowns and
minimal static files.
```
