`verify_original.py` never removes or overwrites a literal comparison failure.

On an exception it writes a new `original-block<N>-failure*.json` with the completed block set and error. Completed `ORIGINAL_*` buffers are likewise retained rather than replaced. No failed full replay was intentionally discarded.
