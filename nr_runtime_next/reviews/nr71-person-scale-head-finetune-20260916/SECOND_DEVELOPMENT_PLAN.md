# Second-stage development plan — frozen before sweep

The first leave-one-identity-out pilot proved that 96 RGB-head weights can reduce the held-out trough by 0.09–0.18 EV, but failed preservation gates because the close-teacher target was applied at every smaller scale and background weight was too weak.

This development stage uses the four original identities only for recipe selection; none may be used as final confirmation.

- Apply the close-teacher correction target only when the input-derived apparent face component is in the already-established 40–90 px danger band.
- At all other scales, target zero head change (original model distillation).
- Region-normalized weights: person1, face8, with background candidate weights `[4,16,64,256]`.
- Ridge lambdas remain `[1e-6,1e-5,1e-4,1e-3,1e-2,1e-1,1,10]`.
- Select among candidates meeting all original preservation gates on the development identities; maximize minimum danger-band improvement, then minimize background drift and weight norm.
- If a recipe is found, freeze it before generating/capturing four new held-out identities (`fluent-001`, `fluent-009`, `fluent-021`, `fluent-026`).
- The final held-out identities receive no optimizer or threshold feedback.
