import Foundation

// Portable Vec3. Right-handed, +X right, +Y up, -Z forward (camera looks along -Z).
// Mirrors design §3.1 / §6.0; bridges to generated Pb_Vec3 from Math.proto.
public struct Vec3: Sendable, Codable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(x: x, y: y, z: z)
    }

    public static let zero = Vec3(0, 0, 0)
}

public extension Vec3 {
    static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func * (lhs: Float, rhs: Vec3) -> Vec3 {
        Vec3(lhs * rhs.x, lhs * rhs.y, lhs * rhs.z)
    }

    static func * (lhs: Vec3, rhs: Float) -> Vec3 {
        rhs * lhs
    }

    static prefix func - (v: Vec3) -> Vec3 {
        Vec3(-v.x, -v.y, -v.z)
    }

    func dot(_ other: Vec3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    // Right-handed cross product per design §6.0: a × b = (a_y b_z − a_z b_y,
    // a_z b_x − a_x b_z, a_x b_y − a_y b_x).
    func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    var lengthSquared: Float { x * x + y * y + z * z }

    var length: Float { lengthSquared.squareRoot() }

    func normalised() -> Vec3 {
        let len = length
        guard len > 0 else { return self }
        return Vec3(x / len, y / len, z / len)
    }
}

public extension Vec3 {
    init(pb: PbVec3) {
        self.init(pb.x, pb.y, pb.z)
    }

    var pb: PbVec3 {
        var out = PbVec3()
        out.x = x
        out.y = y
        out.z = z
        return out
    }
}
