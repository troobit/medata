"""Class-agnostic mask-quality metrics (MD-29, segmenter-foundation Decision 37).

Synthetic label maps with hand-computable answers; pure numpy, no torch. The
metrics are the ones the EdgeTAM spike introduced and every validation run now
records under lineage ``metrics.mask_quality``.
"""

import json

import numpy as np
import pytest

import mask_quality as mq
import validation

BG, UNKNOWN, LIQUID = 33, 34, 35
NON_FOOD = (BG, UNKNOWN, LIQUID)


def _canvas(h=40, w=40, fill=BG):
    return np.full((h, w), fill, dtype=np.uint8)


# ── content shape ───────────────────────────────────────────────────────────────

def test_content_shape_matches_the_letterbox_rounding():
    assert mq.content_shape(1000, 500) == (513, 256)   # 256.5 rounds to even, as train.py does
    assert mq.content_shape(500, 1000) == (256, 513)
    assert mq.content_shape(513, 513) == (513, 513)
    assert mq.content_shape(100, 1, target=10) == (10, 1)


# ── morphology ──────────────────────────────────────────────────────────────────

def test_erode_strips_one_pixel_and_the_image_edge():
    mask = np.zeros((7, 7), dtype=bool)
    mask[1:6, 1:6] = True
    eroded = mq.erode(mask)
    expected = np.zeros((7, 7), dtype=bool)
    expected[2:5, 2:5] = True
    assert np.array_equal(eroded, expected)
    # A mask touching the edge erodes there too (scipy border_value=0).
    edge = np.zeros((5, 5), dtype=bool)
    edge[0:3, 0:3] = True
    assert mq.erode(edge).sum() == 1 and mq.erode(edge)[1, 1]


def test_dilate_grows_one_ring_per_iteration():
    mask = np.zeros((9, 9), dtype=bool)
    mask[4, 4] = True
    assert mq.dilate(mask, 1).sum() == 9
    assert mq.dilate(mask, 2).sum() == 25
    assert mq.dilate(mask, 0).sum() == 1


def test_boundary_is_the_outer_ring():
    mask = np.zeros((8, 8), dtype=bool)
    mask[2:6, 2:6] = True     # 4x4 block: 16 px, 4 interior
    assert mq.boundary(mask).sum() == 12


# ── connected components ────────────────────────────────────────────────────────

def test_label_components_is_eight_connected_and_raster_ordered():
    mask = np.zeros((6, 6), dtype=bool)
    mask[0, 0] = True
    mask[1, 1] = True          # diagonal neighbour → same component
    mask[4, 4] = True          # far away → second component
    mask[2, 5] = True          # isolated → third, but first in raster order after (1,1)
    lab, n = mq.label_components(mask)
    assert n == 3
    assert lab[0, 0] == lab[1, 1] == 1
    assert lab[2, 5] == 2
    assert lab[4, 4] == 3
    assert lab[mask].min() == 1 and (lab[~mask] == 0).all()


def test_label_components_empty_and_full():
    empty = np.zeros((5, 5), dtype=bool)
    lab, n = mq.label_components(empty)
    assert n == 0 and lab.sum() == 0
    full = np.ones((5, 5), dtype=bool)
    lab, n = mq.label_components(full)
    assert n == 1 and (lab == 1).all()


def test_label_components_spiral_needs_many_hooking_rounds():
    # A long snake: one component whose union-find takes several rounds.
    mask = np.zeros((20, 20), dtype=bool)
    for r in range(0, 20, 2):
        mask[r, :] = True
        mask[r + 1, 19 if (r // 2) % 2 == 0 else 0] = True
    lab, n = mq.label_components(mask)
    assert n == 1


def test_label_components_agrees_with_scipy_on_random_masks():
    ndimage = pytest.importorskip("scipy.ndimage")
    rng = np.random.default_rng(7)
    for _ in range(5):
        mask = rng.random((60, 80)) > 0.55
        ours, n = mq.label_components(mask)
        theirs, m = ndimage.label(mask, structure=np.ones((3, 3), dtype=bool))
        assert n == m
        assert np.array_equal(ours, theirs)


def test_components_filters_by_min_px():
    mask = np.zeros((10, 10), dtype=bool)
    mask[0:3, 0:3] = True      # 9 px
    mask[7, 7] = True          # 1 px
    assert len(mq.components(mask)) == 2
    assert len(mq.components(mask, min_px=2)) == 1


# ── GT regions ──────────────────────────────────────────────────────────────────

def test_region_labels_split_touching_classes_and_drop_small_and_non_food():
    labels = _canvas()
    labels[5:15, 5:15] = 1     # 100 px food class 1
    labels[5:15, 15:25] = 2    # touching, class 2 → separate region
    labels[30:33, 30:33] = 1   # 9 px < 64 → dropped
    labels[20:30, 5:15] = UNKNOWN  # sentinel → not a region
    region, classes = mq.region_labels(labels, NON_FOOD)
    assert classes.tolist() == [1, 2]
    assert (region == 1).sum() == 100 and (region == 2).sum() == 100
    assert region[31, 31] == 0 and region[25, 10] == 0
    # The spike's list form is the same data.
    regions = mq.gt_regions(labels, NON_FOOD)
    assert [c for c, _ in regions] == [1, 2]
    assert regions[0][1].sum() == 100


def test_region_labels_min_px_zero_keeps_every_component():
    labels = _canvas()
    labels[0, 0] = 3
    region, classes = mq.region_labels(labels, NON_FOOD, min_px=0)
    assert classes.tolist() == [3] and region[0, 0] == 1


# ── IoU / boundary F ────────────────────────────────────────────────────────────

def test_iou_known_values():
    a = np.zeros((4, 4), dtype=bool)
    b = np.zeros((4, 4), dtype=bool)
    a[0:2, :] = True           # 8 px
    b[1:3, :] = True           # 8 px, 4 overlap → 4 / 12
    assert mq.iou(a, b) == pytest.approx(1 / 3)
    assert mq.iou(a, a) == 1.0
    assert mq.iou(a, np.zeros_like(a)) == 0.0
    assert mq.iou(np.zeros_like(a), np.zeros_like(a)) == 1.0


def test_boundary_f_tolerance():
    gt = np.zeros((30, 30), dtype=bool)
    gt[5:20, 5:20] = True
    assert mq.boundary_f(gt, gt) == 1.0
    shifted_1 = np.roll(gt, 1, axis=1)
    assert mq.boundary_f(shifted_1, gt) == 1.0          # inside the 2 px tolerance
    shifted_4 = np.roll(gt, 4, axis=1)
    f4 = mq.boundary_f(shifted_4, gt)
    assert 0.0 < f4 < 1.0                                # two edges out of tolerance
    assert mq.boundary_f(shifted_4, gt, tol=4) == 1.0
    assert mq.boundary_f(np.zeros_like(gt), gt) == 0.0
    assert mq.boundary_f(np.zeros_like(gt), np.zeros_like(gt)) == 1.0


def test_boundary_f_agrees_with_scipy_reference():
    ndimage = pytest.importorskip("scipy.ndimage")
    eight = np.ones((3, 3), dtype=bool)

    def reference(pred, gt, tol=2):
        pb = pred & ~ndimage.binary_erosion(pred, structure=eight, border_value=0)
        gb = gt & ~ndimage.binary_erosion(gt, structure=eight, border_value=0)
        gd = ndimage.binary_dilation(gb, structure=eight, iterations=tol)
        pd = ndimage.binary_dilation(pb, structure=eight, iterations=tol)
        precision = (pb & gd).sum() / pb.sum()
        recall = (gb & pd).sum() / gb.sum()
        return 2 * precision * recall / (precision + recall)

    rng = np.random.default_rng(3)
    for _ in range(4):
        gt = ndimage.binary_dilation(rng.random((50, 70)) > 0.97, iterations=4)
        pred = ndimage.binary_dilation(rng.random((50, 70)) > 0.97, iterations=4)
        assert mq.boundary_f(pred, gt) == pytest.approx(reference(pred, gt))


# ── region matching ─────────────────────────────────────────────────────────────

def test_matched_region_ious_picks_the_largest_intersection():
    region = np.zeros((20, 20), dtype=np.int32)
    region[0:10, 0:10] = 1                 # 100 px
    pred = np.zeros((20, 20), dtype=np.int32)
    pred[0:10, 0:5] = 1                    # covers half: inter 50, union 100 → 0.5
    pred[0:2, 5:10] = 2                    # a sliver: inter 10 → not chosen
    assert mq.matched_region_ious(region, pred).tolist() == [0.5]
    # No overlap at all → 0; no predicted components → all 0; no regions → empty.
    far = np.zeros_like(pred)
    far[15:20, 15:20] = 1
    assert mq.matched_region_ious(region, far).tolist() == [0.0]
    assert mq.matched_region_ious(region, np.zeros_like(pred)).tolist() == [0.0]
    assert mq.matched_region_ious(np.zeros_like(region), pred).size == 0


def test_region_ious_list_form_matches_union_and_class_aware_components():
    labels = _canvas()
    labels[0:10, 0:10] = 1
    labels[0:10, 10:20] = 2                # touching → one union component
    regions = mq.gt_regions(labels, NON_FOOD)
    union_pred = labels != BG
    # Union mask: one 200 px component against each 100 px region → 0.5 each.
    assert mq.region_ious(union_pred, regions) == [0.5, 0.5]
    # Class-aware components: exact match → 1.0 each.
    comps = [labels == 1, labels == 2]
    assert mq.region_ious(None, regions, comps) == [1.0, 1.0]
    assert mq.region_ious(union_pred, []) == []


# ── shortlist ───────────────────────────────────────────────────────────────────

def _probs_with_ranking(region, ranking, channels=36):
    """[C, H, W] probs where inside region 1 the classes rank as ``ranking``."""
    probs = np.zeros((channels, *region.shape), dtype=np.float32)
    for rank, cls in enumerate(ranking):
        probs[cls][region == 1] = 0.5 / (rank + 1)
    return probs


def test_shortlist_hits_top3_over_food_classes_only():
    region = np.zeros((10, 10), dtype=np.int32)
    region[2:8, 2:8] = 1
    classes = np.array([7])
    # Background and unknown_food outrank everything, then 1, 2, 7: with the
    # sentinels ignored the true class is third → hit.
    probs = _probs_with_ranking(region, [BG, UNKNOWN, 1, 2, 7, 3])
    assert mq.shortlist_hits(probs, region, classes, NON_FOOD).tolist() == [True]
    # Fourth among food classes → miss.
    probs = _probs_with_ranking(region, [1, 2, 3, 7])
    assert mq.shortlist_hits(probs, region, classes, NON_FOOD).tolist() == [False]
    # The spike's regime (background only excluded) counts unknown_food as a slot.
    probs = _probs_with_ranking(region, [BG, UNKNOWN, 1, 2, 7])
    assert mq.shortlist_hits(probs, region, classes, (BG,)).tolist() == [False]
    assert mq.shortlist_hits(probs, region, np.zeros(0, dtype=int), NON_FOOD).size == 0


def test_shortlist_pools_the_mean_over_the_region_not_the_argmax_vote():
    region = np.zeros((10, 10), dtype=np.int32)
    region[0:10, 0:10] = 1
    probs = np.zeros((36, 10, 10), dtype=np.float32)
    probs[5] = 0.4                       # steady second everywhere
    probs[9, :, 0:9] = 0.45              # wins 90 % of the pixels...
    probs[9, :, 9] = 0.0
    probs[2, :, 9] = 0.9                 # ...one column carries class 2 high
    probs[4] = 0.1
    # Means: 9 → 0.405, 5 → 0.4, 2 → 0.09, 4 → 0.1 → top-3 is {9, 5, 4}.
    assert mq.shortlist_hits(probs, region, np.array([4]), NON_FOOD).tolist() == [True]
    assert mq.shortlist_hits(probs, region, np.array([2]), NON_FOOD).tolist() == [False]


# ── score_image / summarise ─────────────────────────────────────────────────────

def test_score_image_end_to_end_with_known_answers():
    gt = _canvas(60, 60)
    gt[10:30, 10:30] = 1                 # 400 px
    gt[40:50, 40:50] = LIQUID            # sentinel: not food, not a region
    pred = _canvas(60, 60)
    pred[10:30, 10:20] = 1               # left half of the region, class 1
    pred[10:30, 20:30] = 2               # right half labelled 2 → two components
    pred[40:50, 40:50] = UNKNOWN         # sentinel prediction is not food either
    probs = np.zeros((36, 60, 60), dtype=np.float32)
    probs[2] = 0.6
    probs[1] = 0.3
    probs[BG] = 0.1
    out = mq.score_image(gt, pred, probs, NON_FOOD)
    assert out["food_iou"] == 1.0                     # sentinels excluded on both sides
    assert out["boundary_f"] == 1.0
    assert out["region_ious"] == [0.5]                # best class-aware component covers half
    assert out["shortlist_hits"] == [True]            # class 1 ranks second
    assert "shortlist_hits" not in mq.score_image(gt, pred, non_food=NON_FOOD)


def test_summarise_means_over_images_and_regions():
    per_image = [
        {"food_iou": 0.8, "boundary_f": 0.4, "region_ious": [1.0, 0.0], "shortlist_hits": [True, False]},
        {"food_iou": 0.6, "boundary_f": 0.6, "region_ious": [0.5], "shortlist_hits": [True]},
    ]
    s = mq.summarise(per_image)
    assert s == {
        "food_iou": pytest.approx(0.7), "region_iou": pytest.approx(0.5),
        "boundary_f2": pytest.approx(0.5), "shortlist_top3_hit": pytest.approx(2 / 3),
        "n_images": 2, "n_regions": 3,
    }
    empty = mq.summarise([])
    assert empty["food_iou"] is None and empty["n_images"] == 0 and empty["n_regions"] == 0
    block = mq.lineage_block(per_image)
    assert block["scored_at"].endswith("+00:00")
    assert set(block) == {"food_iou", "region_iou", "boundary_f2", "shortlist_top3_hit",
                          "n_images", "n_regions", "scored_at"}


# ── lineage recording ───────────────────────────────────────────────────────────

def test_update_lineage_mask_quality_leaves_class_metrics_alone(tmp_path):
    path = tmp_path / "lineage.json"
    before = {"model_version": "abc", "metrics": {
        "mean_iou": 0.42, "per_class_iou": {"pasta": 0.6}, "carb_priority_iou": {"pasta": 0.6},
    }}
    path.write_text(json.dumps(before))
    block = {"food_iou": 0.88, "region_iou": 0.49, "boundary_f2": 0.46,
             "shortlist_top3_hit": 0.82, "n_images": 182, "n_regions": 900,
             "scored_at": "2026-09-27T00:00:00+00:00"}
    validation.update_lineage_mask_quality(block, path)
    after = json.loads(path.read_text())
    assert after["metrics"]["mask_quality"] == block
    for key, value in before["metrics"].items():
        assert after["metrics"][key] == value
    assert after["model_version"] == "abc"
    # A lineage with no metrics block yet gets one.
    bare = tmp_path / "bare.json"
    bare.write_text(json.dumps({"model_version": "x"}))
    out = validation.update_lineage_mask_quality(block, bare)
    assert out["metrics"]["mask_quality"] == block and out["metrics"]["mean_iou"] is None


def test_special_channel_indices_are_the_palette_sentinels():
    assert validation.special_channel_indices() == (33, 34, 35)
