#!/usr/bin/env python3
"""Read `loop_config.json`. Nothing here carries a default of its own.

Every floor, ceiling, budget and cap the loop enforces lives in the JSON beside
this file, so a verdict saying "guard 3 fired at 0.15" names a number a reader
can go and find. A code-side fallback default would let the two drift, and the
one that fired would be the invisible one.
"""

from __future__ import annotations

import json
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parent / "loop_config.json"


def load(path=None) -> dict:
    config = json.loads(Path(path or CONFIG_PATH).read_text())
    # `_`-prefixed keys are the prose explaining the number above them; they are
    # part of the file's job and not part of its data.
    return {k: v for k, v in config.items() if not k.startswith("_")}


def get(config: dict, key: str):
    if key not in config:
        raise KeyError(
            "%s has no key %r — the loop reads every threshold from that file "
            "and carries no fallback" % (CONFIG_PATH, key))
    return config[key]
