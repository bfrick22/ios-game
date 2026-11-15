using System.Collections.Generic;
using System.Linq;
using Ink.UnityIntegration;
using Unity.AI.Navigation;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.AI;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Menu: EMP Escape > Build Test Slice Scene.
    /// Builds the Chapter 1 test slice: street, stalled cars, Ray, hotspots, camera zones and anchors, baked NavMesh.
    /// Gameplay shapes (colliders, NavMesh) are always the same; visuals come from SliceArtSet when models exist
    /// in Assets/EMPEscape/Art, otherwise grey placeholder shapes. Re-run any time; it overwrites the scene.
    /// </summary>
    public static class SliceSceneBuilder
    {
        const string Root = "Assets/EMPEscape";
        const string InkPath = Root + "/Ink/chapter1_slice.ink";
        const string ScenePath = Root + "/Scenes/Slice.unity";
        const string NavMeshPath = Root + "/Scenes/Slice_NavMesh.asset";
        const string MaterialsPath = Root + "/Materials";
        const string ArtRoot = Root + "/Art";
        const string ArtSetPath = ArtRoot + "/SliceArtSet.asset";
        const float CharacterHeight = 1.8f;

        static Shader litShader;
        static readonly Dictionary<string, Material> materials = new Dictionary<string, Material>();
        static SliceArtSet art;

        [MenuItem("EMP Escape/Build Test Slice Scene")]
        public static void Build()
        {
            var ink = AssetDatabase.LoadAssetAtPath<InkFile>(InkPath);
            if (ink == null || !ink.isCompiled)
            {
                EditorUtility.DisplayDialog("EMP Escape",
                    "Couldn't load a compiled story from " + InkPath + ".\n\nSelect the .ink file and check the Inspector for compile errors, then run this again.",
                    "OK");
                return;
            }
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;

            EnsureFolder(Root + "/Scenes");
            EnsureFolder(MaterialsPath);
            foreach (var folder in new[] { "Characters", "Animations", "Vehicles", "City" }) EnsureFolder(ArtRoot + "/" + folder);
            materials.Clear();
            art = LoadOrCreateArtSet();

            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
            CacheLitShader();
            SetupLighting();

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
            var player = Character("Player", new Vector3(2f, 0f, -16f), 0f, "PlayerTeal", art.player);
            player.tag = "Player";
            var agent = player.AddComponent<NavMeshAgent>();
            agent.speed = 2.6f;
            agent.angularSpeed = 720f;
            agent.acceleration = 14f;
            agent.radius = 0.4f;
            agent.height = CharacterHeight;
            agent.baseOffset = 0f;
            var body = player.AddComponent<Rigidbody>();
            body.isKinematic = true;
            body.useGravity = false;
            player.AddComponent<EMPEscape.PlayerController>();

            var ray = Character("Ray", new Vector3(-1.4f, 0f, -1.2f), 200f, "RayOrange", art.ray);
            var obstacle = ray.AddComponent<NavMeshObstacle>();
            obstacle.shape = NavMeshObstacleShape.Capsule;
            obstacle.center = new Vector3(0f, CharacterHeight * 0.5f, 0f);
            obstacle.height = CharacterHeight;
            obstacle.radius = 0.5f;
            obstacle.carving = true;

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

            var mainCamera = Camera.main;
            mainCamera.fieldOfView = 50f;
            mainCamera.farClipPlane = 150f;
            mainCamera.transform.SetPositionAndRotation(streetCam.position, streetCam.rotation);
            var director = mainCamera.gameObject.AddComponent<EMPEscape.CameraDirector>();
            director.anchorsRoot = anchors;
            director.initialAnchor = streetCam;

            // ---------- Game root ----------
            var game = new GameObject("Game");
            game.AddComponent<EMPEscape.GameUI>();
            var story = game.AddComponent<EMPEscape.StoryDirector>();
            story.inkFile = ink;
            story.openingKnot = "intro";

            // ---------- Bake + save ----------
            surface.BuildNavMesh();
            if (AssetDatabase.LoadAssetAtPath<Object>(NavMeshPath) != null) AssetDatabase.DeleteAsset(NavMeshPath);
            AssetDatabase.CreateAsset(surface.navMeshData, NavMeshPath);

            EditorSceneManager.SaveScene(scene, ScenePath);
            AddToBuildSettings(ScenePath);
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            AssetDatabase.SaveAssets();

            Debug.Log("[EMP Escape] Test slice built at " + ScenePath + ". " + ArtSummary() + " Press Play.");
        }

        // ---------- art set ----------

        [MenuItem("EMP Escape/Reset Art Picks")]
        static void ResetArtPicks()
        {
            var set = AssetDatabase.LoadAssetAtPath<SliceArtSet>(ArtSetPath);
            if (set != null)
            {
                set.player = set.ray = set.yourCar = set.van = set.truck = null;
                set.characterAnimator = null;
                set.parkedCars = new GameObject[0];
                set.buildings = new GameObject[0];
                set.streetProps = new GameObject[0];
                EditorUtility.SetDirty(set);
            }
            LoadOrCreateArtSet();
            Debug.Log("[EMP Escape] Art picks reset from Assets/EMPEscape/Art. Run Build Test Slice Scene to apply.");
        }

        static SliceArtSet LoadOrCreateArtSet()
        {
            var set = AssetDatabase.LoadAssetAtPath<SliceArtSet>(ArtSetPath);
            if (set == null)
            {
                set = ScriptableObject.CreateInstance<SliceArtSet>();
                AssetDatabase.CreateAsset(set, ArtSetPath);
            }

            var characters = Models(ArtRoot + "/Characters");
            if (set.player == null) set.player = Pick(characters, "player") ?? characters.FirstOrDefault();
            if (set.ray == null) set.ray = Pick(characters, "ray") ?? characters.FirstOrDefault(m => m != set.player) ?? set.player;

            var vehicles = Models(ArtRoot + "/Vehicles");
            if (set.van == null) set.van = Pick(vehicles, "delivery", "van");
            if (set.truck == null) set.truck = Pick(vehicles, "truck", "garbage-truck", "box");
            if (set.yourCar == null) set.yourCar = Pick(vehicles, "sedan", "hatchback", "suv", "coupe");
            if (set.parkedCars == null || set.parkedCars.All(m => m == null))
            {
                var cars = vehicles.Where(m => m != set.van && m != set.truck && m != set.yourCar
                                               && !Matches(m, "kart", "race", "tractor", "wheel", "debris", "cone", "fire", "garbage")).ToArray();
                var named = cars.Where(m => Matches(m, "sedan", "hatchback", "suv", "taxi", "police", "sports", "coupe", "car")).ToArray();
                set.parkedCars = named.Length > 0 ? named : cars;
            }

            var city = Models(ArtRoot + "/City");
            if (set.buildings == null || set.buildings.All(m => m == null))
                set.buildings = city.Where(m => Matches(m, "building", "skyscraper", "house", "shop", "store", "tower", "office")).ToArray();
            if (set.streetProps == null || set.streetProps.All(m => m == null))
                set.streetProps = city.Where(m => Matches(m, "light", "lamp", "hydrant", "bench", "sign", "bin", "trash", "tree", "planter")).ToArray();

            if (set.characterAnimator == null && (set.player != null || set.ray != null))
                set.characterAnimator = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(CharacterAnimatorBuilder.ControllerPath)
                                        ?? CharacterAnimatorBuilder.Build();

            EditorUtility.SetDirty(set);
            AssetDatabase.SaveAssets();
            return set;
        }

        static List<GameObject> Models(string folder)
        {
            var result = new List<GameObject>();
            if (!AssetDatabase.IsValidFolder(folder)) return result;
            var paths = AssetDatabase.FindAssets("t:Model", new[] { folder })
                .Concat(AssetDatabase.FindAssets("t:Prefab", new[] { folder }))
                .Select(guid => AssetDatabase.GUIDToAssetPath(guid)).Distinct().OrderBy(p => p);
            foreach (var path in paths)
            {
                var model = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                if (model != null) result.Add(model);
            }
            return result;
        }

        static GameObject Pick(List<GameObject> models, params string[] keywords)
        {
            foreach (var keyword in keywords)
                foreach (var model in models)
                    if (model.name.ToLowerInvariant() == keyword) return model;
            foreach (var keyword in keywords)
                foreach (var model in models)
                    if (model.name.ToLowerInvariant().Contains(keyword)) return model;
            return null;
        }

        static bool Matches(GameObject model, params string[] keywords)
        {
            var name = model.name.ToLowerInvariant();
            return keywords.Any(keyword => name.Contains(keyword));
        }

        static string ArtSummary()
        {
            int models = new[] { art.player, art.ray, art.yourCar, art.van, art.truck }.Count(m => m != null)
                         + art.parkedCars.Count(m => m != null) + art.buildings.Count(m => m != null);
            if (models == 0) return "Using placeholder shapes (no models in Assets/EMPEscape/Art yet).";
            bool hasCharacters = art.player != null || art.ray != null;
            if (hasCharacters && art.characterAnimator == null)
                return $"Using {models} art models. Characters will T-pose: no idle clip in Assets/EMPEscape/Art/Animations.";
            return $"Using {models} art models" + (hasCharacters ? " with character animation." : ".");
        }

        // ---------- builders ----------

        /// <summary>Static block: box collider on the root, grey cube visual.</summary>
        static GameObject Block(string name, GameObject parent, Vector3 center, Vector3 size, string material)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent.transform, false);
            root.transform.position = center;
            root.AddComponent<BoxCollider>().size = size;
            VisualCube("Visual", root.transform, Vector3.zero, size, material);
            return root;
        }

        /// <summary>Vehicle: root at ground level, box collider for NavMesh/taps, model or placeholder visual.</summary>
        static GameObject Vehicle(string name, GameObject parent, Vector3 groundPosition, float yaw, Vector3 size, string material, GameObject model, bool withCabin)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent.transform, false);
            root.transform.SetPositionAndRotation(groundPosition, Quaternion.Euler(0f, yaw, 0f));
            var box = root.AddComponent<BoxCollider>();
            box.size = size;
            box.center = new Vector3(0f, size.y * 0.5f, 0f);

            if (model != null)
            {
                PlaceModel(model, root.transform, size, FitMode.Length, art.vehicleYawOffset);
                return root;
            }

            var bodyHeight = withCabin ? size.y * 0.6f : size.y;
            VisualCube("Body", root.transform, new Vector3(0f, bodyHeight * 0.5f, 0f), new Vector3(size.x, bodyHeight, size.z), material);
            if (withCabin)
            {
                var cabinHeight = size.y - bodyHeight;
                VisualCube("Cabin", root.transform, new Vector3(0f, bodyHeight + cabinHeight * 0.5f, -0.2f),
                    new Vector3(size.x * 0.88f, cabinHeight, size.z * 0.5f), "Glass");
            }
            return root;
        }

        /// <summary>Character: root at the feet with a capsule collider, model (animated) or placeholder capsule.</summary>
        static GameObject Character(string name, Vector3 feet, float yaw, string material, GameObject model)
        {
            var root = new GameObject(name);
            root.transform.SetPositionAndRotation(feet, Quaternion.Euler(0f, yaw, 0f));
            var capsule = root.AddComponent<CapsuleCollider>();
            capsule.height = CharacterHeight;
            capsule.radius = 0.35f;
            capsule.center = new Vector3(0f, CharacterHeight * 0.5f, 0f);
            root.AddComponent<EMPEscape.CharacterActor>().actorName = name;

            if (model != null)
            {
                var visual = PlaceModel(model, root.transform, new Vector3(0.6f, CharacterHeight, 0.6f), FitMode.Height, art.characterYawOffset);
                // Not "??": in the editor GetComponent returns a fake-null object that ?? treats as real.
                var animator = visual.GetComponent<Animator>();
                if (animator == null) animator = visual.AddComponent<Animator>();
                animator.runtimeAnimatorController = art.characterAnimator;
                animator.applyRootMotion = false;
                animator.cullingMode = AnimatorCullingMode.CullUpdateTransforms;
                return root;
            }

            var body = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.name = "Visual";
            Object.DestroyImmediate(body.GetComponent<Collider>());
            body.transform.SetParent(root.transform, false);
            body.transform.localPosition = new Vector3(0f, CharacterHeight * 0.5f, 0f);
            body.transform.localScale = new Vector3(0.7f, CharacterHeight * 0.5f, 0.7f);
            body.GetComponent<Renderer>().sharedMaterial = Mat(material);
            // A "nose" so you can read which way placeholder characters face.
            VisualCube("Facing", root.transform, new Vector3(0f, CharacterHeight * 0.75f, 0.32f), new Vector3(0.22f, 0.1f, 0.15f), "Glass");
            return root;
        }

        static void BuildBackdrop()
        {
            var backdrop = new GameObject("Backdrop");
            Block("Ground", backdrop, new Vector3(0f, -0.12f, 2f), new Vector3(80f, 0.1f, 90f), "Concrete");

            var buildings = art.buildings.Where(m => m != null).ToArray();
            var props = art.streetProps.Where(m => m != null).ToArray();
            var random = new System.Random(7);

            if (buildings.Length > 0)
            {
                foreach (var side in new[] { -1f, 1f })
                    for (float z = -24f; z <= 28f; z += 9f)
                    {
                        var slot = new GameObject("Building").transform;
                        slot.SetParent(backdrop.transform, false);
                        slot.SetPositionAndRotation(new Vector3(side * 15f, 0f, z), Quaternion.Euler(0f, side < 0f ? 90f : -90f, 0f));
                        PlaceModel(buildings[random.Next(buildings.Length)], slot, new Vector3(8f, 0f, 8f), FitMode.Length, 0f);
                    }
            }

            if (props.Length > 0)
            {
                foreach (var side in new[] { -1f, 1f })
                    for (float z = -20f; z <= 24f; z += 11f)
                    {
                        var slot = new GameObject("Prop").transform;
                        slot.SetParent(backdrop.transform, false);
                        slot.SetPositionAndRotation(new Vector3(side * 9.4f, 0f, z), Quaternion.Euler(0f, side < 0f ? 90f : -90f, 0f));
                        PlaceModel(props[random.Next(props.Length)], slot, new Vector3(1f, 4.5f, 1f), FitMode.Height, 0f);
                    }
            }
        }

        enum FitMode { Height, Length }

        /// <summary>Instantiate a model under parent, scale it to fit, center it, and stand it on the parent's ground level.</summary>
        static GameObject PlaceModel(GameObject model, Transform parent, Vector3 target, FitMode mode, float yawOffset)
        {
            var instance = (GameObject)PrefabUtility.InstantiatePrefab(model, parent);
            instance.name = "Visual_" + model.name;
            instance.transform.localPosition = Vector3.zero;
            instance.transform.localRotation = Quaternion.Euler(0f, yawOffset, 0f);
            instance.transform.localScale = Vector3.one;
            foreach (var collider in instance.GetComponentsInChildren<Collider>()) Object.DestroyImmediate(collider);

            if (!TryGetBounds(instance, out var bounds)) return instance;
            float scale = mode == FitMode.Height
                ? target.y / Mathf.Max(0.001f, bounds.size.y)
                : Mathf.Max(target.x, target.z) / Mathf.Max(0.001f, Mathf.Max(bounds.size.x, bounds.size.z));
            instance.transform.localScale = Vector3.one * scale;

            TryGetBounds(instance, out bounds);
            instance.transform.position += parent.position - new Vector3(bounds.center.x, bounds.min.y, bounds.center.z);
            return instance;
        }

        static bool TryGetBounds(GameObject go, out Bounds bounds)
        {
            bounds = default;
            var renderers = go.GetComponentsInChildren<Renderer>();
            if (renderers.Length == 0) return false;
            bounds = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++) bounds.Encapsulate(renderers[i].bounds);
            return true;
        }

        static GameObject VisualCube(string name, Transform parent, Vector3 localPosition, Vector3 size, string material)
        {
            var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cube.name = name;
            Object.DestroyImmediate(cube.GetComponent<Collider>());
            cube.transform.SetParent(parent, false);
            cube.transform.localPosition = localPosition;
            cube.transform.localScale = size;
            cube.GetComponent<Renderer>().sharedMaterial = Mat(material);
            return cube;
        }

        static void Hotspot(GameObject target, string displayName, string look, string use, string talk, Transform standPoint)
        {
            var hotspot = target.AddComponent<EMPEscape.Hotspot>();
            hotspot.displayName = displayName;
            hotspot.lookKnot = look;
            hotspot.useKnot = use;
            hotspot.talkKnot = talk;
            hotspot.standPoint = standPoint;
        }

        static Transform StandPoint(Transform parent, string name, Vector3 position)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.position = position;
            return t;
        }

        static Transform Anchor(Transform parent, string name, Vector3 position, Vector3 lookAt)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.position = position;
            t.LookAt(lookAt);
            return t;
        }

        static void Zone(string name, Vector3 center, Vector3 size, Transform anchor)
        {
            var go = new GameObject(name);
            go.transform.position = center;
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = size;
            go.AddComponent<EMPEscape.CameraZone>().cameraAnchor = anchor;
        }

        static void SetupLighting()
        {
            var sun = Object.FindFirstObjectByType<Light>();
            if (sun != null)
            {
                sun.color = new Color(1f, 0.62f, 0.38f);
                sun.intensity = 1.3f;
                sun.shadows = LightShadows.Soft;
                sun.transform.rotation = Quaternion.Euler(14f, -40f, 0f);
            }
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.32f, 0.3f, 0.38f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = new Color(0.55f, 0.42f, 0.4f);
            RenderSettings.fogStartDistance = 25f;
            RenderSettings.fogEndDistance = 70f;
        }

        static void CacheLitShader()
        {
            var probe = GameObject.CreatePrimitive(PrimitiveType.Cube);
            litShader = probe.GetComponent<Renderer>().sharedMaterial.shader;
            Object.DestroyImmediate(probe);
        }

        static Material Mat(string name)
        {
            if (materials.TryGetValue(name, out var cached)) return cached;
            var path = $"{MaterialsPath}/{name}.mat";
            var material = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (material == null)
            {
                material = new Material(litShader) { color = Palette(name) };
                AssetDatabase.CreateAsset(material, path);
            }
            materials[name] = material;
            return material;
        }

        static Color Palette(string name)
        {
            switch (name)
            {
                case "Asphalt": return new Color(0.18f, 0.18f, 0.2f);
                case "Concrete": return new Color(0.55f, 0.53f, 0.5f);
                case "CarBlue": return new Color(0.2f, 0.35f, 0.6f);
                case "CarRed": return new Color(0.55f, 0.15f, 0.12f);
                case "CarGray": return new Color(0.42f, 0.43f, 0.45f);
                case "CarGreen": return new Color(0.2f, 0.38f, 0.28f);
                case "VanWhite": return new Color(0.82f, 0.82f, 0.78f);
                case "TruckRust": return new Color(0.5f, 0.3f, 0.18f);
                case "Glass": return new Color(0.08f, 0.1f, 0.12f);
                case "PlayerTeal": return new Color(0.15f, 0.55f, 0.55f);
                case "RayOrange": return new Color(0.85f, 0.45f, 0.15f);
                default: return Color.magenta;
            }
        }

        static void EnsureFolder(string path)
        {
            if (AssetDatabase.IsValidFolder(path)) return;
            var parent = System.IO.Path.GetDirectoryName(path).Replace('\\', '/');
            EnsureFolder(parent);
            AssetDatabase.CreateFolder(parent, System.IO.Path.GetFileName(path));
        }

        static void AddToBuildSettings(string scenePath)
        {
            var scenes = new List<EditorBuildSettingsScene>(EditorBuildSettings.scenes);
            scenes.RemoveAll(s => s.path == scenePath);
            scenes.Insert(0, new EditorBuildSettingsScene(scenePath, true));
            EditorBuildSettings.scenes = scenes.ToArray();
        }
    }
}
