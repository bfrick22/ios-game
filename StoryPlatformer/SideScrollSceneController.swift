import os
import QuartzCore
import RealityKit
import simd
import UIKit

private struct AxisAlignedRegion {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    func contains(_ p: SIMD3<Float>) -> Bool {
        p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y && p.z >= min.z && p.z <= max.z
    }
}

private struct EnemyRuntime {
    let configId: String
    let entity: ModelEntity
    var health: Float
    let patrolMinX: Float
    let patrolMaxX: Float
    var velocitySign: Float
    let speed: Float
}

/// Owns RealityKit entities, physics, and the side-scroll camera for one loaded segment.
@MainActor
final class SideScrollSceneController {
    private(set) var perspectiveCamera = PerspectiveCamera()

    /// Profile with Instruments → os_signpost / Swift Concurrency (Points of Interest): `chapter_scene_attach`, `chapter_scene_teardown`, `simulation_tick`.
    private let signposter = OSSignposter(subsystem: "com.storyplatformer.app", category: "Gameplay")

    private let root = Entity()
    private let cameraAnchor = Entity()
    private let player = ModelEntity()
    private let playerVisualRoot = Entity()
    private let playerTorso = ModelEntity()
    private let playerHead = ModelEntity()
    private let playerLeftArm = ModelEntity()
    private let playerRightArm = ModelEntity()
    private let playerLeftLeg = ModelEntity()
    private let playerRightLeg = ModelEntity()
    private let ground = ModelEntity()
    private let ladderVisual = ModelEntity()
    private let interactProp = ModelEntity()
    private let workstationProp = ModelEntity()
    private let hazardStrip = ModelEntity()
    private let completionMarker = ModelEntity()
    private let tripwireVisual = ModelEntity()
    private let corridorWallNegZ = Entity()
    private let corridorWallPosZ = Entity()
    private let prototypeObstacles = Entity()
    private var cameraRig = SideScrollCameraRig()
    private var lastMediaTime: CFTimeInterval?
    /// Scene graph (meshes, hierarchy) built once per controller lifetime.
    private var sceneGraphBuilt = false
    /// `root` is currently added to `RealityView` content.
    private var attachedToScene = false

    private var enemyRuntimes: [EnemyRuntime] = []
    private var tripwireArmed = false
    private var tripwireRegion: AxisAlignedRegion?
    private var meleeCooldownRemaining: Float = 0
    private var hostileContactCooldown: Float = 0

    // Player visual animation state (does not affect physics).
    private var locomotionPhase: Float = 0
    private var locomotionBlend: Float = 0

    private var loadedChapter: ChapterConfig?
    private var loadedWorkstations: [CraftingWorkstationConfig] = []
    private var completionRegion = AxisAlignedRegion(
        min: SIMD3<Float>(10.75, 0.02, -1.1),
        max: SIMD3<Float>(12.6, 4, 1.1)
    )
    private var completionLatch = false
    private var storyBeatRewardClaimed = false
    private var hazardRegion: AxisAlignedRegion?
    private var hazardCooldownRemaining: Float = 0

    private static let capsuleHeight: Float = 1.15 * 0.70
    private static let capsuleRadius: Float = 0.32 * 0.70
    /// Matches `PhysicsBodyComponent` mass in `buildPlayer()`; used for impulse = mass × Δv.
    private static let playerMass: Float = 70

    private lazy var playerGroundMaterial: PhysicsMaterialResource = {
        PhysicsMaterialResource.generate(friction: 0.95, restitution: 0)
    }()

    private let landingSettleVyThreshold: Float = 0.6 * 0.70

    /// Half-width along world Z for walkable depth; inner faces of `corridorWall*` sit at ±this value.
    private let corridorHalfWidth: Float = 2.12
    private let depthRunSpeed: Float = 4.0
    private let depthAccel: Float = 20

    /// Ladder volume (hand-tuned to match `ladderVisual`).
    private let climbRegion = AxisAlignedRegion(
        min: SIMD3<Float>(3.52, 0.02, -0.58),
        max: SIMD3<Float>(4.48, 3.25, 0.58)
    )

    private let interactReachX: Float = 1.45
    private let interactReachZ: Float = 0.95
    private let interactReachY: Float = 1.7

    /// Caller adds `root` to `RealityView` content, then sets `content.camera = .virtual` and `content.cameraTarget = perspectiveCamera`.
    func attachIfNeeded(
        insertRoot: (Entity) -> Void,
        viewModel: GameSessionViewModel,
        chapter: ChapterConfig
    ) {
        if !sceneGraphBuilt {
            buildGround()
            buildLadderVisual()
            buildHazardStripPlaceholder()
            buildCompletionMarkerPlaceholder()
            buildInteractProp()
            buildWorkstationProp()
            buildTripwireVisualPlaceholder()
            buildCorridorWalls()
            buildPrototypeObstacles()
            buildPlayer()

            root.addChild(ground)
            root.addChild(ladderVisual)
            root.addChild(hazardStrip)
            root.addChild(completionMarker)
            root.addChild(tripwireVisual)
            root.addChild(interactProp)
            root.addChild(workstationProp)
            root.addChild(corridorWallNegZ)
            root.addChild(corridorWallPosZ)
            root.addChild(prototypeObstacles)
            root.addChild(player)
            root.addChild(cameraAnchor)
            cameraAnchor.addChild(perspectiveCamera)

            sceneGraphBuilt = true
        }

        guard !attachedToScene else { return }

        let loadID = signposter.makeSignpostID()
        let loadState = signposter.beginInterval("chapter_scene_attach", id: loadID)
        insertRoot(root)
        attachedToScene = true

        applyChapter(chapter, viewModel: viewModel)
        signposter.endInterval("chapter_scene_attach", loadState)

        tick(viewModel: viewModel)
    }

    /// Removes the scene from `RealityView` and clears combat entities so the next attach loads a clean chapter state.
    /// Call from `onDisappear` so only one chapter scene stays resident while navigating away.
    func teardown() {
        guard attachedToScene else { return }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval("chapter_scene_teardown", id: id)
        removeAllCombatEntities()
        root.removeFromParent()
        attachedToScene = false
        lastMediaTime = nil
        loadedChapter = nil
        loadedWorkstations = []
        signposter.endInterval("chapter_scene_teardown", state)
    }

    /// Reapply spawn, volumes, and authored props when the hosted chapter changes (same scene instance).
    func applyChapter(_ chapter: ChapterConfig, viewModel: GameSessionViewModel) {
        loadedChapter = chapter
        loadedWorkstations = chapter.craftingWorkstations ?? []
        viewModel.resetSessionForNewChapter()
        completionRegion = AxisAlignedRegion(
            min: chapter.completionVolume.min.simd,
            max: chapter.completionVolume.max.simd
        )
        completionLatch = false
        storyBeatRewardClaimed = false
        hazardCooldownRemaining = 0

        if let hv = chapter.hazardVolume {
            hazardRegion = AxisAlignedRegion(min: hv.min.simd, max: hv.max.simd)
            configureHazardVisual(boundsMin: hv.min.simd, boundsMax: hv.max.simd)
            hazardStrip.isEnabled = true
        } else {
            hazardRegion = nil
            hazardStrip.isEnabled = false
        }

        configureCompletionMarker(
            boundsMin: chapter.completionVolume.min.simd,
            boundsMax: chapter.completionVolume.max.simd
        )

        if let beat = chapter.storyBeat {
            interactProp.isEnabled = true
            interactProp.position = beat.worldPosition.simd
        } else {
            interactProp.isEnabled = false
        }

        if let first = loadedWorkstations.first {
            workstationProp.isEnabled = true
            workstationProp.position = first.worldPosition.simd
        } else {
            workstationProp.isEnabled = false
        }

        rebuildCombat(from: chapter)

        resetPlayerAtSpawn(chapter.playerSpawn.simd, viewModel: viewModel)
    }

    func tick(viewModel: GameSessionViewModel) {
        guard attachedToScene else { return }

        let tickID = signposter.makeSignpostID()
        let tickState = signposter.beginInterval("simulation_tick", id: tickID)
        defer { signposter.endInterval("simulation_tick", tickState) }

        let now = CACurrentMediaTime()
        let deltaTime: Float
        if let last = lastMediaTime {
            deltaTime = Float(now - last)
        } else {
            deltaTime = 1 / 60
        }
        lastMediaTime = now

        guard deltaTime > 0, deltaTime < 0.25 else { return }

        let climbing = climbRegion.contains(player.position)
        viewModel.isClimbing = climbing

        if climbing {
            applyClimbingMovement(viewModel: viewModel, deltaTime: deltaTime)
        } else {
            applyMovement(viewModel: viewModel, deltaTime: deltaTime)
            applyCorridorDepthMovement(viewModel: viewModel, deltaTime: deltaTime)
        }

        let grounded = computeGrounded()
        viewModel.isGrounded = grounded
        dampLandingVerticalVelocityIfNeeded(grounded: grounded, climbing: climbing)

        updateFacing(viewModel: viewModel)
        updatePlayerVisual(deltaTime: deltaTime, viewModel: viewModel)

        if hazardCooldownRemaining > 0 {
            hazardCooldownRemaining = max(0, hazardCooldownRemaining - deltaTime)
        }
        if meleeCooldownRemaining > 0 {
            meleeCooldownRemaining = max(0, meleeCooldownRemaining - deltaTime)
        }
        if hostileContactCooldown > 0 {
            hostileContactCooldown = max(0, hostileContactCooldown - deltaTime)
        }

        processHazard(viewModel: viewModel)
        updateEnemyPatrol(deltaTime: deltaTime)
        processTripwireTrigger(viewModel: viewModel)
        updateInteractPrompt(viewModel: viewModel)
        applyJumpIfNeeded(viewModel: viewModel, climbing: climbing, grounded: grounded)
        processMeleeAttack(viewModel: viewModel, grounded: grounded, climbing: climbing)
        processHostileContact(viewModel: viewModel)
        processInteract(viewModel: viewModel)
        processChapterCompletion(viewModel: viewModel)

        let vx = player.components[PhysicsMotionComponent.self]?.linearVelocity.x ?? 0
        perspectiveCamera.transform = cameraRig.step(
            deltaTime: deltaTime,
            playerPosition: player.position,
            horizontalVelocity: vx,
            facingSign: viewModel.facingSign
        )
    }

    private func buildGround() {
        let size = SIMD3<Float>(48, 0.25, 5)
        ground.model = ModelComponent(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: UIColor(white: 0.35, alpha: 1), isMetallic: false)]
        )
        ground.position = SIMD3<Float>(4, -0.25, 0)
        ground.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        ground.components.set(PhysicsBodyComponent(
            massProperties: .default,
            material: playerGroundMaterial,
            mode: .static
        ))
    }

    private func buildCorridorWalls() {
        let thickness: Float = 0.12
        let halfExtentZ = corridorHalfWidth + thickness * 0.5
        let spanX: Float = 52
        let wallSize = SIMD3<Float>(spanX, 10, thickness)
        let shape = ShapeResource.generateBox(size: wallSize)

        for wall in [corridorWallNegZ, corridorWallPosZ] {
            wall.components.set(CollisionComponent(shapes: [shape], mode: .default))
            wall.components.set(PhysicsBodyComponent(massProperties: .default, mode: .static))
        }

        corridorWallNegZ.position = SIMD3<Float>(4, 2.5, -halfExtentZ)
        corridorWallPosZ.position = SIMD3<Float>(4, 2.5, halfExtentZ)
    }

    /// Hard-coded static masses for 2.5D navigation: block straight-ahead X routes but leave a Z lane to pass.
    private func buildPrototypeObstacles() {
        prototypeObstacles.name = "Prototype.obstacles"

        let groundTopY: Float = -0.125

        func addStaticMass(
            name: String,
            size: SIMD3<Float>,
            center: SIMD3<Float>,
            color: UIColor
        ) {
            let ent = ModelEntity()
            ent.name = name
            ent.model = ModelComponent(
                mesh: .generateBox(size: size, cornerRadius: 0.02),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            var p = center
            p.y = groundTopY + size.y * 0.5
            ent.position = p
            ent.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            ent.components.set(PhysicsBodyComponent(
                massProperties: .default,
                material: playerGroundMaterial,
                mode: .static
            ))
            prototypeObstacles.addChild(ent)
        }

        // East of spawn: occupies +Z half of the corridor; detour on −Z (avoids ladder x band until lane merge).
        addStaticMass(
            name: "Obstacle.wall_segment_near_start",
            size: SIMD3<Float>(0.88, 2.55, 1.35),
            center: SIMD3<Float>(3.0, 0, 0.9),
            color: UIColor(red: 0.34, green: 0.33, blue: 0.32, alpha: 1)
        )

        // Past the ch.1 hazard strip: blocks −Z; weave toward +Z to reach the go-bag beat.
        addStaticMass(
            name: "Obstacle.building_corner_mid",
            size: SIMD3<Float>(1.05, 2.85, 1.5),
            center: SIMD3<Float>(7.35, 0, -0.88),
            color: UIColor(red: 0.30, green: 0.29, blue: 0.27, alpha: 1)
        )

        // Before exit volume: shallow X depth, offset in +Z; pass on −Z or center-left along X.
        addStaticMass(
            name: "Obstacle.abandoned_kiosk",
            size: SIMD3<Float>(1.15, 2.2, 1.25),
            center: SIMD3<Float>(9.85, 0, 0.92),
            color: UIColor(red: 0.36, green: 0.34, blue: 0.31, alpha: 1)
        )
    }

    private func buildLadderVisual() {
        let size = SIMD3<Float>(0.12, 3.1, 0.5)
        ladderVisual.model = ModelComponent(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: UIColor(white: 0.55, alpha: 0.35), isMetallic: false)]
        )
        ladderVisual.position = SIMD3<Float>(4, 1.55, 0)
    }

    private func buildHazardStripPlaceholder() {
        hazardStrip.name = "hazard.bus_bar"
        hazardStrip.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(1, 0.06, 1)),
            materials: [SimpleMaterial(color: UIColor(red: 0.95, green: 0.35, blue: 0.08, alpha: 1), isMetallic: false)]
        )
        hazardStrip.position = .zero
        hazardStrip.isEnabled = false
    }

    private func configureHazardVisual(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        let center = (boundsMin + boundsMax) * 0.5
        hazardStrip.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(
                Swift.max(ext.x, 0.05),
                Swift.max(ext.y, 0.05),
                Swift.max(ext.z, 0.05)
            )),
            materials: [SimpleMaterial(color: UIColor(red: 0.92, green: 0.28, blue: 0.06, alpha: 0.92), isMetallic: false)]
        )
        hazardStrip.position = center
    }

    private func buildCompletionMarkerPlaceholder() {
        completionMarker.name = "trigger.completion_visual"
        completionMarker.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)),
            materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.72, blue: 0.38, alpha: 0.22), isMetallic: false)]
        )
        completionMarker.position = .zero
    }

    private func configureCompletionMarker(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        let center = (boundsMin + boundsMax) * 0.5
        completionMarker.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(
                Swift.max(ext.x, 0.1),
                Swift.max(ext.y, 0.1),
                Swift.max(ext.z, 0.1)
            )),
            materials: [SimpleMaterial(color: UIColor(red: 0.12, green: 0.65, blue: 0.4, alpha: 0.18), isMetallic: false)]
        )
        completionMarker.position = center
    }

    private func buildInteractProp() {
        let size = SIMD3<Float>(0.45, 0.75, 0.35)
        interactProp.name = "Interactable.story_beat"
        interactProp.model = ModelComponent(
            mesh: .generateBox(size: size, cornerRadius: 0.04),
            materials: [SimpleMaterial(color: UIColor(white: 0.42, alpha: 1), isMetallic: true)]
        )
        interactProp.position = .zero
    }

    private func buildWorkstationProp() {
        let size = SIMD3<Float>(0.85, 0.55, 0.45)
        workstationProp.name = "Interactable.workbench"
        workstationProp.model = ModelComponent(
            mesh: .generateBox(size: size, cornerRadius: 0.06),
            materials: [SimpleMaterial(color: UIColor(red: 0.38, green: 0.28, blue: 0.18, alpha: 1), isMetallic: false)]
        )
        workstationProp.position = .zero
        workstationProp.isEnabled = false
    }

    private func buildTripwireVisualPlaceholder() {
        tripwireVisual.name = "trap.tripwire_visual"
        tripwireVisual.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(0.28, 0.04, 0.04)),
            materials: [SimpleMaterial(color: UIColor(white: 0.25, alpha: 0.85), isMetallic: false)]
        )
        tripwireVisual.position = .zero
        tripwireVisual.isEnabled = false
    }

    private func configureTripwireVisual(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        let center = (boundsMin + boundsMax) * 0.5
        tripwireVisual.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(
                Swift.max(ext.x, 0.08),
                Swift.max(ext.y * 0.12, 0.04),
                Swift.max(ext.z, 0.08)
            )),
            materials: [SimpleMaterial(color: UIColor(white: 0.32, alpha: 0.55), isMetallic: false)]
        )
        tripwireVisual.position = center
    }

    private func removeAllCombatEntities() {
        for er in enemyRuntimes {
            er.entity.removeFromParent()
        }
        enemyRuntimes.removeAll()
        tripwireArmed = false
        tripwireRegion = nil
        tripwireVisual.isEnabled = false
    }

    private func rebuildCombat(from chapter: ChapterConfig) {
        removeAllCombatEntities()

        if let tw = chapter.tripwire {
            tripwireRegion = AxisAlignedRegion(min: tw.triggerVolume.min.simd, max: tw.triggerVolume.max.simd)
            configureTripwireVisual(boundsMin: tw.triggerVolume.min.simd, boundsMax: tw.triggerVolume.max.simd)
        }

        if let enemies = chapter.combatEnemies {
            for e in enemies {
                appendEnemy(from: e)
            }
        }
    }

    private func appendEnemy(from config: CombatEnemyConfig) {
        let w: Float = 0.46
        let h: Float = 0.94
        let ent = ModelEntity()
        ent.name = "Hostile.\(config.id)"
        ent.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(w, h, w * 0.82)),
            materials: [SimpleMaterial(color: UIColor(red: 0.42, green: 0.2, blue: 0.16, alpha: 1), isMetallic: false)]
        )
        let base = config.worldPosition.simd
        ent.position = base
        let patrolMin = base.x - config.patrolHalfWidth
        let patrolMax = base.x + config.patrolHalfWidth
        let er = EnemyRuntime(
            configId: config.id,
            entity: ent,
            health: config.maxHealth,
            patrolMinX: patrolMin,
            patrolMaxX: patrolMax,
            velocitySign: 1,
            speed: config.moveSpeed
        )
        enemyRuntimes.append(er)
        root.addChild(ent)
    }

    private func updateFacing(viewModel: GameSessionViewModel) {
        if abs(viewModel.horizontalInput) > 0.12 {
            viewModel.facingSign = viewModel.horizontalInput > 0 ? 1 : -1
        } else if let motion = player.components[PhysicsMotionComponent.self], abs(motion.linearVelocity.x) > 0.22 {
            // Keep facing aligned with horizontal motion when stick is neutral (e.g. after release).
            viewModel.facingSign = motion.linearVelocity.x > 0 ? 1 : -1
        }
    }

    private func updatePlayerVisual(deltaTime: Float, viewModel: GameSessionViewModel) {
        // Face the rig without rotating the physics body. Camera sits at +Z looking at the player along -Z;
        // authored parts use local +Z as depth. Rotate ±90° so the figure faces ±X (side-scroll travel), not ±Z.
        let facingAngleY: Float = viewModel.facingSign >= 0 ? .pi / 2 : -.pi / 2
        playerVisualRoot.transform.rotation = simd_quatf(angle: facingAngleY, axis: SIMD3<Float>(0, 1, 0))

        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity
        let planarSpeed = simd_length(SIMD2<Float>(v.x, v.z))

        // Blend in/out of locomotion with idle damping.
        let speedDeadZone: Float = 0.15
        let speedFull: Float = 2.1
        let targetBlend = min(1, max(0, (planarSpeed - speedDeadZone) / max(0.01, (speedFull - speedDeadZone))))
        let blendResponse: Float = targetBlend > locomotionBlend ? 10.5 : 7.5
        locomotionBlend += (targetBlend - locomotionBlend) * min(1, blendResponse * deltaTime)

        // Advance phase based on movement mode.
        let phaseRate: Float
        if viewModel.isClimbing {
            let climbSpeed = abs(v.y) + planarSpeed * 0.25
            phaseRate = (1.8 + 0.65 * min(4, climbSpeed)) * 2 * .pi
        } else {
            let walk = min(1, planarSpeed / 4.35)
            let strideHz = (1.4 + 1.9 * walk)
            phaseRate = strideHz * 2 * .pi
        }
        locomotionPhase = fmod(locomotionPhase + phaseRate * deltaTime, 2 * .pi)

        let s = sin(locomotionPhase)
        let c = cos(locomotionPhase)

        // Subtle body bob while moving.
        let baseTorsoY = Self.capsuleHeight * 0.60
        playerTorso.position.y = baseTorsoY + (0.03 * locomotionBlend) * abs(s)

        if viewModel.isClimbing {
            // "Reach" motion: alternate arms/legs with a small sway.
            let reachAmp: Float = 0.75 * locomotionBlend
            let swayAmp: Float = 0.25 * locomotionBlend

            let leftArmRot =
                simd_quatf(angle: reachAmp * s, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: swayAmp * c, axis: SIMD3<Float>(0, 0, 1))
            let rightArmRot =
                simd_quatf(angle: -reachAmp * s, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: -swayAmp * c, axis: SIMD3<Float>(0, 0, 1))
            let leftLegRot = simd_quatf(angle: -0.55 * reachAmp * s, axis: SIMD3<Float>(1, 0, 0))
            let rightLegRot = simd_quatf(angle: 0.55 * reachAmp * s, axis: SIMD3<Float>(1, 0, 0))

            playerLeftArm.transform.rotation = leftArmRot
            playerRightArm.transform.rotation = rightArmRot
            playerLeftLeg.transform.rotation = leftLegRot
            playerRightLeg.transform.rotation = rightLegRot
        } else {
            // Walk/run: swing about local X so limbs move fore/aft (depth) in side view — not toward the midline (Z), which reads as an X.
            let armAmp: Float = 0.85 * locomotionBlend
            let legAmp: Float = 1.05 * locomotionBlend

            playerLeftArm.transform.rotation = simd_quatf(angle: armAmp * s, axis: SIMD3<Float>(1, 0, 0))
            playerRightArm.transform.rotation = simd_quatf(angle: -armAmp * s, axis: SIMD3<Float>(1, 0, 0))
            playerLeftLeg.transform.rotation = simd_quatf(angle: -legAmp * s, axis: SIMD3<Float>(1, 0, 0))
            playerRightLeg.transform.rotation = simd_quatf(angle: legAmp * s, axis: SIMD3<Float>(1, 0, 0))
        }

        // Clamp tiny residuals at full idle.
        if locomotionBlend < 0.01 {
            playerLeftArm.transform.rotation = .init(angle: 0, axis: SIMD3<Float>(1, 0, 0))
            playerRightArm.transform.rotation = .init(angle: 0, axis: SIMD3<Float>(1, 0, 0))
            playerLeftLeg.transform.rotation = .init(angle: 0, axis: SIMD3<Float>(1, 0, 0))
            playerRightLeg.transform.rotation = .init(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        }
    }

    private func updateEnemyPatrol(deltaTime: Float) {
        for i in enemyRuntimes.indices {
            guard enemyRuntimes[i].health > 0 else { continue }
            var x = enemyRuntimes[i].entity.position.x
            x += enemyRuntimes[i].velocitySign * enemyRuntimes[i].speed * deltaTime
            if x >= enemyRuntimes[i].patrolMaxX {
                enemyRuntimes[i].velocitySign = -1
                x = enemyRuntimes[i].patrolMaxX
            } else if x <= enemyRuntimes[i].patrolMinX {
                enemyRuntimes[i].velocitySign = 1
                x = enemyRuntimes[i].patrolMinX
            }
            enemyRuntimes[i].entity.position.x = x
        }
    }

    private func processTripwireTrigger(viewModel: GameSessionViewModel) {
        guard tripwireArmed, let region = tripwireRegion else { return }
        for i in enemyRuntimes.indices {
            guard enemyRuntimes[i].health > 0 else { continue }
            guard region.contains(enemyRuntimes[i].entity.position) else { continue }

            let tripDamage: Float = 0.46
            enemyRuntimes[i].health -= tripDamage
            tripwireArmed = false
            tripwireVisual.isEnabled = false

            if enemyRuntimes[i].health <= 0 {
                enemyRuntimes[i].entity.isEnabled = false
                viewModel.flashInteractMessage("Tripwire — down.")
            } else {
                viewModel.flashInteractMessage("Tripwire — tangled.")
            }
            break
        }
    }

    private func processMeleeAttack(viewModel: GameSessionViewModel, grounded: Bool, climbing: Bool) {
        guard viewModel.attackRequested else { return }
        viewModel.attackRequested = false
        guard grounded, !climbing else { return }
        guard meleeCooldownRemaining <= 0 else { return }

        meleeCooldownRemaining = 0.45
        let dmg = MeleeCombat.strikeDamage(equippedWeaponItemId: viewModel.equippedWeaponItemId)
        let p = player.position
        let sign = viewModel.facingSign

        var hit = false
        for i in enemyRuntimes.indices {
            guard enemyRuntimes[i].health > 0 else { continue }
            let e = enemyRuntimes[i].entity.position
            guard enemyInMeleeArc(player: p, facingSign: sign, enemy: e) else { continue }
            enemyRuntimes[i].health -= dmg
            hit = true
            if enemyRuntimes[i].health <= 0 {
                enemyRuntimes[i].entity.isEnabled = false
                viewModel.flashInteractMessage("Hostile down.")
            } else {
                viewModel.flashInteractMessage("Solid hit.")
            }
            break
        }
        if !hit {
            viewModel.flashInteractMessage("Swing.")
        }
    }

    private func enemyInMeleeArc(player: SIMD3<Float>, facingSign: Float, enemy: SIMD3<Float>) -> Bool {
        let dx = enemy.x - player.x
        let dz = abs(enemy.z - player.z)
        let dy = abs(enemy.y - player.y)
        if dz > 0.52 || dy > 0.9 { return false }
        let forward = facingSign * dx
        return forward > 0.22 && forward < 1.12
    }

    private func processHostileContact(viewModel: GameSessionViewModel) {
        guard hostileContactCooldown <= 0 else { return }
        let p = player.position
        for er in enemyRuntimes {
            guard er.health > 0 else { continue }
            let e = er.entity.position
            let dx = p.x - e.x
            let dz = p.z - e.z
            if dx * dx + dz * dz < 0.5 * 0.5 {
                viewModel.applyDamageFromHostile(normalizedAmount: 0.09)
                hostileContactCooldown = 0.55
                viewModel.flashInteractMessage("Too close.")
                return
            }
        }
    }

    private func withinInteractReach(player: SIMD3<Float>, target: SIMD3<Float>) -> Bool {
        let offsetX = player.x - target.x
        let dz = abs(player.z - target.z)
        let dy = abs(player.y - target.y)
        let inFrontBand = offsetX <= 0.55 && offsetX >= -interactReachX
        return inFrontBand && dz < interactReachZ && dy < interactReachY
    }

    private func buildPlayer() {
        let h = Self.capsuleHeight
        let r = Self.capsuleRadius
        player.name = "Player"
        // Keep the physics body/collider on `player`; visuals live on a child rig.
        player.model = nil
        player.position = SIMD3<Float>(0, h / 2 + 0.15 * 0.70, 0)
        let shape = ShapeResource.generateCapsule(height: h, radius: r)
        player.components.set(CollisionComponent(shapes: [shape], mode: .default))
        player.components.set(PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: Self.playerMass),
            material: playerGroundMaterial,
            mode: .dynamic
        ))
        player.components.set(PhysicsMotionComponent())

        playerVisualRoot.name = "PlayerVisualRoot"
        if playerVisualRoot.parent == nil {
            player.addChild(playerVisualRoot)
        }

        let mat = SimpleMaterial(color: UIColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1), isMetallic: false)

        // Simple primitive-based humanoid proportions (tuned for current capsule height).
        let headRadius = r * 0.55
        let torsoW = r * 1.55
        let torsoH = h * 0.50
        let torsoD = r * 1.05

        let armRadius = r * 0.22
        let armLen = h * 0.40

        let legRadius = r * 0.24
        let legLen = h * 0.46

        // Torso (centered)
        playerTorso.name = "PlayerTorso"
        playerTorso.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(torsoW, torsoH, torsoD), cornerRadius: min(r * 0.35, torsoW * 0.25)),
            materials: [mat]
        )
        playerTorso.position = SIMD3<Float>(0, h * 0.60, 0)

        // Head (above torso)
        playerHead.name = "PlayerHead"
        playerHead.model = ModelComponent(mesh: .generateSphere(radius: headRadius), materials: [mat])
        playerHead.position = SIMD3<Float>(0, h * 0.60 + torsoH * 0.58 + headRadius * 1.15, 0)

        // Arms (rounded boxes; `MeshResource.generateCapsule` is not available on all SDKs)
        let armMesh = MeshResource.generateBox(
            size: SIMD3<Float>(armRadius * 2, armLen, armRadius * 2),
            cornerRadius: armRadius * 0.85
        )
        playerLeftArm.name = "PlayerLeftArm"
        playerLeftArm.model = ModelComponent(mesh: armMesh, materials: [mat])
        playerLeftArm.position = SIMD3<Float>(-(torsoW * 0.62), h * 0.60 + torsoH * 0.25, 0)

        playerRightArm.name = "PlayerRightArm"
        playerRightArm.model = ModelComponent(mesh: armMesh, materials: [mat])
        playerRightArm.position = SIMD3<Float>((torsoW * 0.62), h * 0.60 + torsoH * 0.25, 0)

        // Legs (rounded boxes)
        let legMesh = MeshResource.generateBox(
            size: SIMD3<Float>(legRadius * 2, legLen, legRadius * 2),
            cornerRadius: legRadius * 0.85
        )
        playerLeftLeg.name = "PlayerLeftLeg"
        playerLeftLeg.model = ModelComponent(mesh: legMesh, materials: [mat])
        playerLeftLeg.position = SIMD3<Float>(-(torsoW * 0.25), h * 0.26, 0)

        playerRightLeg.name = "PlayerRightLeg"
        playerRightLeg.model = ModelComponent(mesh: legMesh, materials: [mat])
        playerRightLeg.position = SIMD3<Float>((torsoW * 0.25), h * 0.26, 0)

        if playerTorso.parent == nil { playerVisualRoot.addChild(playerTorso) }
        if playerHead.parent == nil { playerVisualRoot.addChild(playerHead) }
        if playerLeftArm.parent == nil { playerVisualRoot.addChild(playerLeftArm) }
        if playerRightArm.parent == nil { playerVisualRoot.addChild(playerRightArm) }
        if playerLeftLeg.parent == nil { playerVisualRoot.addChild(playerLeftLeg) }
        if playerRightLeg.parent == nil { playerVisualRoot.addChild(playerRightLeg) }
    }

    private func dampLandingVerticalVelocityIfNeeded(grounded: Bool, climbing: Bool) {
        guard grounded, !climbing else { return }
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let vy = motion.linearVelocity.y
        guard abs(vy) > 0, abs(vy) < landingSettleVyThreshold else { return }
        player.applyLinearImpulse(SIMD3<Float>(0, -Self.playerMass * vy, 0), relativeTo: nil)
    }

    private func resetPlayerAtSpawn(_ center: SIMD3<Float>, viewModel: GameSessionViewModel) {
        let h = Self.capsuleHeight
        var p = center
        let minCenterY = h * 0.5 + 0.05
        if p.y < minCenterY { p.y = minCenterY }
        player.position = p
        player.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

        if var body = player.components[PhysicsBodyComponent.self] {
            body.isRotationLocked = (x: true, y: true, z: true)
            player.components.set(body)
        }

        if var motion = player.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            player.components.set(motion)
        }

        let eye = SIMD3<Float>(
            player.position.x + cameraRig.lookAheadX,
            player.position.y + cameraRig.heightY,
            player.position.z + cameraRig.offsetZ
        )
        cameraRig.reset(eye: eye, playerPosition: player.position)
        perspectiveCamera.transform = cameraRig.step(
            deltaTime: 1,
            playerPosition: player.position,
            horizontalVelocity: 0,
            facingSign: viewModel.facingSign
        )
    }

    private func applyMovement(viewModel: GameSessionViewModel, deltaTime: Float) {
        let runSpeed: Float = 4.35
        let accel: Float = 18
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity
        let targetVx = viewModel.horizontalInput * runSpeed
        let t = min(1, accel * deltaTime)
        let deltaVx = (targetVx - v.x) * t
        player.applyLinearImpulse(
            SIMD3<Float>(Self.playerMass * deltaVx, 0, 0),
            relativeTo: nil
        )
    }

    private func applyCorridorDepthMovement(viewModel: GameSessionViewModel, deltaTime: Float) {
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity
        let targetVz = viewModel.verticalInput * depthRunSpeed
        let t = min(1, depthAccel * deltaTime)
        let deltaVz = (targetVz - v.z) * t
        player.applyLinearImpulse(
            SIMD3<Float>(0, 0, Self.playerMass * deltaVz),
            relativeTo: nil
        )

        var p = player.position
        let zMin = -corridorHalfWidth
        let zMax = corridorHalfWidth
        let clamped = min(zMax, max(zMin, p.z))
        if clamped != p.z {
            p.z = clamped
            player.position = p
            if var m = player.components[PhysicsMotionComponent.self] {
                var vel = m.linearVelocity
                if (clamped <= zMin && vel.z < 0) || (clamped >= zMax && vel.z > 0) {
                    vel.z = 0
                }
                m.linearVelocity = vel
                player.components.set(m)
            }
        }
    }

    private func applyClimbingMovement(viewModel: GameSessionViewModel, deltaTime: Float) {
        let climbSpeed: Float = 3.35
        let slideDown: Float = viewModel.verticalInput == 0 ? -0.95 : 0
        let targetVy = viewModel.verticalInput * climbSpeed + slideDown
        let targetVx = viewModel.horizontalInput * 2.1

        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity
        let t = min(1, 14 * deltaTime)
        let deltaVx = (targetVx - v.x) * t
        let deltaVy = targetVy - v.y
        let deltaVz = (0 - v.z) * t

        player.applyLinearImpulse(
            SIMD3<Float>(
                Self.playerMass * deltaVx,
                Self.playerMass * deltaVy,
                Self.playerMass * deltaVz
            ),
            relativeTo: nil
        )

        let ladderX: Float = 4
        var p = player.position
        p.x += (ladderX - p.x) * min(1, 6 * deltaTime)
        p.z += (0 - p.z) * min(1, 10 * deltaTime)
        player.position = p
    }

    private func computeGrounded() -> Bool {
        guard let scene = player.scene else { return false }

        let h = Self.capsuleHeight
        let footY = player.position.y - h * 0.5
        // Start just above the foot to avoid self-intersection; a bit higher helps when the capsule sinks slightly into the floor.
        let origin = SIMD3<Float>(player.position.x, footY + 0.09, player.position.z)
        let direction = SIMD3<Float>(0, -1, 0)
        // `.nearest` returns only one hit; when the origin is inside the player capsule, that hit is the player,
        // so skipping it leaves no ground. `.all` collects hits along the ray so we can skip self and still hit the floor.
        let hits = scene.raycast(
            origin: origin,
            direction: direction,
            length: 0.95,
            query: .all,
            mask: .all,
            relativeTo: nil
        )

        let sorted = hits.sorted { $0.distance < $1.distance }
        let up = SIMD3<Float>(0, 1, 0)
        for hit in sorted {
            if isUnderPlayer(hit.entity) { continue }
            let n = hit.normal
            let upwardness = max(simd_dot(n, up), simd_dot(-n, up))
            // Slightly looser than a pure floor (0.28) so shallow contacts still read as ground after physics jitter.
            if upwardness > 0.22, hit.distance <= 0.88 {
                return true
            }
        }
        return false
    }

    private func isUnderPlayer(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let c = current {
            if c === player { return true }
            current = c.parent
        }
        return false
    }

    private func updateInteractPrompt(viewModel: GameSessionViewModel) {
        viewModel.nearWorkstationId = nil

        if let ws = nearestWorkstationInRange(), workstationProp.isEnabled {
            viewModel.nearWorkstationId = ws.id
            viewModel.interactPrompt = ws.interactPrompt
            return
        }

        if let trip = loadedChapter?.tripwire, !tripwireArmed,
           viewModel.countItem("item.tripwire_kit") > 0,
           withinInteractReach(player: player.position, target: trip.armAnchorPosition.simd) {
            viewModel.interactPrompt = trip.interactPrompt
            return
        }

        guard let beat = loadedChapter?.storyBeat, interactProp.isEnabled else {
            viewModel.interactPrompt = ""
            return
        }
        if withinInteractReach(player: player.position, target: beat.worldPosition.simd) {
            viewModel.interactPrompt = beat.interactPrompt
        } else {
            viewModel.interactPrompt = ""
        }
    }

    private func nearestWorkstationInRange() -> CraftingWorkstationConfig? {
        let p = player.position
        for ws in loadedWorkstations {
            if withinInteractReach(player: p, target: ws.worldPosition.simd) {
                return ws
            }
        }
        return nil
    }

    private func applyJumpIfNeeded(viewModel: GameSessionViewModel, climbing: Bool, grounded: Bool) {
        guard viewModel.jumpRequested else { return }
        viewModel.jumpRequested = false

        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity

        if climbing {
            let deltaVy = max(0, 3.7 - v.y)
            player.applyLinearImpulse(
                SIMD3<Float>(Self.playerMass * 2, Self.playerMass * deltaVy, 0),
                relativeTo: nil
            )
            return
        }

        guard grounded else { return }
        // Ignore small upward bounce so jump still fires when settling on the ground.
        if v.y > 0.32 { return }

        let deltaVy = 5.4 - v.y
        player.applyLinearImpulse(SIMD3<Float>(0, Self.playerMass * deltaVy, 0), relativeTo: nil)
    }

    private func processInteract(viewModel: GameSessionViewModel) {
        guard viewModel.interactRequested else { return }
        viewModel.interactRequested = false
        guard !viewModel.interactPrompt.isEmpty else { return }

        if nearestWorkstationInRange() != nil, workstationProp.isEnabled {
            viewModel.showCraftingSheet = true
            return
        }

        if let trip = loadedChapter?.tripwire, !tripwireArmed,
           viewModel.countItem("item.tripwire_kit") > 0,
           withinInteractReach(player: player.position, target: trip.armAnchorPosition.simd),
           viewModel.interactPrompt == trip.interactPrompt {
            if viewModel.consumeOneItem(itemId: "item.tripwire_kit") {
                tripwireArmed = true
                tripwireVisual.isEnabled = true
                viewModel.flashInteractMessage("Tripwire rigged across the gap.")
            }
            return
        }

        guard let beat = loadedChapter?.storyBeat else { return }
        viewModel.flashInteractMessage(beat.interactMessage)
        viewModel.registerStoryBeatCompleted(beat.storyBeatId)

        let grantIds = beat.resolvedGrantItemIds().filter { ItemCatalog.definition(for: $0) != nil }
        guard !storyBeatRewardClaimed else { return }
        if grantIds.isEmpty {
            storyBeatRewardClaimed = true
            return
        }

        if viewModel.addItemsAtomicallyIfPossible(itemIds: grantIds) {
            storyBeatRewardClaimed = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                viewModel.flashInteractMessage("Supplies added to inventory.")
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                viewModel.flashInteractMessage("Inventory full — make room for supplies.")
            }
        }
    }

    private func processHazard(viewModel: GameSessionViewModel) {
        guard let region = hazardRegion, hazardStrip.isEnabled else { return }
        guard hazardCooldownRemaining <= 0 else { return }
        guard region.contains(player.position) else { return }

        hazardCooldownRemaining = 1.15
        viewModel.flashInteractMessage("Live bus bar on the floor — jump clear or use the ladder.")

        if let motion = player.components[PhysicsMotionComponent.self] {
            let v = motion.linearVelocity
            let deltaVy = max(0, 2.6 - v.y)
            player.applyLinearImpulse(SIMD3<Float>(Self.playerMass * (-4.2), Self.playerMass * deltaVy, 0), relativeTo: nil)
        }
    }

    private func processChapterCompletion(viewModel: GameSessionViewModel) {
        guard !completionLatch else { return }
        guard completionRegion.contains(player.position) else { return }
        completionLatch = true
        viewModel.notifyChapterCompleted()
    }
}
