import RealityKit
import simd

/// Third-person orbit camera (standard "camera-relative" rig).
/// Yaw/pitch are player-controlled via the look pad; the rig gently auto-recenters
/// behind the player's heading while moving and not actively looking. Movement is
/// expressed relative to `groundForward`/`groundRight` so "up" always drives into
/// the screen and the character (which faces its travel direction) shows its back.
struct ThirdPersonCameraRig {
    var armLength: Float = 5.2
    var lookAtOffsetY: Float = 0.85
    var positionSmoothSpeed: Float = 12.0
    var recenterSpeed: Float = 2.2       // gentle follow-behind when moving & not looking
    var minPitch: Float = 0.18
    var maxPitch: Float = 0.95

    private var yaw: Float = 0           // azimuth; 0 => camera looks toward -Z
    private var pitch: Float = 0.42      // downward tilt
    private var currentEye: SIMD3<Float> = SIMD3(0, 3, 5)
    private var shakeAmount: Float = 0

    /// Horizontal direction the camera looks — the "forward" for movement.
    var groundForward: SIMD3<Float> { SIMD3(sin(yaw), 0, -cos(yaw)) }
    /// Camera "right" on the ground — the "strafe right" for movement.
    var groundRight: SIMD3<Float> { SIMD3(cos(yaw), 0, sin(yaw)) }

    /// Add a one-shot camera kick, e.g. on a landed strike.
    mutating func addShake(_ amount: Float) {
        shakeAmount = min(0.3, shakeAmount + amount)
    }

    /// Orbit the camera from look-pad drag deltas (radians).
    mutating func applyLook(yawDelta: Float, pitchDelta: Float) {
        yaw += yawDelta
        pitch = min(maxPitch, max(minPitch, pitch + pitchDelta))
    }

    mutating func reset(playerPosition: SIMD3<Float>, facing: SIMD3<Float>) {
        yaw = atan2(facing.x, -facing.z)
        let lookAt = SIMD3(playerPosition.x, playerPosition.y + lookAtOffsetY, playerPosition.z)
        currentEye = eyePosition(lookAt: lookAt)
    }

    private func eyePosition(lookAt: SIMD3<Float>) -> SIMD3<Float> {
        let fwd = groundForward
        let horiz = armLength * cos(pitch)
        return lookAt - fwd * horiz + SIMD3(0, sin(pitch) * armLength, 0)
    }

    /// Advances the rig one tick. `playerFacing` is a unit XZ heading; `autoRecenter`
    /// eases the camera behind it (off while the player is looking or standing still).
    mutating func step(
        deltaTime: Float,
        playerPosition: SIMD3<Float>,
        playerFacing: SIMD3<Float>,
        autoRecenter: Bool
    ) -> Transform {
        if autoRecenter {
            let targetYaw = atan2(playerFacing.x, -playerFacing.z)
            let d = atan2(sin(targetYaw - yaw), cos(targetYaw - yaw))   // shortest signed diff
            yaw += d * (1 - exp(-recenterSpeed * deltaTime))
        }

        let lookAt = SIMD3(playerPosition.x, playerPosition.y + lookAtOffsetY, playerPosition.z)
        let targetEye = eyePosition(lookAt: lookAt)
        let alpha = 1 - exp(-positionSmoothSpeed * deltaTime)
        currentEye += (targetEye - currentEye) * alpha

        // Transient impact shake (decays fast); base eye stays unshaken.
        shakeAmount *= exp(-14 * deltaTime)
        if shakeAmount < 0.001 { shakeAmount = 0 }
        let jitter = SIMD3<Float>(
            Float.random(in: -1 ... 1),
            Float.random(in: -1 ... 1),
            Float.random(in: -1 ... 1)
        ) * shakeAmount
        let eye = currentEye + jitter

        let forward = normalize(lookAt - eye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = cross(right, forward)
        let rotMat = simd_float3x3(columns: (right, up, -forward))
        return Transform(scale: .one, rotation: simd_quatf(rotMat), translation: eye)
    }
}
