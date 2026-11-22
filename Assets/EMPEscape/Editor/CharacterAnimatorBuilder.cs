using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Menu: EMP Escape > Build Character Animator.
    /// Builds Assets/EMPEscape/Art/EMPCharacter.controller from the clips in Art/Animations, matched by file name:
    /// idle (required), walk, talk, and one-shots flinch, swing, shoot. Clips are matched by file or clip name
    /// (see Roles), so multi-clip libraries work too. Parameters: Speed (float), Talking (bool), and one trigger
    /// per one-shot that has a clip (Flinch, Swing, Shoot); CharacterActor.Play("swing") fires them.
    /// Re-run after adding clips. It overwrites the controller.
    /// </summary>
    public static class CharacterAnimatorBuilder
    {
        public const string ControllerPath = "Assets/EMPEscape/Art/EMPCharacter.controller";
        const string AnimationsFolder = "Assets/EMPEscape/Art/Animations";
        // Role -> words that identify a clip by its file name or clip name (first match wins).
        static readonly (string role, string[] words)[] Roles =
        {
            ("idle", new[] { "idle" }),
            ("walk", new[] { "walk" }),
            ("talk", new[] { "talk", "conversation", "chat" }),
            ("flinch", new[] { "flinch", "hit", "react" }),
            ("swing", new[] { "swing", "slash", "stab", "melee", "punch", "attack" }),
            ("shoot", new[] { "shoot", "shooting", "fire", "pistol" }),
        };

        // Played from any state, then back to Idle. Trigger and state are the role capitalized.
        static readonly string[] OneShots = { "flinch", "swing", "shoot" };

        [MenuItem("EMP Escape/Build Character Animator")]
        static void BuildFromMenu()
        {
            var controller = Build();
            if (controller == null)
            {
                EditorUtility.DisplayDialog("EMP Escape",
                    "No idle animation found in " + AnimationsFolder + ".\n\nPut your Mixamo FBX files there with idle, walk, talk, flinch, swing and shoot in their file names, then run this again.",
                    "OK");
                return;
            }
            Selection.activeObject = controller;
            Debug.Log("[EMP Escape] Character animator built at " + ControllerPath + ". Re-run Build Test Slice Scene to apply it.");
        }

        public static AnimatorController Build()
        {
            var clips = FindClips();
            if (!clips.TryGetValue("idle", out var idleClip)) return null;

            if (AssetDatabase.LoadAssetAtPath<Object>(ControllerPath) != null) AssetDatabase.DeleteAsset(ControllerPath);
            var controller = AnimatorController.CreateAnimatorControllerAtPath(ControllerPath);
            controller.AddParameter("Speed", AnimatorControllerParameterType.Float);
            controller.AddParameter("Talking", AnimatorControllerParameterType.Bool);

            var machine = controller.layers[0].stateMachine;
            var idle = machine.AddState("Idle");
            idle.motion = idleClip;
            machine.defaultState = idle;

            if (clips.TryGetValue("walk", out var walkClip))
            {
                var walk = machine.AddState("Walk");
                walk.motion = walkClip;
                Link(idle, walk, 0.15f).AddCondition(AnimatorConditionMode.Greater, 0.1f, "Speed");
                Link(walk, idle, 0.2f).AddCondition(AnimatorConditionMode.Less, 0.1f, "Speed");
            }

            if (clips.TryGetValue("talk", out var talkClip))
            {
                var talk = machine.AddState("Talk");
                talk.motion = talkClip;
                Link(idle, talk, 0.25f).AddCondition(AnimatorConditionMode.If, 0f, "Talking");
                Link(talk, idle, 0.3f).AddCondition(AnimatorConditionMode.IfNot, 0f, "Talking");
                Link(talk, idle, 0.15f).AddCondition(AnimatorConditionMode.Greater, 0.1f, "Speed");
            }

            foreach (var role in OneShots)
            {
                if (!clips.TryGetValue(role, out var clip)) continue;
                var name = char.ToUpperInvariant(role[0]) + role.Substring(1);
                controller.AddParameter(name, AnimatorControllerParameterType.Trigger);
                var state = machine.AddState(name);
                state.motion = clip;
                var enter = machine.AddAnyStateTransition(state);
                enter.hasExitTime = false;
                enter.duration = 0.06f;
                enter.canTransitionToSelf = false;
                enter.AddCondition(AnimatorConditionMode.If, 0f, name);
                var back = state.AddTransition(idle);
                back.hasExitTime = true;
                back.exitTime = 0.9f;
                back.duration = 0.2f;
            }

            AssetDatabase.SaveAssets();
            return controller;
        }

        static AnimatorStateTransition Link(AnimatorState from, AnimatorState to, float duration)
        {
            var transition = from.AddTransition(to);
            transition.hasExitTime = false;
            transition.duration = duration;
            return transition;
        }

        static Dictionary<string, AnimationClip> FindClips()
        {
            var found = new Dictionary<string, AnimationClip>();
            if (!AssetDatabase.IsValidFolder(AnimationsFolder)) return found;

            var paths = new List<string>();
            foreach (var guid in AssetDatabase.FindAssets("t:AnimationClip", new[] { AnimationsFolder }))
                paths.Add(AssetDatabase.GUIDToAssetPath(guid));
            paths.Sort();

            foreach (var path in paths)
            {
                var fileName = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
                foreach (var asset in AssetDatabase.LoadAllAssetsAtPath(path))
                {
                    if (!(asset is AnimationClip clip) || clip.name.StartsWith("__preview__")) continue;
                    var clipName = clip.name.ToLowerInvariant();
                    foreach (var (role, words) in Roles)
                    {
                        if (found.ContainsKey(role)) continue;
                        if (System.Array.Exists(words, w => clipName.Contains(w) || fileName.Contains(w))) { found[role] = clip; break; }
                    }
                }
            }
            return found;
        }
    }
}
