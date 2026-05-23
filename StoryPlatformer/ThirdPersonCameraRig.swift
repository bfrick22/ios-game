import RealityKit
import simd

/// Third-person orbit camera: positions behind and above the player, auto-follows player heading with smooth lag.
struct ThirdPersonCameraRig {
    var armLength: Float = 5.2           // closer for enclosed factory spaces
    var pitchAngle: Float = 0.40        // ~23° look-down shows more level floor
    var lookAtOffsetY: Float = 0.85     // look-at point height above player.position.y
    var positionSmoothSpeed: Float = 10.0
    var yawFollowSpeed: Float = 5.5     // faster yaw for responsive 3rd-person feel

    /// Unit XZ vector representing where the camera arm is pointed (player facing direction).
    /// Starts facing -Z so the camera sits at +Z of player, looking -Z into the level.
    private var currentFacing: SIMD3<Float> = SIMD3(0, 0, -1)
    private var currentEye: SIMD3<Float> = SIMD3(0, 3, 5)

    /// Transient impact shake magnitude (meters of eye jitter); decays each tick.
    private var shakeAmount: Float = 0

    /// Add a one-shot camera kick, e.g. on a landed strike.
    mutating func addShake(_ amount: Float) {
        shakeAmount = min(0.3, shakeAmount + amount)
    }

    /// Direction to move the player when stick is pushed forward.
    var groundForward: SIMD3<Float> { currentFacing }

    /// Direction to move the player when stick is pushed right.
    /// Equals cross(currentFacing, worldUp) in right-handed coordinates.
    var groundRight: SIMD3<Float> {
        SIMD3(-currentFacing.z, 0, currentFacing.x)
    }

    mutating func reset(playerPosition: SIMD3<Float>) {
        let lookAt = SIMD3(playerPosition.x, playerPosition.y + lookAtOffsetY, playerPosition.z)
        let back = -currentFacing
        let armXZ = back * (armLength * cos(pitchAngle))
        currentEye = lookAt + armXZ + SIMD3(0, sin(pitchAngle) * armLength, 0)
    }

    /// Advances the rig one tick. `playerFacing` is a unit XZ vector for where the player faces.
    mutating func step(
        deltaTime: Float,
        playerPosition: SIMD3<Float>,
        playerFacing: SIMD3<Float>
    ) -> Transform {
        // Smoothly blend currentFacing toward playerFacing and re-normalize in XZ plane.
        let t = min(1, yawFollowSpeed * deltaTime)
        let blended = currentFacing + (playerFacing - currentFacing) * t
        let mag = simd_length(SIMD2(blended.x, blended.z))
        if mag > 0.001 {
            currentFacing = SIMD3(blended.x / mag, 0, blended.z / mag)
        }

        let lookAt = SIMD3(playerPosition.x, playerPosition.y + lookAtOffsetY, playerPosition.z)

        // Camera arm: extend opposite to player facing (behind), elevated by pitch.
        let back = -currentFacing
        let armXZ = back * (armLength * cos(pitchAngle))
        let targetEye = lookAt + armXZ + SIMD3(0, sin(pitchAngle) * armLength, 0)

        let alpha = 1 - exp(-positionSmoothSpeed * deltaTime)
        currentEye += (targetEye - currentEye) * alpha

        // Transient impact shake: jitter the eye, decaying fast. Base eye is unshaken
        // so the kick doesn't accumulate into the smoothed follow position.
        shakeAmount *= exp(-14 * deltaTime)
        if shakeAmount < 0.001 { shakeAmount = 0 }
        let jitter = SIMD3<Float>(
            Float.random(in: -1 ... 1),
            Float.random(in: -1 ... 1),
            Float.random(in: -1 ... 1)
        ) * shakeAmount
        let eye = currentEye + jitter

        // Build rotation: camera looks from the (shaken) eye toward lookAt.
        let forward = normalize(lookAt - eye)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = cross(right, forward)
        let rotMat = simd_float3x3(columns: (right, up, -forward))
        let orientation = simd_quatf(rotMat)

        return Transform(scale: .one, rotation: orientation, translation: eye)
    }
}
