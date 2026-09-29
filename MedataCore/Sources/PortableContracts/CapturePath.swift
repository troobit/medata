// Native Swift CapturePath — mirrors PbCapturePath from VolumeResult.proto.
// Lives in PortableContracts because it crosses module boundaries (Volume, Confidence, Pipeline).
public enum CapturePath: String, Equatable, Sendable, Codable {
    case singleViewLidar = "single_view_lidar"
    case twoViewSfS = "two_view_sfs"
}
