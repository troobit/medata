import SwiftUI

// Stub registered in task 12; the live telemetry capsule (tilt°, distance/band,
// LiDAR dot) is built in task 14 (capture chrome rebuild). Kept compilable so
// the shell swap builds before the chrome work lands.
struct TelemetryCapsule: View {
    var body: some View { EmptyView() }
}
