# Final neural-stage finding

The independent single-handle Feature18 replay reproduces the live alternating structured mosaic before custom codec decode:

- raw 24 / global 6936: neural clean
- raw 25 / global 6937: neural structured mosaic
- raw 26 / global 6938: neural clean
- raw 27 / global 6939: neural structured mosaic
- raw 28 / global 6940: neural clean

The corresponding signed native-RR inputs are clean in every frame. `native-vs-neural-raw24-28.jpg` is a direct gamma-preview of the RGBA16F Feature18 output array; no custom decode shader, UE post-processing, Present, OBS, or video codec is involved in the right-hand images. The exact bad/clean/bad/clean cadence matches the prior live post-NR evidence (old raw 104/105/106/107).

Therefore the first observed corruption is in the Feature18 neural stage, not the custom codec decoder. The remaining distinction is between model/runtime behavior and the supplied temporal/input contract; this experiment does not by itself identify a defective weight tensor.
