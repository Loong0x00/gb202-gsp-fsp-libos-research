# AM5 water-loop fan audit — 2026-09-17

## Finding

The controller did not crash and reported no sensor failure/restart. Its policy is nevertheless mismatched to AM5 die-hotspot behavior and a very large water loop.

`/usr/local/sbin/waterloop-fan-control` has no coolant sensor. It treats either CPU Tctl >=70C or package power >=120W in4/8 samples as sustained load, then forces radiator PWM>=57 (~1200RPM) and pump PWM>=106 (~3000RPM). Release requires45s continuously below Tctl/fast68C and package budget100W. A 9950X3D can remain around70–74C at moderate localized load while coolant/socket remains much cooler, so this state can remain latched indefinitely.

Observed during the sleep-period run:

- heavy phase: Tctl78–80C, package181–186W, pump3619–3688RPM, radiator1461–1503RPM;
- one-core low-priority continuation plus other existing EVM work: Tctl70–73C, package~95–120W, pump~3000RPM, radiator1215–1222RPM;
- controller fields: `early=1`, `pump_power_floor=106`, no failures;
- current spot check: Tctl73.9C, CPUTIN41.5C, SYSTIN38C, GPU33C/0% fan.

Cold-feeling tubing is therefore consistent with the data. Tctl is a silicon hotspot/control value, not coolant temperature. The 1080/45mm nine-fan radiator can dissipate100–120W with an almost imperceptible coolant rise, while the current rule still commands all radiator fans to ~1200RPM.

## Additional source

Motherboard fan2 is under BIOS automatic control and was observed around1390–1410RPM. The custom service directly controls only pwm3/fan3 (radiator bank) and pwm4/fan4 (pump). fan2 may add noise independently and needs physical/header identification before changing it.

## Shared-loop GPU auxiliary bound

Because the RTX5090 is bare-die water blocked in the same passive loop, an idle/low-power GPU can provide a conservative coolant upper bound. Without a chiller or other active refrigeration, heat flows from die to coolant, so a stable GPU die temperature cannot sit tens of degrees below the coolant. During the CPU workload the GPU repeatedly remained around30–33C (hotspot34–37C). Coolant near60C is therefore physically incompatible with the telemetry; after sensor tolerance the water was still far below60C.

This is not an exact water thermometer. It is valid only after sustained low GPU power, valid edge/hotspot telemetry and confirmed pump flow. Under GPU load the die-to-water delta grows and the inference must be disabled. A safe controller can use a slow, low-power GPU edge temperature as a `coolant_is_cool` veto against the CPU70C starter, while retaining every direct Tctl critical/pump path.

## Safe correction direction

1. Best: add/use a calibrated10k coolant probe and control radiator fans from coolant temperature; retain CPU/GPU critical overrides.
2. Until then, require about60s of low GPU power plus valid pump tach before accepting GPU edge as a coolant upper-bound proxy. A stable edge below roughly35–38C can suppress the CPU-only radiator starter; it must never suppress CPU warm/critical or telemetry-failure protection.
3. When the GPU proxy is invalid, fall back to validated slow CPUTIN plus sustained high package power, not Tctl>=70 alone. Keep Tctl for pump and immediate95C protection.
4. Separate CPU and GPU starter floors. The validated575W GPU case may retain1200RPM; a100–120W CPU workload should not automatically request the same nine-fan floor.
5. Preserve immediate critical/failure paths and deploy only with atomic backup, offline state-transition tests, low-load handoff, and guarded thermal validation.

No active fan policy was modified by this audit.
