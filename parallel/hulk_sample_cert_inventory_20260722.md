# MODS bundled HULK sample-certificate inventory — 2026-07-22

## Scope

This is a static/offline inventory of the HULK sample JavaScript files bundled
inside the extracted MODS package. No MODS binary was run. No GPU, device node,
BAR, firmware, VBIOS, or network endpoint was touched.

Files searched:

```text
mods_audit/static/**/HULK*.js
```

There are 8 JS wrapper files and 6 unique byte payloads.

## Unique payloads

| File | Payload bytes | SHA256 | Clear device id |
|---|---:|---|---:|
| `HULK_figueroa_2685.js` | 360 | `abae3c58521a18734eeb068a01556ba13571da65431ec49ec389397de60da8c9` | `0x2685` |
| `HULK_figueroa_2816.js` | 304 | `7dd232d267213d6b35d837c7bef9169207600e5be4b5ed080978aecf723ddb7a` | `0x2816` |
| `HULK_figueroa_2817.js` | 664 | `324f6479411742f3ae99f2536fada511f24ed870e9f80210d766a482228cd705` | `0x2817` |
| `HULK_figueroa_2929.js` | 552 | `d5482eab4fd5b962178bb57ad428d1cb7a494500d4a52108ebb4f419df609aff` | `0x2929` |
| `HULK_figueroa_3414.js` | 340 | `02a0759ef7f77c962f300c661a4c21e7d0592f710164b0b1a196edc3eee3aa73` | `0x3414` |
| `HULK_figueroa_3415.js` | 536 | `76451eb302c3b1e02b2b1b5d445816b5e2bc7ce77977296b5bc6a7f38021b8aa` | `0x3415` |

The local RTX 5090 / GB202 PCI device id is `0x2b85`, so none of these payloads
is a clear match for the target card.

## Header observations

The first payload dwords have a stable shape:

```text
fmt, 0x2c, device_id, total_size, 0x0c, 0x02000002, 0x05, 0x01, 0x01, ...
```

The older samples use `fmt=0x20`. `HULK_figueroa_3415.js` uses `fmt=0x22` and
has an extra small per-record-section header before the register list.

This inventory does not attempt to validate signatures or reconstruct the full
certificate grammar. The purpose here is only to decide whether the bundled
samples contain a useful GB202/f8 action.

## Register-action list evidence

The payloads contain clear 12-byte register-operation records that fit:

```text
u32 address
u32 and_mask
u32 or_value
```

Examples:

```text
addr=0x0040964c and=0xffffff00 or=0x000000ff
addr=0x009a0170 and=0xffffff00 or=0x000000ff
addr=0x000205d8 and=0xfffffffd or=0x00000002
addr=0x02409674 and=0xfffffff6 or=0x00000009
```

That supports the previous inference that HULK can carry signed
certificate-driven register RMW actions instead of relying on target addresses
being hard-coded in GSP text.

## Negative search for this project's target registers

Each unique payload was searched for little-endian and big-endian occurrences
of the target words:

```text
0x008200f8
0x008200dc
0x00820040
0x008234e0
0x00002b85
```

Result:

- no `0x008200f8`;
- no `0x008200dc`;
- no `0x00820040`;
- no `0x008234e0`;
- no `0x00002b85`.

The only device-id hits are the clear ids matching the filenames:

```text
0x2685 0x2816 0x2817 0x2929 0x3414 0x3415
```

## Conclusion

Useful facts:

- These bundled samples demonstrate the HULK payload family can contain
  explicit register RMW records.
- They are not opaque names-only markers; at least part of the action list is
  plainly visible.
- A separate VFIO-VM FSP CAPS readback reports HULK NVDM type `0x11`,
  version `1`, as present on the current card/FSP.

Not useful for the current GB202/L2 problem:

- No bundled sample targets the RTX 5090 device id `0x2b85`.
- No bundled sample references `0x8200f8`, `0x8200dc`, `0x820040`, or the raw L2
  mask base.
- Therefore the local MODS package does not contain a ready-made GB202/f8 HULK
  action.

Practical implication:

- HULK remains a theoretical route only if a legitimate GB202/device-bound
  certificate exists with a relevant f8/latch action.
- The bundled MODS samples do not provide that certificate and should not be
  run on the 5090.
