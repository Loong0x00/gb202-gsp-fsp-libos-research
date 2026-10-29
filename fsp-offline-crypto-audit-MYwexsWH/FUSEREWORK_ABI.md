# MODS 570.215 FuseRework ABI reconstruction

Status: static-only; no FSP command sent and no hardware state changed.

## Application payload for outer command `0x0f`

`FuseReworkExecute` (`0x173b050`) appends these fields in order. Values are copied little-endian by the x86-64 host.

| Payload offset | Size | Source / meaning |
|---:|---:|---|
| `0x000` | 2 | Inner selector from helper `+0x12`; orchestrator sets it to `1` |
| `0x002` | 2 | Constant `0x0348`; semantics still unknown |
| `0x004` | 8 | Opaque qword at helper `+0x20`, produced by the first `FuseReworkLoadOne` |
| `0x00c` | `0x30` | Contents of `fuserework_debug_gfw_hash.bin` |
| `0x03c` | `0x180` | Contents of `fuserework_debug_gfw_pub_key.bin` |
| `0x1bc` | `0x180` | Contents of `fuserework_debug_gfw_sig.bin` |
| `0x33c` | 8 | Opaque qword at helper `+0x30`, produced after `FuseReworkTransfer` |
| `0x344` | 2 | Low 16 bits of staged transfer length (`helper[0xb8]-helper[0xb0]`) |

Visible appended payload length is `0x346` bytes. The embedded constant is `0x348`, two bytes larger; it is not yet proven to be the payload length. The difference may be an outer header/length convention or an unidentified reserved field.

## Transport call

The call is:

```text
FspSendRequestCandidate(ctx, 0x0f, 0xffffffff, request_vector, 0, response_vector)
```

- `0x0f` is the outer FSP command/use-case, distinct from the inner selector `1`.
- Builder state records command `0x0f`, secondary byte `0xff`, and dword `0`.
- Transport selector is cached at context `+0x70`; transport object is at `+0x90`.
- Transport vtable `+0x38` sends each packet/fragment; `+0x30` receives the response.
- Unfragmented first packet uses flags `0xc8`; a fragmented first packet uses `0x88`; continuation flags encode a two-bit sequence and a final-fragment marker.
- The request size estimate for command `0x0f` is `(payload_len + 0xb) & ~3`; for `0x346`, this is `0x350`.

## Response validation

`FuseReworkParseResponse` (`0x173ab30`) requires:

- response length exactly 4 bytes;
- little-endian response word exactly `0x0000000f`.

Length mismatch returns `2`; value mismatch returns `0x21f`.

## Main file and side files

The constructor sets default paths for the three side files:

- `fuserework_debug_gfw_hash.bin` — `0x30` bytes
- `fuserework_debug_gfw_pub_key.bin` — `0x180` bytes
- `fuserework_debug_gfw_sig.bin` — `0x180` bytes

`fuserework.bin` exists as a MODS string and the orchestrator loads a main input into helper `+0x98`, then parses it through mode `2`. The selected static chain strongly suggests this is the main FuseRework input, but the exact filename-to-callsite binding is not directly represented by a Ghidra xref and remains a stated uncertainty.

The main-input loader rejects files `>= 0x200000` bytes. It maps the parsed image and returns opaque qwords used in the command payload rather than appending the original file bytes directly.

## Mode-2 main-input formats

The first 4 bytes are:

```text
u8 flags (must be odd)
u8 type  (2, 3, or 4)
u16 header_size
```

Observed versions include `0x0201` (`01 02`, FUB v2) and `0x0403` (`03 04`, GFW v4).

- Type 2: two sections; known `fub_ga100.bin` uses header `0x3c` and exact size `header + section1 + section2`.
- Type 3: two sections using lengths at header offsets `+0x14` and `+0x20`.
- Type 4: standard GFW-v4-style three-section geometry.

Targeted carving of the 4 GiB MODS image found five unique type-2 helpers. The only low-entropy embedded helper (`e466ed...`, `0x3984` bytes) disassembles as Falcon fuc5 and carries a `May 4 2017` DMEM build date, so it is old Falcon firmware, not Blackwell FSP/RISC-V plaintext. The other embedded type-2 helpers also decode as Falcon fuc5 or are encrypted FUB variants.

Evidence files:

- `ghidra_fuserework_orchestrator.c`
- `ghidra_fuserework_payload_helpers.c`
- `ghidra_fuserework_fileload_helpers.c`
- `ghidra_fuserework_mode2_parsers.c`
- `ghidra_fsp_sender_helpers.c`
- `carve_fuserework_mode2.py`
- `carved_fuserework_mode2/inventory.json`
- `type2_helpers/e466ed43319e8f38.fuc5.asm`
