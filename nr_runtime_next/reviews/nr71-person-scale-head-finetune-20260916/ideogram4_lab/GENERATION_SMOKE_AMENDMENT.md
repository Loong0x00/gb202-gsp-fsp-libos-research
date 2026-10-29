# Generation geometry amendment after smoke, before training generation

The excluded smoke image proved the local NF4 path but placed hair at y=0 despite “entire body uncropped.” No frozen training or reserved identity had yet been generated. To prevent unusable cropped silhouettes, tighten the structured object bbox from `[25,180,975,820]` to `[60,220,940,780]` and explicitly request ample empty checkerboard margin around the complete silhouette.

This is a source-data quality amendment based only on the excluded smoke image. The original pre-smoke manifest/freezer is retained as `GENERATION_*_PRE_SMOKE.json`. Seeds, identity descriptions, split assignment, 768×1024 size, sampler and model revision remain unchanged. The six reserved-final images remain ungenerated.
