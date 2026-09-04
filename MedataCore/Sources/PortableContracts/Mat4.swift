import Foundation

// Portable Mat4. Column-major 4x4 (matches simd, OpenGL, standard linear-algebra notation),
// per design §6.0. Storage is `m[col][row]` so m[0] is column 0.
// Maps to Pb_Mat4 (a flat 16-float repeated, column-major: m[col*4 + row]).
public struct Mat4: Sendable, Codable, Equatable, Hashable {
    public var columns: [[Float]]

    public init(columns: [[Float]]) {
        precondition(columns.count == 4 && columns.allSatisfy { $0.count == 4 },
                     "Mat4 requires 4 columns of 4 floats")
        self.columns = columns
    }

    public init(flatColumnMajor f: [Float]) {
        precondition(f.count == 16, "Mat4 flat init requires exactly 16 floats")
        var cols: [[Float]] = []
        cols.reserveCapacity(4)
        for c in 0..<4 {
            cols.append(Array(f[(c * 4)..<((c + 1) * 4)]))
        }
        self.init(columns: cols)
    }

    public static let identity: Mat4 = {
        Mat4(columns: [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ])
    }()

    public subscript(col col: Int, row row: Int) -> Float {
        get { columns[col][row] }
        set { columns[col][row] = newValue }
    }

    public func flatColumnMajor() -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(16)
        for c in 0..<4 { out.append(contentsOf: columns[c]) }
        return out
    }
}

public extension Mat4 {
    init(pb: PbMat4) {
        precondition(pb.m.count == 16, "PbMat4 must contain exactly 16 floats")
        self.init(flatColumnMajor: pb.m)
    }

    var pb: PbMat4 {
        var out = PbMat4()
        out.m = flatColumnMajor()
        return out
    }
}
