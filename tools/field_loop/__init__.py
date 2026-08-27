"""Mac-side field feedback loop (specs/estimation/ml-feedback-loop).

Development tooling only: nothing here runs on the phone, and nothing here is
reachable from the estimation path. Stdlib-only at import time — the heavy
imports (numpy, PIL, torch) are made inside the functions that need them so the
test suite and the pull/ingest path stay runnable on a bare interpreter.
"""
