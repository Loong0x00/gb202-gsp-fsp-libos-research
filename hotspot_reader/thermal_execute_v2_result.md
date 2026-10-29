# Thermal System Execute V2 read-only enumeration

Run on 2026-07-14 (Asia/Singapore), RTX 5090 `0000:01:00.0`, driver
610.43.03.  Command:

```
cd /home/user/rt_5090_project/hotspot_reader
make thermal_execute_v2_probe
sudo ./thermal_execute_v2_probe
```

The probe submits only published GET opcodes through RM control `0x20800513`:

* `0x0500` sensors available
* `0x0510` sensor provider
* `0x0520` sensor target
* `0x0540` reading range
* `0x1500` current reading
* `0x0301` provider type and `0x0101` target type, after valid indices

Observed overview and the only valid sensor:

```
overview rm_status=0x00000000 successful=1
sensors   exec=1 result=0x00000000 out0=0x00000001
targets   exec=1 result=0x00000000 out0=0x00000001
sensor[00] rm_status=0x00000000 successful=4
provider  exec=1 result=0x00000000 out0=0 out1=0
target    exec=1 result=0x00000000 out0=0 out1=0
range     exec=1 result=0x00000000 out0=0 min=0 max=127
reading   exec=1 result=0x00000000 out0=0 value_signed=50
prov_type exec=1 result=0x00000000 out0=0 out1=1
targ_type exec=1 result=0x00000000 out0=0 out1=1
```

At the same time, `nvidia-smi` reported edge 50 C and power 168.68 W, so sensor
0 is the ordinary GPU/edge reading.

Full index-result matrix (all commands returned outer RM status `0`; every
instruction had `executed=1`):

| index | provider result | target result | range result | reading result | reading |
|---:|---:|---:|---:|---:|---:|
| 0 | `0x00000000` | `0x00000000` | `0x00000000` | `0x00000000` | 50 C |
| 1 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 2 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 3 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 4 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 5 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 6 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 7 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 8 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 9 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 10 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 11 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 12 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 13 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 14 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 15 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 16 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 17 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 18 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 19 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 20 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 21 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 22 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 23 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 24 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 25 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 26 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 27 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 28 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 29 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 30 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |
| 31 | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | `0x0000ffff` | invalid |

Conclusion: the public Thermal System instruction layer exposes exactly one
sensor on this GB202 firmware, and it is edge temperature.  No hotspot sensor
leaks through indices 1 through 31.
