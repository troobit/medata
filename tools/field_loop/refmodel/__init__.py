#!/usr/bin/env python3
"""A second opinion on every annotated capture, from a model that is not ours.

Req 4.6 wants the pipeline's reading of an image recorded beside a reference
model's. Decision 16 (amended) settles what "reference model" means here: one
adapter is ACTIVE at a time, but all four — `anthropic`, `openai`, `google`,
`local_torch` — are maintained at verified working parity, so when the active
one stops (a pricing change, an outage, a key expiring) another takes over as
a config edit rather than as a porting exercise. Parity is measured, not
assumed: the test suite runs the same assertions over every adapter, and
`health_probe` reads one image through every ENABLED adapter each cycle so a
broken standby is found before it is needed.

Three properties everything below is arranged around:

* **The cache key is (image sha256, ident), never the path.** A reading is
  expensive and permanent; re-reading the same bytes under the same pinned
  model must cost nothing, and a file moved inside the corpus must not look
  like new evidence.
* **Each ident is its own comparison series.** `pool` REFUSES a set of
  readings spanning idents. A handover starts a new series; silently averaging
  Claude's readings with Gemini's would make a Req 6.2 trend a fiction.
* **Everything a model says about an image is data.** Names, raw responses and
  any text recovered from packaging enter committed artifacts only through
  `as_evidence`, JSON-escaped onto one line (Req 4.7, Decision 19).
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Protocol

if __package__ in (None, ""):  # pragma: no cover - direct-script fallback
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    __package__ = "field_loop.refmodel"

from .. import corpus  # noqa: E402

CONFIG_NAME = "refmodel.json"
# The real configuration names base URLs, local checkpoints and key
# environment variables — facts about one machine, so it lives at the corpus
# root and only this template is committed.
EXAMPLE_CONFIG = Path(__file__).resolve().parent / "refmodel.example.json"

# Region kinds a reading may carry. The adapter's own contract is one of
# MASK (it produces real per-pixel masks) or REGION_HINT (a VLM: a polygon, a
# box, or nothing at all), and the mask axis of the comparison only admits the
# first — a box drawn around a plate is not a segmentation and must never be
# scored as one.
MASK = "mask"
POLYGON = "polygon"
BOX = "box"
NONE = "none"
REGION_HINT = "region_hint"

ADAPTERS = ("anthropic", "openai", "google", "local_torch")


@dataclass(frozen=True)
class RefFood:
    """One food a reference model claims to see."""

    name: str
    confidence: float
    region_kind: str = NONE
    region: dict | None = None


@dataclass(frozen=True)
class RefReading:
    """One model's reading of one image, and what it is allowed to be used for."""

    ident: str
    foods: tuple
    raw: str
    read_at: str
    region_contract: str
    recovered_text: str = ""

    @property
    def mask_capable(self) -> bool:
        return self.region_contract == MASK


class RefModel(Protocol):
    """The whole adapter interface: an identity, and a read."""

    ident: str

    def read(self, image_path: Path) -> RefReading: ...


# ------------------------------------------------------------------- config
# `refmodel.json` lives at the corpus root, not in the repo: it names models,
# base URLs and local checkpoints — deployment facts about this machine, not
# facts about the product.

def load_config(root=None, config=None) -> dict:
    """Read and validate the adapter set, or validate one passed in.

    Fail-closed like every other loop input: an enabled adapter that does not
    pin a model AND a version cannot form an ident, and a reading without a
    stable ident cannot belong to a comparison series (Req 4.6).
    """
    if config is None:
        path = Path(root or corpus.corpus_root()) / CONFIG_NAME
        if not path.exists():
            raise SystemExit(
                "%s is absent — the loop reads its reference-model set from the "
                "corpus root, naming the enabled adapters and the single active "
                "one (Decision 16). Start from %s" % (path, EXAMPLE_CONFIG))
        config = json.loads(path.read_text())

    entries = config.get("adapters")
    if not isinstance(entries, dict) or not entries:
        raise SystemExit("%s has no 'adapters' block" % CONFIG_NAME)

    for name, entry in sorted(entries.items()):
        if name not in ADAPTERS:
            raise SystemExit(
                "%s configures unknown adapter '%s' — the adapter set is "
                "%s" % (CONFIG_NAME, name, ", ".join(ADAPTERS)))
        if not entry.get("enabled"):
            continue
        for key in ("model", "version"):
            if not entry.get(key):
                raise SystemExit(
                    "%s adapter '%s' is enabled without a pinned '%s'; every "
                    "enabled adapter pins its model and version so its readings "
                    "carry a stable ident" % (CONFIG_NAME, name, key))

    active = config.get("active")
    if active not in entries or not entries[active].get("enabled"):
        raise SystemExit(
            "%s names active adapter '%s', which is not an enabled adapter"
            % (CONFIG_NAME, active))
    return config


def enabled_names(config: dict) -> list:
    return sorted(n for n, e in config["adapters"].items() if e.get("enabled"))


def build(name: str, entry: dict, transport=None, clock=None) -> RefModel:
    """One adapter instance. `transport` is the seam the stub suite uses."""
    from . import adapters

    factory = adapters.REGISTRY.get(name)
    if factory is None:
        raise SystemExit("no adapter named '%s'" % name)
    return factory(entry, transport=transport, clock=clock)


def active_adapter(config: dict, transport=None, clock=None) -> RefModel:
    return build(config["active"], config["adapters"][config["active"]],
                 transport=transport, clock=clock)


def enabled_adapters(config: dict, transports=None, clock=None) -> list:
    transports = transports or {}
    return [build(name, config["adapters"][name],
                  transport=transports.get(name), clock=clock)
            for name in enabled_names(config)]


# -------------------------------------------------------------------- cache

def read_cached(conn, adapter, image_path) -> RefReading:
    """The reading for (this image's bytes, this ident), reading only if new.

    Permanent by design: a pinned model asked the same question about the same
    bytes gives the same answer, and the corpus keeps the answer so a later
    cycle — or a later adapter handover — never pays for it twice.
    """
    image_sha = corpus.sha256_file(Path(image_path))
    row = conn.execute(
        "SELECT reading_json FROM ref_readings WHERE image_sha256 = ? AND ident = ?",
        (image_sha, adapter.ident)).fetchone()
    if row is not None:
        return _decode(row["reading_json"], adapter.ident)

    reading = adapter.read(Path(image_path))
    corpus.upsert_ref_reading(conn, {
        "image_sha256": image_sha,
        "ident": reading.ident,
        "series": series_of(reading),
        "reading_json": json.dumps(_encode(reading), sort_keys=True),
    })
    conn.commit()
    return reading


def series_readings(conn, ident: str) -> list:
    """Every cached reading in one ident's series, oldest image first."""
    rows = conn.execute(
        "SELECT reading_json FROM ref_readings WHERE series = ? "
        "ORDER BY image_sha256", (ident,)).fetchall()
    return [_decode(r["reading_json"], ident) for r in rows]


def _encode(reading: RefReading) -> dict:
    return {
        "ident": reading.ident,
        "read_at": reading.read_at,
        "region_contract": reading.region_contract,
        "raw": reading.raw,
        "recovered_text": reading.recovered_text,
        "foods": [{"name": f.name, "confidence": f.confidence,
                   "region_kind": f.region_kind, "region": f.region}
                  for f in reading.foods],
    }


def _decode(payload: str, ident: str) -> RefReading:
    try:
        stored = json.loads(payload)
    except ValueError as error:
        # Not "no reading yet": treating a corrupt row as absent would restart
        # a comparison series that in fact has history, and the restart would
        # look like a clean handover in the report.
        raise ValueError(
            "cached reading for ident %s is not readable JSON (%s) — the row "
            "is corrupt, which is not the same as having no reading"
            % (ident, error)) from error
    return RefReading(
        ident=stored["ident"], read_at=stored["read_at"],
        region_contract=stored["region_contract"], raw=stored.get("raw", ""),
        recovered_text=stored.get("recovered_text", ""),
        foods=tuple(RefFood(name=f["name"], confidence=f["confidence"],
                            region_kind=f.get("region_kind", NONE),
                            region=f.get("region"))
                    for f in stored.get("foods", [])))


# ------------------------------------------------------------------- series

def series_of(reading: RefReading) -> str:
    """A reading's comparison series IS its ident. Nothing pools across them."""
    return reading.ident


def pool(readings) -> str:
    """The one ident a set of readings may be compared within.

    Raises rather than picking one: a trend computed across two models is not
    a trend, and the failure has to be loud where it happens.
    """
    idents = {series_of(r) for r in readings}
    if len(idents) > 1:
        raise ValueError(
            "refusing to pool readings across %d idents in one series (%s) — "
            "each ident forms its own comparison series (Req 4.6)"
            % (len(idents), ", ".join(sorted(idents))))
    return idents.pop() if idents else ""


def mask_axis_readings(readings) -> list:
    """Only mask-capable readings may serve the mask axis of the comparison."""
    return [r for r in readings if r.mask_capable]


# ------------------------------------------------------------- health probe

def health_probe(adapters_, image_path) -> list:
    """One image through every adapter handed in; never raises.

    Decision 16's measurement: the cycle verdict records this, so a standby
    that stopped working is discovered on a cycle where nothing depended on
    it rather than on the day the active adapter goes down.
    """
    results = []
    for adapter in adapters_:
        try:
            reading = adapter.read(Path(image_path))
        except Exception as error:  # noqa: BLE001 - the probe reports, never fails
            results.append({"ident": adapter.ident, "ok": False,
                            "detail": "%s: %s" % (type(error).__name__, error),
                            "foods": 0, "region_contract": adapter.region_contract})
            continue
        results.append({"ident": adapter.ident, "ok": True, "detail": "",
                        "foods": len(reading.foods),
                        "region_contract": reading.region_contract})
    return results


# --------------------------------------------------------------- quarantine

def quarantine(text: str) -> str:
    """Model output as a JSON string literal on one line (Req 4.7).

    Same containment as `cycle_file.quarantine`, applied at the other end of
    the pipe: what a model read off a packet of cereal is data under analysis,
    and an instruction it recovered there survives as a quoted literal.
    """
    return json.dumps(text or "", ensure_ascii=False)


def as_evidence(reading: RefReading) -> dict:
    """The reading, shaped for a cycle file, a verdict, or a triage item."""
    return {
        "ident": reading.ident,
        "read_at": reading.read_at,
        "region_contract": reading.region_contract,
        "raw": quarantine(reading.raw),
        "recovered_text": quarantine(reading.recovered_text),
        "foods": [{"name": quarantine(f.name), "confidence": f.confidence,
                   "region_kind": f.region_kind} for f in reading.foods],
    }


# ---------------------------------------------------------- palette mapping

def map_to_palette(reading: RefReading) -> dict:
    """`{ident, classes, unmapped}` — what `causes.classify` consumes.

    A name the palette does not carry is the Req 4.4 `food_absent_from_palette`
    signal, so it is reported as unmapped rather than dropped: the loop's most
    useful finding may be that the class set is missing a food entirely.
    """
    from .. import bundle  # lazy: pulls candidate_probe's palette in

    known = {name: name for name in bundle.CLASS_NAMES}
    classes, unmapped = [], []
    for food in reading.foods:
        key = _normalise(food.name)
        if key in known:
            classes.append(known[key])
        else:
            unmapped.append(food.name)
    return {"ident": reading.ident, "classes": sorted(set(classes)),
            "unmapped": sorted(set(unmapped))}


def _normalise(name: str) -> str:
    return "_".join(str(name).strip().lower().replace("-", " ").split())


def with_ident(reading: RefReading, ident: str) -> RefReading:
    """A reading re-stamped — used only when re-pinning a cached read's model."""
    return replace(reading, ident=ident)
