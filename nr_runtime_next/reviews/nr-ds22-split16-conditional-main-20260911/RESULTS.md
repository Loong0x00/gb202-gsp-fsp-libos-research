# Main DS22 -> conditional split16 FP8 entry composition

`python3 -B bridge.py` passes; writes are local to this Main review. Producer/consumer helpers import in separate child processes to avoid same-name module collisions.

Four freshly executed original bounded DS22 CTAs produce all32768 downstream bytes from the frozen synthetic16x16 source, real block22 weights and explicit CPU numerical policies. Every producer CTA gets independent pooling/projection/layout checks. The exact assembled bytes have SHA256 `808983e0442179682cedd5a1610f94970ffc2f342b19d7f22749cc8c4085e45a` and equal the accepted DS fixture.

Those bytes feed the **complete conditional FP8 split layer0**, without repacking or holes. Both z slices (two separate four-warp CTAs) reach originalret,8192 MMAs and the scalar half activation/layout proofs pass, and all524288 real layer0 weight bytes are used. The modeled original async-copy/wait/mbarrier sequence executes; this is beyond the DS review's static source-address boundary, but not native async validation.

Complete32768-byte conditional layer0 output SHA256: `1382b2fb50200a88ef1d09f5f6a0db2286f3a427d3cf6bc448e99b4a23da0359`.

Negative checks reject one missing input byte and reject the historical non-FP8 spelling. All recorded dependency/deliverable hashes remain unchanged. The two independently extracted next-entry source slices differ by **exactly one final LF**, verified byte-for-byte; no general whitespace normalization or instruction edit was applied.

## Do not overstate this result

- This connects only DS22 and **conditional FP8 layer0**, not all block23 layers or the preceding skipped standardblocks16–21.
- Factory(0) historical spelling selects a conflicting F16 route. Real runtime selection/rewrite/conversion is unresolved in this report; this experiment does not establish what the game runs or an original-model memory bug.
- Source-derived default network gather is conditional on the captured descriptor evidence; no native data readiness, concurrent publication or actual launch metadata was measured.
- Original input bytes remain saved for the separate layer1 residual skip; consuming them as layer0 input is not permission to replace or discard that skip.
- No native numerical parity, fullmodel/history/image or quality acceptance; no GPU/Wine/deployment.

See `PRODUCER.json`, `CONSUMER.json`, `VERIFICATION.json`, `BRIDGE.log`. CPU continuation separately covers route resolution, projections1/3 and attention2.
