import Foundation
import Persistence

// The review-side reading of two-view-trust Decision 8's degraded marker.
//
// `PipelineDiagnostics` stamps `degradedReason = unbounded_carve_height` onto
// the outcome row of every two-view attempt whose nadir frame carried no depth.
// The outcome row is not what the review screen holds — it holds the persisted
// `MealRecord` — so the same fact is re-derived here from two fields the record
// already carries, rather than widening the meal schema for a second copy of it.
public extension MealRecord {
    /// True when this meal's volume came from a two-view carve with no depth in
    /// the nadir frame, so nothing measured the food's height and the voxel
    /// grid's constant vertical extent set the answer (two-view-trust
    /// Decision 8). The figure is not a measurement.
    ///
    /// `lidarScaleAvailable` is the record's witness for depth: the pipeline
    /// derives the LiDAR scale from the fitted plane's distance and passes it to
    /// `MetricScaleResolver` exactly when `nadir.depth != nil`, and the resolver
    /// carries that through unchanged. A card scale can be dropped for
    /// disagreeing with LiDAR; a LiDAR scale never is.
    var carveHeightWasUnbounded: Bool {
        capturePath == .twoViewSfS && !scale.lidarScaleAvailable
    }
}
