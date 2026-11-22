using Unity.AI.Navigation;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.AI;
using static EMPEscape.EditorTools.SceneBuildKit;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Menu: EMP Escape > Build Action Sandbox.
    /// A fenced yard with one station per interaction type, for trying out the game's actions before real
    /// levels exist: movement, hotspots, timed dialogue, tap / mash / hold QTEs, weapon pickup, melee swings,
    /// shooting, a fight that changes with your weapon and can kill you (death + retry), the end screen, sound,
    /// remembered choices, and the phone (faraday bag, solar panel, Wi-Fi relay, manuals to photograph, a dark
    /// shed for the flashlight).
    /// Story: Assets/EMPEscape/Ink/sandbox.ink. Add a station = geometry + Hotspot here + knots there.
    /// </summary>
    public static class SandboxSceneBuilder
    {
        const string InkPath = Root + "/Ink/sandbox.ink";
        const string ScenePath = Root + "/Scenes/Sandbox.unity";
        const string NavMeshPath = Root + "/Scenes/Sandbox_NavMesh.asset";

        [MenuItem("EMP Escape/Build Action Sandbox")]
        public static void Build()
        {
            var ink = LoadStory(InkPath);
            if (ink == null || !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            var scene = BeginScene();

            // ---------- Yard: everything here is baked into the NavMesh ----------
            var yard = new GameObject("Yard");
            Block("Ground", yard, new Vector3(0f, -0.05f, 0f), new Vector3(32f, 0.1f, 28f), "Ground");
            Block("Fence_N", yard, new Vector3(0f, 0.6f, 14f), new Vector3(32f, 1.2f, 0.3f), "Fence");
            Block("Fence_S", yard, new Vector3(0f, 0.6f, -14f), new Vector3(32f, 1.2f, 0.3f), "Fence");
            Block("Fence_W", yard, new Vector3(-16f, 0.6f, 0f), new Vector3(0.3f, 1.2f, 28f), "Fence");
            Block("Fence_E", yard, new Vector3(16f, 0.6f, 0f), new Vector3(0.3f, 1.2f, 28f), "Fence");
            var gate = Block("Gate", yard, new Vector3(0f, 1.1f, 13.6f), new Vector3(3f, 2.2f, 0.4f), "Board");

            var sign = Block("GuideSign", yard, new Vector3(0f, 1.1f, -6f), new Vector3(1.8f, 2.2f, 0.15f), "Board");

            // QTE row (west): mash, hold, tap
            var shelf = Block("FallenShelf", yard, new Vector3(-12f, 0.5f, 2f), new Vector3(2.2f, 1f, 1.2f), "Wood");
            var door = Block("BackDoor", yard, new Vector3(-8f, 1.1f, 2.5f), new Vector3(1.2f, 2.2f, 0.15f), "Wood");
            var jarShelf = Block("JarShelf", yard, new Vector3(-4f, 0.9f, 2.5f), new Vector3(1.6f, 1.8f, 0.5f), "Wood");

            // Weapons and the shooting range (east). Rails keep the player out of the line of fire.
            Block("WeaponTable", yard, new Vector3(4f, 0.45f, -6f), new Vector3(3.2f, 0.9f, 1f), "Wood");
            var bench = Block("RangeBench", yard, new Vector3(10f, 0.5f, 1.5f), new Vector3(5f, 1f, 0.6f), "Wood");
            Block("RangeRail_W", yard, new Vector3(7.4f, 0.5f, 7.8f), new Vector3(0.2f, 1f, 12f), "Fence");
            Block("RangeRail_E", yard, new Vector3(12.6f, 0.5f, 7.8f), new Vector3(0.2f, 1f, 12f), "Fence");

            // Phone kit: faraday bag by the start, solar panel in the sun, a Wi-Fi relay, a first-aid manual.
            var bagCrate = Block("BagCrate", yard, new Vector3(-2.5f, 0.4f, -9f), new Vector3(1f, 0.8f, 0.7f), "Wood");
            var solar = Block("SolarStand", yard, new Vector3(7f, 0.25f, -11f), new Vector3(1.2f, 0.5f, 0.8f), "Wood");
            var relay = Block("RelayBase", yard, new Vector3(12f, 0.3f, -9f), new Vector3(0.6f, 0.6f, 0.6f), "Gunmetal");
            var manualCrate = Block("ManualCrate", yard, new Vector3(-13.5f, 0.4f, -10f), new Vector3(1f, 0.8f, 0.7f), "Wood");
            var barrel = Block("BurnBarrel", yard, new Vector3(-1.5f, 0.5f, 5f), new Vector3(0.7f, 1f, 0.7f), "Rust");

            // Dark shed (north-west), doorway facing east. Somewhere to use the flashlight.
            Block("Shed_W", yard, new Vector3(-14.5f, 1.5f, 9.5f), new Vector3(0.2f, 3f, 4f), "ShedDark");
            Block("Shed_N", yard, new Vector3(-12.5f, 1.5f, 11.5f), new Vector3(4f, 3f, 0.2f), "ShedDark");
            Block("Shed_S", yard, new Vector3(-12.5f, 1.5f, 7.5f), new Vector3(4f, 3f, 0.2f), "ShedDark");
            Block("Shed_E1", yard, new Vector3(-10.5f, 1.5f, 8.15f), new Vector3(0.2f, 3f, 1.3f), "ShedDark");
            Block("Shed_E2", yard, new Vector3(-10.5f, 1.5f, 10.85f), new Vector3(0.2f, 3f, 1.3f), "ShedDark");
            Block("Shed_Lintel", yard, new Vector3(-10.5f, 2.6f, 9.5f), new Vector3(0.2f, 0.8f, 1.4f), "ShedDark");
            Block("Shed_Roof", yard, new Vector3(-12.5f, 3.05f, 9.5f), new Vector3(4.2f, 0.1f, 4.2f), "ShedDark");
            var handbookShelf = Block("HandbookShelf", yard, new Vector3(-14f, 0.5f, 10.6f), new Vector3(0.8f, 1f, 1.2f), "ShedDark");

            var surface = yard.AddComponent<NavMeshSurface>();
            surface.collectObjects = CollectObjects.Children;
            surface.useGeometry = NavMeshCollectGeometry.PhysicsColliders;

            // ---------- Props: tappable or shootable, not part of the NavMesh ----------
            var props = new GameObject("Props").transform;
            var knife = TableItem("Knife", props, new Vector3(3f, 0.93f, -6f), "knife");
            var bat = TableItem("Bat", props, new Vector3(4f, 0.93f, -6f), "bat");
            var pistol = TableItem("Pistol", props, new Vector3(5f, 0.93f, -6f), "pistol");
            VisualCube("Jar", props, new Vector3(-4f, 1.95f, 2.5f), new Vector3(0.25f, 0.3f, 0.25f), "Glass");
            ShootingTarget("Target_L", props, new Vector3(8.8f, 0f, 9f), "range");
            ShootingTarget("Target_M", props, new Vector3(10f, 0f, 10.5f), "range");
            ShootingTarget("Target_R", props, new Vector3(11.2f, 0f, 9f), "range");

            VisualCube("Bag", props, new Vector3(-2.5f, 0.95f, -9f), new Vector3(0.55f, 0.3f, 0.35f), "Cloth");
            var panel = VisualCube("Panel", props, new Vector3(7f, 0.75f, -11f), new Vector3(1.4f, 0.04f, 0.9f), "SolarBlue");
            panel.transform.rotation = Quaternion.Euler(-35f, 0f, 0f);
            VisualCube("Mast", props, new Vector3(12f, 1.7f, -9f), new Vector3(0.08f, 2.2f, 0.08f), "Gunmetal");
            VisualCube("RelayPanel", props, new Vector3(12f, 2.4f, -9.2f), new Vector3(0.5f, 0.04f, 0.35f), "SolarBlue").transform.rotation = Quaternion.Euler(-40f, 0f, 0f);
            var manual = VisualCube("Manual", props, new Vector3(-13.5f, 0.83f, -10f), new Vector3(0.3f, 0.05f, 0.4f), "Target");
            var handbook = VisualCube("Handbook", props, new Vector3(-14f, 1.03f, 10.6f), new Vector3(0.3f, 0.05f, 0.4f), "Target");
            VisualCube("Flame", props, new Vector3(-1.5f, 1.1f, 5f), new Vector3(0.45f, 0.25f, 0.45f), "Flame");
            var fireLight = new GameObject("FireLight").AddComponent<Light>();
            fireLight.transform.SetParent(props, false);
            fireLight.transform.position = new Vector3(-1.5f, 1.5f, 5f);
            fireLight.type = LightType.Point;
            fireLight.color = new Color(1f, 0.55f, 0.2f);
            fireLight.range = 6f;
            fireLight.intensity = 2f;
            barrel.AddComponent<EMPEscape.AmbientEmitter>().sound = "fire_crackle";

            Photographable(manualCrate, manual.transform, "manual_photo", null);
            Photographable(handbookShelf, handbook.transform, "radio_photo", "radio_photo_dark");

            // ---------- Characters ----------
            MakePlayer(new Vector3(1f, 0f, -10f), 0f);
            var ray = MakeNpc("Ray", new Vector3(-10f, 0f, -6f), 105f, "RayOrange", art.ray);
            var dummy = MakeNpc("Dummy", new Vector3(4f, 0f, 4f), 180f, "Burlap", null);
            var stranger = MakeNpc("Stranger", new Vector3(-6f, 0f, 9f), 180f, "StrangerRed", null);
            var strangerAim = new GameObject("AimPoint").transform;
            strangerAim.SetParent(stranger.transform, false);
            strangerAim.localPosition = new Vector3(0f, 1.35f, 0f);
            var strangerTarget = stranger.AddComponent<EMPEscape.ShootTarget>();
            strangerTarget.group = "stranger";
            strangerTarget.aimPoint = strangerAim;
            strangerTarget.hitSound = "hit_flesh";

            // ---------- Hotspots (knots live in sandbox.ink) ----------
            var stand = new GameObject("StandPoints").transform;
            Hotspot(sign, "Guide Sign", "sign_look", null, null, null);
            Hotspot(ray, "Ray", "ray_look", null, "ray_talk", StandPoint(stand, "AtRay", new Vector3(-8.6f, 0f, -6.4f)));
            Hotspot(shelf, "Fallen Shelf", "shelf_look", "shelf_use", null, StandPoint(stand, "AtShelf", new Vector3(-12f, 0f, 0.6f)));
            Hotspot(door, "Back Door", "door_look", "door_use", null, StandPoint(stand, "AtDoor", new Vector3(-8f, 0f, 1.6f)));
            Hotspot(jarShelf, "Jar Shelf", "jar_look", "jar_use", null, StandPoint(stand, "AtJar", new Vector3(-4f, 0f, 1.6f)));
            var atTable = StandPoint(stand, "AtTable", new Vector3(4f, 0f, -7.2f));
            Hotspot(knife, "Knife", "knife_look", "knife_use", null, atTable);
            Hotspot(bat, "Bat", "bat_look", "bat_use", null, atTable);
            Hotspot(pistol, "Pistol", "pistol_look", "pistol_use", null, atTable);
            Hotspot(dummy, "Training Dummy", "dummy_look", "dummy_use", null, StandPoint(stand, "AtDummy", new Vector3(4f, 0f, 2.9f)));
            Hotspot(bench, "Shooting Range", "range_look", "range_use", null, StandPoint(stand, "AtRange", new Vector3(10f, 0f, 0.5f)));
            Hotspot(stranger, "Stranger", "stranger_look", null, "stranger_talk", StandPoint(stand, "AtStranger", new Vector3(-6f, 0f, 7.4f)));
            Hotspot(gate, "Gate", "gate_look", "gate_use", null, StandPoint(stand, "AtGate", new Vector3(0f, 0f, 12.2f)));
            Hotspot(bagCrate, "Faraday Bag", "bag_look", "bag_use", null, StandPoint(stand, "AtBag", new Vector3(-2.5f, 0f, -10.1f)));
            Hotspot(solar, "Solar Panel", "solar_look", "solar_use", null, StandPoint(stand, "AtSolar", new Vector3(7f, 0f, -12.1f)));
            Hotspot(relay, "Wi-Fi Relay", "relay_look", "relay_use", null, StandPoint(stand, "AtRelay", new Vector3(11f, 0f, -9f)));
            Hotspot(manualCrate, "First-Aid Manual", "manual_look", "manual_use", null, StandPoint(stand, "AtManual", new Vector3(-13.5f, 0f, -8.9f)));
            Hotspot(handbookShelf, "Radio Handbook", "radio_look", "radio_use", null, StandPoint(stand, "AtHandbook", new Vector3(-12.9f, 0f, 10.4f)));
            Hotspot(barrel, "Burn Barrel", "barrel_look", null, null, null);

            // ---------- Cameras: one per half of the yard, plus story close-ups ----------
            var anchors = new GameObject("CameraAnchors").transform;
            var west = Anchor(anchors, "yard_west", new Vector3(-5f, 10f, -19f), new Vector3(-7f, 0f, -1f));
            var east = Anchor(anchors, "yard_east", new Vector3(5f, 10f, -19f), new Vector3(7f, 0f, -1f));
            Anchor(anchors, "intro", new Vector3(0f, 16f, -22f), new Vector3(0f, 0f, 0f));
            Anchor(anchors, "ray_close", new Vector3(-7.2f, 1.9f, -7.6f), new Vector3(-10f, 1.5f, -6f));
            Anchor(anchors, "qte_close", new Vector3(-8f, 3f, -3.5f), new Vector3(-8f, 1f, 2f));
            Anchor(anchors, "table_close", new Vector3(4f, 2.3f, -9.6f), new Vector3(4f, 0.9f, -6f));
            Anchor(anchors, "dummy_close", new Vector3(6.3f, 1.9f, 1.2f), new Vector3(4f, 1.2f, 4f));
            Anchor(anchors, "range", new Vector3(10.9f, 2.3f, -2.2f), new Vector3(10f, 1.3f, 9.5f));
            Anchor(anchors, "stranger_close", new Vector3(-3.8f, 1.9f, 5.6f), new Vector3(-6f, 1.4f, 9f));

            var shedCam = Anchor(anchors, "shed_inside", new Vector3(-11f, 2.5f, 8f), new Vector3(-14f, 0.6f, 10.6f));

            Zone("Zone_West", new Vector3(-8f, 2f, 0f), new Vector3(16f, 4f, 28f), west);
            Zone("Zone_Shed", new Vector3(-12.5f, 1.5f, 9.5f), new Vector3(3.8f, 3f, 3.8f), shedCam);
            Zone("Zone_East", new Vector3(8f, 2f, 0f), new Vector3(16f, 4f, 28f), east);

            SetupCamera(anchors, east);
            SetupGame(ink, "intro");
            FinishScene(scene, surface, ScenePath, NavMeshPath);

            Debug.Log("[EMP Escape] Action sandbox built at " + ScenePath + ". It's now first in Build Settings, so it launches on the iPhone. " + ArtSummary() + " Press Play.");
        }

        static void Photographable(GameObject target, Transform focus, string knot, string darkKnot)
        {
            var subject = target.AddComponent<EMPEscape.PhotoSubject>();
            subject.focus = focus;
            subject.knot = knot;
            subject.needsLight = !string.IsNullOrEmpty(darkKnot);
            subject.darkKnot = darkKnot;
            subject.range = 4f;
        }

        /// <summary>A weapon lying on the table, with a generous tap box so it's easy to hit on a phone.</summary>
        static GameObject TableItem(string name, Transform parent, Vector3 position, string weaponId)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            root.transform.position = position;
            root.AddComponent<BoxCollider>().size = new Vector3(0.8f, 0.3f, 0.8f);

            var prop = WeaponProp(weaponId, root.transform);
            prop.transform.localRotation = Quaternion.Euler(0f, 90f, 90f); // lying on its side, pointing +X
            prop.transform.localPosition = new Vector3(-WeaponLength(weaponId) * 0.5f, 0f, 0f);
            return root;
        }
    }
}
