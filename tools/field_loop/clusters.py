#!/usr/bin/env python3
"""Same-scene attempt clusters (Req 6.1), the loop's unit of repetition.

Repeat groups are STRUCTURAL, not interpreted: attempts chain into one cluster
while consecutive captures are no more than `cluster_max_gap_s` apart. Pure
transitive chaining is not enough — the observed habit is dozens of attempts in
a few minutes, so dish A and dish B captured 90 s apart would merge, and the
false mask inconsistency that produced would feed the Req 6.3 regression flag
and the denylist. The chain therefore SPLITS when the dominant class changes,
or when adjacent attempts' argmax class sets are disjoint.

Cluster sizes are always reported: a consistency figure over two attempts is
not the same claim as one over twenty, and the report must not let them look
alike.
"""

from __future__ import annotations


def _classes(capture) -> set:
    return {c for c in (capture.get("detected_classes") or "").split(",") if c}


def _dominant(capture):
    """The largest food class, when the capture recorded one.

    `dominant_class` is the replay's answer where a replay happened; the
    fallback is the alphabetically-first detected class, which is stable but
    says nothing — so a capture with no replay never SPLITS a chain on
    dominance alone, it only fails to hold one together.
    """
    return capture.get("dominant_class")


def cluster(captures, max_gap_s: int) -> list:
    """Chronological captures -> list of clusters, each a list of captures."""
    ordered = sorted(captures, key=lambda c: (c["timestamp_ms"] or 0, c["stem"]))
    if not ordered:
        return []
    gap_ms = max_gap_s * 1000
    groups = [[ordered[0]]]
    for capture in ordered[1:]:
        previous = groups[-1][-1]
        gap = (capture["timestamp_ms"] or 0) - (previous["timestamp_ms"] or 0)
        if gap > gap_ms or _splits(previous, capture):
            groups.append([capture])
        else:
            groups[-1].append(capture)
    return groups


def _splits(previous, current) -> bool:
    before, after = _dominant(previous), _dominant(current)
    if before and after and before != after:
        return True
    left, right = _classes(previous), _classes(current)
    if left and right and not (left & right):
        return True
    return False


def cluster_id(group) -> str:
    """Stable across runs: the first stem in the group names it."""
    return group[0]["stem"]


def assign(captures, max_gap_s: int) -> dict:
    """stem -> cluster id, plus the size of each cluster."""
    out = {}
    for group in cluster(captures, max_gap_s):
        name = cluster_id(group)
        for capture in group:
            out[capture["stem"]] = name
    return out
