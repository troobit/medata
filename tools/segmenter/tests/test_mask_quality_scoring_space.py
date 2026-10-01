"""Mask metrics are computed in the fixed SCORE_SIZE space, not the model's.

``boundary_f``'s tolerance is in pixels of the scored grid, so a run at input
size 641 scored on a 641 grid is marked against a ruler ~0.8x the physical
length of the 513 one every other run was marked with. Predictions and ground
truth are therefore resampled to SCORE_SIZE before scoring, and a run already at
SCORE_SIZE must come through byte-identical.
"""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mask_quality as mq  # noqa: E402


def test_identity_when_already_at_the_target_shape():
    a = np.arange(6 * 4, dtype="uint8").reshape(6, 4)
    out = mq.resample_nearest(a, 4, 6)
    assert out is a, "a run at SCORE_SIZE must not be touched"


def test_downsamples_label_maps_without_inventing_labels():
    a = np.array([[1, 1, 2, 2],
                  [1, 1, 2, 2],
                  [3, 3, 4, 4],
                  [3, 3, 4, 4]], dtype="uint8")
    out = mq.resample_nearest(a, 2, 2)
    assert out.shape == (2, 2)
    assert set(np.unique(out)) <= {1, 2, 3, 4}
    assert out.tolist() == [[1, 2], [3, 4]]


def test_keeps_leading_axes_so_probability_planes_work():
    p = np.zeros((36, 8, 8), dtype="float32")
    p[7] = 1.0
    out = mq.resample_nearest(p, 4, 4)
    assert out.shape == (36, 4, 4)
    assert np.allclose(out[7], 1.0)


def test_upsampling_is_symmetric_with_no_half_pixel_drift():
    a = np.array([[0, 1]], dtype="uint8")
    out = mq.resample_nearest(a, 4, 1)
    assert out.tolist() == [[0, 0, 1, 1]]


def test_indices_stay_in_bounds_at_awkward_ratios():
    for h, w in ((513, 385), (641, 481), (7, 3)):
        a = np.zeros((h, w), dtype="uint8")
        for th, tw in ((513, 385), (100, 99), (1, 1)):
            assert mq.resample_nearest(a, tw, th).shape == (th, tw)


def test_boundary_f_is_scale_sensitive_which_is_why_this_exists():
    """The premise of the fix: the same mask pair scores differently on grids of
    different size, because the 2 px tolerance is a fraction of the grid."""
    gt = np.zeros((128, 128), dtype=bool)
    gt[32:96, 32:96] = True
    pred = np.zeros((128, 128), dtype=bool)
    pred[35:96, 32:96] = True  # 3 px off on one edge
    coarse_gt = mq.resample_nearest(gt, 64, 64)
    coarse_pred = mq.resample_nearest(pred, 64, 64)
    fine = mq.boundary_f(pred, gt)
    coarse = mq.boundary_f(coarse_pred, coarse_gt)
    assert fine != coarse, "if these matched, the scoring space would not matter"
