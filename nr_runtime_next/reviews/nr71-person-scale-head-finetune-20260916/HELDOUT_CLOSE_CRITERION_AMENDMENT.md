# Held-out close-anchor criterion amendment — frozen before output scoring

Input-derived mask audit shows `fluent-009` reaches only ~151 px apparent face height at the fixed maximum foreground height320, so the preregistered `>=160 px` set would be empty. For any held-out identity with no case >=160 px, use its h320 case as the close-anchor preservation measurement. This amendment depends only on frozen source geometry/masks and was written before adapter outputs were evaluated.

The first warm-component mask attempt for two full-person sources incorrectly included connected warm clothing; it is retained as `HELDOUT_MASK_*_FIRST_WARM_COMPONENT_FAILURE.json`. The corrected input-only rule clips full-person candidates to the upper central source region before connected-component selection. No model output was inspected for either correction.
