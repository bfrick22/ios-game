using System.Collections.Generic;
using System.Linq;
using Ink.UnityIntegration;
using Unity.AI.Navigation;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.SceneManagement;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Shared pieces for the scene builders (SliceSceneBuilder, SandboxSceneBuilder): scene setup and saving,
    /// art picks from Assets/EMPEscape/Art, placeholder-or-model visuals, characters, weapons, hotspots,
    /// cameras and lighting. Builders use it with "using static EMPEscape.EditorTools.SceneBuildKit;".
    /// </summary>
    internal static class SceneBuildKit
    {
        internal const string Root = "Assets/EMPEscape";
        internal const string MaterialsPath = Root + "/Materials";
        internal const string ArtRoot = Root + "/Art";
        internal const string ArtSetPath = ArtRoot + "/SliceArtSet.asset";
        internal const float CharacterHeight = 1.8f;
        static readonly string[] ArtFolders = { "Characters", "Animations", "Vehicles", "City", "Weapons" };

        static Shader litShader;
        internal static readonly Dictionary<string, Material> materials = new Dictionary<string, Material>();
        internal static SliceArtSet art;

        // ---------- scene lifecycle ----------

        /// <summary>Loads a compiled Ink story, or explains how to fix it and returns null.</summary>
        internal static InkFile LoadStory(string path)
        {
            var ink = AssetDatabase.LoadAssetAtPath<InkFile>(path);
            if (ink != null && ink.isCompiled) return ink;
            EditorUtility.DisplayDialog("EMP Escape",
                "Couldn't load a compiled story from " + path + ".\n\nSelect the .ink file and check the Inspector for compile errors, then run this again.",
                "OK");
            return null;
        }

        /// <summary>Folders, art picks, and a fresh scene with lighting.</summary>
        internal static Scene BeginScene()
        {
            EnsureFolder(Root + "/Scenes");
            EnsureFolder(MaterialsPath);
            foreach (var folder in ArtFolders) EnsureFolder(ArtRoot + "/" + folder);
            materials.Clear();
            art = LoadOrCreateArtSet();

            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
            CacheLitShader();
            SetupLighting();
            return scene;
        }

        /// <summary>
        /// Bakes the NavMesh, saves the scene, and puts it first in Build Settings, so the scene built
        /// last is the one that launches on the iPhone.
        /// </summary>
        internal static void FinishScene(Scene scene, NavMeshSurface surface, string scenePath, string navMeshPath)
        {
            surface.BuildNavMesh();
            if (AssetDatabase.LoadAssetAtPath<Object>(navMeshPath) != null) AssetDatabase.DeleteAsset(navMeshPath);
            AssetDatabase.CreateAsset(surface.navMeshData, navMeshPath);

            EditorSceneManager.SaveScene(scene, scenePath);
            AddToBuildSettings(scenePath);
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            AssetDatabase.SaveAssets();
        }

        internal static void SetupCamera(Transform anchors, Transform start)
        {
            var mainCamera = Camera.main;
            mainCamera.fieldOfView = 50f;
            mainCamera.farClipPlane = 150f;
            mainCamera.transform.SetPositionAndRotation(start.position, start.rotation);
            var director = mainCamera.gameObject.AddComponent<EMPEscape.CameraDirector>();
            director.anchorsRoot = anchors;
            director.initialAnchor = start;
        }

        internal static void SetupGame(InkFile ink, string openingKnot)
        {
            var game = new GameObject("Game");
            game.AddComponent<EMPEscape.GameUI>();
            var story = game.AddComponent<EMPEscape.StoryDirector>();
            story.inkFile = ink;
            story.openingKnot = openingKnot;
        }

        // ---------- characters and weapons ----------

        /// <summary>The player: character, NavMesh agent, movement, and a WeaponHolder with all weapon props.</summary>
        internal static GameObject MakePlayer(Vector3 feet, float yaw)
        {
            var player = Character("Player", feet, yaw, "PlayerTeal", art.player);
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
            player.AddComponent<EMPEscape.Flashlight>();
            player.GetComponent<EMPEscape.CharacterActor>().footsteps = true;

            var holder = player.AddComponent<EMPEscape.WeaponHolder>();
            var rack = new GameObject("Weapons").transform;
            rack.SetParent(player.transform, false);
            holder.props = new[] { "knife", "bat", "pistol" }.Select(id => WeaponProp(id, rack)).ToArray();
            foreach (var prop in holder.props) prop.SetActive(false);
            holder.gripPosition = art.weaponGripPosition;
            holder.gripRotation = art.weaponGripRotation;
            return player;
        }

        /// <summary>A standing character the player walks around (NavMesh carves around it).</summary>
        internal static GameObject MakeNpc(string name, Vector3 feet, float yaw, string material, GameObject model)
        {
            var npc = Character(name, feet, yaw, material, model);
            var obstacle = npc.AddComponent<NavMeshObstacle>();
            obstacle.shape = NavMeshObstacleShape.Capsule;
            obstacle.center = new Vector3(0f, CharacterHeight * 0.5f, 0f);
            obstacle.height = CharacterHeight;
            obstacle.radius = 0.5f;
            obstacle.carving = true;
            return npc;
        }

        /// <summary>
        /// A weapon named by id ("knife", "bat", "pistol") pointing along +Z from its grip: the model from
        /// Art/Weapons if there is one, otherwise simple shapes.
        /// </summary>
        internal static GameObject WeaponProp(string id, Transform parent)
        {
            var root = new GameObject(id);
            root.transform.SetParent(parent, false);
            var model = id == "knife" ? art.knife : id == "bat" ? art.bat : art.pistol;
            if (model != null)
            {
                float length = WeaponLength(id);
                PlaceModel(model, root.transform, new Vector3(length, 0f, length), FitMode.Length, 0f);
                return root;
            }

            switch (id)
            {
                case "knife":
                    VisualCube("Handle", root.transform, new Vector3(0f, 0f, 0.05f), new Vector3(0.03f, 0.03f, 0.11f), "Grip");
                    VisualCube("Blade", root.transform, new Vector3(0f, 0f, 0.19f), new Vector3(0.012f, 0.035f, 0.18f), "Steel");
                    break;
                case "bat":
                    VisualCube("Handle", root.transform, new Vector3(0f, 0f, 0.14f), new Vector3(0.035f, 0.035f, 0.3f), "Wood");
                    VisualCube("Barrel", root.transform, new Vector3(0f, 0f, 0.55f), new Vector3(0.07f, 0.07f, 0.55f), "Wood");
                    break;
                default:
                    VisualCube("Grip", root.transform, new Vector3(0f, -0.04f, 0f), new Vector3(0.03f, 0.1f, 0.045f), "Gunmetal");
                    VisualCube("Slide", root.transform, new Vector3(0f, 0.025f, 0.06f), new Vector3(0.035f, 0.045f, 0.19f), "Gunmetal");
                    break;
            }
            return root;
        }

        internal static float WeaponLength(string id) => id == "bat" ? 0.83f : id == "knife" ? 0.28f : 0.2f;

        /// <summary>A target for the shoot QTE: post and plate facing -Z (toward a shooter to the south).</summary>
        internal static GameObject ShootingTarget(string name, Transform parent, Vector3 feet, string group)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            root.transform.SetPositionAndRotation(feet, Quaternion.Euler(0f, 180f, 0f));
            VisualCube("Post", root.transform, new Vector3(0f, 0.55f, 0f), new Vector3(0.08f, 1.1f, 0.08f), "Wood");
            VisualCube("Plate", root.transform, new Vector3(0f, 1.4f, 0f), new Vector3(0.6f, 0.8f, 0.05f), "Target");
            var aim = new GameObject("AimPoint").transform;
            aim.SetParent(root.transform, false);
            aim.localPosition = new Vector3(0f, 1.4f, 0f);
            var target = root.AddComponent<EMPEscape.ShootTarget>();
            target.group = group;
            target.aimPoint = aim;
            return root;
        }

        // ---------- art set ----------

        [MenuItem("EMP Escape/Reset Art Picks")]
        internal static void ResetArtPicks()
        {
            var set = AssetDatabase.LoadAssetAtPath<SliceArtSet>(ArtSetPath);
            if (set != null)
            {
                set.player = set.ray = set.yourCar = set.van = set.truck = null;
                set.knife = set.bat = set.pistol = null;
                set.characterAnimator = null;
                set.parkedCars = new GameObject[0];
                set.buildings = new GameObject[0];
                set.streetProps = new GameObject[0];
                EditorUtility.SetDirty(set);
            }
            LoadOrCreateArtSet();
            Debug.Log("[EMP Escape] Art picks reset from Assets/EMPEscape/Art. Run Build Test Slice Scene to apply.");
        }

        internal static SliceArtSet LoadOrCreateArtSet()
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

            var weapons = Models(ArtRoot + "/Weapons");
            if (set.knife == null) set.knife = Pick(weapons, "knife", "blade");
            if (set.bat == null) set.bat = Pick(weapons, "bat", "club");
            if (set.pistol == null) set.pistol = Pick(weapons, "pistol", "handgun", "gun");

            if (set.characterAnimator == null && (set.player != null || set.ray != null))
                set.characterAnimator = AssetDatabase.LoadAssetAtPath<RuntimeAnimatorController>(CharacterAnimatorBuilder.ControllerPath)
                                        ?? CharacterAnimatorBuilder.Build();

            EditorUtility.SetDirty(set);
            AssetDatabase.SaveAssets();
            return set;
        }

        internal static List<GameObject> Models(string folder)
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

        internal static GameObject Pick(List<GameObject> models, params string[] keywords)
        {
            foreach (var keyword in keywords)
                foreach (var model in models)
                    if (model.name.ToLowerInvariant() == keyword) return model;
            foreach (var keyword in keywords)
                foreach (var model in models)
                    if (model.name.ToLowerInvariant().Contains(keyword)) return model;
            return null;
        }

        internal static bool Matches(GameObject model, params string[] keywords)
        {
            var name = model.name.ToLowerInvariant();
            return keywords.Any(keyword => name.Contains(keyword));
        }

        internal static string ArtSummary()
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
        internal static GameObject Block(string name, GameObject parent, Vector3 center, Vector3 size, string material)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent.transform, false);
            root.transform.position = center;
            root.AddComponent<BoxCollider>().size = size;
            VisualCube("Visual", root.transform, Vector3.zero, size, material);
            return root;
        }

        /// <summary>Vehicle: root at ground level, box collider for NavMesh/taps, model or placeholder visual.</summary>
        internal static GameObject Vehicle(string name, GameObject parent, Vector3 groundPosition, float yaw, Vector3 size, string material, GameObject model, bool withCabin)
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
        internal static GameObject Character(string name, Vector3 feet, float yaw, string material, GameObject model)
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

        internal static void BuildBackdrop()
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

        internal enum FitMode { Height, Length }

        /// <summary>Instantiate a model under parent, scale it to fit, center it, and stand it on the parent's ground level.</summary>
        internal static GameObject PlaceModel(GameObject model, Transform parent, Vector3 target, FitMode mode, float yawOffset)
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

        internal static bool TryGetBounds(GameObject go, out Bounds bounds)
        {
            bounds = default;
            var renderers = go.GetComponentsInChildren<Renderer>();
            if (renderers.Length == 0) return false;
            bounds = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++) bounds.Encapsulate(renderers[i].bounds);
            return true;
        }

        internal static GameObject VisualCube(string name, Transform parent, Vector3 localPosition, Vector3 size, string material)
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

        internal static void Hotspot(GameObject target, string displayName, string look, string use, string talk, Transform standPoint)
        {
            var hotspot = target.AddComponent<EMPEscape.Hotspot>();
            hotspot.displayName = displayName;
            hotspot.lookKnot = look;
            hotspot.useKnot = use;
            hotspot.talkKnot = talk;
            hotspot.standPoint = standPoint;
        }

        internal static Transform StandPoint(Transform parent, string name, Vector3 position)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.position = position;
            return t;
        }

        internal static Transform Anchor(Transform parent, string name, Vector3 position, Vector3 lookAt)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.position = position;
            t.LookAt(lookAt);
            return t;
        }

        internal static void Zone(string name, Vector3 center, Vector3 size, Transform anchor)
        {
            var go = new GameObject(name);
            go.transform.position = center;
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = size;
            go.AddComponent<EMPEscape.CameraZone>().cameraAnchor = anchor;
        }

        internal static void SetupLighting()
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

        internal static void CacheLitShader()
        {
            var probe = GameObject.CreatePrimitive(PrimitiveType.Cube);
            litShader = probe.GetComponent<Renderer>().sharedMaterial.shader;
            Object.DestroyImmediate(probe);
        }

        internal static Material Mat(string name)
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

        internal static Color Palette(string name)
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
                case "Steel": return new Color(0.75f, 0.77f, 0.8f);
                case "Grip": return new Color(0.12f, 0.1f, 0.09f);
                case "Wood": return new Color(0.55f, 0.38f, 0.22f);
                case "Gunmetal": return new Color(0.16f, 0.17f, 0.19f);
                case "Target": return new Color(0.9f, 0.85f, 0.7f);
                case "Ground": return new Color(0.36f, 0.34f, 0.3f);
                case "Fence": return new Color(0.45f, 0.42f, 0.38f);
                case "Board": return new Color(0.25f, 0.32f, 0.28f);
                case "Burlap": return new Color(0.66f, 0.56f, 0.4f);
                case "StrangerRed": return new Color(0.5f, 0.12f, 0.1f);
                case "SolarBlue": return new Color(0.1f, 0.16f, 0.32f);
                case "ShedDark": return new Color(0.1f, 0.09f, 0.08f);
                case "Rust": return new Color(0.4f, 0.22f, 0.12f);
                case "Flame": return new Color(1f, 0.55f, 0.15f);
                case "Cloth": return new Color(0.2f, 0.22f, 0.2f);
                default: return Color.magenta;
            }
        }

        internal static void EnsureFolder(string path)
        {
            if (AssetDatabase.IsValidFolder(path)) return;
            var parent = System.IO.Path.GetDirectoryName(path).Replace('\\', '/');
            EnsureFolder(parent);
            AssetDatabase.CreateFolder(parent, System.IO.Path.GetFileName(path));
        }

        internal static void AddToBuildSettings(string scenePath)
        {
            var scenes = new List<EditorBuildSettingsScene>(EditorBuildSettings.scenes);
            scenes.RemoveAll(s => s.path == scenePath);
            scenes.Insert(0, new EditorBuildSettingsScene(scenePath, true));
            EditorBuildSettings.scenes = scenes.ToArray();
        }
    }
}
