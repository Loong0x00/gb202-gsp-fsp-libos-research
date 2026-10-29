# Main review of source-only worker report

Worker obeyed the bounded read/write-only job and produced source evidence, not execution/tests. Preserve REPORT.md unchanged. Accepted: exact cc_cb_clear stores32-bit -1; +230 handle/+270 context/+228 base/+208 extent dataflow; nonempty begin0 conditionally submits clear, nonzero begin bypasses it; no native happens-before promotion.

Two corrections are required before using the report as a contract:

1. PTX reads a b32 count but compares with `setp.ge.s32` and computes signed index/address operations. Calling N simply u32 and describing `[B,B+4*floor(E/4))` without bounds ignores `low32(E>>2)`, grid-add wrap and signed admission. For the ordinary positive word-aligned bounded domain the simple range is correct; arbitrary E is NOT admitted. A sub-four-byte nonzero E produces a zero-grid submission attempt in the shown setup, not a proven successful no-op.
2. The report's auxiliary-address discussion mixes tables. Activation/primary slot binding uses P=A+E, but the exact LAST-layer auxiliary binding at0x18003f144 loads saved original A from `[rsp+0x78]`, and0x18003f149 adds the selected offset from this+210. Thus those selected aux pointers use A+offset, NOT automatically A+E+offset. The main outer-graph review already distinguishes these tables. It is not yet proved whether every such offset lies within the cleared E prefix; inspect its size/offset generator before promoting fresh-counter coverage.

No claim that every live FFN/QKV/decoder counter is reset, nor that GPU submission order alone provides visibility/epoch correctness. Existing conditional caller prerequisites stay in force. This Main correction is static source review only; no GPU/PE/Wine execution.
