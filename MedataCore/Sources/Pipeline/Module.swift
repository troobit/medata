// Pipeline module — orchestrates the per-path graph (design §2.2 / §2.3).
// Implementation lands in tasks 49–54.
import Foundation
import CaptureKit
import CardDetection
import Confidence
import Foods
import Macros
import MetricScale
import Persistence
import PortableContracts
import Segmentation
import SupportPlane
import Volume

public enum PipelineModule {
    public static let moduleName = "Pipeline"
}
