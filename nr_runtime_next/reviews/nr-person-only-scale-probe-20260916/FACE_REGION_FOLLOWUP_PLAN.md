# Post-primary face-region follow-up — frozen before region extraction

The registered whole-foreground monotonic prediction failed. Inspection of whole-foreground summaries showed a non-monotonic trough whose person-height location differs between full figures and standalone face icons. This exploratory follow-up tests whether the trough aligns when expressed in apparent face pixels.

The mask is input/source-derived only:

1. crop the original Fluent RGBA to nonzero alpha;
2. define warm surface pixels by `alpha>0.5, R>0.55, G>0.20, B<0.48, R>1.35*B` in source sRGB;
3. connected-component label;
4. among components with centroid in the upper 70% and horizontal centroid within 35% of source center, choose the largest;
5. resize that fixed binary component with the same foreground transform and center placement used by the frozen cases.

No output pixel may influence the mask. Report face-weighted delta-EV versus apparent component-bounding-box height. Exploratory prediction after the whole-person result: maximum darkening clusters near approximately one 64-pixel bottleneck cell rather than increasing monotonically toward the smallest scale.
