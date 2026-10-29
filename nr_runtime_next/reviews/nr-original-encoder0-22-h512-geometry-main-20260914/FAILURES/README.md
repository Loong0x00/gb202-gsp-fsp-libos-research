A failed original-literal witness is preserved as `FIRST_FAILURE_NNN.json`.

`PREEXISTING_TRANSPARENT_B15_EXTENT_FAILURE.log` is an exact preserved copy of
the source H512 chain's earlier transparent ingress failure.  It is context,
not an original-literal failure from this validator.

The runner never deletes an earlier failure or a completed `RESULT.json`.  A
failure receipt records the completed blocks/CTA count, the exception, blocked
scope events, and (when possible) source-integrity state.
