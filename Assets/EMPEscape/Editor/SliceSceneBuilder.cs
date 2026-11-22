using System.Collections.Generic;
using System.Linq;
using Ink.UnityIntegration;
using Unity.AI.Navigation;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.AI;
using static EMPEscape.EditorTools.SceneBuildKit;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Menu: EMP Escape > Build Test Slice Scene.
    /// Builds the Chapter 1 test slice: street, stalled cars, Ray, hotspots, camera zones and anchors, baked NavMesh.
    /// Gameplay shapes (colliders, NavMesh) are always the same; visuals come from SliceArtSet when models exist
    /// in Assets/EMPEscape/Art, otherwise grey placeholder shapes. Re-run any time; it overwrites the scene.
    /// Shared building pieces live in SceneBuildKit.
    /// </summary>
    public static class SliceSceneBuilder
    {
        const string InkPath = Root + "/Ink/chapter1_slice.ink";
        const string ScenePath = Root + "/Scenes/Slice.unity";
        const string NavMeshPath = Root + "/Scenes/Slice_NavMesh.asset";

        [MenuItem("EMP Escape/Build Test Slice Scene")]
        public static void Build()
        {
            var ink = LoadStory(InkPath);
            if (ink == null || !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            var scene = BeginScene();

            // ---------- Environment (baked into the NavMesh) ----------
            var environment = new GameObject("Environment");

            Block("Road", environment, new Vector3(0f, -0.05f, 2f), new Vector3(16f, 0.1f, 48f), "Asphalt");
            Block("Barrier_L", environment, new Vector3(-8.25f, 0.6f, 2f), new Vector3(0.5f, 1.2f, 48f), "Concrete");
            Block("Barrier_R", environment, new Vector3(8.25f, 0.6f, 2f), new Vector3(0.5f, 1.2f, 48f), "Concrete");
            Block("Overpass_Deck", environment, new Vector3(0f, 5.5f, 23f), new Vector3(16f, 1f, 4f), "Concrete");
            Block("Overpass_PillarL", environment, new Vector3(-6f, 2.5f, 23f), new Vector3(1f, 5f, 1f), "Concrete");
            Block("Overpass_PillarR", environment, new Vector3(6f, 2.5f, 23f), new Vector3(1f, 5f, 1f), "Concrete");
            var stairs = Block("OverpassStairs", environment, new Vector3(0f, 0.6f, 20.5f), new Vector3(3f, 1.2f, 2f), "Concrete");

            var carSize = new Vector3(1.9f, 1.4f, 4.4f);
            var parked = art.parkedCars.Where(m => m != null).ToArray();
            int parkedIndex = 0;
            GameObject NextParked() => parked.Length == 0 ? null : parked[parkedIndex++ % parked.Length];

            var yourCar = Vehicle("YourCar", environment, new Vector3(4f, 0f, -12f), 8f, carSize, "CarBlue", art.yourCar != null ? art.yourCar : NextParked(), true);
            var van = Vehicle("DeliveryVan", environment, new Vector3(-3.5f, 0f, -4f), -6f, new Vector3(2.3f, 2.6f, 5.8f), "VanWhite", art.van, false);
            Vehicle("Car_A", environment, new Vector3(-4f, 0f, -14f), -4f, carSize, "CarRed", NextParked(), true);
            Vehicle("Car_B", environment, new Vector3(4f, 0f, -3f), 12f, carSize, "CarGray", NextParked(), true);
            Vehicle("Car_C", environment, new Vector3(3.5f, 0f, 6f), -10f, carSize, "CarGreen", NextParked(), true);
            Vehicle("Car_D", environment, new Vector3(-3.5f, 0f, 9f), 5f, carSize, "CarGray", NextParked(), true);
            Vehicle("Truck_A", environment, new Vector3(-4f, 0f, 15f), 0f, new Vector3(2.6f, 3.2f, 8f), "TruckRust", art.truck != null ? art.truck : art.van, false);
            Vehicle("Truck_B", environment, new Vector3(4.2f, 0f, 16f), 0f, new Vector3(2.6f, 3.2f, 8f), "TruckRust", art.truck != null ? art.truck : art.van, false);

            var surface = environment.AddComponent<NavMeshSurface>();
            surface.collectObjects = CollectObjects.Children;
            surface.useGeometry = NavMeshCollectGeometry.PhysicsColliders;

            // ---------- City backdrop (outside the barriers, not walkable) ----------
            BuildBackdrop();

            // ---------- Characters ----------
            MakePlayer(new Vector3(2f, 0f, -16f), 0f);

            var ray = MakeNpc("Ray", new Vector3(-1.4f, 0f, -1.2f), 200f, "RayOrange", art.ray);

            // ---------- Hotspots ----------
            var stand = new GameObject("StandPoints").transform;
            Hotspot(yourCar, "Your Car", "car_look", "car_use", null, StandPoint(stand, "AtYourCar", new Vector3(2.2f, 0f, -12f)));
            Hotspot(van, "Delivery Van", "van_look", null, null, null);
            Hotspot(ray, "Ray", "ray_look", null, "ray_talk", StandPoint(stand, "AtRay", new Vector3(0.2f, 0f, -2.8f)));
            Hotspot(stairs, "Overpass", "overpass_look", "overpass_use", null, StandPoint(stand, "AtStairs", new Vector3(0f, 0f, 18.6f)));

            // ---------- Cameras ----------
            var anchors = new GameObject("CameraAnchors").transform;
            var streetCam = Anchor(anchors, "street", new Vector3(7.5f, 6f, -22f), new Vector3(0f, 1f, -8f));
            var overpassCam = Anchor(anchors, "approach", new Vector3(-7f, 6.5f, 1f), new Vector3(0f, 1f, 14f));
            Anchor(anchors, "intro", new Vector3(-2f, 11f, -26f), new Vector3(3f, 0f, -12f));
            Anchor(anchors, "ray_close", new Vector3(2.4f, 2f, -0.2f), new Vector3(-0.6f, 1.5f, -2f));
            Anchor(anchors, "overpass", new Vector3(1.8f, 2f, 13f), new Vector3(0f, 1.6f, 18.5f));

            Zone("Zone_Street", new Vector3(0f, 2f, -9f), new Vector3(16f, 4f, 22f), streetCam);
            Zone("Zone_Approach", new Vector3(0f, 2f, 12f), new Vector3(16f, 4f, 20f), overpassCam);

            SetupCamera(anchors, streetCam);
            SetupGame(ink, "intro");
            FinishScene(scene, surface, ScenePath, NavMeshPath);

            Debug.Log("[EMP Escape] Test slice built at " + ScenePath + ". " + ArtSummary() + " Press Play.");
        }
    }
}
