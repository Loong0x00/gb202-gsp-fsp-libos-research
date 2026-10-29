# Nonlinear adapter v1 frozen-heldout result

Adapter checkpoint `88c57aa7cc1cdf85179dc653d1bae30c03756d4e07a8a981a1d6fb73b0c32018` was frozen before generating four new identities. It passed three of four identities without retraining:

| identity | worst-band improvement | close change | outside RGB MAE | pass |
|---|---:|---:|---:|---|
| fluent-001 | +0.0835 EV | 0.00010 EV | 0.00137 | yes |
| fluent-009 | +0.0199 EV | 0.04053 EV | 0.00198 | no |
| fluent-021 | +0.0961 EV | 0.00096 EV | 0.00121 | yes |
| fluent-026 | +0.1444 EV | 0.00612 EV | 0.00214 | yes |

Background-only RGB MAE was0.000634. The fairy/full-person identity is a real held-out failure: insufficient correction in the danger band and excessive close change. Thresholds were not relaxed and v1 was not promoted.
