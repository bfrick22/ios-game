import RealityKit
import simd

/// Side-scroller rig: follow player X, smooth Y, fixed Z depth. Camera -Z aims at the player.
struct SideScrollCameraRig {
    var offsetZ: Float = 7
    var heightY: Float = 1.6
    var lookAheadX: Float = 0.8
    var smoothXZ: Float = 10
    var smoothY: Float = 8

    private var currentEye = SIMD3<Float>(0, 1.6, 7)

    mutating func reset(eye: SIMD3<Float>) {
        currentEye = eye
    }

    mutating func step(
        deltaTime: Float,
        playerPosition: SIMD3<Float>
    ) -> Transform {
        let targetX = playerPosition.x + lookAheadX
        let targetY = playerPosition.y + heightY
        let targetZ = playerPosition.z + offsetZ

        let alphaXZ = 1 - exp(-smoothXZ * deltaTime)
        let alphaY = 1 - exp(-smoothY * deltaTime)

        currentEye.x += (targetX - currentEye.x) * alphaXZ
        currentEye.z += (targetZ - currentEye.z) * alphaXZ
        currentEye.y += (targetY - currentEye.y) * alphaY

        let lookAt = SIMD3<Float>(playerPosition.x, playerPosition.y + 0.55, playerPosition.z)
        let forward = normalize(lookAt - currentEye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = cross(right, forward)
        let rotation = simd_float3x3(columns: (right, up, -forward))
        let orientation = simd_quatf(rotation)

        return Transform(scale: .one, rotation: orientation, translation: currentEye)
    }
}
