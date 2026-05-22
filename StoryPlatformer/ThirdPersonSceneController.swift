import os
import QuartzCore
import RealityKit
import simd
import UIKit

private struct AxisAlignedRegion {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    func contains(_ p: SIMD3<Float>) -> Bool {
        p.x >= min.x && p.x <= max.x &&
        p.y >= min.y && p.y <= max.y &&
        p.z >= min.z && p.z <= max.z
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

/// Owns RealityKit entities and physics for one loaded chapter in 3rd-person view.
@MainActor
final class ThirdPersonSceneController {
    private(set) var perspectiveCamera = PerspectiveCamera()

    private let signposter = OSSignposter(subsystem: "com.storyplatformer.app", category: "Gameplay")

    private let root = Entity()
    private let cameraAnchor = Entity()
    private let player = ModelEntity()
    private let playerVisualRoot    = Entity()
    private let playerTorso         = ModelEntity()
    private let playerHips          = ModelEntity()
    private let playerHead          = ModelEntity()
    private let playerFace          = ModelEntity()
    private let playerLeftShoulder  = Entity()
    private let playerRightShoulder = Entity()
    private let playerLeftArm       = ModelEntity()
    private let playerRightArm      = ModelEntity()
    private let playerLeftHip       = Entity()
    private let playerRightHip      = Entity()
    private let playerLeftLeg       = ModelEntity()
    private let playerRightLeg      = ModelEntity()
    private let ground = ModelEntity()
    private let interactProp = ModelEntity()
    private let workstationProp = ModelEntity()
    private let hazardVolumeMesh = ModelEntity()
    private let completionMarker = ModelEntity()
    private let tripwireVisual = ModelEntity()
    private let environmentRoot = Entity()

    private var cameraRig = ThirdPersonCameraRig()
    private var lastMediaTime: CFTimeInterval?
    private var sceneGraphBuilt = false
    private var attachedToScene = false

    /// Player facing direction in world XZ plane; drives camera and visual rig rotation.
    private var playerFacingVector: SIMD3<Float> = SIMD3(0, 0, -1)

    private var enemyRuntimes: [EnemyRuntime] = []
    private var tripwireArmed = false
    private var tripwireRegion: AxisAlignedRegion?
    private var meleeCooldownRemaining: Float = 0
    private var hostileContactCooldown: Float = 0

    private var locomotionPhase: Float = 0
    private var locomotionBlend: Float = 0

    // Combo attack state: 0=idle, 1=leftJab, 2=rightCross, 3=leftKick
    private var comboStep: Int = 0
    private var comboAnimTimer: Float = 0
    private var comboCanAdvance: Bool = false

    private var loadedChapter: ChapterConfig?
    private var loadedWorkstations: [CraftingWorkstationConfig] = []
    private var completionRegion = AxisAlignedRegion(
        min: SIMD3<Float>(-5, 0, -27),
        max: SIMD3<Float>(5, 5, -24)
    )
    private var completionLatch = false
    private var storyBeatRewardClaimed = false
    private var hazardRegion: AxisAlignedRegion?
    private var hazardCooldownRemaining: Float = 0

    private static let capsuleHeight: Float = 1.15 * 0.70
    private static let capsuleRadius: Float = 0.32 * 0.70
    private static let playerMass: Float = 70

    private lazy var playerGroundMaterial: PhysicsMaterialResource = {
        PhysicsMaterialResource.generate(friction: 0.95, restitution: 0)
    }()

    private let landingSettleVyThreshold: Float = 0.6 * 0.70

    /// Spherical reach radius for interact checks (meters, in XZ plane).
    private let interactReachXZ: Float = 2.2
    private let interactReachY: Float = 1.8

    func attachIfNeeded(
        insertRoot: (Entity) -> Void,
        viewModel: GameSessionViewModel,
        chapter: ChapterConfig
    ) {
        if !sceneGraphBuilt {
            buildGround()
            if chapter.id == "chapter.tutorial" {
                buildTutorialEnvironment()
            } else {
                buildFactoryEnvironment()
            }
            buildHazardMeshPlaceholder()
            buildCompletionMarkerPlaceholder()
            buildInteractProp()
            buildWorkstationProp()
            buildTripwireVisualPlaceholder()
            buildPlayer()

            root.addChild(ground)
            root.addChild(environmentRoot)
            root.addChild(hazardVolumeMesh)
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
            hazardVolumeMesh.isEnabled = true
        } else {
            hazardRegion = nil
            hazardVolumeMesh.isEnabled = false
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

        viewModel.isClimbing = false
        applyMovement(viewModel: viewModel, deltaTime: deltaTime)

        let grounded = computeGrounded()
        viewModel.isGrounded = grounded
        dampLandingVerticalVelocityIfNeeded(grounded: grounded)

        updatePlayerFacing(viewModel: viewModel)
        updatePlayerVisual(deltaTime: deltaTime, viewModel: viewModel)

        if hazardCooldownRemaining > 0 { hazardCooldownRemaining = max(0, hazardCooldownRemaining - deltaTime) }
        if meleeCooldownRemaining > 0  { meleeCooldownRemaining  = max(0, meleeCooldownRemaining  - deltaTime) }
        if hostileContactCooldown > 0  { hostileContactCooldown  = max(0, hostileContactCooldown  - deltaTime) }
        updateComboAnimation(deltaTime: deltaTime)

        processHazard(viewModel: viewModel)
        updateEnemyPatrol(deltaTime: deltaTime)
        processTripwireTrigger(viewModel: viewModel)
        updateInteractPrompt(viewModel: viewModel)
        applyJumpIfNeeded(viewModel: viewModel, grounded: grounded)
        processMeleeAttack(viewModel: viewModel, grounded: grounded)
        processHostileContact(viewModel: viewModel)
        processInteract(viewModel: viewModel)
        processChapterCompletion(viewModel: viewModel)

        perspectiveCamera.transform = cameraRig.step(
            deltaTime: deltaTime,
            playerPosition: player.position,
            playerFacing: playerFacingVector
        )
    }

    // MARK: - Scene building

    private func buildGround() {
        // Near-black factory floor — gives neon accents something dark to pop against.
        let size = SIMD3<Float>(32, 0.25, 56)
        ground.model = ModelComponent(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1), isMetallic: true)]
        )
        ground.position = SIMD3<Float>(0, -0.125, -27)
        ground.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        ground.components.set(PhysicsBodyComponent(
            massProperties: .default,
            material: playerGroundMaterial,
            mode: .static
        ))
    }

    // MARK: Factory level — Futuristic Neo-Tokyo Drone Factory
    //
    // Layout (player faces -Z from spawn at origin):
    //   Z=0      →  Entry / staging area
    //   Z=-8     →  Factory floor split: LEFT safe path vs CENTER drone zone vs RIGHT alt path
    //   Z=-30    →  Security gate chokepoint (both paths reconverge)
    //   Z=-36    →  Server room corridor
    //   Z=-50    →  Exit / completion trigger
    //
    // Neon color code:  BLUE = safe  |  RED = danger / drone zone  |  GREEN = exit direction

    private func buildFactoryEnvironment() {
        environmentRoot.name = "DroneFactory"

        // Colors
        let darkMetal  = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        let crate      = UIColor(red: 0.16, green: 0.20, blue: 0.24, alpha: 1)
        let machinery  = UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1)
        let neonBlue   = UIColor(red: 0.00, green: 0.55, blue: 1.00, alpha: 1)  // safe path
        let neonRed    = UIColor(red: 1.00, green: 0.10, blue: 0.08, alpha: 1)  // danger
        let neonGreen  = UIColor(red: 0.00, green: 1.00, blue: 0.35, alpha: 1)  // exit
        let neonOrange = UIColor(red: 1.00, green: 0.50, blue: 0.00, alpha: 1)  // interact

        // ── helpers ──────────────────────────────────────────────────────────
        // Solid block: has collision + static physics. Bottom of block sits on Y=0.
        func solid(name: String, size: SIMD3<Float>, x: Float, z: Float, color: UIColor,
                   metallic: Bool = false) {
            let ent = ModelEntity()
            ent.name = name
            ent.model = ModelComponent(
                mesh: .generateBox(size: size, cornerRadius: 0.05),
                materials: [SimpleMaterial(color: color, isMetallic: metallic)]
            )
            ent.position = SIMD3(x, size.y * 0.5, z)
            ent.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            ent.components.set(PhysicsBodyComponent(massProperties: .default,
                                                    material: playerGroundMaterial, mode: .static))
            environmentRoot.addChild(ent)
        }

        // Decor strip: visual only, no collision. y = exact world Y of center.
        func strip(name: String, size: SIMD3<Float>, x: Float, y: Float, z: Float, color: UIColor) {
            let ent = ModelEntity()
            ent.name = name
            ent.model = ModelComponent(
                mesh: .generateBox(size: size),
                materials: [SimpleMaterial(color: color, isMetallic: true)]
            )
            ent.position = SIMD3(x, y, z)
            environmentRoot.addChild(ent)
        }

        // ── Outer factory shell ───────────────────────────────────────────────
        solid(name: "Wall.L",    size: SIMD3(0.5, 5, 56), x: -14,  z: -27, color: darkMetal)
        solid(name: "Wall.R",    size: SIMD3(0.5, 5, 56), x:  14,  z: -27, color: darkMetal)
        solid(name: "Wall.Back", size: SIMD3(28,  5, 0.5), x: 0,   z: -50, color: darkMetal)
        // No front wall — player enters from Z=0 side.

        // Neon trim on outer left wall (blue = safety side)
        strip(name: "Trim.WallL", size: SIMD3(0.08, 0.14, 52), x: -13.7, y: 1.5, z: -27, color: neonBlue)
        // Neon trim on outer right wall (orange — alternate, less safe)
        strip(name: "Trim.WallR", size: SIMD3(0.08, 0.14, 52), x:  13.7, y: 1.5, z: -27, color: neonOrange)

        // ── Section 1: Entry / staging (Z=0 to -8) ───────────────────────────
        // Four entry pillars frame the factory entrance.
        solid(name: "Pillar.EL",  size: SIMD3(0.8, 4.5, 0.8), x: -5, z: -3,  color: darkMetal, metallic: true)
        solid(name: "Pillar.ER",  size: SIMD3(0.8, 4.5, 0.8), x:  5, z: -3,  color: darkMetal, metallic: true)
        solid(name: "Pillar.EL2", size: SIMD3(0.8, 4.5, 0.8), x: -5, z: -7,  color: darkMetal, metallic: true)
        solid(name: "Pillar.ER2", size: SIMD3(0.8, 4.5, 0.8), x:  5, z: -7,  color: darkMetal, metallic: true)

        // Neon blue cap on left entry pillars → signals the safe left route
        strip(name: "Cap.PillarEL",  size: SIMD3(0.82, 0.12, 0.82), x: -5, y: 4.56, z: -3, color: neonBlue)
        strip(name: "Cap.PillarEL2", size: SIMD3(0.82, 0.12, 0.82), x: -5, y: 4.56, z: -7, color: neonBlue)
        // Neon red cap on right entry pillars → signals the risky center/right
        strip(name: "Cap.PillarER",  size: SIMD3(0.82, 0.12, 0.82), x:  5, y: 4.56, z: -3, color: neonRed)
        strip(name: "Cap.PillarER2", size: SIMD3(0.82, 0.12, 0.82), x:  5, y: 4.56, z: -7, color: neonRed)

        // Cover crates in entry zone
        solid(name: "Crate.E1", size: SIMD3(1.8, 1.4, 1.4), x: -9, z: -5, color: crate)
        solid(name: "Crate.E2", size: SIMD3(2.2, 1.6, 1.4), x:  8, z: -6, color: crate)

        // ── Section 2: Factory floor, LEFT SAFE PATH (X=-13 to -5, Z=-8 to -30) ─
        // Large machinery blocks form a wall on the right edge of the left path,
        // shielding the player from the drone zone.
        solid(name: "Mach.LA", size: SIMD3(4, 3.5, 5), x: -9, z: -13, color: machinery, metallic: true)
        solid(name: "Mach.LB", size: SIMD3(4, 3.5, 6), x: -9, z: -23, color: machinery, metallic: true)
        // Blue neon edge strips on those machinery blocks (facing the player's path)
        strip(name: "Edge.MachLA", size: SIMD3(0.08, 3.5, 5.1), x: -6.95, y: 1.75, z: -13, color: neonBlue)
        strip(name: "Edge.MachLB", size: SIMD3(0.08, 3.5, 6.1), x: -6.95, y: 1.75, z: -23, color: neonBlue)

        // Cover crates along left path
        solid(name: "Crate.L1", size: SIMD3(1.8, 1.4, 1.4), x: -7, z: -10, color: crate)
        solid(name: "Crate.L2", size: SIMD3(1.8, 1.4, 1.6), x: -7, z: -18, color: crate)
        solid(name: "Crate.L3", size: SIMD3(2.2, 1.6, 1.6), x: -7, z: -27, color: crate)

        // Blue floor guidance strip on the safe left path
        strip(name: "Floor.SafeL", size: SIMD3(0.3, 0.05, 22), x: -11, y: 0.03, z: -19, color: neonBlue)

        // ── Section 2: Factory floor, CENTER DRONE ZONE (X=-4.5 to 4.5, Z=-8 to -30) ─
        // Open, red-lit, patrolled. Conveyors and exposed sightlines.
        // Raised conveyor platform (thin, just enough to trip up the player visually)
        solid(name: "Conveyor.Plat", size: SIMD3(8, 0.14, 20), x: 0, z: -19, color: darkMetal, metallic: true)
        // Red neon edge trim on conveyor
        strip(name: "Edge.ConvL", size: SIMD3(0.12, 0.12, 20.2), x: -4, y: 0.2, z: -19, color: neonRed)
        strip(name: "Edge.ConvR", size: SIMD3(0.12, 0.12, 20.2), x:  4, y: 0.2, z: -19, color: neonRed)
        // Red floor glow in center lane
        strip(name: "Floor.Danger", size: SIMD3(7, 0.05, 19.5), x: 0, y: 0.02, z: -19, color: neonRed)
        // Lone cover crate in center (too exposed to be safe — but it's there)
        solid(name: "Crate.C1", size: SIMD3(1.8, 1.4, 1.4), x: 1, z: -16, color: crate)

        // Narrow chokepoint pillars that force players to pick a side
        solid(name: "Pillar.DivL", size: SIMD3(0.8, 4, 0.8), x: -4, z: -9,  color: darkMetal, metallic: true)
        solid(name: "Pillar.DivR", size: SIMD3(0.8, 4, 0.8), x:  4, z: -9,  color: darkMetal, metallic: true)
        solid(name: "Pillar.MidL", size: SIMD3(0.8, 4, 0.8), x: -4, z: -20, color: darkMetal, metallic: true)
        solid(name: "Pillar.MidR", size: SIMD3(0.8, 4, 0.8), x:  4, z: -20, color: darkMetal, metallic: true)

        // ── Section 2: Factory floor, RIGHT ALT PATH (X=5 to 13, Z=-8 to -30) ─
        // Mirrors left path but without the safety neon — still has cover, still faster than left.
        solid(name: "Mach.RA", size: SIMD3(4, 3.5, 4), x: 9, z: -11, color: machinery, metallic: true)
        solid(name: "Mach.RB", size: SIMD3(4, 3.5, 5), x: 9, z: -21, color: machinery, metallic: true)

        solid(name: "Crate.R1", size: SIMD3(1.8, 1.4, 1.4), x: 7, z: -9,  color: crate)
        solid(name: "Crate.R2", size: SIMD3(1.8, 1.4, 1.6), x: 7, z: -16, color: crate)
        solid(name: "Crate.R3", size: SIMD3(2.2, 1.6, 1.6), x: 7, z: -26, color: crate)

        // ── Section 3: Security gate chokepoint (Z=-30 to -36) ───────────────
        // All three paths funnel through here. Gate is visual; no blocking geometry across full width.
        let gateColor = UIColor(red: 0.14, green: 0.14, blue: 0.18, alpha: 1)
        solid(name: "Gate.PostL", size: SIMD3(1.2, 5, 1.2), x: -6.5, z: -31, color: gateColor, metallic: true)
        solid(name: "Gate.PostR", size: SIMD3(1.2, 5, 1.2), x:  6.5, z: -31, color: gateColor, metallic: true)
        // Gate crossbar visual (no physics)
        strip(name: "Gate.Bar",  size: SIMD3(13.2, 0.6, 0.6), x: 0, y: 4.7, z: -31, color: neonRed)
        strip(name: "Gate.Trim", size: SIMD3(13.4, 0.14, 0.9), x: 0, y: 4.4, z: -31, color: neonRed)

        // Cover blocks either side of the gate — gives players a landing spot after converging
        solid(name: "Cover.GL", size: SIMD3(2.5, 1.5, 2.5), x: -4, z: -33, color: crate)
        solid(name: "Cover.GR", size: SIMD3(2.5, 1.5, 2.5), x:  4, z: -33, color: crate)

        // Security terminal (interact prop will be placed here by chapter config)
        // Neon orange column hints at interactable
        solid(name: "Terminal.Base", size: SIMD3(0.9, 0.9, 0.9), x: -7, z: -34.5, color: darkMetal, metallic: true)
        strip(name: "Terminal.Glow", size: SIMD3(0.95, 0.12, 0.95), x: -7, y: 0.96, z: -34.5, color: neonOrange)

        // ── Section 4: Server room corridor (Z=-36 to -50) ───────────────────
        // Narrower — pipe barriers close in the corridor to Z ≈ ±6m.
        solid(name: "Pipe.L1", size: SIMD3(0.6, 3.2, 12), x: -7, z: -42, color: machinery, metallic: true)
        solid(name: "Pipe.R1", size: SIMD3(0.6, 3.2, 12), x:  7, z: -42, color: machinery, metallic: true)
        strip(name: "Pipe.GlowL", size: SIMD3(0.14, 3.2, 12.1), x: -6.65, y: 1.6, z: -42, color: neonBlue)
        strip(name: "Pipe.GlowR", size: SIMD3(0.14, 3.2, 12.1), x:  6.65, y: 1.6, z: -42, color: neonBlue)

        solid(name: "Crate.F1", size: SIMD3(2, 1.5, 2), x: -3.5, z: -39, color: crate)
        solid(name: "Crate.F2", size: SIMD3(2, 1.5, 2), x:  3.5, z: -44, color: crate)

        // Green floor arrows leading to server room exit
        strip(name: "Floor.ExitA", size: SIMD3(2.5, 0.05, 1), x: 0, y: 0.03, z: -38, color: neonGreen)
        strip(name: "Floor.ExitB", size: SIMD3(2.5, 0.05, 1), x: 0, y: 0.03, z: -41, color: neonGreen)
        strip(name: "Floor.ExitC", size: SIMD3(2.5, 0.05, 1), x: 0, y: 0.03, z: -44, color: neonGreen)

        // Server room door — large neon green frame signals the exit
        strip(name: "Door.Top",  size: SIMD3(6.5, 0.4, 0.5),  x: 0, y: 5.2, z: -49.7,  color: neonGreen)
        strip(name: "Door.L",    size: SIMD3(0.4, 5.5, 0.5),   x: -3.2, y: 2.75, z: -49.7, color: neonGreen)
        strip(name: "Door.R",    size: SIMD3(0.4, 5.5, 0.5),   x:  3.2, y: 2.75, z: -49.7, color: neonGreen)
        // Dark door fill (back wall cutout visual)
        strip(name: "Door.Fill", size: SIMD3(6.0, 5.0, 0.3),   x: 0, y: 2.5, z: -49.75,
              color: UIColor(red: 0, green: 0.25, blue: 0.12, alpha: 1))
    }

    // MARK: Tutorial level — Training Yard
    //
    // A calm, mostly-flat course built to show off fluid movement:
    //   Z=0    →  Open plaza: feel acceleration, walk vs sprint, free turning
    //   Z=-12  →  Slalom pillars: weave to feel responsive turning
    //   Z=-25  →  Speed lane: open straight to reach top speed and stop clean
    //   Z=-34  →  Live-wire gate: jump the red hazard strip
    //   Z=-41  →  Supply cache: interact beat (grants go-bag)
    //   Z=-49  →  Green exit door: completion trigger
    //
    // Color code: GREEN = path / go  |  CYAN = guide / go around  |  RED = hazard  |  AMBER = interact
    private func buildTutorialEnvironment() {
        environmentRoot.name = "TrainingYard"

        let wall      = UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1)
        let pillarCol = UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
        let cyan      = UIColor(red: 0.00, green: 0.70, blue: 1.00, alpha: 1)
        let green     = UIColor(red: 0.00, green: 1.00, blue: 0.45, alpha: 1)
        let amber     = UIColor(red: 1.00, green: 0.62, blue: 0.00, alpha: 1)
        let red       = UIColor(red: 1.00, green: 0.12, blue: 0.08, alpha: 1)

        // Solid block: collision + static physics, bottom resting on Y=0.
        func solid(_ name: String, _ size: SIMD3<Float>, _ x: Float, _ z: Float,
                   _ color: UIColor, metallic: Bool = false) {
            let ent = ModelEntity()
            ent.name = name
            ent.model = ModelComponent(
                mesh: .generateBox(size: size, cornerRadius: 0.06),
                materials: [SimpleMaterial(color: color, isMetallic: metallic)]
            )
            ent.position = SIMD3(x, size.y * 0.5, z)
            ent.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            ent.components.set(PhysicsBodyComponent(massProperties: .default,
                                                    material: playerGroundMaterial, mode: .static))
            environmentRoot.addChild(ent)
        }
        // Decor strip: visual only, no collision. y = exact world Y of center.
        func strip(_ name: String, _ size: SIMD3<Float>, _ x: Float, _ y: Float, _ z: Float, _ color: UIColor) {
            let ent = ModelEntity()
            ent.name = name
            ent.model = ModelComponent(
                mesh: .generateBox(size: size),
                materials: [SimpleMaterial(color: color, isMetallic: true)]
            )
            ent.position = SIMD3(x, y, z)
            environmentRoot.addChild(ent)
        }

        // ── Outer bounds: keep the yard open but contained ────────────────────
        solid("Wall.L",    SIMD3(0.5, 3, 52), -9, -25, wall)
        solid("Wall.R",    SIMD3(0.5, 3, 52),  9, -25, wall)
        solid("Wall.Back", SIMD3(18, 3, 0.5),  0, -50, wall)
        strip("Trim.L", SIMD3(0.08, 0.12, 50), -8.72, 1.2, -25, cyan)
        strip("Trim.R", SIMD3(0.08, 0.12, 50),  8.72, 1.2, -25, cyan)

        // ── Center green guide line from plaza to exit ────────────────────────
        for (i, z) in stride(from: Float(-3), through: Float(-46), by: -3).enumerated() {
            strip("Guide.\(i)", SIMD3(0.35, 0.04, 1.2), 0, 0.03, z, green)
        }

        // ── Plaza (z 0..-9): open warm-up, two framing posts ──────────────────
        solid("Post.L", SIMD3(0.6, 2.4, 0.6), -6, -4, pillarCol, metallic: true)
        solid("Post.R", SIMD3(0.6, 2.4, 0.6),  6, -4, pillarCol, metallic: true)
        strip("Cap.PostL", SIMD3(0.64, 0.10, 0.64), -6, 2.45, -4, cyan)
        strip("Cap.PostR", SIMD3(0.64, 0.10, 0.64),  6, 2.45, -4, cyan)

        // ── Slalom (z -12..-24): weave to feel the responsive turning ─────────
        let slalom: [(Float, Float)] = [(-2.6, -12), (2.6, -16), (-2.6, -20), (2.6, -24)]
        for (i, p) in slalom.enumerated() {
            solid("Slalom.\(i)", SIMD3(1.0, 2.6, 1.0), p.0, p.1, pillarCol, metallic: true)
            strip("SlalomCap.\(i)", SIMD3(1.05, 0.10, 1.05), p.0, 2.62, p.1, cyan)
        }

        // ── Live-wire gate (z ≈ -34.5): jump the red hazard strip ─────────────
        // Hazard volume + damage are driven by ChapterConfig.hazardVolume.
        solid("Wire.PostL", SIMD3(0.5, 2.2, 0.5), -3.6, -34.5, pillarCol, metallic: true)
        solid("Wire.PostR", SIMD3(0.5, 2.2, 0.5),  3.6, -34.5, pillarCol, metallic: true)
        strip("Wire.Bar",    SIMD3(7.2, 0.10, 0.10), 0, 1.4, -34.5, red)   // visual wires (no collision)
        strip("Wire.Launch", SIMD3(5.0, 0.04, 0.30), 0, 0.03, -32.6, green)
        strip("Wire.Land",   SIMD3(5.0, 0.04, 0.30), 0, 0.03, -36.4, green)

        // ── Supply cache pad (z -41): story-beat terminal placed here by config ─
        strip("Cache.Pad", SIMD3(2.6, 0.04, 2.6), 0, 0.02, -41, amber)

        // ── Exit door (z -49.7): green frame = goal ───────────────────────────
        strip("Door.Top",  SIMD3(6.5, 0.4, 0.5),  0,    3.0, -49.7, green)
        strip("Door.L",    SIMD3(0.4, 3.2, 0.5), -3.2,  1.6, -49.7, green)
        strip("Door.R",    SIMD3(0.4, 3.2, 0.5),  3.2,  1.6, -49.7, green)
        strip("Door.Fill", SIMD3(6.0, 3.0, 0.3),  0,    1.5, -49.75,
              UIColor(red: 0, green: 0.22, blue: 0.12, alpha: 1))
    }

    private func buildHazardMeshPlaceholder() {
        hazardVolumeMesh.name = "hazard.zone"
        hazardVolumeMesh.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(1, 0.06, 1)),
            materials: [SimpleMaterial(color: UIColor(red: 1, green: 0.10, blue: 0.08, alpha: 1), isMetallic: true)]
        )
        hazardVolumeMesh.isEnabled = false
    }

    private func configureHazardVisual(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        let center = (boundsMin + boundsMax) * 0.5
        // Render as a thin floor glow strip rather than a tall box.
        hazardVolumeMesh.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(
                Swift.max(ext.x, 0.1),
                0.06,
                Swift.max(ext.z, 0.1)
            )),
            materials: [SimpleMaterial(color: UIColor(red: 1, green: 0.10, blue: 0.08, alpha: 1), isMetallic: true)]
        )
        hazardVolumeMesh.position = SIMD3(center.x, 0.04, center.z)
    }

    private func buildCompletionMarkerPlaceholder() {
        completionMarker.name = "trigger.completion_visual"
        completionMarker.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(1, 1, 1)),
            materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.72, blue: 0.38, alpha: 0.18), isMetallic: false)]
        )
    }

    private func configureCompletionMarker(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        completionMarker.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(
                Swift.max(ext.x, 0.1),
                Swift.max(ext.y, 0.1),
                Swift.max(ext.z, 0.1)
            )),
            materials: [SimpleMaterial(color: UIColor(red: 0.12, green: 0.65, blue: 0.4, alpha: 0.15), isMetallic: false)]
        )
        completionMarker.position = (boundsMin + boundsMax) * 0.5
    }

    private func buildInteractProp() {
        // Cyberpunk security terminal: small pedestal with a cyan-blue glow top.
        interactProp.name = "Interactable.story_beat"
        let base = ModelEntity()
        base.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.55, 0.85, 0.40), cornerRadius: 0.05),
            materials: [SimpleMaterial(color: UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1), isMetallic: true)]
        )
        let screen = ModelEntity()
        screen.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.50, 0.08, 0.35)),
            materials: [SimpleMaterial(color: UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 1), isMetallic: true)]
        )
        screen.position = SIMD3(0, 0.465, 0)
        base.addChild(screen)
        interactProp.addChild(base)
    }

    private func buildWorkstationProp() {
        workstationProp.name = "Interactable.workbench"
        let base = ModelEntity()
        base.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.90, 0.60, 0.50), cornerRadius: 0.05),
            materials: [SimpleMaterial(color: UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1), isMetallic: true)]
        )
        let glowTop = ModelEntity()
        glowTop.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.86, 0.08, 0.46)),
            materials: [SimpleMaterial(color: UIColor(red: 1.0, green: 0.50, blue: 0.0, alpha: 1), isMetallic: true)]
        )
        glowTop.position = SIMD3(0, 0.34, 0)
        base.addChild(glowTop)
        workstationProp.addChild(base)
        workstationProp.isEnabled = false
    }

    private func buildTripwireVisualPlaceholder() {
        tripwireVisual.name = "trap.tripwire_visual"
        tripwireVisual.model = ModelComponent(
            mesh: .generateBox(size: SIMD3<Float>(0.28, 0.04, 0.04)),
            materials: [SimpleMaterial(color: UIColor(white: 0.25, alpha: 0.85), isMetallic: false)]
        )
        tripwireVisual.isEnabled = false
    }

    private func configureTripwireVisual(boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) {
        let ext = boundsMax - boundsMin
        let center = (boundsMin + boundsMax) * 0.5
        tripwireVisual.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(
                Swift.max(ext.x, 0.08),
                Swift.max(ext.y * 0.12, 0.04),
                Swift.max(ext.z, 0.08)
            )),
            materials: [SimpleMaterial(color: UIColor(white: 0.32, alpha: 0.55), isMetallic: false)]
        )
        tripwireVisual.position = center
    }

    private func buildPlayer() {
        let h = Self.capsuleHeight
        let r = Self.capsuleRadius
        player.name = "Player"
        player.model = nil
        player.position = SIMD3<Float>(0, h / 2 + 0.12, 0)
        let shape = ShapeResource.generateCapsule(height: h, radius: r)
        player.components.set(CollisionComponent(shapes: [shape], mode: .default))
        player.components.set(PhysicsBodyComponent(
            massProperties: .init(shape: shape, mass: Self.playerMass),
            material: playerGroundMaterial,
            mode: .dynamic
        ))
        player.components.set(PhysicsMotionComponent())

        playerVisualRoot.name = "PlayerVisualRoot"
        if playerVisualRoot.parent == nil { player.addChild(playerVisualRoot) }

        let H = Self.capsuleHeight

        // ── Materials — each maps to a future equippable gear slot ────────────
        let skin    = SimpleMaterial(color: UIColor(red: 0.86, green: 0.69, blue: 0.55, alpha: 1), roughness: 0.9, isMetallic: false)
        let shirt   = SimpleMaterial(color: UIColor(red: 0.21, green: 0.26, blue: 0.33, alpha: 1), roughness: 0.55, isMetallic: false) // torso + sleeves
        let pants   = SimpleMaterial(color: UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1), roughness: 0.7, isMetallic: false)   // legs
        let boots   = SimpleMaterial(color: UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1), roughness: 0.45, isMetallic: false)  // feet
        let feature = SimpleMaterial(color: UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1), roughness: 0.3, isMetallic: false)   // eyes / mouth

        // Mesh helpers — cylinders/spheres give organic limbs vs. stacked boxes.
        func cyl(_ height: Float, _ radius: Float, _ m: SimpleMaterial) -> ModelEntity {
            ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [m])
        }
        func sph(_ radius: Float, _ m: SimpleMaterial) -> ModelEntity {
            ModelEntity(mesh: .generateSphere(radius: radius), materials: [m])
        }
        func box(_ size: SIMD3<Float>, _ m: SimpleMaterial, corner: Float = 0.01) -> ModelEntity {
            ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [m])
        }

        // ── Torso: chest (shirt) tapering into pelvis (pants), flattened front-back ──
        playerTorso.name = "PlayerTorso"
        playerTorso.model = ModelComponent(mesh: .generateCylinder(height: H * 0.20, radius: H * 0.155), materials: [shirt])
        playerTorso.position = SIMD3(0, H * 0.105, 0)
        playerTorso.scale = SIMD3(1.05, 1, 0.72)        // shoulders wider than deep

        playerHips.name = "PlayerHips"
        playerHips.model = ModelComponent(mesh: .generateCylinder(height: H * 0.12, radius: H * 0.125), materials: [pants])
        playerHips.position = SIMD3(0, -H * 0.045, 0)
        playerHips.scale = SIMD3(1, 1, 0.74)

        // ── Neck + head ───────────────────────────────────────────────────────
        let neck = cyl(H * 0.08, H * 0.05, skin)
        neck.name = "Neck"
        neck.position = SIMD3(0, H * 0.245, 0)
        playerVisualRoot.addChild(neck)

        playerHead.name = "PlayerHead"
        playerHead.model = ModelComponent(mesh: .generateSphere(radius: H * 0.12), materials: [skin])
        playerHead.position = SIMD3(0, H * 0.355, 0)
        playerHead.scale = SIMD3(0.92, 1.0, 0.96)       // slightly narrowed, less ball-like

        // ── Face: eyes, nose, mouth on the front (−Z) of the head ─────────────
        let frontZ = -H * 0.12 * 0.99
        for sx in [Float(-1), Float(1)] {
            let eye = sph(H * 0.024, feature)
            eye.position = SIMD3(sx * H * 0.045, H * 0.025, frontZ)
            eye.scale = SIMD3(1, 1, 0.5)                // flatten onto the face
            playerHead.addChild(eye)
        }
        let nose = sph(H * 0.022, skin)
        nose.position = SIMD3(0, -H * 0.005, frontZ - H * 0.01)
        nose.scale = SIMD3(0.8, 1.0, 1.3)
        playerHead.addChild(nose)
        let mouth = box(SIMD3(H * 0.06, H * 0.014, H * 0.02), feature, corner: H * 0.005)
        mouth.position = SIMD3(0, -H * 0.05, frontZ)
        playerHead.addChild(mouth)

        // Head-gear mount (formerly the flat blue visor): masks / helmets attach
        // here later by setting `.model`. Empty + co-located with head for now.
        playerFace.name = "HeadGearMount"
        playerFace.model = nil
        playerFace.position = .zero

        // ── Arms: shirt sleeves, skin hands (glove slot), slight elbow bend ───
        let upperArmLen = H * 0.20, rUpper = H * 0.05
        let foreLen = H * 0.185, rFore = H * 0.04

        playerLeftShoulder.name  = "LeftShoulder"
        playerRightShoulder.name = "RightShoulder"
        playerLeftShoulder.position  = SIMD3(-H * 0.165, H * 0.20, 0)
        playerRightShoulder.position = SIMD3( H * 0.165, H * 0.20, 0)

        func buildArm(shoulder: Entity, upper: ModelEntity) {
            shoulder.addChild(sph(H * 0.062, shirt))    // deltoid at the joint
            upper.model = ModelComponent(mesh: .generateCylinder(height: upperArmLen, radius: rUpper), materials: [shirt])
            upper.position = SIMD3(0, -upperArmLen / 2, 0)

            let elbow = Entity()
            elbow.position = SIMD3(0, -upperArmLen / 2, 0)
            elbow.transform.rotation = simd_quatf(angle: 0.18, axis: SIMD3(1, 0, 0)) // relaxed forward bend
            upper.addChild(elbow)
            elbow.addChild(sph(H * 0.045, shirt))
            let fore = cyl(foreLen, rFore, shirt)
            fore.position = SIMD3(0, -foreLen / 2, 0)
            elbow.addChild(fore)
            let hand = box(SIMD3(H * 0.062, H * 0.075, H * 0.05), skin, corner: H * 0.02)
            hand.position = SIMD3(0, -foreLen - H * 0.03, 0)
            elbow.addChild(hand)
        }
        playerLeftArm.name  = "PlayerLeftArm"
        playerRightArm.name = "PlayerRightArm"
        buildArm(shoulder: playerLeftShoulder, upper: playerLeftArm)
        buildArm(shoulder: playerRightShoulder, upper: playerRightArm)

        // ── Legs: pants thigh+shin, boot feet ─────────────────────────────────
        let thighLen = H * 0.255, rThigh = H * 0.072
        let shinLen = H * 0.235, rShin = H * 0.055

        playerLeftHip.name  = "LeftHip"
        playerRightHip.name = "RightHip"
        playerLeftHip.position  = SIMD3(-H * 0.085, -H * 0.04, 0)
        playerRightHip.position = SIMD3( H * 0.085, -H * 0.04, 0)

        func buildLeg(hip: Entity, thigh: ModelEntity) {
            hip.addChild(sph(H * 0.07, pants))          // hip joint
            thigh.model = ModelComponent(mesh: .generateCylinder(height: thighLen, radius: rThigh), materials: [pants])
            thigh.position = SIMD3(0, -thighLen / 2, 0)

            let knee = Entity()
            knee.position = SIMD3(0, -thighLen / 2, 0)
            thigh.addChild(knee)
            knee.addChild(sph(H * 0.058, pants))
            let shin = cyl(shinLen, rShin, pants)
            shin.position = SIMD3(0, -shinLen / 2, 0)
            knee.addChild(shin)
            let foot = box(SIMD3(H * 0.085, H * 0.05, H * 0.17), boots, corner: H * 0.02)
            foot.position = SIMD3(0, -shinLen - H * 0.02, -H * 0.05) // toe forward (−Z)
            knee.addChild(foot)
        }
        playerLeftLeg.name  = "PlayerLeftLeg"
        playerRightLeg.name = "PlayerRightLeg"
        buildLeg(hip: playerLeftHip, thigh: playerLeftLeg)
        buildLeg(hip: playerRightHip, thigh: playerRightLeg)

        // ── Assemble onto the animated visual root ────────────────────────────
        playerVisualRoot.addChild(playerTorso)
        playerVisualRoot.addChild(playerHips)
        playerVisualRoot.addChild(playerHead)
        playerHead.addChild(playerFace)
        playerVisualRoot.addChild(playerLeftShoulder)
        playerVisualRoot.addChild(playerRightShoulder)
        playerLeftShoulder.addChild(playerLeftArm)
        playerRightShoulder.addChild(playerRightArm)
        playerVisualRoot.addChild(playerLeftHip)
        playerVisualRoot.addChild(playerRightHip)
        playerLeftHip.addChild(playerLeftLeg)
        playerRightHip.addChild(playerRightLeg)
    }

    // MARK: - Combat

    private func removeAllCombatEntities() {
        for er in enemyRuntimes { er.entity.removeFromParent() }
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

        for e in chapter.combatEnemies ?? [] { appendEnemy(from: e) }
    }

    private func appendEnemy(from config: CombatEnemyConfig) {
        let w: Float = 0.46
        let h: Float = 0.94
        let ent = ModelEntity()
        ent.name = "Hostile.\(config.id)"
        ent.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(w, h, w * 0.82)),
            materials: [SimpleMaterial(color: UIColor(red: 0.42, green: 0.20, blue: 0.16, alpha: 1), isMetallic: false)]
        )
        let base = config.worldPosition.simd
        ent.position = base
        enemyRuntimes.append(EnemyRuntime(
            configId: config.id,
            entity: ent,
            health: config.maxHealth,
            patrolMinX: base.x - config.patrolHalfWidth,
            patrolMaxX: base.x + config.patrolHalfWidth,
            velocitySign: 1,
            speed: config.moveSpeed
        ))
        root.addChild(ent)
    }

    // MARK: - Physics / movement

    private func applyMovement(viewModel: GameSessionViewModel, deltaTime: Float) {
        // Raw stick: x = strafe, y = forward (drag up = forward).
        var stick = SIMD2<Float>(viewModel.horizontalInput, -viewModel.verticalInput)
        var stickMag = simd_length(stick)

        // Radial dead-zone + smoothstep response curve: gentle pushes give fine
        // walking control, full pushes give full sprint without a twitchy mid-range.
        let deadZone: Float = 0.12
        if stickMag <= deadZone {
            stick = .zero
            stickMag = 0
        } else {
            let norm   = min(1, (stickMag - deadZone) / (1 - deadZone))
            let curved = norm * norm * (3 - 2 * norm)   // smoothstep
            stick = (stick / stickMag) * curved
            stickMag = curved
        }

        // Camera-relative move direction on the ground plane.
        let fwd = cameraRig.groundForward
        let rgt = cameraRig.groundRight
        var moveXZ = fwd * stick.y + rgt * stick.x
        let moveMag = simd_length(SIMD2(moveXZ.x, moveXZ.z))
        if moveMag > 1 { moveXZ /= moveMag }

        let runSpeed: Float = 4.6
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity

        // Target planar velocity scaled by how far the stick is pushed.
        let desiredX = moveXZ.x * runSpeed
        let desiredZ = moveXZ.z * runSpeed

        // Pick a response rate: weighty-but-quick on accelerate, snappier on a
        // hard direction change, crisp on release. Exponential => framerate-independent.
        let curSpeed     = simd_length(SIMD2(v.x, v.z))
        let desiredSpeed = simd_length(SIMD2(desiredX, desiredZ))
        let rate: Float
        if stickMag <= 0.001 {
            rate = 18                       // releasing — stop crisply
        } else if desiredSpeed < curSpeed {
            rate = 16                       // turning / easing down
        } else {
            rate = 13                       // accelerating
        }
        let t = 1 - exp(-rate * deltaTime)

        let dvX = (desiredX - v.x) * t
        let dvZ = (desiredZ - v.z) * t
        player.applyLinearImpulse(SIMD3(Self.playerMass * dvX, 0, Self.playerMass * dvZ), relativeTo: nil)

        // Rotate the player to face travel direction — quick but smooth.
        if moveMag > 0.1 {
            let target = SIMD3(moveXZ.x / moveMag, 0, moveXZ.z / moveMag)
            let faceT  = 1 - exp(-13 * deltaTime)
            let blended = playerFacingVector + (target - playerFacingVector) * faceT
            let bMag = simd_length(SIMD2(blended.x, blended.z))
            if bMag > 0.001 {
                playerFacingVector = SIMD3(blended.x / bMag, 0, blended.z / bMag)
            }
        }
    }

    private func dampLandingVerticalVelocityIfNeeded(grounded: Bool) {
        guard grounded else { return }
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let vy = motion.linearVelocity.y
        guard abs(vy) > 0, abs(vy) < landingSettleVyThreshold else { return }
        player.applyLinearImpulse(SIMD3<Float>(0, -Self.playerMass * vy, 0), relativeTo: nil)
    }

    private func resetPlayerAtSpawn(_ center: SIMD3<Float>, viewModel: GameSessionViewModel) {
        let h = Self.capsuleHeight
        var p = center
        if p.y < h * 0.5 + 0.05 { p.y = h * 0.5 + 0.05 }
        player.position = p
        player.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

        if var body = player.components[PhysicsBodyComponent.self] {
            body.isRotationLocked = (x: true, y: true, z: true)
            player.components.set(body)
        }
        if var mot = player.components[PhysicsMotionComponent.self] {
            mot.linearVelocity  = .zero
            mot.angularVelocity = .zero
            player.components.set(mot)
        }

        playerFacingVector = SIMD3(0, 0, -1)
        cameraRig = ThirdPersonCameraRig()
        cameraRig.reset(playerPosition: player.position)
        perspectiveCamera.transform = cameraRig.step(
            deltaTime: 1,
            playerPosition: player.position,
            playerFacing: playerFacingVector
        )
    }

    private func computeGrounded() -> Bool {
        guard let scene = player.scene else { return false }
        let h = Self.capsuleHeight
        let footY = player.position.y - h * 0.5
        let origin = SIMD3<Float>(player.position.x, footY + 0.09, player.position.z)
        let hits = scene.raycast(
            origin: origin,
            direction: SIMD3(0, -1, 0),
            length: 0.95,
            query: .all,
            mask: .all,
            relativeTo: nil
        )
        let up = SIMD3<Float>(0, 1, 0)
        for hit in hits.sorted(by: { $0.distance < $1.distance }) {
            if isUnderPlayer(hit.entity) { continue }
            let upward = max(simd_dot(hit.normal, up), simd_dot(-hit.normal, up))
            if upward > 0.22, hit.distance <= 0.88 { return true }
        }
        return false
    }

    private func isUnderPlayer(_ entity: Entity) -> Bool {
        var c: Entity? = entity
        while let cur = c { if cur === player { return true }; c = cur.parent }
        return false
    }

    private func applyJumpIfNeeded(viewModel: GameSessionViewModel, grounded: Bool) {
        guard viewModel.jumpRequested else { return }
        viewModel.jumpRequested = false
        guard grounded else { return }
        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        if motion.linearVelocity.y > 0.32 { return }
        let deltaVy = 5.4 - motion.linearVelocity.y
        player.applyLinearImpulse(SIMD3<Float>(0, Self.playerMass * deltaVy, 0), relativeTo: nil)
    }

    // MARK: - Facing / visual

    private func updatePlayerFacing(viewModel: GameSessionViewModel) {
        viewModel.facingSign = playerFacingVector.x >= 0 ? 1 : -1
    }

    private func updatePlayerVisualFacing(deltaTime: Float) {
        // Rotate visual root so humanoid faces playerFacingVector in world XZ.
        // angle=0 at facing (0,0,-1); atan2(x, -z) maps facing to Y-rotation angle.
        let angle = atan2(playerFacingVector.x, -playerFacingVector.z)
        let target = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        let blend = 1 - exp(-16 * deltaTime)   // framerate-independent turn
        playerVisualRoot.transform.rotation = simd_slerp(
            playerVisualRoot.transform.rotation,
            target,
            blend
        )
    }

    private func updatePlayerVisual(deltaTime: Float, viewModel: GameSessionViewModel) {
        updatePlayerVisualFacing(deltaTime: deltaTime)

        guard let motion = player.components[PhysicsMotionComponent.self] else { return }
        let v = motion.linearVelocity
        let planarSpeed = simd_length(SIMD2(v.x, v.z))

        // Locomotion blend: ramps up fast, ramps down slower.
        let speedDeadZone: Float = 0.15
        let speedFull: Float     = 2.1
        let targetBlend = min(1, max(0, (planarSpeed - speedDeadZone) / max(0.01, speedFull - speedDeadZone)))
        let blendResponse: Float = targetBlend > locomotionBlend ? 10.5 : 7.5
        locomotionBlend += (targetBlend - locomotionBlend) * min(1, blendResponse * deltaTime)

        let walk = min(1, planarSpeed / 4.6)
        let phaseRate = (1.4 + 1.9 * walk) * 2 * Float.pi
        locomotionPhase = fmod(locomotionPhase + phaseRate * deltaTime, 2 * .pi)

        let s = sin(locomotionPhase)

        // Subtle torso bob
        let h = Self.capsuleHeight
        let baseTorsoY = h * 0.105
        playerTorso.position.y = baseTorsoY + (0.025 * locomotionBlend) * abs(s)

        // Base locomotion angles driving shoulder/hip PIVOT entities so limbs
        // swing around the joint rather than their own center.
        // Sign convention: +X rotation = limb swings forward (toward face/-Z); −X = backward.
        // Natural gait: left arm and left leg are out of phase.
        let armAmp: Float = 0.70 * locomotionBlend
        let legAmp: Float = 0.90 * locomotionBlend

        var lShoulderAngle: Float =  armAmp * s
        var rShoulderAngle: Float = -armAmp * s
        var lHipAngle:      Float = -legAmp * s
        var rHipAngle:      Float =  legAmp * s

        // Combo override: replace relevant pivot angle with attack animation.
        if comboStep > 0 {
            let peakTimes:  [Int: Float] = [1: 0.07, 2: 0.07, 3: 0.11]
            let durations:  [Int: Float] = [1: 0.25, 2: 0.25, 3: 0.38]
            let maxAngles:  [Int: Float] = [1: 1.20, 2: 1.10, 3: 1.50]
            if let peak = peakTimes[comboStep],
               let dur  = durations[comboStep],
               let maxA = maxAngles[comboStep] {
                let t = comboAnimTimer
                let raw: Float = t < peak
                    ? t / peak
                    : 1.0 - (t - peak) / max(0.001, dur - peak)
                let curve = max(0, min(1, raw))
                let angle = maxA * curve
                switch comboStep {
                case 1: lShoulderAngle = angle       // left jab: left arm forward
                case 2: rShoulderAngle = angle       // right cross: right arm forward
                case 3: lHipAngle      = angle       // left kick: left leg forward
                default: break
                }
            }
        }

        let xAxis = SIMD3<Float>(1, 0, 0)
        playerLeftShoulder.transform.rotation  = simd_quatf(angle: lShoulderAngle, axis: xAxis)
        playerRightShoulder.transform.rotation = simd_quatf(angle: rShoulderAngle, axis: xAxis)
        playerLeftHip.transform.rotation       = simd_quatf(angle: lHipAngle,      axis: xAxis)
        playerRightHip.transform.rotation      = simd_quatf(angle: rHipAngle,      axis: xAxis)
    }

    // MARK: - Enemy / combat

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
            guard enemyRuntimes[i].health > 0,
                  region.contains(enemyRuntimes[i].entity.position) else { continue }
            let tripDamage: Float = 0.46
            enemyRuntimes[i].health -= tripDamage
            tripwireArmed = false
            tripwireVisual.isEnabled = false
            viewModel.flashInteractMessage(
                enemyRuntimes[i].health <= 0 ? "Tripwire — down." : "Tripwire — tangled."
            )
            if enemyRuntimes[i].health <= 0 { enemyRuntimes[i].entity.isEnabled = false }
            break
        }
    }

    private func processMeleeAttack(viewModel: GameSessionViewModel, grounded: Bool) {
        guard viewModel.attackRequested else { return }
        viewModel.attackRequested = false
        guard grounded else { return }

        if comboStep == 0 {
            guard meleeCooldownRemaining <= 0 else { return }
            comboStep = 1
            comboAnimTimer = 0
            comboCanAdvance = false
            applyMeleeDamage(step: 1, viewModel: viewModel)
        } else if comboCanAdvance && comboStep < 3 {
            comboStep += 1
            comboAnimTimer = 0
            comboCanAdvance = false
            applyMeleeDamage(step: comboStep, viewModel: viewModel)
        }
    }

    private func applyMeleeDamage(step: Int, viewModel: GameSessionViewModel) {
        let dmg = MeleeCombat.strikeDamage(equippedWeaponItemId: viewModel.equippedWeaponItemId)
        let p = player.position
        var hit = false
        for i in enemyRuntimes.indices {
            guard enemyRuntimes[i].health > 0 else { continue }
            guard enemyInMeleeArc(player: p, enemy: enemyRuntimes[i].entity.position) else { continue }
            enemyRuntimes[i].health -= dmg
            hit = true
            if enemyRuntimes[i].health <= 0 {
                enemyRuntimes[i].entity.isEnabled = false
                viewModel.flashInteractMessage("Hostile down.")
            } else {
                viewModel.flashInteractMessage(step == 1 ? "Jab!" : step == 2 ? "Cross!" : "Kick!")
            }
            break
        }
        if !hit {
            let miss = step == 1 ? "Jab." : step == 2 ? "Cross." : "Kick."
            viewModel.flashInteractMessage(miss)
        }
    }

    private func updateComboAnimation(deltaTime: Float) {
        guard comboStep > 0 else { return }
        comboAnimTimer += deltaTime

        let stepDuration: Float
        let windowStart: Float
        let windowEnd: Float
        switch comboStep {
        case 1: stepDuration = 0.25; windowStart = 0.08; windowEnd = 0.22
        case 2: stepDuration = 0.25; windowStart = 0.08; windowEnd = 0.22
        case 3: stepDuration = 0.38; windowStart = 0.12; windowEnd = 0.32
        default: comboStep = 0; comboAnimTimer = 0; return
        }

        comboCanAdvance = comboAnimTimer >= windowStart && comboAnimTimer <= windowEnd

        if comboAnimTimer >= stepDuration {
            comboStep = 0
            comboAnimTimer = 0
            comboCanAdvance = false
            meleeCooldownRemaining = 0.35
        }
    }

    private func enemyInMeleeArc(player: SIMD3<Float>, enemy: SIMD3<Float>) -> Bool {
        let delta = SIMD3(enemy.x - player.x, 0, enemy.z - player.z)
        let distXZ = simd_length(SIMD2(delta.x, delta.z))
        guard distXZ < 1.5, abs(enemy.y - player.y) < 0.9 else { return false }
        let dot = simd_dot(
            SIMD2(delta.x / distXZ, delta.z / distXZ),
            SIMD2(playerFacingVector.x, playerFacingVector.z)
        )
        return dot > 0.4
    }

    private func processHostileContact(viewModel: GameSessionViewModel) {
        guard hostileContactCooldown <= 0 else { return }
        let p = player.position
        for er in enemyRuntimes {
            guard er.health > 0 else { continue }
            let dx = p.x - er.entity.position.x
            let dz = p.z - er.entity.position.z
            if dx * dx + dz * dz < 0.5 * 0.5 {
                viewModel.applyDamageFromHostile(normalizedAmount: 0.09)
                hostileContactCooldown = 0.55
                viewModel.flashInteractMessage("Too close.")
                return
            }
        }
    }

    // MARK: - Interact

    private func withinInteractReach(player: SIMD3<Float>, target: SIMD3<Float>) -> Bool {
        let dx = player.x - target.x
        let dz = player.z - target.z
        return sqrt(dx * dx + dz * dz) < interactReachXZ && abs(player.y - target.y) < interactReachY
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
        viewModel.interactPrompt = withinInteractReach(player: player.position, target: beat.worldPosition.simd)
            ? beat.interactPrompt
            : ""
    }

    private func nearestWorkstationInRange() -> CraftingWorkstationConfig? {
        loadedWorkstations.first { withinInteractReach(player: player.position, target: $0.worldPosition.simd) }
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
                viewModel.flashInteractMessage("Tripwire rigged.")
            }
            return
        }

        guard let beat = loadedChapter?.storyBeat else { return }
        viewModel.flashInteractMessage(beat.interactMessage)
        viewModel.registerStoryBeatCompleted(beat.storyBeatId)

        let grantIds = beat.resolvedGrantItemIds().filter { ItemCatalog.definition(for: $0) != nil }
        guard !storyBeatRewardClaimed else { return }
        if grantIds.isEmpty { storyBeatRewardClaimed = true; return }

        if viewModel.addItemsAtomicallyIfPossible(itemIds: grantIds) {
            storyBeatRewardClaimed = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                viewModel.flashInteractMessage("Supplies added to inventory.")
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                viewModel.flashInteractMessage("Inventory full — make room.")
            }
        }
    }

    // MARK: - Hazard / completion

    private func processHazard(viewModel: GameSessionViewModel) {
        guard let region = hazardRegion, hazardVolumeMesh.isEnabled else { return }
        guard hazardCooldownRemaining <= 0 else { return }
        guard region.contains(player.position) else { return }

        hazardCooldownRemaining = 1.15
        viewModel.flashInteractMessage("Live wires — get clear!")

        if let motion = player.components[PhysicsMotionComponent.self] {
            let vy = motion.linearVelocity.y
            let dvY = max(0, 2.6 - vy)
            // Push player back toward spawn and up
            let backDir = -playerFacingVector
            player.applyLinearImpulse(
                SIMD3(Self.playerMass * backDir.x * 4.2, Self.playerMass * dvY, Self.playerMass * backDir.z * 4.2),
                relativeTo: nil
            )
        }
    }

    private func processChapterCompletion(viewModel: GameSessionViewModel) {
        guard !completionLatch, completionRegion.contains(player.position) else { return }
        completionLatch = true
        viewModel.notifyChapterCompleted()
    }
}
