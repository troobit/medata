"""Leak audit for the enlarged held-out anchor (build_anchor.py, backlog 35).

Torch-free: the perceptual hash, the correlation judge and the admit/drop rule
are pure numpy.
"""

from __future__ import annotations

import build_anchor as ba
import numpy as np


def _scene(seed: int, size: int = 32) -> np.ndarray:
    """A smooth random greyscale 'photo' (low-frequency content, like a
    downscaled plate)."""
    coarse = np.random.default_rng(seed).uniform(0, 255, (4, 4))
    return np.kron(coarse, np.ones((size // 4, size // 4)))


def _fp(stem, img, sha):
    return ba.Fingerprint(stem, sha, ba.dihedral_hashes(img))


def test_rotated_and_mirrored_copies_hash_to_the_same_photo():
    img = _scene(1)
    reference = np.array([ba.dihedral_hashes(img)[0]], dtype=np.uint64)
    for copy in (np.rot90(img), img[:, ::-1], np.rot90(img[::-1], 3)):
        assert ba.hamming_to(reference, ba.dihedral_hashes(copy))[0] == 0
        assert ba.aligned_correlation(copy, img) > 0.999


def test_unrelated_photos_are_far_apart():
    a, b = _scene(1), _scene(2)
    assert ba.hamming_to(np.array([ba.dihedral_hashes(b)[0]], dtype=np.uint64),
                         ba.dihedral_hashes(a))[0] > 4
    assert ba.aligned_correlation(a, b) < 0.85


def test_audit_drops_train_matches_and_pool_duplicates():
    images = {"t0": _scene(10), "t1": _scene(11), "exact": _scene(10),
              "rotated": np.rot90(_scene(11)), "fresh": _scene(20),
              "fresh_again": _scene(20)[:, ::-1], "other": _scene(21)}
    train = [_fp("t0", images["t0"], "sha-t0"), _fp("t1", images["t1"], "sha-t1")]
    cands = [_fp("exact", images["exact"], "sha-t0"),
             _fp("rotated", images["rotated"], "sha-r"),
             _fp("fresh", images["fresh"], "sha-f"),
             _fp("fresh_again", images["fresh_again"], "sha-f2"),
             _fp("other", images["other"], "sha-o")]

    def correlate(a, b):
        return ba.aligned_correlation(images[a], images[b])

    kept, dropped, hist = ba.audit(cands, train, correlate)
    assert kept == ["fresh", "other"]
    assert {d["stem"]: (d["reason"], d["match"]) for d in dropped} == {
        "exact": ("exact_train", "t0"),
        "rotated": ("near_duplicate_train", "t1"),
        "fresh_again": ("near_duplicate_pool", "fresh"),
    }
    assert sum(hist.values()) == len(cands)


def test_a_close_hash_alone_is_not_a_match_when_the_pictures_differ():
    """Among 45k food photos a 6-8 bit hash distance is routinely an unrelated
    plate; inside the screen, only the correlation judge may drop it."""
    train = [_fp("t0", _scene(30), "sha-t0")]
    cand = [_fp("c0", _scene(31), "sha-c0")]
    kept, dropped, _ = ba.audit(cand, train, lambda a, b: 0.3,
                                max_distance=-1, screen_distance=64)
    assert kept == ["c0"] and not dropped
    kept, dropped, _ = ba.audit(cand, train, lambda a, b: 0.9,
                                max_distance=-1, screen_distance=64)
    assert kept == [] and dropped[0]["reason"] == "near_duplicate_train"
