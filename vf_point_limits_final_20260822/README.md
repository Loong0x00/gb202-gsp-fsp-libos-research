# GB202 GPC/XBAR per-point V/F limits (2026-08-22)

## Interpretation

- `confirmed_boundary`: max-pass was repeated for 5 seconds; the next 15 MHz grid point did not pass.
- `nonrepeating*`: a 2-second pass existed, but the same point did not repeat for 5 seconds.
- `point_not_activated*`: direct trials could not make that voltage point active.
- `unreachable*`: no offset is reported because the source point is outside the live rail/policy envelope.

A V/F compiler value is not a promise of final clock grant. `measured_domain_mhz`, rail identity, checked workload status, and kernel health are separate evidence layers.

## Physical envelope

- NVVDD: VMIN 800 mV, reliability/max 1200 mV.
- MSVDD: VMIN 870 mV, current reliability/max 1000 mV.
- Policy0 final GPC ceiling observed: 3135 MHz.
- Tested power regimes: GPC p55-91 at 600 W; GPC high region at short 800 W windows; XBAR p66-88 at 600 W.
- Both experimental banks were byte-identical to their experiment preimages before services were restored.
- Starting persistent LACT afterwards intentionally reapplied the user's daily curve; its separate post-service hashes are in `state.json`.

## Counts

### GPC

- confirmed_boundary: 34
- nonrepeating_boundary: 18
- nonrepeating_short_boundary: 2
- point_not_activated_at_policy_ceiling: 1
- point_not_activated_in_tested_range: 3
- unreachable_policy_and_rail_max: 6
- unreachable_policy_limit: 8
- unreachable_rail_vmin: 55

### XBAR

- confirmed_boundary: 20
- nonrepeating_boundary: 3
- unreachable_rail_reliability_max: 38
- unreachable_rail_vmin: 66

## Directly tested points

|Bank|Point|Source mV|Base MHz|Max pass MHz|First nonpass MHz|Class|5 s|
|---|---:|---:|---:|---:|---:|---|---|
|GPC|55|795|592|30|45|confirmed_boundary|PASS|
|GPC|56|800|675|285|300|nonrepeating_boundary|NOT_HIT|
|GPC|57|810|757|90|105|confirmed_boundary|PASS|
|GPC|58|815|847|0|15|confirmed_boundary|PASS|
|GPC|59|820|930|0|15|confirmed_boundary|PASS|
|GPC|60|825|1020|45|60|confirmed_boundary|PASS|
|GPC|61|835|1102|210|225|nonrepeating_boundary|NOT_HIT|
|GPC|62|840|1192|75|90|confirmed_boundary|PASS|
|GPC|63|845|1275|15|30|confirmed_boundary|PASS|
|GPC|64|850|1365|0|15|confirmed_boundary|PASS|
|GPC|65|860|1447|75|90|confirmed_boundary|PASS|
|GPC|66|865|1537|45|60|confirmed_boundary|PASS|
|GPC|67|870|1620|30|45|nonrepeating_boundary|NOT_HIT|
|GPC|68|875|1702|135|150|nonrepeating_boundary|NOT_HIT|
|GPC|69|885|1792|15|30|nonrepeating_boundary|NOT_HIT|
|GPC|70|890|1875|15|30|nonrepeating_boundary|NOT_HIT|
|GPC|71|895|1965|135|150|confirmed_boundary|PASS|
|GPC|72|900|2047|60|75|nonrepeating_boundary|NOT_HIT|
|GPC|73|910|2137|30|45|nonrepeating_boundary|NOT_HIT|
|GPC|74|915|2220|0|15|nonrepeating_boundary|NOT_HIT|
|GPC|75|920|2302|0|15|confirmed_boundary|PASS|
|GPC|76|925|2392|60|75|confirmed_boundary|PASS|
|GPC|77|935|2475|30|45|nonrepeating_boundary|NOT_HIT|
|GPC|78|940|2565||0|point_not_activated_in_tested_range||
|GPC|79|945|2632|0|15|nonrepeating_boundary|NOT_HIT|
|GPC|80|950|2655|45|60|confirmed_boundary|PASS|
|GPC|81|960|2677|75|90|nonrepeating_boundary|NOT_HIT|
|GPC|82|965|2692|75|90|nonrepeating_boundary|NOT_HIT|
|GPC|83|970|2715|75|90|confirmed_boundary|PASS|
|GPC|84|975|2737|75|90|confirmed_boundary|PASS|
|GPC|85|985|2760|225|240|confirmed_boundary|PASS|
|GPC|86|990|2775|375|390|nonrepeating_boundary|NOT_HIT|
|GPC|87|995|2797|360|375|nonrepeating_boundary|NOT_HIT|
|GPC|88|1000|2827|330|345|nonrepeating_boundary|NOT_HIT|
|GPC|89|1010|2850|375|390|nonrepeating_boundary|NOT_HIT|
|GPC|90|1015|2865|450|465|nonrepeating_boundary|NOT_HIT|
|GPC|91|1020|2887|15|30|confirmed_boundary|PASS|
|GPC|92|1025|2902|495|720|nonrepeating_short_boundary|NOT_HIT|
|GPC|93|1035|2917|480|495|confirmed_boundary|PASS|
|GPC|94|1040|2932|420|435|confirmed_boundary|PASS|
|GPC|95|1045|2940|390|405|confirmed_boundary|PASS|
|GPC|96|1050|2955|15|30|confirmed_boundary|PASS|
|GPC|97|1060|2962|150|165|confirmed_boundary|PASS|
|GPC|98|1065|2977|330|345|confirmed_boundary|PASS|
|GPC|99|1070|2992|330|345|confirmed_boundary|PASS|
|GPC|100|1075|3000|345|360|confirmed_boundary|PASS|
|GPC|101|1085|3015|375|390|confirmed_boundary|PASS|
|GPC|102|1090|3030|360|375|confirmed_boundary|PASS|
|GPC|103|1095|3037|375|390|confirmed_boundary|PASS|
|GPC|104|1100|3052|90|105|nonrepeating_short_boundary|NOT_HIT|
|GPC|105|1110|3060||0|point_not_activated_in_tested_range|NOT_HIT|
|GPC|106|1115|3075|60|75|confirmed_boundary|PASS|
|GPC|107|1120|3082|30|45|confirmed_boundary|PASS|
|GPC|108|1125|3097|240|255|confirmed_boundary|PASS|
|GPC|109|1135|3105|360|375|confirmed_boundary|PASS|
|GPC|110|1140|3112|345|360|confirmed_boundary|PASS|
|GPC|111|1145|3127||0|point_not_activated_in_tested_range||
|GPC|112|1150|3135||0|point_not_activated_at_policy_ceiling|NOT_HIT|
|XBAR|66|865|2025|75|90|confirmed_boundary|PASS|
|XBAR|67|870|2047|105|120|confirmed_boundary|PASS|
|XBAR|68|875|2070|135|150|confirmed_boundary|PASS|
|XBAR|69|885|2092|45|60|nonrepeating_boundary|NOT_HIT|
|XBAR|70|890|2115|90|105|confirmed_boundary|PASS|
|XBAR|71|895|2130|90|105|confirmed_boundary|PASS|
|XBAR|72|900|2152|135|150|confirmed_boundary|PASS|
|XBAR|73|910|2175|150|165|confirmed_boundary|PASS|
|XBAR|74|915|2197|165|180|confirmed_boundary|PASS|
|XBAR|75|920|2212|180|195|confirmed_boundary|PASS|
|XBAR|76|925|2235|195|210|confirmed_boundary|PASS|
|XBAR|77|935|2250|210|225|confirmed_boundary|PASS|
|XBAR|78|940|2272|225|240|confirmed_boundary|PASS|
|XBAR|79|945|2287|240|255|confirmed_boundary|PASS|
|XBAR|80|950|2302|225|240|confirmed_boundary|PASS|
|XBAR|81|960|2325|225|240|confirmed_boundary|PASS|
|XBAR|82|965|2340|480|495|confirmed_boundary|PASS|
|XBAR|83|970|2355|375|390|nonrepeating_boundary|NOT_HIT|
|XBAR|84|975|2377|315|330|confirmed_boundary|PASS|
|XBAR|85|985|2392|600|615|confirmed_boundary|PASS|
|XBAR|86|990|2407|585|600|confirmed_boundary|PASS|
|XBAR|87|995|2422|540|555|nonrepeating_boundary|NOT_HIT|
|XBAR|88|1000|2437|540|555|confirmed_boundary|PASS|

Full 254-row detail and provenance are in `vf-point-limits.csv` and `vf-point-limits.json`.
