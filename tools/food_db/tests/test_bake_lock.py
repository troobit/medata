"""Palette <-> DB edition bake-lock tests (model-production task 11, Req 8.4).

Baking a food/β_c table must fail when the DB's ``meta.palette_version`` does not
match ``ClassPalette.version`` (the Swift single source of truth — "v0" until
the first main release, pipeline Decision 50).
This guards against shipping a DB edition whose class indexing has drifted from
the segmenter palette. Pure predicate — importing generate.py does not bake.
"""

import pytest

import generate


def test_class_palette_version_reads_v0_from_swift():
    # Read straight from ClassPalette.swift's standard declaration so the lock
    # tracks the Swift source, not a duplicated constant.
    assert generate.class_palette_version() == "v0"


def test_baked_version_matches_class_palette():
    # The version generate.py actually stamps into meta must equal ClassPalette.version.
    assert generate.PALETTE_VERSION == generate.class_palette_version()


def test_lock_passes_when_versions_match():
    generate.verify_palette_lock(generate.class_palette_version())  # must not raise


def test_lock_fails_on_mismatch():
    with pytest.raises(SystemExit):
        generate.verify_palette_lock("v9-does-not-match")


def test_lock_fails_on_superseded_label():
    # Labels from expunged pre-release palette iterations must not bake.
    with pytest.raises(SystemExit):
        generate.verify_palette_lock("v2")
