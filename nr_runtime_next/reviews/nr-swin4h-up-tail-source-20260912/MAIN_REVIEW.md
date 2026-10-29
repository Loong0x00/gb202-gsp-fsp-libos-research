# Main tail review

Accepted with numerical/provenance evidence for zero-origin CTA(0,0), not solely report text. ../nr-swin4h-up-main-20260912/check_normalized.py follows raw source-neuron tags through every normalization, delayed rs505..rs520 packing and both actual QK/PV uses. check_attention.py verifies both query halves, all128QK+128PV+256finalMMA, packed/reduction/RCP/probability values, epoch6/8 residual byte origins and epoch7/9 PV scratch reads. Unrolled final carries include explicit precedingK32 producer-step tags.

K/V register banks in the report are shorthand ranges with interleaved unrelated registers; observer roles come from actual MMA operand lists, not every register in a numeric range. All40 shared snapshots across4zero-origin CTAs match mixed epoch expectations, including persistent FFN bottom half. First NN attention code unchanged. Actual host block56 is shifted(-4,0), whose boundary/grid is not yet accepted here; native/full-model scope unchanged.
