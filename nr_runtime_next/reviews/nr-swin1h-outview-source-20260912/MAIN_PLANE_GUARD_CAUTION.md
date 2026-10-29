# Main receipt and channel-plane/guard distinction

Worker complete, original report retained. Own ABI72/76 output extents is confirmed by source. Its combined address/guard prose must be qualified: it lists third/fourth pairs at y+OH and simultaneously states every store guards 0<=y<OH. Plane-flattened address-y is NOT the logical y tested by the guard.

Actual parsed own source: PC4196 forms logical r23=Y+lane/16;4198/4199 compare r23 against0/OH(r14);4205 conditionally skips the store. Only AFTER that guard, PC4209 forms r3627=r23+r14, and4210 uses it in the physical address;4214 stores rs5,rs6. Thus +OH is channel-plane address offset, not a ghost logical coordinate subject to OH bounds. The same distinction is required for both query halves; second query base remains Y+4.

No69NN prediction or numerical acceptance is supplied by the worker report. Main proceeds with own final-MMA neuron/code/each-store address validation; sizes, row-stride/bijection and first-pair shorthand are not a complete layout proof.
