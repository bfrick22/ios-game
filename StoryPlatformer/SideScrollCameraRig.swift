import RealityKit
import simd

/// Side-scroller rig: follow player X (with velocity-aware look-ahead), smooth Y, damped Z depth. Camera -Z aims at the player.
struct SideScrollCameraRig {
    var offsetZ: Float = 7
    var heightY: Float = 1.6
    /// Base horizontal offset in the facing / movement direction.
    var lookAheadX: Float = 0.85
    /// Extra look-ahead from horizontal speed (meters per m/s).
    var velocityLookAheadScale: Float = 0.14
    var lookAheadMaxExtra: Float = 1.15
    var smoothXZ: Float = 11
    var smoothY: Float = 9.5
    /// Z tracks the play plane gently (plan: fixed or softly damped depth).
    var smoothZ: Float = 14

    private var currentEye = SIMD3<Float>(0, 1.6, 7)
    /// Smoothed aim height so look-at does not snap on every small vertical change.
    private var smoothedLookY: Float = 0.55

    mutating func reset(eye: SIMD3<Float>, playerPosition: SIMD3<Float>) {
        currentEye = eye
        smoothedLookY = playerPosition.y + 0.55
    }

    mutating func step(
        deltaTime: Float,
        playerPosition: SIMD3<Float>,
        horizontalVelocity: Float,
        facingSign: Float
    ) -> Transform {
        let speed = abs(horizontalVelocity)
        let extra = min(lookAheadMaxExtra, speed * velocityLookAheadScale)
        let direction: Float
        if speed > 0.2 {
            direction = horizontalVelocity > 0 ? 1 : -1
        } else {
            direction = facingSign >= 0 ? 1 : -1
        }
        let dynamicLook = lookAheadX + extra
        let targetX = playerPosition.x + dynamicLook * direction

        let rawLookY = playerPosition.y + 0.55

        let targetY = playerPosition.y + heightY
        let targetZ = playerPosition.z + offsetZ

        let alphaXZ = 1 - exp(-smoothXZ * deltaTime)
        let alphaY = 1 - exp(-smoothY * deltaTime)
        let alphaZ = 1 - exp(-smoothZ * deltaTime)
        let alphaLookY = 1 - exp(-(smoothY * 0.92) * deltaTime)

        currentEye.x += (targetX - currentEye.x) * alphaXZ
        currentEye.z += (targetZ - currentEye.z) * alphaZ
        currentEye.y += (targetY - currentEye.y) * alphaY
        smoothedLookY += (rawLookY - smoothedLookY) * alphaLookY

        let lookAt = SIMD3<Float>(playerPosition.x, smoothedLookY, playerPosition.z)
        let forward = normalize(lookAt - currentEye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = cross(right, forward)
        let rotation = simd_float3x3(columns: (right, up, -forward))
        let orientation = simd_quatf(rotation)

        return Transform(scale: .one, rotation: orientation, translation: currentEye)
    }
}
