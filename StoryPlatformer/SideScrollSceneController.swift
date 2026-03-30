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
    private let ground = ModelEntity()
    private let ladderVisual = ModelEntity()
    private let interactProp = ModelEntity()
    private let workstationProp = ModelEntity()
    private let hazardStrip = ModelEntity()
    private let completionMarker = ModelEntity()
    private let tripwireVisual = ModelEntity()
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

    private static let capsuleHeight: Float = 1.15
    private static let capsuleRadius: Float = 0.32

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
            buildPlayer()

            root.addChild(ground)
            root.addChild(ladderVisual)
            root.addChild(hazardStrip)
            root.addChild(completionMarker)
            root.addChild(tripwireVisual)
            root.addChild(interactProp)
            root.addChild(workstationProp)
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
        }

        lockPlayPlane(deltaTime: deltaTime)

        let grounded = computeGrounded()
        viewModel.isGrounded = grounded

        updateFacing(viewModel: viewModel)

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
            material: .default,
            mode: .static
        ))
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
        player.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(r * 2, h, r * 2), cornerRadius: r * 0.85),
            materials: [SimpleMaterial(color: UIColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1), isMetallic: false)]
        )
        player.position = SIMD3<Float>(0, h / 2 + 0.15, 0)
        let shape = ShapeResource.generateCapsule(height: h, radius: r)
        player.components.set(CollisionComponent(shapes: [shape], mode: .default))
        player.components.set(PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: 70),
            material: .default,
            mode: .dynamic
        ))
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
        let runSpeed: Float = 5
        var v = player.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        let targetVx = viewModel.horizontalInput * runSpeed
        let accel: Float = 18
        v.x += (targetVx - v.x) * min(1, accel * deltaTime)
        v.z *= max(0, 1 - 6 * deltaTime)

        if var motion = player.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(v.x, motion.linearVelocity.y, v.z)
            player.components.set(motion)
        }
    }

    private func applyClimbingMovement(viewModel: GameSessionViewModel, deltaTime: Float) {
        let climbSpeed: Float = 3.35
        let slideDown: Float = viewModel.verticalInput == 0 ? -0.95 : 0
        let vy = viewModel.verticalInput * climbSpeed + slideDown
        let targetVx = viewModel.horizontalInput * 2.1

        var v = player.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        v.x += (targetVx - v.x) * min(1, 14 * deltaTime)
        v.y = vy
        v.z += (0 - v.z) * min(1, 14 * deltaTime)

        if var motion = player.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(v.x, v.y, v.z)
            player.components.set(motion)
        }

        let ladderX: Float = 4
        var p = player.position
        p.x += (ladderX - p.x) * min(1, 6 * deltaTime)
        p.z += (0 - p.z) * min(1, 10 * deltaTime)
        player.position = p
    }

    private func lockPlayPlane(deltaTime: Float) {
        var v = player.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        v.z *= max(0, 1 - 8 * deltaTime)
        if var motion = player.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = SIMD3<Float>(v.x, v.y, v.z)
            player.components.set(motion)
        }

        if abs(player.position.z) > 0.06 {
            var p = player.position
            p.z *= max(0, 1 - 5 * deltaTime)
            player.position = p
        }
    }

    private func computeGrounded() -> Bool {
        guard let scene = player.scene else { return false }

        let h = Self.capsuleHeight
        let footY = player.position.y - h * 0.5
        let origin = SIMD3<Float>(player.position.x, footY + 0.08, player.position.z)
        let direction = SIMD3<Float>(0, -1, 0)
        let hits = scene.raycast(
            origin: origin,
            direction: direction,
            length: 0.52,
            query: .nearest,
            mask: .all,
            relativeTo: nil
        )

        for hit in hits {
            if isUnderPlayer(hit.entity) { continue }
            let n = hit.normal
            if simd_dot(n, SIMD3<Float>(0, 1, 0)) > 0.35 {
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

        guard var motion = player.components[PhysicsMotionComponent.self] else { return }

        if climbing {
            motion.linearVelocity.y = max(motion.linearVelocity.y, 4.4)
            motion.linearVelocity.x += 2.0
            player.components.set(motion)
            return
        }

        guard grounded else { return }
        if motion.linearVelocity.y > 0.35 { return }

        motion.linearVelocity.y = 6.2
        player.components.set(motion)
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

        if var motion = player.components[PhysicsMotionComponent.self] {
            motion.linearVelocity.x -= 4.2
            motion.linearVelocity.y = max(motion.linearVelocity.y, 2.6)
            player.components.set(motion)
        }
    }

    private func processChapterCompletion(viewModel: GameSessionViewModel) {
        guard !completionLatch else { return }
        guard completionRegion.contains(player.position) else { return }
        completionLatch = true
        viewModel.notifyChapterCompleted()
    }
}
